# Sprint 4.1 — Mosh Transport: Technical Plan

> **Revision 2** — Incorporates architectural feedback, narrows the decision tree, and elevates the rendering-model problem to the primary concern.

---

## 0. The Core Problem

This is not "just another transport implementation." The hard part of Mosh integration is not the protocol, the crypto, or the UDP socket. It is the **rendering model mismatch**.

- **SSH** gives a raw VT100 byte stream. SwiftTerm parses it into a terminal grid and renders it.
- **Mosh** gives synchronized terminal state — a 2D character grid with diffs. There is no raw byte stream to parse.

Everything else — crypto, protobuf, UDP, lifecycle — is secondary to this question:

**What is the client-side rendering contract for a Mosh session in an app whose terminal widget expects VT100 byte streams?**

If that answer is messy, fragile, or slow, the product experience will feel hacked together no matter how correct the protocol layer is. This document is organized accordingly: rendering first, then protocol, then implementation.

---

## 1. What Mosh Is and Why It Matters for Roam

Mosh (Mobile Shell) replaces SSH's TCP byte-stream with a **UDP-based State Synchronization Protocol (SSP)**. Instead of streaming every byte, Mosh sends diffs of the current terminal screen state. This gives:

- **Roaming**: Sessions survive IP changes (Wi-Fi → cellular → new Wi-Fi)
- **Resilience**: Lost packets don't kill the session; the next state update just overwrites
- **Predictive echo**: Client speculatively renders keystrokes locally, correcting when the server responds
- **Low latency**: Median keystroke latency <5ms on high-RTT links vs 500ms+ for SSH

For an iOS SSH client where the user constantly switches between Wi-Fi and cellular, backgrounds the app, etc., Mosh is a significant UX improvement for interactive terminal work.

**Critical constraint**: SSH remains required alongside Mosh. Mosh only replaces the terminal interactivity stream. SFTP, port forwarding, helper RPC, bootstrap, host auth, and trust flows all go through SSH. If anyone on the project starts drifting toward "Mosh as session substrate for everything," they are wasting time.

---

## 2. The Rendering Decision (Primary Architectural Question)

### 2.1 The Problem

**How Mosh renders today**: The Mosh server runs its own terminal emulator (`terminal.cc`). It processes the shell's VT100 output into a 2D character grid (rows x cols, each cell = character + attributes). The SSP sends **diffs of this grid** to the client. The client applies diffs to its local copy of the grid, then renders it to the screen.

**How Roam renders today**: SSH pipes raw VT100 bytes → SwiftTerm parses them → SwiftTerm maintains its own internal grid → SwiftTerm renders to screen.

**The mismatch**: We receive grid diffs from Mosh, but SwiftTerm expects raw VT100 bytes. We must choose how to bridge this.

### 2.2 Rendering Options

#### R1: Grid Diff → Synthesized VT100 → SwiftTerm

- Receive Mosh grid diffs, apply to local grid copy
- Generate VT100 escape sequences that would produce the same visual result
- Feed those into SwiftTerm via `terminal.feed()`
- Essentially: `grid_diff → cursor_moves + character_writes → VT100 bytes`

**Pro**: Minimal changes to SwiftTerm integration. Quick to prototype.
**Con**: Inherently wasteful — grid → VT100 → grid again inside SwiftTerm. Fidelity risk at the VT100 synthesis layer (attributes, cursor state, scroll regions must all round-trip correctly).

#### R2: Direct SwiftTerm Buffer Write

- Bypass SwiftTerm's VT100 parser entirely
- Write directly to SwiftTerm's `Terminal` buffer (its internal grid)
- SwiftTerm's `Terminal` class has methods like `setCursor`, `setCharacter`, etc.

**Pro**: Most efficient, no double-processing.
**Con**: Tight coupling to SwiftTerm internals. Fragile across SwiftTerm updates. Requires deep knowledge of SwiftTerm's buffer model. Every SwiftTerm upgrade becomes a potential breaking change.

#### R3: Custom Renderer for Mosh Sessions

- Use a custom `UIView` subview that directly displays the Mosh character grid
- Renders 2D attributed text grid natively

**Pro**: Perfect fidelity, no conversion overhead.
**Con**: Lose all SwiftTerm features — selection, scrollback, URL detection, text search. Two completely different terminal renderers to maintain. UX inconsistency between SSH and Mosh sessions.

#### R4: Unified Internal Terminal-State Model (Recommended Long-Term Target)

Instead of treating SwiftTerm as the only terminal truth, define an app-owned **session-side terminal-state abstraction**:

- SSH path feeds VT100 into parser → **internal grid model**
- Mosh path feeds SSP updates into → **internal grid model**
- UI renders from **internal grid model** (SwiftTerm or custom view becomes a downstream consumer)

```
SSH Shell Channel ──→ VT100 Parser ──→┐
                                       ├──→ InternalTerminalGrid ──→ TerminalRenderer (UI)
Mosh SSP Updates ─────────────────────┘
```

**Pro**: SSH and Mosh become true siblings instead of incompatible hacks. No grid→VT100→grid round-trips. No poking SwiftTerm internals. Clean ownership boundary.
**Con**: Largest upfront investment. Requires either forking SwiftTerm or building a new renderer. Not appropriate for a v1 prototype.

### 2.3 Recommended Rendering Strategy

**Prototype with R1** to validate protocol correctness and UX. R1 is the lowest-risk path to a working Mosh session, even if the architecture is wasteful.

**Plan for R4** as the long-term target if Mosh proves worth keeping. The internal grid model makes SSH and Mosh first-class peers and eliminates the conversion hacks. This is the architecturally correct end state, but it's a significant investment that should be gated on Mosh actually delivering user value in the R1 prototype.

**Avoid R2** — it creates permanent coupling to SwiftTerm internals with no clean upgrade path.

**Avoid R3** — maintaining two terminal renderers is unsustainable and creates UX inconsistency.

---

## 3. How Mosh Works (Reference)

### 3.1 Connection Flow

```
Phase 1: SSH Bootstrap
  Client SSHes into remote → runs `mosh-server new -c 256 -l LANG=en_US.UTF-8`
  Server outputs: MOSH CONNECT <udp_port> <base64_aes_key>
  SSH connection can close (but Roam keeps it for SFTP/helper/forwards).

Phase 2: UDP Session
  Client opens UDP socket to server:<udp_port>
  All traffic encrypted with AES-128-OCB using the shared key
  SSP begins: bidirectional state sync
    Client → Server: UserInput (keystrokes, TCP-like reliable delivery)
    Server → Client: HostOutput (current screen state, diff-based)

Phase 3: Steady State
  Heartbeat every 3 seconds minimum
  Server updates client source IP on any authenticated packet with higher sequence number
  → automatic roaming, no reconnection needed
```

### 3.2 Mosh Source Code Structure

```
mosh/src/
├── frontend/       # mosh-client.cc, mosh-server.cc (entry points)
├── network/        # UDP transport, datagram encrypt/decrypt
├── statesync/      # SSP protocol: Transport, Sender, Receiver → state diffing
├── crypto/         # AES-128-OCB implementation (crypto.cc, ocb.cc)
├── terminal/       # Terminal emulator (terminal.cc) — server-side only
├── protobufs/      # .proto definitions for UserInput and HostOutput
└── util/           # Timestamps, helpers
```

### 3.3 What the Client Actually Needs

Only these layers:
1. **crypto/** — AES-128-OCB encrypt/decrypt
2. **network/** — UDP datagram framing, sequence numbers, nonces
3. **statesync/** — SSP state machine, diff application
4. **protobufs/** — Compiled protobuf message types

We do **not** need: `terminal/` (our app does rendering), `frontend/mosh-server.cc` (runs on remote), ncurses, libutempter.

### 3.4 Dependencies

| Dependency | Purpose | Required? |
|---|---|---|
| protobuf | Serialize SSP messages | Yes |
| AES-128-OCB | Authenticated encryption | Yes |
| ncurses | Terminal rendering | **No** — we use SwiftTerm |
| libutempter | PTY login records | **No** — server only |
| zlib | Compression | Optional |

---

## 4. Integration Architecture with Roam

### 4.1 Where Mosh Fits

```
┌─────────────────────────────────────┐
│ SessionView (SwiftUI)               │
│   └── TerminalViewRepresentable     │
│         └── bridge: any TerminalSessionBridgeProtocol
│                          │
│              ┌───────────┴───────────┐
│              │ SSH path              │ Mosh path
│              │ TerminalSessionBridge │ MoshSessionBridge
│              │   └── ShellChannel    │   └── MoshTransport (UDP)
│              │       (TCP/SSH)       │       + SSP state machine
│              └───────────────────────┘
│                                      │
│ SSH session stays alive for:         │
│   - SFTP, helper RPC, port forwards │
└─────────────────────────────────────┘
```

### 4.2 The Protocol Bridge

`TerminalSessionBridgeProtocol` defines the interface:

```swift
protocol TerminalSessionBridgeProtocol: AnyObject {
    var sessionID: String { get }
    var connectionState: SSHSessionState { get }
    func sendToRemote(_ data: Data) async throws      // user keystrokes
    func remoteDataStream() -> AsyncThrowingStream<Data, Error>  // terminal output
    func resizePTY(columns: Int, rows: Int) async throws
    func disconnect() async
}
```

For SSH: `sendToRemote` writes to the shell channel, `remoteDataStream` reads from it. Straightforward byte-stream pass-through.

For Mosh: `sendToRemote` feeds keystrokes into SSP's UserInput → encrypted → UDP send. `remoteDataStream` yields terminal output — but the semantics differ fundamentally:
- **SSH**: raw byte stream, order matters, every byte is significant
- **Mosh**: state snapshots with diffs, idempotent, can skip frames

Under R1 rendering, `remoteDataStream` would yield synthesized VT100 bytes from the grid diffs. Under R4, `remoteDataStream` would yield structured grid updates instead of raw bytes, requiring a different consumer.

---

## 5. The Real Decision Tree

The previous revision presented A, B, C1, C2, C3, D as an equal menu. They are not. The real strategic choice collapses to **three buckets**:

### Bucket 1: Ship-Fast Legacy Reuse

Vendor/fork real Mosh C++ code. Compile it for iOS. Wrap in a thin Swift layer.

This includes both "Approach A" (vendor into SPM) and "Approach B" (prebuilt xcframework). The distinction between A and B is a packaging tactic, not an architecture — both are "use Mosh's C++ implementation."

**When this makes sense**: You want Mosh in users' hands as fast as possible and are willing to carry C++ maintenance debt.

**Why it might be a decoy**: GPL-3 contamination risk, C++ build fragility in SPM, debugging is painful, and you inherit Mosh's design decisions (including its terminal emulator model) rather than owning the integration.

**Verdict**: Only worth it as an **explicit tactical bridge** with a planned migration path. Do not treat this as the target architecture.

### Bucket 2: Clean Architecture (Recommended)

Reimplement client-side Mosh in Rust and Swift, without using any Mosh C++ code.

The recommended shape is **C3: Hybrid Rust + Swift**:
- **Rust** handles: SSP state machine, AES-128-OCB crypto, protobuf parsing, protocol correctness, deterministic tests
- **Swift** handles: NWConnection UDP socket, iOS lifecycle/backgrounding, session coordination, terminal UI, workspace integration

```
                    ┌────────────────────────────────────────────────┐
                    │              Rust (roam-mosh crate)            │
                    │                                                │
 Swift UDP recv ──→ │ process_incoming_datagram(bytes)               │
                    │   → decrypt (AES-128-OCB)                     │
                    │   → decode (protobuf HostOutput)              │
                    │   → apply SSP diff to terminal grid           │
                    │   → return TerminalUpdate { grid_changes }    │ ──→ Swift rendering
                    │                                                │
 Swift keystroke ──→│ encode_keystroke(key)                          │
                    │   → encode (protobuf UserInput)               │
                    │   → encrypt (AES-128-OCB)                     │
                    │   → return EncryptedDatagram                  │ ──→ Swift UDP send
                    │                                                │
                    └────────────────────────────────────────────────┘
```

**Why this is the best long-term architecture**:
- Avoids C++ and GPL contamination risk entirely
- Rust handles the protocol-heavy, stateful, correctness-sensitive parts
- Swift owns iOS-native networking, lifecycle, and UI
- Aligns with the existing "Rust helper on host" worldview
- Deterministic Rust unit tests for protocol correctness
- Low maintenance burden — no C++ in SPM, no xcframework rebuilds

**What "pure Swift" (C1) gets wrong**: Build complexity is lower, but engineering risk is not. A pure Swift implementation means you own protocol interpretation, crypto correctness, UDP lifecycle, terminal-state mapping, predictive echo, and all edge-case debugging — all in a language without Rust's type system advantages for this kind of correctness-sensitive code. Pure Swift should only be chosen if you deliberately want zero FFI and maximum Xcode-native debugging, not because it looks "simpler."

**What "pure Rust" (C2) gets wrong**: Fighting iOS lifecycle from Rust via FFI is painful. NWConnection path monitoring, background task management, and UIKit integration should stay in Swift. Don't make Rust fight the platform.

### Bucket 3: Don't Do Mosh Yet

Stick to SSH + tmux reconnect. Invest in:
- Excellent SSH with aggressive reconnect
- Excellent workspace resume (already mostly built)
- tmux-native restore
- Autosave session semantics

This gets a surprising amount of the practical user value. Not the latency and roaming elegance of Mosh, but enough to avoid derailing the core product.

**When this is the right call**: If the rendering path becomes too invasive, protocol correctness stalls, terminal fidelity is visibly worse than SSH in real workflows, or build/legal overhead becomes disproportionate.

---

## 6. AES-128-OCB: The Crypto Question

OCB (Offset Codebook Mode) is an authenticated encryption mode. It's the single most important crypto primitive for Mosh, and it's the one Apple doesn't provide.

| Platform | AES-128-OCB Support |
|---|---|
| OpenSSL 1.1+ | Yes (`EVP_aes_128_ocb`) |
| Apple CryptoKit | **No** — only GCM, not OCB |
| Apple CommonCrypto | **No** — only CBC, CTR, GCM |
| Rust `aes` + `ocb3` crates | **Yes** — pure Rust, audited |
| Mosh source `ocb.cc` | Yes — self-contained ~600 lines |
| libsodium | **No** |

**For the Rust hybrid approach**: The `ocb3` crate from RustCrypto is the obvious choice. Well-maintained, pure Rust, no system dependencies, implements RFC 7253. This is not a hard problem in Rust.

---

## 7. Protobuf: The Serialization Question

Mosh's SSP messages are serialized with Protocol Buffers. The schemas are small (~3-4 message types: UserInput, HostOutput, Instruction).

**For the Rust hybrid approach**: Use the `prost` crate. Compile `.proto` files to Rust structs at build time. This is standard Rust protobuf workflow and adds minimal complexity.

---

## 8. UDP on iOS: The Network Question

### NWConnection (Network.framework) — Use This

```swift
let connection = NWConnection(
    host: NWEndpoint.Host(serverIP),
    port: NWEndpoint.Port(rawValue: udpPort)!,
    using: .udp
)
connection.start(queue: .main)
connection.send(content: encryptedDatagram, completion: .contentProcessed { ... })
connection.receiveMessage { data, _, _, error in ... }
```

NWConnection is the right choice for iOS-facing UDP. The lifecycle and path-change awareness matter more than theoretical purity. Use it unless a hard blocker appears.

### Background Behavior

"Freeze in background, recover on foreground" is completely acceptable for v1. Chasing VoIP entitlement behavior this early is a waste of time and likely not App Store-friendly anyway.

- No special entitlement needed for foreground UDP
- When app backgrounds: iOS suspends after ~30 seconds
- Mosh handles this gracefully — server keeps running, client catches up on foreground
- Can use `beginBackgroundTask()` to briefly extend background time
- Mosh's SSP is designed for exactly this: reconnecting after arbitrary pauses

---

## 9. Predictive Echo

Mosh's predictive echo renders keystrokes locally before the server confirms them, making typing feel instant on high-latency connections.

**For v1: Skip it.** But be honest about what that means.

Technically, yes, the session will work without predictive echo. But product-wise, once you say "Mosh support," users mentally include roaming, resilience, **and** the predictive feel. If you omit predictive echo, you still have something valuable (roaming + resilience), but it will feel like "partial Mosh" rather than the full experience.

**Do not pretend that skipping predictive echo means "Mosh is basically done."** Plan it for v2, and communicate the scope clearly.

v1 must-haves:
- Stable bootstrap (SSH → mosh-server → UDP handshake)
- UDP session with encrypted SSP
- Roaming (automatic, inherent to the protocol)
- Resize
- Acceptable rendering fidelity

v2 additions:
- Predictive echo
- Custom port ranges
- Locale/encoding negotiation

---

## 10. GPL-3 Licensing

**This question should be answered immediately, because it can eliminate half the decision tree.**

Mosh is GPL-3. Blink's fork is GPL-3. If Roam's intended licensing or business model is not GPL-compatible, then Bucket 1 (vendor/fork C++ approaches A and B) is **strategically toxic**, not just "something to evaluate."

A clean-room reimplementation (Bucket 2) eliminates this concern entirely. The Rust `ocb3` and `prost` crates are MIT/Apache-2.0. No GPL code touches the binary.

**This is not a technical question — it's a business question that should be resolved before any implementation begins.**

---

## 11. Terminal Fidelity Requirements

A "mostly works" terminal integration will fail on exactly the cases users care about. The following must be verified against real-world usage:

### Must Handle Correctly

- Alternate screen apps (`vim`, `htop`, `less`, `tmux`)
- ncurses/TUI behavior (curses-based UIs with complex layouts)
- Unicode width (CJK characters, combining characters, emoji — `wcwidth` correctness)
- Scroll regions (partial screen scrolling, common in tmux splits)
- Cursor style and state (block, underline, bar, blink, hidden)
- Bracketed paste mode
- True color (24-bit SGR attributes)
- Wide characters spanning cell boundaries
- Terminal bell / visual bell

### Should Handle (v1 if feasible)

- Mouse reporting (SGR mouse mode, important for tmux and vim)
- Focus events (terminal focus in/out notifications)
- Title setting (OSC sequences for window titles)
- Clipboard integration (OSC 52)

### Known Danger Zones

These are exactly where "mostly works" terminal integrations go to die:
- tmux inside Mosh (nested state synchronization)
- Remote shell inside tmux inside Mosh
- Resize storms (rapid window size changes)
- Paste bursts (large clipboard paste operations)
- Long-lived idle sessions (reconnection after hours/days)

---

## 12. Verification Test Matrix

Without explicit verification targets, the plan is too implementation-centric. These must all pass before Mosh is considered shippable:

### Network Conditions

| Scenario | Expected Behavior |
|---|---|
| Local LAN (<1ms RTT) | Indistinguishable from SSH |
| High RTT (200-500ms) | Usable, roaming works |
| Packet loss (5-10%) | Session remains stable, minor visual lag |
| Wi-Fi → LTE handoff | Session recovers within 1-2 heartbeat cycles |
| LTE → Wi-Fi handoff | Same as above |
| Background 30s → foreground | Session catches up, no data loss |
| Background 5min → foreground | Session catches up, may take 1-2s |
| Background 1hr → foreground | Session recovers or shows clear reconnecting state |

### Terminal Correctness

| Scenario | Expected Behavior |
|---|---|
| `vim` open/close | Alternate screen enters/exits cleanly |
| `htop` running | Full-screen TUI renders correctly |
| `tmux` split panes | Scroll regions and splits correct |
| `man` page scroll | Scrolling and alternate screen correct |
| Unicode: `echo "日本語"` | CJK characters render at correct width |
| Unicode: emoji | Emoji render, don't corrupt grid |
| Paste 10KB text | All text arrives, no corruption |
| Paste 100KB text | Completes (may be slow), no corruption |
| Rapid resize | Grid reflows correctly |
| 24-bit color (`printf '\e[38;2;...m'`) | Colors render correctly |

### Lifecycle

| Scenario | Expected Behavior |
|---|---|
| Mosh transport selected, mosh-server absent | Graceful fallback to SSH |
| Mosh session + SFTP browse simultaneously | Both work independently |
| Mosh session + helper RPC call | SSH channel handles RPC, Mosh handles terminal |
| Network completely lost | Session shows "disconnected" overlay, recovers on reconnect |
| Server reboots | Session detects loss, offers reconnect |

---

## 13. Go/No-Go Criteria

The team should decide in advance when to abandon native Mosh and fall back to Bucket 3 (SSH + tmux). **Mosh must not eat the core app.**

**Abandon native Mosh if any of the following occur:**

1. **Rendering path becomes too invasive** — R1 prototype requires more than ~500 lines of VT100 synthesis code, or synthesis fidelity issues appear in >5% of test-matrix scenarios
2. **Protocol correctness stalls** — After 2 weeks of implementation, basic terminal output is still unreliable (garbled screens, stuck states, incorrect diff application)
3. **Terminal fidelity is visibly worse than SSH** — Users can see the difference between SSH and Mosh sessions in normal workflows (not just edge cases)
4. **Build/legal overhead becomes disproportionate** — FFI layer is more complex than the protocol itself, or licensing questions remain unresolved
5. **Performance regression** — Mosh sessions use >2x the CPU or memory of equivalent SSH sessions

If any of these triggers fire, stop Mosh work, ship the SSH + tmux reconnect path as the resilience story, and revisit Mosh in a future cycle.

---

## 14. Comparative Summary

| Factor | Bucket 1: Vendor C++ | Bucket 2: Rust+Swift Hybrid (C3) | Bucket 3: Skip Mosh |
|---|---|---|---|
| Protocol correctness | Proven | Must validate | N/A |
| Build complexity | High (C++ in SPM) | Medium (Rust FFI) | None |
| Maintenance burden | High | Low | None |
| Debugging | Hard (C++) | Medium (Rust tests + Swift UI) | N/A |
| Binary size impact | ~2-3 MB | ~500 KB | 0 |
| AES-128-OCB | Mosh's ocb.cc | Rust `ocb3` crate | N/A |
| Protobuf | Vendored C++ | Rust `prost` crate | N/A |
| iOS network integration | Needs BSD→NWConnection rewrite | Native (Swift owns NWConnection) | N/A |
| License risk | **GPL-3** | None (MIT/Apache-2.0) | None |
| Predictive echo | Free (included) | Must implement in v2 | N/A |
| Time to v1 | 1-3 weeks | 2-3 weeks | 0 |
| Long-term architecture | Debt | Clean | N/A |

---

## 15. Minimum De-Risk Prototype

Before committing to a full Mosh implementation, build a **one-week prototype** to de-risk the rendering mismatch:

### Week 1 Prototype Scope

1. **Rust crate** (`roam-mosh`): Hardcoded AES-128-OCB decrypt of a captured Mosh datagram. Parse protobuf HostOutput. Extract terminal grid state from SSP diff. Return as a flat `Vec<CellUpdate>`.

2. **Swift test harness**: Connect to a real `mosh-server` via SSH bootstrap. Open NWConnection UDP socket. Receive one HostOutput frame. Pass bytes through Rust FFI. Get back grid updates. Render them via R1 (synthesize VT100 → feed to SwiftTerm).

3. **Verify**: Does a basic `ls` command render correctly in the prototype? Does `vim` opening an alternate screen work? Does a resize produce correct output?

If the prototype renders correctly for these three cases, proceed with full implementation. If it doesn't, the rendering mismatch is worse than expected — evaluate whether to invest in R4 or fall back to Bucket 3.

### What the Prototype Answers

- Is R1 (grid→VT100→SwiftTerm) viable as a v1 strategy?
- How much VT100 synthesis complexity is needed for real-world terminal output?
- Does the Rust FFI layer add meaningful latency?
- Are there fundamental fidelity problems in the grid→VT100 round-trip?

---

## 16. Implementation Plan (Assuming C3 Hybrid + R1 Rendering)

### Phase A: Rust Mosh Crate (roam-mosh)

New Rust crate in the `roam-rs` workspace:

```
roam-rs/
├── Cargo.toml                    # workspace: helper, sync-server, mosh
├── mosh/
│   ├── Cargo.toml                # deps: ocb3, prost, prost-build
│   ├── build.rs                  # prost protobuf compilation
│   ├── proto/
│   │   ├── userinput.proto       # from Mosh source (schema only, no code)
│   │   └── hostoutput.proto
│   └── src/
│       ├── lib.rs
│       ├── crypto.rs             # AES-128-OCB encrypt/decrypt
│       ├── transport.rs          # Datagram framing, sequence numbers
│       ├── ssp.rs                # SSP state machine, diff application
│       ├── grid.rs               # Terminal grid model (cells, attributes)
│       ├── vt_synth.rs           # R1: grid diff → VT100 byte synthesis
│       └── ffi.rs                # C FFI for Swift interop
```

FFI surface (exposed as C functions for Swift):

```rust
// Create a new Mosh session state
pub extern "C" fn mosh_session_new(key: *const u8, key_len: usize) -> *mut MoshSession

// Process an incoming encrypted datagram, returns VT100 bytes to feed to terminal
pub extern "C" fn mosh_process_datagram(
    session: *mut MoshSession,
    data: *const u8, data_len: usize,
    out_vt: *mut u8, out_vt_capacity: usize,
    out_vt_len: *mut usize,
) -> i32

// Encode a keystroke into an encrypted datagram
pub extern "C" fn mosh_encode_keystroke(
    session: *mut MoshSession,
    key: *const u8, key_len: usize,
    out_dgram: *mut u8, out_dgram_capacity: usize,
    out_dgram_len: *mut usize,
) -> i32

// Notify of terminal resize
pub extern "C" fn mosh_resize(session: *mut MoshSession, cols: u16, rows: u16) -> i32

// Free session
pub extern "C" fn mosh_session_free(session: *mut MoshSession)
```

### Phase B: Swift Integration

New/modified Swift files:

- **`Packages/RoamMosh/`** — SPM package wrapping the Rust static library
  - `Package.swift` — C target (links `libroam_mosh.a`) + Swift target
  - `Sources/CMosh/include/mosh_ffi.h` — C header matching Rust FFI
  - `Sources/RoamMosh/MoshTransport.swift` — Swift wrapper around FFI
  - `Sources/RoamMosh/MoshSession.swift` — High-level session management

- **`Roam/SSHCore/MoshServerInitiator.swift`** — SSH exec `mosh-server`, parse `MOSH CONNECT`

- **`Roam/Terminal/TerminalBridge/MoshSessionBridge.swift`** — Implements `TerminalSessionBridgeProtocol`, routes terminal I/O through MoshTransport (UDP) instead of ShellChannel (SSH)

- **`Roam/Services/MoshReconnectService.swift`** — iOS background/foreground lifecycle for Mosh sessions

- **Modified**: `Host.swift` (transport enum), `SessionManager.swift` (bridge type → protocol), `WorkspaceResumeOrchestrator.swift` (Mosh path), `HostEditorView.swift` (transport picker), `SessionView.swift` (transport badge), `ConnectionSheet.swift` (Mosh status)

### Phase C: Testing and Polish

- Rust unit tests for crypto, transport, SSP, grid, VT synthesis
- Swift integration tests for MoshServerInitiator parsing
- Manual test matrix execution (Section 12)
- Fallback behavior: detect missing mosh-server, fall back to SSH gracefully
- UI: transport badge, connection status for Mosh sessions

---

## 17. Remaining Open Questions

The previous revision had 14 open questions. Most have been resolved by the architectural feedback. These remain:

### Must Answer Before Implementation

1. **GPL-3 compatibility**: Is Roam GPL-compatible? If not, Bucket 1 is dead. (This likely confirms C3 hybrid as the only viable path.)

2. **Rust → Swift FFI mechanism**: C headers + static library (simpler, proven in roam-rs helper) or UniFFI (more ergonomic, more build complexity)? The plan above assumes C FFI for consistency with the existing helper pattern.

3. **Minimum iOS version**: Does Roam target iOS 16+? (NWConnection UDP is available from iOS 12, so this is unlikely to be a blocker.)

### Can Decide During Implementation

4. **mosh-server auto-install**: Detect and explain first. Do not build auto-install flows over SSH in v1 — distro/package-manager complexity is high and the value is low.

5. **Custom port range support**: Nice to have for v1 but not blocking. Mosh servers default to 60001-60999.

6. **Internal terminal grid model (R4)**: Worth prototyping? Or defer until Mosh has proven its value? The recommendation is to defer — R1 is sufficient for v1, and R4 is a large investment that should be justified by real usage data.

---

## 18. What Would an Internal Terminal-State Abstraction Look Like?

> (Reference section for future R4 planning — not needed for v1)

If we wanted both SSH and Mosh to feed the same render model:

```swift
/// App-owned terminal state, independent of SwiftTerm or any renderer.
@Observable final class TerminalGrid: @unchecked Sendable {
    var columns: Int
    var rows: Int
    var cells: [[TerminalCell]]       // [row][col]
    var cursorPosition: (row: Int, col: Int)
    var cursorStyle: CursorStyle
    var scrollRegion: (top: Int, bottom: Int)
    var alternateScreenActive: Bool
    var scrollbackBuffer: [[TerminalCell]]

    // SSH path: VT100 parser writes here
    func applyVT100(_ data: Data) { ... }

    // Mosh path: SSP diff applies here
    func applyMoshDiff(_ update: MoshGridUpdate) { ... }

    // Renderer reads from here
    func snapshot() -> TerminalSnapshot { ... }
}

struct TerminalCell {
    var character: Character
    var foreground: TerminalColor
    var background: TerminalColor
    var attributes: CellAttributes  // bold, italic, underline, inverse, etc.
    var wide: Bool                  // CJK double-width
}
```

The renderer (whether SwiftTerm-based or custom) would subscribe to `TerminalGrid` changes and render accordingly. This decouples transport from rendering completely.

**Investment estimate**: ~2-3 weeks for the grid model + VT100 parser + renderer adapter. Significant, but provides a clean foundation for any future transport (Mosh, or anything else that doesn't speak raw VT100).

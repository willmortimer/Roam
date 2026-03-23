
# iOS Native Remote Workspace Client  
## Design Specification

**Status:** Draft v1  
**Document Type:** Product + Architecture Design Spec  
**Target Platform:** iOS / iPadOS only  
**Companion Component:** Optional Rust helper on remote Linux hosts  
**Working Description:** A Termius-class SSH client built specifically for persistent remote development workflows, tmux-native workspace resume, remote AI CLI usage, and one-tap web previews over SSH.

---

## 1. Executive Summary

This project is an open-source, iOS-native SSH client that starts from the proven baseline of products like Termius and then pushes much further in the direction that modern remote development actually needs.

Most SSH clients still model the world incorrectly. They treat a connection as a dumb terminal session plus some convenience features like saved hosts, key storage, SFTP, and port forwarding. That model was good enough when the unit of work was “log into a box and run commands.”

It is not good enough for the workflow people increasingly use now:

**connect to remote machine → attach tmux → enter project → run Codex / Claude Code / Aider / custom CLI → inspect diffs/tests/logs → preview app over tunnel → pull artifacts → disconnect → resume later from phone or tablet**

That means the real product is not “terminal app.” The real product is:

- a **Termius-class SSH client**
- plus a **workspace manager**
- plus **tmux-native orchestration**
- plus **intelligent SSH tunnel / preview handling**
- plus **structured views over remote work artifacts**
- plus an **optional remote helper** that makes all of that reliable

The client remains SSH-first and shell-first. It does **not** try to become a fake IDE. It does **not** try to embed the AI model. It does **not** require a hosted service. Codex and similar tools are simply remote CLI programs the user already runs on the host. The app's job is to make that workflow drastically smoother on iPhone and iPad.

---

## 2. Product Thesis

Build an **open-source remote workspace client for SSH-native AI development**.

The product should optimize for:

- iPhone and iPad as real remote work surfaces, not emergency viewers
- connecting to Linux hosts over SSH, with optional Mosh later
- resuming persistent remote workspaces instantly
- launching or reattaching to remote AI CLIs like Codex, Claude Code, Aider, or custom scripts
- inspecting output in a way better than raw scrollback alone
- opening and managing remote web previews through SSH without manual tunnel babysitting
- keeping secrets local-first and portable
- working fully standalone without any required cloud account
- remaining fully open source and export-friendly

The center of gravity is not “open-source Termius clone.” It is:

> **A native iOS remote workspace client for SSH-native development: hosts, tmux, tunnels, previews, files, and session state in one place.**

---

## 3. What We Are Stealing from Termius

Do not get cute here. The app should copy the baseline SSH client features that users already expect from a serious product.

### 3.1 Table-stakes features

The app should include:

- Saved hosts with aliases, metadata, tags, folders, and notes
- Jump hosts / chained SSH connections
- SSH key generation, import, export, and labeling
- Agent forwarding
- Known-hosts management and fingerprint trust flow
- SFTP browser with upload/download and basic file actions
- Saved local/remote/dynamic forwarding rules
- Snippets / command library
- Local vault for hosts, keys, snippets, forwarding rules, and known hosts
- Cross-device sync later
- Mobile UX that is genuinely usable
- Optional Mosh support later
- Team vaults and shared objects later

### 3.2 Areas where parity is not enough

Parity is not the goal. Baseline parity only gets the product to the starting line. The actual wedge is:

- **Workspaces** instead of only hosts
- **tmux-native session management**
- **one-tap remote AI CLI launch / attach**
- **zero-friction web previewing**
- **structured output lenses**
- **artifact-aware file movement**
- **mobile-first session ergonomics**

---

## 4. Product Goals

### 4.1 Primary goals

1. Make iPhone and iPad viable primary interfaces for remote dev and ops workflows.
2. Preserve the raw power of SSH and the terminal.
3. Add first-class workspace semantics above raw connections.
4. Make tmux feel native rather than bolted on.
5. Make remote AI CLI workflows feel substantially better than in a dumb terminal.
6. Make remote web previewing nearly one tap.
7. Keep all core functionality usable without any hosted service.
8. Design the system so the remote helper is optional, auditable, and unprivileged by default.

### 4.2 Secondary goals

1. Provide clean import/export and avoid lock-in.
2. Support secure local-only operation as the default.
3. Make file transfer and artifact retrieval part of the workspace flow.
4. Provide structured local observability of commands, tunnels, previews, and recent context.
5. Leave room for self-hosted sync and team features later without contaminating the core design.

---

## 5. Non-Goals

This product should **not** try to become:

- a desktop app
- a full IDE
- a hosted cloud dev environment
- a proprietary sync trap
- a special Codex-only shell
- a replacement for tmux
- a replacement for Git hosting
- a root-level remote management platform by default

The correct posture is:

- **terminal-first**
- **SSH-first**
- **workspace-aware**
- **mobile-native**
- **helper-enhanced when available**

---

## 6. User Profiles

### 6.1 Primary user

The primary user is someone who:

- has one or more Linux boxes, VMs, WSL hosts, or cloud instances
- already uses SSH regularly
- often uses tmux or is willing to
- increasingly runs remote AI CLIs inside repos
- wants to stay productive from iPhone or iPad
- cares about low-friction reconnect, previews, files, and tunnels
- does not want to hand private keys to a cloud service

### 6.2 Representative workflows

- Resume a dev session on a remote homelab box from an iPhone
- Reattach to a tmux workspace running Codex and a dev server
- Open a Next.js / Vite / FastAPI preview inside the app
- Pull down a generated patch, screenshot, or log bundle
- Run a saved snippet that reboots a workspace layout
- Jump through a bastion to a target host and attach to the right tmux session
- Review test failures from a structured panel instead of terminal scrollback

---

## 7. Product Principles

1. **SSH is the transport of truth.**  
   Everything important should work over SSH.

2. **The terminal remains first-class.**  
   Structured views are an enhancement, not a replacement.

3. **Workspaces are the product-level abstraction.**  
   Hosts are necessary but insufficient.

4. **tmux is the persistence substrate.**  
   Do not fight how serious users already maintain remote state.

5. **Remote AI tools are just remote CLIs.**  
   The app does not need to “embed” them. It needs to launch, recognize, and organize around them.

6. **The remote helper is optional.**  
   Plain SSH mode must still be useful.

7. **Local-first security matters.**  
   The user should not need an account to get serious value.

8. **Avoid fake IDE bloat.**  
   The UI should remain narrow, fast, and task-oriented.

---

## 8. Product Definition

The product has two components:

### 8.1 iOS application

A native Swift application for iPhone and iPad that provides:

- SSH terminal sessions
- host and key management
- SFTP
- port forwarding
- snippets
- workspace definitions
- tmux-aware resume UX
- preview browser
- local secure vault and metadata store
- optional helper negotiation and control

### 8.2 Optional remote Rust helper

A small Rust binary installed on the remote Linux host that provides richer, structured support for:

- workspace lifecycle
- tmux orchestration
- port and preview discovery
- process labeling
- artifact listing
- session summaries
- thin RPC over SSH stdio

The helper is not a separate internet-facing service and does not replace SSH. In its main mode, it is launched on demand over SSH and communicates over stdin/stdout.

---

## 9. Differentiators vs Existing SSH Clients

### 9.1 First-class workspaces

A workspace is a resumable remote context, not just a saved connection. It bundles:

- host or host chain
- repo path
- preferred shell
- tmux session name
- pane layout
- startup commands
- detected package manager
- forwarded ports
- preview rules
- preferred agent launch command
- notes, tags, and trust zone
- artifact and recent-session context

Examples:

- `prod-api-debug`
- `openseat-frontend-dev`
- `gpu-trainer-main`
- `wsl-codex-workbench`

The core action becomes **Resume Workspace**, not merely **Open Host**.

### 9.2 tmux-native control

The client assumes persistent remote work happens in tmux. It should support:

- listing tmux sessions
- attaching intelligently
- creating sessions from templates
- restoring panes from workspace config
- naming or semantically labeling panes
- capturing pane content for summary views
- sending commands to a specific pane
- quickly jumping among panes on mobile

### 9.3 One-tap remote AI CLI workflows

The app should make it trivial to:

- launch `codex` in the correct pane
- attach to an existing agent pane
- run `claude`, `aider`, or a custom command
- mark a pane as “Agent”
- surface likely diffs, tests, and previews related to that pane

This is **not** a required adapter architecture. It is primarily a launch and recognition model layered on top of ordinary remote processes.

### 9.4 Web previews over SSH without nonsense

The app should detect likely dev servers, propose or auto-create forwards, and open previews in-app. Users should not need to:

- manually create a forward every time
- copy localhost URLs around
- switch apps
- babysit reconnects
- manually rediscover which process owns which preview

### 9.5 Structured output lenses

The terminal remains the canonical view, but the app should add optional “lenses” over session state:

- terminal
- diffs
- tests
- logs
- ports and links
- command timeline
- errors only
- artifacts

### 9.6 Mobile ergonomics that actually matter

The app should be designed around the constraints and strengths of iOS:

- swipeable pane switching
- hardware keyboard shortcuts
- control row for Escape / Ctrl / Alt / Tab
- command bar
- snippet chips
- fuzzy host and workspace search
- compact session switching
- low-bandwidth rendering mode
- long-press actions on panes, ports, files, and branches

---

## 10. High-Level Architecture

The system has four logical layers on the device plus one optional remote component.

### 10.1 iOS app layers

#### Layer 1: Transport layer
Responsible for:

- SSH sessions
- PTY allocation
- exec channels
- SFTP subsystem
- local / remote / dynamic forwarding
- known_hosts and host verification
- key loading and signing
- optional Mosh later

#### Layer 2: Workspace runtime layer
Responsible for:

- workspace definitions
- session restore
- tmux attach/create flow
- snippet execution
- preview lifecycle
- helper negotiation
- local indexing of commands and artifacts

#### Layer 3: Interpretation layer
Responsible for:

- terminal stream parsing
- heuristic detection of ports and links
- diff / test / error extraction
- pane role inference
- command timeline assembly
- light tool-profile recognition

#### Layer 4: UI layer
Responsible for:

- terminal view
- hosts and workspaces screens
- key vault and known_hosts UX
- SFTP view
- preview browser
- structured panels
- onboarding, settings, sync, exports

### 10.2 Remote component

#### Rust helper
Responsible for:

- structured workspace commands
- tmux orchestration
- port/process discovery
- process labeling
- artifact enumeration
- optional session summary streaming
- stdio RPC inside the SSH connection

---

## 11. Technology Stack

## 11.1 iOS application stack

### Language and UI
- **Swift**
- **SwiftUI** for app structure and most screens
- **UIKit integration** where needed for terminal and advanced interactions

### Terminal
Recommended options:

- Use a UIKit-backed terminal component integrated into SwiftUI
- Prefer a mature VT100/xterm engine rather than trying to paint terminal text using generic text views
- Strong candidate: **SwiftTerm**, which provides a UI-agnostic terminal engine plus iOS front-ends for UIKit citeturn186132search0turn186132search12

The terminal view should be treated as a specialized rendering component, not a generic text widget.

### SSH / SFTP / port forwarding
Two viable paths exist:

#### Path A: libssh2-backed engine wrapped for Swift
- Mature C SSH2 library
- Good fit if you want a focused production client stack with direct control over channels, SFTP, and forwards
- Lower-level integration work, but very straightforward conceptually
- Better for a product that wants a clear “client stack” rather than a framework experiment

#### Path B: SwiftNIO + SwiftNIO SSH
- Pure Swift networking stack
- Strong long-term architectural appeal
- More engineering effort
- SwiftNIO SSH explicitly describes itself as a **programmatic implementation of SSH** and a set of building blocks, not a production-ready SSH client you can just drop in citeturn458847search0turn458847search4

**Recommendation:**  
Start with a **libssh2-backed client core** exposed through a thin Swift wrapper. Revisit pure-Swift transport later only if the integration cost and maintenance profile become favorable.

### Local network / tunnel plumbing
- **Network.framework** for local listener and connection plumbing where appropriate
- `NWListener` is Apple’s native listener API for incoming network connections citeturn186132search2
- Use local loopback listeners to present SSH-forwarded content to the in-app browser

### Preview browser
- **WKWebView** for in-app previews
- WKWebView is the native Apple web content surface and supports rich in-app web rendering citeturn458847search2turn458847search6

### Security
- **Keychain Services** for storing wrapped secrets and credentials
- **LocalAuthentication** for Face ID / Touch ID gating and secure unlock flows
- **Secure Enclave** where applicable for protecting locally held keys and wrapping secrets citeturn458847search3turn458847search7turn458847search11turn458847search15

### Storage
- **SQLite** for metadata, workspaces, tunnels, history, and indexes
- Optional SQLCipher or app-level encryption strategy for sensitive records
- Strong separation between secret material and general metadata

### Networking helpers
- `URLSessionWebSocketTask` can be used where the app needs native-side WebSocket handling or monitoring outside the webview path citeturn186132search3turn186132search11

## 11.2 Remote helper stack

### Language
- **Rust**

### Why Rust here
The remote helper is exactly the kind of component Rust is good at:

- small binary
- strong process and I/O control
- cross-distro portability
- safe concurrency
- low memory footprint
- easy static or mostly self-contained distribution
- suitable for a stdio RPC daemon-like process

### Suggested crates / building blocks
Exact crate choices can change, but the helper should likely use:

- Tokio for async runtime
- Serde for structured messages
- Clap for CLI
- portable process inspection utilities where available
- optional `nix` integration for Unix details
- tar / zip / compression helpers for artifact bundling
- simple structured logging

### Remote assumptions
The helper should target:

- modern Linux environments first
- user-level installation in `~/.local/bin`
- no root requirement
- no internet-facing port
- no required background daemon

---

## 12. Operating Modes

### 12.1 Plain SSH mode

No helper installed.

The app still provides:

- host management
- key vault
- terminal
- known_hosts trust
- saved port forwards
- snippets
- basic workspace definitions
- tmux attach by shelling out to tmux directly
- SFTP
- manual previews

This mode must still be solid.

### 12.2 Helper-on-demand mode

Helper is installed remotely and launched over SSH when needed.

The app gains:

- clean workspace resume
- structured tmux control
- port/process discovery
- preview suggestions
- pane summaries
- artifact listing
- richer local lenses

This should be the **main recommended mode**.

### 12.3 Persistent helper mode

The helper can run as an optional user service for faster reconnect and richer event streaming.

This is a power-user feature only. It should not be required and should not be the default.

---

## 13. Workspace Abstraction

The workspace is the core product abstraction.

### 13.1 Workspace fields

A workspace should include:

- workspace ID
- display name
- description
- environment tag
- host reference or jump-chain reference
- preferred transport
- shell
- repo path
- startup directory
- tmux session name
- tmux layout template
- preferred agent command
- snippets
- saved forwards
- preview rules
- artifact roots
- notes
- trust zone
- sync policy
- last-known status

### 13.2 Example workspace YAML

```yaml
version: 1
id: ws_openseat_web
name: OpenSeat Frontend
description: Main remote frontend workspace
environment: dev
host_ref: host_devbox_main
transport: ssh
shell: /bin/zsh
repo_path: /srv/dev/openseat/web
startup_dir: /srv/dev/openseat/web
tmux:
  session_name: openseat-web
  attach_policy: resume_or_create
  layout: web_default
  panes:
    - role: shell
      window: main
    - role: agent
      window: main
    - role: tests
      window: aux
    - role: server
      window: aux
preferred_agent_command: codex
saved_forwards:
  - name: nextjs
    remote_host: 127.0.0.1
    remote_port: 3000
    local_policy: stable
    auto_preview: true
preview_rules:
  auto_detect: true
  open_in_app: true
artifact_roots:
  - /srv/dev/openseat/web/.artifacts
  - /tmp
notes: |
  Main frontend repo. pnpm dev usually binds 3000. Storybook sometimes uses 6006.
trust_zone: trusted_dev
sync_policy: local_only
```

### 13.3 Resume semantics

“Resume workspace” should do as much as it safely can in one action:

1. connect to host
2. verify host key
3. attach or create tmux session
4. cd into repo if needed
5. restore pane layout
6. restart configured forwards
7. restore previews
8. focus primary pane
9. show recent diffs/tests/logs if available

---

## 14. Host Model

Hosts remain important, but they are not the top-level abstraction.

### 14.1 Host fields

- ID
- alias
- hostname
- port
- username
- authentication method
- key reference
- jump chain
- tags
- notes
- environment
- trust class
- known_hosts fingerprint state
- last seen

### 14.2 Host organization

Hosts should support:

- folders
- tags
- filters
- trust zones
- environment labels
- project labels
- quick search
- favorites

### 14.3 Jump paths

A host entry should be able to reference:

- direct connection
- one jump host
- multiple chained jumps
- bastion + target
- specific identities per hop

The UX should make jump topology visible instead of hiding it.

---

## 15. tmux-Native Runtime Design

tmux is the persistence substrate. The product should lean into this hard.

### 15.1 Why tmux is central

Without tmux, a mobile SSH client is always reconstructing ephemeral state. With tmux, the session has stable identity. The app should stop pretending terminal scrollback is session persistence and instead embrace the actual tool users rely on.

### 15.2 Core tmux capabilities

The app and helper should support:

- list sessions
- detect session existence
- create session
- attach session
- list windows
- list panes
- split pane
- create named layout
- capture pane buffer
- send command to pane
- get pane cwd
- get pane title / current command
- assign semantic pane role

### 15.3 Pane roles

Panes should support roles such as:

- shell
- agent
- tests
- server
- logs
- db
- scratch

These roles matter because on a phone the user cannot visually parse six tiny panes. The app needs semantic shortcuts.

### 15.4 Layout templates

Support workspace-defined layouts like:

- single shell
- shell + agent
- shell + agent + tests + server
- prod debug layout
- review layout
- incident response layout

The helper can translate template definitions into tmux commands cleanly.

---

## 16. Remote AI CLI Model

Codex, Claude Code, Aider, Gemini-like CLIs, and custom scripts are **ordinary remote processes**. The architecture should reflect that.

### 16.1 What the app should not do

The app should not:

- embed models
- depend on model-vendor RPC protocols
- require proprietary adapters
- turn remote CLIs into first-class protocol actors

### 16.2 What the app should do

The app should support:

- saved launch commands
- saved target panes
- pane labeling
- command history for these tools
- optional output recognition
- optional parser profiles
- fast re-entry into agent pane workflows

### 16.3 Parser / launch profiles

The initial pasted idea of “adapters” is still useful, but it should be reframed as a **lightweight optional parser/launch profile system**, not a required architectural boundary.

A profile can specify:

- default launch command
- likely command names
- likely output markers
- test result patterns
- diff summary patterns
- port / URL patterns
- interrupt command
- resume hint text
- pane icon / label

Example logical profiles:

- Codex profile
- Claude Code profile
- Aider profile
- Generic “AI CLI” profile
- Generic “custom command” profile

These are optional UX enhancements. The system must still work without them.

---

## 17. Structured Output Lenses

Raw terminal remains first-class, but users need alternate views over the same session data.

### 17.1 Lens types

- Terminal
- Command Timeline
- Diffs
- Tests
- Logs
- Ports & Links
- Errors Only
- Artifacts
- Repo Status

### 17.2 How lenses are built

There are two sources of truth:

1. **terminal stream interpretation**
2. **helper-provided structured metadata**

The app should combine both. When helper data exists, trust it more. When helper data is missing, fall back to terminal heuristics.

### 17.3 Command timeline

The timeline should capture:

- sent commands
- likely exit boundaries
- timestamps
- pane source
- related files
- related previews
- related artifact paths

### 17.4 Diff lens

Possible implementations:

- helper asks `git status --porcelain` and `git diff --stat`
- app can optionally request full diff
- if outside git, helper can still show recent changed files

This should support:

- changed file list
- unified diff
- staged / unstaged distinction
- export patch
- pull patch file locally

### 17.5 Test lens

Should display:

- latest test command
- likely pass/fail status
- failing test names
- summary counts
- rerun action

### 17.6 Logs lens

Should support:

- recent stderr-like output
- helper-labeled server pane logs
- search
- error filtering
- timestamps

### 17.7 Ports and links lens

Should support:

- extracted localhost URLs
- running forwards
- preview state
- owning process label
- one-tap open in preview

---

## 18. Preview and Tunnel System

This is one of the biggest places to beat existing SSH clients.

### 18.1 Product goal

Make remote app previews feel like a natural part of the workspace instead of a manual port-forward chore.

### 18.2 Preview lifecycle

A good preview flow is:

1. App or helper notices a likely listening dev server
2. User is prompted once, or auto-forward rule applies
3. SSH local forward is established
4. Local loopback endpoint is exposed inside the app
5. WKWebView opens the preview
6. Cookies and session state are scoped to that workspace
7. The app monitors tunnel health and re-establishes if needed

### 18.3 Detection inputs

The app may detect a preview candidate via:

- parsed terminal output
- helper process scan
- helper port scan
- known framework fingerprints
- previously saved preview rules

### 18.4 Framework heuristics

Useful pattern families:

- Vite
- Next.js
- React dev servers
- FastAPI / Uvicorn
- Flask
- Django
- Rails
- Phoenix
- Express
- Storybook
- Jupyter
- custom dashboards

### 18.5 Tunnel types

Support:

- local forwards
- remote forwards
- dynamic forwards later
- reverse/public-sharing integration later
- helper-assisted preview proxy later

### 18.6 iOS-specific preview implementation

On iOS the clean design is:

- establish SSH forward to a local loopback port
- present that endpoint inside a WKWebView
- isolate preview session storage per workspace where possible
- manage multiple previews in tabs or cards

For stronger reliability, add a tiny in-app HTTP bridge if necessary to normalize:

- host headers
- path prefixing
- cookie scoping
- preview identity

### 18.7 Edge cases

The preview system should explicitly handle:

- websocket-heavy apps
- SSE streams
- self-signed HTTPS on remote side
- apps that bind only to localhost
- multiple preview ports per workspace
- remapping collisions on local ports
- reconnect after iOS app suspension

### 18.8 Best version: helper-enhanced preview broker

The helper can expose richer preview metadata:

- listening port
- PID
- cwd
- likely framework
- process label
- whether it belongs to current workspace
- readiness / health hint

The helper may later provide an optional tiny reverse proxy mode, but that should be a later enhancement, not day-one complexity.

---

## 19. SFTP and Artifact Flow

SFTP should not feel like an orphaned utility tab.

### 19.1 Core file capabilities

The app should support:

- directory browsing
- favorite paths
- jump to workspace repo root
- upload
- download
- rename
- delete
- mkdir
- chmod / chown presets
- inline preview of text and markdown
- light edit-in-place for small files

### 19.2 Artifact-oriented behavior

The workspace system should make artifact retrieval easy:

- recent patches
- screenshots
- logs
- test reports
- generated markdown / JSON
- exported diffs

The helper can expose artifact roots and recent items so the app can show “Recent Artifacts” without forcing the user to manually browse every time.

### 19.3 Local handling on iOS

Use native iOS facilities for:

- Files integration
- share sheet
- quick look preview
- temporary local copies
- app-local document storage
- open-in-place where safe

---

## 20. Snippet System

Snippets should be treated as reusable workflow actions, not only saved commands.

### 20.1 Snippet capabilities

Support:

- variables
- prompts
- defaults
- host scoping
- workspace scoping
- target pane
- post-actions
- saved output capture
- parser hints
- dependencies on helper or plain SSH mode

### 20.2 Example snippet

```yaml
id: bootstrap_web
name: Bootstrap Web Workspace
scope: workspace
target_pane_role: shell
variables:
  repo_path:
    type: string
    default: /srv/dev/openseat/web
steps:
  - run: cd {{repo_path}}
  - run: pnpm install
  - run: pnpm dev
post_actions:
  - detect_ports: true
  - open_preview_if_found: true
```

### 20.3 Snippet UX

On iOS, snippets should be accessible via:

- toolbar button
- long press on workspace
- pane action sheet
- search / command palette
- quick chips for favorites

---

## 21. Security Model

This product should be more trustworthy than sync-first proprietary terminal clients.

### 21.1 Core security principles

- local-first by default
- no required account
- keys remain under user control
- clear trust model for hosts
- export always available
- optional sync must be encrypted and opt-in
- helper runs with user privileges unless explicitly configured otherwise

### 21.2 Security modes

#### Mode 1: Local-only
- no account
- all data stored on device
- ideal default
- best for security-sensitive users

#### Mode 2: Bring-your-own sync
- encrypted blob sync to user-selected backend
- iCloud Drive, Git, WebDAV, S3-compatible, etc.
- zero-knowledge style sync target

#### Mode 3: Hosted sync
- optional future feature
- end-to-end encrypted
- device approval flow
- clear export path

### 21.3 Secret classes

Separate storage handling for:

- private keys
- passphrases
- known_hosts
- host metadata
- snippets
- workspace definitions
- sync credentials
- team objects later

### 21.4 iOS-specific security implementation

Use:

- Keychain for small secrets and wrapped materials
- LocalAuthentication for unlock gates
- Secure Enclave-backed operations where feasible for locally generated keys or wrapping keys citeturn458847search3turn458847search7turn458847search11turn458847search19

### 21.5 Host trust

The app must support:

- first-use fingerprint display
- known_hosts persistence
- clear warnings for host key mismatch
- separate handling for trust-on-first-use vs strict pinning
- export/import of known_hosts later

### 21.6 Agent forwarding

Agent forwarding should exist, but it must be explicit and visible. Users should know when they are exposing signing capability remotely.

### 21.7 Helper trust

The helper should be treated as:

- optional
- user-installed
- inspectable
- signed release artifact
- not privileged by default
- not internet-facing
- invoked over SSH stdio by default

---

## 22. Sync and Storage

### 22.1 Local database

The app should maintain a local metadata store for:

- hosts
- workspaces
- snippets
- tunnel records
- preview records
- command history
- artifact indexes
- UI preferences
- trust states

### 22.2 Recommended storage split

- **Keychain** for secret material and key-wrapping state
- **SQLite** for metadata and session history
- optional encrypted blobs for export/import backups

### 22.3 Sync philosophy

Sync should not leak secrets by default and should not be required to use the product seriously.

### 22.4 Recommended rollout

- Phase 1: local only
- Phase 2: encrypted export/import + BYO sync
- Phase 3: self-hosted sync service
- Phase 4: hosted team sync if ever desired

---

## 23. iOS UX and Interaction Design

The app must remain terminal-first while still surfacing richer controls around it.

### 23.1 Primary navigation

Top-level sections:

- Hosts
- Workspaces
- Sessions
- Files
- Vault
- Settings

### 23.2 Key screens

#### Hosts
- search
- tags
- aliases
- jump visualization
- trust state
- quick connect

#### Workspaces
- recent
- favorites
- state badges
- preview badges
- environment grouping
- last opened

#### Session
- full terminal
- pane switcher
- snippet button
- preview button
- files button
- action sheet
- helper-aware status pills

#### Preview
- tabbed or card-based previews
- reload
- open externally
- inspect headers/port details later
- switch among previews within a workspace

#### Files / Artifacts
- repo root shortcut
- recent artifacts
- uploads/downloads
- text preview
- share / save to Files

### 23.3 Mobile ergonomics

Essential features:

- hardware keyboard shortcuts
- modifier row on-screen
- swipe between panes
- long-press pane actions
- command palette / fuzzy search
- paste modes
- low-bandwidth rendering toggle
- session resume shortcuts
- “recent workspaces” front and center

### 23.4 iPad
The same app should scale naturally to iPad with:

- multi-column layouts
- side-by-side preview + terminal options
- larger pane switchers
- better file browsing
- richer keyboard workflows

---

## 24. Terminal Engine Requirements

This is one of the real hard parts.

### 24.1 Required capabilities

- robust VT100 / xterm emulation
- alternate screen support
- strong copy/paste
- bracketed paste
- accurate color rendering
- Unicode handling
- minimal input latency
- smooth scrolling under heavy output
- good selection behavior
- keyboard modifier support
- terminal resize handling

### 24.2 Architectural note

Do **not** build the terminal on top of a generic text editor control. Use a real terminal engine and terminal rendering surface.

SwiftTerm is a strong candidate because it is designed specifically as a Swift terminal emulator library and has UIKit front-ends for iOS citeturn186132search0turn186132search12turn186132search20

### 24.3 Performance strategy

- incremental screen diffs
- avoid expensive full redraws
- support reduced-rendering mode when bandwidth is poor
- isolate terminal parsing from main-thread UI work
- maintain separate local scrollback buffer model

---

## 25. SSH Transport Architecture

### 25.1 Connection model

Each live session may maintain:

- interactive PTY channel
- helper exec channel if needed
- SFTP subsystem channel
- one or more port forwarding channels

The app should manage these as a coordinated session graph rather than one monolithic “socket.”

### 25.2 Authentication methods

Support:

- password
- plaintext private key
- encrypted private key
- agent forwarding
- passphrase prompts
- hardware-backed local keys later

### 25.3 Key generation

The app should support in-app key generation and labeling, with optional Face ID / Touch ID protection for local unlock.

### 25.4 Known hosts

Store and manage known_hosts data locally, with import/export later.

### 25.5 Why not pure SwiftNIO SSH first

SwiftNIO SSH is attractive, but its own documentation makes clear that it is a low-level programmatic implementation and building block, not a ready-made SSH client stack citeturn458847search0

For an iOS product whose value depends more on UX polish than on building SSH from scratch, starting with a mature SSH library backend is the more pragmatic choice.

---

## 26. Mosh Support

Mosh should be a later transport option, not a day-one blocker.

### 26.1 Why it matters

Mosh is explicitly designed to be more robust and responsive than SSH over shaky Wi‑Fi, cellular, and roaming scenarios, which is especially relevant on mobile citeturn186132search1turn186132search24

### 26.2 Why it should be phase 2

It introduces:

- UDP transport complexity
- different session semantics
- different reconnection behavior
- iOS backgrounding considerations
- terminal state synchronization behavior

### 26.3 Product posture

Support Mosh later as:

- a transport option for terminal sessions
- likely not the transport for every auxiliary feature
- potentially plain terminal only at first, with SSH still used for SFTP and structured helper flows

---

## 27. Remote Helper Design

The helper is the core differentiator-enabling component, but it must remain optional and disciplined.

### 27.1 Installation model

Default install path:

- `~/.local/bin/owrk-helper`

Default invocation:

```bash
~/.local/bin/owrk-helper serve --stdio
```

### 27.2 Deployment modes

#### Mode A: on-demand stdio mode
- preferred default
- launched over SSH exec
- speaks structured protocol over stdin/stdout
- no open port
- no daemon required

#### Mode B: user service mode
- optional
- faster reconnect
- easier state retention
- more complexity
- only for advanced users

### 27.3 Responsibilities

The helper should expose commands for:

- workspace resolve
- workspace resume plan
- tmux introspection
- tmux layout apply
- pane metadata
- port scan
- process scan
- preview candidates
- artifact listing
- git status summary
- diff summary
- test report summary later

### 27.4 Non-responsibilities

The helper should not:

- replace SSH
- require root
- expose an internet service
- become a full remote agent
- depend on Codex specifically
- store long-lived secrets unless the user explicitly opts in

---

## 28. Helper Protocol

### 28.1 Transport

Use **stdio over SSH exec**.

That gives:

- no extra firewall complexity
- no extra exposed network service
- easy permission model
- clean lifecycle tied to SSH authentication
- simpler threat surface

### 28.2 Message format

Use one of:

- newline-delimited JSON
- CBOR frames
- length-prefixed JSON frames

**Recommendation:** start with newline-delimited JSON or length-prefixed JSON for debuggability, then optimize later if needed.

### 28.3 RPC shape

Example request:

```json
{
  "id": "req-123",
  "method": "workspace.resume_plan",
  "params": {
    "workspace_id": "ws_openseat_web"
  }
}
```

Example response:

```json
{
  "id": "req-123",
  "result": {
    "tmux_session_exists": true,
    "recommended_attach_target": "openseat-web",
    "forward_candidates": [
      {
        "name": "nextjs",
        "remote_host": "127.0.0.1",
        "remote_port": 3000,
        "process_label": "pnpm dev"
      }
    ],
    "recent_artifacts": [
      "/srv/dev/openseat/web/.artifacts/test-report.json"
    ]
  }
}
```

### 28.4 Core methods

Suggested method groups:

- `ping`
- `version`
- `workspace.get`
- `workspace.resume_plan`
- `workspace.apply_layout`
- `tmux.list_sessions`
- `tmux.list_panes`
- `tmux.capture_pane`
- `tmux.send_keys`
- `process.list_ports`
- `process.preview_candidates`
- `artifacts.list_recent`
- `git.status`
- `git.diff_summary`

---

## 29. Preview Broker Design

Even without a heavyweight reverse proxy, the system can act like one from the user’s perspective.

### 29.1 Baseline design

- helper identifies preview candidates
- iOS app establishes SSH local forward
- app exposes forwarded content on loopback
- WKWebView opens it
- preview object is attached to workspace

### 29.2 Metadata tracked per preview

- preview ID
- workspace reference
- local port
- remote host
- remote port
- scheme
- display name
- process label
- health state
- cookie scope
- auto-reconnect flag

### 29.3 Future enhancements

Later, add:

- path-prefix normalization
- multiple preview tabs
- helper-assisted reverse proxy
- public share link through user-owned infra
- Cloudflare / Tailscale integration hooks

---

## 30. Repo-Aware Features

The app should gain leverage from common repo assumptions without pretending to be a full Git client.

### 30.1 Basic repo awareness

Support lightweight actions like:

- branch display
- status badge
- diff summary
- stash action later
- blame/open remote URL later
- open PR URL if remote is known later

### 30.2 Why this matters

A workspace is usually a repo-centered workflow. If the app cannot answer “what branch am I on?” or “what changed?” then it is leaving huge value on the table.

---

## 31. Observability and History

Sessions should produce reusable metadata, not vanish into scrollback.

### 31.1 Local observability objects

Track locally:

- last N commands per workspace
- preview history
- tunnel history
- recent diffs
- recent artifact pulls
- recent errors
- recent helper detections

### 31.2 Searchable local index

Later, add a local-only searchable index over:

- hosts
- workspaces
- snippets
- commands
- artifacts
- notes

This turns the app into a memory layer for remote work.

---

## 32. Optional Lightweight Editor

This should remain small.

### 32.1 Useful scope

Support only:

- viewing text files
- quick edits
- config tweaks
- patch review
- markdown reading
- log inspection

### 32.2 What to avoid

Do not attempt:

- full project editing
- IDE-scale refactoring
- complex language intelligence
- multi-file dev environment replacement

The app wins by tightening remote workflow loops, not by pretending the phone is a full IDE workstation.

---

## 33. Repository and Open-Source Layout

Recommended repo structure:

```text
ios-remote-workspace/
  app/
    Sources/
    Resources/
    Tests/

  ssh-core/
    cshim/
    swift-wrapper/

  terminal/
    terminal-bridge/
    terminal-ui/

  helper/
    src/
    tests/

  schemas/
    workspace/
    snippet/
    export/

  docs/
    DESIGN.md
    ARCHITECTURE.md
    SECURITY.md
    PROTOCOL.md
    ROADMAP.md

  sync/
    byosync-spec/
    future-selfhosted/

  scripts/
    helper-install.sh
    helper-upgrade.sh
```

If terminal and SSH wrappers become substantial, they can be separate Swift packages inside the repo.

---

## 34. Business and Sustainability Model

The product can stay open source without self-sabotage.

### 34.1 Good model

- fully usable open-source client
- optional self-hosted encrypted sync later
- optional hosted encrypted sync later
- optional team vault / shared objects product later
- enterprise policy features later if desired

### 34.2 Bad model

- cripple local-only use
- force sign-in for basics
- hold keys hostage in cloud sync
- hide core SSH functionality behind paid plans

Users will smell that trap instantly.

---

## 35. Implementation Roadmap

## Phase 1: Core wedge

Ship the smallest thing that proves the actual wedge.

### Must-have
- SSH terminal
- saved hosts
- key manager
- known_hosts trust flow
- local port forwarding
- workspaces
- tmux session browser
- simple tmux attach/create
- snippets
- in-app previews
- encrypted local vault
- iPad support as part of same app

### Nice to have
- basic SFTP
- recent workspaces
- preview auto-suggest from terminal parsing

## Phase 2: Helper-enhanced workflows

### Must-have
- Rust helper
- helper install / detect flow
- structured workspace resume
- pane roles
- preview candidate detection
- artifact listing
- recent command timeline
- improved SFTP integration

### Nice to have
- diff and test lenses
- repo summary panel

## Phase 3: Deeper mobile polish

- better structured lenses
- repo-aware actions
- recent artifacts
- export/import
- BYO sync
- hardware keyboard polish
- low-bandwidth mode

## Phase 4: Advanced transport and team features

- Mosh support
- self-hosted sync
- team/shared vaults
- public preview hooks through user-owned infra
- richer helper service mode

---

## 36. Hard Technical Problems

The real difficulty is not “can we open an SSH connection.”

The hard parts are:

- terminal quality on iOS
- helper and tmux integration that feels native
- preview/tunnel robustness across real frameworks
- state sync without security compromises
- reconnect behavior under iOS lifecycle constraints
- good hardware keyboard ergonomics
- host trust UX that is not sloppy
- keeping the UI narrow and fast instead of becoming fake-IDE garbage

Those are the places where most attempts get mediocre.

---

## 37. Success Metrics

### Product metrics
- median time to resume workspace
- number of taps to open preview
- number of manual tunnel creations avoided
- percentage of sessions using workspaces instead of raw hosts
- percentage of sessions with successful tmux resume
- preview reconnect success rate
- artifact retrieval frequency
- snippet reuse rate

### Quality metrics
- terminal input latency
- crash-free session rate
- helper command success rate
- SFTP transfer success rate
- host key mismatch handling correctness
- battery impact during extended sessions
- websocket preview stability

---

## 38. Final Product Definition

The sharpest correct definition of the product is:

> **A native iOS SSH client with first-class workspace semantics, backed by an optional Rust helper on the remote host that exposes tmux, preview, artifact, and session metadata over SSH.**

That is the right scope.

It is not a desktop app.  
It is not a cloud IDE.  
It is not a model integration layer.  
It is not a fake mobile IDE.

It is a serious mobile remote workspace client that steals everything users already love from Termius and then fixes the biggest missing layer for modern remote development.

---

## 39. Immediate Follow-On Specs

The next documents that should be written after this one are:

1. **PROTOCOL.md**  
   Exact helper RPC protocol, framing, method list, and error model.

2. **WORKSPACES.md**  
   Exact workspace schema, versioning, import/export format, and resume semantics.

3. **SECURITY.md**  
   Threat model, key handling, host trust model, helper trust assumptions, and sync encryption design.

4. **TERMINAL.md**  
   Terminal engine requirements, iOS keyboard behavior, buffering, rendering, and performance constraints.

5. **PREVIEWS.md**  
   SSH forwarding model, iOS loopback presentation, webview isolation, websocket handling, and reconnect rules.

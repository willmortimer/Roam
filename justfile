# iDev project — local build and test recipes
# Usage: just <recipe>  (run from ~/Developer/iDev)

set shell := ["zsh", "-cu"]

ios_dir     := "iDev"
rs_dir      := "iDev-rs"
scheme      := "iDev"
simulator   := "iPhone 17 Pro"

# ── Default ──────────────────────────────────────────────────────────────────

# Build everything (Rust + Swift)
default: build

# ── Rust helper ──────────────────────────────────────────────────────────────

# Build Rust helper (debug)
rust-build:
    cd {{rs_dir}} && cargo build

# Build Rust helper (release)
rust-release:
    cd {{rs_dir}} && cargo build --release

# Run helper unit + integration tests
rust-test:
    cd {{rs_dir}} && cargo test -p idev-helper

# Run Rust clippy lints
rust-lint:
    cd {{rs_dir}} && cargo clippy -- -D warnings

# Cross-build for x86_64 musl (static Linux binary)
rust-cross-x86:
    cd {{rs_dir}} && cross build --release --target x86_64-unknown-linux-musl

# Cross-build for aarch64 musl (static Linux binary)
rust-cross-arm:
    cd {{rs_dir}} && cross build --release --target aarch64-unknown-linux-musl

# Show Rust helper binary size (release)
rust-size: rust-release
    ls -lh {{rs_dir}}/target/release/idev-helper | awk '{print $5, $9}'

# ── Sync server ──────────────────────────────────────────────────────────────

# Build sync server (debug)
sync-build:
    cd {{rs_dir}} && cargo build -p idev-sync-server

# Build sync server (release)
sync-release:
    cd {{rs_dir}} && cargo build -p idev-sync-server --release

# Run sync server tests (unit + integration)
sync-test:
    cd {{rs_dir}} && cargo test -p idev-sync-server

# Build sync server Docker image
sync-docker:
    cd {{rs_dir}}/sync-server && docker build -t idev-sync-server .

# ── Combined Rust ────────────────────────────────────────────────────────────

# Run all Rust tests across the workspace (helper + sync-server)
rust-test-all:
    cd {{rs_dir}} && cargo test --workspace

# Lint entire Rust workspace
rust-lint-all:
    cd {{rs_dir}} && cargo clippy --workspace -- -D warnings

# ── iOS app ──────────────────────────────────────────────────────────────────

# Build iOS app for simulator
ios-build:
    cd {{ios_dir}} && xcodebuild build \
        -scheme {{scheme}} \
        -destination 'platform=iOS Simulator,name={{simulator}}' \
        -quiet

# Build iOS app and show only errors/warnings
ios-check:
    cd {{ios_dir}} && xcodebuild build \
        -scheme {{scheme}} \
        -destination 'platform=iOS Simulator,name={{simulator}}' \
        2>&1 | grep -E '(error:|warning:|BUILD)' || true

# ── Combined ─────────────────────────────────────────────────────────────────

# Build both Rust and Swift
build: rust-build ios-build

# Run all tests (Rust workspace)
test: rust-test-all

# Lint Rust + build Swift (quick CI-like check)
check: rust-lint-all ios-check
    @echo "✓ All checks passed"

# ── Utilities ────────────────────────────────────────────────────────────────

# Count lines of code by language
loc:
    @echo "── Rust (helper) ──"
    @find {{rs_dir}}/src -name '*.rs' | xargs wc -l | tail -1
    @echo "── Rust (sync-server) ──"
    @find {{rs_dir}}/sync-server/src -name '*.rs' | xargs wc -l | tail -1
    @echo "── Swift ──"
    @find {{ios_dir}}/iDev -name '*.swift' | xargs wc -l | tail -1

# List all RPC methods registered in the helper (32 total as of Phase 4)
rpc-methods:
    @grep 'server.register(' {{rs_dir}}/src/main.rs | sed 's/.*"\(.*\)".*/\1/'

# Quick NDJSON smoke test: send a ping request to the helper via stdin
rpc-smoke:
    @echo '{"id":"test-1","method":"ping","params":{}}' \
        | cd {{rs_dir}} && cargo run --quiet -- serve --stdio 2>/dev/null \
        | head -1 | python3 -m json.tool

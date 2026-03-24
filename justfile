# Roam project — local build and test recipes
# Usage: just <recipe>  (run from ~/Developer/iDev)
# Auxiliary tool versions live in mise.toml; just is the workflow/task layer.

set shell := ["zsh", "-cu"]

ios_dir           := "Roam"
ios_project       := "Roam/Roam.xcodeproj"
rs_dir            := "roam-rs"
scheme            := "Roam"
bundle_id         := "willmortimer.Roam"
simulator         := "iPhone 17 Pro"
derived_data      := "/tmp/roam-derived"
test_derived_data := "/tmp/roam-test-derived"
app_bundle        := "/tmp/roam-derived/Build/Products/Debug-iphonesimulator/Roam.app"

# ── Default ──────────────────────────────────────────────────────────────────

# Build everything (Rust + Swift)
default: build

# ── Rust helper ──────────────────────────────────────────────────────────────

# Trust the repo's mise.toml on this machine
tools-trust:
    mise trust -y mise.toml

# Install all repo-managed dev tools from mise.toml
tools-install:
    mise install

# Upgrade all repo-managed dev tools via mise
tools-upgrade:
    mise upgrade

# Install or refresh the repo-managed `cross` tool via mise
cross-install:
    mise install cargo:cross

# Install the Rust host toolchain `cross` may need on Apple Silicon
cross-host-toolchain:
    rustup toolchain list | rg -q '^stable-x86_64-unknown-linux-gnu' || rustup toolchain install stable-x86_64-unknown-linux-gnu --force-non-host

# Show the active Rust toolchain plus repo-managed auxiliary tools
rust-toolchain:
    rustc --version
    cargo --version
    rustup show active-toolchain
    NO_COLOR=1 mise current | rg '^(python|cargo:cross)(\s|$)' || true

# Build Rust helper (debug)
rust-build:
    cd {{rs_dir}} && cargo build

# Build Rust helper (release)
rust-release:
    cd {{rs_dir}} && cargo build --release

# Run helper unit + integration tests
rust-test:
    cd {{rs_dir}} && cargo test -p roam-helper

# Run Rust clippy lints
rust-lint:
    cd {{rs_dir}} && cargo clippy -- -D warnings

# Cross-build for x86_64 musl (static Linux binary)
rust-cross-x86: cross-host-toolchain
    cd {{rs_dir}} && mise exec -- cross build --release --target x86_64-unknown-linux-musl

# Cross-build for aarch64 musl (static Linux binary)
rust-cross-arm: cross-host-toolchain
    cd {{rs_dir}} && mise exec -- cross build --release --target aarch64-unknown-linux-musl

# Build both Linux helper binaries used by the app installer
helper-cross-all: rust-cross-x86 rust-cross-arm

# Show where helper cross-build outputs are expected
helper-paths:
    @echo "{{rs_dir}}/target/x86_64-unknown-linux-musl/release/roam-helper"
    @echo "{{rs_dir}}/target/aarch64-unknown-linux-musl/release/roam-helper"

# Show Rust helper binary size (release)
rust-size: rust-release
    ls -lh {{rs_dir}}/target/release/roam-helper | awk '{print $5, $9}'

# ── Sync server ──────────────────────────────────────────────────────────────

# Build sync server (debug)
sync-build:
    cd {{rs_dir}} && cargo build -p roam-sync-server

# Build sync server (release)
sync-release:
    cd {{rs_dir}} && cargo build -p roam-sync-server --release

# Run sync server tests (unit + integration)
sync-test:
    cd {{rs_dir}} && cargo test -p roam-sync-server

# Build sync server Docker image
sync-docker:
    cd {{rs_dir}}/sync-server && docker build -t roam-sync-server .

# ── Combined Rust ────────────────────────────────────────────────────────────

# Run all Rust tests across the workspace (helper + sync-server)
rust-test-all:
    cd {{rs_dir}} && cargo test --workspace

# Lint entire Rust workspace
rust-lint-all:
    cd {{rs_dir}} && cargo clippy --workspace -- -D warnings

# ── iOS app ──────────────────────────────────────────────────────────────────

# Open and boot the configured simulator
sim-open:
    open -a Simulator
    xcrun simctl boot "{{simulator}}" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "{{simulator}}" -b

# Shut down the configured simulator
sim-shutdown:
    xcrun simctl shutdown "{{simulator}}" >/dev/null 2>&1 || true

# Open the Xcode project
xcode-open:
    open {{ios_project}}

# Build iOS app for simulator and run Xcode's helper staging phase
ios-build:
    xcodebuild build \
        -project {{ios_project}} \
        -scheme {{scheme}} \
        -destination 'platform=iOS Simulator,name={{simulator}}' \
        -derivedDataPath {{derived_data}} \
        -quiet

# Build iOS app and show only errors/warnings
ios-check:
    xcodebuild build \
        -project {{ios_project}} \
        -scheme {{scheme}} \
        -destination 'platform=iOS Simulator,name={{simulator}}' \
        -derivedDataPath {{derived_data}} \
        2>&1 | grep -E '(error:|warning:|BUILD)' || true

# Clean iOS build products
ios-clean:
    xcodebuild clean \
        -project {{ios_project}} \
        -scheme {{scheme}} \
        -destination 'platform=iOS Simulator,name={{simulator}}' \
        -derivedDataPath {{derived_data}} \
        -quiet

# Run iOS unit tests from the CLI
ios-test: sim-open
    xcodebuild test \
        -project {{ios_project}} \
        -scheme {{scheme}} \
        -destination 'platform=iOS Simulator,name={{simulator}}' \
        -derivedDataPath {{test_derived_data}} \
        -quiet

# Install the built app into the configured simulator
ios-install: ios-build sim-open
    xcrun simctl install "{{simulator}}" "{{app_bundle}}"

# Launch the installed app in the configured simulator
ios-launch: sim-open
    xcrun simctl launch "{{simulator}}" "{{bundle_id}}"

# Build, install, and launch the app in the configured simulator
ios-run: ios-install
    xcrun simctl launch "{{simulator}}" "{{bundle_id}}"

# ── Combined ─────────────────────────────────────────────────────────────────

# Build both Rust and Swift
build: rust-build ios-build

# Run all tests (Rust workspace)
test: rust-test-all

# Lint Rust + build Swift (quick CI-like check)
check: rust-lint-all ios-check
    @echo "✓ All checks passed"

# Quick local tooling status
doctor:
    @echo "── Core tools ──"
    @if command -v mise >/dev/null 2>&1; then echo "mise:   $(command -v mise) ($(mise --version))"; else echo "mise:   missing"; fi
    @if command -v just >/dev/null 2>&1; then echo "just:   $(command -v just)"; else echo "just:   missing"; fi
    @if command -v cargo >/dev/null 2>&1; then echo "cargo:  $(command -v cargo)"; else echo "cargo:  missing"; fi
    @if command -v rustc >/dev/null 2>&1; then echo "rustc:  $(rustc --version)"; else echo "rustc:  missing"; fi
    @if command -v rustup >/dev/null 2>&1; then echo "rustup: $(command -v rustup)"; else echo "rustup: missing"; fi
    @if command -v rustup >/dev/null 2>&1; then echo "toolchain: $(rustup show active-toolchain 2>/dev/null || echo unknown)"; fi
    @if command -v cross >/dev/null 2>&1; then echo "cross (PATH): $(command -v cross)"; else echo "cross (PATH): missing"; fi
    @if command -v mise >/dev/null 2>&1; then echo "cross (mise): $(mise which cross 2>/dev/null || echo missing)"; else echo "cross (mise): unavailable"; fi
    @if command -v xcodebuild >/dev/null 2>&1; then echo "xcodebuild: $(command -v xcodebuild)"; else echo "xcodebuild: missing"; fi
    @if command -v xcrun >/dev/null 2>&1; then echo "xcrun:  $(command -v xcrun)"; else echo "xcrun:  missing"; fi
    @echo "── Repo-managed tools ──"
    @if command -v mise >/dev/null 2>&1; then NO_COLOR=1 mise current | rg '^(python|cargo:cross)(\s|$)' || true; else echo "mise-managed tools: unavailable"; fi
    @echo "── Container runtime ──"
    @if command -v docker >/dev/null 2>&1; then echo "docker: $(command -v docker)"; elif command -v colima >/dev/null 2>&1; then echo "colima: $(command -v colima)"; elif command -v podman >/dev/null 2>&1; then echo "podman: $(command -v podman)"; else echo "container runtime: missing"; fi
    @echo "── Helper outputs ──"
    @if [ -f "{{rs_dir}}/target/x86_64-unknown-linux-musl/release/roam-helper" ]; then echo "x86_64 helper: present"; else echo "x86_64 helper: missing"; fi
    @if [ -f "{{rs_dir}}/target/aarch64-unknown-linux-musl/release/roam-helper" ]; then echo "aarch64 helper: present"; else echo "aarch64 helper: missing"; fi

# ── Utilities ────────────────────────────────────────────────────────────────

# Count lines of code by language
loc:
    @echo "── Rust (helper) ──"
    @find {{rs_dir}}/src -name '*.rs' | xargs wc -l | tail -1
    @echo "── Rust (sync-server) ──"
    @find {{rs_dir}}/sync-server/src -name '*.rs' | xargs wc -l | tail -1
    @echo "── Swift ──"
    @find {{ios_dir}}/Roam -name '*.swift' | xargs wc -l | tail -1

# List all RPC methods registered in the helper (32 total as of Phase 4)
rpc-methods:
    @grep 'server.register(' {{rs_dir}}/src/main.rs | sed 's/.*"\(.*\)".*/\1/'

# Quick NDJSON smoke test: send a ping request to the helper via stdin
rpc-smoke:
    @echo '{"id":"test-1","method":"ping","params":{}}' \
        | cd {{rs_dir}} && cargo run --quiet -- serve --stdio 2>/dev/null \
        | head -1 | mise exec -- python3 -m json.tool

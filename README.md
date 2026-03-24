# Roam

Roam is an iOS app for serious remote development over SSH. It gives you a native workspace for hosts, terminals, files, previews, vault-backed credentials, and resumable sessions, backed by a Rust helper for repo-aware and workspace-aware actions.

## Status

Roam is under active development. The core product shape is here, but the repo should still be treated as early-stage software rather than a finished platform release.

## What Roam Is For

- Managing remote hosts and saved workspaces from an iPhone or iPad
- Running terminal-first development workflows away from a laptop
- Resuming active work quickly with tmux-aware session context
- Browsing files, previews, artifacts, and repo state from one interface
- Syncing encrypted app data with a self-hosted backend if you want it

## Architecture

- `Roam/`: SwiftUI iOS app, tests, bundled assets, and the local `RoamSSH` package
- `roam-rs/`: Rust workspace for `roam-helper` and `roam-sync-server`
- `docs/`: architecture notes, development setup, and technical plans
- `justfile`: common build and test commands

## Main Components

### Roam iOS app

The app is the primary user-facing surface. It manages hosts, workspaces, sessions, file access, previews, vault flows, sync settings, and the navigation model for mobile remote work.

### `roam-helper`

`roam-helper` is a Rust RPC daemon used by the app for remote operational features, including:

- tmux inspection and control
- git status and write actions
- process and preview discovery
- artifact listing
- resume planning and session restoration
- tunnel and proxy lifecycle management

### `roam-sync-server`

`roam-sync-server` is an optional self-hosted service for encrypted blob sync.

## Requirements

- Xcode 17+ with an iOS 26 simulator runtime
- Rust stable
- `just`
- `mise`
- Xcode Command Line Tools
- A container runtime if you want automatic Linux helper cross-builds (`Docker Desktop`, `Colima`, or `Podman`)

## Quick Start

```sh
just tools-trust
just tools-install
just cross-host-toolchain
just doctor
just rust-build
just ios-build
just ios-run
```

Common full-workspace commands:

```sh
just tools-trust
just tools-install
just tools-upgrade
just rust-toolchain
just cross-install
just cross-host-toolchain
just helper-cross-all
just rust-test-all
just sync-build
just ios-test
just ios-check
just check
```

Direct Xcode commands:

```sh
xcodebuild -project Roam/Roam.xcodeproj -scheme Roam -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/roam-derived build
xcodebuild test -project Roam/Roam.xcodeproj -scheme Roam -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/roam-test-derived
```

## Helper Packaging

The iOS app includes a build phase that stages Linux helper binaries into the app bundle during normal Xcode builds.

- If `cross` is installed through `mise`, missing helper binaries can be built automatically for `x86_64-unknown-linux-musl` and `aarch64-unknown-linux-musl`
- On Apple Silicon hosts, run `just cross-host-toolchain` once so `cross` has the extra Rust host toolchain it may need for Linux builds
- On Apple Silicon hosts, the Xcode build phase currently auto-builds the `x86_64-unknown-linux-musl` helper and expects a prebuilt artifact for `aarch64-unknown-linux-musl`
- If `cross` is not installed, app builds still succeed, but helper install and upgrade flows will report missing binaries until you build them
- Xcode GUI builds (`Cmd-B`, `Cmd-R`, `Cmd-U`) use the same build phase, so they can also trigger helper staging and auto-builds when `cross` is available

## Helper Releases

- `.github/workflows/release-helper.yml` builds `roam-helper` release assets on GitHub Actions
- Push a tag like `helper-v0.1.0` to publish:
  - `roam-helper-linux-x86_64`
  - `roam-helper-linux-aarch64`
- The workflow also publishes:
  - `roam-helper-linux-x86_64.sha256`
  - `roam-helper-linux-aarch64.sha256`
- The iOS app is configured to fetch helper binaries from the GitHub repository in [Roam/Roam/Info.plist](/Users/willmortimer/Developer/iDev/Roam/Roam/Info.plist) using the tag `helper-v<requiredVersion>`
- Downloaded helper assets are SHA-256 verified before install, and cached helper assets are revalidated before reuse
- If your GitHub repo slug is not `willmortimer/Roam`, update `RoamHelperReleaseRepository` in [Roam/Roam/Info.plist](/Users/willmortimer/Developer/iDev/Roam/Roam/Info.plist)

## Documentation

- `docs/architecture.md`
- `docs/development.md`
- `docs/git-setup.md`
- `docs/repository-state.md`
- `docs/sprint-4.1-mosh-technical-plan.md`

## License

Roam is licensed under the MIT License. See [LICENSE](LICENSE).

Bundled font notices are documented in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

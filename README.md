# Roam

Roam is an iOS-first remote development workspace for SSH-driven workflows. It combines a native client, a Rust helper daemon, and a self-hosted sync service so you can manage hosts, workspaces, terminal sessions, previews, artifacts, and encrypted app data from one system.

## What It Does

- Connects to remote machines over SSH with a native iOS client
- Organizes hosts, workspaces, tmux sessions, previews, and repo-aware views
- Uses `roam-helper` for remote RPC features such as git actions, process discovery, tunnel management, and workspace resume planning
- Supports encrypted export/import flows and optional self-hosted sync through `roam-sync-server`

## Repository Layout

- `Roam/`: SwiftUI iOS app, tests, bundled resources, and the local `RoamSSH` package
- `roam-rs/`: Rust workspace for `roam-helper` and `roam-sync-server`
- `docs/`: architecture notes, setup docs, and technical plans
- `justfile`: common local build and test commands

## Requirements

- Xcode 17+ with an iOS 26 simulator runtime
- Rust stable
- `just`
- A container runtime if you want automatic Linux helper cross-builds (`Docker Desktop`, `Colima`, or `Podman`)

## Quick Start

```sh
just doctor
just rust-build
just ios-build
just ios-run
```

Useful full-workspace commands:

```sh
just cross-install
just helper-cross-all
just rust-test-all
just sync-build
just ios-test
just ios-check
just check
```

Useful direct Xcode commands:

```sh
xcodebuild -project Roam/Roam.xcodeproj -scheme Roam -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/roam-derived build
xcodebuild test -project Roam/Roam.xcodeproj -scheme Roam -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/roam-test-derived
```

## Helper Packaging

The app includes a build phase that stages Linux helper binaries into the bundle during normal Xcode builds.

- If `cross` is installed, missing helper binaries can be built automatically for `x86_64-unknown-linux-musl` and `aarch64-unknown-linux-musl`
- If `cross` is not installed, the app still builds, but helper install and upgrade flows will report the missing binaries until you build them

## Documentation

- `docs/architecture.md`
- `docs/development.md`
- `docs/git-setup.md`
- `docs/repository-state.md`
- `docs/sprint-4.1-mosh-technical-plan.md`

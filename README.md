# iDev

iDev is a multi-component remote development workspace centered on an iOS client. This top-level directory is now the intended project root for the app, the Rust services, the shared docs, and the build commands.

## Workspace Layout

- `iDev/`: SwiftUI + SwiftData iOS app, plus the local `iDevSSH` package.
- `iDev-rs/`: Rust workspace containing the `idev-helper` RPC daemon and the `idev-sync-server`.
- `docs/`: architecture notes, development setup, repository assessment, and technical plans.
- `justfile`: common build and test commands for the full workspace.

## Main Components

### iOS app

The iOS app owns the user-facing product surface: hosts, workspaces, SSH sessions, tmux-aware views, repo/test lenses, previews, vault flows, and sync settings.

### Rust helper

`idev-helper` is a local/remote RPC daemon that exposes operational capabilities to the app over NDJSON RPC. It currently covers:

- tmux inspection and control
- git status and write actions
- process and preview discovery
- artifact listing
- workspace resume planning
- test report parsing
- proxy and tunnel lifecycle

### Sync server

`idev-sync-server` is a small Axum service that stores opaque encrypted blobs on disk and can be protected with a bearer token.

## Quick Start

Requirements:

- Xcode 17+ with an iOS 26 simulator runtime
- Rust stable toolchain
- `just`

Common commands:

```sh
just rust-build
just rust-test-all
just sync-build
just ios-build
just ios-check
just check
```

Useful direct Xcode commands:

```sh
xcodebuild -project iDev/iDev.xcodeproj -scheme iDev -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/idev-derived build
xcodebuild test -project iDev/iDev.xcodeproj -scheme iDev -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/idev-test-derived
```

## Documentation

- `docs/architecture.md`
- `docs/development.md`
- `docs/git-setup.md`
- `docs/repository-state.md`
- `docs/sprint-4.1-mosh-technical-plan.md`

## Repository Note

The top-level repository is the canonical repo for the full workspace. The legacy embedded iOS git directory has been retired from the working tree as part of consolidation, with backup details captured in `docs/git-setup.md`.

# Development

## Prerequisites

- Xcode 17+
- iOS 26 simulator runtime
- Rust stable
- `just`

Optional but useful:

- `cross` for Linux cross-compiles
- Docker for the sync-server image build

## Directory Map

- `iDev/`: Xcode project, Swift app sources, local Swift package
- `iDev-rs/`: Cargo workspace
- `docs/`: design and project documentation
- `justfile`: root task entrypoint

## Common Commands

From the repository root:

```sh
just rust-build
just rust-release
just rust-test-all
just rust-lint-all
just sync-build
just sync-test
just ios-build
just ios-check
just check
just loc
```

## Direct Validation Commands

Rust workspace:

```sh
cd iDev-rs
cargo test --workspace
```

iOS build:

```sh
xcodebuild -project iDev/iDev.xcodeproj -scheme iDev -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/idev-derived build
```

iOS tests:

```sh
xcodebuild test -project iDev/iDev.xcodeproj -scheme iDev -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/idev-test-derived
```

## Notes

- The Rust sync-server integration tests bind localhost and spawn the test server process. In restricted sandboxes, they may fail even when the code is correct.
- The Xcode project uses modern toolchains and simulator SDKs, so CI or local machines need a recent Xcode installation.
- The default sync-server data path is `./sync-data`; it is ignored at the repo root.

## What To Keep Out Of Git

- `iDev-rs/target/`
- Xcode user state and `xcuserdata`
- SwiftPM build directories
- local logs, temp directories, and sync data

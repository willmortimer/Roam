# Repository State

Assessment date: 2026-03-23

## Executive Summary

This is a serious product codebase, not a throwaway prototype. The architecture direction is stronger than the remaining product-integration gaps, and the repository structure now matches the actual scope of the project after the root-level consolidation.

## What Exists Today

- Swift iOS app in `iDev/`
- Rust helper workspace in `iDev-rs/`
- Rust sync server in `iDev-rs/sync-server/`
- root `justfile` that already assumes the workspace should be managed from the top level
- one existing technical plan in `docs/`

Approximate size at the time of review:

- 93 Swift source files in the app
- 6 Swift test files
- about 13.3k lines of Swift app code
- 17 Rust source/test files
- about 5.3k lines of Rust code

## Validation Snapshot

What validated during this review:

- `cargo test --workspace` passes for the helper crate and sync-server unit coverage
- sync-server integration tests pass when allowed to bind localhost and spawn the server normally
- the iOS app builds successfully for the simulator
- the iOS build emits a Swift concurrency warning in `KnownHostsService`
- the full iOS test run failed once on `EncryptedBlobServiceTests/emptyData`, but that same test passed when rerun in isolation, which points to a flaky or order-sensitive test rather than an obvious deterministic failure

## Main Problems

### 1. Core product flows are not fully wired

The codebase contains architecture for connection and resume flows, but some obvious entry points are still TODOs in the views:

- `HostDetailView` connect button
- `WorkspaceDetailView` resume button

That suggests implementation is ahead at the service/orchestration layer, but some core UX wiring is still pending.

### 2. Swift 6 strictness is approaching

The simulator build succeeds, but `KnownHostVerification` carries a `KnownHostRecord` associated value while marked `Sendable`. That warning will become more important as the project moves fully into Swift 6 mode.

### 3. Test stability is not fully trustworthy

The Swift test suite is close to green, but at least one test behaved inconsistently during validation. That is a smaller problem than a hard failure, but it means CI confidence is not fully established yet.

### 4. Documentation duplication exists

The remote workspace design spec appears in both `iDev/` and `iDev-rs/`, which is a maintenance smell unless one copy is intentionally generated or vendored.

### 5. Historical repo noise still exists in old commits

The consolidation fixed the active repo boundary, but the old iOS history included tracked Xcode user-state files. That is now a historical cleanup issue rather than a live workspace-structure issue.

## What Looks Strong

- Clear product ambition and a coherent system boundary
- Good modularity on the Rust side
- Broad helper test coverage
- A useful root `justfile` that already reflects how developers want to work
- Strong domain modeling in the iOS app

## Overall Thoughts

My overall read is positive. The codebase has real depth and a credible architecture, especially the split between the Swift product shell and the Rust operational helper. The biggest weakness is not the code itself; it is the repo shape and the missing project-level guidance around it.

The repo-boundary problem is now fixed. The next quality step is straightforward: keep the docs current, finish wiring the top-level connect/resume flows, and stabilize the last flaky parts of the iOS test surface.

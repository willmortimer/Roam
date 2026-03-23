# Git Setup

## Current State

The workspace is now a single top-level git repository containing:

- `iDev/`
- `iDev-rs/`
- `docs/`
- `justfile`

This is now the canonical repo boundary.

## What Was Consolidated

The consolidation preserved the original iOS repo history by importing it into the root history under the `iDev/` path, then committing the current full workspace snapshot at the root.

The old git directories were moved out of active use:

- the temporary empty root repo created during setup was retired
- the embedded iOS repo at `iDev/.git` was moved into `.git-backups/`

After consolidation, `iDev/.git` should no longer exist in the working tree.

## Expected Outcome

From the repository root, these should now be true:

- `git status` describes the whole workspace
- `iDev-rs/` is versioned in the same repo as the iOS app
- `docs/` and `justfile` live in the same repo boundary as the code they describe
- `git add .` is safe at the root

## Ignore Rules Added

The new ignore rules cover:

- Rust build artifacts
- Xcode user state
- SwiftPM build directories
- sync data
- local assistant/tooling files

There is also an `iDev/.gitignore` so the existing iOS repo benefits immediately, even before a full root migration.

One caveat: the old iOS repo tracked Xcode user-state files historically. Ignore rules stop new noise from being added, and the consolidated repo removes that noise from the active tip, but it still exists in earlier history.

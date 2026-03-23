# Architecture

## Overview

The project is split into three main runtime surfaces:

1. A SwiftUI iOS app in `iDev/`
2. A Rust helper daemon in `iDev-rs/`
3. A Rust sync server in `iDev-rs/sync-server/`

The overall product direction is a mobile-first remote development workspace with SSH-driven sessions, tmux awareness, repo/test visibility, forwarding, previews, and optional self-hosted sync.

## iOS App

The iOS app is the product shell and the main orchestration layer.

Key traits:

- SwiftUI app entrypoint with SwiftData-backed persistence
- local package `Packages/iDevSSH` wrapping `libssh2`
- view-heavy structure organized by domain: hosts, workspaces, sessions, vault, settings, shared UI
- service layer for auth, helper install/detection, SSH config parsing, encryption, forwards, previews, known hosts, and session lifecycle
- orchestration flow in `WorkspaceResumeOrchestrator` for the intended end-to-end "resume workspace" experience

High-level flow:

1. The user chooses a host or workspace.
2. The app creates a managed SSH session.
3. The app authenticates and opens a shell bridge.
4. The app optionally starts the Rust helper and talks to it over NDJSON RPC through an exec channel.
5. The UI layers consume helper-backed data for repo summaries, test views, tmux panes, previews, and automation.

## Rust Helper

The helper is a CLI + RPC server registered in `iDev-rs/src/main.rs`.

Its main purpose is to give the iOS app structured access to remote developer tooling without pushing that logic into Swift. Current modules cover:

- `rpc`: transport and dispatch
- `tmux`: sessions, panes, capture, send keys
- `process`: open ports and preview candidates
- `git`: status, diff summary, stage/commit/push/pull/checkout/stash actions
- `artifacts`: recent file discovery
- `workspace`: resume planning
- `testing`: parser for test reports
- `proxy`: reverse proxy lifecycle
- `tunnel`: Cloudflare/Tailscale tunnel lifecycle

This split is a good architectural choice. The heavy operational surface is already pushed into Rust, while the iOS app remains focused on product workflow and presentation.

## Sync Server

The sync server is intentionally narrow:

- Axum HTTP API
- flat-file blob storage
- optional bearer token auth through `IDEV_SYNC_TOKEN`

It behaves like infrastructure glue rather than a product core, which is appropriate for this codebase.

## Strengths

- The system boundary is sensible: UI/product in Swift, operational tooling in Rust.
- The helper surface area is already broad enough to support a serious remote workflow.
- The codebase shows deliberate product thinking rather than being just a terminal wrapper.

## Current Integration Gaps

Some user-facing flows are still only partially wired:

- host connect action is still a TODO in the UI
- workspace resume action is still a TODO in the UI
- parts of the helper-enhanced resume flow are present architecturally but not fully surfaced end-to-end

That means the architecture is ahead of the final product integration in a few key paths.

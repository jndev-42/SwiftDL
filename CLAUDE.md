# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
swift build                   # Debug build
swift build -c release        # Release build
swift run StremioDownloader   # Build and run
```

No external dependencies — native macOS APIs only.

## Architecture

Native macOS SwiftUI app (macOS 14+) for downloading video files via HTTP/HTTPS and managing a local library. Single Swift Package target: `StremioDownloader`.

**Three singleton services** are injected as environment objects at app launch (`StremioDownloaderApp.swift`):

- `DownloadManager` — drives URLSession downloads; all `@MainActor`; does **not** inherit NSObject (uses a separate delegate adapter `DownloadSessionDelegate`)
- `SettingsManager` — folder selection via NSOpenPanel; persists access via security-scoped bookmarks in UserDefaults
- `LibraryManager` — no database; scans the destination folder on demand and rebuilds state from the filesystem

All three use the `@Observable` macro (not `ObservableObject`/`@Published`).

**Key patterns:**

- `DownloadSessionDelegate` is a separate `NSObject : URLSessionDownloadDelegate` that bridges background queue callbacks to `DownloadManager` via `Task { @MainActor in … }`. Never merge it back into `DownloadManager`.
- Download task state is tracked in two dictionaries in `DownloadManager`: `activeTasks: [UUID: URLSessionDownloadTask]` and `taskToDownload: [Int: UUID]` (reverse lookup). `DownloadItem` holds no task reference.
- Filename resolution: Content-Disposition header → URL last component → UUID, with deduplication (` (2)`, ` (3)`, …) and sanitization against path traversal.
- `URLValidator.videoExtensions` is the canonical list of supported extensions used by both the validator and `LibraryManager`.
- App Sandbox is enabled (`swiftdl.entitlements`): requires `user-selected.read-write` for file access and `network.client` for downloads.

**Data flow summary:**
1. User pastes URL → `URLValidator` checks format → `DownloadManager.startDownload(from:to:)`
2. URLSession callbacks → `DownloadSessionDelegate` (background) → dispatched to `DownloadManager` (`@MainActor`)
3. On completion: temp file moved, `LibraryManager.scanFolder()` called to refresh library

**Settings lifecycle:** first launch shows a sheet prompting folder selection; bookmark resolved on subsequent launches; `stopAccess()` called on termination.

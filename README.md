# URLSafeClipboard

URLSafeClipboard is a macOS menu bar app (Swift/SwiftUI) that watches the clipboard and neutralizes tracking parameters from copied URLs.

It uses:
- Remote TXT rules from:
  - `https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/privacy-removeparam.txt`
- Remote JSON rules from:
  - `https://gitlab.com/ClearURLs/rules/-/raw/master/data.min.json`
- Local `assets/` as fallback backup sources when remote fetch/cached copies are unavailable.

Clipboard content is kept in memory only. The app never writes clipboard history or raw clipboard URLs to disk.

## Features

- Menu bar app with no Dock icon (`LSUIElement`)
- Active/Paused toggle and Quit menu actions
- Replace Mode toggle (`r`) to set matched params to `null` instead of removing them
- Manual `Refetch rules` action in menu
- Status icon changes based on Active vs Paused
- Clipboard polling every 200ms, fully stopped while paused
- Debounced processing to avoid rewrite loops when copy events happen quickly
- Clipboard deduplication via in-memory SHA-256 hash (no raw URL persistence for duplicate checks)
- Remote rules fetch behavior:
  - Automatically refetches on launch when parsed cache is missing
  - Manual refetch from menu at any time
  - Fallback order: remote fetch -> cached raw rules -> bundled `assets/`
- URL cleaning with:
  - Global query parameter matching from TXT rules
  - Domain/provider-specific matching from JSON rules
  - Exact and regex query parameter matching
  - Two actions for matched params:
    - Remove mode (default): drop matched params
    - Replace mode: force matched params to `name=null`
- Optional parsed-rule disk cache (no clipboard content), stored at:
  - `~/Library/Caches/URLSafeClipboard/parsedRules.json`
- Optional cached raw remote rules:
  - `~/Library/Caches/URLSafeClipboard/privacy-removeparam.txt`
  - `~/Library/Caches/URLSafeClipboard/data.min.json`
- Optional error log:
  - `~/Library/Caches/URLSafeClipboard/error.txt`

## Project Structure

```text
.
├── assets
│   ├── data.min.json
│   └── privacy-removeparam.txt
├── scripts
│   └── build-app.sh
├── Sources
│   └── URLSafeClipboard
│       ├── AppDelegate.swift
│       ├── AppState.swift
│       ├── ClipboardWatcher.swift
│       ├── URLCleaner.swift
│       └── URLSafeClipboardApp.swift
├── Package.swift
└── URLSafeClipboard-Info.plist
```

## Requirements

- macOS 13+
- Xcode Command Line Tools installed (`xcode-select --install`)

## Build And Run (Development)

From the repository root:

```bash
swift run URLSafeClipboard
```

## Build Drag-And-Drop `.app`

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
```

Output:

```text
dist/URLSafeClipboard.app
```

You can drag this app into `Applications` and launch it.

## Optional xcodebuild Build (Package)

```bash
xcodebuild -scheme URLSafeClipboard -configuration Release -destination "platform=macOS" build
```

## Behavior Notes

- Non-URL clipboard strings are ignored.
- Malformed URLs are ignored safely.
- Only `http` and `https` URLs are cleaned.
- When paused, clipboard polling is fully stopped.
- Last copied URL is not displayed in the UI.
- Duplicate detection uses an in-memory hash only.
- Rules are loaded into memory; cache is only for parsed rules and is overwritten on source updates.

## Future Extension Hooks

- AMP URL unwrapping
- Redirect URL extraction/decoding
- Expanded regex transformations for path-level cleanup

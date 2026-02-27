# URLSafeClipboard

URLSafeClipboard is a macOS menu bar app (Swift/SwiftUI) that neutralizes tracking parameters in copied URLs.

Privacy model:
- Clipboard content is never written to disk.
- Duplicate detection uses an in-memory SHA-256 hash only.
- Only rule files are cached.

## Rule Model

The app now consumes a single parsed file:
- `assets/parsedRules.json`

Schema:
- `generalExact`: global exact query-parameter names
- `generalRegex`: global regex query-parameter patterns
- `providers[]`:
  - `name`
  - `urlPattern` (regex to match URL)
  - `exactParams`
  - `regexParams`

## Update Flow

### 1. Generate Parsed Rules (`./create-rules`)

`./create-rules` fetches upstream rule sources and writes `assets/parsedRules.json`.

Upstream sources:
- TXT: `https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/privacy-removeparam.txt`
- JSON: `https://gitlab.com/ClearURLs/rules/-/raw/master/data.min.json`

Usage:

```bash
./create-rules
```

Offline/local fallback generation:

```bash
./create-rules --offline
```

### 2. App Startup Loading

At startup, app rule loading order is:
1. `~/Library/Caches/URLSafeClipboard/parsedRules.json`
2. Bundled `assets/parsedRules.json`

If cache is missing, startup triggers an async repo refetch attempt.

### 3. Refetch Rules

Menu action: `Refetch rules`
- Fetches only one file from your repo (`parsedRules.json`)
- Updates in-memory rules and cache on success
- Falls back to cache/bundled rules on failure

Configure repo URL via:
- Info.plist key: `URLSafeClipboardParsedRulesURL`
- Or env override: `URLSAFECLIPBOARD_RULES_URL`

## Build App

```bash
./scripts/build-app.sh
```

Output:
- `dist/URLSafeClipboard.app`

Notes:
- Uses `assets/logo.png` to generate and embed `AppIcon.icns`
- Bundles `assets/` into app resources

## Build DMG Installer

```bash
./build-dmg.sh
```

Output:
- `dist/URLSafeClipboard.dmg`

Installer behavior:
- Drag-and-drop layout (`URLSafeClipboard.app` + `Applications` link)
- Includes background image from `assets/background.tiff` (Finder layout step is best-effort)
- Ad-hoc signs app and DMG by default

Optional signing identity:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build-dmg.sh
```

## Run In Development

```bash
swift run URLSafeClipboard
```

## Cache Files

- Rules cache: `~/Library/Caches/URLSafeClipboard/parsedRules.json`
- Optional error log: `~/Library/Caches/URLSafeClipboard/error.txt`

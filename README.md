# PurePaste

PurePaste is a tiny macOS menu bar app that tries to clean tracking junk from links you copy.

It is practical, not perfect. Some links clean nicely, some do not, and a few sites may still behave oddly.

## Install in 3 steps

1. Build the installer:
   ```bash
   ./scripts/build-dmg.sh
   ```
2. Open `./PurePaste.dmg`.
3. Drag `PurePaste.app` to `Applications`.

That is it.

## Daily use

- Click the menu bar icon to open the menu.
- `Pause` stops all clipboard polling.
- `Activate` starts it again.
- `Replace params` changes tracking values to `null` instead of removing them.
- `Refetch rules` reloads the latest rules file from the repo.

## Create a release (maintainers)

1. Update the `VERSION` value in `./scripts/release.sh`.
2. Make sure you are logged into GitHub CLI:
   ```bash
   gh auth login
   ```
3. Run:
   ```bash
   ./scripts/release.sh
   ```

This script builds `PurePaste.dmg`, tags `vX.Y.Z`, and creates a GitHub release with generated notes.

## For nerds

- App source lives in `./source`.
- Rules are loaded from `assets/parsedRules.json` and cached at:
  - `~/Library/Caches/PurePaste/parsedRules.json`
- One-time migration is supported from the old cache path:
  - `~/Library/Caches/URLSafeClipboard/parsedRules.json`
- Rules URL override:
  - env: `PUREPASTE_RULES_URL`
  - plist key: `PurePasteParsedRulesURL`
- Build command used by script:
  - `swift build -c release --product PurePaste`

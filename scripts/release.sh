#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"
APP_NAME="PurePaste"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="v${VERSION}"
DMG_PATH="$ROOT_DIR/${APP_NAME}.dmg"
RULES_PATH="$ROOT_DIR/assets/parsedRules.json"

cd "$ROOT_DIR"

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: GitHub CLI (gh) is not installed."
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "Error: git is required."
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "Error: gh is not authenticated. Run: gh auth login"
  exit 1
fi

current_branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "${ALLOW_NON_MAIN:-0}" != "1" && "$current_branch" != "main" ]]; then
  echo "Error: current branch is '$current_branch'. Switch to 'main' or set ALLOW_NON_MAIN=1."
  exit 1
fi

origin_url="$(git remote get-url origin)"
if [[ "$origin_url" != *"github.com"* ]]; then
  echo "Error: origin remote is not GitHub: $origin_url"
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Error: working tree is not clean. Commit or stash changes first."
  exit 1
fi

if [[ ! -f "$RULES_PATH" ]]; then
  echo "Error: missing $RULES_PATH"
  exit 1
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "Error: tag $TAG already exists locally."
  exit 1
fi

if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  echo "Error: tag $TAG already exists on origin."
  exit 1
fi

echo "Building DMG for release $TAG..."
"$ROOT_DIR/scripts/build-dmg.sh"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "Error: expected DMG not found at $DMG_PATH"
  exit 1
fi

echo "Creating git tag $TAG..."
git tag -a "$TAG" -m "$APP_NAME $TAG"
git push origin "$TAG"

echo "Creating GitHub release $TAG..."
set +e
gh release create "$TAG" "$DMG_PATH" \
  --title "$APP_NAME $TAG" \
  --generate-notes
release_exit=$?
set -e

if [[ $release_exit -ne 0 ]]; then
  echo "Release upload failed after tag push."
  echo "Recovery: gh release create '$TAG' '$DMG_PATH' --title '$APP_NAME $TAG' --generate-notes"
  exit $release_exit
fi

echo "Release created: $TAG"

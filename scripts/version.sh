#!/usr/bin/env bash
#
# version.sh — bump the SwiftDrop project version across all manifests.
#
# Invoked by the "Auto Bump Versions" workflow when a maintainer comments
# /version <level> on a pull request. Reads the current version from the
# VERSION file, applies a semver bump, and writes the result back to VERSION
# and frontend/package.json.
#
#   ./version.sh -u -l minor     # bump minor, write changes to disk
#   ./version.sh -n -l patch     # dry-run, print the next version only
#
set -euo pipefail

LEVEL="patch"
UPDATE=false
DRY_RUN=false

usage() {
  echo "Usage: $0 [-u] [-n] [-l <major|minor|patch>]" >&2
  exit 1
}

while getopts "unl:" opt; do
  case "$opt" in
    u) UPDATE=true ;;
    n) DRY_RUN=true ;;
    l) LEVEL="$OPTARG" ;;
    *) usage ;;
  esac
done

VERSION_FILE="VERSION"
CURRENT="$(cat "$VERSION_FILE" 2>/dev/null || echo "0.1.0")"

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

case "$LEVEL" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
  *) echo "Unknown bump level: $LEVEL" >&2; usage ;;
esac

NEW="${MAJOR}.${MINOR}.${PATCH}"
echo "Bumping version: ${CURRENT} -> ${NEW} (${LEVEL})"

if [ "$DRY_RUN" = true ]; then
  echo "Dry run — no files changed."
  exit 0
fi

if [ "$UPDATE" = true ]; then
  echo "$NEW" > "$VERSION_FILE"
  if [ -f frontend/package.json ]; then
    sed -i -E "s/\"version\": \"[0-9]+\.[0-9]+\.[0-9]+\"/\"version\": \"${NEW}\"/" frontend/package.json
  fi
  echo "Updated VERSION and frontend/package.json to ${NEW}"
fi

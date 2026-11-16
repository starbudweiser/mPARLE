#!/bin/zsh
# Publie une version : compile, notarise (Apple), zippe puis crée la release GitHub.
# Usage : ./release.sh [notes]   — la version vient de CFBundleShortVersionString (Resources/Info.plist).
set -euo pipefail
cd "$(dirname "$0")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
TAG="v$VERSION"
DIST="$PWD/dist"
NOTES="${1:-mPARLE $VERSION}"
git diff --quiet && git diff --cached --quiet || { echo "Modifications non commitées : commiter avant la release." >&2; exit 1; }
! git rev-parse "$TAG" >/dev/null 2>&1 || { echo "La version $TAG existe déjà." >&2; exit 1; }

NO_INSTALL=1 ./build_app.sh
rm -rf "$DIST"
DIST="$DIST" /Volumes/SKYRIM/TOOLS/MAC/_tools/notarize_app.sh mPARLE.app
ZIP="$DIST/mPARLE-$VERSION.zip"
mv "$DIST/mPARLE.zip" "$ZIP"

git tag "$TAG" && git push -q origin "$TAG"
gh release create "$TAG" "$ZIP" --title "mPARLE $VERSION" --notes "$NOTES"

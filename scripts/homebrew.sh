#!/bin/bash
# Fills the Homebrew templates with a release's version and checksums.
# Usage: [SIGNED=true] scripts/homebrew.sh <version> [path/to/SHA256SUMS.txt]
# Without a path, SHA256SUMS.txt is downloaded from the GitHub release.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?usage: scripts/homebrew.sh <version> [SHA256SUMS.txt]}
VERSION=${VERSION#v}
SUMS=${2:-}
if [[ -z "$SUMS" ]]; then
    SUMS=$(mktemp)
    curl -fsSL "https://github.com/08820048/hush/releases/download/v$VERSION/SHA256SUMS.txt" -o "$SUMS"
fi

APP_SHA=$(awk -v f="Hush-$VERSION.zip" '$2 ~ f {print $1}' "$SUMS")
CLI_SHA=$(awk -v f="hush-cli-$VERSION.zip" '$2 ~ f {print $1}' "$SUMS")
[[ -n "$APP_SHA" && -n "$CLI_SHA" ]] || { echo "error: checksums for $VERSION not found in $SUMS" >&2; exit 1; }

OUT=packaging/homebrew/out
mkdir -p "$OUT"
sed -e "s/{{VERSION}}/$VERSION/g" -e "s/{{APP_SHA256}}/$APP_SHA/g" packaging/homebrew/hush.rb.template > "$OUT/hush.rb"
# Signed and notarized builds open without warnings, so drop the "not signed yet" caveat.
if [[ "${SIGNED:-false}" == true ]]; then
    perl -0pi -e 's/\n\n  caveats <<~EOS.*?\n  EOS\n/\n/s' "$OUT/hush.rb"
fi
sed -e "s/{{VERSION}}/$VERSION/g" -e "s/{{CLI_SHA256}}/$CLI_SHA/g" packaging/homebrew/hush-cli.rb.template > "$OUT/hush-cli.rb"
echo "Wrote $OUT/hush.rb and $OUT/hush-cli.rb"

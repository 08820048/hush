#!/bin/bash
# Verifies that the app and the CLI both carry the expected version.
# Usage: scripts/check-version.sh <version>
set -euo pipefail
cd "$(dirname "$0")/.."

EXPECTED=${1:?usage: scripts/check-version.sh <version>}
EXPECTED=${EXPECTED#v}
APP=$(awk '/^    MARKETING_VERSION:/ {print $2; exit}' App/project.yml)
CLI=$(sed -nE 's/^        version: "([^"]*)",/\1/p' Sources/hush/Hush.swift | head -1)

echo "expected: $EXPECTED   app (App/project.yml): $APP   cli (Sources/hush/Hush.swift): $CLI"
if [[ "$APP" != "$EXPECTED" || "$CLI" != "$EXPECTED" ]]; then
    echo "error: version mismatch. Run: scripts/bump-version.sh $EXPECTED" >&2
    exit 1
fi

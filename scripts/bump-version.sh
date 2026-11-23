#!/bin/bash
# Sets the version everywhere it is defined, so the release workflow's check passes.
# Usage: scripts/bump-version.sh 0.2.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?usage: scripts/bump-version.sh <version, e.g. 0.2.0 or 0.2.0-beta.1>}
VERSION=${VERSION#v}
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || { echo "error: '$VERSION' is not a version like 1.2.3 or 1.2.3-beta.1" >&2; exit 1; }

/usr/bin/sed -i '' -E "s/^(    MARKETING_VERSION: ).*/\1$VERSION/" App/project.yml
/usr/bin/sed -i '' -E "s/^(        version: \")[^\"]*(\",)/\1$VERSION\2/" Sources/hush/Hush.swift

scripts/check-version.sh "$VERSION"
cat <<MSG

Next:
  git commit -am "chore: release v$VERSION"
  git tag v$VERSION
  git push origin main v$VERSION
MSG

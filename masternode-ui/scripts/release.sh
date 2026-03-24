#!/bin/bash
# TPIX Master Node — Release Script
# Usage: ./scripts/release.sh 1.0.1
#
# This script:
# 1. Bumps version in package.json
# 2. Commits the version bump
# 3. Creates a git tag
# 4. Pushes to xjanova/TPIX-Coin
# 5. GitHub Actions will build & publish the release automatically
#
# Prerequisites:
# - Git remote 'origin' points to xjanova/TPIX-Coin
# - GitHub Actions workflow is set up (.github/workflows/release.yml)

set -e

VERSION=$1

if [ -z "$VERSION" ]; then
    echo "Usage: ./scripts/release.sh <version>"
    echo "Example: ./scripts/release.sh 1.0.1"
    exit 1
fi

# Validate semver format
if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "Error: Version must be in semver format (e.g., 1.0.1)"
    exit 1
fi

echo "=== TPIX Master Node Release v${VERSION} ==="
echo ""

# 1. Update version in package.json
cd "$(dirname "$0")/.."
echo "Updating package.json version to ${VERSION}..."
npm version "$VERSION" --no-git-tag-version

# 2. Also update version in renderer.js
echo "Updating renderer.js appVersion..."
sed -i "s/const appVersion = '[^']*'/const appVersion = '${VERSION}'/" src/renderer.js

# 3. Commit
echo "Committing version bump..."
git add package.json package-lock.json src/renderer.js
git commit -m "chore: release v${VERSION} — TPIX Master Node"

# 4. Tag
echo "Creating tag v${VERSION}..."
git tag "v${VERSION}"

# 5. Push
echo "Pushing to origin..."
git push origin main
git push origin "v${VERSION}"

echo ""
echo "=== Release v${VERSION} triggered! ==="
echo "GitHub Actions will build and publish the release."
echo "Monitor: https://github.com/xjanova/TPIX-Coin/actions"
echo ""
echo "After build completes, users will see the update notification automatically."

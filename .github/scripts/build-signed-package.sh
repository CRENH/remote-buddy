#!/bin/bash
# Build the CRENH installer with the fixed signing identity (see FORK.md).
# Needs release-signing.p12 and password.txt in ~/Library/Application Support/RemoteBuddySigning/.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
metadata="$(scripts/release-metadata.sh)"
while IFS='=' read -r key value; do
    export "$key=$value"
done <<< "$metadata"
source scripts/architecture.sh
# Builds and signs the app and driver, then checks them against the pinned certificate.
python3 scripts/build-local-signed.py --configuration release
scripts/build-release-package.sh
scripts/verify-release-package.sh
echo "Package: $root/dist/release/Remote_Buddy_${RELEASE_TAG}_macOS_${RELEASE_ARCH_LABEL}.pkg"

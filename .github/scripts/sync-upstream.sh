#!/usr/bin/env bash
# Merges upstream main into the checked-out fork branch and pushes it.
# Writes result=up-to-date|merged|conflict and upstream_sha to $GITHUB_OUTPUT.
# On conflict the merge is aborted, nothing is pushed, and the conflicting
# paths are listed one per line in $CONFLICTS_FILE.
set -euo pipefail

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/zfdang/remote-buddy.git}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"
TARGET_BRANCH="${TARGET_BRANCH:-crenh}"
if [[ -z "${CONFLICTS_FILE:-}" ]]; then
    if [[ -n "${RUNNER_TEMP:-}" ]]; then
        CONFLICTS_FILE="$RUNNER_TEMP/sync-conflicts.txt"
    else
        CONFLICTS_FILE="$(mktemp)"
    fi
fi

emit() {
    echo "$1"
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "$1" >> "$GITHUB_OUTPUT"
    fi
}

git fetch --no-tags "$UPSTREAM_URL" "$UPSTREAM_BRANCH"
upstream_sha="$(git rev-parse FETCH_HEAD)"
emit "upstream_sha=$upstream_sha"

if git merge-base --is-ancestor "$upstream_sha" HEAD; then
    emit "result=up-to-date"
    exit 0
fi

message="Merge upstream $UPSTREAM_BRANCH (${upstream_sha:0:7}) into $TARGET_BRANCH"
if git merge --no-ff --no-edit -m "$message" "$upstream_sha"; then
    git push origin "HEAD:$TARGET_BRANCH"
    emit "result=merged"
    exit 0
fi

git diff --name-only --diff-filter=U > "$CONFLICTS_FILE"
git merge --abort
emit "conflicts_file=$CONFLICTS_FILE"
emit "result=conflict"

#!/usr/bin/env bash
# Exercises sync-upstream.sh against throwaway local repositories.
# Run with: bash .github/scripts/test-sync-upstream.sh
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/sync-upstream.sh"
failures=0

fail() {
    echo "FAIL: $*"
    failures=$((failures + 1))
}

expect_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" != "$actual" ]]; then
        fail "$label: expected '$expected', got '$actual'"
    fi
}

output_value() {
    grep "^$1=" "$2" | tail -1 | cut -d= -f2-
}

commit_file() {
    local repo="$1" file="$2" content="$3"
    printf '%s\n' "$content" > "$repo/$file"
    git -C "$repo" add "$file"
    git -C "$repo" commit -q -m "edit $file"
}

# Creates upstream, origin.git and a work clone on crenh under $1.
setup() {
    local root="$1"
    git init -q -b main "$root/upstream"
    git -C "$root/upstream" config user.name Test
    git -C "$root/upstream" config user.email test@example.com
    commit_file "$root/upstream" a.txt base
    commit_file "$root/upstream" shared.txt base

    git clone -q --bare "$root/upstream" "$root/origin.git"
    git -C "$root/origin.git" branch crenh main
    git clone -q -b crenh "$root/origin.git" "$root/work"
    git -C "$root/work" config user.name Test
    git -C "$root/work" config user.email test@example.com
}

run_sync() {
    local root="$1"
    : > "$root/output"
    (
        cd "$root/work"
        UPSTREAM_URL="$root/upstream" GITHUB_OUTPUT="$root/output" \
            CONFLICTS_FILE="$root/conflicts" bash "$SCRIPT" > "$root/log" 2>&1
    )
}

origin_crenh() {
    git -C "$1/origin.git" rev-parse crenh
}

scenario_up_to_date() {
    local root before
    root="$(mktemp -d)"
    setup "$root"
    before="$(origin_crenh "$root")"
    run_sync "$root" || fail "up-to-date: script exited non-zero ($(cat "$root/log"))"
    expect_eq "up-to-date result" up-to-date "$(output_value result "$root/output")"
    expect_eq "up-to-date origin unchanged" "$before" "$(origin_crenh "$root")"
    rm -rf "$root"
}

scenario_merged() {
    local root before upstream_head after
    root="$(mktemp -d)"
    setup "$root"
    commit_file "$root/work" b.txt fork
    git -C "$root/work" push -q origin crenh
    commit_file "$root/upstream" a.txt upstream-change
    before="$(origin_crenh "$root")"
    upstream_head="$(git -C "$root/upstream" rev-parse HEAD)"
    run_sync "$root" || fail "merged: script exited non-zero ($(cat "$root/log"))"
    after="$(origin_crenh "$root")"
    expect_eq "merged result" merged "$(output_value result "$root/output")"
    expect_eq "merged upstream_sha" "$upstream_head" "$(output_value upstream_sha "$root/output")"
    expect_eq "merged first parent" "$before" "$(git -C "$root/origin.git" rev-parse "$after^1")"
    expect_eq "merged second parent" "$upstream_head" "$(git -C "$root/origin.git" rev-parse "$after^2")"
    rm -rf "$root"
}

scenario_conflict() {
    local root before
    root="$(mktemp -d)"
    setup "$root"
    commit_file "$root/work" shared.txt fork-line
    git -C "$root/work" push -q origin crenh
    commit_file "$root/upstream" shared.txt upstream-line
    before="$(origin_crenh "$root")"
    run_sync "$root" || fail "conflict: script exited non-zero ($(cat "$root/log"))"
    expect_eq "conflict result" conflict "$(output_value result "$root/output")"
    expect_eq "conflict files" shared.txt "$(cat "$root/conflicts")"
    expect_eq "conflict conflicts_file" "$root/conflicts" "$(output_value conflicts_file "$root/output")"
    expect_eq "conflict origin unchanged" "$before" "$(origin_crenh "$root")"
    [[ ! -e "$root/work/.git/MERGE_HEAD" ]] || fail "conflict: MERGE_HEAD left behind"
    expect_eq "conflict clean tree" "" "$(git -C "$root/work" status --porcelain)"
    rm -rf "$root"
}

scenario_up_to_date
scenario_merged
scenario_conflict

if (( failures > 0 )); then
    echo "$failures check(s) failed"
    exit 1
fi
echo "ALL PASS"

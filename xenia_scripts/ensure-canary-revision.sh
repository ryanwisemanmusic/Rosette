#!/usr/bin/env bash
# Keep this checkout on the exact Canary commit used by Rosette's integration.
# The custom macos/ directory is untracked by upstream; refuse any target that
# would claim that path, and never clean untracked files during the switch.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
revision_file="${script_dir}/CANARY_REVISION"

[[ -r "$revision_file" ]] || { echo "Missing pinned Canary revision: $revision_file" >&2; exit 2; }
expected="$(tr -d '[:space:]' < "$revision_file")"
[[ "$expected" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid pinned Canary commit in $revision_file" >&2; exit 2; }

git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Not a Git worktree: $repo_root" >&2
    exit 2
}

if ! git -C "$repo_root" cat-file -e "${expected}^{commit}" 2>/dev/null; then
    git -C "$repo_root" fetch --no-tags origin canary_experimental || {
        echo "Could not fetch the pinned Canary commit from origin/canary_experimental" >&2
        exit 2
    }
fi
git -C "$repo_root" cat-file -e "${expected}^{commit}" 2>/dev/null || {
    echo "Pinned Canary commit is unavailable: $expected" >&2
    exit 2
}

# The local macos/ workflow is intentionally preserved across revision changes.
if git -C "$repo_root" ls-tree -r --name-only "$expected" -- macos | grep -q .; then
    echo "Pinned commit contains macos/ files; refusing a switch that could replace the local workflow" >&2
    exit 2
fi

current="$(git -C "$repo_root" rev-parse HEAD)"
if [[ "$current" != "$expected" ]]; then
    if ! git -C "$repo_root" diff --quiet --; then
        echo "Tracked worktree changes prevent pinning; save them before running this build" >&2
        exit 2
    fi
    if ! git -C "$repo_root" diff --cached --quiet --; then
        echo "Staged changes prevent pinning; save them before running this build" >&2
        exit 2
    fi
    echo "Switching Canary checkout from $current to pinned commit $expected"
    git -C "$repo_root" switch --detach "$expected"
fi

actual="$(git -C "$repo_root" rev-parse HEAD)"
[[ "$actual" == "$expected" ]] || { echo "Canary pin verification failed: expected $expected, found $actual" >&2; exit 2; }
printf 'Canary revision verified: %s\n' "$actual"

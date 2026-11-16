#!/usr/bin/env bash
set -euo pipefail
state_dir="${HERMES_WRITING_STATE:?HERMES_WRITING_STATE is not set}"
worktree="${HERMES_WRITING_WORKTREE:?HERMES_WRITING_WORKTREE is not set}"
branch="${HERMES_WRITING_BRANCH:?HERMES_WRITING_BRANCH is not set}"
repo="${HERMES_WRITING_REPO:?HERMES_WRITING_REPO is not set}"
git_bin="${HERMES_GIT_BIN:-git}"
mountpoint -q "${HERMES_STORAGE_MOUNT:?HERMES_STORAGE_MOUNT is not set}" || { echo 'writing storage is not mounted' >&2; exit 1; }
[[ -d "$state_dir" && -w "$state_dir" ]] || { echo "Hermes state is not ready: $state_dir" >&2; exit 1; }
[[ -d "$worktree" ]] || { echo "Hermes worktree is not prepared: $worktree" >&2; exit 1; }
[[ "$("$git_bin" -C "$worktree" branch --show-current)" = "$branch" ]] || { echo "Hermes worktree branch is not ready" >&2; exit 1; }
repo_common=$("$git_bin" -C "$repo" rev-parse --git-common-dir)
worktree_common=$("$git_bin" -C "$worktree" rev-parse --git-common-dir)
[[ "$repo_common" = /* ]] || repo_common="$repo/$repo_common"
[[ "$worktree_common" = /* ]] || worktree_common="$worktree/$worktree_common"
[[ "$(realpath "$repo_common")" = "$(realpath "$worktree_common")" ]] || {
  echo 'Hermes worktree belongs to a different Git repository' >&2
  exit 1
}

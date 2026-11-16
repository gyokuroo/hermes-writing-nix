#!/usr/bin/env bash
set -euo pipefail
state_dir="${HERMES_WRITING_STATE:?HERMES_WRITING_STATE is not set}"
worktree="${HERMES_WRITING_WORKTREE:?HERMES_WRITING_WORKTREE is not set}"
branch="${HERMES_WRITING_BRANCH:?HERMES_WRITING_BRANCH is not set}"
repo="${1:-${HERMES_WRITING_REPO:?HERMES_WRITING_REPO is not set}}"
git_bin="${HERMES_GIT_BIN:-git}"
if [[ ! -d "$repo/.git" && ! -f "$repo/.git" ]]; then echo "repository is missing: $repo" >&2; exit 1; fi
if [[ -e "$worktree" ]]; then
  if [[ ! -d "$worktree/.git" && ! -f "$worktree/.git" ]]; then
    if [[ -n "$(find "$worktree" -mindepth 1 -print -quit)" ]]; then
      echo "refusing to replace existing path: $worktree" >&2
      exit 1
    fi
    rmdir "$worktree"
  fi
fi
if [[ ! -e "$worktree" ]]; then
  mkdir -p "$(dirname "$worktree")"
  if "$git_bin" -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    "$git_bin" -C "$repo" worktree add "$worktree" "$branch"
  else
    "$git_bin" -C "$repo" worktree add -b "$branch" "$worktree" HEAD
  fi
fi
if [[ "$("$git_bin" -C "$worktree" branch --show-current)" != "$branch" ]]; then
  echo "worktree is on an unexpected branch: $worktree" >&2
  exit 1
fi
repo_common=$("$git_bin" -C "$repo" rev-parse --git-common-dir)
worktree_common=$("$git_bin" -C "$worktree" rev-parse --git-common-dir)
[[ "$repo_common" = /* ]] || repo_common="$repo/$repo_common"
[[ "$worktree_common" = /* ]] || worktree_common="$worktree/$worktree_common"
if [[ "$(realpath "$repo_common")" != "$(realpath "$worktree_common")" ]]; then
  echo "worktree belongs to a different Git repository: $worktree" >&2
  exit 1
fi
mkdir -p "$state_dir/locks" "$worktree/progress"
template_dir="$state_dir/writing"
for file in .hermes.md workflow.md; do
  source="$template_dir/$file"
  destination="$worktree/$file"
  if [[ ! -e "$source" ]]; then
    echo "missing Hermes workspace template: $source" >&2
    exit 1
  fi
  if [[ -e "$destination" ]]; then
    if ! cmp -s "$source" "$destination"; then
      echo "refusing to replace existing workspace instruction: $destination" >&2
      exit 1
    fi
  else
    install -m 0600 "$source" "$destination"
  fi
done
for file in goal.md checkpoint.md questions.md; do
  if [[ ! -e "$worktree/progress/$file" ]]; then install -m 0600 /dev/null "$worktree/progress/$file"; fi
done
chmod 0700 "$state_dir" "$state_dir/locks"
chmod 0700 "$worktree"
echo "Hermes writing state is ready: $state_dir"
echo "Hermes writing worktree is ready: $worktree ($branch)"

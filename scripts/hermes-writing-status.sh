#!/usr/bin/env bash
set -euo pipefail
state_dir="${HERMES_WRITING_STATE:?HERMES_WRITING_STATE is not set}"
worktree="${HERMES_WRITING_WORKTREE:?HERMES_WRITING_WORKTREE is not set}"
git_bin="${HERMES_GIT_BIN:-git}"
printf 'state: %s\nworktree: %s\n' "$state_dir" "$worktree"
if [[ -d "$worktree/.git" || -f "$worktree/.git" ]]; then
  "$git_bin" -C "$worktree" status --short --branch
else
  echo "worktree: not prepared"
fi
for file in goal.md checkpoint.md questions.md; do
  if [[ -s "$worktree/progress/$file" ]]; then
    printf '\n--- %s ---\n' "$file"
    cat "$worktree/progress/$file"
  fi
done

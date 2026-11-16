#!/usr/bin/env bash
set -euo pipefail
state_dir="${HERMES_WRITING_STATE:?HERMES_WRITING_STATE is not set}"
worktree="${HERMES_WRITING_WORKTREE:?HERMES_WRITING_WORKTREE is not set}"
goal="$worktree/progress/goal.md"
job_name="${HERMES_WRITING_JOB_NAME:-hermes-writing}"
schedule="${HERMES_WRITING_SCHEDULE:-5m}"
workflow="$state_dir/writing/workflow.md"
prompt_file="$state_dir/writing/prompt.md"
ready="${HERMES_WRITING_READY:-hermes-writing-ready}"
hermes="${HERMES_BIN:-hermes}"
lock_runner="${HERMES_WRITING_LOCK_RUNNER:?HERMES_WRITING_LOCK_RUNNER is not set}"
"$ready"
[[ -s "$goal" ]] || { echo "writing goal is empty: $goal" >&2; exit 1; }
[[ -s "$prompt_file" ]] || { echo "writing prompt is missing: $prompt_file" >&2; exit 1; }
grep -Eiq '完了条件|completion[[:space:]]+criteria' "$goal" || {
  echo 'writing goal must include explicit completion criteria' >&2
  exit 1
}
prompt="$(cat "$prompt_file")
Read $workflow and $goal. Work only in $worktree. Complete one scene-sized checkpoint, record progress, and stop when the goal's completion criteria are met."
exec python3 "$lock_runner" cron-start "$hermes" "$job_name" "$schedule" "$prompt"

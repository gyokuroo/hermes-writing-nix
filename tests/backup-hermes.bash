#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
helper="$script_dir/../packages/backup-hermes.sh"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

source_dir="$tmp/novel"
worktree_dir="$tmp/worktrees/hermes"
hermes_home="$tmp/hermes"
backup_dir="$tmp/backup"
mkdir -p "$source_dir" "$worktree_dir" "$hermes_home" "$backup_dir"
printf 'draft\n' > "$source_dir/chapter.md"
printf 'proposal\n' > "$worktree_dir/proposal.md"
git -C "$source_dir" init -q

cat > "$hermes_home/gateway_state.json" <<JSON
{"gateway_state":"running","pid":$$,"active_agents":0,"active_work":[]}
JSON
sqlite3 "$hermes_home/state.db" 'CREATE TABLE state (value TEXT); INSERT INTO state VALUES ("private");'
mkdir -p "$hermes_home/cron" "$hermes_home/sessions" "$hermes_home/memories" "$hermes_home/skills"
printf '{"jobs":[]}\n' > "$hermes_home/cron/jobs.json"
printf 'conversation\n' > "$hermes_home/sessions/one.json"
printf 'memory\n' > "$hermes_home/memories/facts.json"
printf 'skill\n' > "$hermes_home/skills/writing.md"
printf 'secret\n' > "$hermes_home/auth.json"
printf 'secret\n' > "$hermes_home/.env"
mkdir -p "$hermes_home/mcp-tokens"
printf 'secret\n' > "$hermes_home/mcp-tokens/discord"
printf 'secret\n' > "$hermes_home/provider.oauth.json"

fake_bin="$tmp/bin"
mkdir -p "$fake_bin"
cat > "$fake_bin/hermes" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$HERMES_CALL_LOG"
case "$*" in
  pause\ --reason\ *) : > "$HERMES_HOME/ESTOP" ;;
  resume) rm -f "$HERMES_HOME/ESTOP" ;;
  gateway\ stop) jq '.gateway_state="stopped" | .pid=0' "$HERMES_HOME/gateway_state.json" > "$HERMES_HOME/gateway_state.json.tmp"; mv "$HERMES_HOME/gateway_state.json.tmp" "$HERMES_HOME/gateway_state.json" ;;
  gateway\ start) jq '.gateway_state="running" | .pid=1' "$HERMES_HOME/gateway_state.json" > "$HERMES_HOME/gateway_state.json.tmp"; mv "$HERMES_HOME/gateway_state.json.tmp" "$HERMES_HOME/gateway_state.json" ;;
esac
SH
chmod +x "$fake_bin/hermes"

export HERMES_HOME="$hermes_home"
export HERMES_CALL_LOG="$tmp/calls"
export HERMES_BIN="$fake_bin/hermes"
export JQ_BIN=jq
export FUSER_BIN=false
export FLOCK_BIN=true

"$helper" \
  --source-dir "$source_dir" \
  --worktree-dir "$worktree_dir" \
  --hermes-home "$hermes_home" \
  --backup-dir "$backup_dir" \
  --generations 14 \
  --skip-mount-check \
  --bare-repo-dir "$tmp/missing.git"

latest=$(find "$backup_dir" -mindepth 1 -maxdepth 1 -type d -name '20*' -print -quit)
test -f "$latest/novel/chapter.md"
test -f "$latest/worktrees/hermes/proposal.md"
test -f "$latest/hermes/state.db"
test -f "$latest/hermes/cron/jobs.json"
test -f "$latest/hermes/sessions/one.json"
test -f "$latest/hermes/memories/facts.json"
test -f "$latest/hermes/skills/writing.md"
test ! -e "$latest/hermes/gateway_state.json"
test ! -e "$latest/hermes/auth.json"
test ! -e "$latest/hermes/.env"
test ! -e "$latest/hermes/mcp-tokens"
test ! -e "$latest/hermes/provider.oauth.json"
mode=$(stat -c %a "$latest" 2>/dev/null || stat -f %Lp "$latest")
test "$mode" = 700
grep -qx 'pause --reason writing-backup' "$HERMES_CALL_LOG"
grep -qx 'gateway stop' "$HERMES_CALL_LOG"
grep -qx 'gateway start' "$HERMES_CALL_LOG"
grep -qx 'resume' "$HERMES_CALL_LOG"

rm -rf "$backup_dir"/*
cat > "$hermes_home/gateway_state.json" <<'JSON'
{"gateway_state":"unknown","pid":1,"active_agents":0,"active_work":[]}
JSON
if "$helper" \
  --source-dir "$source_dir" \
  --worktree-dir "$worktree_dir" \
  --hermes-home "$hermes_home" \
  --backup-dir "$backup_dir" \
  --generations 14 \
  --skip-mount-check \
  --bare-repo-dir "$tmp/missing.git"; then
  echo 'expected unknown gateway state failure' >&2
  exit 1
fi
test -z "$(find "$backup_dir" -mindepth 1 -maxdepth 1 -type d -name '20*' -print -quit)"

rm -f "$HERMES_CALL_LOG"
touch "$hermes_home/ESTOP"
cat > "$hermes_home/gateway_state.json" <<JSON
{"gateway_state":"running","pid":$$,"active_agents":0,"active_work":[]}
JSON
"$helper" \
  --source-dir "$source_dir" \
  --worktree-dir "$worktree_dir" \
  --hermes-home "$hermes_home" \
  --backup-dir "$backup_dir" \
  --generations 14 \
  --skip-mount-check \
  --bare-repo-dir "$tmp/missing.git"
! grep -qx 'pause --reason writing-backup' "$HERMES_CALL_LOG"
! grep -qx 'resume' "$HERMES_CALL_LOG"
rm -f "$hermes_home/ESTOP"

rm -rf "$backup_dir"/*
sqlite3 "$hermes_home/cron/executions.db" 'CREATE TABLE executions (status TEXT); INSERT INTO executions VALUES ("running");'
cat > "$hermes_home/gateway_state.json" <<'JSON'
{"gateway_state":"stopped","pid":0,"active_agents":0,"active_work":[]}
JSON
if "$helper" \
  --source-dir "$source_dir" \
  --worktree-dir "$worktree_dir" \
  --hermes-home "$hermes_home" \
  --backup-dir "$backup_dir" \
  --generations 14 \
  --skip-mount-check \
  --bare-repo-dir "$tmp/missing.git"; then
  echo 'expected stopped gateway ledger failure' >&2
  exit 1
fi
test -z "$(find "$backup_dir" -mindepth 1 -maxdepth 1 -type d -name '20*' -print -quit)"
rm -f "$hermes_home/cron/executions.db"
rm -rf "$backup_dir"/*
cat > "$hermes_home/gateway_state.json" <<'JSON'
{"gateway_state":"stopped","pid":0,"active_agents":0,"active_work":[]}
JSON
if FUSER_BIN=true "$helper" \
  --source-dir "$source_dir" \
  --worktree-dir "$worktree_dir" \
  --hermes-home "$hermes_home" \
  --backup-dir "$backup_dir" \
  --generations 14 \
  --skip-mount-check \
  --bare-repo-dir "$tmp/missing.git"; then
  echo 'expected live database failure' >&2
  exit 1
fi
test -z "$(find "$backup_dir" -mindepth 1 -maxdepth 1 -type d -name '20*' -print -quit)"
printf 'committed WAL frame\n' > "$hermes_home/state.db-wal"
if "$helper" \
  --source-dir "$source_dir" \
  --worktree-dir "$worktree_dir" \
  --hermes-home "$hermes_home" \
  --backup-dir "$backup_dir" \
  --generations 14 \
  --skip-mount-check \
  --bare-repo-dir "$tmp/missing.git"; then
  echo 'expected non-empty WAL refusal' >&2
  exit 1
fi
test -z "$(find "$backup_dir" -mindepth 1 -maxdepth 1 -type d -name '20*' -print -quit)"
rm -f "$hermes_home/state.db-wal"

rm -rf "$backup_dir"/*
cat > "$tmp/fail-rsync" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$tmp/fail-rsync"
if RSYNC_BIN="$tmp/fail-rsync" "$helper" \
  --source-dir "$source_dir" \
  --worktree-dir "$worktree_dir" \
  --hermes-home "$hermes_home" \
  --backup-dir "$backup_dir" \
  --generations 14 \
  --skip-mount-check \
  --bare-repo-dir "$tmp/missing.git"; then
  echo 'expected rsync failure' >&2
  exit 1
fi
test -z "$(find "$backup_dir" -mindepth 1 -maxdepth 1 -type d -name '20*' -print -quit)"
test -z "$(find "$backup_dir" -mindepth 1 -maxdepth 1 -type d -name '.*.tmp.*' -print -quit)"

mkdir -p "$backup_dir/2000-old" "$backup_dir/2001-old"
touch -t 200001010000 "$backup_dir/2000-old" "$backup_dir/2001-old"
"$helper" \
  --source-dir "$source_dir" \
  --worktree-dir "$tmp/missing-worktree" \
  --hermes-home "$tmp/uninitialized-hermes" \
  --backup-dir "$backup_dir" \
  --generations 1 \
  --skip-mount-check \
  --bare-repo-dir "$tmp/missing.git"
test "$(find "$backup_dir" -mindepth 1 -maxdepth 1 -type d -name '200*' | wc -l | tr -d ' ')" = 0

rm -rf "$backup_dir"/*
mkdir -p "$tmp/uninitialized-hermes"
mkdir -p "$tmp/empty-worktree"
mkdir -p "$tmp/plain-source"
printf 'plain draft\n' > "$tmp/plain-source/chapter.md"
printf 'config\n' > "$tmp/uninitialized-hermes/config.yaml"
"$helper" \
  --source-dir "$tmp/plain-source" \
  --worktree-dir "$tmp/empty-worktree" \
  --hermes-home "$tmp/uninitialized-hermes" \
  --backup-dir "$tmp/backup with spaces" \
  --generations 14 \
  --skip-mount-check \
  --bare-repo-dir "$tmp/missing.git"
test -n "$(find "$tmp/backup with spaces" -mindepth 1 -maxdepth 1 -type d -name '20*' -print -quit)"

rm -rf "$backup_dir"/*
cat > "$hermes_home/gateway_state.json" <<JSON
{"gateway_state":"running","pid":$$,"active_agents":1,"active_work":[{"kind":"managed_worker"}]}
JSON
if HERMES_WAIT_SECONDS=0 "$helper" \
  --source-dir "$source_dir" \
  --worktree-dir "$worktree_dir" \
  --hermes-home "$hermes_home" \
  --backup-dir "$backup_dir" \
  --generations 14 \
  --skip-mount-check \
  --bare-repo-dir "$tmp/missing.git"; then
  echo 'expected active work timeout' >&2
  exit 1
fi
test -z "$(find "$backup_dir" -mindepth 1 -maxdepth 1 -type d -name '20*' -print -quit)"
test ! -e "$hermes_home/ESTOP"

cat > "$hermes_home/gateway_state.json" <<JSON
{"gateway_state":"running","pid":$$,"active_agents":0,"active_work":[{"kind":"external_worker"}]}
JSON
if HERMES_WAIT_SECONDS=0 "$helper" \
  --source-dir "$source_dir" \
  --worktree-dir "$worktree_dir" \
  --hermes-home "$hermes_home" \
  --backup-dir "$backup_dir" \
  --generations 14 \
  --skip-mount-check \
  --bare-repo-dir "$tmp/missing.git"; then
  echo 'expected running active work timeout' >&2
  exit 1
fi
test -z "$(find "$backup_dir" -mindepth 1 -maxdepth 1 -type d -name '20*' -print -quit)"
test ! -e "$hermes_home/ESTOP"

external_source="$tmp/external-source"
external_common="$tmp/external-common.git"
external_worktree="$tmp/external-worktree"
external_hermes="$tmp/external-hermes"
external_backup="$tmp/external-backup"
mkdir -p "$external_source" "$external_worktree" "$external_hermes" "$external_backup"
printf 'external draft\n' > "$external_source/chapter.md"
git -C "$external_source" init -q --separate-git-dir "$external_common"
printf 'config\n' > "$external_hermes/config.yaml"
if "$helper" \
  --source-dir "$external_source" \
  --worktree-dir "$external_worktree" \
  --hermes-home "$external_hermes" \
  --backup-dir "$external_backup" \
  --generations 14 \
  --skip-mount-check \
  --bare-repo-dir "$tmp/missing-external.git"; then
  echo 'expected external Git common directory refusal' >&2
  exit 1
fi
test -z "$(find "$external_backup" -mindepth 1 -maxdepth 1 -type d -name '20*' -print -quit)"

invalid_source="$tmp/invalid-git-source"
invalid_hermes="$tmp/invalid-git-hermes"
invalid_backup="$tmp/invalid-git-backup"
mkdir -p "$invalid_source" "$invalid_hermes" "$invalid_backup"
printf 'invalid\n' > "$invalid_source/chapter.md"
printf 'gitdir: /path/that/does/not/exist\n' > "$invalid_source/.git"
printf 'config\n' > "$invalid_hermes/config.yaml"
if "$helper" \
  --source-dir "$invalid_source" \
  --worktree-dir "$tmp/empty-invalid-worktree" \
  --hermes-home "$invalid_hermes" \
  --backup-dir "$invalid_backup" \
  --generations 14 \
  --skip-mount-check \
  --bare-repo-dir "$tmp/missing-invalid.git"; then
  echo 'expected invalid Git metadata refusal' >&2
  exit 1
fi
test -z "$(find "$invalid_backup" -mindepth 1 -maxdepth 1 -type d -name '20*' -print -quit)"

echo 'backup-hermes tests passed'

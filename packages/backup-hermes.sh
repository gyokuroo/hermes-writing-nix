#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 --source-dir DIR --worktree-dir DIR --hermes-home DIR --backup-dir DIR --generations N [--bare-repo-dir DIR] [--skip-mount-check]" >&2
  exit 2
}

source_dir=
worktree_dir=
hermes_home=
backup_root=
bare_repo_dir=/var/lib/git/novel.git
generations=14
skip_mount_check=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --source-dir) source_dir=${2:?}; shift 2 ;;
    --worktree-dir) worktree_dir=${2:?}; shift 2 ;;
    --hermes-home) hermes_home=${2:?}; shift 2 ;;
    --backup-dir) backup_root=${2:?}; shift 2 ;;
    --bare-repo-dir) bare_repo_dir=${2:?}; shift 2 ;;
    --generations) generations=${2:?}; shift 2 ;;
    --skip-mount-check) skip_mount_check=true; shift ;;
    *) usage ;;
  esac
done
[ -n "$source_dir" ] && [ -n "$worktree_dir" ] && [ -n "$hermes_home" ] && [ -n "$backup_root" ] || usage

JQ_BIN=${JQ_BIN:-jq}
FUSER_BIN=${FUSER_BIN:-fuser}
FLOCK_BIN=${FLOCK_BIN:-flock}
SQLITE_BIN=${SQLITE_BIN:-sqlite3}
STATE_MAX_AGE_SECONDS=${STATE_MAX_AGE_SECONDS:-120}
HERMES_BIN=${HERMES_BIN:-hermes}
WAIT_SECONDS=${HERMES_WAIT_SECONDS:-1800}
POLL_SECONDS=${HERMES_POLL_SECONDS:-5}
RSYNC_BIN=${RSYNC_BIN:-rsync}
GIT_BIN=${GIT_BIN:-git}

if ! "$skip_mount_check"; then
  mountpoint -q /mnt/sda1 && mountpoint -q /mnt/sdb1 || {
    echo 'writing backup: required storage is not mounted' >&2
    exit 1
  }
fi
[ -d "$source_dir" ] || { echo 'writing backup: source is missing' >&2; exit 1; }

mkdir -p "$backup_root"
exec 9>"$backup_root/.writing-backup.lock"
"$FLOCK_BIN" -n 9 || { echo 'writing backup: another backup is running' >&2; exit 1; }

state_file="$hermes_home/gateway_state.json"
hermes_initialized=false
if [ -f "$state_file" ]; then
  hermes_initialized=true
fi
if ! "$hermes_initialized" && { [ -e "$hermes_home/cron/executions.db" ] || [ -e "$hermes_home/cron/deliveries.db" ]; }; then
  echo 'writing backup: Hermes ledger exists without gateway_state.json' >&2
  exit 1
fi
if ! "$hermes_initialized" && [ -e "$hermes_home/gateway.pid" ]; then
  echo 'writing backup: Hermes gateway PID exists without gateway_state.json' >&2
  exit 1
fi

gateway_was_running=false
pause_was_set=false
pause_created=false
gateway_stopped=false
staging=
if "$hermes_initialized"; then
  [ -f "$state_file" ] || { echo 'writing backup: Hermes state is initialized but gateway_state.json is missing' >&2; exit 1; }
  gateway_state=$("$JQ_BIN" -er '.gateway_state // empty' "$state_file") || {
    echo 'writing backup: Hermes gateway state is unreadable' >&2; exit 1;
  }
  case "$gateway_state" in
    running|degraded|starting|draining)
      gateway_was_running=true
      gateway_pid=$("$JQ_BIN" -er '.pid // 0' "$state_file") || exit 1
      case "$gateway_pid" in ''|*[!0-9]*|0) echo 'writing backup: Hermes gateway PID is invalid' >&2; exit 1 ;; esac
      kill -0 "$gateway_pid" 2>/dev/null || { echo 'writing backup: Hermes gateway PID is not live' >&2; exit 1; }
      state_mtime=$(stat -c %Y "$state_file" 2>/dev/null || stat -f %m "$state_file") || {
        echo 'writing backup: cannot inspect Hermes gateway state age' >&2
        exit 1
      }
      state_age=$(( $(date +%s) - state_mtime ))
      [ "$state_age" -ge 0 ] && [ "$state_age" -le "$STATE_MAX_AGE_SECONDS" ] || {
        echo 'writing backup: Hermes gateway state snapshot is stale' >&2
        exit 1
      }
      ;;
    stopped|startup_failed) : ;;
    *) echo "writing backup: unknown Hermes gateway state: $gateway_state" >&2; exit 1 ;;
  esac
  if "$JQ_BIN" -e '.active_agents == null or (.active_agents|type != "number") or .active_agents < 0' "$state_file" >/dev/null; then
    echo 'writing backup: Hermes active_agents is missing or invalid' >&2
    exit 1
  fi
  if "$JQ_BIN" -e '(.gateway_state == "stopped" or .gateway_state == "startup_failed") and ((.active_agents // 0) != 0 or ((.active_work // []) | length) != 0)' "$state_file" >/dev/null; then
    echo 'writing backup: Hermes reports work while its gateway is stopped' >&2
    exit 1
  fi
  [ -e "$hermes_home/ESTOP" ] && pause_was_set=true
  if [ "$gateway_was_running" = false ] && [ -s "$hermes_home/gateway.pid" ]; then
    gateway_pid=$(head -n 1 "$hermes_home/gateway.pid")
    case "$gateway_pid" in ''|*[!0-9]*) echo 'writing backup: Hermes gateway PID file is invalid' >&2; exit 1 ;; esac
    if kill -0 "$gateway_pid" 2>/dev/null; then
      echo 'writing backup: Hermes gateway is live although its state says stopped' >&2
      exit 1
    fi
  fi
fi

restore_state() {
  local status=$?
  [ -z "$staging" ] || rm -rf -- "$staging"
  if "$hermes_initialized"; then
    if "$gateway_stopped" && "$gateway_was_running"; then
      "$HERMES_BIN" gateway start || status=1
    fi
    if "$pause_created" && ! "$pause_was_set"; then
      "$HERMES_BIN" resume || status=1
    fi
  fi
  trap - EXIT
  exit "$status"
}
trap restore_state EXIT

ledger_inflight() {
  local path query count
  for path in "$hermes_home/cron/executions.db" "$hermes_home/cron/deliveries.db"; do
    [ -e "$path" ] || continue
    case "$path" in
      */executions.db) query="SELECT count(*) FROM executions WHERE status IN ('claimed','running');" ;;
      */deliveries.db) query="SELECT count(*) FROM deliveries WHERE status='delivering';" ;;
    esac
    count=$("$SQLITE_BIN" -readonly "$path" "$query") || {
      echo "writing backup: cannot read Hermes ledger read-only: $path" >&2
      return 1
    }
    case "$count" in
      ''|*[!0-9]*) echo "writing backup: invalid Hermes ledger count: $path" >&2; return 1 ;;
      0) ;;
      *) return 2 ;;
    esac
  done
  return 0
}

if "$hermes_initialized" && "$gateway_was_running"; then
  if ! "$pause_was_set"; then
    "$HERMES_BIN" pause --reason writing-backup
    pause_created=true
  fi
  deadline=$((SECONDS + WAIT_SECONDS))
  while :; do
    active_agents=$("$JQ_BIN" -er '.active_agents' "$state_file") || {
      echo 'writing backup: Hermes active_agents cannot be read while draining' >&2; exit 1;
    }
    active_work=$("$JQ_BIN" -er '(.active_work // []) | if type == "array" then length else error end' "$state_file") || {
      echo 'writing backup: Hermes active_work is invalid' >&2; exit 1;
    }
    if ledger_inflight; then
      ledger_status=0
    else
      ledger_status=$?
      [ "$ledger_status" -eq 2 ] || exit 1
    fi
    [ "$ledger_status" -eq 0 ] && [ "$active_agents" -eq 0 ] && [ "$active_work" -eq 0 ] && break
    [ "$SECONDS" -lt "$deadline" ] || { echo 'writing backup: Hermes work did not drain before timeout' >&2; exit 1; }
    sleep "$POLL_SECONDS"
  done
  "$HERMES_BIN" gateway stop
  gateway_stopped=true
  deadline=$((SECONDS + WAIT_SECONDS))
  while :; do
    current_state=$("$JQ_BIN" -er '.gateway_state' "$state_file") || exit 1
    [ "$current_state" = stopped ] && break
    [ "$SECONDS" -lt "$deadline" ] || { echo 'writing backup: Hermes gateway did not stop before timeout' >&2; exit 1; }
    sleep "$POLL_SECONDS"
  done
  ledger_inflight || {
    status=$?
    [ "$status" -eq 2 ] && echo 'writing backup: Hermes ledger still has an external worker' >&2
    exit 1
  }
fi

if "$hermes_initialized"; then
  if ledger_inflight; then
    :
  else
    ledger_status=$?
    [ "$ledger_status" -eq 2 ] && echo 'writing backup: Hermes ledger still has an external worker' >&2
    exit 1
  fi
  while IFS= read -r -d '' sidecar; do
    [ ! -s "$sidecar" ] || { echo "writing backup: non-empty SQLite sidecar requires a WAL-safe snapshot: $sidecar" >&2; exit 1; }
  done < <(find "$hermes_home" -type f \( -name '*.db-wal' -o -name '*.db-shm' -o -name '*.db-journal' \) -print0)
  while IFS= read -r -d '' db; do
    "$FUSER_BIN" -s -- "$db" && { echo "writing backup: live Hermes database: $db" >&2; exit 1; } || [ "$?" -eq 1 ] || exit 1
    integrity=$("$SQLITE_BIN" -readonly "$db" 'PRAGMA integrity_check;') || {
      echo "writing backup: Hermes database integrity check failed: $db" >&2
      exit 1
    }
    [ "$integrity" = ok ] || { echo "writing backup: Hermes database is not clean: $db" >&2; exit 1; }
  done < <(find "$hermes_home" -type f \( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) -print0)
fi

generation=$(date +%Y-%m-%d_%H-%M-%S)
destination="$backup_root/$generation"
staging="$backup_root/.${generation}.tmp.$$"
mkdir "$staging"
chmod 0700 "$staging"
source_common_dir=
source_realpath=$(realpath "$source_dir") || {
  echo 'writing backup: source directory cannot be resolved' >&2
  exit 1
}
source_git_metadata=false
[ -e "$source_dir/.git" ] && source_git_metadata=true
if source_common_dir=$("$GIT_BIN" -C "$source_dir" rev-parse --git-common-dir 2>/dev/null); then
  case "$source_common_dir" in
    /*) ;;
    *) source_common_dir="$source_dir/$source_common_dir" ;;
  esac
  source_common_dir=$(realpath "$source_common_dir") || {
    echo 'writing backup: Git common directory cannot be resolved' >&2
    exit 1
  }
  [ -d "$source_common_dir" ] || {
    echo 'writing backup: Git common directory is missing' >&2
    exit 1
  }
elif "$source_git_metadata"; then
  echo 'writing backup: source has Git metadata but its common directory cannot be resolved' >&2
  exit 1
fi
mkdir -p "$staging/novel" "$staging/worktrees/hermes"
"$RSYNC_BIN" -aH --numeric-ids -- "$source_dir/" "$staging/novel/"
if [ -n "$source_common_dir" ]; then
  case "$source_common_dir" in
    "$source_realpath"/*) ;;
    *)
      [ -d "$bare_repo_dir" ] || {
        echo 'writing backup: external Git common directory requires a matching bare-repo backup path' >&2
        exit 1
      }
      bare_repo_realpath=$(realpath "$bare_repo_dir") || exit 1
      [ "$bare_repo_realpath" = "$source_common_dir" ] || {
        echo 'writing backup: configured bare-repo path does not match the source Git common directory' >&2
        exit 1
      }
      ;;
  esac
fi
if [ -d "$worktree_dir" ] && [ -n "$(find "$worktree_dir" -mindepth 1 -print -quit 2>/dev/null)" ]; then
  "$GIT_BIN" -C "$source_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo 'writing backup: non-empty Hermes worktree exists but novel source is not a Git worktree' >&2
    exit 1
  }
  "$RSYNC_BIN" -aH --numeric-ids -- "$worktree_dir/" "$staging/worktrees/hermes/"
  "$GIT_BIN" -C "$source_dir" worktree list --porcelain > "$staging/worktrees.manifest"
fi
if "$hermes_initialized"; then
  mkdir -p "$staging/hermes"
  # Hermes の backup.py が復旧対象として定義する実データのうち、認証・runtimeを含まない範囲だけ保存する。
  for relative in state.db cron/jobs.json cron/executions.db sessions memories skills; do
    [ -e "$hermes_home/$relative" ] || continue
    (cd "$hermes_home" && "$RSYNC_BIN" -aH --numeric-ids --relative \
      --exclude='auth.json' --exclude='.env' --exclude='mcp-tokens/' \
      --exclude='gateway_state.json' --exclude='gateway.pid' --exclude='cron.pid' \
      --exclude='gateway.lock' --exclude='processes.json' --exclude='ESTOP' \
      --exclude='*.db-wal' --exclude='*.db-shm' --exclude='*.db-journal' \
      -- "./$relative" "$staging/hermes/")
  done
fi
if [ -d "$bare_repo_dir" ]; then
  "$RSYNC_BIN" -aH --numeric-ids -- "$bare_repo_dir/" "$staging/novel.git/"
fi
chmod -R go-rwx "$staging"
chmod 0700 "$staging"
mv "$staging" "$destination"
kept=0
ls -1dt "$backup_root"/* 2>/dev/null | while IFS= read -r old; do
  [ -d "$old" ] || continue
  kept=$((kept + 1))
  [ "$kept" -le "$generations" ] || rm -rf -- "$old"
done

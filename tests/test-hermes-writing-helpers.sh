#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/novel"
state="$tmp/state"
worktree="$tmp/worktree"
git init -q "$repo"
git -C "$repo" config user.name test
git -C "$repo" config user.email test@example.invalid
printf '# novel\n' > "$repo/README.md"
printf '# repository rules\n' > "$repo/AGENTS.md"
git -C "$repo" add README.md AGENTS.md
git -C "$repo" commit -qm 'test: seed novel'

export HERMES_WRITING_STATE="$state"
export HERMES_WRITING_WORKTREE="$worktree"
export HERMES_WRITING_BRANCH='agent/hermes-writing'
export HERMES_WRITING_REPO="$repo"
export HERMES_WRITING_LOCK_RUNNER="$root/scripts/hermes-writing-lock.py"
mkdir -p "$state/writing"
printf '%s\n' '# hermes rules' > "$state/writing/.hermes.md"
printf '%s\n' '# workflow' > "$state/writing/workflow.md"
printf '%s\n' '# prompt' > "$state/writing/prompt.md"
mkdir -p "$worktree"
bash "$root/scripts/hermes-writing-init.sh" "$repo" >/dev/null
bash "$root/scripts/hermes-writing-init.sh" "$repo" >/dev/null
test "$(cat "$worktree/AGENTS.md")" = '# repository rules'
test -f "$worktree/.hermes.md"
test "$(stat -f %Lp "$worktree" 2>/dev/null || stat -c %a "$worktree")" = 700

# 既存ブランチでも、まだ worktree がない場合は同じ初期化を行える。
git -C "$repo" branch agent/existing
existing_worktree="$tmp/existing-worktree"
HERMES_WRITING_BRANCH=agent/existing HERMES_WRITING_WORKTREE="$existing_worktree" \
  bash "$root/scripts/hermes-writing-init.sh" "$repo" >/dev/null
test "$(git -C "$existing_worktree" branch --show-current)" = agent/existing

# 同じ branch 名でも別 repository の worktree は拒否する。
other_repo="$tmp/other-repo"
other_worktree="$tmp/other-worktree"
git init -q "$other_repo"
git -C "$other_repo" config user.name test
git -C "$other_repo" config user.email test@example.invalid
printf '# other\n' > "$other_repo/README.md"
git -C "$other_repo" add README.md
git -C "$other_repo" commit -qm 'test: other repo'
git -C "$other_repo" branch agent/hermes-writing
git -C "$other_repo" worktree add -q "$other_worktree" agent/hermes-writing
if HERMES_WRITING_WORKTREE="$other_worktree" bash "$root/scripts/hermes-writing-init.sh" "$repo" >/dev/null 2>&1; then
  echo 'expected cross-repository worktree failure' >&2
  exit 1
fi

printf '%s\n' '# checkpoint' | bash "$root/scripts/hermes-writing-checkpoint.sh" >/dev/null
test "$(cat "$worktree/progress/checkpoint.md")" = '# checkpoint'
printf '%s\n' '# checkpoint 2' | bash "$root/scripts/hermes-writing-checkpoint.sh" >/dev/null
test "$(cat "$worktree/progress/checkpoint.md")" = '# checkpoint 2'
mkdir -p "$worktree/chapters"
printf '%s\n' 'scene' > "$worktree/chapters/scene.md"
printf 'secret\n' > "$worktree/.env"
git -C "$worktree" add .env
if bash "$root/scripts/hermes-writing-commit.sh" 'test: must reject staged secret' 2>/dev/null; then exit 1; fi
git -C "$worktree" reset -q .env
bash "$root/scripts/hermes-writing-commit.sh" 'test: checkpoint scene' >/dev/null
test "$(git -C "$worktree" branch --show-current)" = 'agent/hermes-writing'
test "$(git -C "$worktree" status --porcelain)" = '?? .env'

# commit hook の失敗時も、作業ツリーと stage を保持する。
printf '%s\n' 'hook failure' > "$worktree/chapters/failure.md"
hook_path=$(git -C "$worktree" rev-parse --git-path hooks)/pre-commit
printf '#!/bin/sh\nexit 1\n' > "$hook_path"
chmod 700 "$hook_path"
if bash "$root/scripts/hermes-writing-commit.sh" 'test: expected hook failure' >/dev/null 2>&1; then exit 1; fi
test -f "$worktree/chapters/failure.md"
test -n "$(git -C "$worktree" diff --cached --name-only -- chapters/failure.md)"
python3 - "$hook_path" <<'PY'
from pathlib import Path
Path(__import__('sys').argv[1]).unlink()
PY
git -C "$worktree" commit -qm 'test: retain failed commit changes'

# 許可ディレクトリ内でも、既知の認証ファイルは stage されていれば拒否する。
printf 'secret\n' > "$worktree/chapters/auth.json"
mkdir -p "$worktree/chapters/日本語"
printf 'secret\n' > "$worktree/chapters/日本語/.env.local"
if bash "$root/scripts/hermes-writing-commit.sh" 'test: must reject auth file' >/dev/null 2>&1; then exit 1; fi
test -f "$worktree/chapters/auth.json"
test -f "$worktree/chapters/日本語/.env.local"
test -z "$(git -C "$worktree" diff --cached --name-only -- chapters/auth.json)"
python3 - "$worktree/chapters/auth.json" "$worktree/chapters/日本語/.env.local" <<'PY'
from pathlib import Path
import sys
for filename in sys.argv[1:]:
    Path(filename).unlink()
PY

# goal が明示した完了条件を満たす場合だけ、重複のない 5 分 job を作る。
fake_cron="$tmp/fake-cron"
cron_log="$tmp/cron-log"
cron_list="$tmp/cron-list"
cat > "$fake_cron" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == 'cron list --all' ]]; then
  cat "$CRON_LIST"
else
  printf '%s\n' "$*" > "$CRON_LOG"
fi
SH
chmod 700 "$fake_cron"
: > "$cron_list"
printf '%s\n' '# Goal' '完了条件: 一章の checkpoint と commit が存在すること。' > "$worktree/progress/goal.md"
HERMES_BIN="$fake_cron" HERMES_WRITING_READY=true CRON_LIST="$cron_list" CRON_LOG="$cron_log" \
  bash "$root/scripts/hermes-writing-start.sh"
grep -Fq 'cron create 5m' "$cron_log"
grep -Fq -- '--name hermes-writing' "$cron_log"
grep -Fq -- "--workdir $worktree" "$cron_log"
grep -Fq -- '--deliver discord' "$cron_log"
printf '%s\n' '    Name:      hermes-writing-extra' '    Name:      hermes-writing' > "$cron_list"
if HERMES_BIN="$fake_cron" HERMES_WRITING_READY=true CRON_LIST="$cron_list" CRON_LOG="$cron_log" \
  bash "$root/scripts/hermes-writing-start.sh" >/dev/null 2>&1; then
  echo 'expected duplicate writing job failure' >&2
  exit 1
fi

# list と create の間も control lock で保護し、並行 start は一つだけ成功する。
parallel_cron="$tmp/parallel-cron"
parallel_marker="$tmp/parallel-marker"
parallel_log="$tmp/parallel-log"
cat > "$parallel_cron" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == 'cron list --all' ]]; then
  if [[ -e "$CRON_MARKER" ]]; then printf 'Name: hermes-writing\n'; fi
else
  sleep 0.2
  : > "$CRON_MARKER"
  printf '%s\n' "$*" >> "$CRON_LOG"
fi
SH
chmod 700 "$parallel_cron"
set +e
HERMES_BIN="$parallel_cron" HERMES_WRITING_READY=true CRON_MARKER="$parallel_marker" CRON_LOG="$parallel_log" \
  bash "$root/scripts/hermes-writing-start.sh" >/dev/null 2>&1 &
first_pid=$!
HERMES_BIN="$parallel_cron" HERMES_WRITING_READY=true CRON_MARKER="$parallel_marker" CRON_LOG="$parallel_log" \
  bash "$root/scripts/hermes-writing-start.sh" >/dev/null 2>&1 &
second_pid=$!
wait "$first_pid"; first_status=$?
wait "$second_pid"; second_status=$?
set -e
if [ "$first_status" -eq 0 ] && [ "$second_status" -eq 0 ]; then exit 1; fi
if [ "$first_status" -ne 0 ] && [ "$second_status" -ne 0 ]; then exit 1; fi
test "$(grep -c '^cron create' "$parallel_log")" = 1

git -C "$worktree" switch -q --detach
if bash "$root/scripts/hermes-writing-checkpoint.sh" <<<'wrong branch' >/dev/null 2>&1; then exit 1; fi
if bash "$root/scripts/hermes-writing-commit.sh" 'test: wrong branch' >/dev/null 2>&1; then exit 1; fi

echo 'hermes writing helper tests passed'

#!/usr/bin/env bash
set -euo pipefail

state_dir=${HERMES_GITHUB_HOME:?HERMES_GITHUB_HOME is not set}
install -d -m 0700 "$state_dir" "$state_dir/gh"
chmod 0700 "$state_dir" "$state_dir/gh"
unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN
unset GH_REPO
export GH_CONFIG_DIR="$state_dir/gh"
export GH_HOST=github.com
export GH_PROMPT_DISABLED=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_TERMINAL_PROMPT=0
export GCM_INTERACTIVE=Never
unset GIT_ASKPASS SSH_ASKPASS GIT_SSH_COMMAND GIT_SSH GIT_SSH_VARIANT

real_gh=${HERMES_REAL_GH_BIN:-gh}
actual_user=$("$real_gh" api user --jq .login) || {
  echo 'Hermes GitHub authentication is missing or unreadable' >&2
  exit 1
}
[ "$actual_user" = "${HERMES_GITHUB_USER:?HERMES_GITHUB_USER is not set}" ] || {
  echo "Hermes GitHub account mismatch: expected ${HERMES_GITHUB_USER}, got $actual_user" >&2
  exit 1
}

exec "$real_gh" auth git-credential "$@"

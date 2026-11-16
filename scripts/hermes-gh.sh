#!/usr/bin/env bash
set -euo pipefail

state_dir=${HERMES_GITHUB_HOME:?HERMES_GITHUB_HOME is not set}
gh_config_dir="$state_dir/gh"

install -d -m 0700 "$state_dir" "$gh_config_dir"
chmod 0700 "$state_dir" "$gh_config_dir"

# Hermes は親シェルの認証情報とユーザー設定を継承しない。
unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN
export GH_CONFIG_DIR="$gh_config_dir"
export GH_HOST=github.com
unset GH_REPO
export GH_PROMPT_DISABLED=1
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_TERMINAL_PROMPT=0
export GCM_INTERACTIVE=Never

real_gh=${HERMES_REAL_GH_BIN:-${HERMES_GH_BIN:-gh}}

case "${1:-}" in
  help|--help|-h|version|--version) ;;
  auth)
    [ "${2:-}" = login ] || {
      login=${real_gh}
      actual_user=$("$login" api user --jq .login) || {
        echo 'Hermes GitHub authentication is missing or unreadable' >&2
        exit 1
      }
      [ "$actual_user" = "${HERMES_GITHUB_USER:?HERMES_GITHUB_USER is not set}" ] || {
        echo "Hermes GitHub account mismatch: expected ${HERMES_GITHUB_USER}, got $actual_user" >&2
        exit 1
      }
    }
    ;;
  *)
    actual_user=$("$real_gh" api user --jq .login) || {
      echo 'Hermes GitHub authentication is missing or unreadable' >&2
      exit 1
    }
    [ "$actual_user" = "${HERMES_GITHUB_USER:?HERMES_GITHUB_USER is not set}" ] || {
      echo "Hermes GitHub account mismatch: expected ${HERMES_GITHUB_USER}, got $actual_user" >&2
      exit 1
    }
    ;;
esac

exec "$real_gh" "$@"

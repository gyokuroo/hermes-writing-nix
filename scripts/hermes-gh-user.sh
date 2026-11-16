#!/usr/bin/env bash
set -euo pipefail

expected_user=${HERMES_GITHUB_USER:?HERMES_GITHUB_USER is not set}
gh_wrapper=${HERMES_GH_WRAPPER:-hermes-gh}
actual_user=$("$gh_wrapper" api user --jq .login)

if [ "$actual_user" != "$expected_user" ]; then
  echo "Hermes GitHub account mismatch: expected $expected_user, got $actual_user" >&2
  exit 1
fi

printf '%s\n' "$actual_user"

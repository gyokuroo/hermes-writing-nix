#!/usr/bin/env bash
set -euo pipefail

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_TERMINAL_PROMPT=0
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
unset GIT_ASKPASS SSH_ASKPASS GIT_SSH_COMMAND GIT_SSH GIT_SSH_VARIANT

exec "${HERMES_REAL_GIT_BIN:-${HERMES_GIT_BIN:-git}}" \
  -c user.name="${HERMES_GITHUB_USER:?HERMES_GITHUB_USER is not set}" \
  -c user.email="${HERMES_GIT_AUTHOR_EMAIL:?HERMES_GIT_AUTHOR_EMAIL is not set}" \
  -c core.askPass= \
  -c protocol.ssh.allow=never \
  -c url.https://github.com/.insteadOf=git@github.com: \
  -c url.https://github.com/.insteadOf=ssh://git@github.com/ \
  -c credential.helper= \
  -c credential.helper="${HERMES_GH_CREDENTIAL_HELPER:-hermes-gh-git-credential}" \
  "$@"

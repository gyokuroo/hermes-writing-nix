#!/usr/bin/env bash
set -euo pipefail

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

shim="$tmp/shim"
mkdir -p "$shim"
printf '#!/bin/sh\nexit 0\n' > "$shim/git"
printf '#!/bin/sh\nexit 0\n' > "$shim/gh"
chmod 700 "$shim/git" "$shim/gh"

init="$tmp/hermes-shell-init"
cat > "$init" <<EOF
export PATH=$shim:/usr/bin:/bin:$PATH
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_TERMINAL_PROMPT=0
export GH_CONFIG_DIR=$tmp/github/gh
export GH_HOST=github.com
export GH_PROMPT_DISABLED=1
export GCM_INTERACTIVE=Never
unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN
unset GIT_ASKPASS SSH_ASKPASS GIT_SSH_COMMAND GIT_SSH GIT_SSH_VARIANT
EOF

# login profile が PATH を戻しても、Hermes の init が最後に shim を復元する。
PATH=/usr/bin:/bin GH_TOKEN=secret GITHUB_TOKEN=secret bash --noprofile --norc -c \
  '. "$1"; test "$(command -v git)" = "$2"; test "$(command -v gh)" = "$3"; test "$GIT_CONFIG_GLOBAL" = /dev/null; test -z "${GH_TOKEN:-}"; test -z "${GITHUB_TOKEN:-}"' \
  -- "$init" "$shim/git" "$shim/gh"

wrapper="$tmp/bash"
cat > "$wrapper" <<EOF
#!/usr/bin/env bash
if [[ \$# -eq 2 && ( "\$1" == "-lic" || "\$1" == "-lc" ) ]]; then
  exec /bin/bash --noprofile --norc -c "source $init; \$2"
fi
exec /bin/bash --noprofile --norc "\$@"
EOF
chmod 700 "$wrapper"
SHELL="$wrapper" PATH=/usr/bin:/bin "$wrapper" -lic \
  'test "$(command -v git)" = "'$shim'/git" && test "$(command -v gh)" = "'$shim'/gh"'

echo 'Hermes shell-init and background shell fixture passed'

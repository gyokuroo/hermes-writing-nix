#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/fake-gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${GH_CONFIG_DIR:-}" > "$FAKE_GH_CONFIG"
printf '%s\n' "${GH_TOKEN:-unset}" > "$FAKE_GH_TOKEN"
printf '%s\n' "${GITHUB_TOKEN:-unset}" > "$FAKE_GITHUB_TOKEN"
printf '%s\n' "$@" > "$FAKE_GH_ARGS"
if [ "${1:-}" = api ] && [ "${2:-}" = user ]; then
  printf '%s\n' "$FAKE_GH_LOGIN"
fi
EOF
chmod +x "$tmp/fake-gh"

export HERMES_GITHUB_HOME="$tmp/state"
export HERMES_GITHUB_USER=gyokuroo
export HERMES_GH_BIN="$tmp/fake-gh"
export FAKE_GH_CONFIG="$tmp/config-path"
export FAKE_GH_TOKEN="$tmp/gh-token"
export FAKE_GITHUB_TOKEN="$tmp/github-token"
export FAKE_GH_ARGS="$tmp/gh-args"
export FAKE_GH_LOGIN=gyokuroo
export GH_TOKEN=personal-token
export GITHUB_TOKEN=personal-token

bash "$root/scripts/hermes-gh.sh" api user --jq .login
test "$(cat "$tmp/config-path")" = "$tmp/state/gh"
test "$(cat "$tmp/gh-token")" = unset
test "$(cat "$tmp/github-token")" = unset
if stat -c %a "$tmp/state" >/dev/null 2>&1; then
  test "$(stat -c %a "$tmp/state")" = 700
  test "$(stat -c %a "$tmp/state/gh")" = 700
else
  test "$(stat -f %Lp "$tmp/state")" = 700
test "$(stat -f %Lp "$tmp/state/gh")" = 700
fi

bash "$root/scripts/hermes-gh.sh" repo view gyokuroo/private
test "$(cat "$tmp/gh-args")" = $'repo\nview\ngyokuroo/private'
export FAKE_GH_LOGIN=other-account
if bash "$root/scripts/hermes-gh.sh" api repo view gyokuroo/private; then
  echo 'expected wrong account rejection' >&2
  exit 1
fi
test "$(cat "$tmp/gh-args")" = $'api\nuser\n--jq\n.login'
export FAKE_GH_LOGIN=gyokuroo
bash "$root/scripts/hermes-gh.sh" auth login --hostname github.com </dev/null

cat > "$tmp/fake-credential-gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$FAKE_CREDENTIAL_ARGS"
printf '%s\n' "${GH_CONFIG_DIR:-}" > "$FAKE_CREDENTIAL_CONFIG"
printf '%s\n' "${GH_HOST:-}" > "$FAKE_CREDENTIAL_HOST"
printf '%s\n' "${GH_TOKEN:-unset}" > "$FAKE_CREDENTIAL_TOKEN"
if [ "${1:-}" = api ] && [ "${2:-}" = user ]; then
  printf '%s\n' gyokuroo
fi
EOF
chmod +x "$tmp/fake-credential-gh"
export HERMES_REAL_GH_BIN="$tmp/fake-credential-gh"
export FAKE_CREDENTIAL_ARGS="$tmp/credential-args"
export FAKE_CREDENTIAL_CONFIG="$tmp/credential-config"
export FAKE_CREDENTIAL_HOST="$tmp/credential-host"
export FAKE_CREDENTIAL_TOKEN="$tmp/credential-token"
printf 'protocol=https\nhost=github.com\n\n' | bash "$root/scripts/hermes-gh-git-credential.sh" get
test "$(sed -n '1p' "$tmp/credential-args")" = auth
test "$(sed -n '2p' "$tmp/credential-args")" = git-credential
test "$(sed -n '3p' "$tmp/credential-args")" = get
test "$(cat "$tmp/credential-config")" = "$tmp/state/gh"
test "$(cat "$tmp/credential-host")" = github.com
test "$(cat "$tmp/credential-token")" = unset

cat > "$tmp/fake-user-wrapper" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${FAKE_GH_LOGIN:-}" = missing ]; then
  exit 1
fi
printf '%s\n' "${FAKE_GH_LOGIN:-gyokuroo}"
EOF
chmod +x "$tmp/fake-user-wrapper"
export HERMES_GH_WRAPPER="$tmp/fake-user-wrapper"
export FAKE_GH_LOGIN=gyokuroo
test "$(bash "$root/scripts/hermes-gh-user.sh")" = gyokuroo
export FAKE_GH_LOGIN=other-account
if bash "$root/scripts/hermes-gh-user.sh"; then
  echo 'expected account mismatch' >&2
  exit 1
fi
export FAKE_GH_LOGIN=missing
if bash "$root/scripts/hermes-gh-user.sh"; then
  echo 'expected unauthenticated account failure' >&2
  exit 1
fi

cat > "$tmp/fake-git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$GIT_CONFIG_GLOBAL" > "$FAKE_GIT_GLOBAL"
printf '%s\n' "$GIT_CONFIG_NOSYSTEM" > "$FAKE_GIT_NOSYSTEM"
printf '%s\n' "${GIT_AUTHOR_NAME:-unset}" > "$FAKE_GIT_AUTHOR"
printf '%s\n' "${GIT_COMMITTER_NAME:-unset}" > "$FAKE_GIT_COMMITTER"
printf '%s\n' "${GIT_ASKPASS:-unset}" > "$FAKE_GIT_ASKPASS"
printf '%s\n' "${SSH_ASKPASS:-unset}" > "$FAKE_SSH_ASKPASS"
printf '%s\n' "$@" > "$FAKE_GIT_ARGS"
EOF
chmod +x "$tmp/fake-git"
export HERMES_REAL_GIT_BIN="$tmp/fake-git"
export HERMES_GITHUB_USER=gyokuroo
export HERMES_GIT_AUTHOR_EMAIL=357243118+gyokuroo@users.noreply.github.com
export HERMES_GH_CREDENTIAL_HELPER="$tmp/hermes-gh-git-credential"
export FAKE_GIT_GLOBAL="$tmp/git-global"
export FAKE_GIT_NOSYSTEM="$tmp/git-nosystem"
export FAKE_GIT_ARGS="$tmp/git-args"
export FAKE_GIT_AUTHOR="$tmp/git-author"
export FAKE_GIT_COMMITTER="$tmp/git-committer"
export FAKE_GIT_ASKPASS="$tmp/git-askpass"
export FAKE_SSH_ASKPASS="$tmp/ssh-askpass"
export GIT_AUTHOR_NAME=personal-author
export GIT_AUTHOR_EMAIL=personal@example.invalid
export GIT_COMMITTER_NAME=personal-committer
export GIT_COMMITTER_EMAIL=personal-committer@example.invalid
export GIT_ASKPASS=personal-askpass
export SSH_ASKPASS=personal-ssh-askpass
export GIT_SSH_COMMAND=personal-ssh
export GIT_SSH=personal-ssh
bash "$root/scripts/hermes-writing-git.sh" commit -m draft
test "$(cat "$tmp/git-global")" = /dev/null
test "$(cat "$tmp/git-nosystem")" = 1
test "$(cat "$tmp/git-author")" = unset
test "$(cat "$tmp/git-committer")" = unset
test "$(cat "$tmp/git-askpass")" = unset
test "$(cat "$tmp/ssh-askpass")" = unset
test "$(sed -n '1p' "$tmp/git-args")" = -c
test "$(sed -n '2p' "$tmp/git-args")" = user.name=gyokuroo
test "$(sed -n '3p' "$tmp/git-args")" = -c
test "$(sed -n '4p' "$tmp/git-args")" = user.email=357243118+gyokuroo@users.noreply.github.com
grep -Fx -- '-c' "$tmp/git-args" >/dev/null
grep -Fx -- 'protocol.ssh.allow=never' "$tmp/git-args" >/dev/null
grep -Fx -- 'url.https://github.com/.insteadOf=git@github.com:' "$tmp/git-args" >/dev/null
grep -Fx -- 'url.https://github.com/.insteadOf=ssh://git@github.com/' "$tmp/git-args" >/dev/null
grep -Fx -- 'credential.helper=' "$tmp/git-args" >/dev/null
grep -Fx -- "credential.helper=$tmp/hermes-gh-git-credential" "$tmp/git-args" >/dev/null
repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.name personal-author
git -C "$repo" config user.email personal@example.invalid
printf 'draft\n' > "$repo/chapter.md"
printf '[user]\n\tname = personal-global\n\temail = global@example.invalid\n' > "$tmp/personal-global"
export GIT_CONFIG_GLOBAL="$tmp/personal-global"
export GIT_AUTHOR_NAME=personal-author
export GIT_AUTHOR_EMAIL=personal@example.invalid
export GIT_COMMITTER_NAME=personal-committer
export GIT_COMMITTER_EMAIL=personal-committer@example.invalid
export GIT_SSH_COMMAND=personal-ssh
export GIT_SSH=personal-ssh
(cd "$repo" && HERMES_REAL_GIT_BIN="$(command -v git)" bash "$root/scripts/hermes-writing-git.sh" add chapter.md)
(cd "$repo" && HERMES_REAL_GIT_BIN="$(command -v git)" bash "$root/scripts/hermes-writing-git.sh" commit -m hermes-draft)
test "$(git -C "$repo" log -1 --format='%an|%ae|%cn|%ce')" = 'gyokuroo|357243118+gyokuroo@users.noreply.github.com|gyokuroo|357243118+gyokuroo@users.noreply.github.com'
test "$(git -C "$repo" config user.name)" = personal-author
test "$(cat "$tmp/personal-global")" = $'[user]\n\tname = personal-global\n\temail = global@example.invalid'

echo 'GitHub isolation tests passed'

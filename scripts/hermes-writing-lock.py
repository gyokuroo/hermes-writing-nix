#!/usr/bin/env python3
import fcntl
import os
import re
import subprocess
import sys
import tempfile

state_dir = os.environ["HERMES_WRITING_STATE"]
worktree = os.environ["HERMES_WRITING_WORKTREE"]
expected_branch = os.environ["HERMES_WRITING_BRANCH"]
repo = os.environ["HERMES_WRITING_REPO"]
git_bin = os.environ.get("HERMES_GIT_BIN", "git")
lock_path = os.path.join(state_dir, "locks", "writer.lock")
os.makedirs(os.path.dirname(lock_path), mode=0o700, exist_ok=True)

with open(lock_path, "a+", encoding="utf-8") as lock:
    try:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("writer lock is busy", file=sys.stderr)
        raise SystemExit(75)

    current_branch = subprocess.check_output(
        [git_bin, "-C", worktree, "branch", "--show-current"], text=True
    ).strip()
    if current_branch != expected_branch:
        print(f"worktree is on an unexpected branch: {current_branch}", file=sys.stderr)
        raise SystemExit(1)

    def common_dir(path):
        raw = subprocess.check_output(
            [git_bin, "-C", path, "rev-parse", "--git-common-dir"], text=True
        ).strip()
        if not os.path.isabs(raw):
            raw = os.path.join(path, raw)
        return os.path.realpath(raw)

    if common_dir(repo) != common_dir(worktree):
        print("worktree belongs to a different Git repository", file=sys.stderr)
        raise SystemExit(1)

    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "checkpoint":
        progress = os.path.join(worktree, "progress")
        os.makedirs(progress, mode=0o700, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix=".checkpoint.", dir=progress, text=True)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as output:
                output.write(sys.stdin.read())
                output.flush()
                os.fchmod(output.fileno(), 0o600)
                os.fsync(output.fileno())
            os.replace(temporary, os.path.join(progress, "checkpoint.md"))
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
        print(f"checkpoint updated: {progress}/checkpoint.md")
    elif command == "commit":
        message = sys.argv[2] if len(sys.argv) > 2 else "writing: checkpoint scene"
        staged = subprocess.check_output(
            [git_bin, "-C", worktree, "diff", "--cached", "--name-only"], text=True
        ).splitlines()
        if staged:
            print("refusing to commit pre-staged changes", file=sys.stderr)
            raise SystemExit(1)
        def changed_names(args):
            return set(filter(None, subprocess.check_output(args, text=True).split("\0")))

        changed = set()
        changed.update(changed_names(
            [git_bin, "-C", worktree, "diff", "--name-only", "-z"]
        ))
        changed.update(changed_names(
            [git_bin, "-C", worktree, "ls-files", "--others", "--exclude-standard", "-z"]
        ))
        changed.update(changed_names(
            [git_bin, "-C", worktree, "diff", "--cached", "--name-only", "-z"]
        ))
        protected_names = {
            ".env", "auth.json", "credentials.json", "oauth.json", "provider.oauth.json",
            "tokens.json",
        }
        protected_dirs = {"mcp-tokens", "secrets", ".credentials"}
        allowed = [".hermes.md", "workflow.md", "chapters", "progress", "plot", "plots", "setting", "settings"]
        allowed_roots = set(allowed)
        protected = [
            path for path in changed
            if (path in allowed_roots or path.split(os.sep)[0] in allowed_roots)
            and (
                (os.path.basename(path) in protected_names or os.path.basename(path) == ".env" or os.path.basename(path).startswith(".env."))
                or any(part in protected_dirs for part in path.split(os.sep))
            )
        ]
        if protected:
            print(f"refusing to commit known authentication files: {', '.join(sorted(protected))}", file=sys.stderr)
            raise SystemExit(1)
        existing = [path for path in allowed if os.path.exists(os.path.join(worktree, path))]
        if existing:
            subprocess.run([git_bin, "-C", worktree, "add", "--all", "--", *existing], check=True)
        staged = subprocess.run([git_bin, "-C", worktree, "diff", "--cached", "--quiet"])
        if staged.returncode == 0:
            print("no staged writing changes")
        else:
            subprocess.run([git_bin, "-C", worktree, "commit", "--message", message], check=True)
    elif command == "cron-start":
        hermes, job_name, schedule, prompt = sys.argv[2:6]
        jobs = subprocess.run(
            [hermes, "cron", "list", "--all"], check=True, capture_output=True, text=True
        ).stdout
        if re.search(r"(?m)^\s*Name:\s+" + re.escape(job_name) + r"\s*$", jobs):
            print(f"writing job already exists: {job_name}", file=sys.stderr)
            raise SystemExit(1)
        subprocess.run(
            [
                hermes, "cron", "create", schedule, prompt,
                "--name", job_name, "--workdir", worktree,
                "--deliver", "local", "--failure-deliver", "local",
            ],
            check=True,
        )
    else:
        print("usage: hermes-writing-lock.py checkpoint|commit [message]|cron-start hermes name schedule prompt", file=sys.stderr)
        raise SystemExit(2)

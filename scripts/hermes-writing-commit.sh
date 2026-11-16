#!/usr/bin/env bash
set -euo pipefail
exec python3 "${HERMES_WRITING_LOCK_RUNNER:?HERMES_WRITING_LOCK_RUNNER is not set}" commit "${1:-writing: checkpoint scene}"

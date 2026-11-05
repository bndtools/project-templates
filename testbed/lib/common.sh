#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

err() { printf 'testbed: %s\n' "$*" >&2; }
die() { err "$1"; exit "${2:-1}"; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || die "required command missing: $1" 2; }
is_windows() { [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* ]]; }
native_path() {
  if is_windows; then cygpath -m "$1"; else printf '%s\n' "$1"; fi
}
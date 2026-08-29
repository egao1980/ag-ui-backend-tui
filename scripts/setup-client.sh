#!/usr/bin/env bash
# Pull cl-repository-client (+ its Lisp deps) into ./.cl-repository. No Quicklisp.
# CL_REPOSITORY_FORCE=1 re-pulls even if a client tree is already present.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DEST="${CL_REPOSITORY_DEST:-${ROOT}/.cl-repository}"
if [[ "${CL_REPOSITORY_FORCE:-}" == "1" ]]; then
  rm -rf "${DEST}"
fi

if find "${DEST}" -name 'cl-repository-client.asd' -print -quit 2>/dev/null | grep -q .; then
  printf 'client already in %s\n' "${DEST}"
  exit 0
fi

command -v oras >/dev/null || { printf 'setup-client: oras not on PATH\n' >&2; exit 1; }
export CL_REPOSITORY_DEST="${DEST}"
curl -fsSL \
  https://raw.githubusercontent.com/egao1980/cl-repository/main/.github/actions/setup-client/setup-client.sh \
  | bash

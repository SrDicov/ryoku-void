#!/usr/bin/env bash
# Shared backend runner for installer dry-run behavior tests.

INSTALL_DRYRUN_ROOT=${RYOKU_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}

install_dryrun_backend_path() {
  case $1 in
    arch) printf '%s/installation/backend/ryoku-install\n' "$INSTALL_DRYRUN_ROOT" ;;
    void) printf '%s/void/iso/backend/ryoku-install\n' "$INSTALL_DRYRUN_ROOT" ;;
    *) printf 'unknown installer edition: %s\n' "$1" >&2; return 2 ;;
  esac
}

# install_dryrun_run <arch|void> <output-file> [NAME=VALUE ...]
install_dryrun_run() {
  local edition=$1 output=$2 backend
  shift 2
  backend=$(install_dryrun_backend_path "$edition") || return
  env \
    RYOKU_DRYRUN=1 \
    RYOKU_REPO="$INSTALL_DRYRUN_ROOT" \
    RYOKU_DISK=/dev/vda \
    'RYOKU_PASSWORD_HASH=$6$fake$hash' \
    "$@" \
    bash "$backend" >"$output" 2>&1
}

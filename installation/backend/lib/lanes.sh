#!/usr/bin/env bash
# shellcheck shell=bash
# Translation-table lanes and drops for an edition backend that resolves its
# package plan through system/packages/resolve.

ryoku_profile_lanes() {
  case $RYOKU_PROFILE in
    amd) printf '%s\n' hardware:amd ;;
    intel) printf '%s\n' hardware:intel ;;
    amd-nvidia) printf '%s\n' hardware:amd hardware:intel hardware:nvidia ;;
    vm) printf '%s\n' hardware:vm ;;
    *) die 'unknown RYOKU_PROFILE: %s (want amd-nvidia|amd|intel|vm)' "$RYOKU_PROFILE" ;;
  esac
}

ryoku_resolver_drop_args() {
  local package
  local -a packages=()
  IFS=',' read -ra packages <<<"${RYOKU_DROP_PACKAGES:-}"
  for package in "${packages[@]}"; do
    if [[ -n $package ]]; then
      printf '%s\n' --drop "$package"
    fi
  done
}

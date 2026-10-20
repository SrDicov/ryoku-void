#!/usr/bin/env bash

void_keep_uninstalled_packages() {
  local array_name=$1
  local -n requested=$array_name
  [[ -z ${RYOKU_DRYRUN:-} ]] || return 0

  local listing
  listing=$(env XBPS_ARCH=x86_64 xbps-query -r /mnt -l) \
    || die 'could not read the installed XBPS package set'
  local -a installed=() pending=()
  mapfile -t installed < <(awk '$1 == "ii" { print $2 }' <<<"$listing")

  local package pkgver found
  for package in "${requested[@]}"; do
    found=0
    for pkgver in "${installed[@]}"; do
      if [[ $pkgver == "$package"-[0-9]* ]]; then
        found=1
        break
      fi
    done
    if ((found == 0)); then
      pending+=("$package")
    fi
  done
  requested=("${pending[@]}")
}

void_base_install() {
  void_seed_keys
  local -a args=(--lane system --session)
  local -a drop_args=()
  mapfile -t drop_args < <(ryoku_resolver_drop_args)
  args+=("${drop_args[@]}")
  local -a packages=(base-system)
  mapfile -t -O "${#packages[@]}" packages < <(void_resolve "${args[@]}")
  mapfile -t packages < <(printf '%s\n' "${packages[@]}" | awk 'NF && !seen[$0]++')

  log 'installing Void base from the offline repository (%d packages)' "${#packages[@]}"
  run env XBPS_ARCH=x86_64 xbps-install -r /mnt -R "$RYOKU_OFFLINE_REPO" -i -Sy "${packages[@]}"
  void_offline_target_on
  void_write_fstab
}

void_write_fstab() {
  local esp_uuid
  esp_uuid=$(dev_uuid "$ESP_DEV") || die 'fstab: could not read boot UUID from %s' "$ESP_DEV"
  log "writing UUID-based /etc/fstab"
  run mkdir -p /mnt/etc
  {
    ryoku_fstab_subvolumes
    printf 'UUID=%s\t/boot\tvfat\tdefaults,noatime\t0 2\n' "$esp_uuid"
    printf 'tmpfs\t/tmp\ttmpfs\tdefaults,nosuid,nodev\t0 0\n'
  } | write_file /mnt/etc/fstab
}

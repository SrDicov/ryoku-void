#!/usr/bin/env bash
# shellcheck shell=bash
# Root unlock for an edition backend whose target uses dracut: the kernel
# cmdline and the crypttab dracut bakes in.

ryoku_dracut_cmdline() {
  local root_ref cmdline
  if [[ ${RYOKU_ENCRYPT:-} == 1 ]]; then
    local luks_uuid
    luks_uuid=$(dev_uuid "$LUKS_PART") || die 'could not read LUKS UUID from %s' "$LUKS_PART"
    root_ref=/dev/mapper/root
    cmdline="root=$root_ref rootflags=subvol=@ rw rd.luks.uuid=luks-$luks_uuid"
  else
    local root_uuid
    root_uuid=$(dev_uuid "$ROOT_DEV") || die 'could not read root UUID from %s' "$ROOT_DEV"
    root_ref=UUID=$root_uuid
    cmdline="root=$root_ref rootflags=subvol=@ rw"
  fi
  [[ -z ${RYOKU_KERNEL_CMDLINE_EXTRA:-} ]] || cmdline+=" $RYOKU_KERNEL_CMDLINE_EXTRA"
  printf '%s' "$cmdline"
}

ryoku_dracut_crypttab() {
  [[ ${RYOKU_ENCRYPT:-} == 1 ]] || return 0
  local uuid
  uuid=$(dev_uuid "$LUKS_PART") || die 'crypttab: could not read the LUKS UUID of %s' "$LUKS_PART"
  write_file /mnt/etc/crypttab <<EOF
root UUID=$uuid none luks
EOF
  run mkdir -p /mnt/etc/dracut.conf.d
  write_file /mnt/etc/dracut.conf.d/20-ryoku-crypt.conf <<'EOF'
add_dracutmodules+=" crypt "
hostonly_cmdline="yes"
EOF
}

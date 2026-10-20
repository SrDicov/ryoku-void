#!/usr/bin/bash
#
# dracut module: boots a snapper snapshot read-only from the "Ryoku snapshots"
# GRUB menu, its writes kept in RAM. It runs after dracut has unlocked LUKS, so
# an encrypted disk boots its snapshots the same way. Only the images
# `ryoku boot-menu sync` builds for the snapshot entries carry it (dracut --add
# ryoku-snapshot); Fedora's own initramfs images stay as they are.

check() {
  return 255
}

depends() {
  echo btrfs
}

installkernel() {
  hostonly='' instmods overlay
}

# shellcheck disable=SC2154 # dracut sets moddir
install() {
  inst_multiple mkdir mount umount ln
  inst_hook pre-pivot 10 "$moddir/ryoku-snapshot-preview.sh"
}

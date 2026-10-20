#!/usr/bin/bash
#
# pre-pivot hook. rd.ryoku.preview=<top-level path of a snapshot> boots that
# snapshot read-only: the snapshot is the lower layer of an overlay
# whose writes go to RAM, so the system runs normally and nothing on disk
# changes. sysroot.mount has already mounted the snapshot read-only (the
# entry's rootflags name it); the overlay is stacked on top of /sysroot, and
# its lower layer is a second mount under /run, which switch-root carries
# into the booted system. fstab's options for / name a btrfs subvolume, which
# the overlay refuses on remount, so systemd-remount-fs is masked for this
# boot only (/run).
#
# /.snapshots is the real store, not part of the snapshot this boot runs. The
# hook adds ro to its entry in the overlay's fstab, which lives in RAM, and
# masks snapper's timers and the menu resync, so this boot never cleans up,
# adds or relists snapshots.
#
# /home is not in the snapshot, so this boot shows the live one, but older
# programs must not write to it: an older browser or mail client can damage a
# profile a newer version already upgraded. Its fstab entry moves read-only
# under /run/ryoku/preview/home, and /home becomes an overlay of it whose
# writes share the root's RAM layer. The session runs, and nothing it writes
# reaches the disk.
#
# dracut sources hooks, so this returns and never exits.

# shellcheck source=/dev/null
type getarg >/dev/null 2>&1 || . /lib/dracut-lib.sh

# ryoku_snapshot_preview_fstab <fstab> <base>: adds ro to the /.snapshots
# entry, and moves the /home entry read-only to <base>/home under an overlay
# whose upper layer is <base>/rw/home.
ryoku_snapshot_preview_fstab() {
  local fstab="$1" base="$2" line dev target fstype opts rest out=""
  [ -f "$fstab" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    read -r dev target fstype opts rest <<<"$line"
    if [ "${dev#\#}" = "$dev" ] && [ -n "$opts" ]; then
      case "$target" in
        /.snapshots)
          line="$dev $target $fstype $opts,ro${rest:+ $rest}"
          ;;
        /home)
          line="$dev $base/home $fstype $opts,ro${rest:+ $rest}"$'\n'
          line+="ryoku-preview-home /home overlay lowerdir=$base/home,upperdir=$base/rw/home/upper"
          line+=",workdir=$base/rw/home/work,x-systemd.requires-mounts-for=$base/home 0 0"
          ;;
      esac
    fi
    out+="$line"$'\n'
  done <"$fstab"
  printf '%s' "$out" >"$fstab"
}

ryoku_snapshot_preview() {
  local snap dev run="${RYOKU_RUN:-/run}" newroot="${NEWROOT:-/sysroot}"
  local base="$run/ryoku/preview"
  snap=$(getarg rd.ryoku.preview=) || return 0
  case "$snap" in
    "" | /* | *..* | *[!A-Za-z0-9._/-]*) warn "ryoku: refusing snapshot path '$snap'"; return 0 ;;
  esac
  dev=$(label_uuid_to_dev "$(getarg root=)")
  mkdir -p "$base/lower" "$base/rw"
  if ! mount -t btrfs -o "ro,subvol=$snap" "$dev" "$base/lower"; then
    warn "ryoku: cannot mount $snap; booting it read-only as it is"
    return 0
  fi
  mount -t tmpfs -o mode=0755 ryoku-preview "$base/rw"
  mkdir -p "$base/rw/upper" "$base/rw/work" "$base/rw/home/upper" "$base/rw/home/work"
  if ! mount -t overlay ryoku-preview \
    -o "lowerdir=$base/lower,upperdir=$base/rw/upper,workdir=$base/rw/work" "$newroot"; then
    warn "ryoku: overlay failed; booting $snap read-only as it is"
    umount "$base/rw" "$base/lower"
    return 0
  fi
  mkdir -p "$run/systemd/system"
  local unit
  for unit in systemd-remount-fs.service snapper-timeline.timer snapper-cleanup.timer \
    snapper-boot.timer ryoku-snapshot-menu.path; do
    ln -sf /dev/null "$run/systemd/system/$unit"
  done
  ryoku_snapshot_preview_fstab "$newroot/etc/fstab" "$base"
  info "ryoku: previewing $snap; changes stay in RAM"
}

ryoku_snapshot_preview

#!/usr/bin/env bash
# hermetic test for Fedora's snapshot boot menu (fedora/system/boot).
#
# case 1: the payload, the spec, the units and the CLI agree on names and
#         paths, and the snapper plugin touches /.snapshots only after a
#         snapshot is created or deleted.
# case 2: the initramfs look hook stacks a RAM overlay on the snapshot,
#         masks systemd-remount-fs and the snapshot timers for that boot,
#         mounts /.snapshots read-only and puts /home under a RAM overlay.
# case 3: ryoku-grub-menu themes GRUB and renders the snippet into grub.cfg
#         idempotently, and purge undoes it.
# shellcheck disable=SC2329 # stubs and predicates run indirectly
# shellcheck disable=SC2016 # single-quoted patterns are literal file text

set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd -P)"
bm="$repo/fedora/system/boot"
mod="$bm/dracut/90ryoku-snapshot"
payload="$repo/fedora/packages/rpm/payload/ryoku-desktop.sh"
spec="$repo/fedora/packages/rpm/ryoku-desktop.spec"
cli="$repo/ryoku/cli/internal/updater/bootmenu.go"
restore="$repo/ryoku/cli/internal/updater/bootmenu_restore.go"
manifest="$repo/system/services/manifest.tsv"

work=$(mktemp -d /tmp/ryoku-snapshot-boot.XXXXXX)
trap 'rm -rf "$work"' EXIT

fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
check() { if "${@:2}"; then ok "$1"; else bad "$1"; fi; }
line() { grep -qxF -- "$2" "$1"; }
has() { grep -qF -- "$2" "$1"; }
absent() { [ ! -e "$1" ]; }

# case 1
for dest in \
  usr/bin/ryoku-grub-menu \
  etc/grub.d/15_ryoku_snapshots \
  usr/libexec/snapper/plugins/50-ryoku-boot-menu; do
  check "ryoku-desktop ships /$dest" has "$payload" "\"\$pkgdir/$dest\""
done
for unit in ryoku-snapshot-menu.service ryoku-snapshot-menu.path ryoku-snapshot-restored.service; do
  check "ryoku-desktop ships $unit" has "$payload" "$unit"
  check "$unit exists" test -f "$bm/$unit"
done
check "ryoku-desktop ships the dracut module" has "$payload" '"$pkgdir/usr/lib/dracut/modules.d/90ryoku-snapshot/$mod"'
check "%posttrans themes GRUB and renders the snippet" has "$spec" "/usr/bin/ryoku-grub-menu install"
check "ryoku-desktop ships the theme" has "$payload" '"$pkgdir/usr/share/ryoku/grub/theme/${file##*/}"'
check "%posttrans lists the snapshots on disk and watches for more" has "$spec" \
  "systemctl start --no-block ryoku-snapshot-menu.path ryoku-snapshot-menu.service"
check "%preun disables the menu trigger" has "$spec" \
  "systemctl disable --now ryoku-snapshot-menu.path ryoku-snapshot-restored.service"
check "%preun drops the menu" has "$spec" "/usr/bin/ryoku-grub-menu purge"
legacy="$repo/ryoku/cli/internal/doctor/reconcile_fedora_legacy_boot.go"
twins_marker=$(sed -n 's/^[[:space:]]*consoleTwinsMarker *= "\(.*\)"$/\1/p' "$legacy")
check "a first install seeds the console-twins marker the doctor reads" \
  test -n "$twins_marker" -a "$(grep -c "install -D -m 0644 /dev/null $twins_marker" "$spec")" = 1
check "%postun drops it from grub.cfg" has "$spec" "grub2-mkconfig -o /boot/grub2/grub.cfg"
check "Fedora's boot-success timer is left alone" test -z "$(grep -n 'grub-boot-success' "$spec")"
for dep in grub2-tools grub2-tools-extra fontconfig grubby btrfs-progs snapper dracut; do
  check "ryoku-desktop requires $dep" grep -qE "^Requires: +$dep\$" "$spec"
done
check "the manifest enables the menu trigger at boot" grep -qP '^snapshot-menu\tsystem\tboot\tryoku-snapshot-menu\.path\t' "$manifest"
check "the manifest enables the restore follow-up at boot" grep -qP '^snapshot-restored\tsystem\tboot\tryoku-snapshot-restored\.service\t' "$manifest"
check "the menu unit runs the CLI sync" line "$bm/ryoku-snapshot-menu.service" "ExecStart=/usr/bin/ryoku boot-menu sync"
check "the trigger watches /.snapshots" line "$bm/ryoku-snapshot-menu.path" "PathChanged=/.snapshots"
check "the trigger starts the menu unit" line "$bm/ryoku-snapshot-menu.path" "Unit=ryoku-snapshot-menu.service"
check "the plugin touches /.snapshots" has "$bm/snapper/50-ryoku-boot-menu" '${RYOKU_SNAPSHOTS_DIR:-/.snapshots}'
check "the CLI rescans until /.snapshots holds still" grep -q 'modTime(snapshotsDir).Equal(before)' "$cli"
check "the restored unit runs the CLI follow-up" line "$bm/ryoku-snapshot-restored.service" "ExecStart=/usr/bin/ryoku boot-menu restored"
check "the restored unit waits for the restore's flag" line "$bm/ryoku-snapshot-restored.service" \
  "ConditionPathExists=/etc/ryoku/snapshot-restored"
check "the restored unit stays off during a look boot" line "$bm/ryoku-snapshot-restored.service" \
  "ConditionKernelCommandLine=!rd.ryoku.preview"
check "the CLI writes the flag the unit waits for" grep -q 'restoredFlag = "/etc/ryoku/snapshot-restored"' "$restore"
check "the CLI restores from the snapshot the look hook mounted" grep -q 'previewLower = "/run/ryoku/preview/lower"' "$restore"
check "the look hook mounts it there" has "$mod/ryoku-snapshot-preview.sh" 'base="$run/ryoku/preview"'
check "the CLI builds images with the shipped module" grep -q 'snapshotDracutMod *= "ryoku-snapshot"' "$cli"
check "the snippet sources the file the CLI writes" has "$bm/grub/15_ryoku_snapshots" 'source "${config_directory}/ryoku-snapshots.cfg"'
check "the grub.d snippet renders" sh -c "sh '$bm/grub/15_ryoku_snapshots' | grep -q '^if \\[ -f '"
check "the module is only built in on request" grep -q '^  return 255$' "$mod/module-setup.sh"
check "the module has no unattended restore" test ! -e "$mod/ryoku-snapshot-restore.sh"

plugin() { RYOKU_SNAPSHOTS_DIR="$work/snapshots" sh "$bm/snapper/50-ryoku-boot-menu" "$1" / btrfs 42; }
touched() { test "$(stat -c %Y "$work/snapshots")" != 0; }
mkdir "$work/snapshots" && touch -d @0 "$work/snapshots"
for event in create-snapshot-pre modify-snapshot-post create-config; do
  plugin "$event"
done
check "the plugin leaves /.snapshots alone before or besides a snapshot" test "$(stat -c %Y "$work/snapshots")" = 0
plugin create-snapshot-post
check "the plugin touches /.snapshots after a snapshot is created" touched
touch -d @0 "$work/snapshots"
plugin delete-snapshot-post
check "the plugin touches /.snapshots after a snapshot is deleted" touched
check "the plugin never starts a unit, which SELinux denies snapperd" \
  test -z "$(grep -n systemctl "$bm/snapper/50-ryoku-boot-menu")"

stubs="$work/bin"
mkdir -p "$stubs"

# case 2
# hook <script> <cmdline>: source a dracut hook with the dracut-lib helpers
# stubbed, the root device at /dev/null and /run at $work/run.
hook() {
  local script="$1" cmdline="$2"
  (
    set +eu
    export RYOKU_RUN="$work/run" NEWROOT="$work/sysroot"
    getarg() {
      local tok
      for tok in $cmdline; do
        case "$tok" in "$1"*) echo "${tok#"$1"}"; return 0 ;; esac
      done
      return 1
    }
    warn() { echo "warn: $*" >>"$work/hook.log"; }
    info() { echo "info: $*" >>"$work/hook.log"; }
    label_uuid_to_dev() { echo /dev/null; }
    mount() { echo "mount $*" >>"$work/mount.log"; [ -z "${MOUNT_FAILS:-}" ]; }
    umount() { :; }
    # shellcheck source=/dev/null
    . "$script"
  )
}

mkdir -p "$work/sysroot/etc"
cat >"$work/sysroot/etc/fstab" <<'FSTAB'
# /.snapshots stays commented here
UUID=abc / btrfs subvol=root,compress=zstd:1 0 0
UUID=abc /.snapshots btrfs subvol=.snapshots,compress=zstd:1 0 0
UUID=abc /home btrfs subvol=home,compress=zstd:1 0 0
FSTAB
hook "$mod/ryoku-snapshot-preview.sh" "root=UUID=abc ro rootflags=subvol=.snapshots/42/snapshot rd.ryoku.preview=.snapshots/42/snapshot"
base="$work/run/ryoku/preview"
check "look mounts the snapshot read-only as the lower layer" \
  grep -qxF "mount -t btrfs -o ro,subvol=.snapshots/42/snapshot /dev/null $base/lower" "$work/mount.log"
check "look keeps its writes in RAM" grep -qxF "mount -t tmpfs -o mode=0755 ryoku-preview $base/rw" "$work/mount.log"
check "look stacks the overlay on the root" grep -qxF \
  "mount -t overlay ryoku-preview -o lowerdir=$base/lower,upperdir=$base/rw/upper,workdir=$base/rw/work $work/sysroot" \
  "$work/mount.log"
check "look masks systemd-remount-fs for this boot" \
  test "$(readlink "$work/run/systemd/system/systemd-remount-fs.service")" = /dev/null
for unit in snapper-timeline.timer snapper-cleanup.timer snapper-boot.timer ryoku-snapshot-menu.path; do
  check "look masks $unit for this boot" test "$(readlink "$work/run/systemd/system/$unit")" = /dev/null
done
check "look mounts /.snapshots read-only" \
  grep -qxF "UUID=abc /.snapshots btrfs subvol=.snapshots,compress=zstd:1,ro 0 0" "$work/sysroot/etc/fstab"
check "look leaves the root entry alone" \
  grep -qxF "UUID=abc / btrfs subvol=root,compress=zstd:1 0 0" "$work/sysroot/etc/fstab"
check "look leaves comments alone" \
  grep -qxF "# /.snapshots stays commented here" "$work/sysroot/etc/fstab"
check "look mounts the live /home read-only under the look" \
  grep -qxF "UUID=abc $base/home btrfs subvol=home,compress=zstd:1,ro 0 0" "$work/sysroot/etc/fstab"
check "look stacks a RAM overlay on /home" grep -qxF \
  "ryoku-preview-home /home overlay lowerdir=$base/home,upperdir=$base/rw/home/upper,workdir=$base/rw/home/work,x-systemd.requires-mounts-for=$base/home 0 0" \
  "$work/sysroot/etc/fstab"
check "look keeps /home's writes in the root's RAM layer" test -d "$base/rw/home/upper" -a -d "$base/rw/home/work"
check "look leaves no other /home entry" test "$(grep -c " /home " "$work/sysroot/etc/fstab")" = 1

rm -f "$work/mount.log"
hook "$mod/ryoku-snapshot-preview.sh" "root=UUID=abc ro rootflags=subvol=root"
check "no look argument, nothing is mounted" absent "$work/mount.log"
hook "$mod/ryoku-snapshot-preview.sh" "root=UUID=abc rd.ryoku.preview=../x"
check "look refuses a path outside the filesystem" absent "$work/mount.log"

# case 3
grub="$work/boot/grub2"
theme="$grub/themes/ryoku"
mkdir -p "$grub" "$work/etc"
printf 'GRUB_TIMEOUT=1\nGRUB_DEFAULT=saved\nGRUB_TERMINAL_OUTPUT="console"\nGRUB_ENABLE_BLSCFG=true\n' >"$work/etc/grub"
printf 'PFF2' >"$work/unicode.pf2"
printf 'face' >"$work/face.ttf"
cat >"$stubs/mkconfig" <<EOF_STUB
#!/bin/sh
echo run >>"$work/mkconfig.log"
sh "$bm/grub/15_ryoku_snapshots" >"\$2"
EOF_STUB
cat >"$stubs/mkfont" <<'EOF_STUB'
#!/bin/sh
out=
size=
name=
while [ $# -gt 1 ]; do
  case "$1" in
    -o) out=$2; shift ;;
    -s) size=$2; shift ;;
    -n) name=$2; shift ;;
  esac
  shift
done
printf 'PFF2 %s %s\n' "$name" "$size" >"$out"
EOF_STUB
chmod +x "$stubs/mkconfig" "$stubs/mkfont"
menu() {
  RYOKU_GRUB_DIR="$grub" RYOKU_GRUB_DEFAULTS="$work/etc/grub" RYOKU_GRUB_THEME_SRC="$bm/grub/theme" \
    RYOKU_GRUB_FONT_SRC="$work/unicode.pf2" RYOKU_GRUB_MKCONFIG="$stubs/mkconfig" \
    RYOKU_GRUB_MKFONT="$stubs/mkfont" RYOKU_GRUB_FONT_FACE="${FACE-$work/face.ttf}" \
    bash "$bm/grub/ryoku-grub-menu" "$@"
}
runs() { test "$(wc -l <"$work/mkconfig.log" 2>/dev/null || echo 0)" = "$1"; }

check "the theme draws the wallpaper" line "$bm/grub/theme/theme.txt" 'desktop-image: "ryoku-wall.png"'
check "the theme ships its wallpaper" test -f "$bm/grub/theme/ryoku-wall.png"
check "the theme ships its selection bar" test -f "$bm/grub/theme/select_c.png"
for size in 16 20 24; do
  check "the theme's $size px font is one install builds" grep -q "\"Ryoku Mono Regular $size\"" "$bm/grub/theme/theme.txt"
done
check "the theme names only fonts install builds" \
  test -z "$(grep -o '"[A-Za-z ]* [0-9][0-9]*"' "$bm/grub/theme/theme.txt" | grep -vE '"Ryoku Mono Regular (16|20|24)"')"

mkdir -p "$theme" && printf 'old' >"$theme/background.png" && printf 'old' >"$theme/unicode.pf2"
menu install
check "install drops what the earlier theme left" test ! -e "$theme/background.png" -a ! -e "$theme/unicode.pf2"
check "install copies the theme onto /boot" test -f "$theme/theme.txt" -a -f "$theme/ryoku-wall.png" -a -f "$theme/select_c.png"
for size in 16 20 24; do
  check "install builds Ryoku Mono at $size px" line "$theme/ryoku-mono-$size.pf2" "PFF2 Ryoku Mono $size"
done
check "install turns on the graphical terminal" line "$work/etc/grub" 'GRUB_TERMINAL_OUTPUT="gfxterm"'
check "install points GRUB at the theme" line "$work/etc/grub" "GRUB_THEME=\"$theme/theme.txt\""
check "install takes the font from /boot, not the root filesystem" line "$work/etc/grub" "GRUB_FONT=\"$theme/ryoku-mono-20.pf2\""
check "install keeps the rest of the defaults" line "$work/etc/grub" "GRUB_ENABLE_BLSCFG=true"
check "install rebuilds grub.cfg with the snapshot menu" has "$grub/grub.cfg" "ryoku-snapshots.cfg"
menu install
check "a second install changes nothing and does not rebuild" runs 1
check "a second install does not repeat a key" test "$(grep -c '^GRUB_THEME=' "$work/etc/grub")" = 1
check "a second install leaves no staging files" test -z "$(find "$theme" -name '*.new')"
: >"$grub/grub.cfg"
menu install
check "install rebuilds a grub.cfg that lost the snapshot menu" runs 2
echo stale >>"$theme/theme.txt"
menu install
check "install rebuilds grub.cfg for a changed theme" runs 3
check "install puts the shipped theme back" cmp -s "$bm/grub/theme/theme.txt" "$theme/theme.txt"

mkdir -p "$work/boot/ryoku/snapshots/k" && : >"$grub/ryoku-snapshots.cfg"
menu purge
check "purge restores the text terminal" line "$work/etc/grub" 'GRUB_TERMINAL_OUTPUT="console"'
check "purge drops the theme keys" test -z "$(grep -E '^GRUB_(THEME|FONT)=' "$work/etc/grub")"
check "purge removes the theme, the menu and the kernel copies" \
  test ! -e "$theme" -a ! -e "$grub/ryoku-snapshots.cfg" -a ! -e "$work/boot/ryoku"
check "purge leaves grub.cfg to %postun" test -f "$grub/grub.cfg"

menu install
FACE=$work/missing.ttf menu install
check "without a font face, GRUB's Unifont stands in" cmp -s "$work/unicode.pf2" "$theme/unicode.pf2"
check "and GRUB_FONT names it" line "$work/etc/grub" "GRUB_FONT=\"$theme/unicode.pf2\""
check "and the Ryoku Mono fonts nothing names go" test -z "$(find "$theme" -name 'ryoku-mono-*.pf2')"
menu purge

printf '#!/bin/sh\nexit 1\n' >"$stubs/badfont" && chmod +x "$stubs/badfont"
menu install
menu_badfont() {
  RYOKU_GRUB_DIR="$grub" RYOKU_GRUB_DEFAULTS="$work/etc/grub" RYOKU_GRUB_THEME_SRC="$bm/grub/theme" \
    RYOKU_GRUB_FONT_SRC="$work/unicode.pf2" RYOKU_GRUB_MKCONFIG="$stubs/mkconfig" \
    RYOKU_GRUB_MKFONT="$stubs/badfont" RYOKU_GRUB_FONT_FACE="$work/face.ttf" \
    bash "$bm/grub/ryoku-grub-menu" install
}
menu_badfont
check "a face grub2-mkfont rejects falls back to GRUB's Unifont" line "$work/etc/grub" "GRUB_FONT=\"$theme/unicode.pf2\""
check "and the font GRUB_FONT names exists" test -f "$theme/unicode.pf2"
check "and no half-built font is left" test -z "$(find "$theme" -name '*.new')"
menu purge

printf 'GRUB_TERMINAL_OUTPUT="serial console"\n' >"$work/etc/grub"
menu install
check "install keeps a serial terminal" line "$work/etc/grub" 'GRUB_TERMINAL_OUTPUT="serial console"'
check "install still themes the graphical menu there" grep -q '^GRUB_THEME=' "$work/etc/grub"
menu purge
check "purge leaves a serial terminal alone" line "$work/etc/grub" 'GRUB_TERMINAL_OUTPUT="serial console"'

rm -rf "$grub"
before=$(wc -l <"$work/mkconfig.log")
menu install
check "install does nothing without a GRUB directory" runs "$before"

exit "$fail"

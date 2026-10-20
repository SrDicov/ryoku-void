#!/usr/bin/env bash
set -euo pipefail

PROFILE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
	printf 'usage: %s INPUT_ISO OUTPUT_ISO TITLE LIMINE_ROOT EFI_ACTION_DIR\n' "${0##*/}" >&2
	exit 2
}

[[ $# -eq 5 ]] || usage
INPUT_ISO=$1
OUTPUT_ISO=$2
TITLE=$3
LIMINE_ROOT=$4
EFI_ACTION_DIR=$5
LIMINE_SHARE=$LIMINE_ROOT/usr/share/limine
LIMINE_BIN=$LIMINE_ROOT/usr/bin/limine

[[ -f $INPUT_ISO ]] || { printf 'Limine ISO conversion: image not found: %s\n' "$INPUT_ISO" >&2; exit 1; }
[[ $INPUT_ISO != "$OUTPUT_ISO" ]] \
	|| { printf 'Limine ISO conversion: input and output must differ\n' >&2; exit 1; }
[[ ! -e $OUTPUT_ISO ]] \
	|| { printf 'Limine ISO conversion: output already exists: %s\n' "$OUTPUT_ISO" >&2; exit 1; }
[[ $TITLE != *$'\n'* && -n $TITLE ]] \
	|| { printf 'Limine ISO conversion: invalid title\n' >&2; exit 1; }
for file in limine-bios-cd.bin limine-uefi-cd.bin limine-bios.sys BOOTX64.EFI; do
	[[ -f $LIMINE_SHARE/$file ]] \
		|| { printf 'Limine ISO conversion: asset not found: %s\n' "$LIMINE_SHARE/$file" >&2; exit 1; }
done
for file in restart.efi shutdown.efi; do
	[[ -f $EFI_ACTION_DIR/$file ]] \
		|| { printf 'Limine ISO conversion: action not found: %s\n' "$EFI_ACTION_DIR/$file" >&2; exit 1; }
done
[[ -x $LIMINE_BIN ]] \
	|| { printf 'Limine ISO conversion: installer not found: %s\n' "$LIMINE_BIN" >&2; exit 1; }
command -v xorriso >/dev/null 2>&1 \
	|| { printf 'Limine ISO conversion: xorriso is required\n' >&2; exit 1; }

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/ryoku-limine-iso.XXXXXX")
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT

config=$(<"$PROFILE_DIR/limine.conf.in")
printf '%s\n' "${config//@RYOKU_ISO_TITLE@/$TITLE}" > "$tmp_dir/limine.conf"
config=$(<"$PROFILE_DIR/ventoy-grub.cfg.in")
printf '%s\n' "${config//@RYOKU_ISO_TITLE@/$TITLE}" > "$tmp_dir/ventoy-grub.cfg"
truncate -s 32768 "$tmp_dir/system-area"

xorriso \
	-indev "$INPUT_ISO" \
	-outdev "$OUTPUT_ISO" \
	-boot_image any discard \
	-rm_r /boot/grub /boot/isolinux -- \
	-mkdir /boot/limine /EFI /EFI/BOOT -- \
	-map "$tmp_dir/limine.conf" /boot/limine/limine.conf \
	-map "$LIMINE_SHARE/limine-bios-cd.bin" /boot/limine/limine-bios-cd.bin \
	-map "$LIMINE_SHARE/limine-uefi-cd.bin" /boot/limine/limine-uefi-cd.bin \
	-map "$LIMINE_SHARE/limine-bios.sys" /boot/limine/limine-bios.sys \
	-map "$LIMINE_SHARE/BOOTX64.EFI" /EFI/BOOT/BOOTX64.EFI \
	-map "$tmp_dir/ventoy-grub.cfg" /EFI/BOOT/grub.cfg \
	-map "$EFI_ACTION_DIR/restart.efi" /boot/limine/restart.efi \
	-map "$EFI_ACTION_DIR/shutdown.efi" /boot/limine/shutdown.efi \
	-volid VOID_LIVE \
	-joliet on \
	-rockridge on \
	-boot_image any system_area="$tmp_dir/system-area" \
	-boot_image any partition_table=on \
	-boot_image any partition_cyl_align=off \
	-boot_image any efi_boot_part=--efi-boot-image \
	-boot_image any cat_path=/boot/limine/boot.catalog \
	-boot_image any bin_path=/boot/limine/limine-bios-cd.bin \
	-boot_image any platform_id=0x00 \
	-boot_image any emul_type=no_emulation \
	-boot_image any load_size=2048 \
	-boot_image any boot_info_table=on \
	-boot_image any next \
	-boot_image any efi_path=/boot/limine/limine-uefi-cd.bin \
	-boot_image any platform_id=0xef \
	-boot_image any emul_type=no_emulation \
	-commit_eject all

"$LIMINE_BIN" bios-install "$OUTPUT_ISO"

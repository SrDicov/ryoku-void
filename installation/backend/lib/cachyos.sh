#!/usr/bin/env bash
# shellcheck shell=bash
# Make the installed target a CachyOS system the way CachyOS's own installer
# does: the pacman.conf CachyOS ships (CachyOS-Live-ISO pacman-more.conf), the
# CPU's optimized repositories above [cachyos] (cachyos-calamares
# detect-architecture: znver4, else v4, else v3), and the CachyOS key trusted
# from the installed cachyos-keyring (offline, no keyserver).
#
# The install ITSELF pulls every package (the CachyOS kernel, CachyOS's pacman)
# from the baked [offline] repo (lib/offline.sh), which holds generic x86-64
# builds so it installs on any CPU, as CachyOS's own offline install does. This
# step wires future `pacman -Syu` to CachyOS so the box stays a CachyOS box: a
# CPU with a tier moves onto that tier's builds on the first -Syu, since every
# tier build carries a higher pkgrel than the generic one.

# ryoku_cachyos_replaced: the base.packages names a CachyOS install never
# carries (system/packages/cachyos.replaces).
ryoku_cachyos_replaced() {
  local file="$RYOKU_REPO/system/packages/cachyos.replaces"
  [[ -f $file ]] || return 0
  grep -vE '^[[:space:]]*(#|$)' "$file"
}

# ryoku_cachyos_drops: leave the replaced names out the way a deselected app is
# left out: RYOKU_DROP_PACKAGES keeps them out of pacstrap, and the provisioning
# ledger it seeds (deploy.sh ryoku_seed_provisioned) keeps `ryoku update` from
# delivering them later.
ryoku_cachyos_drops() {
  local p
  while IFS= read -r p; do
    _ryoku_append_drop "$p"
  done < <(ryoku_cachyos_replaced)
  export RYOKU_DROP_PACKAGES
}

# ryoku_cachyos_is_zen45 CPUINFO: a Zen 4 or Zen 5 CPU with AVX-512, the CPUs
# CachyOS gives its znver4 builds. Same family/model table as
# detect-architecture.
ryoku_cachyos_is_zen45() {
  local cpuinfo=$1 family model
  grep -qw avx512f "$cpuinfo" 2>/dev/null || return 1
  family=$(awk -F: '/^cpu family/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$cpuinfo")
  model=$(awk -F: '/^model[[:space:]]*:/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$cpuinfo")
  [[ $family =~ ^[0-9]+$ && $model =~ ^[0-9]+$ ]] || return 1
  case $family in
    25) (( (model >= 0x10 && model <= 0x1f) || (model >= 0x60 && model <= 0xaf) )) ;;
    26) return 0 ;;
    *) return 1 ;;
  esac
}

# ryoku_cachyos_cpu_level: the CachyOS repository tier this CPU runs (znver4,
# v4, v3), or nothing for a CPU below x86-64-v3.
ryoku_cachyos_cpu_level() {
  local isa
  isa=$(LC_ALL=C /lib/ld-linux-x86-64.so.2 --help 2>/dev/null) || isa=""
  if ryoku_cachyos_is_zen45 /proc/cpuinfo; then
    printf 'znver4\n'
  elif grep -qF 'x86-64-v4 (supported' <<<"$isa"; then
    printf 'v4\n'
  elif grep -qF 'x86-64-v3 (supported' <<<"$isa"; then
    printf 'v3\n'
  fi
}

# ryoku_cachyos_tier_repos LEVEL: the repository stanzas for a CPU tier, in
# detect-architecture's order. Nothing for an unknown or empty tier.
ryoku_cachyos_tier_repos() {
  local level=$1 list repo
  local -a repos=()
  case $level in
    znver4) list=cachyos-v4-mirrorlist; repos=(cachyos-znver4 cachyos-core-znver4 cachyos-extra-znver4) ;;
    v4) list=cachyos-v4-mirrorlist; repos=(cachyos-v4 cachyos-extra-v4 cachyos-core-v4) ;;
    v3) list=cachyos-v3-mirrorlist; repos=(cachyos-v3 cachyos-extra-v3 cachyos-core-v3) ;;
    *) return 0 ;;
  esac
  for repo in "${repos[@]}"; do
    printf '[%s]\nInclude = /etc/pacman.d/%s\n\n' "$repo" "$list"
  done
}

# ryoku_cachyos_pacman_conf CONF LEVEL: write CachyOS's pacman.conf with the
# tier's repositories above [cachyos]. deploy.sh appends [ryoku] after it, and
# the installer's temporary [offline] stanza comes and goes in between
# (lib/offline.sh).
ryoku_cachyos_pacman_conf() {
  local conf=$1 level=${2:-}
  write_file "$conf" <<EOF
# /etc/pacman.conf, as CachyOS installs it. See pacman.conf(5).

[options]
HoldPkg     = pacman glibc
Architecture = auto
Color
ILoveCandy
VerbosePkgLists
DisableDownloadTimeout
ParallelDownloads = 10
DownloadUser = alpm
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

$(ryoku_cachyos_tier_repos "$level")
[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
}

# ryoku_cachyos_arch_check CONF LEVEL: `Architecture = auto` takes in the
# x86_64_v3/v4 packages only under CachyOS's pacman. A target that ended up
# with Arch's pacman (a networked install pacstrapped from Arch mirrors)
# resolves it to x86_64 alone and would reject its own tier, so name it there.
ryoku_cachyos_arch_check() {
  local conf=$1 level=$2 want arches
  case $level in
    v3) want=x86_64_v3 ;;
    v4|znver4) want='x86_64_v3 x86_64_v4' ;;
    *) return 0 ;;
  esac
  arches=$(arch-chroot /mnt pacman-conf --config /etc/pacman.conf Architecture 2>/dev/null) || arches=""
  grep -qx "${want##* }" <<<"$arches" && return 0
  log 'cachyos: the target pacman does not resolve Architecture = auto to %s; naming it explicitly' "$want"
  run sed -i "s|^Architecture = auto\$|Architecture = auto $want|" "$conf"
}

ryoku_cachyos_repo() {
  local conf=/mnt/etc/pacman.conf level
  level=$(ryoku_cachyos_cpu_level)
  if [[ -n ${RYOKU_DRYRUN:-} ]]; then
    log "DRYRUN: write CachyOS's pacman.conf with the ${level:-baseline} repositories above [cachyos], populate the cachyos keyring in the target"
    return 0
  fi
  log "cachyos: writing CachyOS's pacman.conf (${level:-baseline} repositories) into the target"
  ryoku_cachyos_pacman_conf "$conf" "$level"
  ryoku_cachyos_arch_check "$conf" "$level"
  ryoku_cachyos_keyring
}

# trust the CachyOS key from the INSTALLED cachyos-keyring (no keyserver, so it
# works offline). the recv/lsign path is the online fallback for a box without
# the package.
ryoku_cachyos_keyring() {
  if arch-chroot /mnt pacman-key --populate cachyos >/dev/null 2>&1; then
    log "cachyos: trusted the CachyOS signing key via the installed keyring"
    return 0
  fi
  log "cachyos: keyring populate failed (cachyos-keyring absent?); a later -Syu can 'pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com'"
}

# Optional CachyOS layer for the plain Arch variant. It keeps Arch userland and
# the stock kernel, adding only the v3 kernel/tuning repository used by the
# Ryostore bundle.
ryoku_cachyos_layer() {
  [[ ${RYOKU_VARIANT:-plain} == plain && ${RYOKU_CACHYOS_LAYER:-0} == 1 ]] || return 0
  RYOKU_CACHYOS_LAYER_ACTIVE=0
  export RYOKU_CACHYOS_LAYER_ACTIVE
  if [[ -n ${RYOKU_DRYRUN:-} ]]; then
    log 'DRYRUN: check the target CPU for x86-64-v3 and the CachyOS mirror for reachability, enable [cachyos-v3] and multilib with the shipped helpers, then run pacman -Syu for linux-cachyos linux-cachyos-headers cachyos-settings ananicy-cpp cachyos-ananicy-rules scx-scheds proton-cachyos-native'
    RYOKU_CACHYOS_LAYER_ACTIVE=1
    export RYOKU_CACHYOS_LAYER_ACTIVE
    return 0
  fi
  if ! arch-chroot /mnt sh -c \
    "/lib/ld-linux-x86-64.so.2 --help 2>/dev/null | grep -q 'x86-64-v3 (supported'"; then
    log 'CachyOS layer: this CPU does not support x86-64-v3; skipping the layer'
    return 0
  fi
  local mirror_probe=https://mirror.cachyos.org/repo/x86_64_v3/cachyos-v3/cachyos-v3.db
  if ! curl -fsSI --connect-timeout 5 --max-time 10 -o /dev/null "$mirror_probe"; then
    log 'CachyOS layer: the CachyOS mirror is unreachable; skipping the layer. Add it later from Ryostore > CachyOS Layer.'
    return 0
  fi

  if ! ryoku_cachyos_layer_helper ryoku-pkg-cachyos ||
    ! ryoku_cachyos_layer_helper ryoku-pkg-multilib; then
    log 'CachyOS layer: could not add the CachyOS or multilib repository; skipping the layer. Add it later from Ryostore > CachyOS Layer.'
    return 0
  fi

  local -a packages=(
    linux-cachyos linux-cachyos-headers cachyos-settings ananicy-cpp
    cachyos-ananicy-rules scx-scheds proton-cachyos-native
  )
  log 'CachyOS layer: installing %s' "${packages[*]}"
  if ! run arch-chroot /mnt pacman -Syu --needed --noconfirm --noprogressbar "${packages[@]}"; then
    log 'CachyOS layer: its packages did not install; the install goes on without it. Add it later from Ryostore > CachyOS Layer.'
    return 0
  fi
  RYOKU_CACHYOS_LAYER_ACTIVE=1
  export RYOKU_CACHYOS_LAYER_ACTIVE
}

# The helpers ship with the desktop; the payload copy covers a target that does
# not carry them yet. A failure returns non-zero so the caller can skip.
ryoku_cachyos_layer_helper() {
  local name=$1 source="$RYOKU_REPO/system/extras/$1" target="/root/$1" rc=0
  if [[ -x /mnt/usr/bin/$name ]]; then
    run arch-chroot /mnt env XDG_RUNTIME_DIR=/tmp "/usr/bin/$name"
    return
  fi
  if [[ ! -x $source ]]; then
    log 'CachyOS layer: helper %s is missing' "$source"
    return 1
  fi
  if ! run cp "$source" "/mnt$target" || ! run chmod 755 "/mnt$target"; then
    return 1
  fi
  run arch-chroot /mnt env XDG_RUNTIME_DIR=/tmp "$target" || rc=$?
  run rm -f "/mnt$target"
  return "$rc"
}

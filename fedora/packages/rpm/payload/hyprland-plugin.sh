# shellcheck shell=bash
: "${pkgdir:?}"

hyprland_version_header() {
  local prefix candidate
  prefix=$(pkg-config --variable=prefix hyprland)
  for candidate in \
    "$prefix/hyprland/src/version.h" \
    "$prefix/include/hyprland/src/version.h" \
    /usr/include/hyprland/src/version.h; do
    if [[ -f $candidate ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
  return 1
}

hyprland_abi() {
  local header
  header=$(hyprland_version_header)
  value() {
    sed -n "s/^#define $1 *\"\([^\"]*\)\".*/\1/p" "$header" | sed 's/\.[^.]*$//'
  }
  printf '%s_aq_%s_hu_%s_hg_%s_hc_%s_hlg_%s\n' \
    "$(sed -n 's/^#define GIT_COMMIT_HASH *"\([^"]*\)".*/\1/p' "$header")" \
    "$(value AQUAMARINE_VERSION)" \
    "$(value HYPRUTILS_VERSION)" \
    "$(value HYPRGRAPHICS_VERSION)" \
    "$(value HYPRCURSOR_VERSION)" \
    "$(value HYPRLANG_VERSION)"
}

install_plugin_abi() {
  local name=$1
  hyprland_abi | install -Dm644 /dev/stdin \
    "$pkgdir/usr/lib/hyprland/plugins/$name.abi"
}

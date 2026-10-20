# shellcheck shell=bash
: "${startdir:?}" "${srcdir:?}" "${pkgdir:?}"
source "$startdir/hyprland-plugin.sh"
_repo="$startdir/../../../.."

# The plugin only: the samples and the importer are their own RPM
# (ryoku-keysounds-profiles), shared with niri's engine, so this package depends
# on that one instead of owning a second copy of /usr/share/ryoku/keysounds.
build() {
  cp -a "$_repo/ryoku/hyprland/plugins/keysounds" "$srcdir/keysounds"
  make -C "$srcdir/keysounds" keysounds.so
}

package() {
  install -Dm755 "$srcdir/keysounds/keysounds.so" \
    "$pkgdir/usr/lib/hyprland/plugins/keysounds.so"
  install_plugin_abi keysounds
  install -Dm644 -t "$pkgdir/usr/share/ryoku/hypr-plugins/keysounds" \
    "$_repo/ryoku/hyprland/plugins/keysounds/main.cpp" \
    "$_repo/ryoku/hyprland/plugins/keysounds/Makefile" \
    "$_repo/ryoku/hyprland/plugins/keysounds/hyprpm.toml" \
    "$_repo/ryoku/hyprland/plugins/keysounds/README.md"
}

# shellcheck shell=bash
: "${startdir:?}" "${srcdir:?}" "${pkgdir:?}"
source "$startdir/hyprland-plugin.sh"
_repo="$startdir/../../../.."

build() {
  cp -a "$_repo/.rpm-ryoku-hypr-plugins/hyprland-plugins" "$srcdir/"
  make -C "$srcdir/hyprland-plugins/hyprbars" all
  make -C "$srcdir/hyprland-plugins/hyprfocus" all
  make -C "$srcdir/hyprland-plugins/borders-plus-plus" all
}

package() {
  local name
  for name in hyprbars hyprfocus borders-plus-plus; do
    install -Dm755 "$srcdir/hyprland-plugins/$name/$name.so" \
      "$pkgdir/usr/lib/hyprland/plugins/$name.so"
    install_plugin_abi "$name"
  done
}

# shellcheck shell=bash
: "${startdir:?}" "${srcdir:?}" "${pkgdir:?}"
source "$startdir/hyprland-plugin.sh"
_repo="$startdir/../../../.."

build() {
  cp -a "$_repo/.rpm-hypr-dynamic-cursors/hypr-dynamic-cursors" "$srcdir/"
  make -C "$srcdir/hypr-dynamic-cursors" all
}

package() {
  install -Dm755 "$srcdir/hypr-dynamic-cursors/out/dynamic-cursors.so" \
    "$pkgdir/usr/lib/hyprland/plugins/dynamic-cursors.so"
  install_plugin_abi dynamic-cursors
}

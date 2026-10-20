# shellcheck shell=bash
: "${startdir:?}" "${srcdir:?}" "${pkgdir:?}"
source "$startdir/hyprland-plugin.sh"
_repo="$startdir/../../../.."

build() {
  cp -a "$_repo/.rpm-hyprglass/hyprglass" "$srcdir/"
  make -C "$srcdir/hyprglass"
}

package() {
  install -Dm755 "$srcdir/hyprglass/hyprglass.so" \
    "$pkgdir/usr/lib/hyprland/plugins/hyprglass.so"
  install_plugin_abi hyprglass
}

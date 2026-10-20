# shellcheck shell=bash
: "${startdir:?}" "${srcdir:?}" "${pkgdir:?}"
source "$startdir/hyprland-plugin.sh"
_repo="$startdir/../../../.."

build() {
  cp -a "$_repo/.rpm-imgborders/imgborders" "$srcdir/"
  cmake -S "$srcdir/imgborders" -B "$srcdir/imgborders/build" \
    -DCMAKE_BUILD_TYPE=Release
  cmake --build "$srcdir/imgborders/build"
}

package() {
  install -Dm755 "$srcdir/imgborders/build/libimgborders.so" \
    "$pkgdir/usr/lib/hyprland/plugins/imgborders.so"
  install_plugin_abi imgborders
}

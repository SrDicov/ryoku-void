# shellcheck shell=bash
: "${startdir:?}" "${srcdir:?}" "${pkgdir:?}"
source "$startdir/hyprland-plugin.sh"
_repo="$startdir/../../../.."

build() {
  cp -a "$_repo/.rpm-hyprgrass/hyprgrass" "$srcdir/"
  mkdir -p "$srcdir/pkgconfig"
  cat > "$srcdir/pkgconfig/glm.pc" <<'PC'
prefix=/usr
includedir=${prefix}/include

Name: glm
Description: C++ OpenGL math library
Version: 1.0.3
Cflags: -I${includedir}
PC
  PKG_CONFIG_PATH="$srcdir/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
    meson setup "$srcdir/hyprgrass/build" "$srcdir/hyprgrass"
  ninja -C "$srcdir/hyprgrass/build"
}

package() {
  install -Dm755 "$srcdir/hyprgrass/build/src/libhyprgrass.so" \
    "$pkgdir/usr/lib/hyprland/plugins/hyprgrass.so"
  install_plugin_abi hyprgrass
}

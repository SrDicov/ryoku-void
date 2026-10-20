# shellcheck shell=bash
startdir=${startdir:?stage-package.sh must set startdir}
srcdir=${srcdir:?stage-package.sh must set srcdir}
pkgdir=${pkgdir:?stage-package.sh must set pkgdir}
pkgver=${RYOKU_PKGVER:?stage-package.sh must set RYOKU_PKGVER}
_repo="$startdir/../../../.."
_payload="$_repo/release/packages/ryoku-desktop-hyprland/payload.sh"

build() {
  RYOKU_SRC="$_repo" RYOKU_BUILD_DIR="$srcdir" RYOKU_PKGVER="$pkgver" \
    "$_payload" build
}

package() {
  RYOKU_SRC="$_repo" RYOKU_BUILD_DIR="$srcdir" RYOKU_PKGVER="$pkgver" \
    "$_payload" install "$pkgdir" systemd

  # Fedora's portal package uses its bundled picker name.
  sed -i \
    's/custom_picker_binary = hyprland-preview-share-picker/custom_picker_binary = hyprland-share-picker/' \
    "$pkgdir/usr/share/ryoku/config/hypr/xdph.conf"
}

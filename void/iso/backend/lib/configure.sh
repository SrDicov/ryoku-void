#!/usr/bin/env bash

void_configure() {
  void_cfg_locale
  void_cfg_keymap
  void_cfg_timezone
  void_cfg_hostname
  void_cfg_user
  void_cfg_sudo
  ryoku_dracut_crypttab
}

void_cfg_locale() {
  log 'locale: %s' "$RYOKU_LOCALE"
  local locale_re=${RYOKU_LOCALE//./\\.}
  run_sh "if grep -qE '^#?[[:space:]]*${locale_re}[[:space:]]+UTF-8' /mnt/etc/default/libc-locales; then sed -i -E 's|^#?[[:space:]]*(${locale_re}[[:space:]]+UTF-8)|\\1|' /mnt/etc/default/libc-locales; else printf '%s UTF-8\\n' '$RYOKU_LOCALE' >> /mnt/etc/default/libc-locales; fi"
  write_file /mnt/etc/locale.conf <<EOF
LANG=$RYOKU_LOCALE
EOF
  void_chroot xbps-reconfigure -f glibc-locales
}

void_cfg_keymap() {
  log 'console keymap: %s' "$RYOKU_KEYMAP"
  run_sh "if grep -q '^KEYMAP=' /mnt/etc/rc.conf; then sed -i 's|^KEYMAP=.*|KEYMAP=$RYOKU_KEYMAP|' /mnt/etc/rc.conf; else printf '\\nKEYMAP=%s\\n' '$RYOKU_KEYMAP' >> /mnt/etc/rc.conf; fi"
  write_file /mnt/etc/vconsole.conf <<EOF
KEYMAP=$RYOKU_KEYMAP
EOF
  local layout=${RYOKU_XKB_LAYOUT:-$RYOKU_KEYMAP} variant=${RYOKU_XKB_VARIANT:-}
  if [[ $layout != us || -n $variant ]]; then
    run mkdir -p /mnt/etc/X11/xorg.conf.d
    write_file /mnt/etc/X11/xorg.conf.d/00-keyboard.conf <<EOF
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "$layout"
    Option "XkbVariant" "$variant"
EndSection
EOF
  fi
}

void_cfg_timezone() {
  local timezone
  ryoku_resolve_timezone "$RYOKU_TIMEZONE"
  timezone=$RYOKU_RESOLVED_TIMEZONE
  log 'timezone: %s' "$timezone"
  run ln -sfn "/usr/share/zoneinfo/$timezone" /mnt/etc/localtime
  void_chroot hwclock --systohc || true
}

void_cfg_hostname() {
  log 'hostname: %s' "$RYOKU_HOSTNAME"
  write_file /mnt/etc/hostname <<EOF
$RYOKU_HOSTNAME
EOF
}

void_cfg_user() {
  local shell=/usr/bin/$RYOKU_LOGIN_SHELL
  [[ $RYOKU_LOGIN_SHELL != fish ]] || shell=/usr/bin/fish
  if [[ -z ${RYOKU_DRYRUN:-} && ! -x /mnt$shell ]]; then
    die 'login shell %s is missing from the target' "$shell"
  fi
  log 'user: %s (wheel,audio,video,input,kvm; shell %s)' "$RYOKU_USERNAME" "$shell"
  void_chroot useradd -m -G wheel,audio,video,input,kvm -s "$shell" "$RYOKU_USERNAME"
  printf '%s:%s\n' "$RYOKU_USERNAME" "$RYOKU_PASSWORD_HASH" | run_secret \
    "chroot /mnt chpasswd -e (user:hash via stdin)" chroot /mnt chpasswd -e
  printf 'root:%s\n' "$RYOKU_PASSWORD_HASH" | run_secret \
    "chroot /mnt chpasswd -e (root:hash via stdin)" chroot /mnt chpasswd -e
}

void_cfg_sudo() {
  log "sudo: wheel group"
  run mkdir -p /mnt/etc/sudoers.d
  write_file /mnt/etc/sudoers.d/10-wheel <<'EOF'
%wheel ALL=(ALL:ALL) ALL
EOF
  run chmod 0440 /mnt/etc/sudoers.d/10-wheel
}

#!/bin/sh
set -eu

root=${1:?rootfs path is required}
service_root=$root/etc/runit/runsvdir/default
mkdir -p "$service_root" "$root/var/log" "$root/var/db/xbps/keys"

# iwd is NetworkManager's Wi-Fi backend here (etc/NetworkManager/conf.d), and
# Void ships it without a D-Bus activation file, so it runs supervised or Wi-Fi
# never associates; wpa_supplicant, the TUI's fallback, is bus-activated.
for service in dbus NetworkManager iwd seatd; do
	[ -d "$root/etc/sv/$service" ] || {
		printf 'post-setup: required live service is missing: %s\n' "$service" >&2
		exit 1
	}
	ln -snf "/etc/sv/$service" "$service_root/$service"
done

# Keep the stock tty1 PAM login; ttyS0 provides unattended recovery.
for getty in agetty-tty1 agetty-ttyS0; do
	[ -x "$root/etc/sv/$getty/run" ] || {
		printf 'post-setup: stock getty service is missing: %s\n' "$getty" >&2
		exit 1
	}
	rm -f "$root/etc/sv/$getty/conf"
done
printf '%s\n' 'GETTY_ARGS="--autologin root --noclear"' \
	> "$root/etc/sv/agetty-tty1/conf"
cat > "$root/etc/sv/agetty-ttyS0/conf" <<'EOF'
GETTY_ARGS="-L -8 --autologin root --noclear"
BAUD_RATE=115200
TERM_NAME=vt100
EOF

chmod 0755 \
	"$root/usr/local/bin/ryoku-installer-session" \
	"$root/usr/local/bin/ryoku-install" \
	"$root/usr/local/bin/ryoku-tui" \
	"$root/usr/local/lib/ryoku/installer-session" \
	"$root/usr/local/lib/ryoku/backend/ryoku-install"
chmod 0644 "$root/etc/sv/agetty-tty1/conf" "$root/etc/sv/agetty-ttyS0/conf"

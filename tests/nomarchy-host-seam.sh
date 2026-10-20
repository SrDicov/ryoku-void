#!/usr/bin/env bash
# Nomarchy's omarchy-* commands reach the system through ryoku-host, so they
# answer on Void and Fedora as they do on Arch: package probes ask the host's
# package manager, and reboot and shutdown go through the host's power seam.
#
# Every command those branches could reach (ryoku-host, pacman, systemctl,
# loginctl, sudo) is faked first on PATH and logged: a regression must fail
# here, never power off the machine running the test.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
bin="$here/../ryoku/shell/nomarchy/bin"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

for tool in systemctl loginctl sudo; do
  printf '#!/usr/bin/env bash\necho "%s $*" >>"$FAKE_LOG"\nexit 0\n' "$tool" >"$tmp/$tool"
done
cat >"$tmp/ryoku-host" <<'EOF'
#!/usr/bin/env bash
echo "ryoku-host $*" >>"$FAKE_LOG"
case "$1 ${2:-}" in
  "pkgmgr ") echo "$FAKE_PKGMGR" ;;
  "pkg installed") [[ $3 == present-pkg ]] ;;
  "power reboot" | "power poweroff") exit 0 ;;
  *) exit 4 ;;
esac
EOF
cat >"$tmp/pacman" <<'EOF'
#!/usr/bin/env bash
echo "pacman $*" >>"$FAKE_LOG"
[[ $1 == -Q && $2 == present-pkg ]]
EOF
chmod +x "$tmp"/*
export PATH="$tmp:$PATH" FAKE_LOG="$tmp/log"

for manager in xbps dnf pacman; do
  export FAKE_PKGMGR=$manager
  : >"$FAKE_LOG"
  "$bin/omarchy-pkg-present" present-pkg || fail "$manager: an installed package reads as missing"
  ! "$bin/omarchy-pkg-present" absent-pkg || fail "$manager: an absent package reads as present"
  "$bin/omarchy-pkg-missing" absent-pkg || fail "$manager: an absent package is not reported missing"
  if [[ $manager == pacman ]]; then
    grep -q '^pacman -Q present-pkg$' "$FAKE_LOG" || fail "pacman: the probe did not ask pacman"
  else
    ! grep -q '^pacman' "$FAKE_LOG" || fail "$manager: the probe called pacman"
    grep -q '^ryoku-host pkg installed present-pkg$' "$FAKE_LOG" || fail "$manager: the probe did not ask ryoku-host"
  fi
done

: >"$FAKE_LOG"
"$bin/omarchy-system-reboot"
"$bin/omarchy-system-shutdown"
grep -qx 'ryoku-host power reboot' "$FAKE_LOG" || fail "reboot did not go through ryoku-host: $(cat "$FAKE_LOG")"
grep -qx 'ryoku-host power poweroff' "$FAKE_LOG" || fail "shutdown did not go through ryoku-host: $(cat "$FAKE_LOG")"
! grep -q '^systemctl' "$FAKE_LOG" || fail "reboot or shutdown called systemctl"

echo "nomarchy-host-seam: all checks passed"

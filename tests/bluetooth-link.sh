#!/usr/bin/env bash

set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/bluetoothctl" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail

while [[ ${1:-} == --agent || ${1:-} == --timeout ]]; do
  shift 2
done

command=${1:-}
arg=${2:-}
state=${BT_FAKE_STATE:?}
log=${BT_FAKE_LOG:?}

case $command in
  scan)
    [[ $arg == off ]]
    printf 'off\n' >"$state/discovery"
    printf 'scan off\n' >>"$log"
    ;;
  show)
    printf 'Powered: yes\nDiscovering: %s\n' "$(cat "$state/discovery")"
    ;;
  info)
    printf 'Paired: %s\nTrusted: %s\nConnected: %s\n' \
      "$(cat "$state/paired")" "$(cat "$state/trusted")" "$(cat "$state/connected")"
    ;;
  pair)
    [[ $(cat "$state/discovery") == off ]]
    printf 'yes\n' >"$state/paired"
    printf 'pair %s\n' "$arg" >>"$log"
    printf 'Pairing successful\n'
    ;;
  trust)
    [[ $(cat "$state/paired") == yes ]]
    printf 'yes\n' >"$state/trusted"
    printf 'trust %s\n' "$arg" >>"$log"
    printf 'Changing %s trust succeeded\n' "$arg"
    ;;
  connect)
    [[ $(cat "$state/discovery") == off ]]
    [[ $(cat "$state/trusted") == yes ]]
    printf 'connect %s\n' "$arg" >>"$log"
    count=$(cat "$state/connect-count")
    count=$((count + 1))
    printf '%s\n' "$count" >"$state/connect-count"
    if ((count == 1)); then
      printf 'Failed to connect: org.bluez.Error.Failed\n'
      exit 1
    fi
    printf 'yes\n' >"$state/connected"
    printf 'Connection successful\n'
    ;;
  *)
    printf 'unexpected bluetoothctl command: %s %s\n' "$command" "$arg" >&2
    exit 2
    ;;
esac
FAKE
chmod +x "$tmp/bluetoothctl"

mkdir "$tmp/state"
printf 'yes\n' >"$tmp/state/discovery"
printf 'no\n' >"$tmp/state/paired"
printf 'no\n' >"$tmp/state/trusted"
printf 'no\n' >"$tmp/state/connected"
printf '0\n' >"$tmp/state/connect-count"
: >"$tmp/calls"

address=12:34:56:78:9A:BC
BT_FAKE_STATE="$tmp/state" \
BT_FAKE_LOG="$tmp/calls" \
RYOKU_BLUETOOTHCTL="$tmp/bluetoothctl" \
RYOKU_BLUETOOTH_NO_SLEEP=1 \
  "$repo/ryoku/shell/scripts/ryoku-bluetooth-link" "$address"

cat >"$tmp/want" <<EOF
scan off
pair $address
trust $address
connect $address
connect $address
EOF

if ! cmp -s "$tmp/want" "$tmp/calls"; then
  printf 'unexpected call order:\n' >&2
  diff -u "$tmp/want" "$tmp/calls" >&2 || true
  exit 1
fi

printf 'bluetooth link sequence: ok\n'

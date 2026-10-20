#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/runtime" "$tmp/assets/pam"
cp -r "$root/ryoku/lockscreen/qylock/quickshell-lockscreen/shim" "$tmp/shim"
cp "$root/tests/lock-pam-backoff.qml" "$tmp/shell.qml"
printf '#!/bin/sh\necho yes\n' > "$tmp/bin/loginctl"
printf '#!/bin/sh\nexec sleep 60\n' > "$tmp/bin/dbus-monitor"
printf '#!/bin/sh\nexit 1\n' > "$tmp/bin/fprintd-list"
chmod +x "$tmp/bin/"*
true_bin="$(command -v true)"
false_bin="$(command -v false)"
printf '%s\n' 'auth required pam_deny.so' 'account required pam_deny.so' > "$tmp/assets/pam/ryoku-lock"
cp "$tmp/assets/pam/ryoku-lock" "$tmp/assets/pam/other"

# run <name> <ryoku-lock-pw auth lines...>
run() {
    local name="$1"
    shift
    printf '%s\n' "$@" 'account required pam_deny.so' > "$tmp/assets/pam/ryoku-lock-pw"
    local mode=typed
    [[ $name == untyped ]] && mode=untyped
    PATH="$tmp/bin:$PATH" XDG_SESSION_ID=lock-pam-backoff XDG_RUNTIME_DIR="$tmp/runtime" \
        HOME="$tmp" QT_QPA_PLATFORM=offscreen LOCK_PAM_RUN="$mode" \
        timeout 15s qs -p "$tmp/shell.qml" > "$tmp/output" 2>&1 || {
            cat "$tmp/output"
            exit 1
        }
    if grep -q 'FAIL:' "$tmp/output" || ! grep -q 'PASS:' "$tmp/output"; then
        cat "$tmp/output"
        exit 1
    fi
    # a wrong password is never mistaken for a stack that cannot prompt
    if [[ $mode == typed ]] && grep -q 'ended before any prompt' "$tmp/output"; then
        cat "$tmp/output"
        echo "FAIL: $name: a typed key was handled as an untyped failure"
        exit 1
    fi
    echo "$name: $(grep -o 'PASS:.*' "$tmp/output")"
}

# the stack denies on its own, before any prompt
run untyped 'auth required pam_deny.so'
# prompts, then the module errors (Quickshell: error() then completed(Error))
run typed-error "auth required pam_exec.so expose_authtok $false_bin"
# prompts, then the stack refuses (Quickshell: completed(Failed))
run typed-failed "auth requisite pam_exec.so expose_authtok $true_bin" 'auth required pam_deny.so'

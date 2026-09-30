package main

// init.go abstracts pid 1. Arch boots systemd, Void boots runit; every step
// that used to hardcode systemctl goes through these helpers, and nothing
// else branches on the init system.
//
// Runit model: system services are links in /var/service pointing at
// /etc/sv/<name> (enable = link, disable = unlink). Ryoku user-session
// services (ryoku-shell, ryoku-idle, ...) are links in ~/runit supervised by
// the user's runsvdir; see docs/void.md.

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"ryoku-i18n"
)

// initSystem reports "systemd", "runit", or "" when neither is detected.
func initSystem() string {
	if fi, err := os.Stat("/run/systemd/system"); err == nil && fi.IsDir() {
		return "systemd"
	}
	if _, err := os.Stat("/run/runit/runsvdir.current"); err == nil {
		return "runit"
	}
	if fi, err := os.Stat("/var/service"); err == nil && fi.IsDir() {
		return "runit"
	}
	return ""
}

func runitBooted() bool { return initSystem() == "runit" }

// runitName maps a systemd unit to its runit service name.
func runitName(unit string) string {
	s := strings.TrimSuffix(unit, ".service")
	switch s {
	case "bluetooth":
		return "bluetoothd"
	case "connman":
		return "connmand"
	}
	return s
}

// sysEnabled reports whether a system service is enabled.
func sysEnabled(unit string) bool {
	if initSystem() == "runit" {
		_, err := os.Lstat("/var/service/" + runitName(unit))
		return err == nil
	}
	return out("systemctl", "is-enabled", unit) == "enabled"
}

// svcDisable disables a system service. svcEnable enables it.
func (e *engine) svcDisable(unit string) error {
	if initSystem() == "runit" {
		return e.sudo("rm", "-f", "/var/service/"+runitName(unit))
	}
	return e.sudo("systemctl", "disable", unit)
}

func (e *engine) svcEnable(unit string) error {
	if initSystem() == "runit" {
		n := runitName(unit)
		return e.sudo("ln", "-sf", "/etc/sv/"+n, "/var/service/"+n)
	}
	return e.sudo("systemctl", "enable", unit)
}

// svcDisableLine / svcEnableLine are the restore.sh spellings of the above.
func svcDisableLine(unit string) string {
	if initSystem() == "runit" {
		return "sudo rm -f /var/service/" + runitName(unit)
	}
	return "sudo systemctl disable " + unit
}

func svcEnableLine(unit string) string {
	if initSystem() == "runit" {
		n := runitName(unit)
		return "sudo ln -sf /etc/sv/" + n + " /var/service/" + n
	}
	return "sudo systemctl enable " + unit
}

// softOffUser disables one conflicting user daemon and records its undo.
// Under runit the supervision link moves out of the way; re-linking restores it.
func (e *engine) softOffUser(unit string) {
	if initSystem() == "runit" {
		link := filepath.Join(e.f.homeDir, "runit", runitName(unit))
		tgt, err := os.Readlink(link)
		if err != nil {
			return // not supervised, nothing to do
		}
		if e.dry {
			e.say("DRYRUN: rm " + link)
			return
		}
		if err := os.Remove(link); err != nil {
			e.say(i18n.Tf("warning: could not disable %s", unit))
			return
		}
		e.recordRestore(fmt.Sprintf("ln -s %q %q", tgt, link))
		return
	}
	if err := e.cmd("", nil, "systemctl", "--user", "disable", unit); err != nil {
		e.say(i18n.Tf("warning: could not disable %s", unit))
		return
	}
	// || true: add-wants units have no [Install] and refuse a bare enable
	e.recordRestore("systemctl --user enable " + unit + " || true")
}

// userDaemonReload refreshes user services after laying configs. runsvdir
// notices new links on its own, so this is a no-op there.
func (e *engine) userDaemonReload() error {
	if initSystem() == "runit" {
		return nil
	}
	return e.cmd("", nil, "systemctl", "--user", "daemon-reload")
}

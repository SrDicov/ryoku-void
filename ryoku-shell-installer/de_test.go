package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestParseGnomeSources(t *testing.T) {
	l, v := parseGnomeSources(`[('xkb', 'us+dvorak'), ('xkb', 'fr'), ('ibus', 'anthy')]`)
	if l != "us" || v != "dvorak" {
		t.Fatalf("got %q %q", l, v)
	}
	l, v = parseGnomeSources(`[('ibus', 'anthy'), ('xkb', 'de')]`)
	if l != "de" || v != "" {
		t.Fatalf("ibus entries must be skipped: %q %q", l, v)
	}
	if l, _ = parseGnomeSources(`@a(ss) []`); l != "" {
		t.Fatalf("empty sources must salvage nothing, got %q", l)
	}
}

func TestParseGnomeOptions(t *testing.T) {
	if got := parseGnomeOptions(`['caps:ctrl_modifier', 'compose:ralt']`); got != "caps:ctrl_modifier,compose:ralt" {
		t.Fatalf("got %q", got)
	}
	if got := parseGnomeOptions(`@as []`); got != "" {
		t.Fatalf("empty options array must be empty, got %q", got)
	}
}

const monitorsXMLSample = `<monitors version="2">
  <configuration>
    <logicalmonitor>
      <x>1920</x><y>0</y>
      <scale>2</scale>
      <primary>yes</primary>
      <transform><rotation>left</rotation><flipped>no</flipped></transform>
      <monitor>
        <monitorspec><connector>HDMI-2</connector><vendor>SAM</vendor></monitorspec>
        <mode><width>1920</width><height>1080</height><rate>30.000</rate></mode>
      </monitor>
    </logicalmonitor>
    <logicalmonitor>
      <x>0</x><y>0</y>
      <scale>1</scale>
      <monitor>
        <monitorspec><connector>eDP-1</connector></monitorspec>
        <mode><width>2560</width><height>1600</height><rate>60.001</rate></mode>
      </monitor>
    </logicalmonitor>
    <disabled><monitorspec><connector>DP-3</connector></monitorspec></disabled>
  </configuration>
</monitors>`

func TestParseMonitorsXML(t *testing.T) {
	outs := parseMonitorsXML([]byte(monitorsXMLSample))
	if len(outs) != 3 {
		t.Fatalf("want 2 monitors + 1 disabled, got %+v", outs)
	}
	hdmi := outs[0]
	if hdmi.name != "HDMI-2" || hdmi.mode != "1920x1080@30.000" || hdmi.position != "1920x0" ||
		hdmi.scale != "2" || hdmi.transform != 1 {
		t.Fatalf("HDMI-2 parsed wrong: %+v", hdmi)
	}
	if outs[1].name != "eDP-1" || outs[1].scale != "" || outs[1].mode != "2560x1600@60.001" {
		t.Fatalf("eDP-1 parsed wrong: %+v", outs[1])
	}
	if !outs[2].off || outs[2].name != "DP-3" {
		t.Fatalf("disabled connector missed: %+v", outs[2])
	}
	// two configuration blocks: matching the right one is guesswork, skip.
	two := strings.Replace(monitorsXMLSample, "</monitors>",
		"<configuration></configuration></monitors>", 1)
	if got := parseMonitorsXML([]byte(two)); got != nil {
		t.Fatalf("multi-config files must not be salvaged: %+v", got)
	}
}

func gnomeMonitorLayout(enabled, disabled string) []byte {
	logical := ""
	if enabled != "" {
		logical = `<logicalmonitor><x>0</x><y>0</y><scale>1</scale><monitor>` +
			`<monitorspec><connector>` + enabled + `</connector></monitorspec>` +
			`<mode><width>1920</width><height>1080</height><rate>60</rate></mode>` +
			`</monitor></logicalmonitor>`
	}
	off := ""
	if disabled != "" {
		off = `<disabled><monitorspec><connector>` + disabled + `</connector></monitorspec></disabled>`
	}
	return []byte(`<monitors version="2"><configuration>` + logical + off + `</configuration></monitors>`)
}

func TestMonitorsXMLDisabledPanelSafety(t *testing.T) {
	tests := []struct {
		name     string
		enabled  string
		disabled string
		statuses map[string]string
		wantOff  bool
	}{
		{
			name: "connected external keeps internal off", enabled: "HDMI-A-1", disabled: "eDP-1",
			statuses: map[string]string{"HDMI-A-1": "connected"}, wantOff: true,
		},
		{
			name: "disconnected external restores internal", enabled: "HDMI-A-1", disabled: "eDP-1",
			statuses: map[string]string{"HDMI-A-1": "disconnected"},
		},
		{name: "internal is the only output", disabled: "eDP-1"},
		{
			name: "desktop output disable is unchanged", enabled: "DP-1", disabled: "DP-2",
			statuses: map[string]string{"DP-1": "disconnected"}, wantOff: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			setDRMStatuses(t, tt.statuses)
			outs := parseMonitorsXML(gnomeMonitorLayout(tt.enabled, tt.disabled))
			lua, _ := renderPins(outs, false, "GNOME")
			kdl, _ := renderKdlPins(outs, false, "GNOME")
			luaOff := strings.Contains(lua, `output = "`+tt.disabled+`", disabled = true`)
			kdlOff := strings.Contains(kdl, `output "`+tt.disabled+"\" {\n    off\n}")
			if luaOff != tt.wantOff || kdlOff != tt.wantOff {
				t.Fatalf("disabled state = lua:%v kdl:%v, want %v\nLua:\n%s\nKDL:\n%s",
					luaOff, kdlOff, tt.wantOff, lua, kdl)
			}
			if !strings.Contains(lua, `output = "`+tt.disabled+`"`) ||
				!strings.Contains(kdl, `output "`+tt.disabled+`" {`) {
				t.Fatalf("disabled output vanished instead of being safely imported\nLua:\n%s\nKDL:\n%s", lua, kdl)
			}
		})
	}
}

func TestParseKxkbrc(t *testing.T) {
	sample := "[Layout]\nLayoutList=us,de\nVariantList=,neo\nOptions=grp:alt_shift_toggle,caps:escape\nResetOldOptions=true\nUse=true\n"
	l, v, o, ok := parseKxkbrc(sample)
	if !ok || l != "us,de" || v != ",neo" || o != "grp:alt_shift_toggle,caps:escape" {
		t.Fatalf("got %q %q %q ok=%v", l, v, o, ok)
	}
	if _, _, _, ok := parseKxkbrc(strings.Replace(sample, "Use=true", "Use=false", 1)); ok {
		t.Fatal("Use=false means KDE follows the system layout, nothing to salvage")
	}
	if _, _, _, ok := parseKxkbrc("[Layout]\nLayoutList=us\n"); ok {
		t.Fatal("absent Use= must not salvage")
	}
	// all-empty variant slots collapse to no variant.
	l, v, _, ok = parseKxkbrc("[Layout]\nUse=true\nLayoutList=us,ru\nVariantList=,\n")
	if !ok || l != "us,ru" || v != "" {
		t.Fatalf("empty variants kept: %q %q", l, v)
	}
}

const kwinSample = `[
  {"name": "outputs", "data": [
    {"connectorName": "DP-2",
     "mode": {"width": 2560, "height": 1440, "refreshRate": 165004},
     "scale": 1.25, "transform": "Rotated90", "vrrPolicy": "Always"},
    {"connectorName": "HDMI-A-1",
     "mode": {"width": 1920, "height": 1080, "refreshRate": 60000},
     "scale": 1, "transform": "Normal", "vrrPolicy": "Never"},
    {"connectorName": "eDP-1", "enabled": false}
  ]}
]`

func TestParseKwinOutputs(t *testing.T) {
	outs := parseKwinOutputs([]byte(kwinSample))
	if len(outs) != 3 {
		t.Fatalf("want both active outputs and one disabled output, got %+v", outs)
	}
	dp := outs[0]
	if dp.name != "DP-2" || dp.mode != "2560x1440@165.004" || dp.scale != "1.25" ||
		dp.transform != 1 || dp.vrr != 1 {
		t.Fatalf("DP-2 parsed wrong: %+v", dp)
	}
	if outs[1].scale != "" || outs[1].transform != 0 || outs[1].vrr != 0 || outs[1].mode != "1920x1080@60" {
		t.Fatalf("HDMI-A-1 parsed wrong: %+v", outs[1])
	}
	if !outs[2].off || outs[2].name != "eDP-1" {
		t.Fatalf("disabled KDE output missed: %+v", outs[2])
	}
	if parseKwinOutputs([]byte("not json")) != nil {
		t.Fatal("bad json must salvage nothing")
	}
}

func TestThemeCurrent(t *testing.T) {
	text := "[General]\nCurrent=wrong\n[Theme]\n#Current=commented\nCurrent = breeze # trailing comment\nCurrent=ryoku\n"
	got, ok := themeCurrent(text)
	if !ok || got != "ryoku" {
		t.Fatalf("theme Current = %q, %v, want ryoku, true", got, ok)
	}
	if got, ok := themeCurrent("[Autologin]\nSession=plasma\n"); ok || got != "" {
		t.Fatalf("non-theme config returned %q, %v", got, ok)
	}
}

func writeSDDMTestFile(t *testing.T, root, path, content string) {
	t.Helper()
	full := sddmPath(root, path)
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestInactiveSDDMMainThemeStaysUntouched(t *testing.T) {
	stockArch := "[Theme]\n#Current=breeze\n"
	if got, changed := updateRyokuSDDMMainTheme(stockArch, true); changed || got != stockArch {
		t.Fatalf("stock Arch main config must stay byte-for-byte unchanged: changed=%v\n%s", changed, got)
	}
}

func TestFedoraSDDMThemePrecedenceAndOwnership(t *testing.T) {
	root := t.TempDir()
	writeSDDMTestFile(t, root, "/usr/lib/sddm/sddm.conf.d/kde_settings.conf", "[Theme]\nCurrent=01-breeze-fedora\n")
	writeSDDMTestFile(t, root, "/usr/lib/sddm/sddm.conf.d/plasma-wayland.conf", "[General]\nDisplayServer=wayland\n")
	writeSDDMTestFile(t, root, "/etc/sddm.conf", "[Theme]\n#Current=01-breeze-fedora\n")

	state := effectiveSDDMThemeAt(root, "01-breeze-fedora")
	if state.current != "01-breeze-fedora" || !strings.HasSuffix(state.source, "kde_settings.conf") {
		t.Fatalf("stock Fedora theme = %+v", state)
	}
	if !kdeOwnsSDDMTheme(root, "fedora", []string{"KDE Plasma"}) {
		t.Fatal("Fedora KDE vendor drop-in must preserve Breeze by default")
	}
	if kdeOwnsSDDMTheme(root, "arch", []string{"KDE Plasma"}) {
		t.Fatal("vendor drop-in must not change Arch's existing greeter default")
	}

	writeSDDMTestFile(t, root, "/etc/sddm.conf.d/99-ryoku.conf", "[Theme]\nCurrent=ryoku\n")
	state = effectiveSDDMThemeAt(root, "01-breeze-fedora")
	if state.current != "ryoku" || !strings.HasSuffix(state.source, "99-ryoku.conf") {
		t.Fatalf("administrator drop-in did not beat Fedora vendor config: %+v", state)
	}

	main := "[Theme]\nCurrent=custom-kde\n"
	writeSDDMTestFile(t, root, "/etc/sddm.conf", main)
	state = effectiveSDDMThemeAt(root, "01-breeze-fedora")
	if state.current != "custom-kde" || !strings.HasSuffix(state.source, "/etc/sddm.conf") {
		t.Fatalf("main config did not beat both drop-in directories: %+v", state)
	}

	selected, changed := updateRyokuSDDMMainTheme(main, true)
	if !changed {
		t.Fatal("active main-file theme must receive the managed override")
	}
	writeSDDMTestFile(t, root, "/etc/sddm.conf", selected)
	if state = effectiveSDDMThemeAt(root, "01-breeze-fedora"); state.current != "ryoku" {
		t.Fatalf("managed main-file selection did not win: %+v", state)
	}
	restored, changed := updateRyokuSDDMMainTheme(selected, false)
	if !changed || restored != main {
		t.Fatalf("disabling managed selection changed original config: changed=%v\n%s", changed, restored)
	}
}

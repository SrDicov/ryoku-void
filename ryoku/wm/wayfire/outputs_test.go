package main

import (
	"bufio"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	wm "ryoku-wm"
)

// monitorsIni is the write half of the display seam, and wayfire applies a bad
// output section silently rather than loudly, so the rendered file is pinned by
// shape: an enabled output carries mode/position and only the transform, scale
// and VRR lines it needs, a disabled one is `mode = off` alone, and a mirror is
// `mode = mirror <name>` with no layout of its own.
func TestMonitorsIni(t *testing.T) {
	got := string(monitorsIni([]wm.OutputLayout{
		{Name: "eDP-1", Enabled: true, Mode: "2560x1600@165.002", Scale: 1.5, X: 0, Y: 0, Transform: 1, VRR: true, ColorMode: "hdr"},
		{Name: "DP-2", Enabled: false},
		{Name: "HDMI-A-1", Enabled: true, Mirror: "eDP-1"},
	}))

	for _, want := range []string{
		"[output:eDP-1]",
		"mode = 2560x1600@165002",
		"position = 0,0",
		"scale = 1.5",
		"transform = 90",
		"vrr = true",
		"hdr = true",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("monitors.ini missing %q\n%s", want, got)
		}
	}

	dp2 := got[strings.Index(got, "[output:DP-2]"):]
	dp2 = dp2[:strings.Index(dp2, "[output:HDMI-A-1]")]
	if !strings.Contains(dp2, "mode = off") {
		t.Errorf("a disabled output must be mode = off:\n%s", dp2)
	}
	if strings.Contains(dp2, "position") || strings.Contains(dp2, "scale") {
		t.Errorf("a disabled output must carry no position or scale:\n%s", dp2)
	}

	hdmi := got[strings.Index(got, "[output:HDMI-A-1]"):]
	if !strings.Contains(hdmi, "mode = mirror eDP-1") {
		t.Errorf("a mirrored output must clone by mode:\n%s", hdmi)
	}
	if strings.Contains(hdmi, "position") {
		t.Errorf("a mirrored output has no layout of its own:\n%s", hdmi)
	}
}

// An untransformed, non-VRR output emits neither line, while explicit SDR keeps
// an earlier HDR session from leaking through. An auto mode stays unset so
// wayfire picks the panel's preferred one.
func TestMonitorsIniOmitsDefaults(t *testing.T) {
	got := string(monitorsIni([]wm.OutputLayout{
		{Name: "eDP-1", Enabled: true, Scale: 1, X: 0, Y: 0},
	}))
	body := got[strings.Index(got, "[output:eDP-1]"):]
	if strings.Contains(body, "transform") {
		t.Errorf("transform 0 must be omitted:\n%s", body)
	}
	if strings.Contains(body, "vrr") {
		t.Errorf("VRR off must be omitted:\n%s", body)
	}
	if !strings.Contains(body, "hdr = false") {
		t.Errorf("an ordinary SDR output must explicitly disable HDR:\n%s", body)
	}
	if strings.Contains(body, "mode = ") {
		t.Errorf("an auto mode must be omitted:\n%s", body)
	}
}

// The neutral store carries rates as human Hz; wayfire parses mHz. The rate
// that arrives already in mHz (a profile saved from wayfire's own state) passes
// through, so a save/apply roundtrip is idempotent.
func TestWayfireMode(t *testing.T) {
	for in, want := range map[string]string{
		"1920x1080@60":       "1920x1080@60000",
		"2560x1600@165.002":  "2560x1600@165002",
		"2560x1600@165002":   "2560x1600@165002",
		"1920x1080@59.94":    "1920x1080@59940",
		"1920x1080":          "1920x1080",
		"1920x1080@notarate": "1920x1080@notarate",
	} {
		if got := wayfireMode(in); got != want {
			t.Errorf("wayfireMode(%q) = %q, want %q", in, got, want)
		}
	}
}

// Wayfire spells the flipped rotations "90_flipped", not the protocol's
// "flipped-90", and the state read has to see what this writer wrote, so both
// directions are pinned for every transform value.
func TestTransformRoundtrip(t *testing.T) {
	for i := 0; i <= 7; i++ {
		tok := wayfireTransform(i)
		if i == 0 && tok != "" {
			t.Errorf("transform 0 must render as no line, got %q", tok)
		}
		if tok != "" {
			if got := transformFromWayfire(tok); got != i {
				t.Errorf("transformFromWayfire(%q) = %d, want %d", tok, got, i)
			}
		}
	}
	if got := transformFromWayfire("normal"); got != 0 {
		t.Errorf(`transformFromWayfire("normal") = %d, want 0`, got)
	}
	if got := transformFromWayfire("nonsense"); got != 0 {
		t.Errorf(`transformFromWayfire("nonsense") = %d, want 0`, got)
	}
	if wayfireTransform(5) != "90_flipped" {
		t.Errorf("wayfire spells the flipped rotations its own way, got %q", wayfireTransform(5))
	}
}

// Wayfire 0.11 supports a per-output HDR toggle, but not a separate wide-gamut
// mode or SDR brightness. Unsupported leaves remain visible in the apply report.
func TestOutputsUnhonoredReportsColour(t *testing.T) {
	unh := outputsUnhonored([]wm.OutputLayout{
		{Name: "eDP-1", Enabled: true, ColorMode: "hdr", SdrBrightness: 1.5},
		{Name: "DP-1", Enabled: true, ColorMode: "wide", SdrBrightness: 1},
		{Name: "HDMI-A-1", Enabled: false, ColorMode: "wide"},
	})
	got := map[string]bool{}
	for _, u := range unh {
		got[u.Key] = true
	}
	if got["displays.eDP-1.colorMode"] || !got["displays.eDP-1.sdrBrightness"] {
		t.Errorf("HDR must be honored while SDR brightness is reported, got %v", unh)
	}
	if !got["displays.DP-1.colorMode"] || len(unh) != 2 {
		t.Errorf("only wide gamut and SDR brightness should be losses, got %v", unh)
	}
}

// A save must reach a running Wayfire even when its file watch is gone (a
// deploy or reset replaced the config directory), so every write ends in one
// reload, a layout save recomposes the one file Wayfire reads, and nothing is
// reloaded for a preview or off a session.
func TestSavesReachARunningWayfire(t *testing.T) {
	wayfireHome(t)
	withDefaults(t, "[core]\nplugins = animate\n")
	store := writeStore(t, `{}`)
	oldOut := stdout
	stdout = bufio.NewWriter(io.Discard)
	t.Cleanup(func() { stdout = oldOut })
	calls := stubAct(t, nil)
	reloads := func() int {
		n := 0
		for _, c := range *calls {
			if c.method == reloadConfigMethod {
				n++
			}
		}
		return n
	}

	if err := runApply([]string{store}); err != nil {
		t.Fatal(err)
	}
	if got := reloads(); got != 1 {
		t.Errorf("apply reloaded %d times, want once after the write", got)
	}

	*calls = nil
	layout := filepath.Join(t.TempDir(), "layout.json")
	if err := os.WriteFile(layout, []byte(`[{"name":"eDP-1","enabled":true,"mode":"1920x1080@60","scale":1}]`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := runOutputs([]string{layout}); err != nil {
		t.Fatal(err)
	}
	composed, err := os.ReadFile(filepath.Join(wayfireConfigDir(), "wayfire.ini"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(composed), "[output:eDP-1]") {
		t.Errorf("a layout save must land in the composed wayfire.ini:\n%s", composed)
	}
	if got := reloads(); got != 1 {
		t.Errorf("a layout save reloaded %d times, want once", got)
	}

	*calls = nil
	if err := runApply([]string{"--preview", store}); err != nil {
		t.Fatal(err)
	}
	aliveCheck = func(string) bool { return false }
	if err := runApply([]string{store}); err != nil {
		t.Fatalf("apply off a session must still write: %v", err)
	}
	if got := reloads(); got != 0 {
		t.Errorf("a preview or an apply off a session reloaded %d times, want none", got)
	}
}

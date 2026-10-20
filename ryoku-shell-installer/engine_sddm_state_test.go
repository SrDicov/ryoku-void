package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func fakeSudo(t *testing.T) {
	t.Helper()
	bin := t.TempDir()
	script := `#!/usr/bin/env bash
set -e
[[ ${1:-} == -n ]] && shift
if [[ ${1:-} == install ]]; then
  shift
  args=()
  while (($#)); do
    case $1 in
      -o|-g) shift 2 ;;
      *) args+=("$1"); shift ;;
    esac
  done
  exec install "${args[@]}"
fi
exec "$@"
`
	if err := os.WriteFile(filepath.Join(bin, "sudo"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
}

func sddmStateTestEngine(t *testing.T, switchDM bool) (*engine, string) {
	t.Helper()
	backup := t.TempDir()
	restore := filepath.Join(backup, "restore.sh")
	header := "#!/usr/bin/env bash\nset -euo pipefail\nDIR=\"$(cd \"$(dirname \"$0\")\" && pwd)\"\n"
	if err := os.WriteFile(restore, []byte(header), 0o755); err != nil {
		t.Fatal(err)
	}
	return &engine{
		f:           &facts{},
		p:           &plan{switchDM: switchDM, compositor: "hyprland"},
		backupDir:   backup,
		restorePath: restore,
	}, restore
}

func TestConfigureSDDMLastSessionCreatesAndRestoresAbsentState(t *testing.T) {
	fakeSudo(t)
	root := t.TempDir()
	state := filepath.Join(root, "var/lib/sddm/state.conf")
	e, restore := sddmStateTestEngine(t, true)
	session := compositorWaylandSessionPath(e.p.compositor)
	if err := e.configureSDDMLastSessionAt(state, session); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(state)
	if err != nil {
		t.Fatal(err)
	}
	if got, want := string(data), "[Last]\nSession="+session+"\n"; got != want {
		t.Fatalf("state.conf = %q, want %q", got, want)
	}
	info, err := os.Stat(state)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("state.conf mode = %o, want 600", info.Mode().Perm())
	}
	if _, err := os.Stat(filepath.Join(e.backupDir, "sddm-state.absent")); err != nil {
		t.Fatalf("absence marker: %v", err)
	}
	if err := exec.Command("bash", restore).Run(); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(state); !os.IsNotExist(err) {
		t.Fatalf("restore left newly-created state.conf: %v", err)
	}
}

func TestConfigureSDDMLastSessionPreservesAndRestoresExistingState(t *testing.T) {
	fakeSudo(t)
	root := t.TempDir()
	state := filepath.Join(root, "var/lib/sddm/state.conf")
	if err := os.MkdirAll(filepath.Dir(state), 0o750); err != nil {
		t.Fatal(err)
	}
	original := "[Last]\nSession=/usr/share/wayland-sessions/plasma.desktop\nUser=alice\n\n[General]\nNumlock=on\n"
	if err := os.WriteFile(state, []byte(original), 0o600); err != nil {
		t.Fatal(err)
	}
	e, restore := sddmStateTestEngine(t, true)
	session := compositorWaylandSessionPath(e.p.compositor)
	if err := e.configureSDDMLastSessionAt(state, session); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(state)
	if err != nil {
		t.Fatal(err)
	}
	text := string(data)
	for _, want := range []string{"Session=" + session, "User=alice", "[General]", "Numlock=on"} {
		if !strings.Contains(text, want) {
			t.Fatalf("updated state.conf dropped %q:\n%s", want, text)
		}
	}
	if strings.Contains(text, "plasma.desktop") {
		t.Fatalf("updated state.conf kept Plasma as the remembered session:\n%s", text)
	}
	backup, err := os.ReadFile(filepath.Join(e.backupDir, "sddm-state.conf"))
	if err != nil {
		t.Fatal(err)
	}
	if string(backup) != original {
		t.Fatalf("backup changed original state.conf: %q", backup)
	}
	if err := exec.Command("bash", restore).Run(); err != nil {
		t.Fatal(err)
	}
	restored, err := os.ReadFile(state)
	if err != nil {
		t.Fatal(err)
	}
	if string(restored) != original {
		t.Fatalf("restore state.conf = %q, want %q", restored, original)
	}
}

func TestConfigureSDDMLastSessionRequiresDisplayManagerSwitch(t *testing.T) {
	fakeSudo(t)
	state := filepath.Join(t.TempDir(), "var/lib/sddm/state.conf")
	e, _ := sddmStateTestEngine(t, false)
	if err := e.configureSDDMLastSessionAt(state, compositorWaylandSessionPath("hyprland")); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(state); !os.IsNotExist(err) {
		t.Fatalf("state.conf changed without the SDDM switch: %v", err)
	}
}

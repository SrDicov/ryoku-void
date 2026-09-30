package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDetectDistro(t *testing.T) {
	for _, c := range []struct {
		id, like, want string
	}{
		{"arch", "", "arch"},
		{"cachyos", "arch", "arch"},
		{"endeavouros", "arch", "arch"},
		{"debian", "", "debian"},
		{"ubuntu", "debian", "debian"},
		{"linuxmint", "ubuntu debian", "debian"},
		{"fedora", "", ""},
		{"void", "", "void"},
	} {
		d := detectDistro(c.id, c.like)
		got := ""
		if d != nil {
			got = d.id
		}
		if got != c.want {
			t.Errorf("detectDistro(%q,%q) = %q, want %q", c.id, c.like, got, c.want)
		}
	}
}

func TestLocalAllRenamesAndDrops(t *testing.T) {
	in := []string{"git", "networkmanager", "fd", "matugen", "limine", "kitty"}
	got := debianLinux.localAll(in)
	want := []string{"git", "network-manager", "fd-find", "kitty"}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("localAll = %v, want %v", got, want)
	}
	if archLinux.local("networkmanager") != "networkmanager" {
		t.Error("arch must pass base.packages names through unchanged")
	}
	// Spot-checks against the Void repodata index; the full map is docs/void.md.
	for _, c := range []struct{ arch, void string }{
		{"networkmanager", "NetworkManager"},
		{"fish", "fish-shell"},
		{"bluez-utils", "bluez"},
		{"vulkan-icd-loader", "vulkan-loader"},
		{"xorg-xwayland", "xorg-server-xwayland"},
		{"qt6-5compat", "qt6-qt5compat"},
		{"qemu-desktop", "qemu"},
		{"tesseract-data-eng", "tesseract-ocr-eng"},
		{"xpadneo-dkms", "xpadneo"},
		{"imagemagick", "ImageMagick"},
		{"mangohud", "MangoHud"},
		{"hypridle", ""},
		{"blesh", ""},
		{"vimix-cursors", "bibata-cursor-theme"},
		{"ttf-material-symbols-variable", "not-st"},
		{"npm", ""},
	} {
		if got := voidLinux.local(c.arch); got != c.void {
			t.Errorf("void local(%q) = %q, want %q", c.arch, got, c.void)
		}
	}
}

// The Arch step list is the contract that must not drift; the Debian one swaps
// the pacman-only steps for the source build.
func TestStepsPerDistro(t *testing.T) {
	ids := func(f *facts) []string {
		e := newEngine(f, &plan{}, true, "", "")
		var out []string
		for _, s := range e.steps {
			out = append(out, s.id)
		}
		return out
	}

	arch := strings.Join(ids(&facts{distro: archLinux}), " ")
	wantArch := "legacy sysupgrade tools payload backup repo conflicts packages drivers session configs aur shell doctor verify"
	if arch != wantArch {
		t.Errorf("arch steps = %q, want %q", arch, wantArch)
	}

	deb := strings.Join(ids(&facts{distro: debianLinux}), " ")
	wantDeb := "sysupgrade tools payload backup conflicts packages build session configs shell doctor verify"
	if deb != wantDeb {
		t.Errorf("debian steps = %q, want %q", deb, wantDeb)
	}

	// Void builds from source exactly like Debian: no [ryoku] repo, no AUR,
	// no pacman-only driver step. It keeps the z-repo trust step, which Debian
	// has no equivalent for.
	voi := strings.Join(ids(&facts{distro: voidLinux}), " ")
	wantVoid := "sysupgrade zrepo tools payload backup conflicts packages build session configs shell doctor verify"
	if voi != wantVoid {
		t.Errorf("void steps = %q, want %q", voi, wantVoid)
	}
}

// A box can only run the window managers it has installed: Void packages niri
// but not hyprland, so the default pick has to follow what is on PATH or the
// install lands on a compositor with no binary.
func TestAvailableCompositorsFollowsPATH(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("PATH", dir)
	if got := availableCompositors(); len(got) != len(compositors()) {
		t.Errorf("with no compositor installed, got %v, want all of %v", got, compositors())
	}
	if err := os.WriteFile(filepath.Join(dir, "niri"), []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	got := availableCompositors()
	if len(got) != 1 || got[0] != "niri" {
		t.Errorf("with only niri installed, got %v, want [niri]", got)
	}
}

func TestInstallArgs(t *testing.T) {
	got := strings.Join(archLinux.installArgs([]string{"git"}), " ")
	if got != "pacman -Syu --needed --noconfirm git" {
		t.Errorf("arch installArgs = %q", got)
	}
	got = strings.Join(debianLinux.installArgs([]string{"git"}), " ")
	if got != "apt-get -y install git" {
		t.Errorf("debian installArgs = %q", got)
	}
	got = strings.Join(debianLinux.removeArgs([]string{"dunst"}), " ")
	if got != "apt-get -y remove dunst" {
		t.Errorf("debian removeArgs = %q", got)
	}
}

// desktopPacmanArgs must --overwrite the ryoku-desktop-owned paths a prior partial
// install, a dev deploy, or the ISO installer can leave unowned (the bin helpers,
// their polkit rules, and the Plymouth splash theme) so a resume or conversion
// never aborts on "exists in filesystem". Dropping any path silently reintroduces
// that outage, so pin coverage here. fromSource distros build from the payload and
// must never carry --overwrite.
func TestDesktopPacmanArgsAdoptsRyokuPaths(t *testing.T) {
	args := desktopPacmanArgs(archLinux, []string{"ryoku-desktop"})
	joined := strings.Join(args, " ")
	if !strings.Contains(joined, "--overwrite") {
		t.Fatalf("arch desktop install missing --overwrite: %v", args)
	}
	var glob string
	for i, a := range args {
		if a == "--overwrite" && i+1 < len(args) {
			glob = args[i+1]
		}
	}
	for _, p := range []string{
		"/usr/bin/ryoku-dns",
		"/usr/share/polkit-1/rules.d/50-ryoku-dns.rules",
		"/usr/share/plymouth/themes/ryoku/bullet.png",
	} {
		covered := false
		for _, g := range strings.Split(glob, ",") {
			if ok, _ := filepath.Match(g, p); ok {
				covered = true
				break
			}
		}
		if !covered {
			t.Errorf("--overwrite %q does not cover seeded path %q", glob, p)
		}
	}
	if strings.Contains(strings.Join(desktopPacmanArgs(debianLinux, []string{"foo"}), " "), "--overwrite") {
		t.Error("fromSource distro must not carry --overwrite")
	}
}

package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// distro is the only place the installer knows a package manager. Every step
// asks it for argv and for the local name of a package; nothing else branches on
// the distribution.
//
// fromSource distros have no [ryoku] repository, so the desktop is built from the
// cloned payload with ryoku/shell/deploy.sh instead of installed with pacman.
type distro struct {
	id         string
	name       string
	fromSource bool

	// rename maps a base.packages (Arch) name to the local one. A missing key
	// means the name is identical; an empty value means the package does not
	// exist here and is skipped.
	rename map[string]string

	// z-repo (Void only): the third-party signed repository and the best-effort
	// extras it serves after the base set. Empty on every other distro.
	zrepoURL     string
	zrepoKeyURL  string
	zrepoKeyName string
	zrepoExtras  []string

	// build are the extra packages a fromSource install needs to compile the
	// Go programs, the Ryoku.Blobs QML plugin, and the Hyprland plugins.
	build []string

	installCmd []string
	removeCmd  []string
	updateCmd  []string
	refreshCmd []string
	queryCmd   []string
}

var archLinux = &distro{
	id:         "arch",
	name:       "Arch",
	installCmd: []string{"pacman", "-Syu", "--needed", "--noconfirm"},
	removeCmd:  []string{"pacman", "-R", "--noconfirm"},
	updateCmd:  []string{"pacman", "-Syu", "--noconfirm"},
	refreshCmd: []string{"pacman", "-Sy"},
	queryCmd:   []string{"pacman", "-Qq"},
}

// Package names verified against api.ftp-master.debian.org (testing/unstable).
var debianLinux = &distro{
	id:         "debian",
	name:       "Debian",
	fromSource: true,
	installCmd: []string{"apt-get", "-y", "install"},
	removeCmd:  []string{"apt-get", "-y", "remove"},
	updateCmd:  []string{"apt-get", "-y", "dist-upgrade"},
	refreshCmd: []string{"apt-get", "update"},
	queryCmd:   []string{"dpkg-query", "-W", "-f=${Status}"},
	build: []string{
		"build-essential", "cmake", "ninja-build", "pkgconf", "golang",
		"qt6-base-dev", "qt6-declarative-dev", "qt6-multimedia-dev",
		"qt6-shadertools-dev", "qt6-svg-dev", "qt6-5compat-dev", "qt6-wayland-dev",
		"hyprland-dev", "libhyprutils-dev",
	},
	rename: map[string]string{
		"base":                    "",
		"base-devel":              "build-essential",
		"bluez-utils":             "bluez",
		"edk2-ovmf":               "ovmf",
		"fd":                      "fd-find",
		"github-cli":              "gh",
		"gst-libav":               "gstreamer1.0-libav",
		"gst-plugins-bad":         "gstreamer1.0-plugins-bad",
		"gst-plugins-base":        "gstreamer1.0-plugins-base",
		"gst-plugins-good":        "gstreamer1.0-plugins-good",
		"gst-plugins-ugly":        "gstreamer1.0-plugins-ugly",
		"inter-font":              "fonts-inter",
		"linux-firmware":          "firmware-linux-free",
		"linux-headers":           "linux-headers-amd64",
		"networkmanager":          "network-manager",
		"noto-fonts":              "fonts-noto-core",
		"noto-fonts-cjk":          "fonts-noto-cjk",
		"noto-fonts-emoji":        "fonts-noto-color-emoji",
		"polkit":                  "polkitd",
		"python":                  "python3",
		"qemu-desktop":            "qemu-system-x86",
		"qt6-multimedia-ffmpeg":   "qt6-multimedia-dev",
		"rust":                    "rustc",
		"tesseract-data-eng":      "tesseract-ocr-eng",
		"ttf-firacode-nerd":       "fonts-firacode",
		"ttf-hack-nerd":           "fonts-hack",
		"ttf-jetbrains-mono-nerd": "fonts-jetbrains-mono",
		"vulkan-icd-loader":       "libvulkan1",
		"wpa_supplicant":          "wpasupplicant",
		"xorg-xwayland":           "xwayland",

		// Absent from Debian: skipped. matugen means no wallpaper palette,
		// the rest are optional tools and cosmetic extras.
		"limine":                        "",
		"limine-mkinitcpio-hook":        "",
		"limine-snapper-sync":           "",
		"mkinitcpio":                    "",
		"snap-pac":                      "",
		"matugen":                       "",
		"otf-space-grotesk":             "",
		"songrec":                       "",
		"ttf-material-symbols-variable": "",
		"vimix-cursors":                 "",
		"waifu2x-ncnn-vulkan":           "",
		"yazi":                          "",
	},
}

// activeDistro is set once by detectFacts; installed() reads it from the
// detection paths that have no engine to hand.
var activeDistro = archLinux

// Package names verified against the Void repodata index (x86_64,
// 2026-09-30; 14790 packages). Void ships no Hyprland stack at all
// (hyprland, hypridle and xdg-desktop-portal-hyprland are all absent), so a
// Void install is niri-first and Hyprland is a hand-build; see docs/void.md.
var voidLinux = &distro{
	id:         "void",
	name:       "Void",
	fromSource: true,
	installCmd: []string{"xbps-install", "-S", "-y"},
	removeCmd:  []string{"xbps-remove", "-y"},
	updateCmd:  []string{"xbps-install", "-Suy"},
	refreshCmd: []string{"xbps-install", "-S"},
	queryCmd:   []string{"xbps-query"},
	// zrepo is the Z Linux binary repository (signed XBPS, glibc x86_64): the
	// source for every package Void's official repos do not carry.
	zrepoURL:     "https://github.com/SrDicov/z-repo/releases/download/stable",
	zrepoKeyURL:  "https://raw.githubusercontent.com/SrDicov/z-repo/master/keys/zlinux-repo.pub",
	zrepoKeyName: "zlinux-repo",
	zrepoExtras:  []string{"zen-browser-bin"},
	build: []string{
		"base-devel", "go", "cmake", "ninja", "pkg-config",
		"qt6-base-devel", "qt6-declarative-devel", "qt6-multimedia-devel",
		"qt6-svg-devel", "qt6-wayland-devel", "qt6-shadertools-devel",
		"qt6-qt5compat-devel", "wayland-devel", "vulkan-loader-devel",
		"libdrm-devel", "elogind-devel",
	},
	rename: map[string]string{
		"base":                    "",
		"bluez-utils":             "bluez",
		"fish":                    "fish-shell",
		"gst-plugins-bad":         "gst-plugins-bad1",
		"gst-plugins-base":        "gst-plugins-base1",
		"gst-plugins-good":        "gst-plugins-good1",
		"gst-plugins-ugly":        "gst-plugins-ugly1",
		"imagemagick":             "ImageMagick",
		"inter-font":              "font-inter",
		"mangohud":                "MangoHud",
		"networkmanager":          "NetworkManager",
		"noto-fonts":              "noto-fonts-ttf",
		"pipewire-alsa":           "alsa-pipewire",
		"pipewire-audio":          "",
		"pipewire-pulse":          "",
		"python":                  "python3",
		"python-pip":              "python3-pip",
		"python-pipx":             "python3-pipx",
		"npm":                     "",
		"qemu-desktop":            "qemu",
		"qt6-5compat":             "qt6-qt5compat",
		"qt6-multimedia-ffmpeg":   "qt6-multimedia",
		"tesseract-data-eng":      "tesseract-ocr-eng",
		"ttf-firacode-nerd":       "",
		"ttf-hack-nerd":           "",
		"ttf-jetbrains-mono-nerd": "nerd-fonts-ttf",
		// from z-repo (verified against its stable repodata, 80 packages)
		"ttf-material-symbols-variable": "not-st",
		"vimix-cursors":                 "bibata-cursor-theme",
		"vulkan-icd-loader":             "vulkan-loader",
		"xorg-xwayland":                 "xorg-server-xwayland",
		"xpadneo-dkms":                  "xpadneo",
		"amd-ucode":                     "linux-firmware-amd",
		"intel-ucode":                   "linux-firmware-intel",

		// Absent from Void: skipped here, hand-built or dropped per docs/void.md.
		// (limine hooks are also in engine.go bootChainSkip; both must agree.)
		"blesh":                  "",
		"game-devices-udev":      "",
		"hypridle":               "",
		"limine-mkinitcpio-hook": "",
		"limine-snapper-sync":    "",
		"snap-pac":               "",
		"ttf-maple-mono-nf":      "",
		"waifu2x-ncnn-vulkan":    "",
	},
}

func detectDistro(id, like string) *distro {
	switch {
	case id == "arch" || strings.Contains(like, "arch"):
		return archLinux
	case id == "void":
		return voidLinux
	case id == "debian" || strings.Contains(like, "debian"):
		return debianLinux
	}
	return nil
}

// local returns the package's name on this distro, or "" when it does not exist.
func (d *distro) local(pkg string) string {
	if to, ok := d.rename[pkg]; ok {
		return to
	}
	return pkg
}

// localAll maps a base.packages list, dropping what this distro does not carry.
func (d *distro) localAll(pkgs []string) []string {
	out := make([]string, 0, len(pkgs))
	for _, p := range pkgs {
		if l := d.local(p); l != "" {
			out = append(out, l)
		}
	}
	return out
}

func (d *distro) installArgs(pkgs []string) []string {
	return append(append([]string{}, d.installCmd...), pkgs...)
}

func (d *distro) removeArgs(pkgs []string) []string {
	return append(append([]string{}, d.removeCmd...), pkgs...)
}

func (d *distro) installedPkg(pkg string) bool {
	args := append(append([]string{}, d.queryCmd[1:]...), pkg)
	out, err := exec.Command(d.queryCmd[0], args...).Output()
	if err != nil {
		return false
	}
	if d.id == "debian" {
		return strings.Contains(string(out), "install ok installed")
	}
	return true
}

// installed queries the detected distro. Replaces the old pacman-only helper.
func installed(pkg string) bool { return activeDistro.installedPkg(pkg) }

// d is the engine's detected distro; archLinux until detection says otherwise.
func (e *engine) d() *distro {
	if e.f != nil && e.f.distro != nil {
		return e.f.distro
	}
	return activeDistro
}

// ryokuBin finds the ryoku CLI: /usr/bin from a package, ~/.local/bin from a
// fromSource build. Empty when it is not installed yet.
func (e *engine) ryokuBin() string {
	cands := []string{"/usr/bin/ryoku"}
	if e.f != nil && e.f.homeDir != "" {
		cands = append(cands, filepath.Join(e.f.homeDir, ".local", "bin", "ryoku"))
	}
	for _, c := range cands {
		if fi, err := os.Stat(c); err == nil && !fi.IsDir() {
			return c
		}
	}
	return ""
}

// detectHostDistro resolves the distro from /etc/os-release and latches it, so
// the preflight gate and the later detection pass agree. RYOKU_FORCE_DISTRO
// overrides it, the same seam detect() honours.
func detectHostDistro() *distro {
	if id := strings.TrimSpace(os.Getenv("RYOKU_FORCE_DISTRO")); id != "" {
		if d := detectDistro(id, ""); d != nil {
			activeDistro = d
			return d
		}
	}
	b, err := os.ReadFile("/etc/os-release")
	if err != nil {
		return nil
	}
	id, like, _ := parseOSRelease(string(b))
	d := detectDistro(id, like)
	if d != nil {
		activeDistro = d
	}
	return d
}

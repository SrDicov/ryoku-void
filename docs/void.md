# Void Linux port

The shell installer (`ryoku-shell-installer/`) supports Void: `xbps-install`
for packages, runit for services, from-source build via `ryoku/shell/deploy.sh`
(the `[ryoku]` pacman repo cannot serve a Void box). All package names below
were verified against the official Void repodata index (x86_64, 14790
packages); the rename map in `ryoku-shell-installer/distro.go` is generated
from it.

## Compositor decision

Void ships **no Hyprland stack**: `hyprland`, `hypridle` and
`xdg-desktop-portal-hyprland` are all absent from the official repos
(`hyprutils` and `hyprwayland-scanner` exist as build deps only). So a Void
install is **niri-first** (`niri` is packaged). Hyprland on Void is a
hand-build; the list is under "Hand-build" below.

## Services: systemd -> runit

System services are links in `/var/service` -> `/etc/sv/<name>`
(`ln -sf` enables, `rm` disables). The installer abstracts this in
`ryoku-shell-installer/init.go`; nothing else branches on pid 1.

| systemd unit | runit service | note |
|---|---|---|
| `NetworkManager.service` | `NetworkManager` | same daemon, capital N in both |
| `bluetooth.service` | `bluetoothd` | only name that changes |
| `sddm.service` | `sddm` | Void builds SDDM with `USE_ELOGIND=ON`, Wayland greeter works |
| `rtkit-daemon.service` | `rtkit` | same |
| `power-profiles-daemon.service` | `power-profiles-daemon` | same |
| `docker.service` | `docker` | still opt-in, provisioned on first use, never enabled at install |
| `dhcpcd.service` / `connman.service` | `dhcpcd` / `connmand` | retired as rival network stacks |
| `gdm/lightdm/greetd/ly` | same names under `/var/service` | retired as rival DMs |
| `ryoku-boot-guard.service` | no equivalent | oneshot revert guard; needs a runit oneshot + pre-sddm ordering, not yet ported |
| `ryoku-network-kill-{guard,disconnect}` | no equivalent | nftables rules + `nmcli` calls are portable; the unit wiring is not yet ported |
| `pacman-init.service` | n/a | ISO-only, irrelevant to the shell installer |

User-session services have no system runit counterpart. `ryoku/shell/deploy.sh`
lays them as `~/runit` services for the user's runsvdir on a runit box (systemd
user units on Arch), so `runsvdir ~/runit &` in the shell profile or compositor
autostart is the only thing a user has to add:

| systemd user unit | `~/runit/<name>/run` |
|---|---|
| `ryoku-shell.service` | `ryoku-shell quit` -> `ryoku-qylock-activate` -> `ryoku-shell daemon` as a child, TERM trap runs `ryoku-qylock-activate --prepare-stop` (the unit's ExecStartPre/ExecStop pair) |
| `ryoku-idle.service` | `ryoku-idle start` |
| `ryoku-clamshell.service` | `ryoku-clamshell daemon` |
| `ryogami.service` | `RYOGAMI_SHELL_QML=... ryogami` |
| `ryoku-rashin.service` | `ryoku-rashin serve --if-enabled` |
| `ryoku-eq.service` | `pipewire -c $XDG_RUNTIME_DIR/ryoku/eq/filter-chain.conf`, only when that file exists |
| `ryoku-bootstrap.service` | no service: one-shot `ryoku materialize` at first login |
| `ryoku-ai-usage.service` + timer | no service: the three collectors refresh once per deploy (runit has no timers) |
| `ryoku-bluetooth-reset.service` | login hook (`sv restart bluetoothd`; Void authorizes through `polkit-elogind`) |
| rival daemons (dunst, waybar, swww, ...) | a `~/runit` link is the probe; the installer unlinks it and records the re-link in `restore.sh` |

Deploy-time differences on runit, all inside `ryoku/shell/deploy.sh`:

- the transient `systemd-inhibit` sleep-block guard has no runit form, so the
  live cutover stops the old owners, swaps, and restarts them directly; the
  clamshell daemon reasserts its elogind inhibitor on the way back.
- the logind drop-in goes to `/etc/elogind/logind.conf.d/10-ryoku-lid.conf`
  (elogind reads the same format from its own directory).
- `WirePlumber`, `ryogami` and the session services are cycled with `sv
  restart` instead of `systemctl --user`.
- `ryoku-qylock-unlock-prepare` has no `systemd-inhibit` to hold a sleep
  block, so it skips that guard and still enforces the proof and the session
  check (the guard is a suspend nicety, the proof is the lock's real gate).

## Packages: pacman -> xbps

Identical names are omitted (most of the set: `firefox`, `kitty`, `neovim`,
`pipewire`, `wireplumber`, `sddm`, `weston`, `niri`, `quickshell`,
`matugen`, `docker`, `qemu`, `gamescope`, `flatpak`, ...). Only renames,
splits and drops:

| Arch (`base.packages`) | Void (xbps) |
|---|---|
| `networkmanager` | `NetworkManager` |
| `bluez-utils` | `bluez` (merged) |
| `fish` | `fish-shell` |
| `inter-font` | `font-inter` |
| `noto-fonts` | `noto-fonts-ttf` |
| `qemu-desktop` | `qemu` |
| `vulkan-icd-loader` | `vulkan-loader` |
| `xorg-xwayland` | `xorg-server-xwayland` |
| `tesseract-data-eng` | `tesseract-ocr-eng` |
| `qt6-5compat` | `qt6-qt5compat` |
| `qt6-multimedia-ffmpeg` | `qt6-multimedia` (backend included) |
| `gst-plugins-{base,good,bad,ugly}` | `gst-plugins-{base1,good1,bad1,ugly1}` |
| `imagemagick` | `ImageMagick` |
| `mangohud` | `MangoHud` |
| `pipewire-alsa` | `alsa-pipewire` |
| `pipewire-pulse`, `pipewire-audio` | dropped (shipped inside Void's `pipewire`) |
| `python`, `python-pip`, `python-pipx` | `python3`, `python3-pip`, `python3-pipx` |
| `npm` | dropped (no standalone package; `nodejs` + corepack/mise cover it) |
| `xpadneo-dkms` | `xpadneo` |
| `ttf-jetbrains-mono-nerd` | `nerd-fonts-ttf` (covers the other nerd sets too) |
| `ttf-firacode-nerd`, `ttf-hack-nerd` | dropped (covered by `nerd-fonts-ttf`) |
| `amd-ucode` / `intel-ucode` | `linux-firmware-amd` / `linux-firmware-intel` (no standalone ucode packages) |
| `vulkan-radeon`, `vulkan-intel`, `vulkan-swrast` (hardware sets) | covered by `mesa` (`mesa-dri`, `mesa-vulkan-*`; no per-vendor packages) |
| `blesh` | dropped (no package; readline fallback) |
| `vimix-cursors`, `phinger-cursors`, `catppuccin-cursors-mocha`, `apple_cursor`, `bibata-cursor-theme-bin` | dropped (none packaged; configure a stocked theme) |
| `otf-space-grotesk`, `ttf-maple-mono-nf`, `ttf-material-symbols-variable` | dropped (none packaged) |
| `waifu2x-ncnn-vulkan` | dropped (`waifu2x-converter-cpp` is a different binary, not a drop-in) |
| `hypridle` | dropped (hand-build with Hyprland, or niri needs no idle daemon of its own) |
| `game-devices-udev` | dropped (hand-build) |
| `snap-pac`, `limine-mkinitcpio-hook`, `limine-snapper-sync` | dropped (Arch boot stack; a converted box keeps its own bootloader) |
| `base`, `linux`, `linux-headers`, `mkinitcpio`, `btrfs-progs`, `cryptsetup`, `dosfstools`, `efibootmgr`, `limine`, `plymouth`, `snapper` | skipped by `bootChainSkip`: a converted box keeps its kernel and boot chain |

Dev toolchains (`dev.packages` via rename): `go`, `nodejs`, `mise` identical;
`python` -> `python3`, `python-pip` -> `python3-pip`, `python-pipx` ->
`python3-pipx`, `npm` dropped. Build deps for the from-source compile are the
`build` list on `voidLinux` (`base-devel`, `go`, `cmake`, `ninja`,
`qt6-*-devel`, `wayland-devel`, `elogind-devel`, ...).

AUR extras (`aur.packages`) never install on from-source distros; on Void
`localsend-bin`, `voxtype-bin`, `nvibrant-bin`, `zen-browser-bin`,
`pam-fprint-grosshack`, `ttf-fraunces-variable` are all unpackaged, so the
voice-dictation, LAN-share and fingerprint-greeter paths stay off until
hand-built.

## z-repo: the packages Void's official repos lack

Signed third-party XBPS repository (glibc `x86_64`), published as the assets of
the `stable` release of `SrDicov/z-repo`; templates in `SrDicov/z-packages`.

| | |
|---|---|
| Repo | `https://github.com/SrDicov/z-repo/releases/download/stable` |
| Templates | `https://github.com/SrDicov/z-packages` (`srcpkgs/`) |
| Key | `keys/zlinux-repo.pub` in `SrDicov/z-repo` (RSA, `Z Linux Core`) |
| Contents | 80 packages, none of them in Void's official index (verified by diffing both repodata indexes) |

The installer writes `/etc/xbps.d/20-ryoku-void.conf` (step `zrepo`, before
tools and packages) and syncs once; xbps imports the signing key from the
signed `index-meta` into `/var/db/xbps/keys/<fingerprint>.plist` on that sync,
which is what makes z-repo packages verify. `restore.sh` removes the file.

Ryoku-relevant packages it serves today, wired into the rename map:

| Arch name | z-repo name | why |
|---|---|---|
| `vimix-cursors` (and Bibata, phinger, catppuccin) | `bibata-cursor-theme` | the only packaged cursor set |
| `ttf-material-symbols-variable` | `not-st` | Material Symbols variable font |
| `ttf-jetbrains-mono-nerd` (alt) | `font-JetBrainsMono` | upstream release font |
| `zen-browser-bin` (AUR extra) | `zen-browser-bin` | default browser, installed best-effort |

Other useful ones already in the repo (not touched by the installer):
`vesktop-bin`, `opencode-bin`, `vscode-bin`, `python3-inputs`, `python3-steam`,
`libva-intel-driver-irql`, `zerotierone`, `mullvad-vpn-bin`, `protonvpn-gui`,
`noctalia`, `ly`, `labwc-singularity`, `pear-desktop-bin`, `unityhub-bin`,
`heroic-games-bin`, `portproton-bin`, `protonup-qt`, `spicetify`, `vary`,
`reaper-bin`, `aseprite`.

Not in z-repo either, so still yours to build: `hyprland`, `hypridle`,
`xdg-desktop-portal-hyprland`, the Ryoku Hyprland plugins, `quickshell`
(official), `voxtype-bin`, `localsend-bin`, `game-devices-udev`,
`waifu2x-ncnn-vulkan`, `otf-space-grotesk`, `ttf-maple-mono-nf`,
`nvibrant-bin`, `ttf-fraunces-variable`, `pam-fprint-grosshack`, `blesh`.

## Hand-build list (tu parte manual)

Nombra estos si los quieres: no existen en los repos oficiales de Void **ni en
z-repo**.

1. `hyprland` (niri cubre el escritorio; sin esto no hay sesion Hyprland)
2. `hypridle` (idle/lock/suspend en Hyprland)
3. `xdg-desktop-portal-hyprland` (screenshare en Hyprland)
4. Hyprland plugins Ryoku: `hypr-dynamic-cursors`, `ryoku-hypr-plugins`, `hyprglass`, `imgborders`, `ryoku-keysounds`
5. `ryoku-desktop` umbrella + `ryoku-shell`, `ryoku-hub`, `ryoku-rashin`, `ryoku-blobs`, `ryogami`, `gpk` (o compila con `xbps-src`; el instalador ya compila Go/QML via `deploy.sh`)
6. `voxtype-bin` (dictado por voz offline; sin esto Super+` no transcribe)
7. `localsend-bin` (stash de archivos LAN)
8. `game-devices-udev` (bateria/config de mandos en Steam)
9. `waifu2x-ncnn-vulkan` (export HD de ryoshot / Enhance de ryowalls)
10. Cursor sets: Bibata, vimix, phinger, catppuccin-mocha (cualquiera vale; el picker ofrece el instalado)
11. `otf-space-grotesk`, `ttf-maple-mono-nf`, `ttf-material-symbols-variable` (tipografia de marca)
12. `nvibrant-bin` (solo NVIDIA Wayland, fader de saturacion)
13. `zen-browser-bin` (navegador por defecto; `chromium`/`firefox` cubren)
14. NVIDIA propietario: vive en `void-repo-nonfree` (`void-repo-nonfree`, `void-repo-multilib-nonfree`), no en main

## Not yet ported (honesto)

Verified working (built, unit-tested, dry-run): the installer's Void lane
(`RYOKU_FORCE_DISTRO=void ... --dry-run` prints 13 xbps-only steps), the
package rename map, the z-repo trust step, the init abstraction, the runit
service layout, and the lock unlock path.

Not ported, and how the port behaves until they are:

- `ryoku update` / `ryoku doctor` still drive pacman and systemd in several
  places (`internal/updater`, `wm use`, the boot guard, the portal routing).
  On Void the update path is `xbps-install -Suy` plus a rebuild through
  `ryoku/shell/deploy.sh`; `ryoku doctor` reports a session-target finding it
  cannot converge, because that target is systemd-only.
- the network kill-switch system services and `ryoku-boot-guard` have no runit
  port (the helpers and the polkit rule install; the boot-time guard does not).
- `installation/` (ISO, TUI, backend) is Arch-only by design and out of scope
  for this fork.
- Hyprland needs a hand-build; until then a Void box runs niri.

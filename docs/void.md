# Void Linux port

Ryoku ships an official Void edition: niri, runit, Turnstile, elogind, SDDM,
and XBPS. The package translation lives in `void/packages/`, the runit init
under `void/init/`, and the whole lane is described in `void/README.md`. This
file covers what the z-repo lane adds on top of it.

## What upstream ships, and what it does not

The Void edition installs signed packages from the Ryoku XBPS repository, and
`void/packages/translations.tsv` maps every shared package lane to a Void
package. Entries marked `-` carry the reason they cannot enter the repo. Two
groups matter here.

**Hyprland.** The table marks the whole Hyprland family unavailable with the
note that "Ryoku's Hyprland needs GCC 15 and Void still ships GCC 14". That is
true for a plain Void toolchain: Hyprland 0.56 sets `CMAKE_CXX_STANDARD 26` and
its sources use `#embed`, `std::string + std::string_view`,
`std::ranges::starts_with`, and `std::vector::insert_range`, none of which
libstdc++ 14 carries.

**Third-party packages.** The z-repo serves the packages Void's own
repositories and the Ryoku repository do not carry, and it is where the
Hyprland stack lives.

## The z-repo lane

`z-repo` is a signed XBPS repository built from `SrDicov/z-packages`. The
installer adds it after the Ryoku repository, imports its key, and installs
the extras it serves. The lane is declared in
`ryoku-shell-installer/distro.go`: the repository URL, the key URL, the key
name, and the packages to pull from it.

| Package | What it is |
|---|---|
| `hyprutils`, `hyprlang`, `hyprcursor`, `hyprgraphics`, `aquamarine` | The Hyprland library stack, rebuilt against Void's toolchain |
| `hyprwire` | The wire protocol Hyprland 0.56 speaks |
| `hyprland` | The compositor, built with clang 21 |
| `hypridle`, `xdg-desktop-portal-hyprland` | The idle daemon and the portal backend |
| `hyprgrass`, `hyprglass`, `imgborders`, `hypr-dynamic-cursors`, `ryoku-hypr-plugins` | The compositor plugins Ryoku ships |
| `ryoku-keysounds`, `ryoku-keysounds-profiles` | The key sound plugin and its profiles |
| `re2`, `lua55` | The libraries Hyprland 0.56 expects, at the versions it expects |
| `game-devices-udev`, `pam-fprint-grosshack` | Hardware support Void does not package |
| `localsend-bin`, `nvibrant`, `voxtype-bin`, `waifu2x-ncnn-vulkan` | The optional extras |
| `font-space-grotesk`, `font-maple-mono-nf`, `font-fraunces`, `vimix-cursor-theme`, `phinger-cursor-theme` | The fonts and cursors Ryoku ships |

## Building the Hyprland stack on Void

Void ships GCC 14.2, whose libstdc++ predates the C++23 and C++26 library
pieces Hyprland 0.56 needs. Three things make it build.

**A newer compiler.** Void carries clang 21, which implements `#embed` and the
C++26 language. The templates select it through CMake, because the chroot
enters with `env -i` and drops `CC` and `CXX` on the way in:

```
configure_args+=" -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++"
```

**The library gaps.** `std::string + std::string_view` and
`std::ranges::starts_with` are C++26. `hyprland` ships a compatibility header
that adds both and forces it into every translation unit with `-include`. The
remaining gap, `std::vector::insert_range`, is a member function no shim can
add, so the one call site is patched in `do_patch`.

**The pkg-config chain.** `hyprland.pc` lists the whole library stack under
`Requires:`, so a consumer needs every one of those `.pc` files present or
pkg-config refuses the module. The `-devel` packages of the stack carry them.

## The compositor plugins

Hyprland plugins are ABI-locked to the compositor: a plugin built against a
different Hyprland fails to load. Upstream keeps the mapping in each
plugin's `hyprpm.toml`, which pairs a Hyprland commit with a plugin commit.
The z-packages templates read the Hyprland commit from the installed
`version.h`, take the plugin commit `hyprpm.toml` pins for it, and write the
`.abi` receipt beside the plugin so the Hub can tell a stale build from a
working one.

Two details are Void specific. Void's `glm` is header only and ships no
`glm.pc`, and meson asks for one, so the build writes a shim. Void's `lua` is
5.3 while Hyprland 0.56 runs on Lua 5.5, so the build resolves Lua through a
5.5 shim as well.

## Services

The Void edition is niri, and its services are runit services under
`void/init/`: system services are links in `/var/service` pointing at
`/etc/sv/<name>`, and the user session services are links under
`~/.config/service`. The installer reaches both through `ryoku-host`, so no
desktop code names an init system.

## Hand-build

Nothing in the Hyprland lane needs a hand build any more: the z-repo serves
the whole stack. The packages Void itself does not carry and the z-repo does
not either remain hand builds, and the translation table records each one
with its reason.

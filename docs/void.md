# Void Linux port

Ryoku ships an official Void edition: Hyprland and niri, runit, Turnstile,
elogind, SDDM, and XBPS. The package translation lives in `void/packages/`,
the runit init under `void/init/`, and the whole lane is described in
`void/README.md`. This file covers what the z-repo lane adds on top of it.

## What upstream ships, and what it does not

The Void edition installs signed packages from the Ryoku XBPS repository, and
`void/packages/translations.tsv` maps every shared package lane to a Void
package, or to the z-repo package that serves it through `repo=zrepo`. The
Hyprland family rides that lane: Void's toolchain cannot build it, the z-repo
serves the whole stack, so the table points each row at the same-named package
in the z-repo instead of marking it `-`. Entries marked `-` carry the reason
they cannot enter any repository.

**Hyprland.** The table used to mark the whole Hyprland family unavailable with
the note that "Ryoku's Hyprland needs GCC 15 and Void still ships GCC 14". That
is true for a plain Void toolchain: Hyprland 0.56 sets `CMAKE_CXX_STANDARD 26`
and its sources use `#embed`, `std::string + std::string_view`,
`std::ranges::starts_with`, and `std::vector::insert_range`, none of which
libstdc++ 14 carries.

**Third-party packages.** The z-repo serves the packages Void's own
repositories and the Ryoku repository do not carry, and it is where the
Hyprland stack lives.

## The z-repo lane

`z-repo` is a signed XBPS repository built from `SrDicov/z-packages` and
published on the release assets of `SrDicov/z-repo`. The installer adds it
after the Ryoku repository and never downloads its key: `registerVoidZRepo`
(`ryoku-shell-installer/engine.go`) writes the repository into
`/etc/xbps.d/25-zrepo.conf` and then runs `xbps-install -S` with the answer
to the key prompt fed on stdin, so xbps itself imports the key carried by
the signed repodata into `/var/db/xbps/keys/<fingerprint>.plist` on the
first sync. The fingerprint is fixed in `ryoku-shell-installer/distro.go`
(`zrepoKeyFP`) and names the plist file xbps reads back there
(`lifecycle.go`). The repository publishes the key both in PEM and in that
plist form, named after the fingerprint with its colons, because that is
the file name xbps looks for (`SrDicov/z-repo`,
`.github/scripts/publish.sh`).

The extras the installer pulls along with the lane install best effort
(`installVoidZRepoExtras`, `engine.go`): a missing extra or an unreachable
repository does not abort the install.

| Package | What it is |
|---|---|
| `hyprutils`, `hyprlang`, `hyprcursor`, `hyprgraphics`, `aquamarine` | The Hyprland library stack, rebuilt against Void's toolchain |
| `hyprwire` | The wire protocol Hyprland 0.56 speaks |
| `hyprland` | The compositor, built with clang 21 |
| `xdg-desktop-portal-hyprland` | The Hyprland portal backend |
| `hyprpolkitagent`, `hyprsunset`, `ryoku-desktop-hyprland` | The polkit authentication agent, the night-light color-temperature toggle and the Hyprland edition's desktop meta-package |
| `hyprland-preview-share-picker` | The screen-share source chooser the portal calls by name |
| `hyprgrass`, `hyprglass`, `imgborders`, `hypr-dynamic-cursors`, `ryoku-hypr-plugins` | The compositor plugins Ryoku ships |
| `ryoku-keysounds`, `ryoku-keysounds-profiles` | The key sound plugin and its profiles |
| `re2`, `lua55` | The libraries Hyprland 0.56 expects, at the versions it expects |
| `game-devices-udev`, `pam-fprint-grosshack`, `asusctl` | Hardware support Void does not package |
| `localsend-bin`, `nvibrant`, `waifu2x-ncnn-vulkan` | The optional extras |
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

**The library gaps.** The `hyprland` template (`SrDicov/z-packages`) writes
`hyprland_compat.hpp` in `do_patch` and forces it into every translation
unit with `-include` in `CXXFLAGS`. The header adds the
`std::basic_string + std::string_view` operator and a
`std::ranges::starts_with` template. The remaining gap,
`std::vector::insert_range`, is a member function no shim can add, so the
one call site is rewritten in `do_patch`.

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

## Compositors and services

The Void edition offers Hyprland and niri and defaults to Hyprland, and no
one writes that list by hand. `loadEditionCompositors`
(`ryoku-shell-installer/edition.go`) resolves the edition from
`void/packages/translations.tsv` through `installerplan.ResolveEdition`
(`installation/installerplan/plan.go`): a choice is available only when
every package it names has a non-`-` target in the table, and the table
points `ryoku-desktop-hyprland` at the z-repo lane (`repo=zrepo`), so
Hyprland rides the third-party lane instead of dropping off the list the
way `ryoku-desktop-wayfire` does. The order comes from
`installation/installerplan/choices.tsv`, which lists Hyprland first and
gives the compositor choice the `first-available` policy, so the first
available compositor is the fresh-install default (`FreshSelection`,
`installation/installerplan/plan.go`). Upstream asserts the Void edition
offers niri only; this fork keeps Hyprland and carries the patched Void
edition test (`installation/installerplan/plan_test.go`). The
`ryoku-desktop-hyprland` meta-package does not come from the Ryoku
repository either: the template in `SrDicov/z-packages` builds it from a
codeload tarball pinned to an exact `SrDicov/ryoku-void` commit.

Its services are runit services under `void/init/`: system services are
links in `/var/service` pointing at
`/etc/sv/<name>`, and the user session services are links under
`~/.config/service`. The installer reaches both through `ryoku-host`, so no
desktop code names an init system.

## Hand-build

Nothing in the Hyprland lane needs a hand build any more: the z-repo serves
the whole stack. The packages Void itself does not carry and the z-repo does
not either remain hand builds, and the translation table records each one
with its reason.

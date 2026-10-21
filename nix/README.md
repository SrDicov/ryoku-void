# Ryoku Nix packages

This directory packages the upstream Ryoku application components: executables,
QML modules, desktop assets and compositor-agnostic data. It does not configure
a NixOS machine. The NixOS module, installer, systemd units, login manager,
hardware policy and update workflow remain in `Ryoku-dev/Ryoku-on-NixOS`.

This is the **initial packaging extraction**, not a validated release. The
package derivations originated in the NixOS port and need build-validation
against upstream's own `ryoku/` tree, then removal of temporary NixOS-only
patches as upstream becomes path-configurable.

Evaluate locally with:

```bash
nix flake lock
nix eval --raw .#packages.x86_64-linux.ryoku-desktop.drvPath
```

After the upstream packaging PR is merged into `unstable-dev`, the target is:

```bash
nix build github:Ryoku-dev/ryoku/unstable-dev#ryoku-desktop
```

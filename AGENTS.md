# Ryoku

A hand-built Arch Linux distribution: a Hyprland or niri desktop (the Ryoku shell), a guided installer, and the system definition that produces both. The repo is the single source of truth. Deployment is one way, repo to `~/.config` (and a few system paths); never copy a live tweak back, change the repo and redeploy.

New here? Read in order, keep open while you work:

- `docs/ryoku.md` what Ryoku is and how the parts fit.
- `docs/structure.md` where everything lives and the one job it has.
- `docs/compositors.md` the window-manager seam: provider contract and capabilities.
- `docs/adding-a-window-manager.md` walkthrough for a new compositor.
- `docs/conventions.md` how code and config are written.
- `docs/development.md` deploy, test, and commit loop.
- `docs/updates.md` how a change reaches a running machine.

## Cardinal rules

Not negotiable. Most are enforced by `.githooks/`, never use `--no-verify`.

1. **Organization is the point.** Every file and folder has one purpose, appears once. Search before adding; reuse, never duplicate. See `docs/structure.md`.
2. **Compositor config is in its own language.** Hyprland is Lua under `ryoku/hyprland/`, niri is KDL under `ryoku/niri/`, one concern per file, never a hand-written `hyprland.conf`. Third-party tools keep native format under their own dir (`kitty.conf`, `hypridle.conf`). Nothing outside `ryoku/wm/` may name a compositor: ask `caps`, see `docs/compositors.md`.
3. **One concern per file.** A Lua module does one thing. A QML component is one component in one file.
4. **Launch through Spawn.** Anything that can end up running Quickshell goes through `Spawn` in `Ryoku.Ui.Singletons`, never bare `Quickshell.execDetached` or `DesktopEntry.execute()`. A crashed instance leaks `__QUICKSHELL_CRASH_INFO_FD` and the child relaunches the desktop instead of the app.
5. **System logic is a named helper.** Multi-step shell is a `ryoku-<thing>` script under `system/hardware/`, invoked by name. Never inline it in Lua, never copy a helper's logic twice.
6. **Comment the why, never the what.** No commented-out code, no filler. Mostly-comments file means the code is too complex.
7. **Every change must reach users.** Dev boxes run the checkout, users run signed `[ryoku]` packages via `ryoku update` (`materialize` for config, `doctor` for drift). A user-facing config must ship in a package or be seeded by the installer; user edits live in `~/.config/ryoku/user_edits` and survive updates. A removed/renamed `shell.json` key needs a `doctor` reconciler. Work lands only on `main` fast-forward from `unstable-dev`. See `docs/updates.md`; `bin/ryoku-dev-verify-delivery` enforces it.
8. **Display English must be wrapped where displayed** (`I18n.tr` in QML, `i18n.T` in Go, Hub schema label/desc, installer `log 'fmt %s'`), or it ships untranslated in all 35 languages. One row in `ryoku/i18n/langs.json` adds a language.

## Dev loop

Develop on a running Ryoku (or Arch on Hyprland/niri). Never edit `~/.config` directly.

```bash
ryoku/shell/dev-run.sh        # build ryoku-shell, run from checkout, hot reload
ryoku/hyprland/dev-binds.sh on # shell keys for this session
ryoku/shell/dev-stop.sh       # stop the dev shell
ryoku/shell/deploy.sh         # lay repo configs into ~/.config one way
```

Gotchas: a `.frag` needs its compiled `.qsb` committed beside it (`qsb --qt6 -o <name>.frag.qsb <name>.frag`), and the surface process restarted, hot reload keeps serving the old shader. `ryoku update` on a checkout reconciles onto `origin/<channel>`: unpushed commits on `unstable-dev` are dropped, keep work pushed or on another branch.

## Verify before commit

Test on the running system, not just parsing. Then run the gates that match what you touched:

```bash
luac -p <file>                                  # every changed Lua file
bash -n <file>                                  # every changed shell script
bin/ryoku-dev-verify-wm-isolation               # no compositor name outside ryoku/wm/
bin/ryoku-dev-verify-delivery                   # every shipped config reaches users
bin/ryoku-dev-lint-qml <config-root>            # changed QML still loads (after deploy)
go build ./... && go vet ./... && go test ./... # in each Go module touched
```

`shellcheck` runs on push. Installer dry run matrix is in `docs/development.md`.

## Commits

Subjects are `[area] scope: imperative summary`, area is `global|installation|system|ryoku|docs|test|tooling|release` (shell uses `[global]`). 72 chars or fewer, no trailing period, no em-dash, no authorship trailers. One logical change per commit, update the matching `CHANGELOG.md`. User-visible change adds a trailer the release bot harvests: `Note: New|Fixed|Removed: ...`. See `CONTRIBUTING.md`.

## Top-level map

| Path | Purpose |
|---|---|
| `ryoku/` | Desktop: wm seam plus per-compositor configs, shell UI, lockscreen, app configs, brand. |
| `system/` | Machine definition: boot chain, hardware policy, package sets. |
| `installation/` | How a machine is built: TUI, backend installer, ISO profile. |
| `release/` | Packaging: desktop PKGBUILDs, `[ryoku]` repo builder, signing keyring. |
| `docs/` | These guides. |
| `.githooks/` `bin/ryoku-dev-*` | Commit/push gates, every change must pass. |

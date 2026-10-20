# Fedora RPM packaging

Specs here build either the shared Ryoku tree or a separately released upstream
project. Source preparation is online, but every SRPM rebuild is offline.

Release builds use the same version and channel values published to users:

```sh
RYOKU_PKGVER=1.2.3 \
RYOKU_RELEASE=v1.2.3 \
RYOKU_CHANNEL=stable \
RYOKU_SRPM_OUT=/tmp/ryoku-srpms \
  fedora/packages/rpm/prepare-srpms.sh
```

Set `RYOKU_RPM_LOCAL=1` for an uncommitted local build. Before preparing a full
set locally, install every spec's build requirements with `dnf builddep`. Source
fetch hooks may need those tools as well as the eventual RPM build.

## Ryoku-tree packages

A Ryoku-tree spec declares `Source0: ryoku-%{version}.tar.gz`. Preparation
replaces its Version with `RYOKU_PKGVER` and its Release with
`RYOKU_RPM_REVISION`, which defaults to 1. The package stages its payload through
`stage-package.sh` and `payload/<name>.sh`.

Large paths can be restricted to their owning package in `source-owners`.
A fetch hook for a tree package writes fetched content below
`$RYOKU_FETCH_TREE/.rpm-<name>/`; add that path and package to `source-owners`.

## Upstream packages

An upstream spec keeps its checked-in Version and Release. Add it with:

1. HTTPS `Source0` through `SourceN` entries. `URL#/localname` gives a stable
   local filename.
2. `sources/<name>` with one dist-git checksum for every URL source:
   `SHA256 (localname) = <64 lowercase hex>`.
3. Explicit `%files` entries and `%license` for license files where practical.

Preparation downloads each URL and stops on a missing, extra, malformed, or
mismatched checksum. Other URL schemes are rejected.

### Refreshing pinned upstream releases

`system/packages/upstream-pins.tsv` is the inventory for Fedora and Void
upstream pins. It records the release source, artifact patterns, and every file
that carries each pin. `.github/workflows/refresh-pins.yml` checks it weekly,
updates all editions of a package together, verifies both package trees, and
pushes the `bot/refresh-pins` branch with a pull request against `unstable-dev`
(or a link to open one in the run summary, since Actions may not open PRs here).
Major-version updates remain listed but require `allow_major=yes` in the
manifest before the bot will write them.

For a manual refresh, run:

```sh
bin/ryoku-refresh-pins --check
bin/ryoku-refresh-pins --write
bash tests/fedora-packages.sh
bash tests/void-packages.sh
```

`--check` exits with status 3 when a refresh or pin-drift repair is available.
Network and parse failures use status 1 and name the failing package. Package
builds run after the resulting change lands on `unstable-dev`.

For Go or Cargo dependencies, add `%global ryoku_vendor go` or
`%global ryoku_vendor cargo`, plus an optional
`%global ryoku_vendor_dir path/inside/Source0`. Declare
`Source100: %{name}-%{version}-vendor.tar.gz`. Preparation checks `go.sum` or
`Cargo.lock`, resolves dependencies, and creates a deterministic archive whose
top directory is `vendor/`. Build with `-mod=vendor` for Go. Cargo specs extract
Source100, point `.cargo/config.toml` at `vendor/`, and build with
`--offline --locked`.

An executable `fetch/<name>.sh` runs before sources are validated. It receives:

```sh
RYOKU_FETCH_TREE=/path/to/staged/ryoku-version
RYOKU_FETCH_SOURCES=/path/to/this/packages/SOURCES
```

Upstream hooks write plain-file Sources into `RYOKU_FETCH_SOURCES` and verify
anything they fetch. A hook may write one RPM-safe version line to
`$RYOKU_FETCH_SOURCES/.version`; preparation uses it as the temporary spec
Version before expanding Source URLs, then removes the file. The checked-in
Release is unchanged.

Packages needed only while building belong in `../build-coprs.tsv`, not the
host-facing `../coprs.tsv`. Its tab-separated header and rows are:

```text
copr	includepkgs	why
owner/project	package-a package-b	reason for the build dependency
```

The build workflow renders each row as a restricted COPR repository before
`dnf builddep`. The file may be absent or contain only its header.

## Reusing published upstream RPMs

The publish workflow mirrors the current stable or testing repository before it
builds. After resolving a fetch hook's dynamic `.version`,
`prepare-srpms.sh` records each upstream binary identity and an input digest in
`upstream-rpms.tsv`. The digest covers the fully expanded spec and every Source
file included in the SRPM, including the generated vendor archive.
Generated dependency archives use fixed ownership, timestamps, ordering, and
gzip headers so rebuilding unchanged sources produces the same digest.

`build-rpm-repo.sh` publishes those digests as `upstream-inputs.tsv` and reuses
a mirrored upstream RPM only when its published manifest has the same digest
for the exact name, epoch, version, release, and architecture. Every candidate
must also verify with the Ryoku release key and pass a
`dnf5 install --assumeno` dependency solve in the current Fedora build
container. A missing or changed input digest, missing binary, untrusted
signature, or incompatible dependency rebuilds the whole upstream spec.

Ryoku-tree specs always rebuild because their source and release metadata follow
the current Ryoku commit. Reused RPM bytes are copied unchanged and are not
signed again. The build log lists reused upstream packages and packages built
in the current run.

## Repository build

Rebuild and assemble the signed repository with:

```sh
RYOKU_SRPM_IN=/tmp/ryoku-srpms \
RYOKU_RPM_OUT=/tmp/ryoku-rpm-repo \
RYOKU_RPM_SIGNING_KEY=EB6D3C0F55A7B3CABA6B2838847B274F025DD6E3 \
  fedora/packages/rpm/build-rpm-repo.sh
```

The output contains binary RPMs, repository metadata, its armored signature,
`upstream-inputs.tsv`, and `release.json`. SRPMs remain build artifacts and are
not published. Generated `-debuginfo` and `-debugsource` RPMs are not mirrored,
signed, or published. Assembly fails if a shipped RPM requires one of them.

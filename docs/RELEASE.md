# Release and CI

BatteryGuard uses **one** GitHub Actions workflow:
[`.github/workflows/ci.yml`](../.github/workflows/ci.yml). There are no
additional workflow files to drift out of sync.

## Triggers

| Trigger | Build installers | Attest | Publish release |
| --- | --- | --- | --- |
| Push to any branch | Yes | Yes | No |
| Push of a `v*` tag | Yes | Yes | Yes |
| Manual dispatch | Yes | Yes | No |

The concurrency group is per ref. A new branch push cancels the previous
branch run; a tag run is never cancelled by the concurrency rule.

## Version and tag rule

`portable/Cargo.toml` is the source of truth:

```toml
version = "0.1.0"
```

- Normal branch runs use `0.1.0-snapshot.<short-sha>` in installer filenames.
- A release tag must be exactly `v` plus the Cargo version. `v0.1.0` is valid
  for `0.1.0`; `v0.2.0` or `v0.1` fails before any build starts.
- The tag version is used in the release title, package metadata and asset
  names. No date or commit-derived version is used for a tagged release.

Release a version by bumping `portable/Cargo.toml`, updating `Cargo.lock` and
the documentation, committing to `main`, then creating and pushing the matching
tag:

```sh
git tag v0.1.0
git push origin v0.1.0
```

## Installer matrix

| Runner | Target | Package |
| --- | --- | --- |
| `windows-2025` | `x86_64-pc-windows-msvc` | `.msi` x64 |
| `windows-2025` | `i686-pc-windows-msvc` | `.msi` x86 |
| `windows-2025` | `aarch64-pc-windows-msvc` | `.msi` ARM64 |
| `ubuntu-24.04` | `x86_64-unknown-linux-musl` | `.deb`, `.rpm`, `.AppImage` x64 |
| `ubuntu-24.04-arm` | `aarch64-unknown-linux-musl` | `.deb`, `.rpm`, `.AppImage` ARM64 |
| `macos-15-intel` | `x86_64-apple-darwin` | `.pkg` Intel |
| `macos-15` | `aarch64-apple-darwin` | `.pkg` Apple silicon |

Linux binaries are statically linked against musl, so the packages do not
depend on the runner's glibc version. The Debian and RPM metadata therefore
does not add a libc dependency.

Tests run on every native job: Windows x64/x86, Linux x64/ARM64 and both macOS
architectures. Windows ARM64 is cross-compiled and packaged but cannot execute
on the x64 hosted runner. `RUSTFLAGS=-D warnings` makes Rust warnings fatal.
The Windows x64 job installs the MSI, verifies the tray, CLI, icon, locales and
both Start Menu shortcuts, then uninstalls it. Linux and macOS jobs install
their native package and run the installed `batteryguard --version`; the RPM
metadata is checked, while the DEB and PKG are actually installed.

## Signing

Every installer is covered by a **keyless GitHub build-provenance
attestation** created by `actions/attest-build-provenance`. The attestation is
signed by Sigstore/Fulcio using the workflow's OIDC identity and binds the
artifact digest to this repository, commit and workflow run. No long-lived
signing key is stored in the repository.

This is a cryptographic supply-chain signature; it is **not** Windows
Authenticode and it is **not** Apple notarization. The current workflow does
not have a Windows code-signing certificate or Apple Developer ID, so native
OS trust prompts and notarization are not claimed. Adding those requires
repository secrets and a deliberate release-hardening change.

Attestations are available from the workflow run and via GitHub's attestation
API; they are not uploaded as extra release assets.

## Published assets

The release job downloads all installer artifacts, rejects every unexpected
extension, and only then creates the GitHub Release. A release therefore
contains only:

- `BatteryGuard-<version>-windows-<arch>.msi`
- `BatteryGuard-<version>-linux-<arch>.deb`
- `BatteryGuard-<version>-linux-<arch>.rpm`
- `BatteryGuard-<version>-linux-<arch>.AppImage`
- `BatteryGuard-<version>-macos-<arch>.pkg`

There are no raw executables, ZIP files, symbol archives, debug builds,
screenshots or test data in a release. Branch runs upload the same installers
as short-lived Actions artifacts, but never create a GitHub Release.

## Packaging implementation

- Windows: WiX Toolset 5 builds a per-machine MSI with a stable UpgradeCode,
  major-upgrade handling, an uninstall entry and a system `PATH` entry. The
  payload includes the C# tray (`application.exe`), the Rust CLI
  (`batteryguard.exe`), the application icon, all 30 locale catalogs, an
  all-users Start Menu shortcut with `BatteryGuard.Tray`, and an uninstall
  shortcut. `generate-locales.ps1` creates the locale WiX components.
- Linux: `packaging/linux/build-linux.sh` creates the `.deb` with `dpkg-deb`,
  the `.rpm` with `rpmbuild`, and a portable AppImage with
  `appimagetool` 1.9.1.
- macOS: `packaging/macos/build-pkg.sh` creates a component `.pkg` that
  installs `/usr/local/bin/batteryguard`.

No packaging tool is run in the repository root on a normal local build; the
CI jobs use the platform tools installed on their hosted runner.

The current branch MSI payload is the C# Windows tray plus the Rust
`batteryguard` CLI. The Linux DEB/RPM/AppImage and macOS PKG payloads remain
the Rust CLI only. The published `v0.1.0` assets predate the tray MSI and are
CLI-only; the tray MSI will be included in the next version tag. The branch
run installs the x64 MSI but does not claim a clean-VM test.

## Verification boundaries

- The first hosted run (`42622500646`) exposed a crate-path bug and failed in
  `prepare`; `d34e2c4` fixed the Cargo manifest paths.
- `531167f` fixed the target directory used by both Unix packagers.
- `f1ce6cb` upgraded the actions to Node 24 releases, added a Linux GNU
  build-id and the CLI smoke test.
- Hosted run `42623422341` passed all seven packaging jobs, produced 11
  installers and contains no workflow warnings. The release job was correctly
  skipped on the branch.
- `784df66` added the tray MSI payload and Start Menu/uninstall shortcuts.
  `39f5578` corrected the WiX standard directory id to `ProgramMenuFolder`,
  and `abe26f5` limited the install smoke test to the native x64 MSI after
  cross-architecture installs failed with 1633 and the x86 payload resolved
  under `Program Files (x86)`.
- Hosted run `42629998330` passed all seven packaging jobs: x64 MSI
  install/uninstall and native DEB/PKG install-and-run checks succeeded. The
  branch artifacts contain the new Windows payload.
- Tag run `42624635716` passed every job and published
  [`v0.1.0`](https://github.com/Alaa91H/BatteryGuard/releases/tag/v0.1.0) with
  exactly 11 installer assets. The tag points to commit `449245b`; it remains
  CLI-only.
- Runtime results, run IDs and release URLs are recorded in
  [`SESSION_LOG.md`](SESSION_LOG.md) after each hosted run.
- A green workflow is the release gate. Do not create a tag if any native test
  or package step is failing.

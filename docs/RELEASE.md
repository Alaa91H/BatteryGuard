# Release and CI

BatteryGuard uses **one** GitHub Actions workflow:
[`.github/workflows/ci.yml`](../.github/workflows/ci.yml). There are no
additional workflow files to drift out of sync.

## Triggers

| Trigger | Build installers | Publish release |
| --- | --- | --- |
| Push to any branch | Yes | No |
| Push of a `v*` tag | Yes | Yes |
| Manual dispatch | Yes | No |

The concurrency group is per ref. A new branch push cancels the previous
branch run; a tag run is never cancelled by the concurrency rule.

## Version and tag rule

`portable/Cargo.toml` is the source of truth:

```toml
version = "0.3.0"
```

- Normal branch runs use `0.3.0-snapshot.<short-sha>` in installer filenames.
- A release tag must be exactly `v` plus the Cargo version. `v0.3.0` is valid
  for `0.3.0`; `v0.2.0` or `v0.1` fails before any build starts.
- The tag version is used in the release title, package metadata and asset
  names. No date or commit-derived version is used for a tagged release.

Release a version by bumping `portable/Cargo.toml`, updating `Cargo.lock` and
the documentation, committing to `main`, then creating and pushing the matching
tag:

```sh
git tag v0.3.0
git push origin v0.3.0
```

## Installer matrix

| Runner | Target | Package |
| --- | --- | --- |
| `windows-2025` | `x86_64-pc-windows-msvc` | `.exe` + `.msi` x64 |
| `windows-2025` | `i686-pc-windows-msvc` | `.exe` + `.msi` x86 |
| `windows-2025` | `aarch64-pc-windows-msvc` | `.exe` + `.msi` ARM64 |
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
The Windows x64 job also runs the hardware-independent C# suite (float policy,
controller profiles and safety gates, schedule conflicts, settings persistence,
notification identity, log rotation, icon rendering and adaptive layout). The Windows x64 job installs the MSI and
the EXE bootstrapper, verifies the tray, CLI, icon, locales and both Start Menu
shortcuts, then uninstalls both. It also installs the published `v0.1.0` MSI,
upgrades it with the new EXE, requires the old product to disappear and exactly
one visible Apps & Features entry to remain (the MSI is hidden behind the
bundle), then uninstalls. Linux and macOS jobs install their native package and
run the installed `batteryguard --version`; the RPM metadata is checked, while
the DEB and PKG are actually installed.

## Release build

The workflow builds the native packages, uploads them as GitHub Actions
artifacts, and a matching `v*` tag publishes those same files. Windows Smart
App Control may block the installers; the measured result is recorded in
[`PROJECT_STATUS.md`](PROJECT_STATUS.md).

## Published assets

The release job downloads all installer artifacts, rejects every unexpected
extension, and only then creates the GitHub Release. A release therefore
contains only:

- `BatteryGuard-<version>-windows-<arch>.exe` (Burn bootstrapper)
- `BatteryGuard-<version>-windows-<arch>.msi`
- `BatteryGuard-<version>-linux-<arch>.deb`
- `BatteryGuard-<version>-linux-<arch>.rpm`
- `BatteryGuard-<version>-linux-<arch>.AppImage`
- `BatteryGuard-<version>-macos-<arch>.pkg`

There are no raw application binaries, ZIP files, symbol archives, debug
builds, screenshots or test data in a release. The allowed `.exe` is the Burn
installer, not the tray or CLI itself. Branch runs upload the same installers
as short-lived Actions artifacts, but never create a GitHub Release.

## Packaging implementation

- Windows: WiX Toolset 5 builds a per-machine MSI with a stable UpgradeCode,
  same-version major-upgrade handling, an uninstall entry and a system `PATH`
  entry. The payload includes the C# tray (`application.exe`), the Rust CLI
  (`batteryguard.exe`), the application icon, all 30 locale catalogs, an
  all-users Start Menu shortcut with `BatteryGuard.Tray`, and an uninstall
  shortcut. `generate-locales.ps1` creates the locale WiX components.
- Windows EXE: `packaging/windows/Bundle.wxs` wraps that MSI in a WiX Burn
  bootstrapper with the application icon, version display, launch-after-install,
  per-machine scope and an Apps & Features uninstall entry. The bootstrapper
  uses `WixStandardBootstrapperApplication`; its Bal extension is pinned to
  5.0.2 in the Windows job.
- Linux: `packaging/linux/build-linux.sh` creates the `.deb` with `dpkg-deb`,
  the `.rpm` with `rpmbuild`, and a portable AppImage with
  `appimagetool` 1.9.1.
- macOS: `packaging/macos/build-pkg.sh` creates a component `.pkg` that
  installs `/usr/local/bin/batteryguard`.

No packaging tool is run in the repository root on a normal local build; the
CI jobs use the platform tools installed on their hosted runner.

The current branch MSI and EXE payload is the C# Windows tray plus the Rust
`batteryguard` CLI. The Linux DEB/RPM/AppImage and macOS PKG payloads remain
the Rust CLI only. The `v0.3.0` release includes the tray MSI and EXE; the earlier `v0.2.0` release also includes them, and `v0.1.0`
assets remain CLI-only. The branch run installs the x64 MSI and EXE and upgrades
the published `v0.1.0` MSI on a clean hosted runner, but it does not exercise
the interactive wizard or a physical clean VM.

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
- Hosted run `42632698346` added the Windows x64 C# suite and kept all seven
  packaging jobs green. This run verifies the release path only.

- Branch run `42652367294` passed all seven packaging jobs for Cargo `0.2.0`,
  and tag run `42653411073` passed every job and published
  [`v0.2.0`](https://github.com/Alaa91H/BatteryGuard/releases/tag/v0.2.0) with
  three Windows EXE bootstrappers, three MSIs, six Linux packages and two
  macOS PKGs. The artifacts are built by the same workflow.
- Local Smart App Control check (2026-11-09): Windows 11 Home 10.0.26300 with
  SAC enforcement (`VerifiedAndReputablePolicyState=1`) blocked the
  x64 EXE before installation with `An Application Control policy has blocked
  this file.` The existing `0.1.0` installation remained; no `0.2.0` upgrade
  occurred. This is a failure result for the published artifact.

- Hosted run `42638941970` passed all seven packaging jobs, built 14
  installers, and passed the x64 MSI/EXE install-uninstall checks plus the
  `v0.1.0` MSI → EXE upgrade test. The test confirmed the old product was gone,
  one visible Apps & Features entry remained and the MSI was a hidden
  `SystemComponent`, then uninstalled cleanly.
- Hosted run `42636451138` added the single-EXE Burn bootstrapper and passed
  the initial x64 MSI/EXE install-uninstall checks. It remains the first green
  run for the EXE; `42638941970` adds the upgrade result.
- Tag run `42624635716` passed every job and published
  [`v0.1.0`](https://github.com/Alaa91H/BatteryGuard/releases/tag/v0.1.0) with
  exactly 11 installer assets. The tag points to commit `449245b`; it remains
  CLI-only.
- Runtime results, run IDs and release URLs are recorded in
  [`SESSION_LOG.md`](SESSION_LOG.md) after each hosted run.
- A green workflow is the release gate. Do not create a tag if any native test
  or package step is failing.

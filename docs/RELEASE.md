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
version = "0.2.0"
```

- Normal branch runs use `0.2.0-snapshot.<short-sha>` in installer filenames.
- A release tag must be exactly `v` plus the Cargo version. `v0.2.0` is valid
  for `0.2.0`; `v0.1.0` or `v0.1` fails before any build starts.
- The tag version is used in the release title, package metadata and asset
  names. No date or commit-derived version is used for a tagged release.

Release a version by bumping `portable/Cargo.toml`, updating `Cargo.lock` and
the documentation, committing to `main`, then creating and pushing the matching
tag:

```sh
git tag v0.2.0
git push origin v0.2.0
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
schedule conflicts, settings persistence, notification identity, log rotation,
icon rendering and adaptive layout). The Windows x64 job installs the MSI and
the EXE bootstrapper, verifies the tray, CLI, icon, locales and both Start Menu
shortcuts, then uninstalls both. It also installs the published `v0.1.0` MSI,
upgrades it with the new EXE, requires the old product to disappear and exactly
one visible Apps & Features entry to remain (the MSI is hidden behind the
bundle), then uninstalls. Linux and macOS jobs install their native package and
run the installed `batteryguard --version`; the RPM metadata is checked, while
the DEB and PKG are actually installed.

## Native signing (optional)

Every installer is covered by a **keyless GitHub build-provenance
attestation** created by `actions/attest-build-provenance`. The attestation is
signed by Sigstore/Fulcio using the workflow's OIDC identity and binds the
artifact digest to this repository, commit and workflow run. No long-lived
signing key is stored in the repository.

The Windows job supports two mutually exclusive Authenticode paths. With
neither configured it builds unsigned packages and emits a notice; it does not
claim an OS signature.

SignPath Foundation (free for this MIT-licensed public project):

- Apply at [signpath.org/apply](https://signpath.org/apply) and install the
  SignPath GitHub App.
- The workflow uses three signing requests: tray/CLI binaries, the MSI before
  the EXE is built, and the final EXE. The upstream WiX Burn engine is included
  unsigned. The returned binaries are verified with `signtool verify /pa /all`
  before they are packaged or published.
- Required repository secret: `SIGNPATH_API_TOKEN`.
- Required repository variables: `SIGNPATH_ORGANIZATION_ID`,
  `SIGNPATH_PROJECT_SLUG`, `SIGNPATH_SIGNING_POLICY_SLUG`,
  `SIGNPATH_ARTIFACT_CONFIGURATION_BINARIES`,
  `SIGNPATH_ARTIFACT_CONFIGURATION_MSI` and
  `SIGNPATH_ARTIFACT_CONFIGURATION_EXE`.
- The publisher is **SignPath Foundation**. The path is implemented but has not
  been exercised because there is no SignPath account, project or token in this
  repository. It is not valid to describe a build as signed until a request
  completes and verification passes.
- If all SignPath variables are set but `SIGNPATH_API_TOKEN` is missing, the
  Windows job fails before signing. If the variables are absent, the PFX path
  or the unsigned path is used.

Windows Authenticode PFX fallback:

- `WINDOWS_CERTIFICATE_BASE64` — base64 of the PFX; `WINDOWS_CERTIFICATE_PASSWORD` — PFX password.
- The tray and CLI are signed before the MSI is built, so their signatures are
  embedded in the package; the MSI is signed afterwards.
- The EXE bundle is signed in two stages: detach the Burn engine, sign it,
  reattach it, then sign the whole bundle. This covers both the cached engine
  and the outer installer.
- `signtool verify /pa /all` must pass for the two executables, the MSI, the
  Burn engine and the EXE bundle.
- SignPath and the PFX path are mutually exclusive: when all SignPath variables
  are set, the PFX signing steps are skipped.

macOS Developer ID and notarization:

- `MACOS_CERTIFICATE_P12_BASE64`, `MACOS_CERTIFICATE_PASSWORD` and
  `MACOS_KEYCHAIN_PASSWORD` import the certificate into a temporary keychain.
- `MACOS_APPLICATION_IDENTITY` and `MACOS_INSTALLER_IDENTITY` are the
  Developer ID Application and Developer ID Installer identities.
- `MACOS_NOTARY_APPLE_ID`, `MACOS_NOTARY_TEAM_ID` and
  `MACOS_NOTARY_PASSWORD` are the Apple ID, team ID and app-specific password
  used by `xcrun notarytool`.
- The binary is signed with the hardened runtime, the PKG with `productsign`,
  then submitted, stapled and checked with `xcrun stapler` and
  `pkgutil --check-signature`.

Neither a SignPath project nor certificate secrets are configured in this
repository, so the native signing paths are implemented but have not been
exercised by the current green hosted run. Do not claim a signed artifact until
a real signing request completes and those verification commands pass.

This is a cryptographic supply-chain signature; it is **not** Windows
Authenticode and it is **not** Apple notarization. Attestations are available
from the workflow run and via GitHub's attestation API; they are not uploaded
as extra release assets.

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
the Rust CLI only. The `v0.2.0` release includes the tray MSI and EXE; the earlier `v0.1.0`
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
  packaging jobs green. The optional signing steps were skipped (no secrets),
  so this run verifies the unsigned path only.
- Hosted run `42647767077` passed all seven packaging jobs with the current
  three-request SignPath configuration absent. Every SignPath step was skipped,
  the PFX steps had no certificate, and the Windows x64 MSI/EXE
  install-uninstall and `v0.1.0` upgrade checks passed. This validates the
  no-secret fallback, not a signed artifact.
- Branch run `42652367294` passed all seven packaging jobs for Cargo `0.2.0`,
  and tag run `42653411073` passed every job and published
  [`v0.2.0`](https://github.com/Alaa91H/BatteryGuard/releases/tag/v0.2.0) with
  three Windows EXE bootstrappers, three MSIs, six Linux packages and two
  macOS PKGs. The artifacts are unsigned because SignPath is not configured.
- Local Smart App Control check (2026-11-09): Windows 11 Home 10.0.26300 with
  SAC enforcement (`VerifiedAndReputablePolicyState=1`) blocked the unsigned
  x64 EXE before installation with `An Application Control policy has blocked
  this file.` The existing `0.1.0` installation remained; no `0.2.0` upgrade
  occurred. This is a failure result for the unsigned artifact, not a signing
  test.
- Hosted run `42642577968` passed all seven packaging jobs with the optional
  SignPath configuration absent. The SignPath steps were skipped, the PFX steps
  had no certificate, and the unsigned installers were built, installed,
  upgraded and removed successfully. This validates the no-secret fallback,
  not a signed artifact.
- Hosted run `42638941970` passed all seven packaging jobs, built 14
  installers, and passed the x64 MSI/EXE install-uninstall checks plus the
  `v0.1.0` MSI → EXE upgrade test. The test confirmed the old product was gone,
  one visible Apps & Features entry remained and the MSI was a hidden
  `SystemComponent`, then uninstalled cleanly. Signing steps were skipped
  because no certificates are set.
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

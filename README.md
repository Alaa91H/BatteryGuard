# Workspace

[![Build, attest and release](https://github.com/Alaa91H/BatteryGuard/actions/workflows/ci.yml/badge.svg)](https://github.com/Alaa91H/BatteryGuard/actions/workflows/ci.yml)

This workspace contains three areas:

| Project | Location | Purpose |
| --- | --- | --- |
| BatteryGuard | `battery/` | Native Win32 tray application for HP notebook charge control and cross-brand battery monitoring. |
| BatteryGuard portable core | `portable/` | Dependency-free Rust read-only battery core for Windows, Linux and macOS, with a CLI and parser tests. |
| WSL provisioning | `windows/`, `linux/`, `.wslconfig`, `docs/production.md` | Scripts and notes for a local WSL2 development environment. |

The WSL project is independent. The portable Rust core is a separate implementation that does not replace or link into the C# tray yet. The WSL documentation that used to live in this file is preserved at [`docs/wsl/README.md`](docs/wsl/README.md).

## BatteryGuard at a glance

BatteryGuard is a small .NET Framework 4.x tray application. On supported HP notebooks it applies a charge ceiling and resume point through the BIOS WMI interface, supports scheduled charge windows and float mode. Float is latched only after the measured charge reaches the configured limit; charging below the limit is never stopped for float mode.

On other brands the app uses a read-only controller: it monitors percentage, health, capacity, cycles and temperature, sends notifications and writes the activity log, while the tray and Settings explicitly show **Monitoring only**. See [`docs/DEVICE_SUPPORT.md`](docs/DEVICE_SUPPORT.md).

The interface ships in **30 languages**. English is the source language and the fallback. The default setting is **Automatic**, which follows the Windows display language and falls back to English when the language is unsupported. Arabic, Urdu, Persian and Hebrew automatically use right-to-left layout.

The tray tooltip and the Settings battery card show the current pack voltage and charge/discharge power, for example `11.8 V · 0.0 W`, when WMI exposes those readings. Notifications use a `BatteryGuard.Tray` AppUserModelID and a matching Start Menu shortcut, so Windows labels them **BatteryGuard** instead of the hosting PowerShell process.

See [`battery/README.md`](battery/README.md) for the application guide and [`docs/LOCALIZATION.md`](docs/LOCALIZATION.md) for the language architecture.

## Layout

```text
battery/
  src/                 C# application and localization runtime
  resources/           application manifest and icon
  locales/             30 JSON catalogs keyed by English source strings
  scripts/             build, start, restart, CLI and hardware probes
  tests/               PowerShell regression and hardware checks
  application.exe      build output
  settings.json        charge policy
  interface.ini        language, direction, notifications and icon options
  theme.ini            light / dark / auto
  capacity.ini         cached design capacity
  application.log      activity log
portable/
  src/                 Rust core, charge policy and platform backends
  scripts/             rustc build/test and cross-target checks
  README.md            portable core guide
  PLATFORMS.md         OS, architecture and packaging matrix
packaging/
  windows/Product.wxs  WiX MSI definition
  windows/Bundle.wxs  WiX Burn single-EXE bootstrapper
  windows/generate-locales.ps1  WiX locale component generator
  linux/               DEB, RPM, AppImage and desktop assets
  macos/build-pkg.sh   macOS installer builder
.github/workflows/
  ci.yml               the single build, attest and release workflow
docs/
  ARCHITECTURE.md
  DECISIONS.md
  DEVICE_SUPPORT.md
  LOCALIZATION.md
  PROJECT_STATUS.md
  ROADMAP.md
  SESSION_LOG.md
  wsl/                 preserved WSL documentation
tools/                 localization/catalog maintenance utilities
CHANGELOG.md
AGENTS.md
```

## Quick start

Build the tray executable:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File battery/scripts/build.ps1
```

Start the tray application (it requests elevation because HP's WMI provider rejects non-admin access):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File battery/scripts/start.ps1
```

Type-check the portable Rust core for Windows, Linux and macOS targets:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File portable/scripts/check-targets.ps1
```

## Installers and releases

GitHub Actions builds native installers for all supported systems:

| Platform | Formats |
| --- | --- |
| Windows x86, x64, ARM64 | `.exe`, `.msi` |
| Linux x64, ARM64 | `.deb`, `.rpm`, `.AppImage` |
| macOS Intel, Apple silicon | `.pkg` |

The latest release is [`v0.2.0`](https://github.com/Alaa91H/BatteryGuard/releases/tag/v0.2.0), with all 14 installers attached. The Windows x86/x64/ARM64 assets install the C# tray and the Rust CLI: `application.exe`, `batteryguard.exe`, the 30 locale catalogs, an all-users Start Menu shortcut carrying `BatteryGuard.Tray`, and an uninstall shortcut. The MSI and the per-machine **single-EXE bootstrapper** use the standard WiX installer UI, show the version, offer launch after install and unregister through Apps & Features. Linux DEB/RPM/AppImage and macOS PKG still bundle the CLI only. The earlier `v0.1.0` release remains CLI-only.

The Windows x64 job runs the hardware-independent C# suite before packaging, then installs and removes both the MSI and the EXE bootstrapper.
Every branch build also creates a keyless Sigstore build-provenance attestation
and keeps the installers as workflow artifacts. Windows Authenticode can use
the free [SignPath Foundation](docs/SIGNPATH.md) path for this MIT-licensed
public project or the repository PFX path; macOS Developer ID/notarization uses
the documented certificate secrets. Without either configuration the packages
remain unsigned. A GitHub Release is created only from a matching `v*` tag;
branch builds never publish. See [`docs/RELEASE.md`](docs/RELEASE.md) for the
version rule, signatures and asset policy.

Run the hardware-independent regression checks:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File battery/tests/Test-FloatLogic.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File battery/tests/Test-ScheduleConflict.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File battery/tests/Test-UiPolish.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File battery/tests/Test-Settings.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File battery/tests/Test-BatteryInfo.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File battery/tests/Test-AppIdentity.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File battery/tests/Test-LogRotation.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File battery/tests/Test-Icons.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File battery/tests/Test-Layout.ps1
```

## Status

- Build: `battery/application.exe`, 99,328 bytes at the last local build.
- Release CI: [`.github/workflows/ci.yml`](.github/workflows/ci.yml) is the only workflow. Hosted run [42647767077](https://github.com/Alaa91H/BatteryGuard/actions/runs/42647767077) passed all seven native packaging jobs and produced the installer artifacts. The Windows x64 job ran the eight-test C# suite; the x64 EXE and MSI install/uninstall, a clean-runner upgrade from the published `v0.1.0` MSI, and native DEB/PKG install-and-run checks passed. The installer wizard itself was not visually tested: this host has no Windows Sandbox/VM and Application Control blocks the EXE, while hosted runners are non-interactive. The SignPath signing path was skipped because no SignPath account or token is configured. Branch builds attest and upload artifacts; a matching `v*` tag is the only path that publishes a GitHub Release. The tag release [`v0.1.0`](https://github.com/Alaa91H/BatteryGuard/releases/tag/v0.1.0) remains the earlier CLI-only release.
- Portable core: the read-only Rust library, CLI and test harness type-check on 12 Windows/Linux/macOS targets. Run 42647767077 linked, tested and ran `batteryguard --version` on six native runners, and installed/ran the DEB and PKG packages. No linked binary or test run was possible locally because the MSVC linker is absent and Application Control blocks Cargo and the available GNU/lld linkers. Linux/macOS widgets and BIOS charger wattage remain later work; optional native signing hooks exist but are unconfigured.
- Float policy: 13/13 decision cases pass; float starts only at the limit and holds until the resume point.
- Electrical readings: the tooltip, tray menu, status balloon and Settings card show pack voltage and charge/discharge power; the real reading was `11.8 V · 0.0 W` while the charger held the battery idle.
- Notification identity: the Start Menu shortcut and `System.AppUserModel.ID` were verified as `BatteryGuard.Tray`; the banner label itself was not captured because browser notifications occupied the screen during the check. No reliable automated banner-label test is included yet.
- Localization: 30 catalogs, 151 keys each, placeholder validation clean.
- Regression checks: float logic, schedule conflicts, UI polish, settings, battery readings, notification identity, log rotation, icon rendering and adaptive layout passed.
- Window sizing: Settings 780×1000 design size (minimum 620×480; content scrolls and the Save/Cancel/Test footer stays pinned), schedule window 500×400 (minimum 440×320; content scrolls and the buttons stay pinned), activity log 760×560 (minimum 520×360; the action bar wraps). All are DPI-aware and clamp to the working area.
- Device support: HP charge control; every other vendor monitored with an explicit **Monitoring only** state.
- Translation review: catalogs are machine-generated from the curated English source with targeted glossary overrides. Native-speaker review is still recommended before treating every wording as final.
- The Settings window was re-inspected in Arabic light/dark and English dark with the electrical value; the schedule and log windows retain their Arabic-light layout captures. The native tray menu and the final notification banner could not be captured, and 125%/150% DPI were not exercised.

## Code signing policy

BatteryGuard's [code signing policy](docs/CODE_SIGNING_POLICY.md) defines the
Windows artifact scope, team roles, signing approval and privacy statement.
Signing is not active yet: no SignPath project or token is configured. Free
code signing is provided by [SignPath.io](https://about.signpath.io/),
certificate by [SignPath Foundation](https://signpath.org/).

## Documentation

- [`battery/README.md`](battery/README.md) — build, run, configure and test the app.
- [`portable/README.md`](portable/README.md) — portable Rust core, CLI and build/test notes.
- [`portable/PLATFORMS.md`](portable/PLATFORMS.md) — architecture, distribution and packaging support matrix.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — process model, components and data flow.
- [`docs/RELEASE.md`](docs/RELEASE.md) — CI matrix, tag/version rule, attestation and release policy.
- [`docs/DEVICE_SUPPORT.md`](docs/DEVICE_SUPPORT.md) — supported devices and the monitoring-only boundary.
- [`docs/LOCALIZATION.md`](docs/LOCALIZATION.md) — language resolution, catalogs and maintenance.
- [`docs/PROJECT_STATUS.md`](docs/PROJECT_STATUS.md) — current state and known gaps.
- [`docs/SIGNPATH.md`](docs/SIGNPATH.md) — free SignPath Foundation signing setup for the MIT-licensed project.
- [`docs/CODE_SIGNING_POLICY.md`](docs/CODE_SIGNING_POLICY.md) — artifact scope, roles, approval and privacy policy.
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — planned work.
- [`docs/DECISIONS.md`](docs/DECISIONS.md) — architecture decisions.
- [`docs/SESSION_LOG.md`](docs/SESSION_LOG.md) — work log.
- [`CHANGELOG.md`](CHANGELOG.md) — changes in English.
- [`AGENTS.md`](AGENTS.md) — repository instructions for coding agents.

## License

BatteryGuard is released under the [MIT License](LICENSE). The MIT license is
required for the project's SignPath Foundation application; it does not change
the local-only, no-network behavior described above.

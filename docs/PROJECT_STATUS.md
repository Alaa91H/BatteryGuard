# Project status

**Date:** 2026-11-10
**Application:** BatteryGuard tray monitor
**Build:** `battery/application.exe` — 120,832 bytes
**CI:** single tag-gated workflow; branch run `42652367294` and tag run `42653411073` green with all seven packaging jobs, the C# suite, the Windows tray MSI and EXE, and a clean-runner upgrade from the published `v0.1.0` MSI; the published `v0.2.0` release has 14 installers, including 3 EXE and 3 MSI

## Completed

- Native Win32 tray application with owner-drawn menus and WinForms settings, schedule, log and rule dialogs.
- **Charge policy split into `ChargePolicy`.** Float mode activates only after the measured charge reaches the ceiling; charging below the limit is never inhibited by float. The latch holds until the resume point, then charging restarts.
- **F.28 firmware map and read-only probe.** A static parse of the official HP F.28 `SetupUtility` module (SoftPaq `sp155605`) recovered 237 settings in nine HII form packages: 58 sit in forms no menu references and 204 carry a `SuppressIf`, `DisableIf` or `GrayOutIf` condition. `docs/DEVICE_SUPPORT.md` documents the SystemConfig, H19SetupUtilityConfig and H19SetupVariable stores, their offsets and visibility gates. `battery/scripts/probe-bios-settings.ps1` is a read-only runtime probe, and `ChargePolicy` now states that the effective ceiling is the lower of the app ceiling and the firmware Battery Care Function.
- **Device controller foundation:** `DeviceFingerprint`, `DeviceProfileCatalog`, `ControllerCapabilities`, `IChargeController`, `WriteGuard`, `IControllerProvider` and `IWmiGateway`; `HpBiosWmiGateway` remains the only real write transport. HP is the only verified writer. Acer, Dell and Lenovo are candidate profiles and remain read-only. The tray omits generic presets for non-`AutoInhibit` capabilities, and Settings uses a capability-only card for fixed/start-stop profiles. `Test-ControllerFoundation` covers live fingerprint fields, catalog/interface/BIOS matching, the numeric `ApplyLimit` gate, unplugged inhibition, access denial, missing-provider fallback, empty/unexpected/mismatched read-back, rollback, the low-level mode allow-list, generic monitoring requests and forced-discharge rejection without hardware.
- **Voltage and power readout.** The tray tooltip, menu, status balloon and Settings battery card show the current pack voltage and charge/discharge power, for example `11.8 V · 0.0 W`. Unavailable values are omitted; zero watts is shown when voltage confirms a battery reading. This is battery-pack power, not AC adapter input wattage.
- **Windows tray MSI and EXE.** The branch MSI installs `application.exe`, `batteryguard.exe`, the icon and all 30 locale catalogs under `Program Files\BatteryGuard`; the EXE is a Burn bootstrapper around the same MSI with a standard wizard, icon, version, launch-after-install and Apps & Features entry. Both create an all-users Start Menu shortcut with `BatteryGuard.Tray` and an **Uninstall BatteryGuard** shortcut. The x64 install/uninstall paths for both are tested in CI; x86 and ARM64 are built but not cross-installed on the x64 runner.
- **C# CI gate.** The Windows x64 job runs thirteen C# checks before packaging: `Test-FloatLogic`, `Test-ControllerFoundation`, `Test-ScheduleConflict`, `Test-UiPolish`, `Test-Settings`, `Test-AppIdentity`, `Test-LogRotation`, `Test-Icons`, `Test-Layout`, `Test-TrayMenu`, `Test-UI`, `Test-Theme` and `Test-TrayHost`. The last three start the real tray with `BATTERYGUARD_TEST_CONTROLLER=monitoring`, so no provider, WMI gateway or `WriteGuard` exists. The local clean-build pass also runs `Test-BatteryInfo`, `Test-LanguageAuto`, `Test-ThemeLive` and `VisualCapture`; none touched hardware. The UI gate covers monitoring-only and a synthetic fixed-80% writable profile. Hosted run `42700624192` on commit `02e44bf` passed all jobs, including the Windows x64 thirteen-check suite.
- Charge ceiling, resume point, float mode, scheduled time windows, overlap detection and conflict banners.
- Battery health, capacity, cycle, temperature and remaining-time display.
- System notifications, test notification, log viewer, export and 1 MiB rotation.
- **Stable notification identity.** `BatteryGuard.Tray` is set as the process AUMID and mirrored in `%APPDATA%\Microsoft\Windows\Start Menu\Programs\BatteryGuard.lnk`, so Windows labels notifications **BatteryGuard** instead of the PowerShell host.
- Theme support (auto/light/dark) and high-contrast tray icon variants.
- Adaptive, DPI-aware dialogs with working-area clamping and scrolling: Settings 980×620 with a two-column layout at 900 px and wider, a single scrollable column below 900 px and a pinned action footer; schedule window 500×350 with a 56 px pinned button bar; activity log 760×560 with a wrapping action bar. `Test-Layout` covers all three at 100%, 125% and 150% in English and Arabic with 222 checks, zero failures and no horizontal scrollbar; 150% Settings content scrolls vertically.
- **Responsive Settings:** Language sits above Appearance, the appearance selector persists to `theme.ini`, and the interface card shows the installed version from assembly metadata with a `0.3.0` fallback.
- **30 locale catalogs**, each with 152 keys; placeholder validation reports 0 mismatches.
- **Focused source modules:** `Program`, `TrayApp`, `Engine`, `Controllers`, `Wmi`, `AppIdentity`, `Config`, `Theme`, `Dialogs` and `Native`; build, launcher and tests compile every `src/*.cs` file.
- **Visual/RTL pass:** The actual-window captures were regenerated in English/Arabic and light/dark; Settings shows all cards, the full footer and the visible RTL ComboBoxes, and the schedule window keeps its Save/Cancel buttons fully inside the frame.
- **Translation terminology pass:** charge, health and schedule labels corrected across the 30 catalogs, including money mistranslations and untranslated values.
- English source/fallback; `language=auto` default; Windows display-language detection; Arabic, Urdu, Persian and Hebrew RTL.
- Language selector in Settings; `language` persisted in `interface.ini`.
- Neutral project layout: `src/`, `resources/`, `locales/`, `scripts/`, `tests/`; neutral data names (`settings.json`, `interface.ini`, `theme.ini`, `capacity.ini`, `application.log`).
- Startup migration from the old product-named data files.
- English project documentation, device support, architecture, decisions, roadmap, localization guide and changelog.
- Elevated restart after the electrical/identity change: process 18616; `controller: HP HP ENVY x360 Convertible 13-ay0xxx (charge control)`, `tray icon added=True`, `tray started`, and the tick line contains `v=11780mV p=0mW`.

## Verification

Passed across the latest local sessions (2026-11-09 and 2026-11-10):

| Check | Result |
| --- | --- |
| `Test-FloatLogic.ps1` | 13/13 OK |
| `Test-ControllerFoundation.ps1` | 71 checks: live fingerprint, catalog order, interface/BIOS matching, fixed/start-stop limit gate, unplugged, access-denied, missing-class fallback, empty/unexpected/mismatch read-back, rollback, low-level allow-list and force-discharge gates OK (simulated WMI) |
| `Test-TrayMenu.ps1` | 32 checks: charge-time placement and language menu OK; injected Acer candidate reports **Monitoring only** in the menu and Settings; synthetic fixed-80% and start-stop 50–100% profiles get a capability-only card with no generic slider |
| `Test-UI.ps1` | `showCeiling` on/off in the injected monitoring-only controller; `cap=monitoring`; no charge-write line; `interface.ini` restored |
| `Test-Theme.ps1` | dark/light/auto in the injected monitoring-only controller; `cap=monitoring`; no charge-write line; `theme.ini` restored |
| `Test-TrayHost.ps1` | Elevated; hosted `--status`, 30 s host sample, screenshots and logon-task install/remove in the injected monitoring-only controller; no charge-write line |
| `Test-ScheduleConflict.ps1` | 6/6 OK |
| `Test-UiPolish.ps1` | 11/11 OK |
| `Test-LanguageAuto.ps1` | `language=auto` follows the Windows UI language; process culture does not override it |
| `Test-ThemeLive.ps1` | Windows theme registry flip/restore only; original values restored |
| `Test-Settings.ps1` | Save, appearance index, installed version (`0.3.0`), schedule conflict guard and restore OK |
| `Test-BatteryInfo.ps1` | Real readings, electrical formatting (`11.8 V · 0.0 W`, `11.8 V · 6.5 W`) and arithmetic OK |
| `Test-AppIdentity.ps1` | Start Menu shortcut, AUMID, target, arguments and description OK |
| `Test-LogRotation.ps1` | Main log and previous log rotation OK |
| `Test-Icons.ps1` | Contact sheet rendered OK |
| `Test-Layout.ps1` | Settings 980×620/780×600/620×480/560×420, schedule 500×350/440×350/380×350 and log 760×560/520×360/440×300 OK; plus 100%/125%/150% in English/Arabic: 222 OK, 0 FAIL, every nested control inside its parent, no horizontal scrollbar; 150% Settings uses vertical scrolling |
| `VisualCapture.ps1` | 12 actual-window images in English/Arabic and light/dark; Settings English/Arabic light/dark, schedule English light and log Arabic light inspected |
| `build.ps1` | csc exit 0; `application.exe` 120,832 bytes |
| Local full suite (2026-11-09 audit) | 16 hardware-free tests exit 0; elevated `Test-TrayHost` exit 0; 71 controller checks and 32 menu checks; no charge-write line; last certified read `mode=Auto` at 22:37:50; no tray process or logon task left; `git diff --check` clean |
| Local UI suite (2026-11-10) | 14 hardware-free tests exit 0; `Test-ThemeLive` exit 0; `VisualCapture` exit 0; `Test-UI` and `Test-Theme` passed in monitoring-only mode after stale PID 2908 was stopped; no charge-write line; no tray or mutex left; `Test-TrayHost` not rerun. Latest DPI run: build exit 0 (`120,832` bytes), `Test-Layout` 222 OK/0 FAIL, `Test-Settings`, `Test-Theme`, `Test-UI` and `VisualCapture` exit 0, no tray process left |
| GitHub Actions `42623422341` | All 7 packaging jobs succeeded; 11 installers; Rust/CLI smoke tests passed; no Node/RPM warnings |
| GitHub Actions `42624635716` | Tag run succeeded; GitHub Release `v0.1.0` published with exactly 11 installer assets |
| GitHub Actions `42629998330` | All 7 packaging jobs succeeded; 11 installers; Windows x64 MSI install/uninstall, DEB install/run and PKG install/run checks passed |
| GitHub Actions `42632698346` | All 7 packaging jobs succeeded; Windows x64 C# suite, x64 MSI install/uninstall, DEB install/run and PKG install/run checks passed |
| GitHub Actions `42636451138` | All 7 packaging jobs succeeded; 14 installers; Windows x64 C# suite, x64 MSI and EXE install/uninstall, DEB install/run and PKG install/run checks passed |
| GitHub Actions `42638941970` | All 7 packaging jobs succeeded; 14 installers; x64 MSI and EXE install/uninstall plus the published `v0.1.0` → EXE upgrade passed with one visible Apps & Features entry and a clean uninstall |
| GitHub Actions `42652367294` | Branch run for `0.2.0` succeeded; all 7 packaging jobs; 14 installers; x64 MSI/EXE and `v0.1.0` upgrade checks passed |
| GitHub Actions `42653411073` | Tag run succeeded; `v0.2.0` published with 14 assets (3 EXE, 3 MSI, 6 Linux packages, 2 PKG) |
| GitHub Actions `42700624192` | Branch run for the controller foundation and injected test mode succeeded; all jobs green, including the Windows x64 thirteen-test suite |
| Local SAC test (2026-11-09) | Windows 11 Home 10.0.26300 with SAC enforcement blocked the `v0.2.0` x64 EXE at launch; no install or upgrade occurred; existing `0.1.0` remained |

### Injected-mode tray tests

`BATTERYGUARD_TEST_CONTROLLER=monitoring` makes `BatteryControllerFactory`
return `GenericBatteryController` before any provider, WMI gateway or
`WriteGuard` is constructed. The tray logs `test controller: monitoring-only`
and `cap=monitoring`; every charge request returns `Unsupported`. This is a
test-only fail-closed path, not a vendor writer.

On 2026-11-09 the three tests ran in that mode and passed: `Test-UI`,
`Test-Theme` and `Test-TrayHost`. A certified read-only HP status before the
set reported `mode=Auto`; the status after each test also reported `mode=Auto`
(21:59:15, 21:59:45, 22:00:44 and 22:01:46). The log contained no
`charge mode set`, `action=auto|inhibit`, `inhibit write` or `auto write` line.
`TRAY_LEFT=0` and the BatteryGuardTray logon task was absent after
`Test-TrayHost` removed it.

`Test-UI` and `Test-Theme` run unelevated. `Test-TrayHost` needs an elevated
shell for its logon-task install/remove check and runs its 30 s host sample and
screenshots in the same injected mode. They are upstream of the write-capable
hardware checks, not a substitute for them.

An earlier UI/Theme attempt, before the test controller existed, left an older
tray process alive after the harness lost track of it. When the original
`Longevity 60` settings were restored, that process reloaded them and wrote
`Inhibit` at 21:34:38. The tray (PID 2424) was stopped and the verified HP
`Auto` path restored charging at 21:39:03 with firmware read-back `Auto`. That
incident is why the injected test controller is now mandatory for these tests.

The real charge-writing checks remain intentionally unrun: `Test-Tray`,
`Test-FloatMode` and `verify.ps1`. They need hardware writes and are not part
of the safe suite.

### F.28 firmware analysis (2026-11-09)

- Static IFR parse: 9 form packages, 237 settings, 58 in unreachable forms, 204 with a visibility condition, and 144 with an English prompt. The remaining 93 are internal variables with no UI string.
- `build.ps1`: csc exit 0; `application.exe` 117,248 bytes after the controller foundation, limit gate and test-mode injection.
- `Test-FloatLogic.ps1`: 13/13 OK.
- `probe-bios-settings.ps1` without elevation: exits 2 with the elevation message.
- `probe-bios-settings.ps1` elevated and read-only: `SeSystemEnvironmentPrivilege` was enabled, but all four documented names (`SystemConfig`, `H19SetupUtilityConfig`, `H19SetupVariable` and `AdvanceConfig`) returned Win32 203 (`ERROR_ENVVAR_NOT_FOUND`). The IFR store names are internal and are not exposed as runtime EFI variables, so no setup value could be read. No firmware write was attempted.

Locale inventory: 30 JSON files, 152 keys in each file including the `Monitoring only` and `Installed version {0}` keys; no missing keys and no placeholder mismatches.

The Settings reflection test reports `980×620` client size at 100%, with a 60 px pinned footer and a 554 px root. `Test-Layout` now also builds Settings, schedule and log at 125% and 150% in English and Arabic with scaled bounds and fonts: 222 checks, zero failures, every nested control inside its parent, no horizontal scrollbar; at 150% the taller Settings root scrolls vertically. The language selector remains above Appearance and the installed version remains visible at all three factors.

## Published v0.1.0 installer checks

- **Windows (real machine):** an existing CLI-only `0.1.0` installation was
  found at `C:\Program Files\BatteryGuard\batteryguard.exe` (303,104 bytes).
  The x64 MSI SHA-256 is
  `B9F46ECD9A80452EECE2E2FD81F0D1C5F4DE28D7123CA4F0444BA206EEA325E5`;
  Running the installed CLI is
  blocked by Application Control, so no successful runtime result was obtained.
  The existing installation was left in place; no clean install/uninstall was
  performed.
- **Linux:** the x64 DEB (SHA-256
  `34FD580A9A6A90007152C47C5F2B09DFA6DAC9F5AA4326A132749571F490A371`) was
  installed in WSL2 Ubuntu 24.04 as root, printed
  `BatteryGuard portable core 0.1.0`, and was removed; the package and
  `/usr/bin/batteryguard` were absent afterwards. This is a real Linux
  kernel/userspace, not a physical Linux device or battery.
- **macOS:** no macOS host was available; the PKG was not installed or run.

## Published v0.2.0 release

- Release: [`v0.2.0`](https://github.com/Alaa91H/BatteryGuard/releases/tag/v0.2.0),
  published 2026-11-09 from tag `v0.2.0` (commit `9e0bf24`) by run
  `42653411073`.
- Assets: 14 — three Windows EXE bootstrappers, three Windows MSIs, three
  x64 Linux packages, three ARM64 Linux packages and two macOS PKGs. The
  Windows payload is the C# tray plus the Rust CLI; Linux and macOS remain
  CLI-only.
- CI ran the quiet x64 MSI/EXE install, uninstall and `v0.1.0` upgrade checks;
  the interactive wizard was not visually tested.
- **Smart App Control:** a local Windows 11 Home 10.0.26300 test with SAC
  enforcement (`VerifiedAndReputablePolicyState=1`) blocked the x64
  EXE at launch (`An Application Control policy has blocked this file.`). No
  `0.2.0` installation or upgrade occurred; the existing `0.1.0` installation
  and Apps & Features entries remained.

## Portable core (phase 1)

- `portable/src/model.rs`, `format.rs` and `policy.rs` implement the shared battery model, electrical/duration formatting and the 13-case charge/float policy.
- `portable/src/platform/{windows,linux,macos}.rs` provide read-only providers: PowerShell/WMI, `power_supply` sysfs and `pmset -g batt`.
- `portable/src/main.rs` provides a text/JSON/watch CLI; `Cargo.toml` and `rustc` build/test scripts are included.
- `portable/scripts/check-targets.ps1` type-checks the library, test harness and CLI for 12 targets: x86/x64/ARM64 Windows, x86/x64/ARMv7/ARM64 Linux and Intel/Apple-silicon macOS.
- The check passed 12/12. It uses `--emit=metadata`, so it validates conditional compilation and types but does not link or execute.
- **Hosted verification:** GitHub Actions run `42647767077` linked and tested the Rust core on Windows x64/x86, Linux x64/ARM64 and macOS Intel/Apple silicon, ran the C# suite on Windows x64, built the Windows MSI and EXE matrix, Linux DEB/RPM/AppImage packages and macOS PKG files, installed the DEB and PKG and ran `batteryguard --version`, installed/uninstalled both the x64 MSI and EXE with the C# tray payload, and upgraded the published `v0.1.0` MSI with the new EXE. The upgrade check confirmed the old product disappeared, exactly one visible Apps & Features entry remained, and uninstall left no BatteryGuard product. The CLI printed `BatteryGuard portable core 0.1.0` on every runnable target.
- **Not verified locally:** no linked `batteryguard` executable, no executed Rust tests and no local Linux/macOS runtime. This host has no MSVC linker; Application Control blocks Cargo, GNU rustc and the available lld/GNU linkers.
- **Not included:** Linux/macOS widgets and cross-platform charge control.

## Release CI

- `.github/workflows/ci.yml` is the only workflow. It validates the Cargo version, builds the full matrix and uploads branch artifacts.
- The release job is skipped unless the ref is `refs/tags/v<Cargo version>`; it filters assets to `.exe`, `.msi`, `.deb`, `.rpm`, `.AppImage` and `.pkg`.
- Branch run `42629998330` covered all 7 native packaging jobs and produced 11 installers. Its x64 MSI passed install, payload, Start Menu/uninstall-shortcut and uninstall checks; Linux DEB and macOS PKG install-and-run checks passed.
- Branch run `42632698346` added the eight-test C# suite and kept all seven packaging jobs green, including the x64 MSI and native package checks.
- Branch run `42638941970` added the clean-runner `v0.1.0` → EXE upgrade test and produced 14 installers. The x64 job passed MSI/EXE install-uninstall and the upgrade, including one visible Apps & Features entry and a clean uninstall. Earlier runs exposed duplicate bundle/MSI registration, missing Cargo paths (`42622500646`), Unix packaging paths, the invalid `CommonProgramsFolder` WiX id and cross-architecture MSI installation; all were fixed.
- Tag run `42624635716` passed all jobs and published [`v0.1.0`](https://github.com/Alaa91H/BatteryGuard/releases/tag/v0.1.0) with exactly the 11 installer files; the tag points to commit `449245b` and remains CLI-only.
- Branch run `42652367294` validated the `0.2.0` version bump and the same seven-job matrix. Tag run `42653411073` published [`v0.2.0`](https://github.com/Alaa91H/BatteryGuard/releases/tag/v0.2.0) with 14 assets, including three EXE bootstrappers and three MSIs.

## Known limitations

1. **Charge control is HP-only.** Lenovo, Dell, ASUS, MSI, Acer and other vendors are monitored but not controlled; see `docs/DEVICE_SUPPORT.md` for the matrix and safety rationale.
2. **Translation review.** The non-English catalogs are machine-generated; this pass corrected charge, health and schedule terminology, but long sentences and technical wording have not been reviewed by native speakers.
3. **Portable runtime.** Hosted CI now links, runs the unit tests and invokes the CLI on six native runners. This Windows host still cannot link locally because Cargo and the available linkers are blocked by Application Control; no Linux/macOS hardware was available for a real battery reading.
4. **Live visual check.** Actual-window 100% captures were regenerated with process DPI awareness; Settings English/Arabic light/dark, schedule English light and log Arabic light were reviewed, including RTL ComboBoxes, the pinned footer and the installed version. The native tray menu and final notification banner were not captured. 125%/150% are covered by `Test-Layout`'s scaled layout/font simulation, not by native screenshots.
5. **Notification banner automation.** `Test-AppIdentity` verifies the shortcut and AUMID, but no reliable automated test currently opens the real Windows banner and reads its app label; a UI Automation probe did not find a visible toast on this desktop.
6. **Elevation.** HP's WMI provider requires an elevated process. `start.ps1` requests elevation; `-NoElevate` is intended for the logon task or for hosts that are already elevated. Tests that write charge mode need elevation.
7. **BIOS charger wattage.** Windows `BatteryStatus` exposes pack voltage and charge/discharge power, not AC adapter input power. HP BIOS settings were not accessible without elevation and no documented adapter-wattage field was verified, so the UI does not fabricate a charger-power value.
8. **Linux/macOS widgets.** No menu-bar or tray widget is included; only the CLI is packaged on those systems.
9. **Smart App Control.** `application.exe` may be blocked on this machine; the launcher falls back to compiling the same source in the system PowerShell host.
10. **Language switch layout.** Choosing a different language updates the tray after refresh, but an already-open Settings window keeps its original layout until reopened.
11. **Undocumented firmware.** HP charge modes are model-specific. Unsupported models fail closed to monitoring.
12. **Interactive installer UI.** CI exercises quiet install, upgrade and uninstall only. The wizard, launch-after-install checkbox and visual layout were not tested: this Windows 11 Home host has no Windows Sandbox/VM tools and Application Control blocks the EXE, while GitHub-hosted runners have no interactive desktop.
13. **Installer execution.** Smart App Control may block the installers; do not describe them as publisher-verified.
14. **Firmware setup values are not readable from Windows.** Even elevated, `GetFirmwareEnvironmentVariable` returned Win32 203 for the F.28 IFR names `SystemConfig`, `H19SetupUtilityConfig`, `H19SetupVariable` and `AdvanceConfig`, so the stored values and the firmware Battery Care ceiling cannot be read or reconciled by the app. A read-only UEFI shell dump is documented in `docs/DEVICE_SUPPORT.md`; the app never writes these variables.

## Out of scope

- Cloud accounts, telemetry or network services.
- Forced discharge or battery calibration.
- Charge-control writes on non-HP firmware without a documented, hardware-verified interface.
- An auto-update channel. Release artifacts are built directly by CI.

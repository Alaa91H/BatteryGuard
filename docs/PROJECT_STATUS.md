# Project status

**Date:** 2026-11-09  
**Application:** BatteryGuard tray monitor  
**Build:** `battery/application.exe` — 99,328 bytes  
**CI:** single tag-gated workflow; hosted run `42632698346` green with 11 installers, the C# suite and the new Windows tray MSI; published release remains `v0.1.0` (CLI-only)

## Completed

- Native Win32 tray application with owner-drawn menus and WinForms settings, schedule, log and rule dialogs.
- **Charge policy split into `ChargePolicy`.** Float mode activates only after the measured charge reaches the ceiling; charging below the limit is never inhibited by float. The latch holds until the resume point, then charging restarts.
- **Device controller layer:** `IBatteryController`, `HpBios`, `GenericBatteryController` and `BatteryControllerFactory`. HP gets charge control; other vendors get full monitoring with an explicit **Monitoring only** state.
- **Voltage and power readout.** The tray tooltip, menu, status balloon and Settings battery card show the current pack voltage and charge/discharge power, for example `11.8 V · 0.0 W`. Unavailable values are omitted; zero watts is shown when voltage confirms a battery reading. This is battery-pack power, not AC adapter input wattage.
- **Windows tray MSI.** The branch MSI installs `application.exe`, `batteryguard.exe`, the icon and all 30 locale catalogs under `Program Files\BatteryGuard`. It creates an all-users Start Menu shortcut with `BatteryGuard.Tray` and an **Uninstall BatteryGuard** shortcut. The x64 MSI install/uninstall path is tested in CI; x86 and ARM64 are built but not cross-installed on the x64 runner.
- **C# CI gate.** The Windows x64 job runs eight hardware-independent C# tests before packaging; the same suite passed locally.
- **Optional native signing.** The workflow can Authenticode-sign the tray, CLI and MSI, and Developer ID-sign/notarize the macOS PKG, only when the documented secrets exist. No certificates are configured in this repository, so the unsigned path is what the current green run exercises.
- Charge ceiling, resume point, float mode, scheduled time windows, overlap detection and conflict banners.
- Battery health, capacity, cycle, temperature and remaining-time display.
- System notifications, test notification, log viewer, export and 1 MiB rotation.
- **Stable notification identity.** `BatteryGuard.Tray` is set as the process AUMID and mirrored in `%APPDATA%\Microsoft\Windows\Start Menu\Programs\BatteryGuard.lnk`, so Windows labels notifications **BatteryGuard** instead of the PowerShell host.
- Theme support (auto/light/dark) and high-contrast tray icon variants.
- Adaptive, DPI-aware dialogs with working-area clamping and scrolling: Settings 780×1000 with a pinned action footer, schedule window 500×400 with pinned buttons, activity log 760×560 with a wrapping action bar.
- **30 locale catalogs**, each with 151 keys; placeholder validation reports 0 mismatches.
- **Focused source modules:** `Program`, `TrayApp`, `Engine`, `Wmi`, `AppIdentity`, `Config`, `Theme`, `Dialogs` and `Native`; build, launcher and tests compile every `src/*.cs` file.
- **Visual/RTL pass:** Settings, schedule and log inspected in English/Arabic and light/dark; RTL row order, schedule columns, card heights, list visibility and LTR log body corrected.
- **Translation terminology pass:** charge, health and schedule labels corrected across the 30 catalogs, including money mistranslations and untranslated values.
- English source/fallback; `language=auto` default; Windows display-language detection; Arabic, Urdu, Persian and Hebrew RTL.
- Language selector in Settings; `language` persisted in `interface.ini`.
- Neutral project layout: `src/`, `resources/`, `locales/`, `scripts/`, `tests/`; neutral data names (`settings.json`, `interface.ini`, `theme.ini`, `capacity.ini`, `application.log`).
- Startup migration from the old product-named data files.
- English project documentation, device support, architecture, decisions, roadmap, localization guide and changelog.
- Elevated restart after the electrical/identity change: process 18616; `controller: HP HP ENVY x360 Convertible 13-ay0xxx (charge control)`, `tray icon added=True`, `tray started`, and the tick line contains `v=11780mV p=0mW`.

## Verification

Passed in this session (2026-11-09):

| Check | Result |
| --- | --- |
| `Test-FloatLogic.ps1` | 13/13 OK |
| `Test-ScheduleConflict.ps1` | 6/6 OK |
| `Test-UiPolish.ps1` | 11/11 OK |
| `Test-Settings.ps1` | Save, schedule conflict guard and restore OK |
| `Test-BatteryInfo.ps1` | Real readings, electrical formatting (`11.8 V · 0.0 W`, `11.8 V · 6.5 W`) and arithmetic OK |
| `Test-AppIdentity.ps1` | Start Menu shortcut, AUMID, target, arguments and description OK |
| `Test-LogRotation.ps1` | Main log and previous log rotation OK |
| `Test-Icons.ps1` | Contact sheet rendered OK |
| `Test-Layout.ps1` | Settings 780×601/700×520/620×480/560×420, schedule 500×400/440×320/380×300 and log 760×560/520×360/440×300 OK |
| `VisualCapture.ps1` | 13 images in English/Arabic and light/dark; Settings Arabic light/dark, English dark and the full Settings content re-inspected with the electrical value |
| `build.ps1` | csc exit 0 |
| GitHub Actions `42623422341` | All 7 packaging jobs succeeded; 11 installers; Rust/CLI smoke tests passed; no Node/RPM warnings |
| GitHub Actions `42624635716` | Tag run succeeded; GitHub Release `v0.1.0` published with exactly 11 installer assets |
| GitHub Actions `42629998330` | All 7 packaging jobs succeeded; 11 installers; Windows x64 MSI install/uninstall, DEB install/run and PKG install/run checks passed |
| GitHub Actions `42632698346` | All 7 packaging jobs succeeded; Windows x64 C# suite, x64 MSI install/uninstall, DEB install/run and PKG install/run checks passed |

Locale inventory: 30 JSON files, 151 keys in each file including the `Monitoring only` key; no missing keys and no placeholder mismatches.

The Settings reflection test reported `780×601` client size on this 1280×720 desktop, with a 54 px pinned footer and a 930 px scrollable root. `Test-Layout` confirmed that the footer stays inside the window at every measured size, the content scrolls, and the language/direction combos keep a 190 px width and selected text.

## Published v0.1.0 installer checks

- **Windows (real machine):** an existing CLI-only `0.1.0` installation was
  found at `C:\Program Files\BatteryGuard\batteryguard.exe` (303,104 bytes).
  The x64 MSI SHA-256 is
  `B9F46ECD9A80452EECE2E2FD81F0D1C5F4DE28D7123CA4F0444BA206EEA325E5`;
  `Get-AuthenticodeSignature` reports `NotSigned`. Running the installed CLI is
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

## Portable core (phase 1)

- `portable/src/model.rs`, `format.rs` and `policy.rs` implement the shared battery model, electrical/duration formatting and the 13-case charge/float policy.
- `portable/src/platform/{windows,linux,macos}.rs` provide read-only providers: PowerShell/WMI, `power_supply` sysfs and `pmset -g batt`.
- `portable/src/main.rs` provides a text/JSON/watch CLI; `Cargo.toml` and `rustc` build/test scripts are included.
- `portable/scripts/check-targets.ps1` type-checks the library, test harness and CLI for 12 targets: x86/x64/ARM64 Windows, x86/x64/ARMv7/ARM64 Linux and Intel/Apple-silicon macOS.
- The check passed 12/12. It uses `--emit=metadata`, so it validates conditional compilation and types but does not link or execute.
- **Hosted verification:** GitHub Actions run `42632698346` linked and tested the Rust core on Windows x64/x86, Linux x64/ARM64 and macOS Intel/Apple silicon, ran the C# suite on Windows x64, built 3 MSI, 6 Linux packages and 2 PKG files, installed the DEB and PKG and ran `batteryguard --version`, and installed/uninstalled the x64 MSI with the C# tray payload. The CLI printed `BatteryGuard portable core 0.1.0` on every runnable target.
- **Not verified locally:** no linked `batteryguard` executable, no executed Rust tests and no local Linux/macOS runtime. This host has no MSVC linker; Application Control blocks Cargo, GNU rustc and the available lld/GNU linkers.
- **Not included:** Linux/macOS widgets and cross-platform charge control. Native Authenticode/Apple notarization is implemented as an optional signing path, but no certificates are configured and it has not been exercised; the current installers carry Sigstore build-provenance attestations only.

## Release CI

- `.github/workflows/ci.yml` is the only workflow. It validates the Cargo version, builds the full matrix, attests the installers and uploads branch artifacts.
- The release job is skipped unless the ref is `refs/tags/v<Cargo version>`; it filters assets to `.msi`, `.deb`, `.rpm`, `.AppImage` and `.pkg`.
- Branch run `42629998330` covered all 7 native packaging jobs and produced 11 installers. Its x64 MSI passed install, payload, Start Menu/uninstall-shortcut and uninstall checks; Linux DEB and macOS PKG install-and-run checks passed.
- Branch run `42632698346` added the eight-test C# suite and kept all seven packaging jobs green, including the x64 MSI and native package checks. The optional signing steps were skipped because no certificate secrets are configured. Earlier runs exposed missing Cargo paths (`42622500646`), Unix packaging paths, the invalid `CommonProgramsFolder` WiX id and cross-architecture MSI installation; all were fixed.
- Tag run `42624635716` passed all jobs and published [`v0.1.0`](https://github.com/Alaa91H/BatteryGuard/releases/tag/v0.1.0) with exactly the 11 installer files; the tag points to commit `449245b` and remains CLI-only.

## Known limitations

1. **Charge control is HP-only.** Lenovo, Dell, ASUS, MSI, Acer and other vendors are monitored but not controlled; see `docs/DEVICE_SUPPORT.md` for the matrix and safety rationale.
2. **Translation review.** The non-English catalogs are machine-generated; this pass corrected charge, health and schedule terminology, but long sentences and technical wording have not been reviewed by native speakers.
3. **Portable runtime.** Hosted CI now links, runs the unit tests and invokes the CLI on six native runners. This Windows host still cannot link locally because Cargo and the available linkers are blocked by Application Control; no Linux/macOS hardware was available for a real battery reading.
4. **Live visual check.** Settings Arabic light/dark, English dark and the full Settings content were re-inspected with the electrical reading; status balloon capture was not possible because browser notifications occupied the desktop, so the final Windows label was not visually confirmed. The native tray menu could not be captured; its RTL flags are set but its pixels were not reviewed. 125%/150% DPI was not exercised.
5. **Notification banner automation.** `Test-AppIdentity` verifies the shortcut and AUMID, but no reliable automated test currently opens the real Windows banner and reads its app label; a UI Automation probe did not find a visible toast on this desktop.
6. **Elevation.** HP's WMI provider requires an elevated process. `start.ps1` requests elevation; `-NoElevate` is intended for the logon task or for hosts that are already elevated. Tests that write charge mode need elevation.
7. **BIOS charger wattage.** Windows `BatteryStatus` exposes pack voltage and charge/discharge power, not AC adapter input power. HP BIOS settings were not accessible without elevation and no documented adapter-wattage field was verified, so the UI does not fabricate a charger-power value.
8. **Linux/macOS widgets.** No menu-bar or tray widget is included; only the CLI is packaged on those systems.
9. **Smart App Control.** Unsigned `application.exe` may be blocked on this machine; the launcher falls back to compiling the same source in the signed PowerShell host.
10. **Language switch layout.** Choosing a different language updates the tray after refresh, but an already-open Settings window keeps its original layout until reopened.
11. **Undocumented firmware.** HP charge modes are model-specific. Unsupported models fail closed to monitoring.

## Out of scope

- Cloud accounts, telemetry or network services.
- Forced discharge or battery calibration.
- Charge-control writes on non-HP firmware without a documented, hardware-verified interface.
- Configured and verified native Authenticode/Apple Developer ID signatures (the opt-in workflow paths exist but have no credentials), notarization on a physical macOS device, and an auto-update channel. The CI attestation is a separate supply-chain signature.

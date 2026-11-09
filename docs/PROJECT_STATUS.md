# Project status

**Date:** 2026-11-09  
**Application:** BatteryGuard tray monitor  
**Build:** `battery/application.exe` — 99,328 bytes  
**CI:** single tag-gated workflow; hosted run `42623422341` green with 11 installers

## Completed

- Native Win32 tray application with owner-drawn menus and WinForms settings, schedule, log and rule dialogs.
- **Charge policy split into `ChargePolicy`.** Float mode activates only after the measured charge reaches the ceiling; charging below the limit is never inhibited by float. The latch holds until the resume point, then charging restarts.
- **Device controller layer:** `IBatteryController`, `HpBios`, `GenericBatteryController` and `BatteryControllerFactory`. HP gets charge control; other vendors get full monitoring with an explicit **Monitoring only** state.
- **Voltage and power readout.** The tray tooltip, menu, status balloon and Settings battery card show the current pack voltage and charge/discharge power, for example `11.8 V · 0.0 W`. Unavailable values are omitted; zero watts is shown when voltage confirms a battery reading.
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

Locale inventory: 30 JSON files, 151 keys in each file including the `Monitoring only` key; no missing keys and no placeholder mismatches.

The Settings reflection test reported `780×601` client size on this 1280×720 desktop, with a 54 px pinned footer and a 930 px scrollable root. `Test-Layout` confirmed that the footer stays inside the window at every measured size, the content scrolls, and the language/direction combos keep a 190 px width and selected text.

## Portable core (phase 1)

- `portable/src/model.rs`, `format.rs` and `policy.rs` implement the shared battery model, electrical/duration formatting and the 13-case charge/float policy.
- `portable/src/platform/{windows,linux,macos}.rs` provide read-only providers: PowerShell/WMI, `power_supply` sysfs and `pmset -g batt`.
- `portable/src/main.rs` provides a text/JSON/watch CLI; `Cargo.toml` and `rustc` build/test scripts are included.
- `portable/scripts/check-targets.ps1` type-checks the library, test harness and CLI for 12 targets: x86/x64/ARM64 Windows, x86/x64/ARMv7/ARM64 Linux and Intel/Apple-silicon macOS.
- The check passed 12/12. It uses `--emit=metadata`, so it validates conditional compilation and types but does not link or execute.
- **Hosted verification:** GitHub Actions run `42623422341` linked and tested the Rust core on Windows x64/x86, Linux x64/ARM64 and macOS Intel/Apple silicon, then built 3 MSI, 6 Linux packages and 2 PKG files. The CLI printed `BatteryGuard portable core 0.1.0` on every runnable target.
- **Not verified locally:** no linked `batteryguard` executable, no executed Rust tests and no local Linux/macOS runtime. This host has no MSVC linker; Application Control blocks Cargo, GNU rustc and the available lld/GNU linkers.
- **Not included:** Linux/macOS widgets, cross-platform charge control and native Authenticode/Apple notarization. The installers carry Sigstore build-provenance attestations, not OS code signatures.

## Release CI

- `.github/workflows/ci.yml` is the only workflow. It validates the Cargo version, builds the full matrix, attests the installers and uploads branch artifacts.
- The release job is skipped unless the ref is `refs/tags/v<Cargo version>`; it filters assets to `.msi`, `.deb`, `.rpm`, `.AppImage` and `.pkg`.
- Branch run `42623422341` covered all 7 native packaging jobs and produced 11 installers without warnings. Earlier runs exposed missing Cargo paths (`42622500646`) and Unix packaging paths; both were fixed before this run.
- `v0.1.0` is the release tag for the current `portable/Cargo.toml` version `0.1.0`.

## Known limitations

1. **Charge control is HP-only.** Lenovo, Dell, ASUS, MSI, Acer and other vendors are monitored but not controlled; see `docs/DEVICE_SUPPORT.md` for the matrix and safety rationale.
2. **Translation review.** The non-English catalogs are machine-generated; this pass corrected charge, health and schedule terminology, but long sentences and technical wording have not been reviewed by native speakers.
3. **Portable runtime.** Hosted CI now links, runs the unit tests and invokes the CLI on six native runners. This Windows host still cannot link locally because Cargo and the available linkers are blocked by Application Control; no Linux/macOS hardware was available for a real battery reading.
4. **Live visual check.** Settings Arabic light/dark, English dark and the full Settings content were re-inspected with the electrical reading; status balloon capture was not possible because browser notifications occupied the desktop, so the final Windows label was not visually confirmed. The native tray menu could not be captured; its RTL flags are set but its pixels were not reviewed. 125%/150% DPI was not exercised.
5. **Elevation.** HP's WMI provider requires an elevated process. `start.ps1` requests elevation; `-NoElevate` is intended for the logon task or for hosts that are already elevated. Tests that write charge mode need elevation.
6. **Smart App Control.** Unsigned `application.exe` may be blocked on this machine; the launcher falls back to compiling the same source in the signed PowerShell host.
7. **Language switch layout.** Choosing a different language updates the tray after refresh, but an already-open Settings window keeps its original layout until reopened.
8. **Undocumented firmware.** HP charge modes are model-specific. Unsupported models fail closed to monitoring.

## Out of scope

- Cloud accounts, telemetry or network services.
- Forced discharge or battery calibration.
- Charge-control writes on non-HP firmware without a documented, hardware-verified interface.
- Native Authenticode/Apple Developer ID signing, notarization and an auto-update channel. The CI attestation is a separate supply-chain signature.

# Changelog

All notable changes to this project are documented here. The format follows the spirit of Keep a Changelog; versions are not used because the application is distributed as a portable build.

## 2026-11-09 — portable Rust core

### Added

- Dependency-free Rust core under `portable/`: battery model, electrical/duration formatting, 13-case charge/float policy, text/JSON/watch CLI and read-only Windows, Linux and macOS backends.
- Windows PowerShell/WMI provider, Linux `power_supply` sysfs provider and macOS `pmset -g batt` provider, each with fixture parsers.
- `Cargo.toml`, `rustc` build/test scripts and `check-targets.ps1` for x86/x64/ARM64 Windows, x86/x64/ARMv7/ARM64 Linux and Intel/Apple-silicon macOS.
- `portable/README.md` and `portable/PLATFORMS.md`.

### Verification

- The 12-target check passed for the library, test harness and CLI using `--emit=metadata`.
- No linked executable or runtime test was produced: the host lacks an MSVC linker, and Application Control blocks Cargo, GNU rustc and the available lld/GNU linkers. Linux and macOS hardware was unavailable.

### Known limitations

- The portable backends are read-only. HP Windows remains the only charge-control implementation.
- No installers, packages or Linux/macOS widgets are included yet.

## 2026-11-09 — electrical readout and notification identity

### Added

- **Voltage and power readout.** `BatteryInfo` now exposes `PowerMilliwatts`, `ElectricalText()` and `FormatElectrical()`. The tray tooltip, tray menu, status balloon and Settings battery card show `11.8 V · 0.0 W` from `BatteryStatus.Voltage`, `ChargeRate` and `DischargeRate`.
- **Notification identity.** `AppIdentity` sets `BatteryGuard.Tray` as the process AUMID and creates `%APPDATA%\Microsoft\Windows\Start Menu\Programs\BatteryGuard.lnk` with `System.AppUserModel.ID`, icon and description. The shortcut targets the compiled exe or the PowerShell host with `start.ps1 -NoElevate`.
- `Test-AppIdentity.ps1`: verifies the shortcut, AUMID, target, arguments and description without elevation.

### Changed

- The tooltip places the electrical reading near the start, before longer details, because the native tooltip is capped at 127 characters.
- The tick log now includes `v=<mV> p=<mW>` for diagnostics.
- `Test-BatteryInfo.ps1` checks the electrical format, including the real idle reading and an empty reading.
- The Settings battery card includes the electrical value beside capacity; the adaptive layout still fits at 780×601.

### Verification

- Build: csc exit 0; `application.exe` 99,328 bytes.
- `Test-BatteryInfo`: real reading `11781 mV`, `0 mW`; `11.8 V · 0.0 W`; sample `11.8 V · 6.5 W`; idle and empty formats OK.
- `Test-AppIdentity`: all shortcut and AUMID checks pass.
- `Test-Layout`: pass after the battery-card addition.
- `VisualCapture`: Settings Arabic light/dark, English dark and full Settings content inspected; the new value is not clipped.
- Elevated restart: `tray icon added=True`, `tray started`, tick line contains `v=11780mV p=0mW`.

### Known limitations

- The notification banner itself was not visually confirmed because browser notifications occupied the captured desktop; the AUMID and Start Menu shortcut were verified directly.
- The wattage is the battery charge/discharge rate, not AC adapter input power. An idle charger reports zero watts.
- 125%/150% DPI was not exercised.

## 2026-11-09 — adaptive window layout

### Changed

- Settings now separates its scrollable content from a pinned Save/Cancel/Test footer. The design size is 780×1000, the minimum is 620×480, the root table is 930 px tall, and the footer height is recomputed when the window is resized.
- The Settings content keeps a 660 px minimum width. Below that, horizontal scrolling preserves every field instead of clipping it; the footer action buttons use `AutoSize` and `WrapContents` so they remain reachable.
- The schedule window is now 500×400 with a 440×320 minimum. Its content scrolls, its layout floor is 360 px, its explanatory note wraps, and Save/Cancel stay pinned below the scrolling area.
- The activity log minimum is 520×360; its action bar is auto-sized and wraps the status and buttons onto a second row on narrow windows.
- `UiLayout.Fit` now lowers a form's `MinimumSize` when the working area cannot fit it, then clamps the window to `WorkingArea - 32`. This prevents the title bar or action buttons from being pushed off a small display.
- `VisualCapture.Capture-Full` now finds the `SettingsRoot` inside `SettingsContent`, so the full-height capture reflects the new scrollable structure.

### Verification

- `build.ps1`: csc exit 0; `application.exe` 94,208 bytes.
- New `Test-Layout.ps1` passes. It measures Settings at 780×601, 700×520, 620×480 and 560×420; the schedule window at 500×400, 440×320 and 380×300; and the log at 760×560, 520×360 and 440×300.
- The footer stays inside Settings at every measured size (54 px high at 780×601), the content scrolls (929 px maximum), the root keeps its 660 px width, and the language/direction combos keep a 190 px width and selected text.
- The schedule note and controls avoid sideways scrolling at 380 px; the log action bar grows from 49 px to 80 px when it wraps at 440 px.
- Hardware-free suite: FloatLogic 13/13, ScheduleConflict 6/6, UiPolish 11/11, Settings, BatteryInfo, LogRotation, Icons and Layout pass.
- `VisualCapture.ps1` regenerated 13 PNGs. Settings Arabic light/dark, schedule and log Arabic light, and the full Settings content were inspected.

### Known limitations

- English and the dark schedule/log captures were regenerated but not re-inspected in this pass.
- `DrawToBitmap` does not paint the native selected text of a WinForms ComboBox; `Test-Layout` checks combo width, selection and text instead.
- 125% and 150% DPI were not exercised.

## 2026-11-09 — module split, RTL layout and translation terminology

### Changed

- Split `src/Application.cs` into `Program`, `TrayApp`, `Engine`, `Wmi`, `Config`, `Theme`, `Dialogs` and `Native` without changing behavior. Build, launcher and tests enumerate `src/*.cs`.
- Settings now uses a 780×1000 design size with a 990 px root table so the notification and interface cards fit without clipping.

### Fixed

- RTL rows in Settings were laid out left-to-right because `FlowDirection.RightToLeft` was mirrored twice by the RTL form. Rows now keep a logical left-to-right flow and let the form mirror them; charge/recharge labels, presets, schedule buttons, notification rows and language rows read right-to-left.
- The schedule list collapsed to one pixel because its table rows were implicitly auto-sized; explicit rows and a 98 px list host keep it visible.
- The battery card truncated its second line in Arabic; it now uses two lines at 104 px.
- The notifications card clipped its second and third rows; the card rows now use explicit percentage heights.
- Activity log content stays LTR inside an RTL window so timestamps and paths remain readable.
- `Test-UI` no longer erases `language`/`direction` when it rewrites `interface.ini`; `VisualCapture` appends missing keys and reloads `UiSettings` before each language.

### Localization

- Corrected charge/health/schedule terminology across the 30 catalogs, including money meanings of “recharge” in Thai, Vietnamese and Chinese, “standard fee” in Chinese and Ukrainian, untranslated Finnish scheduling, German “Terminplanung” (appointments) and French “chargement” (loading).
- Catalog validation: 30 files, 151 keys each, no missing keys and no placeholder mismatches.

### Verification

- `build.ps1`: csc exit 0; `application.exe` 92,672 bytes.
- Hardware-free suite: FloatLogic 13/13, ScheduleConflict 6/6, UiPolish 11/11, Settings, BatteryInfo, LogRotation and Icons pass.
- `VisualCapture.ps1`: 13 images covering Settings, schedule and log in English/Arabic and light/dark; inspected for RTL, clipping and alignment.
- The native tray popup menu could not be captured from the test host; its `MFT_RTL`/`TPM_RIGHTALIGN` flags were verified in code.

## 2026-11-09 — charge float latch, device support and dialog sizing

### Added

- `IBatteryController`, `HpBios`, `GenericBatteryController`, `BatteryControllerFactory` and `DeviceInfo`: HP charge control with a read-only fallback for every other vendor.
- `ChargePolicy` / `ChargeDecision`: a pure charge/float decision table separated from WMI.
- **Monitoring only** state in the tray, menu and Settings battery card, plus the key in all 30 catalogs.
- `Test-FloatLogic.ps1`: 13 hardware-free charge/float decisions.
- `docs/DEVICE_SUPPORT.md`: vendor matrix, detection, safety model and verification scope.
- `UiLayout.Fit`: clamps DPI-scaled dialogs to the screen working area.

### Changed

- **Float mode now starts only after the charge reaches the ceiling.** Charging below the limit is never inhibited for float; a stale inhibit is released. The latch holds through small drops until the resume point.
- Tray icon states now distinguish floating (teal), stopped/charging (orange/green) and monitoring (slate); the tooltip reports `Charger power · battery idle` while floating.
- Tray menu shows vendor/model, the monitoring state and disables charge actions on non-HP hardware.
- Settings window: 780×980 design size, minimum 680×620, `AutoScaleMode.Dpi`, `AutoScroll`, working-area clamp.
- Schedule window: 500×380 and DPI-aware; activity log: 760×560, minimum 620×420 and DPI-aware.
- Docs updated for the new policy, device layer, window sizes and totals (151 keys).

### Fixed

- Faulty expression `FloatActive = decision.FloatActive && wasFloat || decision.FloatActive` in `Engine.Tick`.
- Float could inhibit charging before the configured limit or stay inhibited below the target.
- Monitoring-only devices were treated as an error (`Unsupported` mode produced a red icon and an HP-provider error notification).
- `Monitoring only` appeared twice in the tooltip.
- Dialogs could exceed the screen on a 1280×720 desktop; they are now clamped and scroll instead of clipping.

### Verification

- `build.ps1`: csc exit 0; `application.exe` 92,160 bytes.
- `Test-FloatLogic.ps1`: 13/13 OK.
- `Test-ScheduleConflict.ps1`: 6/6 OK.
- `Test-UiPolish.ps1`: 11/11 OK.
- `Test-Settings.ps1`, `Test-BatteryInfo.ps1`, `Test-LogRotation.ps1`, `Test-Icons.ps1`: pass.
- Locale validation: 30 files, 151 keys each, zero missing keys and zero placeholder mismatches.
- Settings measured 780×585 client on the 1280×720 test desktop (working-area clamp); design size 780×980.
- Elevated restart: process 18396; HP controller detected, `tray icon added=True`, first tick `float=no control=full`.

### Known limitations

- Charge control is HP-only; Lenovo, Dell, ASUS, MSI and other vendors are monitoring-only.
- The dialogs were not visually inspected; sizes and states were verified through reflection tests.
- Non-English catalogs remain machine-generated without native-speaker review.

## 2026-11-09

### Added

- **30 language catalogs:** English, Arabic, Spanish, French, German, Portuguese, Italian, Russian, Simplified Chinese, Traditional Chinese, Japanese, Korean, Hindi, Bengali, Urdu, Persian, Turkish, Dutch, Polish, Ukrainian, Romanian, Greek, Czech, Swedish, Danish, Finnish, Hebrew, Thai, Vietnamese and Indonesian.
- `Loc` runtime localization: language metadata, native names, RTL flags, automatic Windows-language detection, JSON catalog loading, `T()` and `F()` with English fallback.
- **Language selector** in Settings with an Automatic option and native language names; persisted as `language=` in `interface.ini`.
- Automatic default (`language=auto`) and language-derived direction, with an explicit `direction=rtl|ltr` override.
- `Language` catalog key across all 30 files.
- English project documentation: root `README.md`, application README, `AGENTS.md`, architecture, project status, roadmap, decisions, localization guide, session log and this changelog.
- Neutral project layout: `src/`, `resources/`, `locales/`, `scripts/`, `tests/`.
- Startup data migration from the old product-named files to `settings.json`, `interface.ini`, `theme.ini`, `capacity.ini`, `application.log` and `application.previous.log`.
- Maintenance utilities under `tools/` for catalog generation, English refinement, glossary corrections, placeholder validation and the one-time restructuring.

### Changed

- UI strings in `Application.cs` now use English source keys and `Loc.T`/`Loc.F` instead of Arabic literals.
- `UiSettings.Load()` now loads the selected language; `UiSettings.Rtl` follows the language when `direction=auto`.
- `UiSettings.Save()` persists `language`.
- Build, launcher, restart, control and test scripts use the new folder layout and neutral data paths.
- `start.ps1` compiles `src/Localization.cs` and `src/Application.cs`; the compiled output is `application.exe`.
- Log and interface names are neutral; log rotation writes `application.previous.log`.
- English source terminology was clarified for battery meanings: “charge limit” instead of the ambiguous “ceiling”, “time window” for schedule ranges, “activity log” for the log, and “light/dark theme” for themes.
- Targeted glossary translations replaced ambiguous machine output for charge limit, charge control, themes, time windows and the conflict-message fragment.

### Fixed

- Three multiline UI messages that the first literal-replacement pass missed (empty schedule prompt, paused schedule prompt and exported-log path).
- `Test-UiPolish` now writes `language=en` temporarily and restores `interface.ini`, so its English assertions are deterministic.
- Tests compile both C# source files after the localization split.
- `Test-LogRotation`, `Test-Icons`, `Test-Tray` and `Test-TrayHost` use the new repository root and data names.
- Destination path migration preserves existing settings without overwriting a new file.

### Verification

- `build.ps1`: csc exit 0; `application.exe` 88,064 bytes.
- `Test-ScheduleConflict.ps1`: 6/6 OK.
- `Test-UiPolish.ps1`: 11/11 OK.
- `Test-Settings.ps1`: save, conflict guard and restore OK.
- `Test-BatteryInfo.ps1`: real readings and arithmetic OK.
- `Test-LogRotation.ps1`: main and archive rotation OK.
- `Test-Icons.ps1`: contact sheet rendered OK.
- Elevated restart: `tray pid=16740 alive=True`; `tray started`; first policy `Limit 60% (resume 55%)`.
- Locale validation: 30 files, 150 keys each at that time (now 151), zero missing keys and zero placeholder mismatches.

### Known limitations

- Non-English catalogs are machine-generated and have not been reviewed by native speakers.
- The final build was launched elevated (process 16740, `tray started`), but the tray, menu and dialogs were not visually inspected.
- HP WMI writes still require elevation; Smart App Control may block the unsigned executable and trigger the in-memory host fallback.
- An open Settings window keeps its layout until reopened after a language change.

# Session log

## 2026-11-09 — cross-platform installers and tag-gated release CI

### Goal

Replace the repository's ad-hoc build notes with one professional CI workflow
that builds installers for every supported system, signs them, does not publish
on ordinary pushes, and publishes only when a tag matches the release version.
Keep the Windows tray, the read-only Rust core and the safety boundary intact.

### Work performed

1. Added `.github/workflows/ci.yml` as the only workflow. It validates the
   three-part version in `portable/Cargo.toml`, derives a snapshot version for
   branch builds, and requires a tag of exactly `v<version>`.
2. Added seven native packaging jobs:
   - Windows x86/x64/ARM64 MSI through WiX 5.0.2.
   - Linux x64/ARM64 static-musl DEB, RPM and AppImage through
     `packaging/linux/build-linux.sh`.
   - macOS Intel and Apple-silicon PKG through
     `packaging/macos/build-pkg.sh`.
3. Added Rust unit tests and a `batteryguard --version` smoke test on every
   runnable target. Windows ARM64 is cross-compiled but not executed on the
   x64 hosted runner.
4. Added keyless GitHub/Sigstore build-provenance attestations for the
   installers and kept ordinary artifacts on branch runs.
5. Added the `release` job. It is skipped unless the ref is a `v*` tag, rejects
   unexpected file extensions, and publishes only `.msi`, `.deb`, `.rpm`,
   `.AppImage` and `.pkg` assets.
6. Fixed the packaging paths after the first hosted runs:
   - `d34e2c4` added `portable/` to the Cargo manifest paths.
   - `531167f` used the Cargo target directory from both Unix packagers.
   - `f1ce6cb` moved the actions to Node 24 releases, added a GNU build-id to
     Linux binaries, and added the CLI smoke test.
7. Added `docs/RELEASE.md` and updated the README, agent instructions and
   architecture/status/roadmap/decision records for the new pipeline.

### Verification

- Hosted run [`42623422341`](https://github.com/Alaa91H/BatteryGuard/actions/runs/42623422341)
  completed successfully: all 7 packaging jobs and the final run are green;
  the release job was skipped because the ref was a branch.
- Seven artifacts covered 11 installers: 3 MSI, 6 Linux packages and 2 PKG
  files. A `Keep only installer payload` step removes non-installer output
  such as the WiX `.wixpdb` before attestation and upload.
- The Rust tests and `BatteryGuard portable core 0.1.0` CLI smoke test passed
  on Windows x64/x86, Linux x64/ARM64 and macOS Intel/Apple silicon.
- The final logs contain no GitHub warning, Node deprecation warning, RPM
  missing-build-id warning or error. The earlier run's Node 20 and RPM warnings
  were corrected by the action upgrades and Linux build-id flag.
- No native Authenticode, Apple notarization or GPG signature was produced;
  there are no certificate secrets in this repository.

### Limitations observed

- No local linked Rust binary or local Rust test run was possible: this host
  lacks the MSVC linker and Application Control blocks Cargo and the available
  GNU/lld linkers.
- No real Linux or macOS battery reading was taken. Hosted runners have no
  battery hardware.
- The installers were built but were not installed or launched on clean
  Windows, Linux or macOS systems.
- The Windows tray C# code was not changed, so its previously recorded
  regression results still apply; no new visual or hardware check was made.

### Next

- Tag `v0.1.0` on the final documentation commit, wait for the release job and
  verify the published asset list and release notes.
- Add native OS signing and clean-VM install tests in a later release-hardening
  pass.

## 2026-11-09 — portable Rust core and support matrix

### Goal

Start the shared cross-platform BatteryGuard core in Rust, covering Windows, Linux and macOS across x86, x64, ARMv7 and ARM64, while keeping the working Windows tray application unchanged.

### Work performed

1. Added `portable/src/model.rs`: battery readings, derived power/health/minutes, status text and a structured error.
2. Added `portable/src/format.rs`: the shared `11.8 V · 6.5 W` and duration formatting.
3. Ported the 13 charge/float decisions to `portable/src/policy.rs` without platform or firmware dependencies.
4. Added read-only platform providers: Windows PowerShell/WMI, Linux `/sys/class/power_supply` and macOS `pmset -g batt`, each with fixture parsers.
5. Added the text/JSON/watch CLI, `Cargo.toml`, Cargo-compatible layout and `rustc` build/test scripts.
6. Added `PLATFORMS.md`, the README coverage matrix and `check-targets.ps1`.

### Verification

- `portable/scripts/check-targets.ps1` passed 12/12 targets for the library, test harness and CLI using `--emit=metadata`: x86/x64/ARM64 Windows, x86/x64/ARMv7/ARM64 Linux and Intel/Apple-silicon macOS.
- Windows library metadata and test metadata compile without errors.
- No linked executable and no executed Rust test: this host has no MSVC linker, and Application Control blocks Cargo, GNU rustc and the available lld/GNU linkers.
- No Linux or macOS runtime was available.

### Limitations observed

- The portable core is read-only. Charge control remains the existing HP Windows path.
- Installers, Linux/macOS widgets and linked binaries are not implemented.
- The Windows WMI and macOS `pmset` providers need a real runtime check before they can be called verified.

### Next

- Link and run the CLI on Windows, Linux and macOS; run the unit tests.
- Produce signed architecture-specific builds and installers, then add Linux/macOS widgets.

## 2026-11-09 — voltage/power readout and notification identity

### Goal

Add the incoming pack voltage and wattage to the tray tooltip and use the same reading in the tray menu, status balloon and Settings battery card. Make Windows notifications appear under **BatteryGuard** instead of **PowerShell** when the UI runs in the PowerShell host.

### Work performed

1. Added `PowerMilliwatts`, `ElectricalText()` and `FormatElectrical()` to `BatteryInfo`; the formatter uses one decimal, invariant culture and the `V`/`W` units without adding a translated UI string.
2. Added the same reading to `Engine`, placed it near the start of the 127-character tooltip, and included it in the menu and status balloon.
3. Added the reading to the Settings battery card after capacity. The real hardware reading was `11.8 V · 0.0 W` while the charger held the battery idle.
4. Added `v={11}mV p={12}mW` to the 30-second tick log line so rates can be checked while charging or discharging.
5. Added `AppIdentity`: process AUMID `BatteryGuard.Tray`, a Start Menu shortcut with `System.AppUserModel.ID`, icon and description, targeting the exe or the PowerShell host with `start.ps1 -NoElevate`.
6. Added `SetCurrentProcessExplicitAppUserModelID` to `Native` and called `AppIdentity.Install()` before the tray window is created.
7. Added `Test-AppIdentity.ps1` and extended `Test-BatteryInfo.ps1` with voltage/power formatting checks.

### Verification

- Build: csc exit 0; `application.exe` 99,328 bytes.
- `Test-BatteryInfo`: real `voltage=11781 mV`, `power=0 mW`; `electrical=11.8 V · 0.0 W`; `format=11.8 V · 6.5 W`; idle and empty formats OK.
- `Test-AppIdentity`: shortcut exists, AUMID `BatteryGuard.Tray`, PowerShell target, expected `start.ps1 -NoElevate` arguments and description all OK.
- `Test-Layout`: pass; the changed battery card did not affect footer, scrolling or minimum sizes.
- Elevated restart: host process 18616; log reports `tray icon added=True`, `tray started`, and `v=11780mV p=0mW` in the tick line.
- VisualCapture: Settings Arabic light/dark, English dark and the full Settings content were inspected; the card shows `11.8 V · 0.0 W` without clipping.

### Limitations observed

- The status balloon was requested through the tray window, but the captured desktop was occupied by browser notifications; the final Windows label was not visually confirmed. The AUMID and shortcut were verified directly.
- The watts are the Windows battery charge/discharge rate, not AC adapter input power; idle charging correctly reports `0.0 W`.
- 125%/150% DPI was not exercised.

### Next

- Trigger a BatteryGuard balloon on a clean notification area and confirm the **BatteryGuard** label.
- Check a charging or discharging sample where `ChargeRate`/`DischargeRate` is non-zero.

## 2026-11-09 — adaptive window layout

### Goal

Make the Settings, schedule and activity-log dialogs usable at smaller working areas without clipping labels, action buttons or explanatory notes.

### Work performed

1. Moved the Settings content into a `SettingsContent` panel with `AutoScroll` and kept the Save/Cancel/Test footer outside it, docked at the bottom. The root table is 930 px tall and keeps at least 660 px of width.
2. Recomputed the footer height from its preferred size on resize; the action buttons are `AutoSize` and the footer wraps when necessary.
3. Changed `UiLayout.Fit` to lower `MinimumSize` before clamping to `WorkingArea - 32`, so a small display does not force a title bar or footer off-screen.
4. Reworked the schedule window: 500×400 design, 440×320 minimum, scrollable content, 360 px layout floor, wrapping note and pinned Save/Cancel buttons.
5. Reworked the activity-log action bar to auto-size and wrap; the log minimum is 520×360.
6. Updated `VisualCapture.Capture-Full` to locate `SettingsRoot` through `SettingsContent` after the layout restructure.
7. Added `tests/Test-Layout.ps1`, which shows the forms off-screen and measures footer bounds, scroll ranges, root width, combo text, rule layout and log bar wrapping at ten client sizes.

### Verification

- Build: csc exit 0; `application.exe` 94,208 bytes.
- `Test-Layout`: all measured checks pass. Settings 780×601 footer 54 px; scroll maximum 929; 620×480 and 560×420 use a 660 px root with horizontal fallback. Rule 500×400, 440×320 and 380×300 avoid sideways scrolling. Log bar 49 px at 520×360 and 80 px at 440×300.
- Hardware-free suite: FloatLogic 13/13, ScheduleConflict 6/6, UiPolish 11/11, Settings, BatteryInfo, LogRotation, Icons and Layout pass.
- Visual captures: 13 PNGs regenerated; Settings Arabic light/dark, schedule and log Arabic light, and the full Settings content inspected.

### Limitations observed

- English and dark schedule/log captures were not re-inspected after the layout change.
- `DrawToBitmap` omits native ComboBox selected text; the combo width, selection and text are asserted by `Test-Layout`.
- 125%/150% DPI and non-HP hardware were not exercised.

### Next

- Repeat the dialog matrix at 125% and 150% DPI.
- Re-inspect the English and dark schedule/log captures.
- Keep the footer and scroll checks in the release checklist.

## 2026-11-09 — module split, RTL pass and translation audit

### Goal

Split the monolithic application source into focused modules without behavior changes, inspect the windows in English/Arabic and light/dark, fix RTL and clipping defects, and review the charge, health and schedule terminology in all 30 catalogs.

### Work performed

1. Split `src/Application.cs` into `Program.cs`, `TrayApp.cs`, `Engine.cs`, `Wmi.cs`, `Config.cs`, `Theme.cs`, `Dialogs.cs` and `Native.cs`; kept `Localization.cs`. Source blocks were moved unchanged.
2. Updated `scripts/build.ps1`, `scripts/start.ps1` and every test to enumerate `src/*.cs`, removing the fixed source list.
3. Added `tests/VisualCapture.ps1`, which renders Settings, schedule and log at light/dark and English/Arabic and restores the UI/theme files.
4. Fixed RTL layout: FlowLayoutPanel double mirroring, schedule ListView columns, slider labels, battery-card wrapping, notification card row heights, schedule list height, button order and LTR log content.
5. Fixed `Test-UI` so rewriting `interface.ini` preserves `language`/`direction`, and restored the Arabic preference after the test run.
6. Corrected charge/health/schedule terms in the 30 catalogs (including money mistranslations and an untranslated Finnish value) and validated keys and placeholders.
7. Updated the architecture, README, roadmap, changelog, status and agent instructions for the module layout and current window sizes.

### Verification

- Build: csc exit 0; `application.exe` 92,672 bytes.
- Float decisions 13/13, schedule conflicts 6/6, UI polish 11/11; Settings, BatteryInfo, LogRotation and Icons pass.
- Visual captures: 13 PNGs; inspected Settings (full height), schedule and log in light/dark and English/Arabic.
- RTL measurements: language label at x=693 with the combo at x=494; charge/recharge labels at the right; equal schedule columns 237/237/242; notification rows 44 px each.
- Locale validation: 30 files, 151 keys each, zero missing keys and zero placeholder mismatches.

### Limitations observed

- The native tray popup menu could not be captured from the test host (hidden tray window not reachable from the capture process). Its RTL menu flags are set in code, but its pixels were not reviewed.
- No non-HP hardware was available for the generic controller path.
- 125% and 150% DPI were not exercised.
- The catalogs remain machine-translated with targeted corrections; no native-speaker review was performed.

### Next

- Native-speaker review of menu, settings, notification and schedule strings.
- Capture the tray menu and the dialogs at 125%/150% DPI.
- Live language switch for an open Settings window.

## 2026-11-09 — float latch, device abstraction and window sizing

### Goal

Make float mode start only after the battery reaches the configured limit, fix the clipped and undersized dialogs, and extend the application to devices and brands beyond HP.

### Work performed

1. Added `ChargePolicy`, `ChargeDecision` and `Engine.FloatActive`; float now latches only at the ceiling and holds until the resume point. Removed the faulty `FloatActive = decision.FloatActive && wasFloat || decision.FloatActive` expression and the stale-inhibit path that could stop charging below the target.
2. Added `IBatteryController`, `HpBios`, `GenericBatteryController`, `BatteryControllerFactory` and `DeviceInfo`. HP keeps charge control; every other vendor gets read-only monitoring and a logged fallback.
3. Updated the tray for three states: floating (teal), stopped/charging (orange/green) and monitoring (slate). The menu shows vendor/model and **Monitoring only**, disables charge items on non-HP hardware, and no longer treats an unsupported mode as an error on monitoring devices.
4. Enlarged and DPI-scaled the dialogs: Settings 780×980 (minimum 680×620, `AutoScroll`), schedule window 500×380, activity log 760×560. Added `UiLayout.Fit` to clamp windows to the working area.
5. Added the `Monitoring only` key to all 30 catalogs (151 keys each) and a monitoring note to the Settings battery card.
6. Added `tests/Test-FloatLogic.ps1` covering 13 charge/float decisions without hardware.
7. Wrote `docs/DEVICE_SUPPORT.md` and updated the README, application README, architecture, decisions, roadmap, project status and changelog.

### Verification

- Build: csc exit 0, `application.exe` 92,160 bytes.
- Float decisions: 13/13 OK.
- Schedule conflicts: 6/6 OK.
- UI polish: 11/11 OK.
- Settings save, conflict guard and restore: pass.
- Battery readings and capacity arithmetic: pass.
- Log rotation: pass.
- Icon contact sheet: pass.
- Locale inventory: 30 files, 151 keys each, no missing keys and no placeholder mismatches.
- Window measurement: Settings reported 780×585 client on the 1280×720 test desktop, i.e. the expected working-area clamp with scrolling; the design size is 780×980 on larger displays.
- Elevated restart: `tray pid=18396 alive=True`; `controller: HP HP ENVY x360 Convertible 13-ay0xxx (charge control)`; `tray icon added=True`; first tick `float=no control=full`.
- Hardware float activation was not exercised because AC was disconnected (64% on battery); the decision table covers that path.

### Limitations observed

- The tray, menu and dialogs were not visually inspected; behavior was measured through reflection tests.
- No non-HP hardware was available, so the generic controller was verified by code inspection and the shared battery reader, not on a second physical device.
- Non-English wording remains machine-generated with glossary corrections and needs native review.
- Charge control remains HP-only; other vendors are monitored.

### Next

- Native review of menu, settings, notification and schedule strings.
- Visual and DPI pass at 100%, 125%, 150% and 200% scaling.
- Split `Application.cs` into engine, controller, configuration and dialog files.
- Add vendor adapters only with documented interfaces and real-hardware verification.

## 2026-11-09 — localization, neutral structure and documentation

### Goal

Translate the tray application into 30 languages, make English the default with an Automatic system-language option, reorganize the project under neutral names, and update every project document in English.

### Work performed

1. Extracted 152 Arabic UI literals and built a curated English catalog.
2. Corrected ambiguous English terms before translation (charge limit, time window, activity log, light/dark theme, battery health).
3. Generated 30 locale files and added a glossary pass for ambiguous labels.
4. Added `src/Localization.cs`: 30 language definitions, native names, RTL flags, automatic Windows-language resolution, JSON loading, `T()`/`F()` and English fallback.
5. Replaced UI literals in `src/Application.cs` with `Loc.T`/`Loc.F`; fixed the three multiline strings that the automatic pass missed.
6. Added `language` to `interface.ini` and `UiSettings`; defaulted to `auto`; added a language selector to Settings; tied RTL to the language unless `direction` is explicit.
7. Moved the project into `src/`, `resources/`, `locales/`, `scripts/` and `tests/`; renamed data files to `settings.json`, `interface.ini`, `theme.ini`, `capacity.ini`, `application.log` and `application.previous.log`.
8. Added startup migration from the old data file names.
9. Updated build, start, restart, CLI and test scripts for the new layout.
10. Wrote the English README, application guide, agent instructions, architecture, status, roadmap, decisions, localization guide and changelog.

### Verification

- Build: csc exit 0, `application.exe` 88,064 bytes.
- Elevated restart: `tray pid=16740 alive=True`; log reports `tray icon added=True`, `tray started`, first policy `Limit 60% (resume 55%)`.
- Schedule conflicts: 6/6 checks.
- UI polish: 11/11 checks.
- Settings save/conflict guard/restore: pass.
- Battery readings and capacity arithmetic: pass.
- Log rotation: pass.
- Icon contact sheet: pass.
- Locale validation: 30 files, 150 keys each at that time (now 151), no missing keys, no placeholder mismatches.

### Limitations observed

- The final build was launched elevated on 2026-11-09 (process 16740); `application.log` reports `tray started`. Visual tray/menu/RTL rendering was not inspected.
- Non-English wording is machine-generated with glossary corrections and still needs native review.
- The settings window does not rebuild itself when the language changes; it must be reopened.
- HP WMI operations need elevation and a supported model; Smart App Control may force the PowerShell host fallback.

### Next

- Native review of menu, settings, notification and schedule strings.
- Live in-place language/direction switch for the open Settings window.
- Split `Application.cs` into engine, WMI, configuration and dialog files.
- Add a visual smoke test and a release checklist.

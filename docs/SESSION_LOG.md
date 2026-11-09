# Session log

## 2026-11-09 — SignPath Foundation signing path

### Goal

Enable a trusted Windows signature without requiring the maintainer to own a
code-signing certificate, while keeping the normal build usable with no
signing configuration.

### Work performed

1. Added the MIT `LICENSE` and the Cargo package license metadata required for
   the public project's SignPath Foundation application.
2. Added optional Windows steps for four SignPath requests: the tray/CLI
   binaries before MSI packaging, the MSI before the EXE is built, the detached
   Burn engine, and the final EXE. Each returned artifact is verified with
   `signtool verify /pa /all`.
3. Kept the existing PFX path as the fallback and made SignPath take precedence
   only when all seven `SIGNPATH_*` variables are present. The unsigned path
   still works when no signing configuration exists.
4. Added `docs/SIGNPATH.md` with the application steps, artifact configuration
   layout, required GitHub variables and Smart App Control verification notes.

### Verification

- Hosted run `42642577968` passed all seven packaging jobs with SignPath
  unconfigured; the optional SignPath steps were skipped and the unsigned path
  remained green. That run used the earlier three-request order. The current
  four-request workflow still needs its own hosted run.
- No SignPath account, project, artifact configuration or API token exists in
  this repository, so no signing request ran and no signed artifact was
  produced.

### Limitations observed

- The SignPath path is implemented but not exercised. Smart App Control will
  still block the unsigned artifacts until a real request completes.
- SignPath Foundation's publisher identity is **SignPath Foundation**, not a
  personal certificate subject. Approval and artifact signing are human steps.
- The interactive installer UI remains untested for the earlier reason: no
  interactive clean Windows VM was available.

### Next

- Apply to SignPath, configure the four artifact configurations and GitHub
  variables, then run and verify a signed build on Windows 11 with Smart App
  Control enforcement.

## 2026-11-09 — Windows single-EXE bootstrapper

### Goal

Provide a complete, professional Windows installer in EXE form, not only an
MSI, and verify that it installs and uninstalls the tray and CLI.

### Work performed

1. Added `packaging/windows/Bundle.wxs`, a per-machine WiX Burn bootstrapper
   around the existing tray+CLI MSI. It uses `WixStandardBootstrapperApplication`
   with the application icon, version display, hidden install-directory
   options, launch-after-install and Apps & Features registration.
2. Added the Bal extension (`WixToolset.BootstrapperApplications.wixext`
   5.0.2) and EXE build steps to the Windows matrix. The x86, x64 and ARM64
   jobs all produce an EXE; the x64 job installs it quietly, checks the payload
   and Start Menu shortcut, then uninstalls it.
3. Added a two-stage Authenticode path for the bundle when signing secrets
   exist: detach the Burn engine, sign it, reattach it, then sign the whole
   EXE. The signing steps were skipped because no certificate is configured.
4. Added same-version MSI upgrades so a newer branch snapshot can replace an
   installed `0.1.0` package instead of leaving duplicate products.
5. Added `packaging/windows/Test-WindowsUpgrade.ps1` and a Windows x64 CI step:
   install the published `v0.1.0` MSI, verify its CLI, install the new EXE over
   it, require the old product to disappear, require one visible Apps &
   Features entry, then uninstall and verify no BatteryGuard product remains.
6. The first upgrade run found two registered entries. The bundle now passes
   `ARPSYSTEMCOMPONENT=1` to its MSI; the next run confirmed one visible bundle
   entry and one hidden `SystemComponent` MSI.
7. Downloaded and inspected the final hosted x64 EXE locally:
   `BatteryGuard-0.1.0-snapshot.e281b0d-windows-x64.exe`, 1,309,331 bytes,
   SHA-256 `79b52985b64ee11011ed063c59bfc8e9d0f6119be7b540427c4920ad05d4d5aa`.
   Its file/product version is `0.1.0`; Authenticode reports `NotSigned`.

### Verification

- Hosted run `42638941970` passed all seven packaging jobs and produced 14
  installers: 3 EXE, 3 MSI, 6 Linux packages and 2 PKG.
- The Windows x64 job's **Package Windows EXE**, **Smoke-test Windows MSI**,
  **Smoke-test Windows EXE** and **Test Windows v0.1.0 upgrade** steps passed.
  The upgrade installed the published old MSI, verified its CLI, installed the
  new EXE, confirmed the old product was gone and one visible Apps & Features
  entry remained, then uninstalled cleanly.
- The final local EXE is saved under the ignored `dist/` directory for the user;
  it is not committed to Git.

### Limitations observed

- The interactive installer UI was not tested. This Windows 11 Home host has
  no Windows Sandbox/VM tools, and Application Control blocks the EXE with
  "An Application Control policy has blocked this file"; GitHub-hosted runners
  have no interactive desktop. Only the quiet install/upgrade/uninstall path is
  verified.
- The EXE is unsigned because no Authenticode certificate is configured. Do
  not claim a trusted publisher or SmartScreen reputation.
- The existing local `Program Files\BatteryGuard` installation was not replaced
  to avoid changing the user's current installation; the clean-runner CI test
  is the install/uninstall evidence.

### Next

- Sign the EXE and Burn engine with a real certificate and verify both
  signatures on a clean Windows VM.
- Exercise the interactive wizard on an interactive clean Windows VM and
  verify launch-after-install and the visible layout.

## 2026-11-09 — C# CI gate, optional signing and v0.1.0 installer checks

### Goal

Run the existing C# regression suite in CI, add native-signing paths that only
activate when credentials exist, and record honest runtime results for the
published `v0.1.0` packages instead of treating a build as a device test.

### Work performed

1. Added a Windows x64 CI step that seeds ignored `settings.json`,
   `interface.ini` and `application.log` files and runs eight
   hardware-independent C# tests: float logic, schedule conflicts, UI polish,
   settings, notification identity, log rotation, icon rendering and layout.
2. Added optional Authenticode signing for `application.exe`,
   `batteryguard.exe` and the MSI when `WINDOWS_CERTIFICATE_BASE64` and
   `WINDOWS_CERTIFICATE_PASSWORD` exist. The job signs the executables before
   WiX packages them and verifies every signature with `signtool`.
3. Added optional macOS Developer ID signing for the CLI, `productsign` for the
   PKG, `notarytool --wait`, stapler validation and `pkgutil` verification.
   All documented `MACOS_*` secrets are required together; a partial setup
   fails instead of silently shipping an unsigned package.
4. Updated `docs/RELEASE.md` with the secret names and the distinction between
   the always-on Sigstore attestation and the optional native signatures.
5. Tested the published `v0.1.0` assets where the environment allowed:
   - Windows: found an existing CLI-only `0.1.0` installation at
     `C:\Program Files\BatteryGuard\batteryguard.exe` (303,104 bytes). The
     x64 MSI hash is `B9F46ECD9A80452EECE2E2FD81F0D1C5F4DE28D7123CA4F0444BA206EEA325E5`
     and its Authenticode status is `NotSigned`. Executing the installed CLI
     is blocked by Application Control, so no runtime result was obtained. I
     did not remove the user's existing installation.
   - Linux: installed the x64 DEB in WSL2 Ubuntu 24.04 as root, ran
     `batteryguard --version` (`BatteryGuard portable core 0.1.0`), removed it,
     and confirmed the package and `/usr/bin/batteryguard` were gone. This is
     a real Linux kernel/userspace, not a physical Linux device or battery.
   - macOS: no macOS host was available; the PKG was not installed or run.

### Verification

- All eight C# tests passed locally; hosted run `42632698346` ran the same
  suite successfully on Windows x64.
- The new workflow YAML parses; the unsigned path remains the default.
- Hosted run `42632698346` passed all seven packaging jobs; the signing steps
  were skipped because no certificate secrets are configured.
- Linux DEB hash:
  `34FD580A9A6A90007152C47C5F2B09DFA6DAC9F5AA4326A132749571F490A371`.

### Limitations observed

- No Windows code-signing certificate or Apple Developer ID credentials are
  available, so the new signing paths are implemented but unverified.
- The Windows execution test is blocked by Application Control, and the
  existing installation prevented a clean install/uninstall test. I did not
  remove it without authorization.
- Linux coverage is WSL2 only; no physical Linux machine or battery was used.
- macOS runtime coverage is still missing.

### Next

- Configure the documented signing secrets and verify all three Windows files
  and the macOS PKG on a clean machine.
- Run v0.1.0 and the upcoming tray MSI on clean physical Windows, Linux and
  macOS devices.

## 2026-11-09 — Windows tray MSI and native package checks

### Goal

Give the existing Windows tray a professional installer with a Start Menu
shortcut and uninstall path, and exercise the native packages rather than only
building them. Keep the pre-existing `v0.1.0` release unchanged.

### Work performed

1. Added `packaging/windows/generate-locales.ps1`, which emits one WiX
   component per `battery/locales/*.json` file.
2. Rewrote `packaging/windows/Product.wxs` to install the C# tray, Rust CLI,
   application icon and locale catalogs. It creates an all-users Start Menu
   shortcut with `System.AppUserModel.ID=BatteryGuard.Tray` and an uninstall
   shortcut.
3. Updated CI to build the C# tray, stage its payload and generate the locale
   WiX source before invoking WiX 5.
4. Added an x64 MSI smoke test: install, check `application.exe`,
   `batteryguard.exe`, the icon, Arabic and Chinese catalogs, both Start Menu
   shortcuts, then uninstall.
5. Added native package checks: install the DEB and run `batteryguard
   --version` plus the AppImage, check the RPM metadata, and install and run the
   macOS PKG.

### Verification

- Hosted run [`42629998330`](https://github.com/Alaa91H/BatteryGuard/actions/runs/42629998330)
  passed all seven packaging jobs and produced the same 11 installer assets.
- The x64 MSI install, payload, Start Menu shortcut, uninstall shortcut and
  uninstall checks passed. The x86 and ARM64 MSIs built, but Windows Installer
  cannot install the ARM64 package on the x64 runner; the x86 package resolves
  under Program Files (x86).
- Linux x64/ARM64 installed the DEB and ran `BatteryGuard portable core 0.1.0`;
  the AppImage also ran. The RPM metadata check passed. macOS Intel/Apple
  silicon installed the PKG and ran the installed CLI.
- Earlier runs exposed `CommonProgramsFolder` (invalid in WiX 5) and the
  cross-architecture install limitation; both were corrected.

### Limitations observed

- No local link or Rust runtime test: this host still lacks the MSVC linker and
  Application Control blocks Cargo and the available GNU/lld linkers.
- No real Linux or macOS battery was available; hosted install checks are not
  hardware readings.
- No native Authenticode/notarization; only Sigstore build provenance.
- BIOS AC adapter input wattage was not available as a documented, readable
  field; the UI continues to show pack voltage and charge/discharge power.
- A UI Automation probe of a real notification did not find a visible toast on
  this desktop. `Test-AppIdentity` still verifies the shortcut and AUMID, not
  the banner label.
- No Linux/macOS widget or menu-bar UI was added.
- The new MSI is not in the published `v0.1.0` release.

### Next

- Tag a new version when the tray MSI is accepted, then verify it on a clean
  Windows VM and add native signing.
- Verify Linux/macOS packages and widgets on real hardware.
- Add a reliable interactive notification-banner check and a documented BIOS
  adapter-power source if one becomes available.

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
- Tag run [`42624635716`](https://github.com/Alaa91H/BatteryGuard/actions/runs/42624635716)
  completed successfully and published
  [`v0.1.0`](https://github.com/Alaa91H/BatteryGuard/releases/tag/v0.1.0) with
  exactly 11 assets: 3 MSI, 6 Linux packages and 2 PKG files. The tag points to
  commit `449245b`.
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

- Add native OS signing and clean-VM install tests in a later release-hardening
  pass. The current release carries Sigstore build provenance only.
- Run the released installers on real Windows, Linux and macOS hardware; no
  clean-VM install or hardware reading was performed for `v0.1.0`.

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

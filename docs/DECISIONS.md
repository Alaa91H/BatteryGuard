# Architecture decisions

## ADR-001 — English source keys, flat JSON catalogs

**Status:** accepted  
**Decision:** Author UI strings as `Loc.T("English source")`; store translations in `locales/<code>.json` as `{ "English source": "translation" }`.  
**Why:** One readable source of truth, deterministic fallback and no generated resource identifiers.  
**Consequence:** Changing an English key invalidates its translations. Prefer stable, unambiguous source sentences.

## ADR-002 — English is the default and the fallback

**Status:** accepted  
**Decision:** `language=auto` is the shipped default; automatic resolution falls back to English when the Windows language is unsupported.  
**Why:** The app must be usable on any Windows installation and must not fail when a catalog is missing.  
**Consequence:** A partially translated catalog is safe; missing keys render in English.

## ADR-003 — 30 language catalogs

**Status:** accepted  
**Decision:** Ship `en, ar, es, fr, de, pt, it, ru, zh-CN, zh-TW, ja, ko, hi, bn, ur, fa, tr, nl, pl, uk, ro, el, cs, sv, da, fi, he, th, vi, id`.  
**Why:** Broad coverage of major world languages, including the user's Arabic requirement and both Chinese scripts.  
**Consequence:** Catalog size is small (JSON), but translation maintenance is ongoing.

## ADR-004 — RTL follows the language unless explicitly overridden

**Status:** accepted  
**Decision:** Arabic, Urdu, Persian and Hebrew set RTL; `interface.ini` may override with `rtl` or `ltr`.  
**Why:** Language and direction normally travel together; an override covers mixed-language preferences and testing.  
**Consequence:** The menu and dialogs use `UiSettings.Rtl`; changing language in Settings takes effect after reload/reopen.

## ADR-005 — Neutral project and data names

**Status:** accepted  
**Decision:** Use `src/`, `resources/`, `locales/`, `scripts/`, `tests/`, `application.exe`, `settings.json`, `interface.ini`, `theme.ini`, `capacity.ini`, `application.log`. Keep the display name BatteryGuard and the namespace `BatteryGuardTray`.  
**Why:** Standard, predictable layout without product/version in paths; avoids churn when the product name changes.  
**Consequence:** Existing scripts and data names needed a migration layer.

## ADR-006 — Migrate old data files on startup

**Status:** accepted  
**Decision:** `Program.MigrateLegacyDataFiles()` moves `BatteryGuard.config.json`, `ui.txt`, `theme.txt`, `capacity.txt`, `batteryguard.log` and `batteryguard.previous.log` to the neutral names when the new file is absent.  
**Why:** Preserve settings and logs for existing installations.  
**Consequence:** Migration is best-effort and runs before the tray starts; it never overwrites a new file.

## ADR-007 — Machine translation with a curated glossary

**Status:** accepted, with review pending  
**Decision:** Generate non-English catalogs from the English source, then apply explicit context translations for ambiguous battery labels (charge limit/control, light/dark theme, time window).  
**Why:** Full native translation was not available in the implementation environment; the glossary prevents the worst literal errors (billing “charge”, illumination “light”, generic “window”).  
**Consequence:** The catalogs are structurally complete but not native-reviewed. Treat wording changes as a review task, not a code regression.

## ADR-008 — No external runtime dependencies

**Status:** accepted  
**Decision:** Use only .NET Framework, Win32, `System.Management` and WinForms that ship with Windows.  
**Why:** The app must run on locked-down corporate machines and on this SAC-enabled host.  
**Consequence:** No modern UI toolkit or package manager; the Win32/WinForms code is more verbose.

## ADR-009 — Float starts only at the charge limit

**Status:** accepted 2026-11-09  
**Decision:** `ChargePolicy.Evaluate` is a pure decision table. Float is latched only when the measured charge is at or above the ceiling. Below the ceiling the engine never inhibits charging for float and releases any stale inhibit so charging reaches the limit. While floating, inhibit is held until the resume point, then auto charging restarts.  
**Why:** The product requirement is explicit: charge fully to the limit, then float. The previous condition could latch on an existing inhibit below the target and keep inhibiting early.  
**Consequence:** Float behavior is testable without WMI (`Test-FloatLogic.ps1`, 13 cases), and the tray must render the latch from `Engine.FloatActive` rather than inferring it from the firmware mode.

## ADR-010 — HP charge control, cross-brand monitoring

**Status:** accepted 2026-11-09  
**Decision:** Abstract charge control behind `IBatteryController`. `BatteryControllerFactory` selects `HpBios` only for HP/Hewlett/HPE and falls back to `GenericBatteryController`, which is read-only and reports `CanControlCharge = false`. The tray and Settings show **Monitoring only** and disable charge actions.  
**Why:** Lenovo, Dell, ASUS, MSI and other vendors use ACPI/EC or private utilities; no stable documented Windows WMI write path exists. Guessing commands could damage battery firmware.  
**Consequence:** Monitoring works on every vendor; charge writes remain limited to verified HP hardware. Adding a vendor requires a new adapter, capability probe and real-hardware read-back verification.

## ADR-011 — Dialogs pin actions and scroll content

**Status:** accepted 2026-11-09  
**Decision:** Keep the Settings action footer and the schedule Save/Cancel buttons outside a scrolling content area, let the activity-log action bar wrap, and lower a dialog's `MinimumSize` when the working area is too small. The Settings root uses a 520 px content floor and reflows to one column below 900 px; the schedule layout narrows to 360 px and wraps its note.
**Why:** Small working areas can be shorter than the design sizes. Burying Save/Cancel inside a scroll region makes the primary action hard to reach, while fixed columns clip labels and controls.
**Consequence:** The footer is always visible, every field remains reachable, and `Test-Layout.ps1` asserts the behavior at representative sizes and at simulated 100%/125%/150% DPI without hardware. The tested 100%, 125% and 150% states have no horizontal scrollbar; the 150% Settings content scrolls vertically.

## ADR-012 — Show pack voltage and charge/discharge power

**Status:** accepted 2026-11-09  
**Decision:** Read `BatteryStatus.Voltage` (mV) and `BatteryStatus.ChargeRate` / `DischargeRate` (mW). Show them as `11.8 V · 0.0 W` in the tray tooltip, tray menu, status balloon and Settings battery card, and log the raw values as `v=`/`p=` in the tick line. Omit voltage when it is not positive; show zero watts when voltage confirms a reading; format one decimal with invariant culture.  
**Why:** These are the generic Windows battery readings, so they work across vendors without new WMI assumptions or a new localized UI string. A zero rate is meaningful while the charger holds the battery idle and makes the reading visibly complete.  
**Consequence:** The tooltip gets the electrical reading near its start because the native tooltip is capped at 127 characters. The values describe the battery pack, not the AC adapter's input rail.

## ADR-013 — Stable AUMID plus Start Menu shortcut for notifications

**Status:** accepted 2026-11-09  
**Decision:** Set the process AppUserModelID to `BatteryGuard.Tray` before creating the tray window and maintain `%APPDATA%\Microsoft\Windows\Start Menu\Programs\BatteryGuard.lnk` with `System.AppUserModel.ID=BatteryGuard.Tray`. Target the compiled executable, or the PowerShell host with `start.ps1 -NoElevate`, and set the icon and description.  
**Why:** A desktop process cannot change its displayed notification name with the notification title alone. Windows requires a matching Start Menu shortcut and AUMID for the app label; the PowerShell-hosted fallback otherwise appears as **PowerShell**.  
**Consequence:** The app writes one Start Menu shortcut for the current user. `Test-AppIdentity.ps1` verifies it without elevation; the notification banner itself still needs a visual check on a clean notification area.

## ADR-014 — A shared Rust core beside the Windows tray

**Status:** accepted 2026-11-09  
**Decision:** Start the cross-platform work as a dependency-free Rust library and CLI under `portable/`, leaving the C# Windows application intact. Use `rustc`/Cargo with no third-party crates and platform modules behind `cfg(target_os)`.  
**Why:** The policy and formatting are pure and portable, while Windows charge control is firmware-specific. A separate core allows Windows, Linux and macOS to share behavior without risking the working tray application or inventing cross-platform firmware writes.  
**Consequence:** The core is not linked into the tray yet. Windows, Linux and macOS backends are read-only; installers are now produced by CI, while widgets and real hardware runtime verification remain later phases.

## ADR-015 — Read-only portable backends, fail closed

**Status:** accepted 2026-11-09  
**Decision:** The Windows backend uses PowerShell/WMI read-only; Linux reads `power_supply` sysfs; macOS runs `pmset -g batt`. A missing measurement becomes `None`, and no backend writes charge state.  
**Why:** These interfaces are present across architectures and distributions without bundling vendor SDKs. Kernel and firmware charge-threshold interfaces vary too much to write safely without per-device confirmation.  
**Consequence:** The portable core supports monitoring everywhere it can read a battery, but charge control stays on the existing HP Windows path until a documented, tested controller exists.

## ADR-016 — One tag-gated workflow for every installer

**Status:** accepted 2026-11-09
**Decision:** Use a single GitHub Actions workflow for validation, native builds, packaging and release. Build all installers on every push, upload them as workflow artifacts, and create a GitHub Release only for a tag that exactly matches the Cargo version. Restrict release assets to installer extensions.
**Why:** Separate packaging workflows drift in versions and permissions, while publishing individual files invites raw binaries and debug artifacts into a release. A single matrix gives one reproducible path for every platform, and the tag/version check ties the published filenames to the source version.
**Consequence:** A normal push spends CI time building every installer but publishes nothing. `v0.1.0` is the first valid tag for Cargo `0.1.0`.

## ADR-017 — Windows MSI bundles the tray and CLI

**Status:** accepted 2026-11-09
**Decision:** Build a per-machine WiX MSI containing the C# tray, the Rust CLI, the application icon, all 30 locale catalogs, an all-users Start Menu shortcut with `System.AppUserModel.ID=BatteryGuard.Tray`, and an uninstall shortcut. Keep the Linux and macOS packages CLI-only. Install/uninstall the x64 MSI in CI; build x86 and ARM64 without cross-installing them.
**Why:** The Windows application is the primary product, so a Windows installer that shipped only the CLI would be misleading. A single MSI keeps the tray and CLI versions aligned. Cross-architecture MSI installation is rejected by Windows Installer on the x64 runner, and the x86 package correctly targets Program Files (x86), so those packages need native test hosts rather than a fake pass.
**Consequence:** The new MSI is branch-built but not part of the published `v0.1.0` release. Linux/macOS widgets, BIOS adapter wattage and a banner-level notification test remain unverified.

## ADR-019 — Ship a single-EXE Burn bootstrapper for Windows

**Status:** accepted 2026-11-09
**Decision:** Keep the MSI as the package of record and add a per-machine WiX Burn EXE bootstrapper around it. The EXE uses `WixStandardBootstrapperApplication`, the application icon, version display, suppressed install-directory options, launch-after-install and Apps & Features registration. Build it for x86/x64/ARM64; install/uninstall the x64 bundle in CI.
**Why:** The MSI is appropriate for managed deployment, while most end users expect a single setup EXE with a familiar wizard and an uninstall entry. Wrapping the same MSI avoids a second payload definition and keeps the tray/CLI versions aligned. The bundle is built from the same MSI as the managed-deployment path.
**Consequence:** Branch runs now produce 14 installers instead of 11. The clean-runner upgrade from the published `v0.1.0` MSI passes, including removal of the old product and one visible Apps & Features entry; the MSI remains a hidden `SystemComponent` behind the bundle. The interactive wizard and physical clean VM remain untested. The MSI remains available for Group Policy and managed deployment.

## ADR-021 — Evidence-gated controller providers

**Status:** accepted 2026-11-09
**Decision:** Represent laptop charge control as an embedded `DeviceProfile` with a `DeviceFingerprint`, one or more capabilities, an evidence status and a provider. Only profiles with `LabVerified` or `FieldVerified` status may register a charge writer. Every production write goes through `WriteGuard`, which permits only auto and inhibit, requires AC for inhibit, performs one read-back and rolls back once on mismatch. `IWmiGateway` isolates the HP transport so contract tests can use replayed responses.
**Why:** Vendor WMI/ACPI/EC interfaces differ by model and BIOS, and a detected class is not proof that a write is safe. The previous HP-only branch could not represent fixed-80% or start/stop policies without inventing a universal slider, and an unverified adapter could damage firmware.
**Consequence:** Acer, Lenovo and Dell are candidate profiles only in this build; ASUS, MSI and other unknown devices remain monitoring-only. The read-only probe, simulator and hardware validation protocol can collect evidence, but no candidate writer is enabled until two independent devices pass read-back, sleep/resume, reboot, unplug and restore checks. The HP path remains the only field-verified writer.

## ADR-022 — Tag-gated release with built-in GitHub permissions

**Status:** accepted 2026-11-10
**Decision:** Keep `.github/workflows/ci.yml` as the only build and release workflow. Validate `portable/Cargo.toml` in `prepare`, build every native package in `build`, and publish only for a tag that exactly matches the Cargo version. Use `contents: read` and `actions: read` at workflow level, with `contents: write` only in the release job. Require no repository secret or external release service.
**Why:** One workflow keeps versions, permissions and asset filtering in one reviewable place. A tag-gated release prevents branch builds from publishing, while the minimum permissions keep the release path independent of account-level services.
**Consequence:** Every push spends CI time on the full installer matrix. A normal branch push uploads artifacts but never creates a release. A release requires the version bump, matching documentation, a green branch run, and the exact `v` tag.

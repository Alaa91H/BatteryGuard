# Roadmap

## Now

- **Hardware smoke tests.** Hosted CI now links, tests and runs the CLI on six native runners; run it against real batteries on Windows, Linux and macOS and record the readings. Do not treat a hosted build as a hardware test.
- **Native signing.** Add Windows Authenticode and Apple Developer ID/notarization when certificates and a secret-management policy exist. Keep the current Sigstore provenance attestation as an additional layer, not a substitute.
- **Native translation review.** Have the 30 catalogs reviewed by speakers, starting with the visible menu, settings labels and notification text. Keep the English source keys stable during review.
- **Live language switch.** Rebuild or reload the open Settings window when the language changes so RTL/LTR and labels update immediately.
- **Release checklist.** Build, run the hardware-independent suite, launch elevated, inspect the tray and settings windows in LTR and RTL, and verify log rotation.
- **DPI visual pass.** The three dialogs are captured at 100% in light/dark and English/Arabic; repeat at 125% and 150%.

## Done

- **One tag-gated CI pipeline.** Added `.github/workflows/ci.yml` to build Windows x86/x64/ARM64 MSI, Linux x64/ARM64 DEB/RPM/AppImage and macOS Intel/Apple-silicon PKG packages; attest every installer with GitHub/Sigstore provenance; upload branch artifacts; and publish only for a `v*` tag matching `portable/Cargo.toml`. Hosted run `42623422341` passed all seven packaging jobs with 11 installers and no warnings. Tag run `42624635716` published [`v0.1.0`](https://github.com/Alaa91H/BatteryGuard/releases/tag/v0.1.0) with exactly those 11 assets.

- **Portable Rust core (phase 1).** Added the shared battery model, formatting, 13-case policy, read-only Windows/Linux/macOS backends, text/JSON/watch CLI, build/test scripts and a 12-target metadata check. The 12 Windows/Linux/macOS targets type-check; no binary or runtime test was possible on this host.
- **Voltage and power readout.** The tooltip, tray menu, status balloon and Settings battery card show pack voltage and charge/discharge power from `BatteryStatus`; the real idle reading was `11.8 V · 0.0 W`.
- **Notification identity.** The process AUMID and a matching Start Menu shortcut make Windows label notifications **BatteryGuard**, including the PowerShell-hosted fallback.
- **Adaptive window layout.** Settings, schedule and log dialogs now pin their action bars, scroll long content, wrap narrow toolbars and lower their minimum sizes on small working areas; `Test-Layout` covers ten client sizes.
- **Split `Application.cs`.** Engine, WMI, configuration, theme, native helpers, tray and dialogs now live in focused `src/` modules; scripts and tests enumerate `src/*.cs`.
- **Dialog RTL and clipping pass.** Settings, schedule and log were inspected in light/dark and English/Arabic; row order, numeric labels, table columns, card heights and log direction were corrected.
- **Translation terminology pass.** Charge, health and schedule labels were corrected across the 30 catalogs; placeholder and key coverage validation passes.

## Next

- **Linux/macOS widgets.** Add a tray or menu-bar interface after the read-only backends are verified on real hardware. The Windows tray remains the active UI.
- **Distribution hardening.** Add native OS code signatures and a documented upgrade/uninstall test on clean VMs. The current workflow publishes installers with Sigstore build provenance only.
- **Notification banner check.** Trigger a status balloon on a clean notification area and confirm the Windows app label visually.
- **Localization QA tooling.** Detect untranslated values, wrong placeholders, text expansion and RTL truncation. Add a catalog coverage report per language.
- **UI automation.** Add a repeatable smoke test that opens the menu and dialogs and checks visible labels without depending on Arabic/English assertions.
- **DPI matrix check.** Measure all three dialogs at 100%, 125%, 150% and 200% scaling and assert that no control falls outside the working area.
- **Config schema version.** Add a `schemaVersion` field to `settings.json` and a migration path for future fields.
- **Installer and signing.** Produce a signed per-user installer or a documented portable layout; keep the Smart App Control fallback.
- **Log language.** Keep diagnostic lines stable and English even when the interface is localized.

## Later

- **Verified vendor adapters.** Add a Lenovo, Dell or ASUS adapter only after a documented interface, real test hardware and read-back confirmation exist. Keep the monitoring-only fallback for everything else.
- **Per-user data directory.** Move generated data to `%LOCALAPPDATA%` if portable/root configuration becomes a limitation.
- **Accessibility.** Keyboard navigation audit, screen-reader labels and high-contrast verification for owner-drawn menus.
- **Localization contribution workflow.** Document how to add a language, validate placeholders and run the coverage checks.

## Non-goals

- Cloud accounts, telemetry or a network service.
- Forced discharge or battery calibration.
- Bypassing firmware restrictions, poking EC/ACPI registers or writing undocumented modes outside auto/inhibit.
- Replacing the WSL provisioning project.

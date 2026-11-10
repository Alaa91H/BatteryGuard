# Architecture

## Process model

BatteryGuard is one .NET Framework 4.x process. There is no service and no network listener.

- A message-only Win32 window owns the tray icon and receives `WM_TIMER`, tray callbacks, `WM_REFRESH`, theme changes and shutdown.
- `Shell_NotifyIcon` displays the icon; a native popup menu provides status and actions.
- WinForms is used only for the Settings, Add/Edit schedule window and Activity log dialogs.
- `System.Management` talks to the HP WMI provider through `IWmiGateway` and `IChargeController`. Other vendors receive a read-only controller.
- All production charge writes pass through `WriteGuard`, which allows only auto and inhibit, requires AC for inhibit, and verifies each write with a read-back.
- A mutex prevents two tray instances.
- `AppIdentity` sets the process AppUserModelID to `BatteryGuard.Tray` before the tray window is created and maintains a matching Start Menu shortcut. Windows uses that identity for notifications even when the UI is hosted by `powershell.exe`.

When Smart App Control blocks the executable, `scripts/start.ps1` compiles the same `src/*.cs` files with `Add-Type` inside `powershell.exe` and invokes `Program.Main` by reflection. The UI and behavior are identical.

## Components

| Component | Responsibility |
| --- | --- |
| `Program` | Paths, startup, CLI flags, log rotation, legacy data migration, mutex. |
| `TrayApp` | Window procedure, tick, tray icon, menu, notifications, settings/log windows. |
| `Engine` | Reads battery/controller state, evaluates the charge decision, applies presets and schedules. |
| `ChargePolicy` / `ChargeDecision` | Pure float/charge decision table, testable without WMI. |
| `IBatteryController` | Legacy contract for vendor adapters: read mode, set auto, set inhibit. |
| `IChargeController` | Capability-aware contract: fingerprint, profile, `RequestInhibit`, `RequestAuto`, `RequestLimit` and a structured result. |
| `DeviceFingerprint` | Read-only SMBIOS/WMI identity: manufacturer, product, board, BIOS, family and SKU; no serial number. |
| `DeviceProfile` / `DeviceProfileCatalog` | Embedded profile, interface, capabilities, evidence status and wildcard matching. |
| `ControllerCapabilities` | `AutoInhibit`, `FixedThreshold`, `StartStopThreshold` or `MonitoringOnly`, with allowed limits. |
| `WriteGuard` | Single safety gate: mode/value allow-list, AC check, threshold range, read-back and one rollback on mismatch. |
| `IControllerProvider` | Ordered provider registry; HP is the only write-capable provider in this build. |
| `HpBios` | HP `hpqBIntM` WMI read/write through `IWmiGateway`, with a pre-transport 0x00/0x05 allow-list and the legacy setters retained for hardware tests. |
| `HpBiosWmiGateway` / `SimulatedWmiGateway` | Real and hardware-free WMI transports for the HP protocol. |
| `GenericBatteryController` | Monitoring-only adapter for non-HP and candidate hardware. |
| `BatteryControllerFactory` | Profile detection, provider registration and fail-closed generic fallback. |
| `DeviceInfo` | Cached device fingerprint and matched profile. |
| `BatteryInfo` | Battery percentage, capacities, health, pack voltage, charge/discharge power, cycles and temperature. |
| `AppIdentity` | Process AUMID and Start Menu shortcut used for the Windows notification label. |
| `GuardConfig` | `settings.json` model and persistence. |
| `WindowRule` / `ScheduleRules` | Schedule windows, overlap detection and localization-aware descriptions. |
| `UiSettings` | `interface.ini`: language, direction, thresholds, notifications, icon options. |
| `ThemeSettings` / `UiTheme` | Theme persistence and shared colors. |
| `UiLayout` | Clamps DPI-scaled dialogs to the working area and lowers their minimum size when the display is smaller. |
| `Loc` | Language list, auto detection, JSON catalog loading, `T`/`F`, RTL metadata. |
| `SettingsForm` | Charge, schedule, notification and interface/language editing. |
| `WindowRuleForm` | Add/edit a time window with full-day handling. |
| `LogForm` | Last 300 activity lines, refresh, export. |

## Tick flow

1. `TrayApp.Tick()` calls `Engine.Tick(true)`.
2. The engine reads the current firmware mode through the controller, refreshes battery readings and resolves the active policy (first matching schedule window, otherwise the global ceiling).
3. When charge control is unavailable, the engine clears `FloatActive` and returns immediately; the tray renders the monitoring state.
4. `ChargePolicy.Evaluate` returns an action (`None`, `Auto`, `Inhibit`) and the next latch value:
   - standard charging, no ceiling, or unplugged: release inhibit and clear float;
   - below the ceiling: no float; release a stale inhibit so charging reaches the limit;
   - at/above the ceiling: inhibit; latch float only when float mode is on;
   - below the ceiling while floating: keep inhibit until the resume point, then restore auto.
5. `Engine` applies the action only when `apply` is true. `WriteGuard` checks capabilities and AC state, writes once, confirms with a mode read-back and rolls back once on mismatch. `FloatActive` is updated from the decision on every tick, including read-only ticks.
6. `TrayApp` updates the icon, tooltip and menu, including the voltage/power reading when available, then checks full/low/health alerts, schedule conflicts and float drain warnings.
7. `WM_TIMER` repeats the cycle; `WM_REFRESH` reloads `settings.json` and `interface.ini` after a settings save.

## Data flow

```text
settings.json ─┐
interface.ini ─┼─> GuardConfig / UiSettings / Loc
theme.ini ─────┘          │
                          v
BatteryInfo + IBatteryController -> Engine + ChargePolicy -> TrayApp -> icon/menu/notifications
                          │
                          v
                    application.log
```

`capacity.ini` caches the design capacity reported by `powercfg` when WMI does not expose it.

## Device layer

`BatteryControllerFactory.Create()` builds a `DeviceFingerprint` and matches it against `DeviceProfileCatalog`:

- HP/Hewlett/HPE matches the field-verified HP profile. `HpBios` is constructed through `HpBiosWmiGateway`; a constructor or WMI failure logs the reason and falls through.
- Acer, Lenovo and Dell match candidate profiles. They are logged with their interface and capability, but `CanWrite` is false, so no provider is created.
- Everything else uses `GenericBatteryController`, `CanControlCharge = false`, `ReadMode()` = `Unsupported` and a `MonitoringOnly` capability.

`Engine` exposes `CanControlCharge`, `Capabilities` and `ControllerProfile`; the tray uses them for icon color, badge, float warnings, menu enablement and the `Monitoring only` label. `ControllerCapabilities.DisplayName` is the single capability description used by the tray and Settings. `SettingsForm` derives its charge-control layout from the matched profile: `AutoInhibit` gets the full limit/resume controls, fixed and start-stop capabilities get a capability-only card with no 50–100% slider, and a non-writable profile gets **Monitoring only**. This keeps vendor detection out of the UI and prevents accidental writes on unsupported hardware. `WriteGuard` is the only production write path.

## Portable core (phase 1)

The `portable/` directory is a separate, dependency-free Rust core. It is not linked into the C# tray yet; it establishes the shared model and read-only backends for the cross-platform phase.

| Module | Responsibility |
| --- | --- |
| `src/model.rs` | Battery percentage, voltage, rates, capacity, cycles, temperature, derived power/health/minutes and errors. |
| `src/format.rs` | The shared `11.8 V · 6.5 W` and duration formats. |
| `src/policy.rs` | Platform-neutral charge/float policy with the 13 Windows decision cases. |
| `src/platform/windows.rs` | Read-only PowerShell/WMI provider with a fixture-tested parser. |
| `src/platform/linux.rs` | Read-only `/sys/class/power_supply` provider with a fixture-tested parser. |
| `src/platform/macos.rs` | Read-only `pmset -g batt` provider with fixture-tested parsers. |
| `src/main.rs` | Text/JSON/watch CLI. |

All platform modules are behind `#[cfg(target_os)]`; the library, test harness and CLI type-check on 12 Windows/Linux/macOS targets. The backends do not write firmware. A future controller adapter must probe capabilities and fail closed to monitoring. The existing Windows HP controller remains the only charge writer.

## CI and installer pipeline

`.github/workflows/ci.yml` is the single build path:

1. `prepare` reads `portable/Cargo.toml`, validates a three-part version and, for a tag, requires `refs/tags/v<version>`. It derives a snapshot suffix for branch builds.
2. Seven native jobs build the CLI for Windows x86/x64/ARM64, Linux x64/ARM64 and macOS Intel/Apple silicon. Linux uses static musl targets. Every runnable target runs the Rust tests and `batteryguard --version`; Windows ARM64 is cross-compiled but not executed on the x64 hosted runner. The Windows x64 job also runs the hardware-independent C# suite, including the controller foundation test.
3. The packaging jobs create the EXE, MSI, DEB, RPM, AppImage and PKG files. The Windows job also builds the C# tray, generates the 30 locale components and stages the tray, CLI, icon and catalogs; the x64 MSI and EXE are installed, checked for payload and Start Menu/uninstall shortcuts, then removed. The same job installs the published `v0.1.0` MSI, upgrades it with the new EXE, verifies the old product disappeared and exactly one visible Apps & Features entry remains, then uninstalls. The EXE is a WiX Burn bootstrapper around the MSI, with the standard installer UI, version display, launch-after-install and Apps & Features registration. Linux and macOS jobs install their DEB and PKG and run the installed CLI as a smoke test.
4. The Windows job builds the tray/CLI binaries, MSI and EXE; the macOS job builds the PKG. The release job downloads the artifacts, filters by the installer extension allowlist and creates a GitHub Release only for a matching tag; a branch event stops before publication.

## Window sizing

- Settings: 980×620 design size, minimum 720×480, `AutoScaleMode.Dpi`. At 900 px and wider the battery, charge/schedule and notifications/interface cards use two columns; below 900 px they stack in one scrollable column with a 520 px content floor and no horizontal scrolling. The Save/Cancel/Test footer is docked outside the scroll area, so it stays visible. The interface card places Language above Appearance and shows the installed version at the bottom.
- Schedule window: 500×350 fixed dialog, minimum 440×350, `AutoScaleMode.Dpi`. Its content panel scrolls, the layout narrows to 360 px, the note wraps, and the Save/Cancel buttons stay in a 56 px pinned bar.
- Activity log: 760×560, minimum 520×360, `AutoScaleMode.Dpi`. The action bar is auto-sized and wraps its status and buttons onto a second row on narrow windows.
- `UiLayout.Fit` clamps each form to `Screen.WorkingArea - 32` after layout and lowers `MinimumSize` first when the display cannot fit it. `SettingsForm.OnShown` repeats fit/footer/root layout twice for DPI-scaled windows, then the card columns and interface rows keep their content inside the card. At 100% the Settings window measures 980×620 client with a 60 px pinned footer and a 554 px root. `Test-Layout` also builds all three dialogs at 125% and 150% in English and Arabic with scaled bounds and fonts: every nested control stays inside its parent, the 150% Settings root scrolls vertically, and no tested state has a horizontal scrollbar. These are layout simulations, not native 125%/150% screenshots.

## Localization

- The `src/` modules contain no user-facing Arabic literals. UI text is `Loc.T("English source")` or `Loc.F("Template {0}", ...)`.
- `src/Localization.cs` defines the 30 supported codes, native names and RTL flags.
- `language=auto` resolves the Windows user default UI language through `GetUserDefaultUILanguage` (the tray may be hosted by a process with a different `CurrentUICulture`): `zh-Hans/Hant` maps to `zh-CN`/`zh-TW`; `iw`/`in` normalize to `he`/`id`; unsupported languages fall back to English.
- `locales/<code>.json` is a flat map keyed by the exact English source. Missing keys return the source string.
- `UiSettings.Rtl` uses an explicit `direction` override, otherwise the current language's RTL flag.
- English is not loaded from a catalog at runtime; `Loc.T` returns the source string directly.

## File responsibilities

| Path | Role |
| --- | --- |
| `src/Program.cs` | Entry point, paths, startup, CLI, log rotation, migration and mutex. |
| `src/TrayApp.cs` | Window procedure, tick, tray icon, menu, notifications and dialog launch. |
| `src/AppIdentity.cs` | Process AUMID and Start Menu shortcut for the notification identity. |
| `src/Engine.cs` | Battery/controller state, charge decisions, presets, schedules and notifications state. |
| `src/Controllers.cs` | Fingerprint, profiles, capabilities, provider contract, `WriteGuard`, WMI gateway and simulator. |
| `src/Wmi.cs` | Battery readings, HP `hpqBIntM` controller, generic monitoring controller and provider factory. |
| `src/Config.cs` | `settings.json`, `interface.ini`, schedule rules, UI settings and autostart. |
| `src/Theme.cs` | Theme persistence, shared colors, owner-drawn controls and the dual-range slider. |
| `src/Dialogs.cs` | Settings, Add/Edit schedule window and activity log. |
| `src/Native.cs` | Win32 P/Invoke, icon rendering and popup-menu helpers. |
| `src/Localization.cs` | Runtime language support. |
| `resources/application.manifest`, `application.ico` | Build resources, including DPI awareness. |
| `locales/*.json` | 30 translation catalogs. |
| `scripts/build.ps1` | csc build. |
| `scripts/start.ps1` | Elevation, exe preference, in-memory fallback. |
| `scripts/restart.ps1` | Stop the launcher and start it again. |
| `scripts/control.ps1` | Hardware/CLI operations. |
| `tests/*.ps1` | Regression and hardware checks. |
| `packaging/windows/Product.wxs` | Per-machine WiX MSI: tray, CLI, locales, Start Menu and uninstall shortcuts. |
| `packaging/windows/generate-locales.ps1` | Generates the WiX locale component group from `battery/locales/`. |
| `settings.json`, `interface.ini`, `theme.ini`, `capacity.ini` | Local data. |
| `application.log`, `application.previous.log` | Activity log and archive. |

## RTL layout

- Forms set `RightToLeft` and `RightToLeftLayout` from the language or the explicit `direction` override.
- Child `FlowLayoutPanel` rows keep a logical `LeftToRight` flow because WinForms mirrors the row inside an RTL form; setting `RightToLeft` on both levels reverses the order twice.
- The schedule `ListView` uses `RightToLeftLayout` so its columns read right-to-left; the activity log body stays LTR for readable timestamps and paths.
- The tray menu uses `MFT_RTL` and `TPM_RIGHTALIGN` when the interface is RTL.

## Security and safety

- HP WMI writes require elevation; the app does not store credentials.
- No network access and no telemetry.
- Charge mode is restricted to auto and inhibit; forced discharge is never requested. `WriteGuard.IsSafeMode` rejects every other mode before a transport call.
- Production writes are capability-gated, AC-gated for inhibit, read-back confirmed and rolled back once on mismatch.
- Candidate profiles are read-only; a WMI class or probe result cannot enable a writer.
- Non-HP and unsupported HP hardware fails closed to monitoring.
- The launcher only runs local source/exe and local scripts.
- The mutex and single-instance guard prevent concurrent tray policies.

## Release path

`.github/workflows/ci.yml` is the only workflow. `prepare` validates the
three-part version in `portable/Cargo.toml` and rejects a tag that does not
match it exactly. `build` runs the seven native packaging jobs, tests the Rust
core and the Windows C# suite, and uploads installer artifacts. `release` runs
only for a matching `v*` tag, verifies the installer allow-list, and publishes
the GitHub Release.

The workflow root has `contents: read` and `actions: read`; only the release
job raises `contents: write`. No repository secret or external release service
is required. A branch build never publishes, and a tag build cannot bypass the
native test and packaging jobs.

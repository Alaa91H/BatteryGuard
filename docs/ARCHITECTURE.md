# Architecture

## Process model

BatteryGuard is one .NET Framework 4.x process. There is no service and no network listener.

- A message-only Win32 window owns the tray icon and receives `WM_TIMER`, tray callbacks, `WM_REFRESH`, theme changes and shutdown.
- `Shell_NotifyIcon` displays the icon; a native popup menu provides status and actions.
- WinForms is used only for the Settings, Add/Edit schedule window and Activity log dialogs.
- `System.Management` talks to the HP WMI provider through `IBatteryController`. Other vendors receive a read-only controller.
- All charge writes are limited to auto (`0x00`) and inhibit (`0x05`).
- A mutex prevents two tray instances.
- `AppIdentity` sets the process AppUserModelID to `BatteryGuard.Tray` before the tray window is created and maintains a matching Start Menu shortcut. Windows uses that identity for notifications even when the UI is hosted by `powershell.exe`.

When Smart App Control blocks unsigned executables, `scripts/start.ps1` compiles the same `src/*.cs` files with `Add-Type` inside `powershell.exe` and invokes `Program.Main` by reflection. The UI and behavior are identical.

## Components

| Component | Responsibility |
| --- | --- |
| `Program` | Paths, startup, CLI flags, log rotation, legacy data migration, mutex. |
| `TrayApp` | Window procedure, tick, tray icon, menu, notifications, settings/log windows. |
| `Engine` | Reads battery/controller state, evaluates the charge decision, applies presets and schedules. |
| `ChargePolicy` / `ChargeDecision` | Pure float/charge decision table, testable without WMI. |
| `IBatteryController` | Contract for vendor adapters: capability, read mode, set auto, set inhibit. |
| `HpBios` | HP `hpqBIntM` WMI read/write with signature and read-back. |
| `GenericBatteryController` | Monitoring-only adapter for non-HP hardware. |
| `BatteryControllerFactory` | Vendor detection and safe HP-to-generic fallback. |
| `DeviceInfo` | Cached `Win32_ComputerSystem` manufacturer/model and HP detection. |
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
5. `Engine` applies the action only when `apply` is true and confirms it with a mode read-back. `FloatActive` is updated from the decision on every tick, including read-only ticks.
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

`BatteryControllerFactory.Create()` checks `DeviceInfo.IsHp`:

- HP/Hewlett/HPE: try `HpBios`; log `controller: HP <model> (charge control)`. On any constructor or WMI failure, log the reason and fall through.
- Everything else: `GenericBatteryController`, `CanControlCharge = false`, `ReadMode()` = `Unsupported`, write methods return `false`.

`Engine` exposes `CanControlCharge` and `IsHpDevice`; the tray uses them for icon color, badge, float warnings, menu enablement and the `Monitoring only` label. This keeps vendor detection out of the UI and prevents accidental writes on unsupported hardware.

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

## Window sizing

- Settings: 780×1000 design size, minimum 620×480, `AutoScaleMode.Dpi`. The scrolling content panel holds a 930 px root table; the Save/Cancel/Test footer is docked outside it, so it stays visible. The root keeps a 660 px minimum width and uses horizontal scrolling below that.
- Schedule window: 500×400 fixed dialog, minimum 440×320, `AutoScaleMode.Dpi`. Its content panel scrolls, the layout narrows to 360 px, the note wraps, and the Save/Cancel buttons stay pinned at the bottom.
- Activity log: 760×560, minimum 520×360, `AutoScaleMode.Dpi`. The action bar is auto-sized and wraps its status and buttons onto a second row on narrow windows.
- `UiLayout.Fit` clamps each form to `Screen.WorkingArea - 32` after layout and lowers `MinimumSize` first when the display cannot fit it. On a 1280×720 desktop the Settings window measured 780×601 client with a 54 px pinned footer; its 930 px content remains reachable by scrolling.

## Localization

- The `src/` modules contain no user-facing Arabic literals. UI text is `Loc.T("English source")` or `Loc.F("Template {0}", ...)`.
- `src/Localization.cs` defines the 30 supported codes, native names and RTL flags.
- `language=auto` resolves `CultureInfo.CurrentUICulture`: `zh-Hans/Hant` maps to `zh-CN`/`zh-TW`; `iw`/`in` normalize to `he`/`id`; unsupported languages fall back to English.
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
| `src/Wmi.cs` | Battery readings, HP `hpqBIntM` adapter and the generic monitoring controller. |
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
- Charge mode is restricted to auto and inhibit; forced discharge is never requested.
- Non-HP and unsupported HP hardware fails closed to monitoring.
- The launcher only runs local source/exe and local scripts.
- The mutex and single-instance guard prevent concurrent tray policies.

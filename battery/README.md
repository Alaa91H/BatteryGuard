# BatteryGuard

BatteryGuard is a native Win32 tray monitor for Windows notebooks. On supported HP notebooks it also controls charging through the BIOS WMI interface. It is a single .NET Framework 4.x process with no external packages and no background service.

A separate read-only Rust core under [`../portable`](../portable/README.md) is the first phase of the Windows/Linux/macOS shared work. It is not linked into this tray and does not control charging. Its 12-target type-check matrix and packaging boundary are documented in [`../portable/PLATFORMS.md`](../portable/PLATFORMS.md); CI-built Windows, Linux and macOS installers and the tag policy are in [`../docs/RELEASE.md`](../docs/RELEASE.md).

## Features

- **Charge limit and resume point.** Stops charging at a configurable ceiling and resumes at a lower point. The default Longevity policy is 60% / 55%; Recommended is 80% / 75%.
- **Float mode after the target.** Float never starts early: the battery charges normally to the configured limit, and only then does the app inhibit charging and keep the device on charger power. The latch holds through small drops and releases at the resume point.
- **Scheduled time windows.** Each window can use a ceiling or standard charging. Overlaps are detected when settings load, while editing and before saving.
- **Cross-brand monitoring.** Every vendor gets percentage, health, capacity, cycles, temperature and estimates. HP adds charge control; other vendors show **Monitoring only** and never receive guessed firmware writes.
- **Electrical readout.** The tray tooltip, tray menu, status balloon and Settings battery card show pack voltage and charge/discharge power from Windows battery WMI, for example `11.8 V · 0.0 W`. A zero wattage is shown while the charger holds the battery idle; unavailable readings are omitted.
- **Notifications with a stable identity.** Full-charge, low-battery and battery-health thresholds, plus an explicit test notification. Windows labels them **BatteryGuard** through the `BatteryGuard.Tray` AppUserModelID and a matching Start Menu shortcut, including when the UI runs inside the PowerShell host.
- **Activity log.** Last 300 lines, export and automatic rotation at 1 MiB.
- **30 languages.** English source and fallback; a **Language** submenu above **Appearance** switches manually and refreshes immediately; Automatic follows Windows; RTL for Arabic, Urdu, Persian and Hebrew.
- **Theme and accessibility.** Light, dark and system theme; owner-drawn menus; high-contrast battery icon rendering.
- **Adaptive dialogs.** Settings, schedule and log windows clamp to the working area, keep their action buttons visible, scroll long content and wrap toolbars on narrow screens.
- **Responsive Settings.** The window uses two columns at 900 px and wider and a single scrollable column below that. The language selector sits above the appearance selector, and the installed version is shown at the bottom of the interface card.

## Requirements

- Windows 10 or 11.
- .NET Framework 4.x (included with Windows).
- Charge control: a supported HP notebook and an elevated session for the HP BIOS WMI provider (`hpqBIntM`). Acer, Dell and Lenovo are candidate profiles only; they have no writer in this build. Other vendors are monitoring-only.
- PowerShell 5.1 for scripts and tests.

The app never uses forced discharge. It writes only HP charge modes `0x00` (auto) and `0x05` (inhibit). See [`../docs/DEVICE_SUPPORT.md`](../docs/DEVICE_SUPPORT.md) for the vendor matrix and safety model.

## Project layout

```text
battery/
  src/
    Program.cs            entry point, paths, startup, CLI, log rotation, migration, mutex
    TrayApp.cs            window procedure, tick, tray icon, menu, notifications
    Engine.cs             state, charge policy application, presets and schedules
    Controllers.cs        fingerprints, profiles, capabilities, WriteGuard and WMI gateway
    Wmi.cs                battery readings, HP WMI controller and generic fallback
    AppIdentity.cs        process AUMID and Start Menu shortcut for notifications
    Config.cs             settings.json, interface.ini, schedule model, autostart
    Theme.cs              theme settings, colors and owner-drawn controls
    Dialogs.cs            Settings, schedule window and activity log
    Native.cs             Win32 P/Invoke, icons and popup-menu helpers
    Localization.cs       language list, auto detection, catalog loader, T(), F()
  resources/
    application.manifest
    application.ico
  locales/
    en.json ar.json es.json ... zh-TW.json
  scripts/
    build.ps1             compile application.exe with csc.exe
    start.ps1             run compiled exe or host the source in PowerShell
    restart.ps1           stop the launcher and start it again
    control.ps1           command-line charge manager
    probe-*.ps1           read-only hardware probes
    simulate-controller.ps1  replay controller scenarios without hardware
  tests/
    Test-*.ps1            regression checks
    verify.ps1            end-to-end verification helper
  application.exe         build output
  settings.json           charge policy
  interface.ini           language/direction/notification/icon options
  theme.ini               auto / light / dark
  capacity.ini            cached design capacity
  application.log         current activity log
```

The C# namespace remains `BatteryGuardTray` for compatibility with existing scripts and tests; source and data file names are intentionally neutral.

## Build

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File battery/scripts/build.ps1
```

The script uses the .NET Framework compiler that ships with Windows, fails on compiler errors and prints the output size. No NuGet or network access is required.

## Windows installer

Branch CI builds a per-machine WiX MSI and a single-EXE Burn bootstrapper that install the tray and the portable CLI together under `Program Files\BatteryGuard`:

- `application.exe` and `batteryguard.exe`;
- `resources\application.ico` and all 30 `locales\*.json` catalogs;
- an all-users Start Menu shortcut for the tray with `System.AppUserModel.ID=BatteryGuard.Tray`;
- an **Uninstall BatteryGuard** Start Menu shortcut that runs `msiexec /x`.
- a standard installer wizard with version display, per-machine scope, launch-after-install and an Apps & Features uninstall entry (EXE only).

The workflow installs the x64 MSI and EXE, checks the payload and shortcuts, then uninstalls both. It also installs the published `v0.1.0` CLI MSI on a clean runner, upgrades it with the new EXE, verifies the old product is gone, then uninstalls. The x86 and ARM64 installers are built in the matrix but are not cross-installed on the x64 runner. The Windows x64 job also runs the hardware-independent C# suite. The interactive wizard and a physical clean Windows VM were not exercised. See [`../packaging/windows/Product.wxs`](../packaging/windows/Product.wxs), [`../packaging/windows/Bundle.wxs`](../packaging/windows/Bundle.wxs), [`../packaging/windows/Test-WindowsUpgrade.ps1`](../packaging/windows/Test-WindowsUpgrade.ps1) and [`../docs/RELEASE.md`](../docs/RELEASE.md). The published `v0.3.0` release includes these tray installers; `v0.2.0` remains the earlier tray-installer release and `v0.1.0` is the CLI-only release.

## Run

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File battery/scripts/start.ps1
```

`start.ps1` relaunches itself elevated unless `-NoElevate` is supplied. It prefers `application.exe`; when Smart App Control blocks the executable it compiles the same `src/*.cs` files in memory inside the system PowerShell host.

The command-line interface is available separately:

```powershell
powershell -File battery/scripts/control.ps1 -Status
powershell -File battery/scripts/control.ps1 -Preset Recommended
powershell -File battery/scripts/control.ps1 -Limit 60 -ResumeDrop 5
```

## Charge policy and float

The decision logic lives in `ChargePolicy.Evaluate`, separate from WMI so it can be tested without hardware:

1. Standard-charging policies (no limit, "Off", scheduled standard windows) never float.
2. On battery power the app returns to auto and clears the float latch.
3. Below the ceiling the app does not request inhibit for float. A stale inhibit is released so charging reaches the limit.
4. At or above the ceiling it inhibits charging. `FloatActive` is set only when float mode is enabled.
5. While floating, the inhibit is kept until the measured charge reaches the resume point.
6. At or below the resume point it restores auto charging; the latch clears and the next cycle starts after the ceiling.

The tray has a separate icon state and color for floating, and the tooltip reports `Charger power · battery idle`. The menu shows the current mode, policy, device vendor/model and monitoring state.

## Device support

| Family | Monitoring | Charge control |
| --- | --- | --- |
| HP notebooks | Yes | Yes, when `hpqBIntM` is available |
| Acer, Lenovo, Dell | Yes | Candidate profiles only; no writer |
| ASUS, MSI, Razer, Samsung and others | Yes | No — monitoring only |
| Desktops / unknown hardware | Yes, if a battery exists | No |

`DeviceInfo` builds a read-only `DeviceFingerprint` from manufacturer, product, board and BIOS fields. `DeviceProfileCatalog` matches embedded profiles; `BatteryControllerFactory` registers a writer only when the profile is `LabVerified` or `FieldVerified`. HP is the only such profile. Acer, Dell and Lenovo match candidate profiles and are logged, but no writer is created. Any provider failure falls back to `GenericBatteryController`, which reports `CanControlCharge = false`. The tray disables charge actions and labels the state **Monitoring only**; Settings hides the threshold slider rather than showing a generic 50–100% control. See [`../docs/DEVICE_SUPPORT.md`](../docs/DEVICE_SUPPORT.md) and [`../docs/CONTROLLER_VALIDATION.md`](../docs/CONTROLLER_VALIDATION.md).

## Settings and data

| File | Meaning |
| --- | --- |
| `settings.json` | Charge preset, ceiling, resume point, float mode and schedule windows. |
| `interface.ini` | `language`, `direction`, `showCeiling`, notification flags and thresholds. |
| `theme.ini` | `auto`, `light` or `dark`. |
| `capacity.ini` | Cached `powercfg` design capacity. |
| `application.log` | Activity lines; rotated to `application.previous.log` at 1 MiB. |

Older builds used `BatteryGuard.config.json`, `ui.txt`, `theme.txt`, `capacity.txt` and `batteryguard.log`. On startup, `Program.MigrateLegacyDataFiles()` moves those files to the neutral names if the new file does not exist.

Settings are read at startup and after a save; a `WM_REFRESH` message makes the tray reload them without a restart. The logon task runs the same `settings.json` used by manual runs.

## Window sizes

| Window | Design size | Minimum | Notes |
| --- | --- | --- | --- |
| Settings | 980×620 | 720×480 | Resizable; two-column layout at 900 px and wider, one scrollable column below; pinned Save/Cancel/Test footer; language, appearance and installed version in the interface card. |
| Schedule window | 500×350 | 440×350 | Fixed dialog; 56 px pinned button bar, scrolling content, narrows to a 360 px layout. |
| Activity log | 760×560 | 520×360 | Resizable; the action bar wraps to a second row on narrow windows. |

All three use `AutoScaleMode.Dpi`. `UiLayout.Fit` caps each window to the screen working area minus 32 px and lowers `MinimumSize` when the display cannot fit it, so a small screen scrolls instead of clipping the title bar or action buttons. `Test-Layout` builds the same dialogs at 100%, 125% and 150% in English and Arabic and checks every nested control; at 150% the Settings content scrolls vertically and has no horizontal scrollbar.

## Languages

- Source language: English.
- Default setting: `language=auto`.
- Automatic resolution: Windows display language; Chinese is mapped to `zh-CN` or `zh-TW` by script/region; unsupported languages fall back to English.
- RTL: `ar`, `ur`, `fa`, `he`.
- `direction=auto|rtl|ltr` can override the language-derived direction.
- Catalogs are flat JSON objects keyed by the exact English source string. A missing key falls back to English.
- Placeholders such as `{0}` and `{0:N0}` must be preserved. The maintenance script validates them.

See [`../docs/LOCALIZATION.md`](../docs/LOCALIZATION.md) for the full list and maintenance workflow.

## Tests

Hardware-independent:

```powershell
powershell -File battery/tests/Test-FloatLogic.ps1
powershell -File battery/tests/Test-ControllerFoundation.ps1
powershell -File battery/tests/Test-ScheduleConflict.ps1
powershell -File battery/tests/Test-UiPolish.ps1
powershell -File battery/tests/Test-Settings.ps1
powershell -File battery/tests/Test-BatteryInfo.ps1
powershell -File battery/tests/Test-AppIdentity.ps1
powershell -File battery/tests/Test-LogRotation.ps1
powershell -File battery/tests/Test-Icons.ps1
powershell -File battery/tests/Test-Layout.ps1
powershell -File battery/tests/Test-TrayMenu.ps1
powershell -File battery/tests/Test-LanguageAuto.ps1
```

Injected-mode tray checks (real tray, no charge-write path; `Test-TrayHost`
needs an elevated shell for the logon-task check):

```powershell
powershell -File battery/tests/Test-UI.ps1
powershell -File battery/tests/Test-Theme.ps1
powershell -File battery/tests/Test-TrayHost.ps1
```

These set `BATTERYGUARD_TEST_CONTROLLER=monitoring`; the factory returns a
monitoring-only controller before any provider or WMI gateway, the log shows
`test controller: monitoring-only` and `cap=monitoring`, and every charge
request is refused. The real HP mode read `Auto` before and after each run, and
no tray or logon task remained.

All tests compile every `src/*.cs` module. `Test-FloatLogic` checks the 13 charge/float decisions without touching hardware. `Test-ControllerFoundation` drives `HpBios` through a simulated WMI gateway and checks profile matching, capability gates, unplugged inhibition, access denial, empty/mismatched read-back and rollback. `Test-UiPolish` temporarily writes `interface.ini` with `language=en` and restores it. `Test-Layout` resizes the dialogs from 980×620 down to 380×350 and checks the two-column/stacked Settings switch, the pinned footer, no horizontal scroll, the language-above-appearance order, the installed version, combo text and the 360 px rule layout with fully visible buttons. It also simulates 100%/125%/150% DPI in English and Arabic with scaled bounds and fonts; the 222-check matrix verifies every nested control, the footer actions, cards, rule note/buttons and log bar/status. `Test-TrayMenu` builds the native popup menu with a synthetic charging state and checks that the charge time appears next to the active limit, disappears at the limit, and stays separate under standard charging. It also verifies that the Language submenu sits immediately above Appearance, that a manual language choice is persisted, and that an injected Acer candidate controller shows **Monitoring only** with no threshold menu item; its Settings form also attaches no slider or limit checkbox. A synthetic fixed-80% writable profile verifies the capability-only Settings card and the absence of a generic slider; no non-HP provider is enabled. `Test-LanguageAuto` changes the process UI culture and confirms that `language=auto` still follows the Windows user UI language. `Test-AppIdentity` creates or replaces the current user's BatteryGuard Start Menu shortcut and verifies its AUMID, target, arguments and description.

Visual review (no hardware, WMI writes or elevation):

```powershell
powershell -File battery/tests/VisualCapture.ps1
```

It writes 13 PNGs for Settings, schedule and log in English/Arabic and light/dark, plus a full-height Settings view. `interface.ini` and `theme.ini` are restored afterwards.

`DrawToBitmap` does not paint the native selected text of a WinForms ComboBox; `Test-Layout` checks the language and direction combo width, selection and text instead.

Hardware/elevation-dependent checks:

- `Test-FloatMode.ps1` samples the real charger and battery; it reports SKIP when AC is disconnected.
- `Test-Tray.ps1` and `verify.ps1` are write-capable hardware checks. They may change the charge mode and are intentionally not part of the safe suite.
- `Test-ThemeLive.ps1` changes only the Windows theme registry; it passed safely.

## Known limitations

- The 30 catalogs are machine-generated from the curated English source with targeted glossary corrections. Native-speaker review is still advisable, especially for technical terms and long sentences.
- The settings window cannot re-layout itself in a new language until it is reopened; the tray menu and tooltip update after the save/refresh cycle.
- The adaptive-layout pass re-inspected Settings in Arabic light/dark and schedule/log in Arabic light. English and dark schedule/log captures were regenerated but not re-inspected. The native tray popup menu could not be captured from the test host; its RTL flags are set in code but its pixels were not reviewed. 125%/150% are covered by the layout simulation, not by native screenshots; non-HP hardware was not exercised.
- The notification identity was verified through the Start Menu shortcut and its `System.AppUserModel.ID`. A real notification banner was requested from the running tray, but the captured desktop was occupied by browser notifications, so the final Windows label was not visually confirmed. The current automated suite does not open or inspect the banner.
- The 30 catalogs received a terminology/consistency pass for charge, health and schedule terms; native-speaker review is still advisable.
- HP's WMI interface is undocumented and model-specific. Unsupported models fail closed to monitoring rather than guessing a mode.
- Charge control on Acer, Lenovo, Dell, ASUS, MSI and other vendors is not implemented; those devices are monitored only. Acer, Dell and Lenovo have read-only candidate profiles for diagnostics, but no writer is enabled without independent hardware validation.

## Related documentation

- [`../docs/DEVICE_SUPPORT.md`](../docs/DEVICE_SUPPORT.md)
- [`../docs/CONTROLLER_VALIDATION.md`](../docs/CONTROLLER_VALIDATION.md)
- [`../portable/README.md`](../portable/README.md)
- [`../portable/PLATFORMS.md`](../portable/PLATFORMS.md)
- [`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md)
- [`../docs/PROJECT_STATUS.md`](../docs/PROJECT_STATUS.md)
- [`../docs/DECISIONS.md`](../docs/DECISIONS.md)
- [`../CHANGELOG.md`](../CHANGELOG.md)

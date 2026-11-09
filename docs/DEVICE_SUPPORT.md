# Device support

BatteryGuard monitors the battery on any Windows notebook. Charge control is
available only where the firmware exposes a documented, verified write path.
Today that is the HP BIOS WMI interface; every other device runs in
monitoring-only mode instead of guessing firmware commands.

## Support matrix

| Device family | Monitoring | Charge limit and float | Notes |
| --- | --- | --- | --- |
| HP consumer and business notebooks | Yes | Yes | Needs the `hpqBIntM` WMI provider and an elevated process. If the provider is missing or the model rejects the call, the app falls back to monitoring. |
| Lenovo (IdeaPad, ThinkPad, Legion) | Yes | No | Conservation Mode is handled through ACPI/EC or Lenovo Vantage. No documented Windows WMI write path. |
| Dell (XPS, Latitude, Inspiron, Alienware) | Yes | No | Dell Command \| Power Manager and BIOS settings own the charge policy. No stable public WMI charge-write interface. |
| ASUS (ZenBook, VivoBook, ROG) | Yes | No | MyASUS / ASUS System Control Interface and ACPI own the policy. |
| MSI, Acer, Razer, Samsung, Toshiba, Fujitsu | Yes | No | Vendor utilities and ACPI/EC; no documented per-model WMI write path. |
| Microsoft Surface, Framework | Yes | No | Firmware/UEFI battery limits; no WMI charge-mode interface. |
| Desktops and unknown hardware | Yes, when a battery is present | No | The generic controller is read-only. |

The app never claims control on a device it cannot probe. The tray menu and
the Settings battery card show **Monitoring only** on those devices, and the
charge items are disabled in the tray menu.

## How the controller is chosen

1. `DeviceInfo` reads `Win32_ComputerSystem.Manufacturer` and `Model` once.
2. `BatteryControllerFactory` treats HP, Hewlett-Packard and HPE as HP.
3. On HP it constructs `HpBios`, which connects to `root\wmi` and obtains the
   `hpqBIntM` instance. Any failure is logged and falls through.
4. Everything else gets `GenericBatteryController`: `CanControlCharge` is
   `false`, `ReadMode()` returns `Unsupported`, and the write methods are
   no-ops.
5. `Engine` exposes `CanControlCharge` and the tray uses it for colors, menu
   state, badges, float warnings and the monitoring label.

## Safety model

- Only two HP charge modes are ever written: `0x00` (auto / normal charging)
  and `0x05` (inhibit / stop charging). Forced discharge (`0x02`) is read for
  diagnostics but never requested.
- Every write is followed by a read-back. If the firmware does not confirm the
  new mode, the action is logged and the app waits for the next tick instead of
  retrying in a loop.
- A missing provider, access-denied error or unexpected byte fails closed to
  monitoring.
- No EC/ACPI register pokes and no vendor utility automation. Writing unknown
  firmware registers can leave a battery unable to charge and is outside the
  app's scope.
- On battery power the app always returns to auto; it never inhibits charging
  while unplugged.

## What monitoring includes

`BatteryInfo` combines WMI battery classes with the cached `powercfg` design
capacity:

- charge percentage, charging/discharging state and AC status;
- full-charged and designed capacity, health percentage;
- cycle count, pack voltage and charge/discharge power (shown in the tooltip, tray menu, status balloon and Settings card as `11.8 V · 0.0 W` when exposed);
- temperature when exposed;
- remaining-time and time-to-full estimates;
- full, low and health notifications, tray tooltip, activity log and export.

These readings come from Windows generic battery interfaces and therefore work
across vendors, subject to what each firmware exposes.

## Why other vendors are monitoring-only

The vendor tools do not publish a stable WMI command set for charge thresholds.
Their implementations use ACPI methods, embedded-controller registers or
kernel drivers, and the method IDs differ by model and firmware generation.
Implementing them from reverse-engineered snippets would be unverifiable on
this machine and could damage battery firmware.

Adding a vendor is therefore a deliberate task: implement `IBatteryController`,
probe capability, confirm the mode read-back on real hardware, and add a
regression test. Until that exists, the honest state is monitoring only.

## Cross-platform portable core

The `portable/` Rust core is a separate read-only layer for Windows, Linux and macOS. It reads Windows `BatteryStatus`/`Win32_Battery` through PowerShell, Linux `power_supply` sysfs and macOS `pmset -g batt`. It has no firmware writes, no vendor dependencies and no UI. Its platform modules type-check on x86/x64/ARM64 Windows, x86/x64/ARMv7/ARM64 Linux and Intel/Apple-silicon macOS targets. Charge control remains HP-Windows-only; the portable core is not a claim of cross-platform charge control.

## Verification status

- The HP write path is hardware-tested on the development notebook by the
  existing elevated tests; `Test-FloatMode.ps1` still requires AC power.
- The generic controller and the policy decision table are covered without
  hardware: `Test-FloatLogic.ps1` checks 13 charge/float cases.
- Non-HP hardware was not available in this environment, so the monitoring
  path was verified by code inspection and the shared battery reader, not on a
  second physical vendor device.- Window behavior was measured through reflection tests; pixel-level visual inspection on a non-HP machine was not performed.
- The portable Rust code type-checks on 12 targets, but no linked binary or Rust test ran on this host; Linux and macOS hardware was not available. See `portable/PLATFORMS.md` for the exact boundary.

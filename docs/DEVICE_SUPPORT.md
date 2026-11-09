# Device support

BatteryGuard monitors the battery on any Windows notebook. Charge control is
available only where the firmware exposes a documented, verified write path.
Today that is the HP BIOS WMI interface; every other device runs in
monitoring-only mode instead of guessing firmware commands.

The controller foundation now records a device profile and its capabilities,
but a profile is not a support claim. A vendor writer is enabled only when the
profile is `LabVerified` or `FieldVerified` and the exact model/BIOS path has
passed hardware read-back tests.

## Support matrix

| Device family | Monitoring | Charge control | Evidence status | Capability type |
| --- | --- | --- | --- | --- |
| HP consumer and business notebooks | Yes | Yes, `hpqBIntM` only | **Field-verified** | `AutoInhibit` (auto/inhibit + software resume) |
| Acer Aspire, Swift, Nitro and Predator | Yes | No | Documented (candidate) | `FixedThreshold` 80% (candidate; no writer) |
| Lenovo ThinkPad, IdeaPad and Legion | Yes | No | Candidate (detected interface, unvalidated) | `StartStopThreshold` (candidate; no writer) |
| Dell XPS, Latitude, Inspiron and Alienware | Yes | No | Candidate (detected interface, unvalidated) | `StartStopThreshold` (candidate; no writer) |
| ASUS ZenBook, VivoBook and ROG | Yes | No | Monitoring-only | `MonitoringOnly` |
| MSI notebooks | Yes | No | Monitoring-only | `MonitoringOnly` |
| Razer notebooks | Yes | No | Monitoring-only | `MonitoringOnly` |
| Samsung notebooks | Yes | No | Monitoring-only | `MonitoringOnly` |
| Toshiba / Fujitsu (Dynabook) | Yes | No | Monitoring-only | `MonitoringOnly` |
| Microsoft Surface | Yes | No | Monitoring-only | `MonitoringOnly` |
| Framework laptops | Yes | No | Monitoring-only | `MonitoringOnly` |
| Desktops and unknown hardware | Yes, when a battery is present | No | Monitoring-only | `MonitoringOnly` |

Evidence levels: **Documented** means a public interface or independent
implementation exists without local hardware validation; **Candidate** means a
possible interface was detected but is unverified; **LabVerified** and
**FieldVerified** are the only write-eligible levels; **Blocked/prohibited**
means a BIOS password, locked firmware, Secure Boot requirement, unsigned
driver or another unsafe path. No profile is currently `LabVerified` or
`Blocked`; HP is the only `FieldVerified` and writing-capable profile. The
matrix lists all eleven Phase 0 brands (HP, Acer, Lenovo, Dell, ASUS, MSI,
Razer, Samsung, Toshiba/Fujitsu, Surface and Framework).

The app never claims control on a device it cannot probe. The tray menu and
the Settings battery card show **Monitoring only** on those devices, the tray
charge items are disabled, and Settings attaches no threshold slider or limit
control. A future `FixedThreshold` or `StartStopThreshold` writer is rendered
as a capability-only card, never as a generic 50–100% slider. A candidate
profile is logged for support diagnostics but never promoted to a writer
automatically.

## How the controller is chosen

1. `DeviceInfo` caches a `DeviceFingerprint`: manufacturer, product, board,
   BIOS version/release date, family and system SKU from four read-only WMI
   queries. The serial number is deliberately not retained.
2. `DeviceProfileCatalog` matches the fingerprint against embedded profiles.
   Matching uses wildcard model/BIOS patterns; no regex comes from a user or a
   network source.
3. HP is the only provider whose profile currently has `CanWrite=true`. Its
   `HpBios` controller still uses `hpqBIntM`; any constructor or WMI failure
   falls through to monitoring.
4. Candidate profiles (Acer, Dell and Lenovo) are reported in the log with
   their interface and capability, but no provider is registered for them.
5. Everything else gets `GenericBatteryController`: `CanControlCharge` is
   `false`, `ReadMode()` returns `Unsupported`, and the capability is
   `MonitoringOnly`.
6. `Engine` exposes `CanControlCharge`, `Capabilities` and `CapabilityText()`;
   the tray uses them for colors, menu state, badges, float warnings and the
   monitoring label.

## Test mode

Tests set `BATTERYGUARD_TEST_CONTROLLER=monitoring`. The factory then returns
`GenericBatteryController` before any provider, so no WMI gateway or
`WriteGuard` exists. The tray logs `test controller: monitoring-only` and
`cap=monitoring`, and charge requests return `Unsupported`. This mode is for
verification only; it is not a device profile and never enables a vendor
writer.

## Controller foundation

- `DeviceFingerprint` is the vendor/model/BIOS identity used for profile
  selection. It never includes a serial number.
- `DeviceProfile` records the interface, capability kind, evidence status and
  whether a writer is allowed. `CanWrite` requires a verified status.
- `ControllerCapabilities` distinguishes `AutoInhibit`, `FixedThreshold`,
  `StartStopThreshold` and `MonitoringOnly`. A fixed-80% profile does not show
  a 50–100% slider.
- `IChargeController` adds capability-aware requests to the existing
  `IBatteryController` contract. `HpBios` and `GenericBatteryController`
  implement it; HP keeps the legacy public setters for the hardware tests.
- `WriteGuard` is the production write path: it rejects unsafe modes, missing
  capability, unplugged inhibit and unsupported operations, then performs one
  read-back and one rollback on mismatch. It never retries in a loop.
- `IWmiGateway` isolates the HP WMI calls. `HpBiosWmiGateway` is the real
  transport; `SimulatedWmiGateway` replays recorded responses without hardware.
- `battery/scripts/probe-controllers.ps1` is a read-only inventory for testers.
  `battery/scripts/simulate-controller.ps1` runs the simulator scenarios.
- `battery/tests/Test-ControllerFoundation.ps1` covers profile matching,
  capability gating, access denial, unplugged inhibition, empty/mismatched
  read-back and rollback. It does not touch a real battery.

See [`docs/CONTROLLER_VALIDATION.md`](CONTROLLER_VALIDATION.md) for the hardware
protocol, acceptance criteria and report template.

## Safety model

- Only two HP charge modes are ever written: `0x00` (auto / normal charging)
  and `0x05` (inhibit / stop charging). Forced discharge (`0x02`) is read for
  diagnostics but never requested.
- Every production write goes through `WriteGuard`. It validates the capability
  and AC state, performs exactly one read-back, and rolls back once on a
  mismatch. It does not retry endlessly.
- A missing provider, access-denied error, unexpected byte or unknown device
  fails closed to monitoring.
- No EC/ACPI register pokes and no vendor utility automation. Writing unknown
  firmware registers can leave a battery unable to charge and is outside the
  app's scope.
- On battery power the app always returns to auto; it never inhibits charging
  while unplugged.
- A firmware charge limit is outside the app's control. The effective ceiling is
  the lower of the app ceiling and the firmware limit; see
  [Hidden firmware settings](#hidden-firmware-settings-hp-envy-x360-13-ay-insyde-f28).

## Hidden firmware settings (HP ENVY x360 13-ay, Insyde F.28)

A static parse of the official F.28 `SetupUtility` module (SoftPaq `sp155605`)
recovered 237 settings in nine HII form packages. Most of them are not reachable
from the menus HP ships: 58 sit in forms that no `Ref` points at, and 204 carry
a `SuppressIf`, `DisableIf` or `GrayOutIf` condition. The F.28 IFR reports these
as the firmware defaults, not as the values currently stored on a machine.

The charge-related settings live in these setup stores:

| Store | GUID | Size |
| --- | --- | --- |
| `SystemConfig` | `f4274aa0-00df-424d-b552-39511302113d` | 700 bytes |
| `H19SetupUtilityConfig` | `746d2526-c058-6441-bbaa-99f203e1f522` | 44 bytes |
| `H19SetupVariable` | `a5f3fe30-29ba-6747-9f11-7c7fd606ffa6` | 17 bytes |

| Setting | Store | Offset | Values | Visibility gate |
| --- | --- | --- | --- | --- |
| Battery Care Function | SystemConfig | `0x23E` | `0` = 100%, `1` = 80%, `2` = 50% | `H19SetupUtilityConfig[0x17] != 0` |
| Adaptive Battery Optimizer | SystemConfig | `0x240` | `0` = off, `1` = on | `H19SetupUtilityConfig[0x23] != 0` |
| Battery Remaining Time | SystemConfig | `0x23C` | `0` = off, `1` = on | `H19SetupUtilityConfig[0x15] != 0` |
| USB Charging | SystemConfig | `0x237` | `0` = off, `1` = on | `H19SetupUtilityConfig[0x02] != 0` |
| Virtualization Technology | SystemConfig | `0xEE` | `0` = off, `1` = on | `SystemConfig[0x220] != 0` |
| SVM support | SystemConfig | `0xEE` | same field as Virtualization Technology | grayed by `SystemConfig[0x80]` and `[0x81]` |
| SVM Lock | SystemConfig | `0xEF` | `0` = off, `1` = on | same gray-out pair |
| Integrated Camera | H19SetupVariable | `0x0D` | `0` = off, `1` = on | `H19SetupUtilityConfig[0x08] != 0` |
| Fingerprint Reader | H19SetupVariable | `0x0F` | `0` = off, `1` = on | `H19SetupUtilityConfig[0x09] != 0` |

These settings are hidden, not merely undocumented: a setting is only built
into the setup UI when its gate byte is non-zero, and HP's platform flags in
`H19SetupUtilityConfig` decide that. Editing the visible value alone therefore
has no effect until the gate is also set, which is a second NVRAM write.

### The firmware ceiling and BatteryGuard

`Battery Care Function` is a second, independent charge ceiling enforced below
the operating system. BatteryGuard has no read path for it and never writes it.
The effective ceiling is the lower of the two:

- app ceiling 60%, firmware limit 80%: the app inhibits at 60% as usual;
- app ceiling 100%, firmware limit 80%: the pack stops at 80% while the WMI
  mode stays `Auto`, so the app reports standard charging and float never
  latches.

That plateau is not a controller failure. The app reads the mode back, sees a
real `Auto`, and correctly waits for the next tick instead of retrying. No code
path tries to detect or override the firmware value, and the UI must not claim
the configured ceiling was reached when the pack stopped lower.

### Why this project does not write these settings

Changing them requires writing the setup variables, which on this platform means
a UEFI shell tool such as `RU.efi` or `SetupVar`, usually with Secure Boot
disabled. A wrong byte in the 700-byte `SystemConfig` store can leave the
machine unable to boot, and a notebook has no easy Clear CMOS. HP BIOS
Protection may reject or silently restore the change. WMI is not an alternative:
`hpqBIntM` exposes the charge mode only, not these fields.

`battery/scripts/probe-bios-settings.ps1` is the supported way to look. It
reads the four documented variables (`SystemConfig`, `H19SetupUtilityConfig`,
`H19SetupVariable` and `AdvanceConfig`) with `GetFirmwareEnvironmentVariable`,
prints the bytes at the documented offsets, and never writes. Run it from an
elevated PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File battery/scripts/probe-bios-settings.ps1
```

If the variables are absent, runtime-locked or the privilege cannot be enabled,
the probe reports the Win32 error and exits without changing anything.

On this machine the elevated probe enabled `SeSystemEnvironmentPrivilege` and
then returned `Win32 203 (ERROR_ENVVAR_NOT_FOUND)` for every name it tried. The
IFR store names are internal to the firmware and are not exposed as runtime EFI
variables, so the stored values and the Battery Care ceiling cannot be read
from Windows. The probe is a capability check; a read-only UEFI shell dump
would be the only alternative. Nothing was written.

### Read-only UEFI shell dump (only if the values are required)

The Windows API cannot see these stores on this machine, so the only remaining
read-only option is a UEFI shell. The procedure below only reads; it does not
write NVRAM.

1. Prepare a FAT32 USB stick with an EDK2 `Shell.efi`, or use a signed vendor
   shell if one is available. Booting an unsigned shell usually requires
   disabling Secure Boot, which is itself a firmware change and can trigger
   BitLocker recovery. Have the recovery key ready, re-enable Secure Boot, and
   treat this step as optional: a signed shell avoids it entirely.
2. Boot the stick from the HP F9 boot menu and start the shell.
3. Capture the variables (replace `fs0:` with the USB volume shown by `map`):

   ```
   map -r
   fs0:
   dmpstore -guid f4274aa0-00df-424d-b552-39511302113d SystemConfig >a fs0:\systemconfig.txt
   dmpstore -guid 746d2526-c058-6441-bbaa-99f203e1f522 H19SetupUtilityConfig >a fs0:\h19config.txt
   dmpstore -guid a5f3fe30-29ba-6747-9f11-7c7fd606ffa6 H19SetupVariable >a fs0:\h19var.txt
   dmpstore -guid f4274aa0-00df-424d-b552-39511302113d AdvanceConfig >a fs0:\advanceconfig.txt
   ```

   The `-guid` filter and the `>a` ASCII redirection depend on the EDK2 shell
   version. If a filter is rejected, `dmpstore -all >a fs0:\nvram.txt` writes
   every variable and the four blocks can be located by GUID and name.
4. Read the files on Windows. `dmpstore` prints the GUID, name, data size and a
   hex dump; check the expected sizes (700, 44, 17 and 8 bytes). Offset `0x23E`
   is data byte 575, `0x240` is 577 and `0x237` is 567.

Never run `dmpstore -d`, `setvar -delete`, `mm`, `pci -w` or `bcfg` in the
shell: they delete variables or write memory and can leave the machine unable
to boot. They are not part of this procedure. Do not unplug the stick while the
dump is being written.

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

Adding a vendor is therefore a deliberate, evidence-gated task: define its
`DeviceProfile`, implement a capability-aware `IChargeController`, register a
provider only after two independent hardware read-back reports, and keep the
generic fallback. Until that exists, the honest state is monitoring only.

Acer, Dell and Lenovo are candidates in this build, not supported writers. The
probe can detect their interfaces, and the simulator can reproduce reports, but
neither is a substitute for hardware validation.

## Cross-platform portable core

The `portable/` Rust core is a separate read-only layer for Windows, Linux and macOS. It reads Windows `BatteryStatus`/`Win32_Battery` through PowerShell, Linux `power_supply` sysfs and macOS `pmset -g batt`. It has no firmware writes, no vendor dependencies and no UI. Its platform modules type-check on x86/x64/ARM64 Windows, x86/x64/ARMv7/ARM64 Linux and Intel/Apple-silicon macOS targets. Charge control remains HP-Windows-only; the portable core is not a claim of cross-platform charge control.

## Verification status

- The HP write path is hardware-tested on the development notebook by the
  existing elevated tests; `Test-FloatMode.ps1` still requires AC power.
- The generic controller and the policy decision table are covered without
  hardware: `Test-FloatLogic.ps1` checks 13 charge/float cases and
  `Test-ControllerFoundation.ps1` checks profile, capability, write-gate,
  unplugged, access-denied, empty/mismatched read-back and rollback behavior
  through a simulated WMI gateway.
- Non-HP hardware was not available in this environment, so the monitoring
  path was verified by code inspection and the shared battery reader, not on a
  second physical vendor device. Acer, Dell and Lenovo candidate profiles have
  no writer and no hardware validation claim.
- The read-only probe ran on the HP development notebook and produced 77 WMI
  class entries and 31 normalized ACPI prefixes with no serial numbers. That is
  an inventory result, not proof of a new write path.
- Window behavior was measured through reflection tests; pixel-level visual inspection on a non-HP machine was not performed.
- The portable Rust code type-checks on 12 targets; hosted CI links and tests it, but no linked binary or Rust test ran on this host and Linux/macOS hardware was not available. See `portable/PLATFORMS.md` for the exact boundary.
- Windows `BatteryStatus` exposes pack voltage and charge/discharge power, not AC adapter input wattage. No documented HP BIOS adapter-wattage field was verified, and the BIOS provider was inaccessible without elevation, so no charger-input value is displayed or fabricated.
- The notification identity is verified through the Start Menu shortcut and AUMID; a UI Automation probe did not find a visible toast, so no automated banner-label check is claimed.

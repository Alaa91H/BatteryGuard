# Controller validation

BatteryGuard will not enable a vendor charge writer without hardware evidence.
The controller foundation is present and tested without hardware, but the only
writer enabled in this build remains the field-verified HP `hpqBIntM` path.

## Evidence levels

| Status | Meaning | Writer allowed |
| --- | --- | --- |
| `MonitoringOnly` | No safe, documented write path is known. | No |
| `Candidate` | A vendor interface may exist, but it is not confirmed for this family or BIOS. | No |
| `Documented` | A public interface or independent implementation exists, but BatteryGuard has not tested it. | No |
| `LabVerified` | Reproducible tests passed on at least two independent devices. | Yes, after review |
| `FieldVerified` | The same path has passed the release checklist and field reports. | Yes |
| `Blocked` | BIOS password, missing driver, locked firmware or an unsafe path. | No |

`DeviceProfile.CanWrite` derives from the status and capabilities. A detected
WMI class alone never promotes a device.

## Read-only probe

Use Windows PowerShell 5.1 or later:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File battery/scripts/probe-controllers.ps1 `
  -OutputPath .\controller-probe.json
```

The probe reads the SMBIOS fingerprint, battery readings, battery/charge-related
WMI class and method names, normalized ACPI prefixes and selected signed
drivers. It does not invoke a WMI method and does not write firmware, the EC,
NVRAM or BatteryGuard settings. Serial numbers are not collected.

The JSON report is suitable for a GitHub issue. Remove a machine name or any
other personal detail before attaching it. A report proves only that an
interface was visible; it does not prove that a write is accepted.

## Simulator

The simulator replays WMI responses without contacting a provider:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File battery/scripts/simulate-controller.ps1 -Scenario success

powershell -NoProfile -ExecutionPolicy Bypass `
  -File battery/scripts/simulate-controller.ps1 -Scenario unplugged

powershell -NoProfile -ExecutionPolicy Bypass `
  -File battery/scripts/simulate-controller.ps1 -Scenario denied

powershell -NoProfile -ExecutionPolicy Bypass `
  -File battery/scripts/simulate-controller.ps1 -Scenario mismatch
```

`Test-ControllerFoundation.ps1` uses the same fake gateway in CI. These checks
prove profile selection and safety behavior, not firmware behavior.

## Hardware test protocol

Run only on a device whose owner has approved the test, with a known recovery
path and the charger connected. Never run these steps on a production machine
without the owner's consent.

1. Run the read-only probe and attach its report to the validation issue.
2. Record the exact model, BIOS version, Windows build, vendor utility version
   and whether a BIOS password or Secure Boot restriction is present.
3. Confirm the app reports **Monitoring only** before any provider is enabled.
4. Enable the candidate provider only in a local test build, never by guessing
   an EC/ACPI command in a released build.
5. Set the supported limit (for example 80% on a fixed-health-mode device).
6. Confirm the mode/limit with an independent read-back and with the vendor
   utility or firmware UI when available.
7. Repeat after sleep/resume and after a reboot.
8. Disconnect AC, wait for the policy tick, and confirm the app releases inhibit
   and restores its safe default.
9. Return the device to its original vendor setting and uninstall the test
   build. Check that the original setting survived.
10. Attach the app log, probe report and a short result table to the issue.

The app must never require a BIOS setup-variable write, an EC/ACPI register
write, Secure Boot disablement or a third-party kernel driver. Such a device is
`Blocked`, not a candidate to work around.

## Acceptance criteria

A profile may move from `Candidate` or `Documented` to `LabVerified` only when:

- the exact manufacturer, product, board and BIOS family are recorded;
- two independent devices, preferably on different BIOS versions, pass the
  protocol;
- the write is followed by a confirmed read-back;
- a failed or mismatched read-back rolls back to auto and does not retry in a
  loop;
- unplugged, sleep/resume, reboot, access-denied and unknown-model paths fail
  closed;
- the firmware/vendor utility still accepts the restored setting;
- the hardware-independent suite and the affected HP regression checks pass.

`FieldVerified` additionally requires a release build and reports from users on
the same profile. No profile should be advertised as supported from a single
report or from a WMI class appearing in a probe.

## Report template

```text
Model:
BIOS version:
Windows build:
Vendor utility and version:
Probe status: read-only report attached
Interface observed:
Limit tested:
Read-back result:
Sleep/resume result:
Reboot result:
AC unplug result:
Restore result:
Visible side effects:
App log attached: yes/no
Owner approved the test: yes/no
```

## Current limitations

- No second vendor device is available in this development environment.
- The Acer, Dell and Lenovo entries are candidate profiles only; no writer is
  registered for them.
- No tester package is signed because the project has no signing configuration.
  Do not describe an unsigned test script as signed.
- A probe result or a simulator pass is not hardware validation.

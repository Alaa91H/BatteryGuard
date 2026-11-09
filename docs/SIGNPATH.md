# SignPath Foundation signing

BatteryGuard is **MIT licensed** and the repository is public. This lets the
project apply to the [SignPath Foundation](https://signpath.org/) for free
code signing. SignPath Foundation issues the certificate to itself and signs
from its HSM; no contributor-owned code-signing certificate or USB token is
needed. The publisher shown on the signed installers is
**SignPath Foundation**, not a personal certificate subject.

The CI integration is **implemented but not exercised**. No SignPath account,
project, signing policy, artifact configuration or API token exists in this
repository yet. Until a real signing request completes, the installers remain
unsigned and Smart App Control will continue to block them.

## What the pipeline signs

The Windows job uses three SignPath requests, in this order:

1. `SIGNPATH_ARTIFACT_CONFIGURATION_BINARIES` — `application.exe` and
   `batteryguard.exe`, before they are placed in the MSI.
2. `SIGNPATH_ARTIFACT_CONFIGURATION_ENGINE` — the detached WiX Burn engine,
   after the bundle is built; the signed engine is reattached before the outer
   EXE is signed.
3. `SIGNPATH_ARTIFACT_CONFIGURATION_INSTALLERS` — the MSI and the final EXE
   bundle.

Every signing request uses Authenticode. The existing PFX steps are skipped
when SignPath is enabled; the PFX path remains the fallback when SignPath is
not configured.

## Onboarding

1. Apply at [signpath.org/apply](https://signpath.org/apply). Use the public
   repository URL and describe the Windows tray, CLI and installer payload.
   The project must remain public, MIT licensed and free of proprietary
   components.
2. After approval, install the [SignPath GitHub App](https://github.com/apps/signpath)
   and link the GitHub.com trusted build system to the SignPath project.
3. Create the SignPath project and a signing policy. Use an approval process
   for release signing. The CI waits up to one hour for each approval.
4. Create three artifact configurations in SignPath. Upload a sample ZIP for
   each and review the generated configuration:
   - **binaries**: signs `application.exe` and `batteryguard.exe` with
     Authenticode. No deep signing is required.
   - **engine**: signs `burn-engine.exe`.
   - **installers**: signs the MSI and the final EXE. No deep signing is
     required because the binaries are signed before packaging.
5. Create a CI user with submitter permission and an API token.

## GitHub configuration

Create the repository secret:

| Name | Value |
| --- | --- |
| `SIGNPATH_API_TOKEN` | API token for the SignPath CI submitter |

Create the repository variables:

| Name | SignPath value |
| --- | --- |
| `SIGNPATH_ORGANIZATION_ID` | Organization ID from SignPath |
| `SIGNPATH_PROJECT_SLUG` | Project slug |
| `SIGNPATH_SIGNING_POLICY_SLUG` | Release signing policy slug |
| `SIGNPATH_ARTIFACT_CONFIGURATION_BINARIES` | Binaries artifact configuration slug |
| `SIGNPATH_ARTIFACT_CONFIGURATION_ENGINE` | Burn engine artifact configuration slug |
| `SIGNPATH_ARTIFACT_CONFIGURATION_INSTALLERS` | MSI + EXE artifact configuration slug |

All six variables must be set for the SignPath path to activate. If
`SIGNPATH_API_TOKEN` is missing after the variables are set, the workflow fails
early with a configuration error. If the variables are absent, the Windows job
follows the existing PFX-or-unsigned path.

## Verification

After a signed run:

```powershell
Get-AuthenticodeSignature .\dist\BatteryGuard-*-windows-x64.exe |
  Format-List Status, StatusMessage, SignerCertificate
signtool.exe verify /pa /all .\dist\BatteryGuard-*-windows-x64.exe
signtool.exe verify /pa /all .\dist\BatteryGuard-*-windows-x64.msi
```

The workflow also runs `signtool verify /pa /all` on the returned binaries,
engine, MSI and EXE. A SignPath approval is a human step; a branch push alone
does not produce a signed artifact.

## Smart App Control

Microsoft documents that Smart App Control accepts valid signatures from
certificate authorities in the Windows Trusted Root Program. SignPath
Foundation's OV-level certificate is intended for that purpose, but the result
must still be tested on a real Windows 11 device with Smart App Control in
enforcement mode:

- Verify the installer and the installed tray/CLI signatures.
- Test a clean install and the `v0.1.0` upgrade path.
- Check `Applications and Services Logs > Microsoft > Windows > CodeIntegrity >
  Operational` if a block remains.
- Smart App Control still has no per-app allowlist. A self-signed certificate,
  an administrator token, Defender exclusions or `Unblock-File` are not
  substitutes for a trusted signature.

The previous unsigned artifacts remain blocked. Do not describe a build as
signed until the SignPath request succeeds and the verification commands pass.

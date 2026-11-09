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

## Before applying

- Use the public `v0.2.0` release, which contains the MSI and EXE bootstrapper.
  The earlier `v0.1.0` release is CLI-only and cannot cover the final EXE
  request.
- Keep the [code signing policy](CODE_SIGNING_POLICY.md) linked from
  the project home page. It defines the signing scope, roles, approval and
  privacy statement.
- Enable multi-factor authentication for the GitHub account and the SignPath
  account.
- Check the repository's public reputation. SignPath Foundation requires
  verifiable reputation for executable programs; a new repository without an
  established public history may not satisfy that criterion. Approval is
  discretionary and is not guaranteed.

## What the pipeline signs

The Windows job uses three SignPath requests, in this order:

1. `SIGNPATH_ARTIFACT_CONFIGURATION_BINARIES` — `application.exe` and
   `batteryguard.exe`, before they are placed in the MSI.
2. `SIGNPATH_ARTIFACT_CONFIGURATION_MSI` — the MSI after packaging and before
   the EXE is built, so the bundle embeds a signed MSI.
3. `SIGNPATH_ARTIFACT_CONFIGURATION_EXE` — the final EXE bundle after the signed
   MSI is embedded.

The upstream WiX Burn engine is included unsigned. It is not signed under the
SignPath Foundation certificate. The optional PFX fallback may sign it with the
maintainer's own certificate.

## Onboarding

1. Apply at [signpath.org/apply](https://signpath.org/apply) using the public
   repository URL, the download-page URL and a description of the Windows tray,
   CLI and installer payload.
2. After approval, install the [SignPath GitHub App](https://github.com/apps/signpath)
   and link the GitHub.com trusted build system to the SignPath project.
3. Create the SignPath project and a signing policy. Use an approval process
   for release signing. The CI waits up to one hour for each approval.
4. Create three artifact configurations in SignPath. Upload a sample ZIP for
   each and review the generated configuration:
   - **binaries**: signs `application.exe` and `batteryguard.exe` with
     Authenticode. No deep signing is required.
   - **msi**: signs the MSI after the signed binaries have been packaged.
   - **exe**: signs the final EXE after the signed MSI is embedded.
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
| `SIGNPATH_ARTIFACT_CONFIGURATION_MSI` | MSI artifact configuration slug |
| `SIGNPATH_ARTIFACT_CONFIGURATION_EXE` | Final EXE artifact configuration slug |

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

The workflow also runs `signtool verify /pa /all` on the returned binaries, MSI
and EXE. A SignPath approval is a human step; a branch push alone does not
produce a signed artifact.

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

## Measured Smart App Control result

On 2026-11-09, a Windows 11 Home 10.0.26300 host with SAC enforcement
(`VerifiedAndReputablePolicyState=1`) blocked the unsigned
`BatteryGuard-0.2.0-windows-x64.exe` at launch with `An Application Control
policy has blocked this file.` The download was `NotSigned` (SHA-256
`6c41267667e92bde41f76efd7430c925d1e2750d91e559b7b79fbee72e4a59e3`). No
installation or upgrade occurred; the existing `0.1.0` installation remained.
This is the expected unsigned result, not a test of a signed build.

# Microsoft Entra Breakglass Setup

PowerShell/WPF tool for preparing and documenting Microsoft Entra ID breakglass accounts in a tenant.

The tool uses Microsoft Graph PowerShell modules. It does not use the deprecated AzureAD or MSOnline modules.

## Features

- WPF GUI with tenant, UPN, group, dry-run, and action choices.
- Connects to Microsoft Graph PowerShell.
- Checks whether two breakglass accounts exist.
- Creates missing breakglass accounts when selected.
- Forces breakglass account UPNs to the tenant `.onmicrosoft.com` domain.
- Finds or creates the `CA-BreakGlassExclude` security group.
- Adds the breakglass accounts to the group when selected.
- Shows clear warnings for Conditional Access exclusions and admin SSPR scope.
- Can disable administrator SSPR tenant-wide when selected.
- Generates a short Markdown report with actions and manual steps.
- Logs every action to the local `logs` folder.
- Prompts before every change unless dry-run mode is enabled.

## Requirements

- Windows PowerShell 5.1 or newer.
- Microsoft Graph PowerShell SDK.
- An account with sufficient Entra ID role permissions to create users, create groups, update group membership, and update authorization policy settings.
- Admin consent for the delegated Microsoft Graph permissions listed below.

Install Graph PowerShell if needed:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

## Graph permissions

The script requests these delegated Microsoft Graph scopes:

- `Directory.Read.All`
- `Domain.Read.All`
- `User.ReadWrite.All`
- `Group.ReadWrite.All`
- `Policy.ReadWrite.Authorization`

`Policy.ReadWrite.Authorization` is required when disabling administrator SSPR through the authorization policy endpoint.

Microsoft references:

- [Microsoft Graph PowerShell authentication](https://learn.microsoft.com/powershell/microsoftgraph/authentication-commands)
- [Update authorizationPolicy](https://learn.microsoft.com/graph/api/authorizationpolicy-update)
- [authorizationPolicy resource type](https://learn.microsoft.com/graph/api/resources/authorizationpolicy)

## Usage

Run the script from PowerShell:

```powershell
.\Invoke-EntraBreakglassSetup.ps1
```

Recommended first run:

1. Enter the tenant initial domain, for example `contoso.onmicrosoft.com`.
2. Enter both breakglass UPNs.
3. Keep `Dry-run mode` enabled.
4. Review the GUI log and generated report.
5. Run again with dry-run disabled when the planned actions are correct.

## Important behavior

- The script never deletes existing users, groups, or Conditional Access policies.
- Conditional Access policies are not modified by this script.
- You must manually exclude `CA-BreakGlassExclude` from every relevant Conditional Access policy.
- Administrator SSPR cannot be disabled only for the two breakglass accounts. The setting applies tenant-wide to administrators in administrator roles.
- Temporary passwords for newly created accounts are shown once in the GUI and are not written to logs or reports.

## Manual steps to complete

- Register one separate FIDO2 security key per breakglass account.
- Store the FIDO2 keys physically separated and securely.
- Exclude `CA-BreakGlassExclude` from all Conditional Access policies.
- Configure alerting on sign-in for both breakglass accounts.
- Test the accounts periodically.
- Never use the accounts for daily administration.

## Output folders

- `logs`: timestamped run logs.
- `reports`: generated Markdown reports.

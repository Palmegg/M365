# Microsoft Entra Breakglass Setup

PowerShell/WPF tool for preparing and documenting Microsoft Entra ID breakglass accounts in a tenant.

The tool uses Microsoft Graph PowerShell modules. It does not use the deprecated AzureAD or MSOnline modules.

## Features

- WPF GUI with tenant, UPN, group, dry-run, and action choices.
- Connects to Microsoft Graph PowerShell.
- Tenant field is optional. If it is blank, the `.onmicrosoft.com` domain is resolved from the signed-in tenant.
- Disconnects existing Graph PowerShell context and uses process-scoped context for each run.
- Includes naming preset buttons for `svr_ea01` / `svr_ea02` and `adm_ea01` / `adm_ea02`.
- Looks for existing potential emergency access accounts and warns if likely candidates are found.
- Checks whether two breakglass accounts exist.
- Creates missing breakglass accounts when selected.
- Forces breakglass account UPNs to the tenant `.onmicrosoft.com` domain.
- Accepts either full UPNs or account prefixes. For example, `svr_ea02` becomes `svr_ea02@tenant.onmicrosoft.com`.
- Finds or creates the `CA-BreakGlassExclude` security group.
- Adds the breakglass accounts to the group when selected.
- Shows clear warnings for Conditional Access exclusions and admin SSPR scope.
- Can disable administrator SSPR tenant-wide when selected.
- Generates a short Markdown report with actions and manual steps.
- Logs every action to the local `logs` folder.
- Prompts before every change unless dry-run mode is enabled.
- Runs Graph work on a background worker thread so the WPF GUI stays responsive during sign-in and Graph operations.

## Requirements

- Windows PowerShell 5.1 or newer.
- Internet access to PowerShell Gallery on the first run if Microsoft Graph PowerShell modules are missing.
- An account with sufficient Entra ID role permissions to create users, create groups, update group membership, and update authorization policy settings.
- Admin consent for the delegated Microsoft Graph permissions listed below.

The script checks for the required Microsoft Graph PowerShell modules when `Run setup` is clicked. If modules are missing, it prompts to install them for the current user:

- `Microsoft.Graph.Authentication`
- `Microsoft.Graph.Users`
- `Microsoft.Graph.Groups`
- `Microsoft.Graph.Identity.DirectoryManagement`

On a blank PC, the script also checks for the NuGet package provider and the default PowerShell Gallery registration, then prompts before setting them up.

## Graph permissions

The script requests these delegated Microsoft Graph scopes:

- `Directory.Read.All`
- `Domain.Read.All`
- `User.ReadWrite.All`
- `Group.ReadWrite.All`
- `RoleManagement.Read.Directory`
- `Policy.ReadWrite.Authorization`

`Policy.ReadWrite.Authorization` is required when disabling administrator SSPR through the authorization policy endpoint.
`RoleManagement.Read.Directory` is used to confirm Global Administrator role membership.

Microsoft references:

- [Microsoft Graph PowerShell authentication](https://learn.microsoft.com/powershell/microsoftgraph/authentication-commands)
- [Update authorizationPolicy](https://learn.microsoft.com/graph/api/authorizationpolicy-update)
- [authorizationPolicy resource type](https://learn.microsoft.com/graph/api/resources/authorizationpolicy)

## Usage

Run the script from PowerShell:

```powershell
.\Invoke-EntraBreakglassSetup.ps1
```

If execution policy blocks local scripts, use a process-scoped bypass for this PowerShell window only:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Invoke-EntraBreakglassSetup.ps1
```

Recommended first run:

1. Optionally enter the tenant ID or domain. Leave it blank to resolve the tenant after sign-in.
2. Enter both breakglass UPNs or prefixes, for example `svr_ea01` and `svr_ea02`, or use one of the preset buttons.
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

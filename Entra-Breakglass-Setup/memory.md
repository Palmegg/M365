# Codex Memory - Entra Breakglass Setup

## Project

Repository:

`C:\Users\jop\OneDrive - netIP\Dokumenter\GitHub\M365`

Project folder:

`Entra-Breakglass-Setup`

Main script:

`Entra-Breakglass-Setup\Invoke-EntraBreakglassSetup.ps1`

README:

`Entra-Breakglass-Setup\README.md`

## User Goal

Build a PowerShell/WPF tool that helps admins configure and document Microsoft Entra ID emergency access / breakglass accounts using Microsoft Graph PowerShell only.

The tool should:

- Use WPF embedded XAML GUI.
- Use Microsoft Graph PowerShell, not AzureAD/MSOnline.
- Check/create two emergency access accounts.
- Force accounts to the tenant `.onmicrosoft.com` domain.
- Create/find `CA-BreakGlassExclude`.
- Add accounts to the group.
- Warn that the group must be manually excluded from Conditional Access policies.
- Optionally disable admin SSPR tenant-wide.
- Generate a confidential HTML report.
- Avoid writing generated passwords to normal logs.
- Support dry-run.
- Prompt before changes.
- Log actions.

## Current Implementation Notes

- GUI supports account prefixes like `svr_ea01` and converts them to `svr_ea01@tenant.onmicrosoft.com` after resolving the tenant domain.
- Tenant field is now optional. If blank, Graph sign-in determines the tenant and `Get-MgDomain` resolves the `.onmicrosoft.com` domain.
- Graph login disconnects any existing context first and uses process-scoped context when supported.
- `Run setup` no longer uses `BackgroundWorker`. It starts the same script in a separate PowerShell worker process using `-WorkerMode -ConfigPath <json>`.
- Worker process writes to the same log file as the GUI. GUI polls that log file while the worker runs.
- Worker process is launched with `WindowStyle Normal` so Graph/passkey authentication UI can be seen.
- GUI now uses native Microsoft Graph interactive browser sign-in by default, because FIDO/passkey sign-in must happen in the Microsoft login window or browser.
- GUI keeps `Fallback: device code sign-in`, disabled by default. Use it only if native browser sign-in cannot open.
- GUI has `Run in current terminal`, enabled by default, so sign-in prompts stay attached to the VS Code / PowerShell terminal that launched the GUI.
- Startup now auto-relaunches in STA Windows PowerShell when started from a non-STA shell, because WPF can close or fail silently without STA.
- Startup exceptions are logged and shown in a MessageBox instead of disappearing immediately.
- Internal Graph connection helper is named `Connect-BreakglassGraph` because Microsoft Graph PowerShell can expose a `Connect-Graph` alias on existing PCs. That alias shadowed the original helper and caused `A parameter cannot be found that matches parameter name 'TenantName'`.
- The old `$timer` StrictMode bug was fixed by using `$script:WorkerTimer`.
- `Browse...` button is wired to `System.Windows.Forms.FolderBrowserDialog`.
- Naming preset buttons exist for `svr_ea01 / svr_ea02` and `adm_ea01 / adm_ea02`.
- The script scans for potential existing emergency access accounts and warns/logs if it finds candidates.

## Recent Bugs Fixed

- `UPN 'svr_ea02' is not valid`: fixed by accepting account prefixes.
- WPF froze during Graph sign-in: changed from inline execution to worker process.
- `Browse...` did nothing: fixed by adding click handler.
- `There is no Runspace available`: fixed by removing `BackgroundWorker` and using worker process mode.
- `The variable '$timer' cannot be retrieved because it has not been set`: fixed by using `$script:WorkerTimer`.
- `A parameter cannot be found that matches parameter name 'TenantName'`: fixed by renaming the internal connection helper to avoid a `Connect-Graph` alias collision from Microsoft Graph PowerShell.

## Important Security Decisions

- Do not use `breakglass` in generated account UPN presets because it is too descriptive.
- Generated initial passwords are only written to the confidential HTML report, not normal logs.
- Existing account passwords cannot be retrieved and should be shown as unavailable in the report.
- Report is marked `CONFIDENTIAL` and includes warning to move passwords to an approved password manager or physical emergency procedure, then remove local files.

## Git Notes

The repo has unrelated untracked files in other folders, especially under:

- `Application deployments/OfficeExtensionsPreRequisites/`
- `Application deployments/RetryFailedWin32App/`
- `Application deployments/WAU Uninstall/`

Do not stage or modify those unless the user asks.

## Suggested Next Checks

- Run `.\Invoke-EntraBreakglassSetup.ps1`.
- Leave tenant blank.
- Click `Use svr_ea01 / svr_ea02`.
- Select output folder with `Browse...`.
- Leave `Fallback: device code sign-in` disabled for tenants requiring FIDO/passkey. Native browser sign-in should open a Microsoft login window/browser where the FIDO key can be used.
- Keep `Run in current terminal` enabled if the worker PowerShell window stays blank or sign-in prompts are not visible.
- Keep dry-run enabled for first test.
- Click `Run setup`.
- Confirm whether Graph sign-in/passkey flow opens visibly and whether the GUI log keeps updating.

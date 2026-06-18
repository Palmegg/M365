function New-EbgHandoffHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Result,
        [Parameter(Mandatory)][string] $OutputFolder
    )

    function ConvertTo-EbgHtmlValue([AllowNull()]$value) { [System.Net.WebUtility]::HtmlEncode([string]$value) }
    function Get-EbgTablePropertyNames([AllowNull()]$item) {
        if ($null -eq $item) { return @() }
        if ($item -is [System.Collections.IDictionary]) {
            return @($item.Keys | ForEach-Object { [string]$_ })
        }
        return @($item.PSObject.Properties.Name)
    }
    function Rows($items) {
        if (-not $items -or @($items).Count -eq 0) { return '<p>Ingen.</p>' }
        $props = @($items | ForEach-Object { Get-EbgTablePropertyNames $_ } | Select-Object -Unique)
        $head = '<tr>' + (($props | ForEach-Object { '<th>{0}</th>' -f (ConvertTo-EbgHtmlValue $_) }) -join '') + '</tr>'
        $body = foreach ($item in $items) {
            '<tr>' + (($props | ForEach-Object { '<td>{0}</td>' -f (ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $item -Name $_)) }) -join '') + '</tr>'
        }
        return '<table>' + $head + ($body -join "`n") + '</table>'
    }

    $path = Join-Path $OutputFolder 'handoff.html'
    New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null
    $account1 = Get-EbgObjectPropertyValue -InputObject $Result -Name 'Account1'
    $account2 = Get-EbgObjectPropertyValue -InputObject $Result -Name 'Account2'
    $group = Get-EbgObjectPropertyValue -InputObject $Result -Name 'Group'
    $fido2MethodPolicy = Get-EbgObjectPropertyValue -InputObject $Result -Name 'Fido2AuthenticationMethodPolicy'
    $registrationCampaign = Get-EbgObjectPropertyValue -InputObject $Result -Name 'RegistrationCampaign'
    $regularSSPR = Get-EbgObjectPropertyValue -InputObject $Result -Name 'RegularSSPR'
    $changed = @(Get-EbgObjectPropertyValue -InputObject $Result -Name 'CAPoliciesChanged')
    $already = @(Get-EbgObjectPropertyValue -InputObject $Result -Name 'CAPoliciesAlreadyExcluded')
    $failed = @(Get-EbgObjectPropertyValue -InputObject $Result -Name 'CAPoliciesFailed')
    $memberships = @(Get-EbgObjectPropertyValue -InputObject $Result -Name 'GroupMembership')
    $roleAssignments = @(Get-EbgObjectPropertyValue -InputObject $Result -Name 'RoleAssignments')
    $adminSSPR = Get-EbgObjectPropertyValue -InputObject $Result -Name 'AdminSSPR'
    $authenticationStrength = Get-EbgObjectPropertyValue -InputObject $Result -Name 'AuthenticationStrength'
    $breakGlassCAPolicy = Get-EbgObjectPropertyValue -InputObject $Result -Name 'BreakGlassCAPolicy'
    $temporaryAccessPasses = @(Get-EbgObjectPropertyValue -InputObject $Result -Name 'SensitiveTemporaryAccessPasses')
    $tapSummary = @(Get-EbgObjectPropertyValue -InputObject $Result -Name 'TemporaryAccessPassSummary')
    $tapCleanup = @(Get-EbgObjectPropertyValue -InputObject $Result -Name 'TAPCleanup')
    $fidoMethods = @(Get-EbgObjectPropertyValue -InputObject $Result -Name 'Fido2Methods')
    $extractedAAGUIDs = @(Get-EbgObjectPropertyValue -InputObject $Result -Name 'ExtractedAAGUIDs')
    $resultWarnings = @(Get-EbgObjectPropertyValue -InputObject $Result -Name 'Warnings')
    $changedTable = Rows $changed
    $alreadyTable = Rows $already
    $failedTable = Rows $failed
    $membershipTable = Rows $memberships
    $roleAssignmentTable = Rows $roleAssignments
    $temporaryAccessPassTable = Rows $temporaryAccessPasses
    $tapSummaryTable = Rows $tapSummary
    $tapCleanupTable = Rows $tapCleanup
    $fidoMethodsTable = Rows $fidoMethods
    $warnings = if ($resultWarnings.Count -gt 0) { '<ul>' + (($resultWarnings | ForEach-Object { '<li>{0}</li>' -f (ConvertTo-EbgHtmlValue $_) }) -join '') + '</ul>' } else { '<p>Ingen.</p>' }
    $html = @"
<!doctype html>
<html lang="da">
<head>
  <meta charset="utf-8">
  <title>CONFIDENTIAL - Break Glass Handoff</title>
  <style>
    body { font-family: Segoe UI, Arial, sans-serif; margin: 32px; color: #111827; line-height: 1.45; }
    .banner { background:#7f1d1d; color:white; padding:14px 18px; font-weight:700; font-size:22px; }
    table { border-collapse: collapse; width: 100%; margin: 10px 0 18px 0; }
    th, td { border: 1px solid #d1d5db; padding: 8px 10px; text-align: left; vertical-align: top; }
    th { background: #f3f4f6; }
    h2 { border-bottom: 1px solid #d1d5db; padding-bottom: 6px; margin-top: 28px; }
  </style>
</head>
<body>
  <div class="banner">CONFIDENTIAL - HANDOFF</div>
  <h1>Entra Break Glass handoff</h1>
  <p>Dette dokument er CONFIDENTIAL. Hvis Temporary Access Pass-koder fremgår, skal de flyttes til godkendt password manager eller fysisk nødprocedure og derefter fjernes fra lokale filer.</p>
  <h2>Tenant</h2>
  <table>
    <tr><th>Tenant navn</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $Result -Name 'TenantDisplayName'))</td></tr>
    <tr><th>Tenant ID</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $Result -Name 'TenantId'))</td></tr>
    <tr><th>Dato/tid</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $Result -Name 'Timestamp'))</td></tr>
    <tr><th>Konsulent / Graph konto</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $Result -Name 'Operator'))</td></tr>
    <tr><th>.onmicrosoft.com domæne</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $Result -Name 'OnMicrosoftDomain'))</td></tr>
  </table>
  <h2>Break-glass konti</h2>
  <table>
    <tr><th>Konto 1 display name</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $account1 -Name 'DisplayName'))</td></tr>
    <tr><th>Konto 1 UPN</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $account1 -Name 'UserPrincipalName'))</td></tr>
    <tr><th>Konto 1 status</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $account1 -Name 'Status'))</td></tr>
    <tr><th>Konto 1 enabled</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $account1 -Name 'AccountEnabled'))</td></tr>
    <tr><th>Konto 2 display name</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $account2 -Name 'DisplayName'))</td></tr>
    <tr><th>Konto 2 UPN</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $account2 -Name 'UserPrincipalName'))</td></tr>
    <tr><th>Konto 2 status</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $account2 -Name 'Status'))</td></tr>
    <tr><th>Konto 2 enabled</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $account2 -Name 'AccountEnabled'))</td></tr>
  </table>
  <h2>Temporary Access Pass</h2>
  <p>TAP oprettes i Phase 1 med one-time use = No og 2 timers varighed. Koderne må kun bruges til manuel FIDO2 bootstrap og skal fjernes efter Phase 2, hvis kunden vælger det.</p>
  <h3>TAP-koder fra Phase 1</h3>
  $temporaryAccessPassTable
  <h3>TAP status</h3>
  $tapSummaryTable
  <h3>TAP cleanup i Phase 2</h3>
  $tapCleanupTable
  <h2>Security group</h2>
  <table>
    <tr><th>Navn</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $group -Name 'DisplayName'))</td></tr>
    <tr><th>Object ID</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $group -Name 'Id'))</td></tr>
    <tr><th>Status</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $group -Name 'Status'))</td></tr>
  </table>
  <h2>Gruppemedlemskab</h2>
  $membershipTable
  <h2>FIDO2/passkey Authentication Method policy</h2>
  <table>
    <tr><th>Policy</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $fido2MethodPolicy -Name 'displayName'))</td></tr>
    <tr><th>State</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $fido2MethodPolicy -Name 'state'))</td></tr>
    <tr><th>Target group</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $fido2MethodPolicy -Name 'TargetGroupName'))</td></tr>
    <tr><th>Status</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $fido2MethodPolicy -Name 'Status'))</td></tr>
    <tr><th>Detail</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $fido2MethodPolicy -Name 'Detail'))</td></tr>
  </table>
  <h2>Authentication Methods registration campaign</h2>
  <table>
    <tr><th>Policy</th><td>Authentication Methods registration campaign</td></tr>
    <tr><th>Target group</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $registrationCampaign -Name 'TargetGroupName'))</td></tr>
    <tr><th>Status</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $registrationCampaign -Name 'Status'))</td></tr>
    <tr><th>Detail</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $registrationCampaign -Name 'Detail'))</td></tr>
  </table>
  <h2>Regular SSPR scope</h2>
  <p>Regular SSPR kan scopes til én valgt gruppe i Entra Password reset. Configuratoren opretter/opdaterer gruppen nedenfor, men selve SSPR targeting skal verificeres manuelt i Entra admin center.</p>
  <table>
    <tr><th>Group name</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $regularSSPR -Name 'DisplayName'))</td></tr>
    <tr><th>Object ID</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $regularSSPR -Name 'Id'))</td></tr>
    <tr><th>Status</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $regularSSPR -Name 'Status'))</td></tr>
    <tr><th>Dynamic membership rule</th><td><code>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $regularSSPR -Name 'MembershipRule'))</code></td></tr>
    <tr><th>Manual action</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $regularSSPR -Name 'ManualAction'))</td></tr>
  </table>
  <h2>Administratorrolle</h2>
  <p>Begge break-glass konti tildeles direkte Global Administrator på tenant scope (/).</p>
  $roleAssignmentTable
  <h2>Administrator-SSPR</h2>
  <table>
    <tr><th>Setting</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $adminSSPR -Name 'Setting'))</td></tr>
    <tr><th>Previous value</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $adminSSPR -Name 'PreviousValue'))</td></tr>
    <tr><th>Desired value</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $adminSSPR -Name 'DesiredValue'))</td></tr>
    <tr><th>Status</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $adminSSPR -Name 'Status'))</td></tr>
    <tr><th>Detail</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $adminSSPR -Name 'Detail'))</td></tr>
  </table>
  <h2>Conditional Access</h2>
  <h3>BreakGlass-FIDO2 authentication strength</h3>
  <table>
    <tr><th>Navn</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $authenticationStrength -Name 'displayName'))</td></tr>
    <tr><th>Object ID</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $authenticationStrength -Name 'id'))</td></tr>
    <tr><th>Status</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $authenticationStrength -Name 'Status'))</td></tr>
    <tr><th>Tilladte AAGUIDs</th><td>$(ConvertTo-EbgHtmlValue (@(Get-EbgObjectPropertyValue -InputObject $authenticationStrength -Name 'allowedAAGUIDs') -join ', '))</td></tr>
    <tr><th>Extracted AAGUIDs</th><td>$(ConvertTo-EbgHtmlValue ($extractedAAGUIDs -join ', '))</td></tr>
  </table>
  <h3>FIDO2 methods fundet på break-glass konti</h3>
  $fidoMethodsTable
  <h3>Dedikeret BreakGlass FIDO2 CA-policy</h3>
  <table>
    <tr><th>Navn</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $breakGlassCAPolicy -Name 'displayName'))</td></tr>
    <tr><th>Object ID</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $breakGlassCAPolicy -Name 'id'))</td></tr>
    <tr><th>State</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $breakGlassCAPolicy -Name 'state'))</td></tr>
    <tr><th>Status</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $breakGlassCAPolicy -Name 'Status'))</td></tr>
  </table>
  <h3>Eksisterende Conditional Access exclusions</h3>
  <table>
    <tr><th>CA exclusions valgt</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $Result -Name 'CAExclusionsEnabled'))</td></tr>
    <tr><th>Antal policies ændret</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $Result -Name 'CAPoliciesChangedCount'))</td></tr>
    <tr><th>Backup path</th><td>$(ConvertTo-EbgHtmlValue (Get-EbgObjectPropertyValue -InputObject $Result -Name 'CABackupPath'))</td></tr>
  </table>
  <h3>Policies ændret</h3>
  $changedTable
  <h3>Policies der allerede ekskluderede gruppen</h3>
  $alreadyTable
  <h3>Policies der fejlede</h3>
  $failedTable
  <h2>Advarsler/fejl</h2>
  $warnings
  <h2>Manuelle næste steps</h2>
  <ol>
    <li>Gem de genererede adgangskoder/TAP-koder sikkert efter intern/kundeprocedure og fjern lokale kopier efter handoff.</li>
    <li>Registrer to separate FIDO2 security keys pr. break-glass konto.</li>
    <li>Verificér at begge break-glass konti har direkte Global Administrator rolle.</li>
    <li>Hvis administrator-SSPR blev deaktiveret, vent op til 60 minutter og test derefter FIDO2/TAP onboarding igen.</li>
    <li>Hvis regular SSPR bruges, sæt Self service password reset til Selected og vælg SSPR-scope-gruppen fra dokumentet.</li>
    <li>Verificér at begge break-glass konti kan logge ind.</li>
    <li>Den dedikerede BreakGlass FIDO2 CA-policy oprettes som disabled. Valider sign-in logs og authentication strength før den sættes til enabled.</li>
    <li>Verificér at kontiene er medlem af CA-BreakGlass-Exclude.</li>
    <li>Verificér at gruppen er ekskluderet fra de ønskede Conditional Access-politikker, hvis funktionen blev valgt.</li>
    <li>Dokumentér hvor credentials opbevares.</li>
    <li>Aftal periodisk test/review med kunden.</li>
  </ol>
</body>
</html>
"@
    Set-Content -LiteralPath $path -Value $html -Encoding UTF8
    $sync.State.HandoffPath = $path
    return $path
}

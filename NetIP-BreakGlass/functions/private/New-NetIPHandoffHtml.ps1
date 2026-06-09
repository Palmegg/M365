function New-NetIPHandoffHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Result,
        [Parameter(Mandatory)][string] $OutputFolder
    )

    function H([AllowNull()]$value) { [System.Net.WebUtility]::HtmlEncode([string]$value) }
    function Rows($items) {
        if (-not $items -or @($items).Count -eq 0) { return '<p>Ingen.</p>' }
        $props = @($items | ForEach-Object { $_.PSObject.Properties.Name } | Select-Object -Unique)
        $head = '<tr>' + (($props | ForEach-Object { '<th>{0}</th>' -f (H $_) }) -join '') + '</tr>'
        $body = foreach ($item in $items) {
            '<tr>' + (($props | ForEach-Object { '<td>{0}</td>' -f (H (Get-NetIPObjectPropertyValue -InputObject $item -Name $_)) }) -join '') + '</tr>'
        }
        return '<table>' + $head + ($body -join "`n") + '</table>'
    }

    $path = Join-Path $OutputFolder 'handoff.html'
    $changedTable = Rows @($Result.CAPoliciesChanged)
    $alreadyTable = Rows @($Result.CAPoliciesAlreadyExcluded)
    $failedTable = Rows @($Result.CAPoliciesFailed)
    $membershipTable = Rows @($Result.GroupMembership)
    $warnings = if (@($Result.Warnings).Count -gt 0) { '<ul>' + (($Result.Warnings | ForEach-Object { '<li>{0}</li>' -f (H $_) }) -join '') + '</ul>' } else { '<p>Ingen.</p>' }
    $html = @"
<!doctype html>
<html lang="da">
<head>
  <meta charset="utf-8">
  <title>CONFIDENTIAL - NetIP Break Glass Handoff</title>
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
  <h1>NetIP Entra Break Glass handoff</h1>
  <p>Dette dokument indeholder ikke adgangskoder, tokens eller secrets.</p>
  <h2>Tenant</h2>
  <table>
    <tr><th>Tenant navn</th><td>$(H $Result.TenantDisplayName)</td></tr>
    <tr><th>Tenant ID</th><td>$(H $Result.TenantId)</td></tr>
    <tr><th>Dato/tid</th><td>$(H $Result.Timestamp)</td></tr>
    <tr><th>Konsulent / Graph konto</th><td>$(H $Result.Operator)</td></tr>
    <tr><th>.onmicrosoft.com domæne</th><td>$(H $Result.OnMicrosoftDomain)</td></tr>
  </table>
  <h2>Break-glass konti</h2>
  <table>
    <tr><th>Konto 1 display name</th><td>$(H $Result.Account1.DisplayName)</td></tr>
    <tr><th>Konto 1 UPN</th><td>$(H $Result.Account1.UserPrincipalName)</td></tr>
    <tr><th>Konto 1 status</th><td>$(H $Result.Account1.Status)</td></tr>
    <tr><th>Konto 2 display name</th><td>$(H $Result.Account2.DisplayName)</td></tr>
    <tr><th>Konto 2 UPN</th><td>$(H $Result.Account2.UserPrincipalName)</td></tr>
    <tr><th>Konto 2 status</th><td>$(H $Result.Account2.Status)</td></tr>
  </table>
  <h2>Security group</h2>
  <table>
    <tr><th>Navn</th><td>$(H $Result.Group.DisplayName)</td></tr>
    <tr><th>Object ID</th><td>$(H $Result.Group.Id)</td></tr>
    <tr><th>Status</th><td>$(H $Result.Group.Status)</td></tr>
  </table>
  <h2>Gruppemedlemskab</h2>
  $membershipTable
  <h2>Conditional Access</h2>
  <table>
    <tr><th>CA exclusions valgt</th><td>$(H $Result.CAExclusionsEnabled)</td></tr>
    <tr><th>Antal policies ændret</th><td>$(H $Result.CAPoliciesChangedCount)</td></tr>
    <tr><th>Backup path</th><td>$(H $Result.CABackupPath)</td></tr>
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
    <li>Gem de genererede adgangskoder sikkert efter intern/kundeprocedure.</li>
    <li>Konfigurer MFA/FIDO2/passkey manuelt, hvis det indgår i kundens standard.</li>
    <li>Tildel relevante administratorroller manuelt, hvis det indgår i kundens break-glass procedure.</li>
    <li>Verificér at begge break-glass konti kan logge ind.</li>
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

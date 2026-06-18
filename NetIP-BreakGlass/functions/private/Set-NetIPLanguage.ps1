function Set-NetIPLanguage {
    [CmdletBinding()]
    param([ValidateSet('da-DK','en-US')][string] $Language = 'da-DK')

    if (-not $sync.Form) { return }
    if (-not $sync.Form.Dispatcher.CheckAccess()) {
        [void]$sync.Form.Dispatcher.Invoke([System.Action]{ Set-NetIPLanguage -Language $Language | Out-Null })
        return
    }

    $sync.State.Language = $Language
    $strings = @(
        @{ Da = 'Entra Break Glass Configurator'; En = 'Entra Break Glass Configurator' }
        @{ Da = 'Simpel Microsoft Graph-baseret opsætning af break-glass konti og CA-exclude gruppe.'; En = 'Simple Microsoft Graph-based setup of break-glass accounts and a CA exclude group.' }
        @{ Da = '1. Velkommen'; En = '1. Welcome' }
        @{ Da = '2. Forbind'; En = '2. Connect' }
        @{ Da = '3. Discovery'; En = '3. Discovery' }
        @{ Da = '4. Konfiguration'; En = '4. Configuration' }
        @{ Da = '5. Plan'; En = '5. Plan' }
        @{ Da = '6. Udfør'; En = '6. Apply' }
        @{ Da = '7. Handoff'; En = '7. Handoff' }
        @{ Da = 'Sprog'; En = 'Language' }
        @{ Da = 'Velkommen'; En = 'Welcome' }
        @{ Da = 'Dette værktøj opretter to break-glass konti på tenantens .onmicrosoft.com domæne, opretter gruppen CA-BreakGlass-Exclude og kan valgfrit ekskludere gruppen fra eksisterende Conditional Access-politikker.'; En = 'This tool creates two break-glass accounts on the tenant .onmicrosoft.com domain, creates the CA-BreakGlass-Exclude group, and can optionally exclude the group from existing Conditional Access policies.' }
        @{ Da = 'Værktøjet forbinder kun til Microsoft Graph. Det bruger ikke Azure, PIM, RMAU, FIDO2, Log Analytics eller Sentinel.'; En = 'The tool connects only to Microsoft Graph. It does not use Azure, PIM, RMAU, FIDO2, Log Analytics, or Sentinel.' }
        @{ Da = 'Discovery og Plan foretager ingen ændringer. Ændringer udføres først i trinnet Udfør.'; En = 'Discovery and Plan make no changes. Changes are performed only in the Apply step.' }
        @{ Da = 'Midlertidige adgangskoder vises kun én gang og gemmes ikke i log, JSON eller handoff dokument.'; En = 'Temporary passwords are shown only once and are not saved to logs, JSON, or the handoff document.' }
        @{ Da = 'Jeg forstår at dette script ændrer sikkerhedskritisk tenant-konfiguration.'; En = 'I understand that this script changes security-critical tenant configuration.' }
        @{ Da = 'Forbind'; En = 'Connect' }
        @{ Da = 'Forbind én gang til Microsoft Graph. Samme session bruges til discovery, plan og udførsel.'; En = 'Connect once to Microsoft Graph. The same session is used for discovery, plan, and apply.' }
        @{ Da = 'Requested Graph scopes:'; En = 'Requested Graph scopes:' }
        @{ Da = 'Forbind til Microsoft 365 tenant'; En = 'Connect to Microsoft 365 tenant' }
        @{ Da = 'Forbundet:'; En = 'Connected:' }
        @{ Da = 'Konto:'; En = 'Account:' }
        @{ Da = 'Tenant navn:'; En = 'Tenant name:' }
        @{ Da = '.onmicrosoft.com domæne:'; En = '.onmicrosoft.com domain:' }
        @{ Da = 'Nej'; En = 'No' }
        @{ Da = 'Ja'; En = 'Yes' }
        @{ Da = 'Discovery er read-only og viser aktive Global Administrator-konti, de aktuelle target UPNs, CA-BreakGlass-Exclude og eksisterende Conditional Access-politikker.'; En = 'Discovery is read-only and shows active Global Administrator accounts, the current target UPNs, CA-BreakGlass-Exclude, and existing Conditional Access policies.' }
        @{ Da = 'Kør discovery'; En = 'Run discovery' }
        @{ Da = 'Konfiguration'; En = 'Configuration' }
        @{ Da = 'Account 1 display name'; En = 'Account 1 display name' }
        @{ Da = 'Account 1 UPN prefix'; En = 'Account 1 UPN prefix' }
        @{ Da = 'Account 2 display name'; En = 'Account 2 display name' }
        @{ Da = 'Account 2 UPN prefix'; En = 'Account 2 UPN prefix' }
        @{ Da = 'Skift neutrale navne'; En = 'Cycle neutral names' }
        @{ Da = "Cykler mellem neutrale display names og UPN-prefixes uden 'BreakGlass' i navnet."; En = "Cycles through neutral display names and UPN prefixes without 'BreakGlass' in the name." }
        @{ Da = 'Domain'; En = 'Domain' }
        @{ Da = 'Final UPN preview'; En = 'Final UPN preview' }
        @{ Da = 'Security group name'; En = 'Security group name' }
        @{ Da = 'Security group description'; En = 'Security group description' }
        @{ Da = 'FIDO2 authentication strength'; En = 'FIDO2 authentication strength' }
        @{ Da = 'AAGUID kildebruger'; En = 'AAGUID source user' }
        @{ Da = 'Hent AAGUID'; En = 'Fetch AAGUID' }
        @{ Da = 'Tilladte AAGUIDs'; En = 'Allowed AAGUIDs' }
        @{ Da = 'Auth strength navn'; En = 'Auth strength name' }
        @{ Da = 'BG CA policy navn'; En = 'BG CA policy name' }
        @{ Da = 'Opret/opdater BreakGlass-FIDO2 authentication strength med AAGUID-restriction'; En = 'Create/update BreakGlass-FIDO2 authentication strength with AAGUID restriction' }
        @{ Da = 'Opret dedikeret CA-policy der kræver BreakGlass-FIDO2 for CA-BreakGlass-Exclude'; En = 'Create dedicated CA policy requiring BreakGlass-FIDO2 for CA-BreakGlass-Exclude' }
        @{ Da = 'Opret CA-policy som enabled i stedet for report-only'; En = 'Create CA policy as enabled instead of report-only' }
        @{ Da = 'Anbefaling: lad CA-politikken være report-only indtil begge konti har to registrerede og testede FIDO2 keys.'; En = 'Recommendation: keep the CA policy in report-only until both accounts have two registered and tested FIDO2 keys.' }
        @{ Da = 'Opret brugere hvis de ikke findes'; En = 'Create users if missing' }
        @{ Da = 'Opret gruppen CA-BreakGlass-Exclude hvis den ikke findes'; En = 'Create CA-BreakGlass-Exclude if missing' }
        @{ Da = 'Tilføj break-glass konti til CA-BreakGlass-Exclude'; En = 'Add break-glass accounts to CA-BreakGlass-Exclude' }
        @{ Da = 'Deaktivér administrator-SSPR tenant-wide'; En = 'Disable administrator SSPR tenant-wide' }
        @{ Da = "Admin SSPR kan ikke slås fra kun for de to konti. Hvis valgt, deaktiveres administrator-SSPR for alle administratorroller i tenant'en."; En = 'Admin SSPR cannot be disabled only for the two accounts. If selected, administrator SSPR is disabled for all administrator roles in the tenant.' }
        @{ Da = 'Ekskludér CA-BreakGlass-Exclude fra alle eksisterende Conditional Access-politikker'; En = 'Exclude CA-BreakGlass-Exclude from all existing Conditional Access policies' }
        @{ Da = 'Dette ændrer eksisterende Conditional Access-politikker. Der oprettes backup før ændringerne udføres.'; En = 'This changes existing Conditional Access policies. A backup is created before changes are applied.' }
        @{ Da = 'Generér plan'; En = 'Generate plan' }
        @{ Da = 'Udfør'; En = 'Apply' }
        @{ Da = 'Dette er det eneste trin der ændrer tenant-konfiguration.'; En = 'This is the only step that changes tenant configuration.' }
        @{ Da = 'Anvend konfiguration'; En = 'Apply configuration' }
        @{ Da = 'Handoff-dokumentet genereres efter udførsel. Det indeholder ikke passwords.'; En = 'The handoff document is generated after apply. It does not contain passwords.' }
        @{ Da = 'Output folder'; En = 'Output folder' }
        @{ Da = 'Handoff dokument'; En = 'Handoff document' }
        @{ Da = 'Åbn outputmappe'; En = 'Open output folder' }
        @{ Da = 'Åbn handoff'; En = 'Open handoff' }
        @{ Da = 'Klar'; En = 'Ready' }
    )

    function Convert-AppText([AllowNull()][string] $Text) {
        if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }
        foreach ($entry in $strings) {
            if ($Text -eq $entry.Da -or $Text -eq $entry.En) {
                if ($Language -eq 'en-US') { return $entry.En }
                return $entry.Da
            }
        }
        return $Text
    }

    function Update-TextObject([AllowNull()] $Object) {
        if ($null -eq $Object) { return }
        if ($Object -is [System.Windows.Controls.ComboBoxItem]) { return }
        if ($Object -is [System.Windows.Controls.TextBlock]) {
            $Object.Text = Convert-AppText $Object.Text
        }
        elseif ($Object -is [System.Windows.Controls.Button] -or $Object -is [System.Windows.Controls.CheckBox] -or $Object -is [System.Windows.Controls.Primitives.ToggleButton]) {
            if ($Object.Content -is [string]) { $Object.Content = Convert-AppText ([string]$Object.Content) }
        }
        elseif ($Object -is [System.Windows.Controls.TextBox]) {
            if (-not $Object.AcceptsReturn -and $Object.IsReadOnly -and -not [string]::IsNullOrWhiteSpace($Object.Text)) {
                $Object.Text = Convert-AppText $Object.Text
            }
        }
        if (-not ($Object -is [System.Windows.DependencyObject])) { return }
        foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($Object)) {
            Update-TextObject $child
        }
    }

    $sync.Form.Title = "$($sync.App.Name) v$($sync.App.Version)"
    Update-TextObject $sync.Form
    if ($sync.WPFAppTitle) { $sync.WPFAppTitle.Text = $sync.App.Name }
    if ($sync.WPFVersionBadge) { $sync.WPFVersionBadge.Text = "v$($sync.App.Version)" }
}

function Update-EbgAAGUIDSourceOptions {
    [CmdletBinding()]
    param()

    if (-not $sync.WPFAAGUIDSourceUser) { return }

    $domain = [string]$sync.State.OnMicrosoftDomain
    if ([string]::IsNullOrWhiteSpace($domain)) { return }

    $prefix1 = if ([string]$sync.State.StartMode -eq 'Phase2' -and $sync.WPFPhase2UserPrefix1 -and -not [string]::IsNullOrWhiteSpace($sync.WPFPhase2UserPrefix1.Text)) {
        $sync.WPFPhase2UserPrefix1.Text.Trim()
    }
    elseif ($sync.WPFUserPrefix1) {
        $sync.WPFUserPrefix1.Text.Trim()
    }
    else {
        ''
    }
    $prefix2 = if ([string]$sync.State.StartMode -eq 'Phase2' -and $sync.WPFPhase2UserPrefix2 -and -not [string]::IsNullOrWhiteSpace($sync.WPFPhase2UserPrefix2.Text)) {
        $sync.WPFPhase2UserPrefix2.Text.Trim()
    }
    elseif ($sync.WPFUserPrefix2) {
        $sync.WPFUserPrefix2.Text.Trim()
    }
    else {
        ''
    }
    $upn1 = "$prefix1@$domain"
    $upn2 = "$prefix2@$domain"

    if ($sync.WPFAAGUIDSourceUser.Items.Count -ge 3) {
        $sync.WPFAAGUIDSourceUser.Items[0].Content = "Account 1 - $upn1"
        $sync.WPFAAGUIDSourceUser.Items[1].Content = "Account 2 - $upn2"
        $sync.WPFAAGUIDSourceUser.Items[2].Content = 'Other user UPN'
    }
}

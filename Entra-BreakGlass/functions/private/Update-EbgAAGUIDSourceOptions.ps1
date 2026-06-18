function Update-EbgAAGUIDSourceOptions {
    [CmdletBinding()]
    param()

    if (-not $sync.WPFAAGUIDSourceUser) { return }

    $domain = [string]$sync.State.OnMicrosoftDomain
    if ([string]::IsNullOrWhiteSpace($domain)) { return }

    $upn1 = "$(if($sync.WPFUserPrefix1){$sync.WPFUserPrefix1.Text.Trim()})@$domain"
    $upn2 = "$(if($sync.WPFUserPrefix2){$sync.WPFUserPrefix2.Text.Trim()})@$domain"

    if ($sync.WPFAAGUIDSourceUser.Items.Count -ge 3) {
        $sync.WPFAAGUIDSourceUser.Items[0].Content = "Account 1 - $upn1"
        $sync.WPFAAGUIDSourceUser.Items[1].Content = "Account 2 - $upn2"
        $sync.WPFAAGUIDSourceUser.Items[2].Content = 'Other user UPN'
    }
}

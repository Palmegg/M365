function Update-EbgAAGUIDSourceOptions {
    [CmdletBinding()]
    param()

    if ($sync.WPFAAGUIDCustomUser -and [string]::IsNullOrWhiteSpace($sync.WPFAAGUIDCustomUser.Text) -and $sync.State.GraphAccount) {
        $sync.WPFAAGUIDCustomUser.Text = [string]$sync.State.GraphAccount
    }
}

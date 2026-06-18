function Invoke-EbgFetchAAGUIDs {
    [CmdletBinding()]
    param()

    if (-not $sync.State.GraphConnected -and -not $sync.App.Mock) {
        [System.Windows.MessageBox]::Show("Du skal først forbinde til Microsoft Graph under trinnet 'Forbind'.", $sync.App.Name, 'OK', 'Warning') | Out-Null
        return
    }
    if ($sync.UI.ProcessRunning) {
        [System.Windows.MessageBox]::Show('Der kører allerede en opgave. Vent til den er færdig.', $sync.App.Name, 'OK', 'Information') | Out-Null
        return
    }

    $sync.UI.ProcessRunning = $true
    if ($sync.WPFFetchAAGUIDs) { $sync.WPFFetchAAGUIDs.IsEnabled = $false }
    if ($sync.WPFProgressBar) { $sync.WPFProgressBar.IsIndeterminate = $true }
    Update-EbgUIState | Out-Null

    try {
        $config = Get-EbgConfigFromUI
        Write-EbgStatus -Busy -Message 'Henter FIDO2 AAGUIDs...'
        [System.Windows.Forms.Application]::DoEvents()

        Ensure-EbgGraphContext
        [System.Windows.Forms.Application]::DoEvents()

        $sourceUpn = Get-EbgAAGUIDSourceUserPrincipalName -Config $config
        Write-EbgLog -Message "Henter registrerede FIDO2/passkey methods fra: $sourceUpn"
        [System.Windows.Forms.Application]::DoEvents()

        $methods = @(Get-EbgFido2MethodsForUser -UserPrincipalName $sourceUpn)
        if ($methods.Count -lt 1) {
            Write-EbgStatus -Message "Ingen FIDO2/passkey methods fundet på $sourceUpn."
            [System.Windows.MessageBox]::Show("Der blev ikke fundet registrerede FIDO2/passkey methods på $sourceUpn. Log ind på kontoen via https://aka.ms/mfasetup og registrer security keys først.", $sync.App.Name, 'OK', 'Warning') | Out-Null
            return
        }

        $aaGuids = @($methods | ForEach-Object {
            [string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'aaGuid')
        } | Where-Object { $_ -match '^[0-9a-fA-F-]{36}$' } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)

        foreach ($method in $methods) {
            $name = [string](Get-EbgObjectPropertyValue -InputObject $method -Name 'displayName')
            $model = [string](Get-EbgObjectPropertyValue -InputObject $method -Name 'model')
            $guid = [string](Get-EbgObjectPropertyValue -InputObject $method -Name 'aaGuid')
            $attestation = [string](Get-EbgObjectPropertyValue -InputObject $method -Name 'attestationLevel')
            $type = [string](Get-EbgObjectPropertyValue -InputObject $method -Name 'passkeyType')
            Write-EbgLog -Level PASS -Message "FIDO2 method fundet: user=$sourceUpn; name=$name; model=$model; aaGuid=$guid; attestation=$attestation; type=$type"
        }

        if ($aaGuids.Count -lt 1) {
            Write-EbgStatus -Message 'FIDO2 methods fundet, men ingen gyldige AAGUIDs kunne læses.'
            [System.Windows.MessageBox]::Show("FIDO2/passkey methods blev fundet på $sourceUpn, men Microsoft Graph returnerede ingen gyldige AAGUIDs.", $sync.App.Name, 'OK', 'Warning') | Out-Null
            return
        }

        $existing = @(ConvertFrom-EbgAAGUIDText -Text $sync.WPFAAGUIDs.Text)
        $merged = @($existing + $aaGuids | Select-Object -Unique)
        $sync.WPFAAGUIDs.Text = ($merged -join [Environment]::NewLine)
        $sync.State.AAGUIDsFetched = $true
        Write-EbgStatus -Message "AAGUIDs hentet fra $sourceUpn. Tryk nu 'Kør Phase 2' for at oprette auth strength og disabled CA-policy."
        [System.Windows.MessageBox]::Show("AAGUIDs hentet fra ${sourceUpn}:`n`n$($aaGuids -join [Environment]::NewLine)", $sync.App.Name, 'OK', 'Information') | Out-Null
    }
    catch {
        $message = ConvertTo-EbgRedactedError -ErrorRecord $_
        Write-EbgLog -Level ERROR -Message $message
        Write-EbgStatus -Message 'Hentning af AAGUID fejlede.'
        [System.Windows.MessageBox]::Show($message, $sync.App.Name, 'OK', 'Error') | Out-Null
    }
    finally {
        $sync.UI.ProcessRunning = $false
        if ($sync.WPFProgressBar) { $sync.WPFProgressBar.IsIndeterminate = $false }
        if ($sync.WPFFetchAAGUIDs) { $sync.WPFFetchAAGUIDs.IsEnabled = $true }
        Update-EbgUIState | Out-Null
    }
}

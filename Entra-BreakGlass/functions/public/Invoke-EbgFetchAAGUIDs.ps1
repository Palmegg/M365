function Invoke-EbgFetchAAGUIDs {
    [CmdletBinding()]
    param()

    if (-not $sync.State.GraphConnected -and -not $sync.App.Mock) {
        [System.Windows.MessageBox]::Show("Du skal først forbinde til Microsoft Graph under trinnet 'Forbind'.", $sync.App.Name, 'OK', 'Warning') | Out-Null
        return
    }

    $config = Get-EbgConfigFromUI
    Invoke-EbgRunspace -ArgumentList @($config) -ScriptBlock {
        param($config)
        Write-EbgStatus -Busy -Message 'Henter FIDO2 AAGUID...'
        $sourceUpn = Get-EbgAAGUIDSourceUserPrincipalName -Config $config
        Write-EbgLog -Message "Henter FIDO2 methods fra: $sourceUpn"
        $methods = @(Get-EbgFido2MethodsForUser -UserPrincipalName $sourceUpn)
        if ($methods.Count -lt 1) {
            Write-EbgStatus -Message 'Ingen FIDO2 methods fundet.'
            $sync.Form.Dispatcher.Invoke([System.Action]{
                [System.Windows.MessageBox]::Show("Der blev ikke fundet registrerede FIDO2/passkey methods på $sourceUpn.", $sync.App.Name, 'OK', 'Warning') | Out-Null
            })
            return
        }

        $aaGuids = @($methods | ForEach-Object {
            [string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'aaGuid')
        } | Where-Object { $_ -match '^[0-9a-fA-F-]{36}$' } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)

        $details = @($methods | ForEach-Object {
            $name = [string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'displayName')
            $model = [string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'model')
            $guid = [string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'aaGuid')
            $attestation = [string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'attestationLevel')
            $type = [string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'passkeyType')
            "$name / $model / $guid / attestation=$attestation / type=$type"
        })

        foreach ($detail in $details) { Write-EbgLog -Level PASS -Message "FIDO2 method: $detail" }
        if ($aaGuids.Count -lt 1) {
            Write-EbgStatus -Message 'Ingen gyldige AAGUIDs fundet.'
            $sync.Form.Dispatcher.Invoke([System.Action]{
                [System.Windows.MessageBox]::Show("FIDO2 methods blev fundet, men ingen gyldige AAGUIDs kunne læses.", $sync.App.Name, 'OK', 'Warning') | Out-Null
            })
            return
        }

        $sync.Form.Dispatcher.Invoke([System.Action]{
            $existing = @(ConvertFrom-EbgAAGUIDText -Text $sync.WPFAAGUIDs.Text)
            $merged = @($existing + $aaGuids | Select-Object -Unique)
            $sync.WPFAAGUIDs.Text = ($merged -join [Environment]::NewLine)
        })
        Write-EbgStatus -Message "AAGUID hentet fra $sourceUpn."
    }
}
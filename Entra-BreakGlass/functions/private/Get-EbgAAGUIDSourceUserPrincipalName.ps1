function Get-EbgAAGUIDSourceUserPrincipalNames {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable] $Config)

    return @($sync.Form.Dispatcher.Invoke([func[object[]]]{
        $sources = [System.Collections.Generic.List[string]]::new()
        foreach ($comboName in @('WPFAAGUIDSourceAdmin1','WPFAAGUIDSourceAdmin2')) {
            $combo = $sync[$comboName]
            if (-not $combo -or -not $combo.SelectedItem) { continue }
            if ($comboName -eq 'WPFAAGUIDSourceAdmin2' -and -not [bool]$sync.State.AAGUIDSource2Visible) { continue }
            $upn = [string](Get-EbgObjectPropertyValue -InputObject $combo.SelectedItem -Name 'userPrincipalName')
            if (-not [string]::IsNullOrWhiteSpace($upn)) {
                $sources.Add($upn)
            }
        }

        $unique = @($sources | Select-Object -Unique)
        if ($unique.Count -lt 1) {
            throw 'Vælg mindst én Global Administrator-konto som AAGUID-kilde. Kør Discovery eller Hent Global Admins først.'
        }

        foreach ($upn in $unique) {
            if ($upn -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
                throw "AAGUID kildebrugeren skal være et fuldt UPN. Værdi: $upn"
            }
        }

        return [object[]]$unique
    }))
}

function Get-EbgAAGUIDSourceUserPrincipalName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable] $Config)

    return @(Get-EbgAAGUIDSourceUserPrincipalNames -Config $Config | Select-Object -First 1)[0]
}

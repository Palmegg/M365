function Get-EbgSelectedRegularSSPRUsers {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable] $Config)

    $users = @(
        Get-EbgObjectPropertyValue -InputObject $Config -Name 'RegularSSPRAccount1'
        Get-EbgObjectPropertyValue -InputObject $Config -Name 'RegularSSPRAccount2'
    ) | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'id'))
    }

    if ($users.Count -gt 1) {
        $ids = @($users | ForEach-Object { [string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'id') })
        if (($ids | Select-Object -Unique).Count -ne $ids.Count) {
            throw 'Vælg to forskellige Global Administrator-konti til regular SSPR exclusion.'
        }
    }

    return @($users)
}

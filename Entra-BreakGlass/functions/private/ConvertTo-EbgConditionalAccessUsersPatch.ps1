function ConvertTo-EbgConditionalAccessUsersPatch {
    [CmdletBinding()]
    param(
        [AllowNull()] $Users,
        [Parameter(Mandatory)][string] $GroupId
    )

    $patch = [ordered]@{}
    $arrayProperties = @(
        'includeUsers',
        'excludeUsers',
        'includeGroups',
        'excludeGroups',
        'includeRoles',
        'excludeRoles'
    )

    foreach ($propertyName in $arrayProperties) {
        $values = @(Get-EbgObjectPropertyValue -InputObject $Users -Name $propertyName | Where-Object { $null -ne $_ -and [string]$_ -ne '' })
        if ($propertyName -eq 'excludeGroups') {
            $values = @($values + $GroupId | Select-Object -Unique)
        }
        if ($values.Count -gt 0 -or $propertyName -eq 'excludeGroups') {
            $patch[$propertyName] = @($values)
        }
    }

    foreach ($propertyName in @('includeGuestsOrExternalUsers', 'excludeGuestsOrExternalUsers')) {
        $value = Get-EbgObjectPropertyValue -InputObject $Users -Name $propertyName
        if ($null -ne $value) {
            $patch[$propertyName] = ConvertTo-EbgPlainHashtable -InputObject $value -MaxDepth 10
        }
    }

    $hasIncludeTarget = @(
        @($patch['includeUsers']).Count
        @($patch['includeGroups']).Count
        @($patch['includeRoles']).Count
        if ($patch.Contains('includeGuestsOrExternalUsers')) { 1 } else { 0 }
    ) | Where-Object { $_ -gt 0 }

    if (@($hasIncludeTarget).Count -lt 1) {
        return $null
    }

    return $patch
}

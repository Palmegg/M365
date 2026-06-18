function Ensure-EbgAuthenticationStrength {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $DisplayName,
        [Parameter(Mandatory)][string] $Description,
        [Parameter(Mandatory)][string[]] $AllowedAAGUIDs,
        [Parameter(Mandatory)][bool] $Apply
    )

    $allowed = @($AllowedAAGUIDs | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
    if ($allowed.Count -lt 1) {
        throw 'Der skal mindst være ét AAGUID før authentication strength kan oprettes.'
    }

    if (-not $Apply -or $sync.App.Mock) {
        return [pscustomobject]@{
            id = 'planned-auth-strength'
            displayName = $DisplayName
            allowedAAGUIDs = $allowed
            Status = if ($Apply) { 'Created' } else { 'PlannedCreate' }
        }
    }

    $existing = Get-EbgAuthenticationStrengthByName -DisplayName $DisplayName
    if (-not $existing) {
        Write-EbgLog -Message "Opretter authentication strength: $DisplayName"
        $body = @{
            displayName = $DisplayName
            description = $Description
            requirementsSatisfied = 'mfa'
            allowedCombinations = @('fido2')
            combinationConfigurations = @(
                @{
                    '@odata.type' = '#microsoft.graph.fido2CombinationConfiguration'
                    allowedAAGUIDs = $allowed
                    appliesToCombinations = @('fido2')
                }
            )
        }
        $created = Invoke-EbgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/authenticationStrength/policies' -Body $body
        $created | Add-Member -MemberType NoteProperty -Name Status -Value 'Created' -Force
        $created | Add-Member -MemberType NoteProperty -Name allowedAAGUIDs -Value $allowed -Force
        return $created
    }

    $strengthId = [string](Get-EbgObjectPropertyValue -InputObject $existing -Name 'id')
    $configs = @(Get-EbgGraphCollection -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/authenticationStrength/policies/$strengthId/combinationConfigurations")
    $fidoConfig = $configs | Where-Object {
        $type = [string](Get-EbgObjectPropertyValue -InputObject $_ -Name '@odata.type')
        $applies = @(Get-EbgObjectPropertyValue -InputObject $_ -Name 'appliesToCombinations')
        $type -match 'fido2CombinationConfiguration' -or $applies -contains 'fido2'
    } | Select-Object -First 1

    if (-not $fidoConfig) {
        Write-EbgLog -Message "Tilføjer FIDO2 AAGUID restriction til authentication strength: $DisplayName"
        $body = @{
            '@odata.type' = '#microsoft.graph.fido2CombinationConfiguration'
            allowedAAGUIDs = $allowed
            appliesToCombinations = @('fido2')
        }
        Invoke-EbgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/authenticationStrength/policies/$strengthId/combinationConfigurations" -Body $body | Out-Null
        $existing | Add-Member -MemberType NoteProperty -Name Status -Value 'Updated' -Force
        $existing | Add-Member -MemberType NoteProperty -Name allowedAAGUIDs -Value $allowed -Force
        return $existing
    }

    $existingAAGUIDs = @(Get-EbgObjectPropertyValue -InputObject $fidoConfig -Name 'allowedAAGUIDs') | ForEach-Object { [string]$_ }
    $merged = @($existingAAGUIDs + $allowed | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique)
    if (@($merged | Where-Object { $existingAAGUIDs -notcontains $_ }).Count -gt 0) {
        $configId = [string](Get-EbgObjectPropertyValue -InputObject $fidoConfig -Name 'id')
        Write-EbgLog -Message "Opdaterer AAGUID-listen på authentication strength: $DisplayName"
        Invoke-EbgGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/authenticationStrength/policies/$strengthId/combinationConfigurations/$configId" -Body @{ allowedAAGUIDs = $merged } | Out-Null
        $status = 'Updated'
    }
    else {
        $status = 'AlreadyExists'
    }

    $existing | Add-Member -MemberType NoteProperty -Name Status -Value $status -Force
    $existing | Add-Member -MemberType NoteProperty -Name allowedAAGUIDs -Value $merged -Force
    return $existing
}
function Set-EbgAdminSSPRDisabled {
    [CmdletBinding()]
    param([Parameter(Mandatory)][bool] $Apply)

    $policy = Get-EbgAuthorizationPolicy
    $current = [bool](Get-EbgObjectPropertyValue -InputObject $policy -Name 'allowedToUseSSPR')

    if (-not $current) {
        Write-EbgLog -Level PASS -Message 'Administrator-SSPR er allerede deaktiveret.'
        return [pscustomobject]@{
            Setting = 'allowedToUseSSPR'
            PreviousValue = $false
            DesiredValue = $false
            Status = 'AlreadyDisabled'
            Detail = 'Administrator-SSPR was already disabled.'
        }
    }

    if (-not $Apply -or $sync.App.Mock) {
        Write-EbgLog -Level PASS -Message 'Administrator-SSPR planlagt deaktiveret.'
        return [pscustomobject]@{
            Setting = 'allowedToUseSSPR'
            PreviousValue = $true
            DesiredValue = $false
            Status = if ($Apply) { 'Disabled' } else { 'PlannedDisable' }
            Detail = 'Administrator-SSPR is tenant-wide for administrator roles.'
        }
    }

    Write-EbgLog -Message 'Deaktiverer administrator-SSPR tenant-wide...'
    Invoke-EbgGraphRequest -Method PATCH -Uri 'https://graph.microsoft.com/v1.0/policies/authorizationPolicy' -Body @{ allowedToUseSSPR = $false } | Out-Null
    Write-EbgLog -Level PASS -Message 'Administrator-SSPR er deaktiveret tenant-wide.'
    return [pscustomobject]@{
        Setting = 'allowedToUseSSPR'
        PreviousValue = $true
        DesiredValue = $false
        Status = 'Disabled'
        Detail = 'Policy changes can take up to 60 minutes to take effect.'
    }
}
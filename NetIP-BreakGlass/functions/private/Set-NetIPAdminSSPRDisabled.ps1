function Set-NetIPAdminSSPRDisabled {
    [CmdletBinding()]
    param([Parameter(Mandatory)][bool] $Apply)

    $policy = Get-NetIPAuthorizationPolicy
    $current = [bool](Get-NetIPObjectPropertyValue -InputObject $policy -Name 'allowedToUseSSPR')

    if (-not $current) {
        Write-NetIPLog -Level PASS -Message 'Administrator-SSPR er allerede deaktiveret.'
        return [pscustomobject]@{
            Setting = 'allowedToUseSSPR'
            PreviousValue = $false
            DesiredValue = $false
            Status = 'AlreadyDisabled'
            Detail = 'Administrator-SSPR was already disabled.'
        }
    }

    if (-not $Apply -or $sync.App.Mock) {
        Write-NetIPLog -Level PASS -Message 'Administrator-SSPR planlagt deaktiveret.'
        return [pscustomobject]@{
            Setting = 'allowedToUseSSPR'
            PreviousValue = $true
            DesiredValue = $false
            Status = if ($Apply) { 'Disabled' } else { 'PlannedDisable' }
            Detail = 'Administrator-SSPR is tenant-wide for administrator roles.'
        }
    }

    Write-NetIPLog -Message 'Deaktiverer administrator-SSPR tenant-wide...'
    Invoke-NetIPGraphRequest -Method PATCH -Uri 'https://graph.microsoft.com/v1.0/policies/authorizationPolicy' -Body @{ allowedToUseSSPR = $false } | Out-Null
    Write-NetIPLog -Level PASS -Message 'Administrator-SSPR er deaktiveret tenant-wide.'
    return [pscustomobject]@{
        Setting = 'allowedToUseSSPR'
        PreviousValue = $true
        DesiredValue = $false
        Status = 'Disabled'
        Detail = 'Policy changes can take up to 60 minutes to take effect.'
    }
}

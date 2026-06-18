function Ensure-NetIPBreakGlassCAPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $DisplayName,
        [Parameter(Mandatory)][string] $GroupId,
        [Parameter(Mandatory)][string] $AuthenticationStrengthId,
        [Parameter(Mandatory)][bool] $Enabled,
        [Parameter(Mandatory)][bool] $Apply
    )

    if ([string]::IsNullOrWhiteSpace($GroupId)) { throw 'CA-BreakGlass-Exclude gruppen skal have et Object ID før CA-politikken kan oprettes.' }
    if ([string]::IsNullOrWhiteSpace($AuthenticationStrengthId)) { throw 'Authentication strength skal have et Object ID før CA-politikken kan oprettes.' }

    $state = if ($Enabled) { 'enabled' } else { 'enabledForReportingButNotEnforced' }
    if (-not $Apply -or $sync.App.Mock) {
        return [pscustomobject]@{ id='planned-ca-policy'; displayName=$DisplayName; state=$state; Status=if($Apply){'Created'}else{'PlannedCreate'} }
    }

    $existing = @(Get-NetIPConditionalAccessPolicies | Where-Object { [string](Get-NetIPObjectPropertyValue -InputObject $_ -Name 'displayName') -eq $DisplayName }) | Select-Object -First 1
    if ($existing) {
        $existing | Add-Member -MemberType NoteProperty -Name Status -Value 'AlreadyExists' -Force
        return $existing
    }

    Write-NetIPLog -Message "Opretter dedikeret BreakGlass FIDO2 CA-policy: $DisplayName"
    $body = @{
        displayName = $DisplayName
        state = $state
        conditions = @{
            users = @{
                includeGroups = @($GroupId)
                excludeUsers = @()
                excludeGroups = @()
            }
            applications = @{
                includeApplications = @('All')
                excludeApplications = @()
            }
            clientAppTypes = @('all')
        }
        grantControls = @{
            operator = 'OR'
            authenticationStrength = @{
                id = $AuthenticationStrengthId
            }
        }
    }
    $created = Invoke-NetIPGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies' -Body $body
    $created | Add-Member -MemberType NoteProperty -Name Status -Value 'Created' -Force
    return $created
}

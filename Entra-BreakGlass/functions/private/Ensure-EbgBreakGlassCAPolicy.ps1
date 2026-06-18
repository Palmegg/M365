function Ensure-EbgBreakGlassCAPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $DisplayName,
        [string] $GroupId = '',
        [string[]] $UserIds = @(),
        [Parameter(Mandatory)][string] $AuthenticationStrengthId,
        [bool] $Enabled = $false,
        [Parameter(Mandatory)][bool] $Apply
    )

    $targetUsers = @($UserIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($targetUsers.Count -lt 1 -and [string]::IsNullOrWhiteSpace($GroupId)) { throw 'Der skal angives mindst én break-glass konto eller gruppe før CA-politikken kan oprettes.' }
    if ([string]::IsNullOrWhiteSpace($AuthenticationStrengthId)) { throw 'Authentication strength skal have et Object ID før CA-politikken kan oprettes.' }

    $state = if ($Enabled) { 'enabled' } else { 'disabled' }
    if (-not $Apply -or $sync.App.Mock) {
        return [pscustomobject]@{ id='planned-ca-policy'; displayName=$DisplayName; state=$state; Status=if($Apply){'Created'}else{'PlannedCreate'} }
    }

    $existing = @(Get-EbgConditionalAccessPolicies | Where-Object { [string](Get-EbgObjectPropertyValue -InputObject $_ -Name 'displayName') -eq $DisplayName }) | Select-Object -First 1
    if ($existing) {
        $existing | Add-Member -MemberType NoteProperty -Name Status -Value 'AlreadyExists' -Force
        return $existing
    }

    Write-EbgLog -Message "Opretter dedikeret BreakGlass FIDO2 CA-policy: $DisplayName"
    $body = @{
        displayName = $DisplayName
        state = $state
        conditions = @{
            users = @{
                includeUsers = if ($targetUsers.Count -gt 0) { $targetUsers } else { @() }
                includeGroups = if ($targetUsers.Count -lt 1 -and -not [string]::IsNullOrWhiteSpace($GroupId)) { @($GroupId) } else { @() }
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
    $created = Invoke-EbgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies' -Body $body
    $created | Add-Member -MemberType NoteProperty -Name Status -Value 'Created' -Force
    return $created
}
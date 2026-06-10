function Ensure-NetIPGroupMember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Group,
        [Parameter(Mandatory)] $User,
        [Parameter(Mandatory)][bool] $Apply
    )

    $groupId = [string](Get-NetIPObjectPropertyValue -InputObject $Group -Name 'id')
    $userId = [string](Get-NetIPObjectPropertyValue -InputObject $User -Name 'id')
    $upn = [string](Get-NetIPObjectPropertyValue -InputObject $User -Name 'userPrincipalName')
    $groupName = [string](Get-NetIPObjectPropertyValue -InputObject $Group -Name 'displayName')
    if ([string]::IsNullOrWhiteSpace($groupId) -or [string]::IsNullOrWhiteSpace($userId)) {
        return [pscustomobject]@{ UserPrincipalName = $upn; Group = $groupName; Status = 'Skipped'; Detail = 'Group or user missing.' }
    }
    if ($sync.App.Mock -or $groupId -like 'planned-*' -or $userId -like 'mock-*') {
        return [pscustomobject]@{ UserPrincipalName = $upn; Group = $groupName; Status = if ($Apply) { 'Added' } else { 'Planned' } }
    }
    $members = Get-NetIPGraphCollection -Uri "https://graph.microsoft.com/v1.0/groups/$groupId/members?`$select=id"
    if (@($members | Where-Object { [string](Get-NetIPObjectPropertyValue -InputObject $_ -Name 'id') -eq $userId }).Count -gt 0) {
        return [pscustomobject]@{ UserPrincipalName = $upn; Group = $groupName; Status = 'AlreadyMember' }
    }
    if (-not $Apply) {
        return [pscustomobject]@{ UserPrincipalName = $upn; Group = $groupName; Status = 'Planned' }
    }
    Invoke-NetIPGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/groups/$groupId/members/`$ref" -Body @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$userId" } | Out-Null
    return [pscustomobject]@{ UserPrincipalName = $upn; Group = $groupName; Status = 'Added' }
}

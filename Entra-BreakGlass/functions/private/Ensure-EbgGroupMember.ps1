function Ensure-EbgGroupMember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Group,
        [Parameter(Mandatory)] $User,
        [Parameter(Mandatory)][bool] $Apply
    )

    $groupId = [string](Get-EbgObjectPropertyValue -InputObject $Group -Name 'id')
    $userId = [string](Get-EbgObjectPropertyValue -InputObject $User -Name 'id')
    $upn = [string](Get-EbgObjectPropertyValue -InputObject $User -Name 'userPrincipalName')
    $groupName = [string](Get-EbgObjectPropertyValue -InputObject $Group -Name 'displayName')
    if ([string]::IsNullOrWhiteSpace($groupId) -or [string]::IsNullOrWhiteSpace($userId)) {
        return [pscustomobject]@{ UserPrincipalName = $upn; Group = $groupName; Status = 'Skipped'; Detail = 'Group or user missing.' }
    }
    if ($sync.App.Mock -or $groupId -like 'planned-*' -or $userId -like 'mock-*') {
        Write-EbgLog -Level PASS -Message "Gruppemedlemskab håndteret: $upn -> $groupName"
        return [pscustomobject]@{ UserPrincipalName = $upn; Group = $groupName; Status = if ($Apply) { 'Added' } else { 'Planned' } }
    }
    if (-not $Apply) {
        return [pscustomobject]@{ UserPrincipalName = $upn; Group = $groupName; Status = 'Planned' }
    }
    Write-EbgLog -Message "Tilføjer $upn til gruppen $groupName..."
    try {
        Invoke-EbgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/groups/$groupId/members/`$ref" -Body @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$userId" } | Out-Null
        Write-EbgLog -Level PASS -Message "Gruppemedlemskab tilføjet: $upn -> $groupName"
        return [pscustomobject]@{ UserPrincipalName = $upn; Group = $groupName; Status = 'Added' }
    }
    catch {
        $message = [string]$_
        if ($message -match 'already exist|already exists|added object references already exist|object references already exist') {
            Write-EbgLog -Level PASS -Message "Gruppemedlemskab findes allerede: $upn -> $groupName"
            return [pscustomobject]@{ UserPrincipalName = $upn; Group = $groupName; Status = 'AlreadyMember' }
        }
        throw
    }
}
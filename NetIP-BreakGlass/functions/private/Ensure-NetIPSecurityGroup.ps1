function Ensure-NetIPSecurityGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $DisplayName,
        [Parameter(Mandatory)][string] $Description,
        [Parameter(Mandatory)][bool] $CreateIfMissing,
        [Parameter(Mandatory)][bool] $Apply
    )

    $group = Get-NetIPGroupByDisplayName -DisplayName $DisplayName
    if ($group) {
        $group | Add-Member -MemberType NoteProperty -Name EnsureStatus -Value 'AlreadyExists' -Force
        $currentDescription = [string](Get-NetIPObjectPropertyValue -InputObject $group -Name 'description')
        if ($currentDescription -ne $Description) {
            if ($Apply) {
                Invoke-NetIPGraphRequest -Method PATCH -Uri "https://graph.microsoft.com/v1.0/groups/$($group.id)" -Body @{ description = $Description } | Out-Null
                $group.description = $Description
                $group.EnsureStatus = 'UpdatedDescription'
            }
            else {
                $group.EnsureStatus = 'PlannedDescriptionUpdate'
            }
        }
        return $group
    }
    if (-not $CreateIfMissing) {
        return [pscustomobject]@{ id = ''; displayName = $DisplayName; EnsureStatus = 'SkippedMissing' }
    }
    if (-not $Apply) {
        return [pscustomobject]@{ id = 'planned-group'; displayName = $DisplayName; description = $Description; EnsureStatus = 'PlannedCreate' }
    }
    $created = New-NetIPSecurityGroup -DisplayName $DisplayName -Description $Description
    $created | Add-Member -MemberType NoteProperty -Name EnsureStatus -Value 'Created' -Force
    return $created
}

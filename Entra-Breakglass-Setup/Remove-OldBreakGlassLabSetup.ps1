#requires -Version 7.0
<#
.SYNOPSIS
    Removes explicitly named old/lab break-glass objects from Microsoft Entra ID.

.DESCRIPTION
    This is a guarded cleanup helper for lab/demo tenants after testing older
    versions of the NetIP Entra Break Glass Configurator.

    It does not discover and delete objects by pattern. You must provide exact
    UPNs and display names. Dry-run is the default. To actually delete, use
    -Apply and type the confirmation phrase.

    Deletion order:
      1. Remove Entra directory role assignments from target users/groups.
      2. Remove scoped RMAU role assignments.
      3. Remove target users/groups from target administrative units.
      4. Delete target administrative units.
      5. Delete target groups.
      6. Delete target users.

    The script does not remove Conditional Access policies, authentication
    strengths, Log Analytics workspaces, Azure Monitor alerts, or Azure resource
    groups. Handle those separately after reviewing the generated reports.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]] $UserPrincipalNames = @(),
    [string[]] $GroupDisplayNames = @(),
    [string[]] $AdministrativeUnitDisplayNames = @(),
    [switch] $Apply,
    [string] $ConfirmationPhrase = 'DELETE OLD BREAKGLASS LAB SETUP'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param(
        [string] $Message,
        [ValidateSet('INFO','PLAN','DELETE','SKIP','WARN','ERROR','PASS')]
        [string] $Level = 'INFO'
    )

    $color = switch ($Level) {
        'DELETE' { 'Red' }
        'WARN' { 'Yellow' }
        'ERROR' { 'Red' }
        'PASS' { 'Green' }
        'PLAN' { 'Cyan' }
        default { 'White' }
    }
    Write-Host ("[{0}] {1}" -f $Level, $Message) -ForegroundColor $color
}

function Invoke-GraphDelete {
    param(
        [Parameter(Mandatory)][string] $Uri,
        [Parameter(Mandatory)][string] $Description
    )

    if (-not $Apply) {
        Write-Step -Level PLAN -Message $Description
        return
    }

    Write-Step -Level DELETE -Message $Description
    try {
        Invoke-MgGraphRequest -Method DELETE -Uri $Uri -ErrorAction Stop | Out-Null
    }
    catch {
        $message = $_.Exception.Message
        if ($message -match '404|Request_ResourceNotFound|Resource .* does not exist') {
            Write-Step -Level SKIP -Message "Already gone: $Description"
            return
        }
        throw
    }
}

function Get-GraphCollection {
    param([Parameter(Mandatory)][string] $Uri)

    $items = @()
    $next = $Uri
    while ($next) {
        $response = Invoke-MgGraphRequest -Method GET -Uri $next -ErrorAction Stop
        if ($response.value) {
            $items += @($response.value)
        }
        $next = $response.'@odata.nextLink'
    }
    return $items
}

function Get-ObjectPropertyValue {
    param(
        [AllowNull()] $InputObject,
        [Parameter(Mandatory)][string] $Name
    )

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary] -and $InputObject.Contains($Name)) {
        return $InputObject[$Name]
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Get-UserByUpn {
    param([Parameter(Mandatory)][string] $UserPrincipalName)

    try {
        return Invoke-MgGraphRequest -Method GET -Uri ("https://graph.microsoft.com/v1.0/users/{0}?`$select=id,displayName,userPrincipalName,accountEnabled" -f [uri]::EscapeDataString($UserPrincipalName)) -ErrorAction Stop
    }
    catch {
        Write-Step -Level SKIP -Message "User not found: $UserPrincipalName"
        return $null
    }
}

function Get-GroupByDisplayName {
    param([Parameter(Mandatory)][string] $DisplayName)

    $filter = [uri]::EscapeDataString("displayName eq '$($DisplayName.Replace("'", "''"))'")
    $groups = @(Get-GraphCollection -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=$filter&`$select=id,displayName,mailNickname,isAssignableToRole,securityEnabled")
    if ($groups.Count -eq 0) {
        Write-Step -Level SKIP -Message "Group not found: $DisplayName"
        return $null
    }
    if ($groups.Count -gt 1) {
        throw "More than one group matched '$DisplayName'. Use the portal/Graph to clean this up manually."
    }
    return $groups[0]
}

function Get-AdministrativeUnitByDisplayName {
    param([Parameter(Mandatory)][string] $DisplayName)

    $filter = [uri]::EscapeDataString("displayName eq '$($DisplayName.Replace("'", "''"))'")
    $units = @(Get-GraphCollection -Uri "https://graph.microsoft.com/beta/directory/administrativeUnits?`$filter=$filter&`$select=id,displayName,isMemberManagementRestricted")
    if ($units.Count -eq 0) {
        Write-Step -Level SKIP -Message "Administrative unit not found: $DisplayName"
        return $null
    }
    if ($units.Count -gt 1) {
        throw "More than one administrative unit matched '$DisplayName'. Use the portal/Graph to clean this up manually."
    }
    return $units[0]
}

function Remove-DirectoryRoleAssignmentsForPrincipal {
    param(
        [Parameter(Mandatory)][string] $PrincipalId,
        [Parameter(Mandatory)][string] $PrincipalLabel
    )

    $filter = [uri]::EscapeDataString("principalId eq '$PrincipalId'")
    $assignments = @(Get-GraphCollection -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$filter=$filter")
    if ($assignments.Count -eq 0) {
        Write-Step -Level SKIP -Message "No directory role assignments found for $PrincipalLabel"
        return
    }
    foreach ($assignment in $assignments) {
        $assignmentId = Get-ObjectPropertyValue -InputObject $assignment -Name 'id'
        Invoke-GraphDelete -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments/$assignmentId" -Description "Remove directory role assignment $assignmentId from $PrincipalLabel"
    }
}

function Remove-AdministrativeUnitScopedRoleMembers {
    param(
        [Parameter(Mandatory)] $AdministrativeUnit
    )

    $auId = Get-ObjectPropertyValue -InputObject $AdministrativeUnit -Name 'id'
    $auName = Get-ObjectPropertyValue -InputObject $AdministrativeUnit -Name 'displayName'
    $scopedRoleMembers = @(Get-GraphCollection -Uri "https://graph.microsoft.com/v1.0/directory/administrativeUnits/$auId/scopedRoleMembers")
    if ($scopedRoleMembers.Count -eq 0) {
        Write-Step -Level SKIP -Message "No scoped RMAU role members found for $auName"
        return
    }
    foreach ($member in $scopedRoleMembers) {
        $membershipId = Get-ObjectPropertyValue -InputObject $member -Name 'id'
        Invoke-GraphDelete -Uri "https://graph.microsoft.com/v1.0/directory/administrativeUnits/$auId/scopedRoleMembers/$membershipId" -Description "Remove scoped RMAU role membership $membershipId from $auName"
    }
}

function Remove-AdministrativeUnitMemberIfPresent {
    param(
        [Parameter(Mandatory)] $AdministrativeUnit,
        [Parameter(Mandatory)][string] $ObjectId,
        [Parameter(Mandatory)][string] $ObjectLabel
    )

    $auId = Get-ObjectPropertyValue -InputObject $AdministrativeUnit -Name 'id'
    $auName = Get-ObjectPropertyValue -InputObject $AdministrativeUnit -Name 'displayName'
    Invoke-GraphDelete -Uri "https://graph.microsoft.com/v1.0/directory/administrativeUnits/$auId/members/$ObjectId/`$ref" -Description "Remove $ObjectLabel from administrative unit $auName"
}

if (-not $UserPrincipalNames -and -not $GroupDisplayNames -and -not $AdministrativeUnitDisplayNames) {
    throw 'Provide at least one exact UserPrincipalNames, GroupDisplayNames, or AdministrativeUnitDisplayNames value.'
}

Write-Step -Message 'Connecting to Microsoft Graph...'
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
$scopes = @(
    'User.ReadWrite.All',
    'Group.ReadWrite.All',
    'Directory.ReadWrite.All',
    'RoleManagement.ReadWrite.Directory'
)
Connect-MgGraph -Scopes $scopes -NoWelcome -ErrorAction Stop | Out-Null

$context = Get-MgContext
Write-Step -Level PASS -Message "Connected as $($context.Account) to tenant $($context.TenantId)"

if ($Apply) {
    Write-Host ''
    Write-Step -Level WARN -Message 'APPLY mode is enabled. This will delete the explicitly named old/lab objects.'
    Write-Step -Level WARN -Message "Type this exact phrase to continue: $ConfirmationPhrase"
    $typed = Read-Host 'Confirmation'
    if ($typed -ne $ConfirmationPhrase) {
        throw 'Confirmation phrase did not match. Cleanup cancelled.'
    }
}
else {
    Write-Step -Level PLAN -Message 'Dry-run mode. Nothing will be deleted. Add -Apply to execute.'
}

$targetUsers = @()
foreach ($upn in $UserPrincipalNames) {
    if ([string]::IsNullOrWhiteSpace($upn)) { continue }
    $user = Get-UserByUpn -UserPrincipalName $upn.Trim()
    if ($user) { $targetUsers += $user }
}

$targetGroups = @()
foreach ($name in $GroupDisplayNames) {
    if ([string]::IsNullOrWhiteSpace($name)) { continue }
    $group = Get-GroupByDisplayName -DisplayName $name.Trim()
    if ($group) { $targetGroups += $group }
}

$targetAdministrativeUnits = @()
foreach ($name in $AdministrativeUnitDisplayNames) {
    if ([string]::IsNullOrWhiteSpace($name)) { continue }
    $unit = Get-AdministrativeUnitByDisplayName -DisplayName $name.Trim()
    if ($unit) { $targetAdministrativeUnits += $unit }
}

Write-Host ''
Write-Step -Message 'Cleanup plan:'
foreach ($user in $targetUsers) {
    Write-Step -Level PLAN -Message ("User: {0} / {1}" -f (Get-ObjectPropertyValue -InputObject $user -Name 'userPrincipalName'), (Get-ObjectPropertyValue -InputObject $user -Name 'id'))
}
foreach ($group in $targetGroups) {
    Write-Step -Level PLAN -Message ("Group: {0} / {1} / isAssignableToRole={2}" -f (Get-ObjectPropertyValue -InputObject $group -Name 'displayName'), (Get-ObjectPropertyValue -InputObject $group -Name 'id'), (Get-ObjectPropertyValue -InputObject $group -Name 'isAssignableToRole'))
}
foreach ($unit in $targetAdministrativeUnits) {
    Write-Step -Level PLAN -Message ("Administrative unit: {0} / {1}" -f (Get-ObjectPropertyValue -InputObject $unit -Name 'displayName'), (Get-ObjectPropertyValue -InputObject $unit -Name 'id'))
}
Write-Host ''

foreach ($user in $targetUsers) {
    Remove-DirectoryRoleAssignmentsForPrincipal -PrincipalId (Get-ObjectPropertyValue -InputObject $user -Name 'id') -PrincipalLabel (Get-ObjectPropertyValue -InputObject $user -Name 'userPrincipalName')
}
foreach ($group in $targetGroups) {
    Remove-DirectoryRoleAssignmentsForPrincipal -PrincipalId (Get-ObjectPropertyValue -InputObject $group -Name 'id') -PrincipalLabel (Get-ObjectPropertyValue -InputObject $group -Name 'displayName')
}

foreach ($unit in $targetAdministrativeUnits) {
    Remove-AdministrativeUnitScopedRoleMembers -AdministrativeUnit $unit
}

foreach ($unit in $targetAdministrativeUnits) {
    foreach ($user in $targetUsers) {
        Remove-AdministrativeUnitMemberIfPresent -AdministrativeUnit $unit -ObjectId (Get-ObjectPropertyValue -InputObject $user -Name 'id') -ObjectLabel (Get-ObjectPropertyValue -InputObject $user -Name 'userPrincipalName')
    }
    foreach ($group in $targetGroups) {
        Remove-AdministrativeUnitMemberIfPresent -AdministrativeUnit $unit -ObjectId (Get-ObjectPropertyValue -InputObject $group -Name 'id') -ObjectLabel (Get-ObjectPropertyValue -InputObject $group -Name 'displayName')
    }
}

foreach ($unit in $targetAdministrativeUnits) {
    $auId = Get-ObjectPropertyValue -InputObject $unit -Name 'id'
    $auName = Get-ObjectPropertyValue -InputObject $unit -Name 'displayName'
    Invoke-GraphDelete -Uri "https://graph.microsoft.com/v1.0/directory/administrativeUnits/$auId" -Description "Delete administrative unit $auName"
}

foreach ($group in $targetGroups) {
    $groupId = Get-ObjectPropertyValue -InputObject $group -Name 'id'
    $groupName = Get-ObjectPropertyValue -InputObject $group -Name 'displayName'
    Invoke-GraphDelete -Uri "https://graph.microsoft.com/v1.0/groups/$groupId" -Description "Delete group $groupName"
}

foreach ($user in $targetUsers) {
    $userId = Get-ObjectPropertyValue -InputObject $user -Name 'id'
    $upn = Get-ObjectPropertyValue -InputObject $user -Name 'userPrincipalName'
    Invoke-GraphDelete -Uri "https://graph.microsoft.com/v1.0/users/$userId" -Description "Delete user $upn"
}

Write-Host ''
if ($Apply) {
    Write-Step -Level PASS -Message 'Cleanup finished. Review Entra portal and any remaining CA/auth strength/Azure Monitor resources manually.'
}
else {
    Write-Step -Level PASS -Message 'Dry-run finished. Re-run with -Apply when the plan is correct.'
}

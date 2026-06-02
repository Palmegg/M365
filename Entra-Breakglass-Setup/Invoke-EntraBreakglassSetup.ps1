#requires -Version 5.1
<#
.SYNOPSIS
    WPF tool for configuring and documenting Microsoft Entra ID breakglass accounts.

.DESCRIPTION
    This script uses Microsoft Graph PowerShell only. It never deletes users, groups,
    or Conditional Access policies. Every change is gated by a confirmation prompt,
    supports dry-run mode, and is written to a local log file.
#>

[CmdletBinding()]
param(
    [switch] $WorkerMode,
    [string] $ConfigPath
)

if (-not $WorkerMode -and [System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
    $windowsPowerShell = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if ((Test-Path -Path $windowsPowerShell) -and -not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
        Write-Host 'Restarting Microsoft Entra Breakglass Setup in STA Windows PowerShell for WPF compatibility...' -ForegroundColor Cyan
        & $windowsPowerShell -NoProfile -STA -ExecutionPolicy Bypass -File $PSCommandPath
        exit $LASTEXITCODE
    }
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AppName = 'Microsoft Entra Breakglass Setup'
$script:LogDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'logs'
$script:ReportDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'reports'
$script:LogFile = Join-Path -Path $script:LogDirectory -ChildPath ("BreakglassSetup_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$script:RunResults = New-Object System.Collections.Generic.List[string]
$script:CreatedUserSecrets = New-Object System.Collections.Generic.List[object]
$script:DryRun = $true
$script:MainWindow = $null
$script:LogTextBox = $null
$script:WorkerProcess = $null
$script:WorkerConfigPath = $null
$script:WorkerTimer = $null
$script:ActiveRunButton = $null
$script:LastLogTextLength = 0

New-Item -ItemType Directory -Force -Path $script:LogDirectory, $script:ReportDirectory | Out-Null

function Invoke-UiThread {
    [CmdletBinding()]
    param([Parameter(Mandatory)][scriptblock] $ScriptBlock)

    if (-not $script:MainWindow -or -not $script:MainWindow.Dispatcher -or $script:MainWindow.Dispatcher.CheckAccess()) {
        return (& $ScriptBlock)
    }

    return $script:MainWindow.Dispatcher.Invoke([Func[object]] { & $ScriptBlock })
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'DRYRUN')]
        [string] $Level = 'INFO'
    )

    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $script:LogFile -Value $line -Encoding UTF8

    if ($script:LogTextBox) {
        Invoke-UiThread -ScriptBlock {
            $script:LogTextBox.AppendText($line + [Environment]::NewLine)
            $script:LogTextBox.ScrollToEnd()
            try {
                $script:LastLogTextLength = (Get-Content -Path $script:LogFile -Raw -Encoding UTF8 -ErrorAction Stop).Length
            }
            catch {
                $script:LastLogTextLength = 0
            }
            return $null
        } | Out-Null
    }
}

function Sync-LogViewFromFile {
    [CmdletBinding()]
    param()

    if (-not $script:LogTextBox -or -not (Test-Path -Path $script:LogFile)) {
        return
    }

    try {
        $content = Get-Content -Path $script:LogFile -Raw -Encoding UTF8 -ErrorAction Stop
        if ($content.Length -lt $script:LastLogTextLength) {
            $script:LastLogTextLength = 0
        }

        if ($content.Length -gt $script:LastLogTextLength) {
            $newText = $content.Substring($script:LastLogTextLength)
            $script:LogTextBox.AppendText($newText)
            $script:LogTextBox.ScrollToEnd()
            $script:LastLogTextLength = $content.Length
        }
    }
    catch {
        # The worker process may be writing the log at this exact moment. The next tick will retry.
    }
}

function Add-RunResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Message)

    $script:RunResults.Add($Message) | Out-Null
    Write-Log -Message $Message
}

function Show-Warning {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Message)

    Write-Log -Message $Message -Level WARN
    Invoke-UiThread -ScriptBlock {
        [System.Windows.MessageBox]::Show($Message, $script:AppName, 'OK', 'Warning') | Out-Null
        return $null
    } | Out-Null
}

function Confirm-DependencyInstall {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Message)

    $answer = Invoke-UiThread -ScriptBlock {
        [System.Windows.MessageBox]::Show(
            $Message,
            "$($script:AppName) - dependency setup",
            'YesNo',
            'Question'
        )
    }

    return ($answer -eq 'Yes')
}

function Confirm-Change {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Message)

    if ($script:DryRun) {
        Write-Log -Message "Dry-run: would ask for confirmation: $Message" -Level DRYRUN
        return $false
    }

    $answer = Invoke-UiThread -ScriptBlock {
        [System.Windows.MessageBox]::Show(
            $Message,
            "$($script:AppName) - confirm change",
            'YesNo',
            'Question'
        )
    }

    return ($answer -eq 'Yes')
}

function Initialize-PowerShellGalleryAccess {
    [CmdletBinding()]
    param()

    # Older Windows PowerShell builds may default to TLS versions that PowerShell Gallery rejects.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        if (-not (Confirm-DependencyInstall -Message 'The NuGet package provider is required to install Microsoft Graph PowerShell modules. Install NuGet for the current user now?')) {
            throw 'NuGet package provider is missing and installation was cancelled.'
        }

        Write-Log -Message 'Installing NuGet package provider for CurrentUser.'
        Install-PackageProvider -Name NuGet -MinimumVersion '2.8.5.201' -Scope CurrentUser -Force -ErrorAction Stop | Out-Null
    }

    if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
        if (-not (Confirm-DependencyInstall -Message 'PowerShell Gallery is not registered on this PC. Register the default PSGallery repository now?')) {
            throw 'PowerShell Gallery is not registered and registration was cancelled.'
        }

        Write-Log -Message 'Registering default PowerShell Gallery repository.'
        Register-PSRepository -Default -ErrorAction Stop
    }
}

function Install-RequiredGraphModule {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $ModuleName)

    Initialize-PowerShellGalleryAccess

    Write-Log -Message "Installing '$ModuleName' from PowerShell Gallery for CurrentUser."
    Install-Module `
        -Name $ModuleName `
        -Repository PSGallery `
        -Scope CurrentUser `
        -AllowClobber `
        -Force `
        -ErrorAction Stop

    Add-RunResult "Installed PowerShell module: $ModuleName"
}

function Invoke-RequiredModuleCheck {
    [CmdletBinding()]
    param()

    $requiredModules = @(
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.Users',
        'Microsoft.Graph.Groups',
        'Microsoft.Graph.Identity.DirectoryManagement'
    )

    $missingModules = @(foreach ($moduleName in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $moduleName)) {
            $moduleName
        }
    })

    if ($missingModules.Count -gt 0) {
        $moduleList = ($missingModules -join [Environment]::NewLine)
        if (-not (Confirm-DependencyInstall -Message "The following Microsoft Graph PowerShell modules are missing and must be installed for the current user:$([Environment]::NewLine)$([Environment]::NewLine)$moduleList$([Environment]::NewLine)$([Environment]::NewLine)Install them now?")) {
            throw "Missing required Microsoft Graph PowerShell modules: $($missingModules -join ', ')"
        }

        foreach ($moduleName in $missingModules) {
            Install-RequiredGraphModule -ModuleName $moduleName
        }
    }

    foreach ($moduleName in $requiredModules) {
        Write-Log -Message "Importing PowerShell module: $moduleName"
        Import-Module $moduleName -ErrorAction Stop
    }
}

# Microsoft Graph PowerShell can expose a Connect-Graph alias on some systems.
# Use an internal, unique helper name so existing Graph modules cannot shadow it.
function Connect-BreakglassGraph {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string] $TenantName,

        [bool] $UseDeviceCode
    )

    Invoke-RequiredModuleCheck

    $scopes = @(
        'Directory.Read.All',
        'Domain.Read.All',
        'User.ReadWrite.All',
        'Group.ReadWrite.All',
        'RoleManagement.Read.Directory',
        'Policy.ReadWrite.Authorization'
    )

    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        Write-Log -Message 'Disconnected any existing Microsoft Graph PowerShell context.'
    }
    catch {
        Write-Log -Level WARN -Message "Could not disconnect an existing Graph context: $($_.Exception.Message)"
    }

    Write-Log -Message "Connecting to Microsoft Graph with delegated scopes: $($scopes -join ', ')"

    $connectParams = @{
        Scopes    = $scopes
        NoWelcome = $true
    }

    if ((Get-Command Connect-MgGraph -ErrorAction Stop).Parameters.ContainsKey('ContextScope')) {
        $connectParams.ContextScope = 'Process'
    }

    if ($UseDeviceCode) {
        if (-not (Get-Command Connect-MgGraph -ErrorAction Stop).Parameters.ContainsKey('UseDeviceCode')) {
            throw 'This installed Microsoft.Graph.Authentication module does not support Connect-MgGraph -UseDeviceCode. Update Microsoft.Graph and try again.'
        }

        $connectParams.UseDeviceCode = $true
        Write-Log -Message 'Using device code sign-in fallback. Follow the code instructions in the PowerShell terminal.'
        Write-Host ''
        Write-Host 'Microsoft Graph device code sign-in fallback is starting.' -ForegroundColor Cyan
        Write-Host 'If a code is shown below, open https://microsoft.com/devicelogin and complete sign-in.' -ForegroundColor Cyan
        Write-Host ''
    }
    else {
        Write-Log -Message 'Using native Microsoft Graph interactive browser sign-in. A Microsoft sign-in window or browser tab should open; complete sign-in with your FIDO key/passkey.'
        Write-Host ''
        Write-Host 'Microsoft Graph interactive browser sign-in is starting.' -ForegroundColor Cyan
        Write-Host 'Complete sign-in in the Microsoft login window/browser and use your FIDO key/passkey when prompted.' -ForegroundColor Cyan
        Write-Host ''
    }

    if (-not [string]::IsNullOrWhiteSpace($TenantName)) {
        $connectParams.TenantId = $TenantName.Trim()
    }
    else {
        Write-Log -Message 'Tenant field is empty. Microsoft Graph sign-in will determine the tenant, and the .onmicrosoft.com domain will be resolved after sign-in.'
    }

    Connect-MgGraph @connectParams | Out-Null
    $context = Get-MgContext

    if (-not $context) {
        throw 'Microsoft Graph connection failed. No Graph context was returned.'
    }

    Add-RunResult ("Connected to tenant '{0}' as '{1}'." -f $context.TenantId, $context.Account)
    return $context
}

function Resolve-OnMicrosoftDomain {
    [CmdletBinding()]
    param([string] $TenantName)

    if ($TenantName -match '^[^@\s]+\.onmicrosoft\.com$') {
        return $TenantName.Trim().ToLowerInvariant()
    }

    Write-Log -Message 'Resolving initial .onmicrosoft.com domain from tenant domains.'
    $domains = Get-MgDomain -All -ErrorAction Stop
    $initialDomain = $domains |
        Where-Object {
            $domainId = Get-GraphObjectPropertyValue -InputObject $_ -PropertyName @('Id', 'id')
            $isInitial = Get-GraphObjectPropertyValue -InputObject $_ -PropertyName @('IsInitial', 'isInitial')
            $domainId -like '*.onmicrosoft.com' -and $isInitial -eq $true
        } |
        Select-Object -First 1

    if (-not $initialDomain) {
        $initialDomain = $domains |
            Where-Object {
                $domainId = Get-GraphObjectPropertyValue -InputObject $_ -PropertyName @('Id', 'id')
                $domainId -like '*.onmicrosoft.com'
            } |
            Sort-Object { Get-GraphObjectPropertyValue -InputObject $_ -PropertyName @('Id', 'id') } |
            Select-Object -First 1
    }

    if (-not $initialDomain) {
        throw 'Could not find a tenant .onmicrosoft.com domain. Enter the tenant initial domain and try again.'
    }

    $initialDomainId = Get-GraphObjectPropertyValue -InputObject $initialDomain -PropertyName @('Id', 'id')
    Add-RunResult "Resolved tenant .onmicrosoft.com domain: $initialDomainId"
    return $initialDomainId.ToLowerInvariant()
}

function ConvertTo-OnMicrosoftUpn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $InputUpn,
        [Parameter(Mandatory)][string] $OnMicrosoftDomain
    )

    $trimmedInput = $InputUpn.Trim()

    if ($trimmedInput -notmatch '^[^@\s]+(@[^@\s]+)?$') {
        throw "UPN or account prefix '$InputUpn' is not valid."
    }

    $localPart = ($trimmedInput -split '@', 2)[0]
    $targetUpn = ('{0}@{1}' -f $localPart, $OnMicrosoftDomain).ToLowerInvariant()

    if ($trimmedInput.ToLowerInvariant() -ne $targetUpn) {
        Write-Log -Level WARN -Message "Account input '$InputUpn' was adjusted to '$targetUpn' because breakglass accounts must use the .onmicrosoft.com domain."
    }

    return $targetUpn
}

function New-RandomPassword {
    [CmdletBinding()]
    param()

    $lower = 'abcdefghijkmnopqrstuvwxyz'
    $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $digits = '23456789'
    $symbols = '!@#$%&*_-+=?'
    $all = ($lower + $upper + $digits + $symbols).ToCharArray()
    $required = @(
        $lower[(Get-Random -Minimum 0 -Maximum $lower.Length)]
        $upper[(Get-Random -Minimum 0 -Maximum $upper.Length)]
        $digits[(Get-Random -Minimum 0 -Maximum $digits.Length)]
        $symbols[(Get-Random -Minimum 0 -Maximum $symbols.Length)]
    )

    $rest = 1..20 | ForEach-Object { $all[(Get-Random -Minimum 0 -Maximum $all.Length)] }
    return -join (($required + $rest) | Sort-Object { Get-Random })
}

function Get-GraphObjectPropertyValue {
    [CmdletBinding()]
    param(
        [AllowNull()] $InputObject,
        [Parameter(Mandatory)][string[]] $PropertyName
    )

    if (-not $InputObject) {
        return $null
    }

    foreach ($name in $PropertyName) {
        $property = $InputObject.PSObject.Properties[$name]
        if ($property -and $null -ne $property.Value) {
            return $property.Value
        }
    }

    $additionalProperties = $InputObject.PSObject.Properties['AdditionalProperties']
    if ($additionalProperties -and $additionalProperties.Value -is [System.Collections.IDictionary]) {
        foreach ($name in $PropertyName) {
            if ($additionalProperties.Value.Contains($name) -and $null -ne $additionalProperties.Value[$name]) {
                return $additionalProperties.Value[$name]
            }
        }
    }

    return $null
}

function Get-GraphObjectId {
    [CmdletBinding()]
    param([AllowNull()] $InputObject)

    return Get-GraphObjectPropertyValue -InputObject $InputObject -PropertyName @('Id', 'id')
}

function Get-GraphObjectDisplayName {
    [CmdletBinding()]
    param([AllowNull()] $InputObject)

    return Get-GraphObjectPropertyValue -InputObject $InputObject -PropertyName @('DisplayName', 'displayName')
}

function Get-GraphObjectUserPrincipalName {
    [CmdletBinding()]
    param([AllowNull()] $InputObject)

    return Get-GraphObjectPropertyValue -InputObject $InputObject -PropertyName @('UserPrincipalName', 'userPrincipalName')
}

function Get-GraphUserByUpn {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $UserPrincipalName)

    try {
        return Get-MgUser -UserId $UserPrincipalName -Property 'id,displayName,userPrincipalName,accountEnabled' -ErrorAction Stop
    }
    catch {
        if ($_.Exception.Message -match 'Request_ResourceNotFound|Resource .* does not exist|does not exist') {
            return $null
        }

        throw
    }
}

function Get-GraphGroupByDisplayName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $GroupName)

    $escapedName = $GroupName.Replace("'", "''")
    $groups = Get-MgGroup -Filter "displayName eq '$escapedName'" -ConsistencyLevel eventual -All -Property 'id,displayName' -ErrorAction Stop
    return $groups | Where-Object { (Get-GraphObjectDisplayName -InputObject $_) -eq $GroupName } | Select-Object -First 1
}

function Find-PotentialBreakglassAccounts {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $OnMicrosoftDomain)

    Write-Log -Message 'Looking for existing potential emergency access / breakglass accounts.'

    try {
        $users = Get-MgUser -All -Property 'id,displayName,userPrincipalName,accountEnabled' -ErrorAction Stop
        $candidatePattern = '(?i)(^|[@._-])(svr_ea|adm_ea|ea0[1-9]|ea[0-9]{2}|emergency|emergencyaccess|emergency-access|breakglass|break-glass|break_glass)'
        $candidates = @(
            $users | Where-Object {
                $candidateUpn = Get-GraphObjectUserPrincipalName -InputObject $_
                $candidateDisplayName = Get-GraphObjectDisplayName -InputObject $_
                ($candidateUpn -match $candidatePattern) -or
                ($candidateDisplayName -match $candidatePattern)
            } | Sort-Object { Get-GraphObjectUserPrincipalName -InputObject $_ }
        )

        if ($candidates.Count -eq 0) {
            Add-RunResult 'Existing account discovery: no obvious emergency access candidates found.'
            return @()
        }

        $candidateText = ($candidates | Select-Object -First 15 | ForEach-Object {
            $candidateUpn = Get-GraphObjectUserPrincipalName -InputObject $_
            $candidateAccountEnabled = Get-GraphObjectPropertyValue -InputObject $_ -PropertyName @('AccountEnabled', 'accountEnabled')
            '{0} (enabled: {1})' -f $candidateUpn, $candidateAccountEnabled
        }) -join [Environment]::NewLine

        $moreText = if ($candidates.Count -gt 15) { "$([Environment]::NewLine)...and $($candidates.Count - 15) more." } else { '' }
        $message = "Potential existing emergency access accounts found:$([Environment]::NewLine)$([Environment]::NewLine)$candidateText$moreText"

        Add-RunResult "Existing account discovery: found $($candidates.Count) potential emergency access account(s)."
        Show-Warning -Message $message
        return $candidates
    }
    catch {
        Write-Log -Level WARN -Message "Could not scan for existing emergency access accounts: $($_.Exception.Message)"
        Add-RunResult "Existing account discovery could not complete: $($_.Exception.Message)"
        return @()
    }
}

function Get-OrCreateBreakglassUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $InputUpn,
        [Parameter(Mandatory)][string] $OnMicrosoftDomain,
        [Parameter(Mandatory)][bool] $CreateIfMissing
    )

    $upn = ConvertTo-OnMicrosoftUpn -InputUpn $InputUpn -OnMicrosoftDomain $OnMicrosoftDomain
    $existingUser = Get-GraphUserByUpn -UserPrincipalName $upn

    if ($existingUser) {
        $existingUserId = Get-GraphObjectId -InputObject $existingUser
        if ([string]::IsNullOrWhiteSpace($existingUserId)) {
            Write-Log -Level WARN -Message "Breakglass account '$upn' exists, but Microsoft Graph did not return an object id. Re-querying the user."
            $existingUser = Get-GraphUserByUpn -UserPrincipalName $upn
            $existingUserId = Get-GraphObjectId -InputObject $existingUser
        }

        if ([string]::IsNullOrWhiteSpace($existingUserId)) {
            throw "Breakglass account '$upn' exists, but Microsoft Graph did not return an Id. Cannot safely continue."
        }

        Add-RunResult "Breakglass account exists: $upn"
        return $existingUser
    }

    if (-not $CreateIfMissing) {
        Add-RunResult "Breakglass account missing and creation was not selected: $upn"
        return $null
    }

    if ($script:DryRun) {
        Write-Log -Level DRYRUN -Message "Would create breakglass account: $upn"
        Add-RunResult "Dry-run: would create breakglass account: $upn"
        return [pscustomobject]@{
            Id                = "dryrun-$upn"
            UserPrincipalName = $upn
            DisplayName       = "Breakglass $upn"
        }
    }

    if (-not (Confirm-Change -Message "Create breakglass account '$upn'?")) {
        Add-RunResult "Skipped account creation after prompt: $upn"
        return $null
    }

    $password = New-RandomPassword
    $mailNickname = (($upn -split '@', 2)[0] -replace '[^a-zA-Z0-9]', '')
    if ([string]::IsNullOrWhiteSpace($mailNickname)) {
        $mailNickname = 'breakglass'
    }

    $newUserParams = @{
        AccountEnabled    = $true
        DisplayName       = "Breakglass $upn"
        MailNickname      = $mailNickname
        UserPrincipalName = $upn
        PasswordProfile   = @{
            forceChangePasswordNextSignIn = $true
            password                      = $password
        }
    }

    New-MgUser @newUserParams -ErrorAction Stop | Out-Null
    $createdUser = Get-GraphUserByUpn -UserPrincipalName $upn
    $createdUserId = Get-GraphObjectId -InputObject $createdUser
    if ([string]::IsNullOrWhiteSpace($createdUserId)) {
        throw "Created breakglass account '$upn', but Microsoft Graph did not return it with an Id on verification. Re-run the tool; it will check for the existing account before creating anything."
    }

    $script:CreatedUserSecrets.Add([pscustomobject]@{
        UserPrincipalName = $upn
        TemporaryPassword = $password
    }) | Out-Null

    Add-RunResult "Created breakglass account: $upn"
    Write-Log -Message "A temporary password was generated for '$upn'. It is shown in the GUI prompt only and is not written to the log."

    return $createdUser
}

function Get-OrCreateBreakglassGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $GroupName,
        [Parameter(Mandatory)][bool] $CreateIfMissing
    )

    $existingGroup = Get-GraphGroupByDisplayName -GroupName $GroupName

    if ($existingGroup) {
        $existingGroupId = Get-GraphObjectId -InputObject $existingGroup
        if ([string]::IsNullOrWhiteSpace($existingGroupId)) {
            Write-Log -Level WARN -Message "Security group '$GroupName' exists, but Microsoft Graph did not return an object id. Re-querying the group."
            $existingGroup = Get-GraphGroupByDisplayName -GroupName $GroupName
            $existingGroupId = Get-GraphObjectId -InputObject $existingGroup
        }

        if ([string]::IsNullOrWhiteSpace($existingGroupId)) {
            throw "Security group '$GroupName' exists, but Microsoft Graph did not return an Id. Cannot safely continue."
        }

        Add-RunResult "Security group exists: $GroupName"
        return $existingGroup
    }

    if (-not $CreateIfMissing) {
        Add-RunResult "Security group missing and creation was not selected: $GroupName"
        return $null
    }

    if ($script:DryRun) {
        Write-Log -Level DRYRUN -Message "Would create security group: $GroupName"
        Add-RunResult "Dry-run: would create security group: $GroupName"
        return [pscustomobject]@{
            Id          = "dryrun-$GroupName"
            DisplayName = $GroupName
        }
    }

    if (-not (Confirm-Change -Message "Create security group '$GroupName'?")) {
        Add-RunResult "Skipped group creation after prompt: $GroupName"
        return $null
    }

    $mailNickname = ($GroupName -replace '[^a-zA-Z0-9]', '')
    if ([string]::IsNullOrWhiteSpace($mailNickname)) {
        $mailNickname = 'CABreakGlassExclude'
    }

    New-MgGroup `
        -DisplayName $GroupName `
        -MailEnabled:$false `
        -MailNickname $mailNickname `
        -SecurityEnabled:$true `
        -ErrorAction Stop | Out-Null

    $createdGroup = Get-GraphGroupByDisplayName -GroupName $GroupName
    $createdGroupId = Get-GraphObjectId -InputObject $createdGroup
    if ([string]::IsNullOrWhiteSpace($createdGroupId)) {
        throw "Created security group '$GroupName', but Microsoft Graph did not return it with an Id on verification. Re-run the tool; it will check for the existing group before creating anything."
    }

    Add-RunResult "Created security group: $GroupName"
    return $createdGroup
}

function Add-BreakglassUsersToGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Group,
        [Parameter(Mandatory)] [object[]] $Users
    )

    $groupId = Get-GraphObjectId -InputObject $Group
    $groupDisplayName = Get-GraphObjectDisplayName -InputObject $Group
    if ([string]::IsNullOrWhiteSpace($groupDisplayName)) {
        $groupDisplayName = 'selected group'
    }

    if ([string]::IsNullOrWhiteSpace($groupId)) {
        Add-RunResult "Could not add users to '$groupDisplayName' because the group object id was not available."
        Write-Log -Level ERROR -Message "Could not add users to '$groupDisplayName' because the group object id was not available."
        return
    }

    $members = if ($script:DryRun) {
        @()
    }
    else {
        @(Get-MgGroupMember -GroupId $groupId -All -Property 'id' -ErrorAction Stop)
    }
    $memberIds = @($members | ForEach-Object { Get-GraphObjectId -InputObject $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    foreach ($user in ($Users | Where-Object { $_ })) {
        $userId = Get-GraphObjectId -InputObject $user
        $userPrincipalName = Get-GraphObjectUserPrincipalName -InputObject $user
        if ([string]::IsNullOrWhiteSpace($userPrincipalName)) {
            $userPrincipalName = 'unknown user'
        }

        if ([string]::IsNullOrWhiteSpace($userId)) {
            Add-RunResult "Could not add '$userPrincipalName' to '$groupDisplayName' because the user object id was not available."
            Write-Log -Level WARN -Message "Could not add '$userPrincipalName' to '$groupDisplayName' because the user object id was not available."
            continue
        }

        if ($script:DryRun) {
            Write-Log -Level DRYRUN -Message "Would add '$userPrincipalName' to group '$groupDisplayName'."
            Add-RunResult "Dry-run: would add '$userPrincipalName' to '$groupDisplayName'."
            continue
        }

        if ($memberIds -contains $userId) {
            Add-RunResult "User is already member of '$groupDisplayName': $userPrincipalName"
            continue
        }

        if (-not (Confirm-Change -Message "Add '$userPrincipalName' to '$groupDisplayName'?")) {
            Add-RunResult "Skipped group membership after prompt: $userPrincipalName"
            continue
        }

        $body = @{
            '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$userId"
        }

        New-MgGroupMemberByRef -GroupId $groupId -BodyParameter $body -ErrorAction Stop
        Add-RunResult "Added '$userPrincipalName' to '$groupDisplayName'."
        $memberIds += $userId
    }
}

function Test-BreakglassGroupMembership {
    [CmdletBinding()]
    param(
        [AllowNull()] $Group,
        [Parameter(Mandatory)][object[]] $Users
    )

    $results = @()
    $groupId = Get-GraphObjectId -InputObject $Group
    if (-not $Group -or [string]::IsNullOrWhiteSpace($groupId)) {
        foreach ($user in ($Users | Where-Object { $_ })) {
            $userPrincipalName = Get-GraphObjectUserPrincipalName -InputObject $user
            $results += [pscustomobject]@{
                UserPrincipalName = $userPrincipalName
                IsMember          = $false
                Status            = 'Group not available'
            }
        }

        return $results
    }

    if ($script:DryRun) {
        foreach ($user in ($Users | Where-Object { $_ })) {
            $userPrincipalName = Get-GraphObjectUserPrincipalName -InputObject $user
            $results += [pscustomobject]@{
                UserPrincipalName = $userPrincipalName
                IsMember          = $false
                Status            = 'Dry-run: membership not changed'
            }
        }

        return $results
    }

    $members = @(Get-MgGroupMember -GroupId $groupId -All -Property 'id' -ErrorAction Stop)
    $memberIds = @($members | ForEach-Object { Get-GraphObjectId -InputObject $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach ($user in ($Users | Where-Object { $_ })) {
        $userId = Get-GraphObjectId -InputObject $user
        $userPrincipalName = Get-GraphObjectUserPrincipalName -InputObject $user
        if ([string]::IsNullOrWhiteSpace($userId)) {
            $results += [pscustomobject]@{
                UserPrincipalName = $userPrincipalName
                IsMember          = $false
                Status            = 'User object id not available'
            }
            continue
        }

        $isMember = ($memberIds -contains $userId)
        $results += [pscustomobject]@{
            UserPrincipalName = $userPrincipalName
            IsMember          = $isMember
            Status            = $(if ($isMember) { 'Confirmed member' } else { 'Not confirmed as member' })
        }
    }

    return $results
}

function Test-GlobalAdministratorMembership {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]] $Users)

    $results = @()

    if ($script:DryRun) {
        foreach ($user in ($Users | Where-Object { $_ })) {
            $userPrincipalName = Get-GraphObjectUserPrincipalName -InputObject $user
            $results += [pscustomobject]@{
                UserPrincipalName = $userPrincipalName
                IsGlobalAdmin     = $false
                Status            = 'Dry-run: role membership not checked'
            }
        }

        return $results
    }

    try {
        $roleDefinitionFilter = [uri]::EscapeDataString("displayName eq 'Global Administrator'")
        $roleDefinitionResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions?`$filter=$roleDefinitionFilter" -ErrorAction Stop
        $globalAdminRole = @($roleDefinitionResponse.value) | Select-Object -First 1

        if (-not $globalAdminRole) {
            throw 'Global Administrator role definition was not returned by Microsoft Graph.'
        }

        foreach ($user in ($Users | Where-Object { $_ })) {
            $userId = Get-GraphObjectId -InputObject $user
            $userPrincipalName = Get-GraphObjectUserPrincipalName -InputObject $user
            if ([string]::IsNullOrWhiteSpace($userId)) {
                $results += [pscustomobject]@{
                    UserPrincipalName = $userPrincipalName
                    IsGlobalAdmin     = $false
                    Status            = 'User object id not available'
                }
                continue
            }

            $assignmentFilter = [uri]::EscapeDataString("principalId eq '$userId' and roleDefinitionId eq '$($globalAdminRole.id)'")
            $assignmentResponse = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$filter=$assignmentFilter" -ErrorAction Stop
            $isGlobalAdmin = (@($assignmentResponse.value).Count -gt 0)

            $results += [pscustomobject]@{
                UserPrincipalName = $userPrincipalName
                IsGlobalAdmin     = $isGlobalAdmin
                Status            = $(if ($isGlobalAdmin) { 'Confirmed Global Administrator' } else { 'Not confirmed as Global Administrator' })
            }
        }
    }
    catch {
        Write-Log -Level WARN -Message "Could not confirm Global Administrator role membership: $($_.Exception.Message)"
        foreach ($user in ($Users | Where-Object { $_ })) {
            $userPrincipalName = Get-GraphObjectUserPrincipalName -InputObject $user
            $results += [pscustomobject]@{
                UserPrincipalName = $userPrincipalName
                IsGlobalAdmin     = $false
                Status            = "Could not check: $($_.Exception.Message)"
            }
        }
    }

    return $results
}

function Get-AdminSSPRStatus {
    [CmdletBinding()]
    param()

    if ($script:DryRun) {
        return 'Dry-run: not changed'
    }

    try {
        $policy = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -ErrorAction Stop
        if ($policy.allowedToUseSSPR -eq $true) {
            return 'Enabled'
        }

        if ($policy.allowedToUseSSPR -eq $false) {
            return 'Disabled'
        }

        return 'Unknown'
    }
    catch {
        Write-Log -Level WARN -Message "Could not read Admin SSPR status: $($_.Exception.Message)"
        return "Unknown: $($_.Exception.Message)"
    }
}

function ConvertTo-HtmlEncodedText {
    [CmdletBinding()]
    param([AllowNull()][object] $Value)

    if ($null -eq $Value) {
        return ''
    }

    return [System.Net.WebUtility]::HtmlEncode([string] $Value)
}

function New-HtmlList {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]] $Items)

    $encodedItems = $Items | ForEach-Object { '<li>{0}</li>' -f (ConvertTo-HtmlEncodedText $_) }
    return "<ul>$($encodedItems -join [Environment]::NewLine)</ul>"
}

function Disable-AdminSSPR {
    [CmdletBinding()]
    param()

    $warning = @'
Admin SSPR can not be disabled only for the two breakglass accounts.
This Graph authorization policy setting applies tenant-wide to administrators in administrator roles.
'@
    Show-Warning -Message $warning

    if ($script:DryRun) {
        Write-Log -Level DRYRUN -Message 'Would disable administrator SSPR tenant-wide by setting authorizationPolicy.allowedToUseSSPR to false.'
        Add-RunResult 'Dry-run: would disable administrator SSPR tenant-wide.'
        return
    }

    if (-not (Confirm-Change -Message 'Disable administrator SSPR tenant-wide for administrator roles?')) {
        Add-RunResult 'Skipped administrator SSPR change after prompt.'
        return
    }

    $body = @{ allowedToUseSSPR = $false } | ConvertTo-Json -Depth 4
    Invoke-MgGraphRequest -Method PATCH -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -Body $body -ContentType 'application/json' -ErrorAction Stop
    Add-RunResult 'Disabled administrator SSPR tenant-wide for administrator roles.'
}

function Generate-Report {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string] $TenantName,
        [Parameter(Mandatory)][string] $OnMicrosoftDomain,
        [Parameter(Mandatory)][object[]] $Users,
        [AllowNull()] $Group,
        [Parameter(Mandatory)][string] $GroupName,
        [AllowEmptyString()][string] $OutputDirectory,
        [Parameter(Mandatory)][object[]] $GroupMembershipStatus,
        [Parameter(Mandatory)][object[]] $GlobalAdministratorStatus,
        [Parameter(Mandatory)][string] $AdminSSPRStatus
    )

    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $OutputDirectory = $script:ReportDirectory
    }

    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

    $reportPath = Join-Path -Path $OutputDirectory -ChildPath ("BreakglassReport_{0}.html" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $createdTimestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $userList = @($Users | Where-Object { $_ })
    $account1 = $userList | Select-Object -First 1
    $account2 = $userList | Select-Object -Skip 1 -First 1
    $account1Upn = if ($account1) { Get-GraphObjectUserPrincipalName -InputObject $account1 } else { 'Not available' }
    $account2Upn = if ($account2) { Get-GraphObjectUserPrincipalName -InputObject $account2 } else { 'Not available' }
    $groupObjectId = if ($Group) { Get-GraphObjectId -InputObject $Group } else { 'Not available' }
    if ([string]::IsNullOrWhiteSpace($groupObjectId)) {
        $groupObjectId = 'Not available'
    }

    $passwordRows = foreach ($user in $userList) {
        $userPrincipalName = Get-GraphObjectUserPrincipalName -InputObject $user
        $secret = $script:CreatedUserSecrets | Where-Object { $_.UserPrincipalName -eq $userPrincipalName } | Select-Object -First 1
        $passwordText = if ($secret) {
            $secret.TemporaryPassword
        }
        elseif ($script:DryRun) {
            'Dry-run: no password generated'
        }
        else {
            'Not generated in this run. Existing passwords can not be retrieved.'
        }

        '<tr><td>{0}</td><td class="secret">{1}</td></tr>' -f (ConvertTo-HtmlEncodedText $userPrincipalName), (ConvertTo-HtmlEncodedText $passwordText)
    }

    $groupRows = foreach ($status in $GroupMembershipStatus) {
        '<tr><td>{0}</td><td>{1}</td><td>{2}</td></tr>' -f `
            (ConvertTo-HtmlEncodedText $status.UserPrincipalName),
            (ConvertTo-HtmlEncodedText $status.IsMember),
            (ConvertTo-HtmlEncodedText $status.Status)
    }

    $globalAdminRows = foreach ($status in $GlobalAdministratorStatus) {
        '<tr><td>{0}</td><td>{1}</td><td>{2}</td></tr>' -f `
            (ConvertTo-HtmlEncodedText $status.UserPrincipalName),
            (ConvertTo-HtmlEncodedText $status.IsGlobalAdmin),
            (ConvertTo-HtmlEncodedText $status.Status)
    }

    $actionItems = @($script:RunResults | ForEach-Object { [string] $_ })
    if ($actionItems.Count -eq 0) {
        $actionItems = @('No actions recorded.')
    }
    $manualSteps = @(
        'Register FIDO2 key on each account.',
        'Exclude the group from all Conditional Access policies.',
        'Configure login alerting.',
        'Complete login test.',
        'Store credentials securely.'
    )

    $content = @"
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <title>CONFIDENTIAL - Microsoft Entra Breakglass Setup Report</title>
    <style>
        body { font-family: Segoe UI, Arial, sans-serif; margin: 32px; color: #111827; line-height: 1.45; }
        .banner { background: #7f1d1d; color: #fff; padding: 14px 18px; font-size: 22px; font-weight: 700; letter-spacing: 1px; }
        .warning { border: 2px solid #b45309; background: #fffbeb; padding: 14px 18px; margin: 18px 0; }
        h1 { margin-top: 22px; }
        h2 { border-bottom: 1px solid #d1d5db; padding-bottom: 6px; margin-top: 28px; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0 18px 0; }
        th, td { border: 1px solid #d1d5db; padding: 8px 10px; text-align: left; vertical-align: top; }
        th { background: #f3f4f6; }
        .secret { font-family: Consolas, monospace; font-weight: 700; color: #7f1d1d; }
        .muted { color: #4b5563; }
        @media print { body { margin: 18mm; } .banner { -webkit-print-color-adjust: exact; print-color-adjust: exact; } }
    </style>
</head>
<body>
    <div class="banner">CONFIDENTIAL</div>
    <h1>Microsoft Entra Breakglass Setup Report</h1>
    <div class="warning">
        <strong>Credential handling warning:</strong>
        Move generated initial passwords to an approved password manager or approved physical emergency procedure immediately.
        After transfer, remove this local file and any local copies according to your security process.
    </div>

    <h2>Tenant and Creation Details</h2>
    <table>
        <tr><th>Tenant name</th><td>$(ConvertTo-HtmlEncodedText $TenantName)</td></tr>
        <tr><th>Resolved .onmicrosoft.com domain</th><td>$(ConvertTo-HtmlEncodedText $OnMicrosoftDomain)</td></tr>
        <tr><th>Date and time of creation</th><td>$(ConvertTo-HtmlEncodedText $createdTimestamp)</td></tr>
        <tr><th>Dry-run</th><td>$(ConvertTo-HtmlEncodedText $script:DryRun)</td></tr>
    </table>

    <h2>Breakglass Accounts</h2>
    <table>
        <tr><th>Breakglass Account 1 UPN</th><td>$(ConvertTo-HtmlEncodedText $account1Upn)</td></tr>
        <tr><th>Breakglass Account 2 UPN</th><td>$(ConvertTo-HtmlEncodedText $account2Upn)</td></tr>
    </table>

    <h2>Generated Initial Passwords</h2>
    <p class="muted">Passwords are included only for accounts created in this run. Existing account passwords cannot be retrieved.</p>
    <table>
        <tr><th>Account</th><th>Generated initial password</th></tr>
        $($passwordRows -join [Environment]::NewLine)
    </table>

    <h2>Conditional Access Exclusion Group</h2>
    <table>
        <tr><th>Group name</th><td>$(ConvertTo-HtmlEncodedText $GroupName)</td></tr>
        <tr><th>Group object id</th><td>$(ConvertTo-HtmlEncodedText $groupObjectId)</td></tr>
    </table>

    <h2>Group Membership Confirmation</h2>
    <table>
        <tr><th>Account</th><th>Member</th><th>Status</th></tr>
        $($groupRows -join [Environment]::NewLine)
    </table>

    <h2>Global Administrator Role Confirmation</h2>
    <table>
        <tr><th>Account</th><th>Global Administrator</th><th>Status</th></tr>
        $($globalAdminRows -join [Environment]::NewLine)
    </table>

    <h2>Admin SSPR Status</h2>
    <table>
        <tr><th>Status</th><td>$(ConvertTo-HtmlEncodedText $AdminSSPRStatus)</td></tr>
    </table>

    <h2>Actions Performed</h2>
    $(New-HtmlList -Items $actionItems)

    <h2>Manual Follow-Up Tasks</h2>
    $(New-HtmlList -Items $manualSteps)

    <h2>Important Warnings</h2>
    $(New-HtmlList -Items @(
        'The script does not delete users, groups, or Conditional Access policies.',
        "The '$GroupName' group must be manually excluded from all relevant Conditional Access policies.",
        'Administrator SSPR can not be disabled only for the two breakglass accounts. If changed, it applies tenant-wide to administrators in administrator roles.',
        'Generated passwords are not written to the normal log file.'
    ))

    <h2>Log File</h2>
    <p>$(ConvertTo-HtmlEncodedText $script:LogFile)</p>
</body>
</html>
"@

    Set-Content -Path $reportPath -Value $content -Encoding UTF8
    Add-RunResult "Generated confidential HTML report: $reportPath"
    Start-Process -FilePath $reportPath
    return $reportPath
}

function Invoke-BreakglassSetup {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string] $TenantName,
        [Parameter(Mandatory)][string] $BreakglassUpn1,
        [Parameter(Mandatory)][string] $BreakglassUpn2,
        [Parameter(Mandatory)][string] $GroupName,
        [bool] $CreateAccountsIfMissing,
        [bool] $CreateGroupIfMissing,
        [bool] $AddAccountsToGroup,
        [bool] $DisableAdminSspr,
        [bool] $GenerateDocumentation,
        [string] $OutputDirectory,
        [bool] $UseDeviceCode,
        [bool] $DryRun
    )

    $script:DryRun = $DryRun
    $script:RunResults.Clear()
    $script:CreatedUserSecrets.Clear()

    Write-Log -Message "Starting breakglass setup. Dry-run: $script:DryRun"

    Connect-BreakglassGraph -TenantName $TenantName -UseDeviceCode $UseDeviceCode | Out-Null
    $onMicrosoftDomain = Resolve-OnMicrosoftDomain -TenantName $TenantName
    Find-PotentialBreakglassAccounts -OnMicrosoftDomain $onMicrosoftDomain | Out-Null

    $user1 = Get-OrCreateBreakglassUser -InputUpn $BreakglassUpn1 -OnMicrosoftDomain $onMicrosoftDomain -CreateIfMissing $CreateAccountsIfMissing
    $user2 = Get-OrCreateBreakglassUser -InputUpn $BreakglassUpn2 -OnMicrosoftDomain $onMicrosoftDomain -CreateIfMissing $CreateAccountsIfMissing

    $group = Get-OrCreateBreakglassGroup -GroupName $GroupName -CreateIfMissing $CreateGroupIfMissing

    Show-Warning -Message "Manual step required: exclude '$GroupName' from all Conditional Access policies. This script will not modify or delete Conditional Access policies."

    if ($AddAccountsToGroup) {
        if (-not $group) {
            Add-RunResult "Could not add users to group because '$GroupName' does not exist."
        }
        else {
            Add-BreakglassUsersToGroup -Group $group -Users @($user1, $user2)
        }
    }

    if ($DisableAdminSspr) {
        Disable-AdminSSPR
    }

    $users = @($user1, $user2) | Where-Object { $_ }
    $groupMembershipStatus = @(Test-BreakglassGroupMembership -Group $group -Users $users)
    $globalAdministratorStatus = @(Test-GlobalAdministratorMembership -Users $users)
    $adminSSPRStatus = Get-AdminSSPRStatus

    if (-not $GenerateDocumentation) {
        Add-RunResult 'Confidential documentation generation is required and was generated even though the GUI option was cleared.'
    }

    $reportPath = Generate-Report `
        -TenantName $TenantName `
        -OnMicrosoftDomain $onMicrosoftDomain `
        -Users $users `
        -Group $group `
        -GroupName $GroupName `
        -OutputDirectory $OutputDirectory `
        -GroupMembershipStatus $groupMembershipStatus `
        -GlobalAdministratorStatus $globalAdministratorStatus `
        -AdminSSPRStatus $adminSSPRStatus

    $summary = "Completed. Log: $script:LogFile"
    if ($reportPath) {
        $summary += "`r`nConfidential report: $reportPath"
    }

    Invoke-UiThread -ScriptBlock {
        [System.Windows.MessageBox]::Show($summary, $script:AppName, 'OK', 'Information') | Out-Null
        return $null
    } | Out-Null
}

function Invoke-BreakglassWorkerMode {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $WorkerConfigPath)

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    if (-not (Test-Path -Path $WorkerConfigPath)) {
        throw "Worker config file was not found: $WorkerConfigPath"
    }

    $configObject = Get-Content -Path $WorkerConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

    if (-not [string]::IsNullOrWhiteSpace($configObject.LogFile)) {
        $script:LogFile = $configObject.LogFile
    }

    Write-Log -Message 'Worker process started.'

    $runConfig = @{
        TenantName               = [string] $configObject.TenantName
        BreakglassUpn1           = [string] $configObject.BreakglassUpn1
        BreakglassUpn2           = [string] $configObject.BreakglassUpn2
        GroupName                = [string] $configObject.GroupName
        CreateAccountsIfMissing = [bool] $configObject.CreateAccountsIfMissing
        CreateGroupIfMissing    = [bool] $configObject.CreateGroupIfMissing
        AddAccountsToGroup      = [bool] $configObject.AddAccountsToGroup
        DisableAdminSspr        = [bool] $configObject.DisableAdminSspr
        GenerateDocumentation   = [bool] $configObject.GenerateDocumentation
        OutputDirectory         = [string] $configObject.OutputDirectory
        UseDeviceCode           = [bool] $configObject.UseDeviceCode
        DryRun                  = [bool] $configObject.DryRun
    }

    Invoke-BreakglassSetup @runConfig
    Write-Log -Message 'Worker process completed.'
}

function Start-BreakglassWorkerProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable] $RunConfig,
        [Parameter(Mandatory)] $RunButton
    )

    $workerConfig = @{} + $RunConfig
    $workerConfig.LogFile = $script:LogFile
    $script:ActiveRunButton = $RunButton

    $script:WorkerConfigPath = Join-Path -Path $script:LogDirectory -ChildPath ("WorkerConfig_{0}.json" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $workerConfig | ConvertTo-Json -Depth 5 | Set-Content -Path $script:WorkerConfigPath -Encoding UTF8

    $powerShellExe = Join-Path -Path $PSHOME -ChildPath 'powershell.exe'
    if (-not (Test-Path -Path $powerShellExe)) {
        $powerShellExe = (Get-Command powershell.exe -ErrorAction Stop).Source
    }

    $arguments = @(
        '-NoProfile',
        '-Sta',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $PSCommandPath),
        '-WorkerMode',
        '-ConfigPath', ('"{0}"' -f $script:WorkerConfigPath)
    ) -join ' '

    Write-Log -Message 'Starting setup in a separate PowerShell worker process so the GUI stays responsive.'
    $script:WorkerProcess = Start-Process -FilePath $powerShellExe -ArgumentList $arguments -WindowStyle Normal -PassThru

    $script:WorkerTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:WorkerTimer.Interval = [TimeSpan]::FromSeconds(1)
    $script:WorkerTimer.Add_Tick({
        Sync-LogViewFromFile

        if (-not $script:WorkerProcess) {
            return
        }

        if ($script:WorkerProcess.HasExited) {
            $script:WorkerTimer.Stop()
            Sync-LogViewFromFile
            $exitCode = $script:WorkerProcess.ExitCode
            $script:WorkerProcess.Dispose()
            $script:WorkerProcess = $null
            $script:WorkerTimer = $null

            $script:ActiveRunButton.IsEnabled = $true
            $script:ActiveRunButton.Content = 'Run setup'
            $script:ActiveRunButton = $null

            if ($exitCode -eq 0) {
                Write-Log -Message 'Worker process completed successfully.'
            }
            else {
                Write-Log -Level ERROR -Message "Worker process exited with code $exitCode. Review the log for details."
                [System.Windows.MessageBox]::Show("Worker process exited with code $exitCode. Review the log for details.", "$($script:AppName) - error", 'OK', 'Error') | Out-Null
            }
        }
    })

    $script:WorkerTimer.Start()
}

function Start-BreakglassWpfGui {
    [CmdletBinding()]
    param()

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    Add-Type -AssemblyName System.Windows.Forms

    [xml] $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Microsoft Entra Breakglass Setup"
        Height="780"
        Width="980"
        MinHeight="720"
        MinWidth="900"
        WindowStartupLocation="CenterScreen"
        Background="#F6F8FA">
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0" Margin="0,0,0,16">
            <TextBlock Text="Microsoft Entra Breakglass Setup" FontSize="24" FontWeight="SemiBold" Foreground="#1F2937"/>
            <TextBlock Text="Configure, validate, and document best practice breakglass prerequisites without modifying Conditional Access policies." FontSize="13" Foreground="#4B5563" Margin="0,6,0,0"/>
        </StackPanel>

        <Border Grid.Row="1" BorderBrush="#D1D5DB" BorderThickness="1" Background="White" CornerRadius="6" Padding="16" Margin="0,0,0,14">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="180"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="220"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <TextBlock Grid.Row="0" Grid.Column="0" Text="Tenant ID/domain (optional)" VerticalAlignment="Center" Margin="0,0,10,10"/>
                <TextBox x:Name="TenantNameTextBox" Grid.Row="0" Grid.Column="1" Grid.ColumnSpan="3" Height="28" Margin="0,0,0,10"/>

                <TextBlock Grid.Row="1" Grid.Column="0" Text="Breakglass account 1 UPN or prefix" VerticalAlignment="Center" Margin="0,0,10,10"/>
                <TextBox x:Name="BreakglassUpn1TextBox" Grid.Row="1" Grid.Column="1" Grid.ColumnSpan="3" Height="28" Margin="0,0,0,10"/>

                <TextBlock Grid.Row="2" Grid.Column="0" Text="Breakglass account 2 UPN or prefix" VerticalAlignment="Center" Margin="0,0,10,10"/>
                <TextBox x:Name="BreakglassUpn2TextBox" Grid.Row="2" Grid.Column="1" Grid.ColumnSpan="3" Height="28" Margin="0,0,0,10"/>

                <TextBlock Grid.Row="3" Grid.Column="0" Text="Naming presets" VerticalAlignment="Center" Margin="0,0,10,10"/>
                <StackPanel Grid.Row="3" Grid.Column="1" Grid.ColumnSpan="3" Orientation="Horizontal" Margin="0,0,0,10">
                    <Button x:Name="UseSvrEaPresetButton" Content="Use svr_ea01 / svr_ea02" Height="28" Width="170" Margin="0,0,8,0"/>
                    <Button x:Name="UseAdmEaPresetButton" Content="Use adm_ea01 / adm_ea02" Height="28" Width="170"/>
                </StackPanel>

                <TextBlock Grid.Row="4" Grid.Column="0" Text="Security group name" VerticalAlignment="Center" Margin="0,0,10,14"/>
                <TextBox x:Name="GroupNameTextBox" Grid.Row="4" Grid.Column="1" Grid.ColumnSpan="3" Height="28" Text="CA-BreakGlassExclude" Margin="0,0,0,14"/>

                <TextBlock Grid.Row="5" Grid.Column="0" Text="Output folder" VerticalAlignment="Center" Margin="0,0,10,14"/>
                <TextBox x:Name="OutputFolderTextBox" Grid.Row="5" Grid.Column="1" Grid.ColumnSpan="2" Height="28" Margin="0,0,8,14"/>
                <Button x:Name="BrowseOutputFolderButton" Grid.Row="5" Grid.Column="3" Content="Browse..." Height="28" Width="90" HorizontalAlignment="Left" Margin="0,0,0,14"/>

                <CheckBox x:Name="CreateAccountsCheckBox" Grid.Row="6" Grid.Column="0" Grid.ColumnSpan="2" Content="Create accounts if missing" IsChecked="True" Margin="0,0,0,10"/>
                <CheckBox x:Name="CreateGroupCheckBox" Grid.Row="6" Grid.Column="2" Grid.ColumnSpan="2" Content="Create group if missing" IsChecked="True" Margin="0,0,0,10"/>
                <CheckBox x:Name="AddToGroupCheckBox" Grid.Row="7" Grid.Column="0" Grid.ColumnSpan="2" Content="Add accounts to group" IsChecked="True" Margin="0,0,0,0"/>
                <CheckBox x:Name="DisableAdminSsprCheckBox" Grid.Row="7" Grid.Column="2" Content="Disable admin SSPR" Margin="0,0,0,0"/>
                <CheckBox x:Name="GenerateDocumentationCheckBox" Grid.Row="7" Grid.Column="3" Content="Generate confidential documentation" IsChecked="True" Margin="0,0,0,0"/>
            </Grid>
        </Border>

        <Grid Grid.Row="2">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <DockPanel Grid.Row="0" Margin="0,0,0,8">
                <TextBlock Text="Run log" FontSize="16" FontWeight="SemiBold" Foreground="#1F2937" DockPanel.Dock="Left"/>
                <StackPanel Orientation="Horizontal" DockPanel.Dock="Right" HorizontalAlignment="Right">
                    <CheckBox x:Name="RunInCurrentTerminalCheckBox" Content="Run in current terminal" IsChecked="True" Margin="0,0,18,0"/>
                    <CheckBox x:Name="UseDeviceCodeCheckBox" Content="Fallback: device code sign-in" IsChecked="False" Margin="0,0,18,0"/>
                    <CheckBox x:Name="DryRunCheckBox" Content="Dry-run mode" IsChecked="True"/>
                </StackPanel>
            </DockPanel>
            <TextBox x:Name="LogTextBox" Grid.Row="1" IsReadOnly="True" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" FontFamily="Consolas" FontSize="12" Background="#111827" Foreground="#E5E7EB" Padding="10"/>
        </Grid>

        <DockPanel Grid.Row="3" Margin="0,14,0,0">
            <StackPanel Orientation="Horizontal" DockPanel.Dock="Right" HorizontalAlignment="Right">
                <Button x:Name="RunButton" Content="Run setup" Width="110" Height="34" Margin="0,0,8,0" IsDefault="True"/>
                <Button x:Name="ClearLogButton" Content="Clear log view" Width="110" Height="34" Margin="0,0,8,0"/>
                <Button x:Name="OpenLogButton" Content="Open log folder" Width="120" Height="34" Margin="0,0,8,0"/>
                <Button x:Name="ExitButton" Content="Exit" Width="80" Height="34"/>
            </StackPanel>
        </DockPanel>
    </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $script:MainWindow = [Windows.Markup.XamlReader]::Load($reader)
    $script:MainWindow.Dispatcher.add_UnhandledException({
        param($Sender, $EventArgs)

        $exceptionMessage = "Unhandled WPF dispatcher error: $($EventArgs.Exception.Message)"
        Write-Log -Level ERROR -Message $exceptionMessage
        [System.Windows.MessageBox]::Show($exceptionMessage, "$($script:AppName) - WPF error", 'OK', 'Error') | Out-Null
        $EventArgs.Handled = $true
    })
    $script:MainWindow.Add_Loaded({
        Write-Log -Message 'GUI loaded and visible.'
    })
    $script:MainWindow.Add_ContentRendered({
        try {
            $script:MainWindow.WindowState = 'Normal'
            $script:MainWindow.Activate() | Out-Null
            $script:MainWindow.Focus() | Out-Null
        }
        catch {
            Write-Log -Level WARN -Message "Could not activate GUI window: $($_.Exception.Message)"
        }
    })
    $script:MainWindow.Add_Closed({
        Write-Log -Message 'GUI closed.'
    })

    $tenantNameTextBox = $script:MainWindow.FindName('TenantNameTextBox')
    $breakglassUpn1TextBox = $script:MainWindow.FindName('BreakglassUpn1TextBox')
    $breakglassUpn2TextBox = $script:MainWindow.FindName('BreakglassUpn2TextBox')
    $groupNameTextBox = $script:MainWindow.FindName('GroupNameTextBox')
    $outputFolderTextBox = $script:MainWindow.FindName('OutputFolderTextBox')
    $browseOutputFolderButton = $script:MainWindow.FindName('BrowseOutputFolderButton')
    $useSvrEaPresetButton = $script:MainWindow.FindName('UseSvrEaPresetButton')
    $useAdmEaPresetButton = $script:MainWindow.FindName('UseAdmEaPresetButton')
    $createAccountsCheckBox = $script:MainWindow.FindName('CreateAccountsCheckBox')
    $createGroupCheckBox = $script:MainWindow.FindName('CreateGroupCheckBox')
    $addToGroupCheckBox = $script:MainWindow.FindName('AddToGroupCheckBox')
    $disableAdminSsprCheckBox = $script:MainWindow.FindName('DisableAdminSsprCheckBox')
    $generateDocumentationCheckBox = $script:MainWindow.FindName('GenerateDocumentationCheckBox')
    $runInCurrentTerminalCheckBox = $script:MainWindow.FindName('RunInCurrentTerminalCheckBox')
    $useDeviceCodeCheckBox = $script:MainWindow.FindName('UseDeviceCodeCheckBox')
    $dryRunCheckBox = $script:MainWindow.FindName('DryRunCheckBox')
    $runButton = $script:MainWindow.FindName('RunButton')
    $clearLogButton = $script:MainWindow.FindName('ClearLogButton')
    $openLogButton = $script:MainWindow.FindName('OpenLogButton')
    $exitButton = $script:MainWindow.FindName('ExitButton')
    $script:LogTextBox = $script:MainWindow.FindName('LogTextBox')
    $outputFolderTextBox.Text = $script:ReportDirectory

    Write-Log -Message "GUI started. Log file: $script:LogFile"

    $useSvrEaPresetButton.Add_Click({
        $breakglassUpn1TextBox.Text = 'svr_ea01'
        $breakglassUpn2TextBox.Text = 'svr_ea02'
        Write-Log -Message 'Applied naming preset: svr_ea01 / svr_ea02.'
    })

    $useAdmEaPresetButton.Add_Click({
        $breakglassUpn1TextBox.Text = 'adm_ea01'
        $breakglassUpn2TextBox.Text = 'adm_ea02'
        Write-Log -Message 'Applied naming preset: adm_ea01 / adm_ea02.'
    })

    $browseOutputFolderButton.Add_Click({
        $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderDialog.Description = 'Select folder for the confidential breakglass report'
        $folderDialog.ShowNewFolderButton = $true

        if (-not [string]::IsNullOrWhiteSpace($outputFolderTextBox.Text) -and (Test-Path -Path $outputFolderTextBox.Text)) {
            $folderDialog.SelectedPath = $outputFolderTextBox.Text
        }
        else {
            $folderDialog.SelectedPath = $script:ReportDirectory
        }

        $result = $folderDialog.ShowDialog()
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            $outputFolderTextBox.Text = $folderDialog.SelectedPath
            Write-Log -Message "Output folder selected: $($folderDialog.SelectedPath)"
        }
    })

    $runButton.Add_Click({
        if ([string]::IsNullOrWhiteSpace($breakglassUpn1TextBox.Text) -or
            [string]::IsNullOrWhiteSpace($breakglassUpn2TextBox.Text) -or
            [string]::IsNullOrWhiteSpace($groupNameTextBox.Text)) {
            [System.Windows.MessageBox]::Show('Both account fields and group name are required. Tenant can be blank and will be resolved after sign-in.', $script:AppName, 'OK', 'Warning') | Out-Null
            return
        }

        $runConfig = @{
            TenantName                = $tenantNameTextBox.Text.Trim()
            BreakglassUpn1           = $breakglassUpn1TextBox.Text.Trim()
            BreakglassUpn2           = $breakglassUpn2TextBox.Text.Trim()
            GroupName                = $groupNameTextBox.Text.Trim()
            CreateAccountsIfMissing  = [bool] $createAccountsCheckBox.IsChecked
            CreateGroupIfMissing     = [bool] $createGroupCheckBox.IsChecked
            AddAccountsToGroup       = [bool] $addToGroupCheckBox.IsChecked
            DisableAdminSspr         = [bool] $disableAdminSsprCheckBox.IsChecked
            GenerateDocumentation    = [bool] $generateDocumentationCheckBox.IsChecked
            OutputDirectory          = $outputFolderTextBox.Text.Trim()
            UseDeviceCode            = [bool] $useDeviceCodeCheckBox.IsChecked
            DryRun                   = [bool] $dryRunCheckBox.IsChecked
        }

        $runButton.IsEnabled = $false
        $runButton.Content = 'Running...'

        if ([bool] $runInCurrentTerminalCheckBox.IsChecked) {
            try {
                Write-Log -Message 'Running setup in the current PowerShell session so sign-in prompts are visible.'
                Invoke-BreakglassSetup @runConfig
            }
            catch {
                Write-Log -Level ERROR -Message $_.Exception.Message
                [System.Windows.MessageBox]::Show($_.Exception.Message, "$($script:AppName) - error", 'OK', 'Error') | Out-Null
            }
            finally {
                $runButton.IsEnabled = $true
                $runButton.Content = 'Run setup'
            }
        }
        else {
            Start-BreakglassWorkerProcess -RunConfig $runConfig -RunButton $runButton
        }
    })

    $clearLogButton.Add_Click({
        $script:LogTextBox.Clear()
        Write-Log -Message 'Log view cleared.'
    })

    $openLogButton.Add_Click({
        Start-Process explorer.exe -ArgumentList $script:LogDirectory
    })

    $exitButton.Add_Click({
        $script:MainWindow.Close()
    })

    $dialogResult = $script:MainWindow.ShowDialog()
    Write-Log -Message "GUI ShowDialog returned: $dialogResult"
}

try {
    if ($WorkerMode) {
        Invoke-BreakglassWorkerMode -WorkerConfigPath $ConfigPath
    }
    else {
        Start-BreakglassWpfGui
    }
}
catch {
    $message = "Startup failed: $($_.Exception.Message)"
    try {
        Write-Log -Level ERROR -Message $message
    }
    catch {
        $fallbackLog = Join-Path -Path $PSScriptRoot -ChildPath ("BreakglassStartupError_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        Set-Content -Path $fallbackLog -Value $message -Encoding UTF8
    }

    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
        [System.Windows.MessageBox]::Show($message, "$($script:AppName) - startup error", 'OK', 'Error') | Out-Null
    }
    catch {
        Write-Error $message
    }

    throw
}

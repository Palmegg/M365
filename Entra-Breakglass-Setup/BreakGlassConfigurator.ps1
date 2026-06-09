#requires -Version 5.1
<#
.SYNOPSIS
    NetIP Entra Break Glass Configurator v1.

.DESCRIPTION
    Danish WPF wizard for configuring and validating a Microsoft Entra break-glass baseline.
    The script uses Microsoft Graph PowerShell, Microsoft Graph REST, Az PowerShell, and ARM REST.
    It does not automate FIDO2 registration and never writes generated passwords or secrets to logs or reports.
#>

[CmdletBinding()]
param(
    [switch] $Mock,
    [switch] $NoApply,
    [switch] $WorkerMode,
    [string] $WorkerConfigPath,
    [switch] $ModuleWorkerMode,
    [string] $ModuleWorkerLogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AppName = 'NetIP Entra Break Glass Configurator'
$script:AppVersion = '1.0.0'
$script:ProjectRoot = Split-Path -Parent $PSCommandPath
if ([string]::IsNullOrWhiteSpace($script:ProjectRoot)) {
    $script:ProjectRoot = (Get-Location).Path
}
$script:DefaultOutputRoot = Join-Path -Path $script:ProjectRoot -ChildPath 'Output'
$script:SessionOutputFolder = $null
$script:LogFile = Join-Path -Path $script:ProjectRoot -ChildPath 'app-startup.log'
$script:MainWindow = $null
$script:LogTextBox = $null
$script:LogPollTimer = $null
$script:WorkerProcess = $null
$script:ModuleWorkerProcess = $null
$script:ModuleWorkerLogFile = ''
$script:LastLogLength = 0
$script:WizardMaxStep = 0
$script:WizardInternalNavigation = $false
$script:PrecheckPassed = $false
$script:PlanBuilt = $false

$script:RequiredGraphScopes = @(
    'User.ReadWrite.All',
    'Group.ReadWrite.All',
    'Directory.ReadWrite.All',
    'RoleManagement.ReadWrite.Directory',
    'Policy.Read.All',
    'Policy.ReadWrite.ConditionalAccess',
    'Policy.ReadWrite.AuthenticationMethod',
    'UserAuthenticationMethod.Read.All',
    'Organization.Read.All'
)

$script:RequiredModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Users',
    'Microsoft.Graph.Groups',
    'Microsoft.Graph.Identity.DirectoryManagement',
    'Microsoft.Graph.Identity.SignIns',
    'Microsoft.Graph.Identity.Governance',
    'Az.Accounts',
    'Az.Resources',
    'Az.OperationalInsights',
    'Az.Monitor'
)

$script:State = [ordered]@{
    Mock                         = [bool] $Mock
    NoApply                      = [bool] $NoApply
    GraphConnected               = $false
    AzureConnected               = $false
    GraphAccount                 = ''
    GraphScopes                  = @()
    TenantId                     = ''
    TenantDisplayName            = ''
    OnMicrosoftDomain            = ''
    AzureAccount                 = ''
    AzureSubscriptionId          = ''
    AzureSubscriptionName        = ''
    OutputFolder                 = ''
    Plan                         = $null
    Result                       = $null
    ValidationResults            = @()
    Warnings                     = New-Object System.Collections.Generic.List[string]
    CaBackupFiles                = @()
    CreatedPasswords             = New-Object System.Collections.Generic.List[object]
}

function Test-StaMode {
    [CmdletBinding()]
    param()

    return ([System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA)
}

function Restart-InStaModeIfNeeded {
    [CmdletBinding()]
    param()

    if ($WorkerMode -or $ModuleWorkerMode) {
        return
    }

    if (-not (Test-StaMode)) {
        $powerShell = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', ('"{0}"' -f $PSCommandPath))
        if ($Mock) { $arguments += '-Mock' }
        if ($NoApply) { $arguments += '-NoApply' }
        Write-Host 'Genstarter i Windows PowerShell STA til WPF...' -ForegroundColor Cyan
        Start-Process -FilePath $powerShell -ArgumentList ($arguments -join ' ') -Wait
        exit 0
    }
}

function ConvertTo-RedactedError {
    [CmdletBinding()]
    param([AllowNull()] $ErrorObject)

    $text = if ($ErrorObject -is [System.Management.Automation.ErrorRecord]) {
        $ErrorObject.Exception.Message
    }
    elseif ($ErrorObject) {
        [string] $ErrorObject
    }
    else {
        ''
    }

    if ([string]::IsNullOrWhiteSpace($text)) {
        return ''
    }

    $patterns = @(
        '(?i)(access_token|refresh_token|client_secret|password|passwd|pwd|secret)\s*[:=]\s*[^,\s;\}]+',
        '(?i)Bearer\s+[A-Za-z0-9\._\-]+',
        '(?i)eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+'
    )
    foreach ($pattern in $patterns) {
        $text = [regex]::Replace($text, $pattern, '$1=[REDACTED]')
    }

    return $text
}

function Write-AppLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'PLAN', 'SKIP', 'PASS', 'FAIL')]
        [string] $Level = 'INFO'
    )

    $safeMessage = ConvertTo-RedactedError -ErrorObject $Message
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $safeMessage
    $folder = Split-Path -Parent $script:LogFile
    if (-not [string]::IsNullOrWhiteSpace($folder)) {
        New-Item -ItemType Directory -Force -Path $folder | Out-Null
    }
    Add-Content -Path $script:LogFile -Value $line -Encoding UTF8

    if ($script:LogTextBox -and $script:LogTextBox.Dispatcher.CheckAccess()) {
        $script:LogTextBox.AppendText($line + [Environment]::NewLine)
        $script:LogTextBox.ScrollToEnd()
    }
}

function Write-SafeError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Message,
        [AllowNull()] $ErrorRecord
    )

    $safe = ConvertTo-RedactedError -ErrorObject $ErrorRecord
    if ([string]::IsNullOrWhiteSpace($safe)) {
        Write-AppLog -Level ERROR -Message $Message
    }
    else {
        Write-AppLog -Level ERROR -Message "$Message $safe"
    }
}

function Show-AppMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Message,
        [string] $Title = $script:AppName,
        [string] $Buttons = 'OK',
        [string] $Icon = 'Information'
    )

    if ($script:MainWindow) {
        $previousTopmost = $false
        try {
            $previousTopmost = [bool] $script:MainWindow.Topmost
            $script:MainWindow.Topmost = $true
            $script:MainWindow.Activate() | Out-Null
            $result = [System.Windows.MessageBox]::Show($script:MainWindow, $Message, $Title, $Buttons, $Icon)
            $script:MainWindow.Topmost = $previousTopmost
            return $result
        }
        catch {
            if ($script:MainWindow) {
                $script:MainWindow.Topmost = $previousTopmost
            }
            return [System.Windows.MessageBox]::Show($Message, $Title, $Buttons, $Icon)
        }
    }

    return [System.Windows.MessageBox]::Show($Message, $Title, $Buttons, $Icon)
}

function Initialize-AppState {
    [CmdletBinding()]
    param()

    Restart-InStaModeIfNeeded
    New-Item -ItemType Directory -Force -Path $script:DefaultOutputRoot | Out-Null
    Write-AppLog -Message "$($script:AppName) v$($script:AppVersion) initialiseret. Mock: $($script:State.Mock). NoApply: $($script:State.NoApply)."
}

function New-OutputFolder {
    [CmdletBinding()]
    param([string] $TenantId)

    $safeTenant = if ([string]::IsNullOrWhiteSpace($TenantId)) { 'UnknownTenant' } else { $TenantId -replace '[^a-zA-Z0-9\-]', '_' }
    $folder = Join-Path -Path $script:DefaultOutputRoot -ChildPath ('BreakGlassConfig-{0}-{1}' -f $safeTenant, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    $script:SessionOutputFolder = $folder
    $script:State['OutputFolder'] = $folder
    $script:LogFile = Join-Path -Path $folder -ChildPath 'app.log'
    Write-AppLog -Message "Outputmappe oprettet: $folder"
    return $folder
}

function Export-JsonSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $InputObject,
        [Parameter(Mandatory)][string] $Path,
        [int] $Depth = 20
    )

    $json = $InputObject | ConvertTo-Json -Depth $Depth
    $json = [regex]::Replace($json, '(?i)("?(password|secret|token|accessToken|refreshToken)"?\s*:\s*)".*?"', '$1"[REDACTED]"')
    Set-Content -Path $Path -Value $json -Encoding UTF8
    return $Path
}

function ConvertTo-HashtableRecursive {
    [CmdletBinding()]
    param([AllowNull()] $InputObject)

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $hash = @{}
        foreach ($key in $InputObject.Keys) {
            $hash[$key] = ConvertTo-HashtableRecursive -InputObject $InputObject[$key]
        }
        return $hash
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        return @($InputObject | ForEach-Object { ConvertTo-HashtableRecursive -InputObject $_ })
    }

    if ($InputObject.GetType().FullName -eq 'System.Management.Automation.PSCustomObject' -and @($InputObject.PSObject.Properties).Count -gt 0) {
        $hash = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $hash[$property.Name] = ConvertTo-HashtableRecursive -InputObject $property.Value
        }
        return $hash
    }

    return $InputObject
}

function Test-RequiredModules {
    [CmdletBinding()]
    param()

    $results = foreach ($module in $script:RequiredModules) {
        $found = Get-Module -ListAvailable -Name $module | Select-Object -First 1
        [pscustomobject]@{
            Name    = $module
            Present = [bool] $found
            Version = if ($found) { [string] $found.Version } else { '' }
        }
    }
    return @($results)
}

function Install-RequiredModulesWithConsent {
    [CmdletBinding()]
    param([object[]] $ModuleStatus)

    $missing = @($ModuleStatus | Where-Object { -not $_.Present })
    if ($missing.Count -eq 0) {
        Write-AppLog -Message 'Alle nødvendige moduler findes.'
        return
    }

    $message = "Følgende PowerShell moduler mangler og kan installeres for CurrentUser:`r`n`r`n$($missing.Name -join "`r`n")`r`n`r`nInstaller nu?"
    if ((Show-AppMessage -Message $message -Title "$($script:AppName) - modulinstallation" -Buttons 'YesNo' -Icon 'Question') -ne 'Yes') {
        throw 'Nødvendige moduler mangler, og installation blev afvist.'
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion '2.8.5.201' -Scope CurrentUser -Force -ErrorAction Stop | Out-Null
    }

    foreach ($module in $missing.Name) {
        Write-AppLog -Message "Installerer modul: $module"
        Install-Module -Name $module -Scope CurrentUser -Repository PSGallery -AllowClobber -Force -ErrorAction Stop
    }
}

function Import-RequiredModules {
    [CmdletBinding()]
    param()

    foreach ($module in $script:RequiredModules) {
        Write-AppLog -Message "Importerer modul: $module"
        Import-Module $module -ErrorAction Stop
    }
}

function Start-ModulePreparationWorker {
    [CmdletBinding()]
    param()

    $folder = Join-Path -Path $script:DefaultOutputRoot -ChildPath ('ModulePreparation-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    $script:ModuleWorkerLogFile = Join-Path -Path $folder -ChildPath 'module-worker.log'
    $powerShell = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $args = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        ('"{0}"' -f $PSCommandPath),
        '-ModuleWorkerMode',
        '-ModuleWorkerLogPath',
        ('"{0}"' -f $script:ModuleWorkerLogFile)
    )
    $script:ModuleWorkerProcess = Start-Process -FilePath $powerShell -ArgumentList ($args -join ' ') -PassThru -WindowStyle Normal
    Set-UiStatus -Message 'Modulinstallation kører i et separat PowerShell vindue. Godkend prompten dér.' -Busy -Log
}

function Invoke-ModulePreparationWorkerMode {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $LogPath)

    $script:LogFile = $LogPath
    Write-AppLog -Message 'Module preparation worker startet.'
    Write-Host ''
    Write-Host 'NetIP Entra Break Glass Configurator - module preparation' -ForegroundColor Cyan
    Write-Host 'Denne worker installerer kun PowerShell-moduler for CurrentUser.' -ForegroundColor Cyan
    Write-Host ''

    $status = Test-RequiredModules
    $missing = @($status | Where-Object { -not $_.Present })
    if ($missing.Count -eq 0) {
        Write-AppLog -Message 'Alle nødvendige moduler findes allerede.'
        Write-Host 'Alle nødvendige moduler findes allerede.' -ForegroundColor Green
        exit 0
    }

    Write-AppLog -Level WARN -Message "Manglende moduler: $($missing.Name -join ', ')"
    Write-Host 'Manglende moduler:' -ForegroundColor Yellow
    foreach ($module in $missing.Name) {
        Write-Host " - $module" -ForegroundColor Yellow
    }
    Write-Host ''
    $answer = Read-Host 'Installer manglende moduler for CurrentUser fra PSGallery? Skriv Y for ja'
    if ($answer -notin @('Y','y','YES','Yes','yes','J','j','JA','Ja','ja')) {
        Write-AppLog -Level WARN -Message 'Modulinstallation blev afvist af brugeren.'
        Write-Host 'Modulinstallation afbrudt.' -ForegroundColor Yellow
        exit 20
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Write-AppLog -Message 'Installerer NuGet package provider.'
        Write-Host 'Installerer NuGet package provider...' -ForegroundColor Cyan
        Install-PackageProvider -Name NuGet -MinimumVersion '2.8.5.201' -Scope CurrentUser -Force -ErrorAction Stop | Out-Null
    }

    foreach ($module in $missing.Name) {
        Write-AppLog -Message "Installerer modul: $module"
        Write-Host "Installerer modul: $module" -ForegroundColor Cyan
        Install-Module -Name $module -Scope CurrentUser -Repository PSGallery -AllowClobber -Force -ErrorAction Stop
    }

    $after = Test-RequiredModules
    $stillMissing = @($after | Where-Object { -not $_.Present })
    if ($stillMissing.Count -gt 0) {
        Write-AppLog -Level ERROR -Message "Moduler mangler stadig: $($stillMissing.Name -join ', ')"
        Write-Host "Moduler mangler stadig: $($stillMissing.Name -join ', ')" -ForegroundColor Red
        exit 30
    }

    Write-AppLog -Level PASS -Message 'Modulinstallation færdig.'
    Write-Host ''
    Write-Host 'Modulinstallation færdig. Du kan lukke dette vindue og trykke connect i GUI igen.' -ForegroundColor Green
    Start-Sleep -Seconds 3
    exit 0
}

function Connect-AppGraph {
    [CmdletBinding()]
    param()

    if ($script:State.Mock) {
        $script:State['GraphConnected'] = $true
        $script:State['GraphAccount'] = 'mock-operator@contoso.onmicrosoft.com'
        $script:State['GraphScopes'] = $script:RequiredGraphScopes
        $script:State['TenantId'] = '00000000-0000-0000-0000-000000000001'
        $script:State['TenantDisplayName'] = 'Mock Tenant'
        $script:State['OnMicrosoftDomain'] = 'contoso.onmicrosoft.com'
        Write-AppLog -Message 'Mock Graph-forbindelse oprettet.'
        return $script:State
    }

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    Write-AppLog -Message "Forbinder til Microsoft Graph med scopes: $($script:RequiredGraphScopes -join ', ')"
    Connect-MgGraph -Scopes $script:RequiredGraphScopes -ContextScope Process -NoWelcome -ErrorAction Stop | Out-Null
    $context = Get-MgContext
    if (-not $context) {
        throw 'Microsoft Graph context blev ikke returneret.'
    }

    $script:State['GraphConnected'] = $true
    $script:State['GraphAccount'] = [string] $context.Account
    $script:State['GraphScopes'] = @($context.Scopes)
    $script:State['TenantId'] = [string] $context.TenantId
    Get-TenantInfo | Out-Null
    Write-AppLog -Message "Graph forbundet som $($script:State.GraphAccount), tenant $($script:State.TenantId)."
    return $script:State
}

function Get-AppGraphContext {
    [CmdletBinding()]
    param()

    if ($script:State.Mock) {
        return [pscustomobject]$script:State
    }
    return Get-MgContext
}

function Test-GraphScopes {
    [CmdletBinding()]
    param()

    $context = Get-AppGraphContext
    $granted = @()
    if ($context -and $context.PSObject.Properties['Scopes']) {
        $granted = @($context.Scopes)
    }
    elseif ($script:State.GraphScopes) {
        $granted = @($script:State.GraphScopes)
    }

    foreach ($scope in $script:RequiredGraphScopes) {
        [pscustomobject]@{
            Scope   = $scope
            Present = ($granted -contains $scope)
            Status  = if ($granted -contains $scope) { 'Passed' } else { 'Warning' }
        }
    }
}

function Invoke-GraphRequestSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GET','POST','PATCH','PUT','DELETE')] [string] $Method,
        [Parameter(Mandatory)][string] $Uri,
        [object] $Body
    )

    if ($script:State.Mock) {
        Write-AppLog -Level PLAN -Message "Mock Graph $Method $Uri"
        return [pscustomobject]@{ value = @() }
    }

    try {
        if ($null -ne $Body) {
            $payload = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 30 }
            return Invoke-MgGraphRequest -Method $Method -Uri $Uri -Body $payload -ContentType 'application/json' -ErrorAction Stop
        }
        return Invoke-MgGraphRequest -Method $Method -Uri $Uri -ErrorAction Stop
    }
    catch {
        Write-SafeError -Message "Graph-kald fejlede: $Method $Uri." -ErrorRecord $_
        throw
    }
}

function Invoke-GraphGetAllPages {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Uri)

    $items = New-Object System.Collections.Generic.List[object]
    $next = $Uri
    while (-not [string]::IsNullOrWhiteSpace($next)) {
        $response = Invoke-GraphRequestSafe -Method GET -Uri $next
        if ($response.PSObject.Properties['value']) {
            foreach ($item in @($response.value)) {
                $items.Add($item) | Out-Null
            }
        }
        $nextProperty = $response.PSObject.Properties['@odata.nextLink']
        $next = if ($nextProperty) { [string] $nextProperty.Value } else { $null }
    }
    return @($items)
}

function Connect-AppAzure {
    [CmdletBinding()]
    param()

    if ($script:State.Mock) {
        $script:State['AzureConnected'] = $true
        $script:State['AzureAccount'] = 'mock-operator@contoso.onmicrosoft.com'
        $script:State['AzureSubscriptionId'] = '00000000-0000-0000-0000-000000000002'
        $script:State['AzureSubscriptionName'] = 'Mock Subscription'
        Write-AppLog -Message 'Mock Azure-forbindelse oprettet.'
        return $script:State
    }

    Import-Module Az.Accounts -ErrorAction Stop
    Connect-AzAccount -ErrorAction Stop | Out-Null
    $context = Get-AzContext
    if (-not $context) {
        throw 'Azure context blev ikke returneret.'
    }
    $script:State['AzureConnected'] = $true
    $script:State['AzureAccount'] = [string] $context.Account
    $script:State['AzureSubscriptionId'] = [string] $context.Subscription.Id
    $script:State['AzureSubscriptionName'] = [string] $context.Subscription.Name
    Write-AppLog -Message "Azure forbundet som $($script:State.AzureAccount), subscription $($script:State.AzureSubscriptionName)."
    return $script:State
}

function Get-AppAzureContext {
    [CmdletBinding()]
    param()

    if ($script:State.Mock) {
        return [pscustomobject]@{
            Account      = $script:State.AzureAccount
            Subscription = [pscustomobject]@{
                Id   = $script:State.AzureSubscriptionId
                Name = $script:State.AzureSubscriptionName
            }
        }
    }
    return Get-AzContext
}

function Get-OrSelectSubscription {
    [CmdletBinding()]
    param([string] $SubscriptionId)

    if ($script:State.Mock) {
        return $script:State.AzureSubscriptionId
    }

    if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) {
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
    }
    $context = Get-AzContext
    $script:State['AzureSubscriptionId'] = [string] $context.Subscription.Id
    $script:State['AzureSubscriptionName'] = [string] $context.Subscription.Name
    return $script:State.AzureSubscriptionId
}

function Get-TenantInfo {
    [CmdletBinding()]
    param()

    if ($script:State.Mock) {
        return [pscustomobject]@{
            Id                = $script:State.TenantId
            DisplayName       = $script:State.TenantDisplayName
            OnMicrosoftDomain = $script:State.OnMicrosoftDomain
        }
    }

    $organization = Invoke-GraphGetAllPages -Uri 'https://graph.microsoft.com/v1.0/organization?$select=id,displayName,verifiedDomains' | Select-Object -First 1
    if (-not $organization) {
        throw 'Kunne ikke læse tenant organization fra Graph.'
    }

    $script:State['TenantId'] = [string] $organization.id
    $script:State['TenantDisplayName'] = [string] $organization.displayName
    $script:State['OnMicrosoftDomain'] = Get-OnMicrosoftDomain -Organization $organization
    return [pscustomobject]@{
        Id                = $script:State.TenantId
        DisplayName       = $script:State.TenantDisplayName
        OnMicrosoftDomain = $script:State.OnMicrosoftDomain
    }
}

function Get-OnMicrosoftDomain {
    [CmdletBinding()]
    param([AllowNull()] $Organization)

    if ($script:State.Mock) {
        return $script:State.OnMicrosoftDomain
    }

    $domains = @()
    if ($Organization -and $Organization.PSObject.Properties['verifiedDomains']) {
        $domains = @($Organization.verifiedDomains)
    }
    if ($domains.Count -eq 0) {
        $domains = Invoke-GraphGetAllPages -Uri 'https://graph.microsoft.com/v1.0/domains'
    }

    $initial = $domains | Where-Object { $_.name -like '*.onmicrosoft.com' -and ($_.isInitial -eq $true -or $_.isDefault -eq $true) } | Select-Object -First 1
    if (-not $initial) {
        $initial = $domains | Where-Object { $_.name -like '*.onmicrosoft.com' } | Sort-Object name | Select-Object -First 1
    }
    if (-not $initial) {
        throw 'Kunne ikke finde tenantens *.onmicrosoft.com domæne.'
    }
    return ([string] $initial.name).ToLowerInvariant()
}

function New-RandomStrongPassword {
    [CmdletBinding()]
    param()

    $lower = 'abcdefghijkmnopqrstuvwxyz'
    $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $digits = '23456789'
    $symbols = '!@#$%&*_-+=?'
    $all = ($lower + $upper + $digits + $symbols).ToCharArray()
    $chars = New-Object System.Collections.Generic.List[char]
    $chars.Add($lower[(Get-Random -Minimum 0 -Maximum $lower.Length)]) | Out-Null
    $chars.Add($upper[(Get-Random -Minimum 0 -Maximum $upper.Length)]) | Out-Null
    $chars.Add($digits[(Get-Random -Minimum 0 -Maximum $digits.Length)]) | Out-Null
    $chars.Add($symbols[(Get-Random -Minimum 0 -Maximum $symbols.Length)]) | Out-Null
    1..28 | ForEach-Object { $chars.Add($all[(Get-Random -Minimum 0 -Maximum $all.Length)]) | Out-Null }
    return -join ($chars | Sort-Object { Get-Random })
}

function ConvertTo-BreakGlassUpn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Prefix,
        [Parameter(Mandatory)][string] $OnMicrosoftDomain
    )

    $trimmed = $Prefix.Trim()
    if ($trimmed -match '@') {
        $trimmed = ($trimmed -split '@', 2)[0]
    }
    if ($trimmed -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{1,62}$') {
        throw "UPN prefix '$Prefix' er ikke gyldigt."
    }
    return ('{0}@{1}' -f $trimmed.ToLowerInvariant(), $OnMicrosoftDomain.ToLowerInvariant())
}

function Get-BreakGlassUser {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $UserPrincipalName)

    if ($script:State.Mock) {
        return $null
    }

    try {
        return Invoke-GraphRequestSafe -Method GET -Uri ("https://graph.microsoft.com/v1.0/users/{0}?`$select=id,displayName,userPrincipalName,accountEnabled" -f [uri]::EscapeDataString($UserPrincipalName))
    }
    catch {
        if ((ConvertTo-RedactedError $_) -match 'Request_ResourceNotFound|does not exist|ResourceNotFound|404') {
            return $null
        }
        throw
    }
}

function New-BreakGlassUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $UserPrincipalName,
        [Parameter(Mandatory)][string] $DisplayName
    )

    $password = New-RandomStrongPassword
    $mailNickname = (($UserPrincipalName -split '@', 2)[0] -replace '[^a-zA-Z0-9]', '')
    $body = @{
        accountEnabled    = $true
        displayName       = $DisplayName
        mailNickname      = $mailNickname
        userPrincipalName = $UserPrincipalName
        passwordProfile   = @{
            forceChangePasswordNextSignIn = $true
            password                      = $password
        }
    }

    Invoke-GraphRequestSafe -Method POST -Uri 'https://graph.microsoft.com/v1.0/users' -Body $body | Out-Null
    $script:State.CreatedPasswords.Add([pscustomobject]@{
        UserPrincipalName = $UserPrincipalName
        Password          = $password
    }) | Out-Null
    Write-AppLog -Message "Bruger oprettet: $UserPrincipalName. Midlertidig adgangskode vises kun i sikker dialog."
    return Get-BreakGlassUser -UserPrincipalName $UserPrincipalName
}

function Show-CreatedPasswordsOnce {
    [CmdletBinding()]
    param()

    if ($script:State.CreatedPasswords.Count -eq 0) {
        return
    }

    $lines = @(
        'Midlertidige adgangskoder vises kun her. De er ikke skrevet til log eller rapport.',
        'Flyt dem straks til godkendt password manager eller nødprocedure.',
        ''
    )
    foreach ($item in $script:State.CreatedPasswords) {
        $lines += ('{0}: {1}' -f $item.UserPrincipalName, $item.Password)
    }
    Show-AppMessage -Message ($lines -join [Environment]::NewLine) -Title "$($script:AppName) - midlertidige adgangskoder" -Buttons 'OK' -Icon 'Warning' | Out-Null
}

function Ensure-BreakGlassUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Prefix,
        [Parameter(Mandatory)][string] $DisplayName,
        [Parameter(Mandatory)][string] $OnMicrosoftDomain,
        [Parameter(Mandatory)][bool] $Apply
    )

    $upn = ConvertTo-BreakGlassUpn -Prefix $Prefix -OnMicrosoftDomain $OnMicrosoftDomain

    if ($script:State.Mock) {
        return [pscustomobject]@{ id = "mock-user-$Prefix"; userPrincipalName = $upn; displayName = $DisplayName; accountEnabled = $true; Action = 'MockValidated' }
    }

    $existing = Get-BreakGlassUser -UserPrincipalName $upn
    if ($existing) {
        Write-AppLog -Level PASS -Message "Bruger findes: $upn"
        if ($existing.accountEnabled -ne $true) {
            Write-AppLog -Level WARN -Message "Brugeren findes men er ikke enabled: $upn"
        }
        return $existing
    }

    if (-not $Apply) {
        Write-AppLog -Level PLAN -Message "Plan: opret bruger $upn"
        return [pscustomobject]@{ id = "planned-user-$Prefix"; userPrincipalName = $upn; displayName = $DisplayName; accountEnabled = $true; Planned = $true }
    }

    return New-BreakGlassUser -UserPrincipalName $upn -DisplayName $DisplayName
}

function Get-BreakGlassGroup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $DisplayName)

    if ($script:State.Mock) {
        return $null
    }
    $filter = [uri]::EscapeDataString("displayName eq '$($DisplayName.Replace("'", "''"))'")
    return Invoke-GraphGetAllPages -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=$filter&`$select=id,displayName,securityEnabled,mailEnabled,isAssignableToRole,groupTypes" | Select-Object -First 1
}

function New-BreakGlassRoleAssignableGroup {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $DisplayName)

    $mailNickname = ($DisplayName -replace '[^a-zA-Z0-9]', '')
    $body = @{
        displayName        = $DisplayName
        mailEnabled        = $false
        mailNickname       = $mailNickname
        securityEnabled    = $true
        isAssignableToRole = $true
        groupTypes         = @()
    }
    Invoke-GraphRequestSafe -Method POST -Uri 'https://graph.microsoft.com/v1.0/groups' -Body $body | Out-Null
    return Get-BreakGlassGroup -DisplayName $DisplayName
}

function Ensure-BreakGlassGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $DisplayName,
        [Parameter(Mandatory)][bool] $Apply
    )

    if ($script:State.Mock) {
        return [pscustomobject]@{ id = 'mock-bg-group'; displayName = $DisplayName; isAssignableToRole = $true; securityEnabled = $true; mailEnabled = $false }
    }

    $group = Get-BreakGlassGroup -DisplayName $DisplayName
    if ($group) {
        Write-AppLog -Level PASS -Message "Gruppe findes: $DisplayName"
        if ($group.isAssignableToRole -ne $true) {
            Write-AppLog -Level WARN -Message "Gruppen findes, men isAssignableToRole er ikke true. Ny rolle-assignable gruppe kan være nødvendig."
        }
        return $group
    }

    if (-not $Apply) {
        Write-AppLog -Level PLAN -Message "Plan: opret rolle-assignable gruppe $DisplayName"
        return [pscustomobject]@{ id = 'planned-bg-group'; displayName = $DisplayName; isAssignableToRole = $true; securityEnabled = $true; mailEnabled = $false; Planned = $true }
    }

    return New-BreakGlassRoleAssignableGroup -DisplayName $DisplayName
}

function Ensure-GroupMember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Group,
        [Parameter(Mandatory)] $User,
        [Parameter(Mandatory)][bool] $Apply
    )

    $groupId = [string] $Group.id
    $userId = [string] $User.id
    $userUpn = [string] $User.userPrincipalName
    if ($groupId -like 'planned-*' -or $userId -like 'planned-*' -or $script:State.Mock) {
        Write-AppLog -Level PLAN -Message "Plan/mock: sikr medlemskab $userUpn i $($Group.displayName)"
        return [pscustomobject]@{ User = $userUpn; Group = $Group.displayName; Status = 'PlannedOrMock' }
    }

    $members = Invoke-GraphGetAllPages -Uri "https://graph.microsoft.com/v1.0/groups/$groupId/members?`$select=id"
    if (@($members | Where-Object { $_.id -eq $userId }).Count -gt 0) {
        Write-AppLog -Level PASS -Message "$userUpn er allerede medlem af $($Group.displayName)."
        return [pscustomobject]@{ User = $userUpn; Group = $Group.displayName; Status = 'AlreadyMember' }
    }

    if (-not $Apply) {
        Write-AppLog -Level PLAN -Message "Plan: tilføj $userUpn til $($Group.displayName)"
        return [pscustomobject]@{ User = $userUpn; Group = $Group.displayName; Status = 'Planned' }
    }

    $body = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$userId" }
    Invoke-GraphRequestSafe -Method POST -Uri "https://graph.microsoft.com/v1.0/groups/$groupId/members/`$ref" -Body $body | Out-Null
    Write-AppLog -Level PASS -Message "$userUpn tilføjet til $($Group.displayName)."
    return [pscustomobject]@{ User = $userUpn; Group = $Group.displayName; Status = 'Added' }
}

function Get-GlobalAdministratorRoleDefinition {
    [CmdletBinding()]
    param()

    if ($script:State.Mock) {
        return [pscustomobject]@{ id = 'mock-ga-role-definition'; displayName = 'Global Administrator' }
    }
    $filter = [uri]::EscapeDataString("displayName eq 'Global Administrator'")
    return Invoke-GraphGetAllPages -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions?`$filter=$filter" | Select-Object -First 1
}

function Ensure-DirectGlobalAdminAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $User,
        [Parameter(Mandatory)][bool] $Apply
    )

    $role = Get-GlobalAdministratorRoleDefinition
    if (-not $role) {
        throw 'Global Administrator rolledefinition blev ikke fundet.'
    }

    if ($script:State.Mock -or $User.id -like 'planned-*') {
        Write-AppLog -Level PLAN -Message "Plan/mock: direkte Global Administrator til $($User.userPrincipalName)"
        return [pscustomobject]@{ User = $User.userPrincipalName; Role = 'Global Administrator'; Status = 'PlannedOrMock'; AssignmentId = '' }
    }

    $filter = [uri]::EscapeDataString("principalId eq '$($User.id)' and roleDefinitionId eq '$($role.id)'")
    $existing = Invoke-GraphGetAllPages -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$filter=$filter" | Select-Object -First 1
    if ($existing) {
        Write-AppLog -Level PASS -Message "$($User.userPrincipalName) har allerede direkte Global Administrator."
        return [pscustomobject]@{ User = $User.userPrincipalName; Role = 'Global Administrator'; Status = 'AlreadyAssigned'; AssignmentId = $existing.id }
    }

    if (-not $Apply) {
        Write-AppLog -Level PLAN -Message "Plan: tildel direkte Global Administrator til $($User.userPrincipalName)"
        return [pscustomobject]@{ User = $User.userPrincipalName; Role = 'Global Administrator'; Status = 'Planned'; AssignmentId = '' }
    }

    $body = @{
        principalId      = $User.id
        roleDefinitionId = $role.id
        directoryScopeId = '/'
    }
    $assignment = Invoke-GraphRequestSafe -Method POST -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments' -Body $body
    Write-AppLog -Level PASS -Message "Direkte Global Administrator tildelt til $($User.userPrincipalName)."
    return [pscustomobject]@{ User = $User.userPrincipalName; Role = 'Global Administrator'; Status = 'Assigned'; AssignmentId = $assignment.id }
}

function Get-RestrictedManagementAdministrativeUnit {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $DisplayName)

    if ($script:State.Mock) { return $null }
    $filter = [uri]::EscapeDataString("displayName eq '$($DisplayName.Replace("'", "''"))'")
    return Invoke-GraphGetAllPages -Uri "https://graph.microsoft.com/beta/directory/administrativeUnits?`$filter=$filter" | Select-Object -First 1
}

function New-RestrictedManagementAdministrativeUnit {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $DisplayName)

    $body = @{
        displayName                  = $DisplayName
        description                  = 'Restricted administrative unit for break-glass account and group protection.'
        isMemberManagementRestricted = $true
    }
    Invoke-GraphRequestSafe -Method POST -Uri 'https://graph.microsoft.com/beta/directory/administrativeUnits' -Body $body | Out-Null
    return Get-RestrictedManagementAdministrativeUnit -DisplayName $DisplayName
}

function Ensure-RestrictedManagementAdministrativeUnit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $DisplayName,
        [Parameter(Mandatory)][bool] $Apply
    )

    if ($script:State.Mock) {
        return [pscustomobject]@{ id = 'mock-rmau'; displayName = $DisplayName; isMemberManagementRestricted = $true }
    }

    $unit = Get-RestrictedManagementAdministrativeUnit -DisplayName $DisplayName
    if ($unit) {
        Write-AppLog -Level PASS -Message "RMAU findes: $DisplayName"
        return $unit
    }
    if (-not $Apply) {
        Write-AppLog -Level PLAN -Message "Plan: opret RMAU $DisplayName"
        return [pscustomobject]@{ id = 'planned-rmau'; displayName = $DisplayName; isMemberManagementRestricted = $true; Planned = $true }
    }
    return New-RestrictedManagementAdministrativeUnit -DisplayName $DisplayName
}

function Ensure-RmauMember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $AdministrativeUnit,
        [Parameter(Mandatory)] $DirectoryObject,
        [Parameter(Mandatory)][bool] $Apply
    )

    $auId = [string] $AdministrativeUnit.id
    $objectId = [string] $DirectoryObject.id
    if ($script:State.Mock -or $auId -like 'planned-*' -or $objectId -like 'planned-*') {
        Write-AppLog -Level PLAN -Message "Plan/mock: tilføj objekt $objectId til RMAU $($AdministrativeUnit.displayName)"
        return [pscustomobject]@{ ObjectId = $objectId; Status = 'PlannedOrMock' }
    }

    try {
        $members = Invoke-GraphGetAllPages -Uri "https://graph.microsoft.com/beta/directory/administrativeUnits/$auId/members?`$select=id"
        if (@($members | Where-Object { $_.id -eq $objectId }).Count -gt 0) {
            Write-AppLog -Level PASS -Message "Objekt $objectId er allerede medlem af RMAU."
            return [pscustomobject]@{ ObjectId = $objectId; Status = 'AlreadyMember' }
        }
        if (-not $Apply) {
            Write-AppLog -Level PLAN -Message "Plan: tilføj objekt $objectId til RMAU."
            return [pscustomobject]@{ ObjectId = $objectId; Status = 'Planned' }
        }
        $body = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$objectId" }
        Invoke-GraphRequestSafe -Method POST -Uri "https://graph.microsoft.com/beta/directory/administrativeUnits/$auId/members/`$ref" -Body $body | Out-Null
        Write-AppLog -Level PASS -Message "Objekt $objectId tilføjet til RMAU."
        return [pscustomobject]@{ ObjectId = $objectId; Status = 'Added' }
    }
    catch {
        Write-SafeError -Message 'RMAU medlemskab kunne ikke sættes.' -ErrorRecord $_
        return [pscustomobject]@{ ObjectId = $objectId; Status = 'Warning'; Message = ConvertTo-RedactedError $_ }
    }
}

function Validate-AaguidList {
    [CmdletBinding()]
    param([string] $Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }
    $values = @($Text -split '[,;`\r`\n ]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach ($value in $values) {
        if ($value -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
            throw "AAGUID '$value' er ikke en gyldig GUID."
        }
    }
    return $values
}

function Get-AuthenticationStrengthPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $DisplayName)

    if ($script:State.Mock) { return $null }
    $filter = [uri]::EscapeDataString("displayName eq '$($DisplayName.Replace("'", "''"))'")
    return Invoke-GraphGetAllPages -Uri "https://graph.microsoft.com/beta/identity/conditionalAccess/authenticationStrength/policies?`$filter=$filter" | Select-Object -First 1
}

function New-BreakGlassAuthenticationStrengthPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $DisplayName,
        [string[]] $AllowedAaguids = @()
    )

    $body = @{
        displayName         = $DisplayName
        description         = 'Break-glass authentication strength requiring FIDO2.'
        policyType          = 'custom'
        requirementsSatisfied = 'mfa'
        allowedCombinations = @('fido2')
    }
    if ($AllowedAaguids.Count -gt 0) {
        $body.combinationConfigurations = @(
            @{
                '@odata.type'  = '#microsoft.graph.fido2CombinationConfiguration'
                appliesToCombinations = @('fido2')
                allowedAAGUIDs = $AllowedAaguids
            }
        )
    }
    return Invoke-GraphRequestSafe -Method POST -Uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/authenticationStrength/policies' -Body $body
}

function Ensure-BreakGlassAuthenticationStrengthPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $DisplayName,
        [string[]] $AllowedAaguids = @(),
        [Parameter(Mandatory)][bool] $Apply
    )

    if ($script:State.Mock) {
        return [pscustomobject]@{ id = 'mock-auth-strength'; displayName = $DisplayName; allowedCombinations = @('fido2') }
    }

    $existing = Get-AuthenticationStrengthPolicy -DisplayName $DisplayName
    if ($existing) {
        Write-AppLog -Level PASS -Message "Authentication strength findes: $DisplayName"
        return $existing
    }
    if (-not $Apply) {
        Write-AppLog -Level PLAN -Message "Plan: opret authentication strength $DisplayName"
        return [pscustomobject]@{ id = 'planned-auth-strength'; displayName = $DisplayName; allowedCombinations = @('fido2') }
    }
    return New-BreakGlassAuthenticationStrengthPolicy -DisplayName $DisplayName -AllowedAaguids $AllowedAaguids
}

function Get-ConditionalAccessPolicyByName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $DisplayName)

    if ($script:State.Mock) { return $null }
    $filter = [uri]::EscapeDataString("displayName eq '$($DisplayName.Replace("'", "''"))'")
    return Invoke-GraphGetAllPages -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies?`$filter=$filter" | Select-Object -First 1
}

function Backup-ConditionalAccessPolicies {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $OutputFolder)

    $backupPath = Join-Path -Path $OutputFolder -ChildPath 'ca-backup-before.json'
    if ($script:State.Mock) {
        Export-JsonSafe -InputObject @() -Path $backupPath | Out-Null
        return $backupPath
    }

    $policies = Invoke-GraphGetAllPages -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies'
    Export-JsonSafe -InputObject $policies -Path $backupPath | Out-Null
    $script:State['CaBackupFiles'] += $backupPath
    Write-AppLog -Message "Conditional Access backup gemt: $backupPath"
    return $backupPath
}

function New-BreakGlassConditionalAccessPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $DisplayName,
        [Parameter(Mandatory)][string] $GroupId,
        [Parameter(Mandatory)][string] $AuthenticationStrengthId,
        [Parameter(Mandatory)][string] $State
    )

    $body = @{
        displayName = $DisplayName
        state       = $State
        conditions  = @{
            users = @{
                includeGroups = @($GroupId)
                excludeGroups = @()
            }
            applications = @{
                includeApplications = @('All')
            }
            clientAppTypes = @('all')
        }
        grantControls = @{
            operator = 'AND'
            authenticationStrength = @{
                id = $AuthenticationStrengthId
            }
        }
    }
    return Invoke-GraphRequestSafe -Method POST -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies' -Body $body
}

function Ensure-BreakGlassConditionalAccessPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $DisplayName,
        [Parameter(Mandatory)][string] $GroupId,
        [Parameter(Mandatory)][string] $AuthenticationStrengthId,
        [Parameter(Mandatory)][string] $State,
        [Parameter(Mandatory)][bool] $Apply
    )

    if ($script:State.Mock) {
        return [pscustomobject]@{ id = 'mock-ca-policy'; displayName = $DisplayName; state = $State }
    }

    $existing = Get-ConditionalAccessPolicyByName -DisplayName $DisplayName
    if ($existing) {
        Write-AppLog -Level PASS -Message "Dedikeret CA policy findes: $DisplayName"
        return $existing
    }
    if (-not $Apply) {
        Write-AppLog -Level PLAN -Message "Plan: opret CA policy $DisplayName i state $State"
        return [pscustomobject]@{ id = 'planned-ca-policy'; displayName = $DisplayName; state = $State }
    }
    return New-BreakGlassConditionalAccessPolicy -DisplayName $DisplayName -GroupId $GroupId -AuthenticationStrengthId $AuthenticationStrengthId -State $State
}

function Add-BreakGlassGroupExclusionToExistingCAPolicies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $GroupId,
        [Parameter(Mandatory)][string] $DedicatedPolicyName,
        [Parameter(Mandatory)][bool] $Apply,
        [Parameter(Mandatory)][string] $OutputFolder
    )

    if ($script:State.Mock) {
        return @([pscustomobject]@{ Policy = 'Mock existing CA'; Status = 'PlannedOrMock' })
    }

    $backup = Backup-ConditionalAccessPolicies -OutputFolder $OutputFolder
    $policies = Invoke-GraphGetAllPages -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies'
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($policy in $policies) {
        if ($policy.displayName -eq $DedicatedPolicyName) {
            continue
        }
        $excludeGroups = @()
        if ($policy.conditions -and $policy.conditions.users -and $policy.conditions.users.excludeGroups) {
            $excludeGroups = @($policy.conditions.users.excludeGroups)
        }
        if ($excludeGroups -contains $GroupId) {
            $results.Add([pscustomobject]@{ Policy = $policy.displayName; Status = 'AlreadyExcluded'; Backup = $backup }) | Out-Null
            continue
        }

        if (-not $Apply) {
            $results.Add([pscustomobject]@{ Policy = $policy.displayName; Status = 'Planned'; Backup = $backup }) | Out-Null
            continue
        }

        try {
            $policy.conditions.users.excludeGroups = @($excludeGroups + $GroupId | Select-Object -Unique)
            $body = @{
                conditions = $policy.conditions
            }
            Invoke-GraphRequestSafe -Method PATCH -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$($policy.id)" -Body $body | Out-Null
            $results.Add([pscustomobject]@{ Policy = $policy.displayName; Status = 'Updated'; Backup = $backup }) | Out-Null
        }
        catch {
            Write-SafeError -Message "Kunne ikke patche CA policy '$($policy.displayName)'." -ErrorRecord $_
            $results.Add([pscustomobject]@{ Policy = $policy.displayName; Status = 'Warning'; Backup = $backup }) | Out-Null
        }
    }
    return @($results)
}

function Get-UserFido2Methods {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $User)

    if ($script:State.Mock) {
        return @([pscustomobject]@{ id = 'mock-fido2-method'; displayName = 'Mock FIDO2 key'; model = 'Mock' })
    }
    try {
        return Invoke-GraphGetAllPages -Uri "https://graph.microsoft.com/v1.0/users/$($User.id)/authentication/fido2Methods"
    }
    catch {
        Write-SafeError -Message "Kunne ikke læse FIDO2 methods for $($User.userPrincipalName)." -ErrorRecord $_
        return @()
    }
}

function Test-BreakGlassFido2Registration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]] $Users)

    foreach ($user in $Users) {
        $methods = @(Get-UserFido2Methods -User $user)
        [pscustomobject]@{
            UserPrincipalName = $user.userPrincipalName
            HasFido2          = ($methods.Count -gt 0)
            Count             = $methods.Count
            Metadata          = @($methods | Select-Object id,displayName,model,createdDateTime)
        }
    }
}

function Get-OrCreate-ResourceGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Location,
        [Parameter(Mandatory)][bool] $Apply
    )

    if ($script:State.Mock) { return [pscustomobject]@{ ResourceGroupName = $Name; Location = $Location; ResourceId = "/mock/resourceGroups/$Name" } }
    $rg = Get-AzResourceGroup -Name $Name -ErrorAction SilentlyContinue
    if ($rg) { return $rg }
    if (-not $Apply) { Write-AppLog -Level PLAN -Message "Plan: opret resource group $Name"; return [pscustomobject]@{ ResourceGroupName = $Name; Location = $Location; Planned = $true } }
    return New-AzResourceGroup -Name $Name -Location $Location -ErrorAction Stop
}

function Get-OrCreate-LogAnalyticsWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $ResourceGroupName,
        [Parameter(Mandatory)][string] $WorkspaceName,
        [Parameter(Mandatory)][string] $Location,
        [Parameter(Mandatory)][bool] $Apply
    )

    if ($script:State.Mock) { return [pscustomobject]@{ Name = $WorkspaceName; ResourceId = "/mock/workspaces/$WorkspaceName"; CustomerId = 'mock-workspace-id' } }
    $workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName -ErrorAction SilentlyContinue
    if ($workspace) { return $workspace }
    if (-not $Apply) { Write-AppLog -Level PLAN -Message "Plan: opret Log Analytics workspace $WorkspaceName"; return [pscustomobject]@{ Name = $WorkspaceName; ResourceId = "/planned/workspaces/$WorkspaceName"; Planned = $true } }
    return New-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName -Location $Location -Sku PerGB2018 -ErrorAction Stop
}

function Ensure-EntraDiagnosticSettingToLogAnalytics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $DiagnosticSettingName,
        [Parameter(Mandatory)][string] $WorkspaceResourceId,
        [Parameter(Mandatory)][bool] $Apply
    )

    if ($script:State.Mock) { return [pscustomobject]@{ Name = $DiagnosticSettingName; Status = 'MockValidated' } }
    if (-not $Apply) {
        Write-AppLog -Level PLAN -Message "Plan: opret/opdater Entra diagnostic setting $DiagnosticSettingName"
        return [pscustomobject]@{ Name = $DiagnosticSettingName; Status = 'Planned' }
    }

    $body = @{
        properties = @{
            workspaceId = $WorkspaceResourceId
            logs = @(
                @{ category = 'SigninLogs'; enabled = $true },
                @{ category = 'AuditLogs'; enabled = $true }
            )
        }
    } | ConvertTo-Json -Depth 20

    $path = "/providers/microsoft.aadiam/diagnosticSettings/$DiagnosticSettingName?api-version=2017-04-01-preview"
    try {
        Invoke-AzRestMethod -Method PUT -Path $path -Payload $body -ErrorAction Stop | Out-Null
        return [pscustomobject]@{ Name = $DiagnosticSettingName; Status = 'Configured' }
    }
    catch {
        Write-SafeError -Message 'Diagnostic setting kunne ikke konfigureres.' -ErrorRecord $_
        return [pscustomobject]@{ Name = $DiagnosticSettingName; Status = 'Warning'; Message = ConvertTo-RedactedError $_ }
    }
}

function Get-OrCreate-ActionGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $SubscriptionId,
        [Parameter(Mandatory)][string] $ResourceGroupName,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Location,
        [string[]] $EmailRecipients = @(),
        [Parameter(Mandatory)][bool] $Apply
    )

    $resourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Insights/actionGroups/$Name"
    if ($script:State.Mock -or -not $Apply) {
        Write-AppLog -Level PLAN -Message "Plan/mock: action group $Name"
        return [pscustomobject]@{ Name = $Name; Id = $resourceId; Status = if ($script:State.Mock) { 'MockValidated' } else { 'Planned' } }
    }

    $receivers = @()
    $index = 1
    foreach ($email in $EmailRecipients) {
        if (-not [string]::IsNullOrWhiteSpace($email)) {
            $receivers += @{ name = "email$index"; emailAddress = $email.Trim(); useCommonAlertSchema = $true }
            $index++
        }
    }

    $body = @{
        location   = 'Global'
        properties = @{
            groupShortName = ($Name.Substring(0, [Math]::Min($Name.Length, 12)))
            enabled        = $true
            emailReceivers = $receivers
        }
    } | ConvertTo-Json -Depth 20
    $path = "$resourceId?api-version=2022-06-01"
    Invoke-AzRestMethod -Method PUT -Path $path -Payload $body -ErrorAction Stop | Out-Null
    return [pscustomobject]@{ Name = $Name; Id = $resourceId; Status = 'Configured' }
}

function New-BreakGlassSignInKql {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]] $UserPrincipalNames)

    $quoted = ($UserPrincipalNames | ForEach-Object { '"' + $_.ToLowerInvariant() + '"' }) -join ','
    return @"
let BreakGlassUsers = dynamic([$quoted]);
SigninLogs
| where UserPrincipalName in~ (BreakGlassUsers)
| summarize SignInAttempts = count() by bin(TimeGenerated, 5m)
| where SignInAttempts > 0
"@
}

function New-BreakGlassAuditKql {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]] $UserPrincipalNames,
        [string[]] $ObjectIds = @()
    )

    $quotedUsers = ($UserPrincipalNames | ForEach-Object { '"' + $_.ToLowerInvariant() + '"' }) -join ','
    $quotedIds = ($ObjectIds | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { '"' + $_ + '"' }) -join ','
    return @"
let BreakGlassUsers = dynamic([$quotedUsers]);
let BreakGlassObjectIds = dynamic([$quotedIds]);
AuditLogs
| where tostring(TargetResources) has_any (BreakGlassUsers) or tostring(TargetResources) has_any (BreakGlassObjectIds)
| project TimeGenerated, OperationName, Category, Result, InitiatedBy, TargetResources, CorrelationId
"@
}

function Ensure-ScheduledQueryRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $SubscriptionId,
        [Parameter(Mandatory)][string] $ResourceGroupName,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Location,
        [Parameter(Mandatory)][string] $WorkspaceResourceId,
        [Parameter(Mandatory)][string] $Query,
        [Parameter(Mandatory)][string] $ActionGroupId,
        [Parameter(Mandatory)][bool] $Apply
    )

    $resourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Insights/scheduledQueryRules/$Name"
    if ($script:State.Mock -or -not $Apply) {
        Write-AppLog -Level PLAN -Message "Plan/mock: scheduled query rule $Name"
        return [pscustomobject]@{ Name = $Name; Id = $resourceId; Status = if ($script:State.Mock) { 'MockValidated' } else { 'Planned' }; Query = $Query }
    }

    $body = @{
        location   = $Location
        properties = @{
            enabled            = $true
            scopes             = @($WorkspaceResourceId)
            evaluationFrequency = 'PT5M'
            windowSize         = 'PT5M'
            severity           = 1
            criteria           = @{
                allOf = @(
                    @{
                        query              = $Query
                        timeAggregation    = 'Count'
                        operator           = 'GreaterThan'
                        threshold          = 0
                        failingPeriods     = @{
                            numberOfEvaluationPeriods = 1
                            minFailingPeriodsToAlert  = 1
                        }
                    }
                )
            }
            actions = @{
                actionGroups = @($ActionGroupId)
            }
        }
    } | ConvertTo-Json -Depth 30
    Invoke-AzRestMethod -Method PUT -Path "$resourceId?api-version=2021-08-01" -Payload $body -ErrorAction Stop | Out-Null
    return [pscustomobject]@{ Name = $Name; Id = $resourceId; Status = 'Configured'; Query = $Query }
}

function Test-RequiredModulesPrecheck {
    [CmdletBinding()]
    param()

    if ($script:State.Mock) {
        foreach ($module in $script:RequiredModules) {
            [pscustomobject]@{
                Check  = "Modul: $module"
                Status = 'Skipped'
                Detail = 'Mock mode'
            }
        }
        return
    }

    Test-RequiredModules | ForEach-Object {
        [pscustomobject]@{
            Check  = "Modul: $($_.Name)"
            Status = if ($_.Present) { 'Passed' } else { 'Failed' }
            Detail = if ($_.Present) { $_.Version } else { 'Mangler' }
        }
    }
}

function Invoke-PreCheck {
    [CmdletBinding()]
    param([hashtable] $Config)

    $results = New-Object System.Collections.Generic.List[object]
    $results.Add([pscustomobject]@{ Check = 'Windows PowerShell'; Status = if ($PSVersionTable.PSVersion.Major -ge 5) { 'Passed' } else { 'Failed' }; Detail = [string] $PSVersionTable.PSVersion }) | Out-Null
    $results.Add([pscustomobject]@{ Check = 'STA mode'; Status = if (Test-StaMode) { 'Passed' } else { 'Failed' }; Detail = [System.Threading.Thread]::CurrentThread.GetApartmentState() }) | Out-Null
    foreach ($item in Test-RequiredModulesPrecheck) { $results.Add($item) | Out-Null }
    $results.Add([pscustomobject]@{ Check = 'Microsoft Graph forbindelse'; Status = if ($script:State.GraphConnected) { 'Passed' } else { 'Failed' }; Detail = $script:State.GraphAccount }) | Out-Null
    $results.Add([pscustomobject]@{ Check = 'Azure forbindelse'; Status = if ($Config.DisableMonitoring -or $script:State.AzureConnected) { if ($Config.DisableMonitoring) { 'Skipped' } else { 'Passed' } } else { 'Warning' }; Detail = $script:State.AzureSubscriptionName }) | Out-Null
    $results.Add([pscustomobject]@{ Check = 'onmicrosoft.com domæne'; Status = if (-not [string]::IsNullOrWhiteSpace($script:State.OnMicrosoftDomain)) { 'Passed' } else { 'Failed' }; Detail = $script:State.OnMicrosoftDomain }) | Out-Null
    foreach ($scope in Test-GraphScopes) {
        $results.Add([pscustomobject]@{ Check = "Graph scope: $($scope.Scope)"; Status = $scope.Status; Detail = if ($scope.Present) { 'Granted' } else { 'Mangler eller kan ikke detekteres' } }) | Out-Null
    }
    return @($results)
}

function New-Plan {
    [CmdletBinding()]
    param([hashtable] $Config)

    $domain = if ($script:State.OnMicrosoftDomain) { $script:State.OnMicrosoftDomain } else { '<detected-domain>' }
    $upn1 = ConvertTo-BreakGlassUpn -Prefix $Config.UserPrefix1 -OnMicrosoftDomain $domain
    $upn2 = ConvertTo-BreakGlassUpn -Prefix $Config.UserPrefix2 -OnMicrosoftDomain $domain
    $aaguids = Validate-AaguidList -Text $Config.AllowedAaguids
    $plan = [ordered]@{
        Version               = $script:AppVersion
        Timestamp             = (Get-Date).ToString('o')
        Mock                  = $script:State.Mock
        NoApply               = [bool] $Config.NoApply
        TenantId              = $script:State.TenantId
        OnMicrosoftDomain     = $domain
        Users                 = @(
            @{ Prefix = $Config.UserPrefix1; UPN = $upn1; DisplayName = $Config.DisplayName1 },
            @{ Prefix = $Config.UserPrefix2; UPN = $upn2; DisplayName = $Config.DisplayName2 }
        )
        Group                 = $Config.GroupDisplayName
        RMAU                  = $Config.RmauDisplayName
        AuthenticationStrength = @{
            DisplayName = $Config.AuthStrengthName
            AllowedAaguids = $aaguids
        }
        ConditionalAccess     = @{
            PolicyName = $Config.CaPolicyName
            State      = $Config.CaState
            PatchExistingPolicies = [bool] $Config.ExcludeFromExistingCa
        }
        Monitoring            = @{
            Enabled = -not [bool] $Config.DisableMonitoring
            ResourceGroupName = $Config.ResourceGroupName
            WorkspaceName = $Config.WorkspaceName
            Location = $Config.AzureRegion
            DiagnosticSettingName = $Config.DiagnosticSettingName
            ActionGroupName = $Config.ActionGroupName
            AlertEmails = $Config.AlertEmails
            CreateSignInAlert = [bool] $Config.CreateSignInAlert
            CreateAuditAlert = [bool] $Config.CreateAuditAlert
        }
        PlannedActions        = @(
            "Validate or create users $upn1 and $upn2",
            "Validate or create role-assignable group $($Config.GroupDisplayName)",
            'Ensure direct permanent Global Administrator assignments',
            "Validate or create restricted management administrative unit $($Config.RmauDisplayName)",
            "Validate or create authentication strength $($Config.AuthStrengthName)",
            "Validate or create Conditional Access policy $($Config.CaPolicyName)",
            'Configure Log Analytics diagnostic settings and Azure Monitor alerts if enabled'
        )
    }
    $script:State['Plan'] = $plan
    return $plan
}

function Invoke-BreakGlassConfiguration {
    [CmdletBinding()]
    param([hashtable] $Config)

    $apply = -not [bool] $Config.NoApply
    $tenantId = if ($script:State.TenantId) { $script:State.TenantId } else { 'UnknownTenant' }
    $output = New-OutputFolder -TenantId $tenantId
    $plan = New-Plan -Config $Config
    Export-JsonSafe -InputObject $plan -Path (Join-Path $output 'plan.json') | Out-Null

    Write-AppLog -Message "Starter konfiguration. Apply: $apply"
    $tenant = Get-TenantInfo
    $domain = $tenant.OnMicrosoftDomain
    $users = @()
    $users += Ensure-BreakGlassUser -Prefix $Config.UserPrefix1 -DisplayName $Config.DisplayName1 -OnMicrosoftDomain $domain -Apply $apply
    $users += Ensure-BreakGlassUser -Prefix $Config.UserPrefix2 -DisplayName $Config.DisplayName2 -OnMicrosoftDomain $domain -Apply $apply

    $group = Ensure-BreakGlassGroup -DisplayName $Config.GroupDisplayName -Apply $apply
    $membership = foreach ($user in $users) { Ensure-GroupMember -Group $group -User $user -Apply $apply }
    $roleAssignments = foreach ($user in $users) { Ensure-DirectGlobalAdminAssignment -User $user -Apply $apply }
    $rmau = Ensure-RestrictedManagementAdministrativeUnit -DisplayName $Config.RmauDisplayName -Apply $apply
    $rmauMembership = @()
    foreach ($user in $users) { $rmauMembership += Ensure-RmauMember -AdministrativeUnit $rmau -DirectoryObject $user -Apply $apply }
    $rmauMembership += Ensure-RmauMember -AdministrativeUnit $rmau -DirectoryObject $group -Apply $apply

    $aaguids = Validate-AaguidList -Text $Config.AllowedAaguids
    $authStrength = Ensure-BreakGlassAuthenticationStrengthPolicy -DisplayName $Config.AuthStrengthName -AllowedAaguids $aaguids -Apply $apply
    $caPolicy = Ensure-BreakGlassConditionalAccessPolicy -DisplayName $Config.CaPolicyName -GroupId $group.id -AuthenticationStrengthId $authStrength.id -State $Config.CaState -Apply $apply
    $existingCaExclusionResults = @()
    if ($Config.ExcludeFromExistingCa) {
        $existingCaExclusionResults = Add-BreakGlassGroupExclusionToExistingCAPolicies -GroupId $group.id -DedicatedPolicyName $Config.CaPolicyName -Apply $apply -OutputFolder $output
    }

    $monitoring = [pscustomobject]@{ Enabled = -not [bool]$Config.DisableMonitoring; Entries = @() }
    if (-not [bool] $Config.DisableMonitoring) {
        try {
            Get-OrSelectSubscription -SubscriptionId $Config.SubscriptionId | Out-Null
            $subscriptionId = $script:State.AzureSubscriptionId
            $rg = Get-OrCreate-ResourceGroup -Name $Config.ResourceGroupName -Location $Config.AzureRegion -Apply $apply
            $workspace = Get-OrCreate-LogAnalyticsWorkspace -ResourceGroupName $Config.ResourceGroupName -WorkspaceName $Config.WorkspaceName -Location $Config.AzureRegion -Apply $apply
            $workspaceResourceId = if ($workspace.ResourceId) { $workspace.ResourceId } elseif ($workspace.Id) { $workspace.Id } else { "/subscriptions/$subscriptionId/resourceGroups/$($Config.ResourceGroupName)/providers/Microsoft.OperationalInsights/workspaces/$($Config.WorkspaceName)" }
            $diag = Ensure-EntraDiagnosticSettingToLogAnalytics -DiagnosticSettingName $Config.DiagnosticSettingName -WorkspaceResourceId $workspaceResourceId -Apply $apply
            $emails = @($Config.AlertEmails -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $ag = Get-OrCreate-ActionGroup -SubscriptionId $subscriptionId -ResourceGroupName $Config.ResourceGroupName -Name $Config.ActionGroupName -Location $Config.AzureRegion -EmailRecipients $emails -Apply $apply
            $monitoring.Entries += $diag
            $monitoring.Entries += $ag
            $upns = @($users | ForEach-Object { $_.userPrincipalName })
            $ids = @($users | ForEach-Object { $_.id }) + @($group.id, $rmau.id, $authStrength.id, $caPolicy.id)
            if ($Config.CreateSignInAlert) {
                $monitoring.Entries += Ensure-ScheduledQueryRule -SubscriptionId $subscriptionId -ResourceGroupName $Config.ResourceGroupName -Name 'alert-breakglass-any-signin' -Location $Config.AzureRegion -WorkspaceResourceId $workspaceResourceId -Query (New-BreakGlassSignInKql -UserPrincipalNames $upns) -ActionGroupId $ag.Id -Apply $apply
            }
            if ($Config.CreateAuditAlert) {
                $monitoring.Entries += Ensure-ScheduledQueryRule -SubscriptionId $subscriptionId -ResourceGroupName $Config.ResourceGroupName -Name 'alert-breakglass-object-change' -Location $Config.AzureRegion -WorkspaceResourceId $workspaceResourceId -Query (New-BreakGlassAuditKql -UserPrincipalNames $upns -ObjectIds $ids) -ActionGroupId $ag.Id -Apply $apply
            }
        }
        catch {
            Write-SafeError -Message 'Azure Monitor konfiguration kunne ikke fuldføres.' -ErrorRecord $_
            $monitoring.Entries += [pscustomobject]@{ Status = 'Warning'; Message = ConvertTo-RedactedError $_ }
        }
    }

    $fidoStatus = Test-BreakGlassFido2Registration -Users $users
    $validation = Invoke-Validation -Users $users -Group $group -RoleAssignments $roleAssignments -Rmau $rmau -AuthStrength $authStrength -CaPolicy $caPolicy -FidoStatus $fidoStatus -Monitoring $monitoring
    $script:State['ValidationResults'] = $validation

    $result = New-Object psobject
    $result | Add-Member -MemberType NoteProperty -Name Version -Value $script:AppVersion
    $result | Add-Member -MemberType NoteProperty -Name Timestamp -Value ((Get-Date).ToString('o'))
    $result | Add-Member -MemberType NoteProperty -Name TenantId -Value $script:State['TenantId']
    $result | Add-Member -MemberType NoteProperty -Name TenantDisplayName -Value $script:State['TenantDisplayName']
    $result | Add-Member -MemberType NoteProperty -Name Operator -Value $script:State['GraphAccount']
    $result | Add-Member -MemberType NoteProperty -Name OnMicrosoftDomain -Value $domain
    $resultUsers = [object[]]@($users | Select-Object id,userPrincipalName,displayName,accountEnabled)
    $result | Add-Member -MemberType NoteProperty -Name Users -Value ([object]$resultUsers)
    $result | Add-Member -MemberType NoteProperty -Name Group -Value $group
    $result | Add-Member -MemberType NoteProperty -Name Membership -Value ([object]([object[]]@($membership)))
    $result | Add-Member -MemberType NoteProperty -Name RoleAssignments -Value ([object]([object[]]@($roleAssignments)))
    $result | Add-Member -MemberType NoteProperty -Name RMAU -Value $rmau
    $result | Add-Member -MemberType NoteProperty -Name RmauMembership -Value ([object]([object[]]@($rmauMembership)))
    $result | Add-Member -MemberType NoteProperty -Name AuthenticationStrength -Value $authStrength
    $result | Add-Member -MemberType NoteProperty -Name ConditionalAccess -Value $caPolicy
    $result | Add-Member -MemberType NoteProperty -Name ExistingCaExclusions -Value ([object]([object[]]@($existingCaExclusionResults)))
    $result | Add-Member -MemberType NoteProperty -Name Monitoring -Value $monitoring
    $result | Add-Member -MemberType NoteProperty -Name Fido2 -Value ([object]([object[]]@($fidoStatus)))
    $result | Add-Member -MemberType NoteProperty -Name ValidationResults -Value ([object]([object[]]@($validation)))
    $result | Add-Member -MemberType NoteProperty -Name Warnings -Value ([object]([object[]]@($script:State['Warnings'])))
    $result | Add-Member -MemberType NoteProperty -Name CaBackupFiles -Value ([object]([object[]]@($script:State['CaBackupFiles'])))
    $script:State['Result'] = $result
    New-JsonReport -Result $result -OutputFolder $output | Out-Null
    New-HtmlReport -Result $result -OutputFolder $output | Out-Null
    Show-CreatedPasswordsOnce
    Write-AppLog -Level PASS -Message 'Konfiguration/rapportering fuldført.'
    return $result
}

function Invoke-Validation {
    [CmdletBinding()]
    param(
        [object[]] $Users,
        [AllowNull()] $Group,
        [object[]] $RoleAssignments,
        [AllowNull()] $Rmau,
        [AllowNull()] $AuthStrength,
        [AllowNull()] $CaPolicy,
        [object[]] $FidoStatus,
        [AllowNull()] $Monitoring
    )

    $items = @()
    Write-AppLog -Message 'Starter samlet validering.'
    foreach ($user in $Users) {
        $items += [pscustomobject]@{ Check = "Bruger findes: $($user.userPrincipalName)"; Status = if ($user.id) { 'Passed' } else { 'Failed' }; Detail = $user.id }
        $items += [pscustomobject]@{ Check = "Bruger enabled: $($user.userPrincipalName)"; Status = if ($user.accountEnabled -eq $true) { 'Passed' } else { 'Warning' }; Detail = $user.accountEnabled }
        $items += [pscustomobject]@{ Check = "onmicrosoft.com UPN: $($user.userPrincipalName)"; Status = if ($user.userPrincipalName -like '*@*.onmicrosoft.com') { 'Passed' } else { 'Failed' }; Detail = $user.userPrincipalName }
    }
    $items += [pscustomobject]@{ Check = 'Break-glass gruppe findes'; Status = if ($Group.id) { 'Passed' } else { 'Failed' }; Detail = $Group.displayName }
    $items += [pscustomobject]@{ Check = 'Global Administrator assignments'; Status = if (@($RoleAssignments | Where-Object { $_.Status -match 'Assigned|AlreadyAssigned|Planned|PlannedOrMock' }).Count -ge 2) { 'Passed' } else { 'Warning' }; Detail = (@($RoleAssignments).Status -join ', ') }
    $items += [pscustomobject]@{ Check = 'RMAU findes'; Status = if ($Rmau.id) { 'Passed' } else { 'Warning' }; Detail = $Rmau.displayName }
    $items += [pscustomobject]@{ Check = 'Authentication strength findes'; Status = if ($AuthStrength.id) { 'Passed' } else { 'Warning' }; Detail = $AuthStrength.displayName }
    $items += [pscustomobject]@{ Check = 'Conditional Access policy findes'; Status = if ($CaPolicy.id) { 'Passed' } else { 'Warning' }; Detail = $CaPolicy.displayName }
    foreach ($fido in $FidoStatus) {
        $items += [pscustomobject]@{ Check = "FIDO2 registreret: $($fido.UserPrincipalName)"; Status = if ($fido.HasFido2) { 'Passed' } else { 'Warning' }; Detail = "Count: $($fido.Count)" }
    }
    if ($Monitoring -and $Monitoring.Enabled) {
        $monitoringEntries = @($Monitoring.Entries)
        $monitoringWarnings = @($monitoringEntries | Where-Object { $_.Status -eq 'Warning' })
        $monitoringStatus = if ($monitoringWarnings.Count -eq 0) { 'Passed' } else { 'Warning' }
        $monitoringDetail = (@($monitoringEntries | ForEach-Object { $_.Status }) -join ', ')
        $items += [pscustomobject]@{
            Check  = 'Azure Monitor konfiguration'
            Status = $monitoringStatus
            Detail = $monitoringDetail
        }
    }
    else {
        $items += [pscustomobject]@{ Check = 'Azure Monitor konfiguration'; Status = 'Skipped'; Detail = 'Monitoring er slået fra' }
    }
    Write-AppLog -Message 'Samlet validering færdig.'
    return @($items)
}

function New-JsonReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Result,
        [Parameter(Mandatory)][string] $OutputFolder
    )

    return Export-JsonSafe -InputObject $Result -Path (Join-Path $OutputFolder 'result.json') -Depth 40
}

function ConvertTo-HtmlEncoded {
    [CmdletBinding()]
    param([AllowNull()] $Value)

    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string] $Value)
}

function Get-ReportProperty {
    [CmdletBinding()]
    param(
        [AllowNull()] $Object,
        [Parameter(Mandatory)][string] $Name
    )

    if ($null -eq $Object) { return '' }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return '' }
    return $property.Value
}

function New-HtmlTable {
    [CmdletBinding()]
    param([object[]] $Items)

    if (-not $Items -or $Items.Count -eq 0) {
        return '<p>Ingen data.</p>'
    }
    $properties = @($Items[0].PSObject.Properties.Name)
    $header = '<tr>' + (($properties | ForEach-Object { '<th>{0}</th>' -f (ConvertTo-HtmlEncoded $_) }) -join '') + '</tr>'
    $rows = foreach ($item in $Items) {
        '<tr>' + (($properties | ForEach-Object { '<td>{0}</td>' -f (ConvertTo-HtmlEncoded $item.$_) }) -join '') + '</tr>'
    }
    return '<table>' + $header + ($rows -join [Environment]::NewLine) + '</table>'
}

function New-HtmlReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Result,
        [Parameter(Mandatory)][string] $OutputFolder
    )

    $path = Join-Path -Path $OutputFolder -ChildPath 'report.html'
    $validationTable = New-HtmlTable -Items @($Result.ValidationResults)
    $usersTable = New-HtmlTable -Items @($Result.Users)
    $membershipTable = New-HtmlTable -Items @($Result.Membership)
    $roleTable = New-HtmlTable -Items @($Result.RoleAssignments)
    $rmauMembershipTable = New-HtmlTable -Items @($Result.RmauMembership)
    $fidoTable = New-HtmlTable -Items @($Result.Fido2 | Select-Object UserPrincipalName,HasFido2,Count)
    $monitoringTable = New-HtmlTable -Items @($Result.Monitoring.Entries)
    $caExclusionTable = New-HtmlTable -Items @($Result.ExistingCaExclusions)
    $warnings = if ($Result.Warnings.Count -gt 0) { '<ul>' + (($Result.Warnings | ForEach-Object { '<li>{0}</li>' -f (ConvertTo-HtmlEncoded $_) }) -join '') + '</ul>' } else { '<p>Ingen registrerede advarsler.</p>' }
    $content = @"
<!doctype html>
<html lang="da">
<head>
  <meta charset="utf-8">
  <title>CONFIDENTIAL - NetIP Entra Break Glass Configurator</title>
  <style>
    body { font-family: Segoe UI, Arial, sans-serif; margin: 32px; color: #111827; line-height: 1.45; }
    .banner { background: #7f1d1d; color: #fff; padding: 14px 18px; font-size: 22px; font-weight: 700; letter-spacing: 1px; }
    .warning { border: 2px solid #b45309; background: #fffbeb; padding: 14px 18px; margin: 18px 0; }
    h1 { margin-top: 22px; }
    h2 { border-bottom: 1px solid #d1d5db; padding-bottom: 6px; margin-top: 28px; }
    table { border-collapse: collapse; width: 100%; margin: 10px 0 18px 0; }
    th, td { border: 1px solid #d1d5db; padding: 8px 10px; text-align: left; vertical-align: top; }
    th { background: #f3f4f6; }
    .muted { color: #4b5563; }
  </style>
</head>
<body>
  <div class="banner">CONFIDENTIAL</div>
  <h1>NetIP Entra Break Glass Configurator</h1>
  <div class="warning"><strong>Vigtigt:</strong> Rapporten indeholder ikke adgangskoder, tokens eller FIDO2 hemmeligheder. FIDO2 opsætning udføres manuelt.</div>
  <h2>Tenant</h2>
  <table>
    <tr><th>Tenant ID</th><td>$(ConvertTo-HtmlEncoded $Result.TenantId)</td></tr>
    <tr><th>Tenant navn</th><td>$(ConvertTo-HtmlEncoded $Result.TenantDisplayName)</td></tr>
    <tr><th>Operator</th><td>$(ConvertTo-HtmlEncoded $Result.Operator)</td></tr>
    <tr><th>Timestamp</th><td>$(ConvertTo-HtmlEncoded $Result.Timestamp)</td></tr>
    <tr><th>onmicrosoft.com</th><td>$(ConvertTo-HtmlEncoded $Result.OnMicrosoftDomain)</td></tr>
  </table>
  <h2>Brugere</h2>
  $usersTable
  <h2>Role-assignable gruppe</h2>
  <table>
    <tr><th>DisplayName</th><td>$(ConvertTo-HtmlEncoded (Get-ReportProperty -Object $Result.Group -Name 'displayName'))</td></tr>
    <tr><th>ID</th><td>$(ConvertTo-HtmlEncoded (Get-ReportProperty -Object $Result.Group -Name 'id'))</td></tr>
    <tr><th>MailNickname</th><td>$(ConvertTo-HtmlEncoded (Get-ReportProperty -Object $Result.Group -Name 'mailNickname'))</td></tr>
  </table>
  <h2>Gruppemedlemskab</h2>
  $membershipTable
  <h2>Global Administrator assignments</h2>
  $roleTable
  <h2>Restricted management administrative unit</h2>
  <table>
    <tr><th>DisplayName</th><td>$(ConvertTo-HtmlEncoded (Get-ReportProperty -Object $Result.RMAU -Name 'displayName'))</td></tr>
    <tr><th>ID</th><td>$(ConvertTo-HtmlEncoded (Get-ReportProperty -Object $Result.RMAU -Name 'id'))</td></tr>
  </table>
  <h2>RMAU medlemskab</h2>
  $rmauMembershipTable
  <h2>Authentication strength</h2>
  <table>
    <tr><th>DisplayName</th><td>$(ConvertTo-HtmlEncoded (Get-ReportProperty -Object $Result.AuthenticationStrength -Name 'displayName'))</td></tr>
    <tr><th>ID</th><td>$(ConvertTo-HtmlEncoded (Get-ReportProperty -Object $Result.AuthenticationStrength -Name 'id'))</td></tr>
  </table>
  <h2>Dedikeret Conditional Access policy</h2>
  <table>
    <tr><th>DisplayName</th><td>$(ConvertTo-HtmlEncoded (Get-ReportProperty -Object $Result.ConditionalAccess -Name 'displayName'))</td></tr>
    <tr><th>ID</th><td>$(ConvertTo-HtmlEncoded (Get-ReportProperty -Object $Result.ConditionalAccess -Name 'id'))</td></tr>
    <tr><th>State</th><td>$(ConvertTo-HtmlEncoded (Get-ReportProperty -Object $Result.ConditionalAccess -Name 'state'))</td></tr>
  </table>
  <h2>Conditional Access exclusions</h2>
  $caExclusionTable
  <h2>FIDO2 validering</h2>
  $fidoTable
  <h2>Azure Monitor</h2>
  $monitoringTable
  <h2>Validering</h2>
  $validationTable
  <h2>Advarsler</h2>
  $warnings
  <h2>Manuelle resterende trin</h2>
  <ul>
    <li>Registrer en separat FIDO2/FIDO key for hver konto.</li>
    <li>Opbevar keys og credentials efter intern nødprocedure.</li>
    <li>Test login og alerting periodisk.</li>
    <li>Brug aldrig kontiene til daglig administration.</li>
  </ul>
</body>
</html>
"@
    Set-Content -Path $path -Value $content -Encoding UTF8
    Write-AppLog -Message "HTML rapport genereret: $path"
    return $path
}

function Validate-LogAnalyticsConfiguration {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{ Status = 'BestEffort'; Detail = 'Valideres via ARM-kald under konfiguration.' }
}

function Build-ConfigFromUi {
    [CmdletBinding()]
    param()

    return @{
        UserPrefix1            = $script:Ui.UserPrefix1.Text.Trim()
        UserPrefix2            = $script:Ui.UserPrefix2.Text.Trim()
        DisplayName1           = $script:Ui.DisplayName1.Text.Trim()
        DisplayName2           = $script:Ui.DisplayName2.Text.Trim()
        GroupDisplayName       = $script:Ui.GroupDisplayName.Text.Trim()
        RmauDisplayName        = $script:Ui.RmauDisplayName.Text.Trim()
        AuthStrengthName       = $script:Ui.AuthStrengthName.Text.Trim()
        CaPolicyName           = $script:Ui.CaPolicyName.Text.Trim()
        CaState                = [string] $script:Ui.CaState.SelectedItem.Content
        ExcludeFromExistingCa  = [bool] $script:Ui.ExcludeExistingCa.IsChecked
        AllowedAaguids         = $script:Ui.AllowedAaguids.Text
        UseExistingWorkspace   = [bool] $script:Ui.UseExistingWorkspace.IsChecked
        SubscriptionId         = $script:Ui.SubscriptionId.Text.Trim()
        ResourceGroupName      = $script:Ui.ResourceGroupName.Text.Trim()
        WorkspaceName          = $script:Ui.WorkspaceName.Text.Trim()
        AzureRegion            = $script:Ui.AzureRegion.Text.Trim()
        DiagnosticSettingName  = $script:Ui.DiagnosticSettingName.Text.Trim()
        ActionGroupName        = $script:Ui.ActionGroupName.Text.Trim()
        AlertEmails            = $script:Ui.AlertEmails.Text.Trim()
        CreateSignInAlert      = [bool] $script:Ui.CreateSignInAlert.IsChecked
        CreateAuditAlert       = [bool] $script:Ui.CreateAuditAlert.IsChecked
        DisableMonitoring      = [bool] $script:Ui.DisableMonitoring.IsChecked
        NoApply                = [bool] $script:Ui.NoApply.IsChecked
    }
}

function Update-ConnectionStatusUi {
    [CmdletBinding()]
    param()

    if (-not $script:MainWindow) { return }
    $script:Ui.GraphAccount.Text = $script:State.GraphAccount
    $script:Ui.TenantId.Text = $script:State.TenantId
    $script:Ui.TenantName.Text = $script:State.TenantDisplayName
    $script:Ui.OnMicrosoftDomain.Text = $script:State.OnMicrosoftDomain
    $script:Ui.AzureAccount.Text = $script:State.AzureAccount
    $script:Ui.SubscriptionIdDetected.Text = $script:State.AzureSubscriptionId
    $script:Ui.ConnectionStatus.Text = "Graph: $($script:State.GraphConnected) | Azure: $($script:State.AzureConnected)"
}

function Update-PrecheckUi {
    [CmdletBinding()]
    param([object[]] $Results)

    $script:Ui.PrecheckList.Items.Clear()
    foreach ($result in $Results) {
        $script:Ui.PrecheckList.Items.Add(('{0} [{1}] {2}' -f $result.Check, $result.Status, $result.Detail)) | Out-Null
    }
}

function Update-ValidationUi {
    [CmdletBinding()]
    param([object[]] $Results)

    $script:Ui.ValidationList.Items.Clear()
    foreach ($result in $Results) {
        $script:Ui.ValidationList.Items.Add(('{0} [{1}] {2}' -f $result.Check, $result.Status, $result.Detail)) | Out-Null
    }
}

function Update-UiPump {
    [CmdletBinding()]
    param()

    if (-not $script:MainWindow) { return }
    try {
        $script:MainWindow.Dispatcher.Invoke([Action] { }, [System.Windows.Threading.DispatcherPriority]::Background)
    }
    catch {
        # UI pump refresh is best-effort.
    }
}

function Set-UiStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Message,
        [switch] $Busy,
        [switch] $Log
    )

    if ($script:Ui -and $script:Ui.ContainsKey('BackgroundStatus') -and $script:Ui.BackgroundStatus) {
        $script:Ui.BackgroundStatus.Text = $Message
    }
    if ($script:Ui -and $script:Ui.ContainsKey('StatusProgress') -and $script:Ui.StatusProgress) {
        $script:Ui.StatusProgress.IsIndeterminate = [bool] $Busy
        $script:Ui.StatusProgress.Visibility = if ($Busy) { 'Visible' } else { 'Collapsed' }
    }
    if ($Log) {
        Write-AppLog -Message $Message
    }
    Update-UiPump
}

function Set-UiBusy {
    [CmdletBinding()]
    param([bool] $Busy)

    foreach ($name in @('ConnectAllButton','ConnectGraphButton','ConnectAzureButton','RunPrecheckButton','BuildPlanButton','ExportPlanButton','ApplyButton','BackButton','NextButton')) {
        if ($script:Ui.ContainsKey($name) -and $script:Ui[$name]) {
            $script:Ui[$name].IsEnabled = -not $Busy
        }
    }
    if (-not $Busy) {
        Update-WizardNavigation
    }
    Update-UiPump
}

function Set-WizardMaxStep {
    [CmdletBinding()]
    param([int] $Step)

    if ($Step -gt $script:WizardMaxStep) {
        $script:WizardMaxStep = [Math]::Min($Step, $script:Ui.WizardTabs.Items.Count - 1)
    }
    Update-WizardNavigation
}

function Set-WizardStep {
    [CmdletBinding()]
    param([int] $Step)

    $target = [Math]::Max(0, [Math]::Min($Step, $script:WizardMaxStep))
    $script:WizardInternalNavigation = $true
    $script:Ui.WizardTabs.SelectedIndex = $target
    $script:WizardInternalNavigation = $false
    Update-WizardNavigation
}

function Update-WizardNavigation {
    [CmdletBinding()]
    param()

    if (-not $script:Ui.WizardTabs) { return }
    for ($i = 0; $i -lt $script:Ui.WizardTabs.Items.Count; $i++) {
        $script:Ui.WizardTabs.Items[$i].IsEnabled = ($i -le $script:WizardMaxStep)
    }
    $index = $script:Ui.WizardTabs.SelectedIndex
    $script:Ui.BackButton.IsEnabled = ($index -gt 0)
    $script:Ui.NextButton.IsEnabled = ($index -lt ($script:Ui.WizardTabs.Items.Count - 1))
    $script:Ui.FooterStatus.Text = 'Step {0} af {1}' -f ($index + 1), $script:Ui.WizardTabs.Items.Count
}

function Ensure-AppModulesFromUi {
    [CmdletBinding()]
    param()

    if ($script:State.Mock) {
        Set-UiStatus -Message 'Mock mode: module check springes over.' -Busy
        return $true
    }
    Set-UiStatus -Message 'Tjekker nødvendige PowerShell moduler...' -Busy -Log
    $status = Test-RequiredModules
    $missing = @($status | Where-Object { -not $_.Present })
    if ($missing.Count -gt 0) {
        if ($script:ModuleWorkerProcess -and -not $script:ModuleWorkerProcess.HasExited) {
            Set-UiStatus -Message 'Modulinstallation kører allerede i separat PowerShell vindue.' -Busy
            return $false
        }
        Start-ModulePreparationWorker
        return $false
    }
    Set-UiStatus -Message 'Importerer Microsoft Graph og Az moduler...' -Busy -Log
    Import-RequiredModules
    return $true
}

function Connect-AllFromUi {
    [CmdletBinding()]
    param()

    Set-UiStatus -Message 'Starter samlet forbindelse...' -Busy -Log
    if (-not (Ensure-AppModulesFromUi)) { return $false }
    Set-UiStatus -Message 'Forbinder til Microsoft Graph. Gennemfør loginprompten, hvis den vises...' -Busy -Log
    Connect-AppGraph | Out-Null
    if (-not [bool] $script:Ui.DisableMonitoring.IsChecked) {
        try {
            Set-UiStatus -Message 'Forbinder til Azure Resource Manager. Gennemfør loginprompten, hvis den vises...' -Busy -Log
            Connect-AppAzure | Out-Null
        }
        catch {
            Write-SafeError -Message 'Azure forbindelse fejlede under samlet forbindelse.' -ErrorRecord $_
            $answer = Show-AppMessage -Message ("Azure forbindelse fejlede:`r`n{0}`r`n`r`nVil du fortsætte uden Azure Monitor/Log Analytics for denne kørsel?" -f (ConvertTo-RedactedError $_)) -Buttons 'YesNo' -Icon 'Question'
            if ($answer -ne 'Yes') {
                throw
            }
            $script:Ui.DisableMonitoring.IsChecked = $true
            Write-AppLog -Level WARN -Message 'Azure Monitor/Log Analytics blev slået fra for denne kørsel efter Azure sign-in fejl.'
        }
    }
    Update-ConnectionStatusUi
    Set-UiStatus -Message 'Forbindelser klar.' -Log
    return $true
}

function Invoke-PrecheckFromUi {
    [CmdletBinding()]
    param()

    $results = Invoke-PreCheck -Config (Build-ConfigFromUi)
    Update-PrecheckUi -Results $results
    $failed = @($results | Where-Object { $_.Status -eq 'Failed' })
    $script:PrecheckPassed = ($failed.Count -eq 0)
    if ($script:PrecheckPassed) {
        Set-WizardMaxStep -Step 3
    }
    return $results
}

function New-PlanFromUi {
    [CmdletBinding()]
    param()

    $plan = New-Plan -Config (Build-ConfigFromUi)
    $script:Ui.PlanText.Text = ($plan | ConvertTo-Json -Depth 30)
    $script:PlanBuilt = $true
    Set-WizardMaxStep -Step 5
    return $plan
}

function Test-ConfigurationForWizard {
    [CmdletBinding()]
    param()

    $config = Build-ConfigFromUi
    foreach ($field in @('UserPrefix1','UserPrefix2','DisplayName1','DisplayName2','GroupDisplayName','RmauDisplayName','AuthStrengthName','CaPolicyName')) {
        if ([string]::IsNullOrWhiteSpace([string] $config[$field])) {
            throw "Feltet '$field' skal udfyldes."
        }
    }
    Validate-AaguidList -Text $config.AllowedAaguids | Out-Null
    return $config
}

function Move-WizardNext {
    [CmdletBinding()]
    param()

    $index = $script:Ui.WizardTabs.SelectedIndex
    switch ($index) {
        0 {
            if (-not [bool] $script:Ui.UnderstandRisk.IsChecked) {
                Show-AppMessage -Message 'Sæt flueben i sikkerhedsbekræftelsen før du fortsætter.' -Icon 'Warning' | Out-Null
                return
            }
            Set-WizardMaxStep -Step 1
            Set-WizardStep -Step 1
            Set-UiStatus -Message 'Næste trin: forbind til Graph + Azure, eller kun Graph hvis monitoring skal springes over.'
        }
        1 {
            if (-not $script:State.GraphConnected) {
                Show-AppMessage -Message 'Forbind til Microsoft Graph før du fortsætter.' -Icon 'Warning' | Out-Null
                return
            }
            if (-not $script:State.AzureConnected -and -not [bool] $script:Ui.DisableMonitoring.IsChecked) {
                $answer = Show-AppMessage -Message "Azure er ikke forbundet. Vil du fortsætte uden Azure Monitor/Log Analytics for denne kørsel?" -Buttons 'YesNo' -Icon 'Question'
                if ($answer -ne 'Yes') { return }
                $script:Ui.DisableMonitoring.IsChecked = $true
            }
            Set-WizardMaxStep -Step 2
            Set-WizardStep -Step 2
            Set-UiStatus -Message 'Klar til pre-check.'
        }
        2 {
            Set-UiStatus -Message 'Kører pre-check...' -Busy -Log
            Invoke-PrecheckFromUi | Out-Null
            if (-not $script:PrecheckPassed) {
                Set-UiStatus -Message 'Pre-check har hard failures.'
                Show-AppMessage -Message 'Pre-check har hard failures. Ret dem før du fortsætter.' -Icon 'Warning' | Out-Null
                return
            }
            Set-WizardStep -Step 3
            Set-UiStatus -Message 'Pre-check OK. Udfyld konfigurationen.'
        }
        3 {
            Test-ConfigurationForWizard | Out-Null
            Set-WizardMaxStep -Step 4
            Set-WizardStep -Step 4
            Set-UiStatus -Message 'Konfiguration valideret. Byg og gennemgå dry-run planen.'
        }
        4 {
            if (-not $script:PlanBuilt) {
                Set-UiStatus -Message 'Bygger dry-run plan...' -Busy -Log
                New-PlanFromUi | Out-Null
            }
            Set-WizardStep -Step 5
            Set-UiStatus -Message 'Dry-run plan er klar. Apply kan startes fra trin 5.'
        }
        default {
            Set-WizardMaxStep -Step ($index + 1)
            Set-WizardStep -Step ($index + 1)
            Set-UiStatus -Message ('Wizard flyttet til step {0}.' -f ($script:Ui.WizardTabs.SelectedIndex + 1))
        }
    }
}

function Sync-LogView {
    [CmdletBinding()]
    param()

    if (-not $script:LogTextBox -or -not (Test-Path -Path $script:LogFile)) { return }
    try {
        $content = Get-Content -Path $script:LogFile -Raw -Encoding UTF8 -ErrorAction Stop
        if ($content.Length -lt $script:LastLogLength) { $script:LastLogLength = 0 }
        if ($content.Length -gt $script:LastLogLength) {
            $script:LogTextBox.AppendText($content.Substring($script:LastLogLength))
            $script:LogTextBox.ScrollToEnd()
            $script:LastLogLength = $content.Length
        }
    }
    catch {
        # Log polling can race with file writes.
    }
}

function Start-WorkerApply {
    [CmdletBinding()]
    param([hashtable] $Config)

    $output = New-OutputFolder -TenantId $(if ($script:State.TenantId) { $script:State.TenantId } else { 'UnknownTenant' })
    $workerConfig = @{
        Config = $Config
        State  = @{
            Mock = $script:State.Mock
            NoApply = $script:State.NoApply
            GraphConnected = $script:State.GraphConnected
            AzureConnected = $script:State.AzureConnected
            TenantId = $script:State.TenantId
            TenantDisplayName = $script:State.TenantDisplayName
            OnMicrosoftDomain = $script:State.OnMicrosoftDomain
            AzureSubscriptionId = $script:State.AzureSubscriptionId
            AzureSubscriptionName = $script:State.AzureSubscriptionName
        }
        OutputFolder = $output
        LogFile = $script:LogFile
        Mock = $script:State.Mock
    }
    $configPath = Join-Path -Path $output -ChildPath 'worker-config.json'
    Export-JsonSafe -InputObject $workerConfig -Path $configPath -Depth 30 | Out-Null
    $powerShell = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $args = @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',('"{0}"' -f $PSCommandPath),'-WorkerMode','-WorkerConfigPath',('"{0}"' -f $configPath))
    if ($script:State.Mock) { $args += '-Mock' }
    $script:WorkerProcess = Start-Process -FilePath $powerShell -ArgumentList ($args -join ' ') -PassThru -WindowStyle Normal
    Write-AppLog -Message 'Worker process startet i et synligt PowerShell vindue. Sign-in prompts kan blive vist der.'
}

function Invoke-WorkerMode {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)

    $worker = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:State['Mock'] = [bool] $worker.Mock
    $script:LogFile = [string] $worker.LogFile
    $script:SessionOutputFolder = [string] $worker.OutputFolder
    foreach ($property in $worker.State.PSObject.Properties) {
        if ($script:State.Contains($property.Name)) {
            $script:State[$property.Name] = $property.Value
        }
    }
    if (-not $script:State.Mock) {
        Import-RequiredModules
        Write-AppLog -Message 'Worker forbinder til Microsoft Graph. Et loginvindue kan blive vist.'
        Connect-AppGraph | Out-Null
        if (-not [bool] $worker.Config.DisableMonitoring) {
            Write-AppLog -Message 'Worker forbinder til Azure Resource Manager. Et loginvindue kan blive vist.'
            Connect-AppAzure | Out-Null
        }
    }
    else {
        Write-AppLog -Message 'Worker kører i mock mode og springer modulimport/sign-in over.'
    }
    Invoke-BreakGlassConfiguration -Config (ConvertTo-HashtableRecursive -InputObject $worker.Config) | Out-Null
}

function Start-BreakGlassWizard {
    [CmdletBinding()]
    param()

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    Add-Type -AssemblyName System.Windows.Forms
    $script:Ui = @{}

    [xml] $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="NetIP Entra Break Glass Configurator"
        Height="820"
        Width="1180"
        MinHeight="760"
        MinWidth="1050"
        WindowStartupLocation="CenterScreen"
        Background="#F5F7FA">
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Margin="0,0,0,12">
            <TextBlock Text="NetIP Entra Break Glass Configurator" FontSize="24" FontWeight="SemiBold" Foreground="#111827"/>
            <TextBlock Text="Dansk wizard til sikker og ensartet break-glass baseline i Microsoft Entra tenants." Foreground="#4B5563" Margin="0,4,0,0"/>
        </StackPanel>
        <TabControl x:Name="WizardTabs" Grid.Row="1">
            <TabItem Header="1. Velkommen">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="18" MaxWidth="980">
                        <TextBlock FontSize="18" FontWeight="SemiBold" Text="Velkommen"/>
                        <TextBlock TextWrapping="Wrap" Margin="0,10,0,0" Text="Dette værktøj etablerer en break-glass baseline med cloud-only konti, rolle-assignable gruppe, direkte Global Administrator roller, RMAU, FIDO2 authentication strength, Conditional Access, Log Analytics og Azure Monitor alerts."/>
                        <TextBlock TextWrapping="Wrap" Margin="0,10,0,0" Text="FIDO2/FIDO key registrering automatiseres ikke. Konsulenten skal manuelt registrere FIDO2 keys og derefter validere metoderne i værktøjet."/>
                        <TextBlock TextWrapping="Wrap" Margin="0,10,0,0" Text="Microsoft Sentinel og SentinelOne bruges ikke i v1. Overvågning bruger Entra Diagnostic Settings til Log Analytics samt Azure Monitor scheduled query alerts."/>
                        <CheckBox x:Name="UnderstandRisk" Margin="0,20,0,0" Content="Jeg forstår at dette script ændrer sikkerhedskritisk tenant-konfiguration."/>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>
            <TabItem Header="2. Forbindelser">
                <Grid Margin="18">
                    <Grid.ColumnDefinitions>
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
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <StackPanel Grid.Row="0" Grid.Column="0" Grid.ColumnSpan="2" Orientation="Horizontal" Margin="0,0,0,10">
                        <Button x:Name="ConnectAllButton" Content="Forbind til Graph + Azure" Height="32" Width="190" Margin="0,0,8,0"/>
                        <Button x:Name="ConnectGraphButton" Content="Kun Graph" Height="32" Width="110" Margin="0,0,8,0"/>
                        <Button x:Name="ConnectAzureButton" Content="Kun Azure" Height="32" Width="110"/>
                    </StackPanel>
                    <TextBlock Grid.Row="1" Grid.Column="0" Text="Graph konto" FontWeight="SemiBold"/>
                    <TextBlock x:Name="GraphAccount" Grid.Row="1" Grid.Column="1"/>
                    <TextBlock Grid.Row="2" Grid.Column="0" Text="Tenant ID" FontWeight="SemiBold"/>
                    <TextBlock x:Name="TenantId" Grid.Row="2" Grid.Column="1"/>
                    <TextBlock Grid.Row="3" Grid.Column="0" Text="Tenant navn" FontWeight="SemiBold"/>
                    <TextBlock x:Name="TenantName" Grid.Row="3" Grid.Column="1"/>
                    <TextBlock Grid.Row="4" Grid.Column="0" Text="onmicrosoft.com domæne" FontWeight="SemiBold"/>
                    <TextBlock x:Name="OnMicrosoftDomain" Grid.Row="4" Grid.Column="1"/>
                    <TextBlock Grid.Row="5" Grid.Column="0" Text="Azure konto" FontWeight="SemiBold"/>
                    <TextBlock x:Name="AzureAccount" Grid.Row="5" Grid.Column="1"/>
                    <TextBlock Grid.Row="6" Grid.Column="0" Text="Subscription ID" FontWeight="SemiBold"/>
                    <TextBlock x:Name="SubscriptionIdDetected" Grid.Row="6" Grid.Column="1"/>
                    <TextBlock Grid.Row="7" Grid.Column="0" Text="Status" FontWeight="SemiBold"/>
                    <TextBlock x:Name="ConnectionStatus" Grid.Row="7" Grid.Column="1" Text="Ikke forbundet"/>
                </Grid>
            </TabItem>
            <TabItem Header="3. Pre-check">
                <DockPanel Margin="18">
                    <Button x:Name="RunPrecheckButton" DockPanel.Dock="Top" Content="Kør pre-check" Height="32" Width="140" HorizontalAlignment="Left" Margin="0,0,0,10"/>
                    <ListBox x:Name="PrecheckList" FontFamily="Consolas"/>
                </DockPanel>
            </TabItem>
            <TabItem Header="4. Konfiguration">
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <Grid Margin="18">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="260"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="260"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <TextBlock Grid.Row="0" Grid.Column="0" Text="Konto 1 prefix"/>
                        <TextBox x:Name="UserPrefix1" Grid.Row="0" Grid.Column="1" Text="bg-admin-01" Margin="0,0,12,8"/>
                        <TextBlock Grid.Row="0" Grid.Column="2" Text="Konto 2 prefix"/>
                        <TextBox x:Name="UserPrefix2" Grid.Row="0" Grid.Column="3" Text="bg-admin-02" Margin="0,0,0,8"/>
                        <TextBlock Grid.Row="1" Grid.Column="0" Text="Display name 1"/>
                        <TextBox x:Name="DisplayName1" Grid.Row="1" Grid.Column="1" Text="Break Glass Admin 01" Margin="0,0,12,8"/>
                        <TextBlock Grid.Row="1" Grid.Column="2" Text="Display name 2"/>
                        <TextBox x:Name="DisplayName2" Grid.Row="1" Grid.Column="3" Text="Break Glass Admin 02" Margin="0,0,0,8"/>
                        <TextBlock Grid.Row="2" Grid.Column="0" Text="Gruppe"/>
                        <TextBox x:Name="GroupDisplayName" Grid.Row="2" Grid.Column="1" Text="GRP-ENTRA-BreakGlass-Admins" Margin="0,0,12,8"/>
                        <TextBlock Grid.Row="2" Grid.Column="2" Text="RMAU"/>
                        <TextBox x:Name="RmauDisplayName" Grid.Row="2" Grid.Column="3" Text="RMAU-BreakGlass-Protection" Margin="0,0,0,8"/>
                        <TextBlock Grid.Row="3" Grid.Column="0" Text="Authentication strength"/>
                        <TextBox x:Name="AuthStrengthName" Grid.Row="3" Grid.Column="1" Text="AS-BreakGlass-FIDO2" Margin="0,0,12,8"/>
                        <TextBlock Grid.Row="3" Grid.Column="2" Text="CA policy navn"/>
                        <TextBox x:Name="CaPolicyName" Grid.Row="3" Grid.Column="3" Text="CA-BG-Require-FIDO2-AuthenticationStrength" Margin="0,0,0,8"/>
                        <TextBlock Grid.Row="4" Grid.Column="0" Text="CA state"/>
                        <ComboBox x:Name="CaState" Grid.Row="4" Grid.Column="1" SelectedIndex="0" Margin="0,0,12,8">
                            <ComboBoxItem Content="reportOnly"/>
                            <ComboBoxItem Content="disabled"/>
                            <ComboBoxItem Content="enabled"/>
                        </ComboBox>
                        <CheckBox x:Name="ExcludeExistingCa" Grid.Row="4" Grid.Column="2" Grid.ColumnSpan="2" Content="Ekskluder break-glass gruppen fra eksisterende CA policies" Margin="0,0,0,8"/>
                        <TextBlock Grid.Row="5" Grid.Column="0" Text="Tilladte FIDO2 AAGUIDs"/>
                        <TextBox x:Name="AllowedAaguids" Grid.Row="5" Grid.Column="1" Grid.ColumnSpan="3" Height="54" AcceptsReturn="True" TextWrapping="Wrap" Margin="0,0,0,8"/>
                        <CheckBox x:Name="NoApply" Grid.Row="6" Grid.Column="0" Grid.ColumnSpan="2" Content="Dry-run/NoApply: lav kun plan og rapport" IsChecked="True" Margin="0,0,0,8"/>
                        <CheckBox x:Name="DisableMonitoring" Grid.Row="6" Grid.Column="2" Grid.ColumnSpan="2" Content="Deaktiver Azure Monitor/Log Analytics i denne kørsel" Margin="0,0,0,8"/>
                        <CheckBox x:Name="UseExistingWorkspace" Grid.Row="7" Grid.Column="0" Grid.ColumnSpan="2" Content="Brug eksisterende Log Analytics workspace" Margin="0,0,0,8"/>
                        <TextBlock Grid.Row="8" Grid.Column="0" Text="Subscription ID"/>
                        <TextBox x:Name="SubscriptionId" Grid.Row="8" Grid.Column="1" Margin="0,0,12,8"/>
                        <TextBlock Grid.Row="8" Grid.Column="2" Text="Resource group"/>
                        <TextBox x:Name="ResourceGroupName" Grid.Row="8" Grid.Column="3" Text="rg-breakglass-monitoring" Margin="0,0,0,8"/>
                        <TextBlock Grid.Row="9" Grid.Column="0" Text="Workspace navn"/>
                        <TextBox x:Name="WorkspaceName" Grid.Row="9" Grid.Column="1" Text="law-entra-breakglass" Margin="0,0,12,8"/>
                        <TextBlock Grid.Row="9" Grid.Column="2" Text="Azure region"/>
                        <TextBox x:Name="AzureRegion" Grid.Row="9" Grid.Column="3" Text="westeurope" Margin="0,0,0,8"/>
                        <TextBlock Grid.Row="10" Grid.Column="0" Text="Diagnostic setting"/>
                        <TextBox x:Name="DiagnosticSettingName" Grid.Row="10" Grid.Column="1" Text="diag-entra-activity-to-loganalytics" Margin="0,0,12,8"/>
                        <TextBlock Grid.Row="10" Grid.Column="2" Text="Action group"/>
                        <TextBox x:Name="ActionGroupName" Grid.Row="10" Grid.Column="3" Text="ag-breakglass-alerts" Margin="0,0,0,8"/>
                        <TextBlock Grid.Row="11" Grid.Column="0" Text="Alert email modtagere"/>
                        <TextBox x:Name="AlertEmails" Grid.Row="11" Grid.Column="1" Grid.ColumnSpan="3" Margin="0,0,0,8"/>
                        <CheckBox x:Name="CreateSignInAlert" Grid.Row="12" Grid.Column="0" Grid.ColumnSpan="2" Content="Opret sign-in alert" IsChecked="True" Margin="0,0,0,8"/>
                        <CheckBox x:Name="CreateAuditAlert" Grid.Row="12" Grid.Column="2" Grid.ColumnSpan="2" Content="Opret audit/change alert" IsChecked="True" Margin="0,0,0,8"/>
                    </Grid>
                </ScrollViewer>
            </TabItem>
            <TabItem Header="5. Dry-run">
                <DockPanel Margin="18">
                    <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,10">
                        <Button x:Name="BuildPlanButton" Content="Byg plan" Height="32" Width="100" Margin="0,0,8,0"/>
                        <Button x:Name="ExportPlanButton" Content="Eksporter plan JSON" Height="32" Width="150" Margin="0,0,8,0"/>
                        <Button x:Name="ApplyButton" Content="Apply configuration" Height="32" Width="160"/>
                    </StackPanel>
                    <TextBox x:Name="PlanText" FontFamily="Consolas" IsReadOnly="True" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
                </DockPanel>
            </TabItem>
            <TabItem Header="6. Udfør">
                <DockPanel Margin="18">
                    <ProgressBar x:Name="ProgressBar" DockPanel.Dock="Top" Height="18" IsIndeterminate="False" Margin="0,0,0,10"/>
                    <TextBox x:Name="ExecutionLog" FontFamily="Consolas" IsReadOnly="True" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
                </DockPanel>
            </TabItem>
            <TabItem Header="7. Manuel FIDO2 opsætning">
                <StackPanel Margin="18">
                    <TextBlock FontSize="18" FontWeight="SemiBold" Text="Manuel FIDO2 opsætning"/>
                    <TextBlock TextWrapping="Wrap" Margin="0,8,0,10" Text="Konsulenten skal manuelt registrere FIDO2/FIDO keys for begge konti. Værktøjet opretter ikke nøgler og håndterer ikke PIN eller fysisk opbevaring."/>
                    <TextBlock Text="Checklist:" FontWeight="SemiBold"/>
                    <CheckBox Content="Log ind som/for konto 1 og registrer FIDO2 key"/>
                    <CheckBox Content="Opbevar key efter intern procedure"/>
                    <CheckBox Content="Gentag for konto 2"/>
                    <StackPanel Orientation="Horizontal" Margin="0,14,0,10">
                        <Button x:Name="OpenSecurityInfoButton" Content="Åbn Security Info" Height="32" Width="150" Margin="0,0,8,0"/>
                        <Button x:Name="ValidateFidoButton" Content="Valider FIDO2 metoder" Height="32" Width="170"/>
                    </StackPanel>
                    <ListBox x:Name="FidoResults" FontFamily="Consolas" Height="260"/>
                </StackPanel>
            </TabItem>
            <TabItem Header="8. Validering">
                <DockPanel Margin="18">
                    <Button x:Name="RunValidationButton" DockPanel.Dock="Top" Content="Vis seneste validering" Height="32" Width="160" HorizontalAlignment="Left" Margin="0,0,0,10"/>
                    <ListBox x:Name="ValidationList" FontFamily="Consolas"/>
                </DockPanel>
            </TabItem>
            <TabItem Header="9. Rapport">
                <StackPanel Margin="18">
                    <TextBlock Text="Rapporter genereres automatisk efter kørsel." FontSize="16" FontWeight="SemiBold"/>
                    <TextBlock Text="Outputmappe:" Margin="0,12,0,0"/>
                    <TextBox x:Name="OutputFolderText" IsReadOnly="True" Margin="0,4,0,10"/>
                    <Button x:Name="OpenOutputFolderButton" Content="Åbn outputmappe" Height="32" Width="150"/>
                </StackPanel>
            </TabItem>
        </TabControl>
        <DockPanel Grid.Row="2" Margin="0,12,0,0">
            <Button x:Name="CloseButton" DockPanel.Dock="Right" Content="Luk" Width="90" Height="32"/>
            <Button x:Name="NextButton" DockPanel.Dock="Right" Content="Fortsæt" Width="110" Height="32" Margin="0,0,8,0"/>
            <Button x:Name="BackButton" DockPanel.Dock="Right" Content="Tilbage" Width="110" Height="32" Margin="0,0,8,0"/>
            <Border BorderBrush="#CBD5E1" BorderThickness="1" Background="#FFFFFF" CornerRadius="3" Padding="8,5" VerticalAlignment="Center">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <TextBlock Grid.Column="0" Text="Status:" FontWeight="SemiBold" Margin="0,0,6,0"/>
                    <TextBlock x:Name="BackgroundStatus" Grid.Column="1" Text="Klar" TextTrimming="CharacterEllipsis"/>
                    <ProgressBar x:Name="StatusProgress" Grid.Column="2" Width="90" Height="12" Margin="12,0,12,0" Visibility="Collapsed"/>
                    <TextBlock x:Name="FooterStatus" Grid.Column="3" Text="Step 1 af 9" Foreground="#475569"/>
                </Grid>
            </Border>
        </DockPanel>
    </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $script:MainWindow = [Windows.Markup.XamlReader]::Load($reader)
    foreach ($name in @(
        'UnderstandRisk','ConnectGraphButton','ConnectAzureButton','ConnectAllButton','GraphAccount','TenantId','TenantName','OnMicrosoftDomain','AzureAccount','SubscriptionIdDetected','ConnectionStatus',
        'RunPrecheckButton','PrecheckList','UserPrefix1','UserPrefix2','DisplayName1','DisplayName2','GroupDisplayName','RmauDisplayName','AuthStrengthName','CaPolicyName','CaState',
        'ExcludeExistingCa','AllowedAaguids','NoApply','DisableMonitoring','UseExistingWorkspace','SubscriptionId','ResourceGroupName','WorkspaceName','AzureRegion','DiagnosticSettingName',
        'ActionGroupName','AlertEmails','CreateSignInAlert','CreateAuditAlert','BuildPlanButton','ExportPlanButton','ApplyButton','PlanText','ProgressBar','ExecutionLog','OpenSecurityInfoButton',
        'ValidateFidoButton','FidoResults','RunValidationButton','ValidationList','OutputFolderText','OpenOutputFolderButton','BackButton','NextButton','CloseButton','BackgroundStatus','StatusProgress','FooterStatus','WizardTabs'
    )) {
        $script:Ui[$name] = $script:MainWindow.FindName($name)
    }
    $script:LogTextBox = $script:Ui.ExecutionLog
    $script:Ui.NoApply.IsChecked = [bool]($NoApply -or $true)

    $script:Ui.ConnectGraphButton.Add_Click({
        try {
            Set-UiBusy -Busy $true
            Set-UiStatus -Message 'Starter Graph forbindelse...' -Busy -Log
            if (-not (Ensure-AppModulesFromUi)) { return }
            Set-UiStatus -Message 'Forbinder til Microsoft Graph. Gennemfør loginprompten, hvis den vises...' -Busy -Log
            Connect-AppGraph | Out-Null
            Update-ConnectionStatusUi
            Set-UiStatus -Message 'Graph forbundet.' -Log
        }
        catch {
            Write-SafeError -Message 'Graph forbindelse fejlede.' -ErrorRecord $_
            Set-UiStatus -Message 'Graph forbindelse fejlede.'
            Show-AppMessage -Message ("Graph forbindelse fejlede:`r`n{0}" -f (ConvertTo-RedactedError $_)) -Icon 'Error' | Out-Null
        }
        finally {
            Set-UiBusy -Busy $false
        }
    })

    $script:Ui.ConnectAzureButton.Add_Click({
        try {
            Set-UiBusy -Busy $true
            Set-UiStatus -Message 'Starter Azure forbindelse...' -Busy -Log
            if (-not (Ensure-AppModulesFromUi)) { return }
            Set-UiStatus -Message 'Forbinder til Azure Resource Manager. Gennemfør loginprompten, hvis den vises...' -Busy -Log
            Connect-AppAzure | Out-Null
            Update-ConnectionStatusUi
            Set-UiStatus -Message 'Azure forbundet.' -Log
        }
        catch {
            Write-SafeError -Message 'Azure forbindelse fejlede.' -ErrorRecord $_
            Set-UiStatus -Message 'Azure forbindelse fejlede.'
            Show-AppMessage -Message ("Azure forbindelse fejlede:`r`n{0}" -f (ConvertTo-RedactedError $_)) -Icon 'Error' | Out-Null
        }
        finally {
            Set-UiBusy -Busy $false
        }
    })

    $script:Ui.ConnectAllButton.Add_Click({
        try {
            Set-UiBusy -Busy $true
            if (-not (Connect-AllFromUi)) { return }
            Set-WizardMaxStep -Step 2
            Set-UiStatus -Message 'Forbindelser klar.'
        }
        catch {
            Write-SafeError -Message 'Samlet forbindelse fejlede.' -ErrorRecord $_
            Set-UiStatus -Message 'Samlet forbindelse fejlede.'
            Show-AppMessage -Message ("Samlet forbindelse fejlede:`r`n{0}" -f (ConvertTo-RedactedError $_)) -Icon 'Error' | Out-Null
        }
        finally {
            Set-UiBusy -Busy $false
        }
    })

    $script:Ui.RunPrecheckButton.Add_Click({
        try {
            Set-UiBusy -Busy $true
            Set-UiStatus -Message 'Kører pre-check...' -Busy -Log
            Invoke-PrecheckFromUi | Out-Null
            Set-UiStatus -Message 'Pre-check færdig.'
        }
        catch {
            Write-SafeError -Message 'Pre-check fejlede.' -ErrorRecord $_
            Set-UiStatus -Message 'Pre-check fejlede.'
            Show-AppMessage -Message (ConvertTo-RedactedError $_) -Icon 'Error' | Out-Null
        }
        finally {
            Set-UiBusy -Busy $false
        }
    })

    $script:Ui.BuildPlanButton.Add_Click({
        try {
            Set-UiBusy -Busy $true
            Set-UiStatus -Message 'Bygger dry-run plan...' -Busy -Log
            New-PlanFromUi | Out-Null
            Set-UiStatus -Message 'Dry-run plan bygget.'
        }
        catch {
            Write-SafeError -Message 'Plan kunne ikke bygges.' -ErrorRecord $_
            Set-UiStatus -Message 'Plan kunne ikke bygges.'
            Show-AppMessage -Message (ConvertTo-RedactedError $_) -Icon 'Error' | Out-Null
        }
        finally {
            Set-UiBusy -Busy $false
        }
    })

    $script:Ui.ExportPlanButton.Add_Click({
        try {
            Set-UiBusy -Busy $true
            Set-UiStatus -Message 'Eksporterer dry-run plan til JSON...' -Busy -Log
            $config = Build-ConfigFromUi
            $plan = New-Plan -Config $config
            $output = if ($script:SessionOutputFolder) { $script:SessionOutputFolder } else { New-OutputFolder -TenantId $(if ($script:State.TenantId) { $script:State.TenantId } else { 'UnknownTenant' }) }
            $path = Join-Path -Path $output -ChildPath 'plan.json'
            Export-JsonSafe -InputObject $plan -Path $path | Out-Null
            $script:Ui.OutputFolderText.Text = $output
            Set-UiStatus -Message "Plan eksporteret: $path"
            Show-AppMessage -Message "Plan gemt:`r`n$path" | Out-Null
        }
        catch {
            Write-SafeError -Message 'Plan eksport fejlede.' -ErrorRecord $_
            Set-UiStatus -Message 'Plan eksport fejlede.'
            Show-AppMessage -Message (ConvertTo-RedactedError $_) -Icon 'Error' | Out-Null
        }
        finally {
            Set-UiBusy -Busy $false
        }
    })

    $script:Ui.ApplyButton.Add_Click({
        $workerStarted = $false
        try {
            Set-UiBusy -Busy $true
            if (-not [bool] $script:Ui.UnderstandRisk.IsChecked) {
                Show-AppMessage -Message 'Du skal bekræfte sikkerhedsforståelsen på Velkommen-fanen først.' -Icon 'Warning' | Out-Null
                return
            }
            $config = Build-ConfigFromUi
            if ($config.CaState -eq 'enabled') {
                if ((Show-AppMessage -Message 'Du har valgt at oprette Conditional Access policy som ENABLED. Dette er sikkerhedskritisk. Fortsæt?' -Buttons 'YesNo' -Icon 'Warning') -ne 'Yes') {
                    return
                }
            }
            Set-UiStatus -Message 'Starter apply/rapportering i separat PowerShell worker...' -Busy -Log
            Start-WorkerApply -Config $config
            $workerStarted = $true
            $script:Ui.ProgressBar.IsIndeterminate = $true
            Set-UiStatus -Message 'Worker kører. Følg live-loggen på Udfør-fanen...' -Busy
            Set-WizardMaxStep -Step 5
            Set-WizardStep -Step 5
        }
        catch {
            Write-SafeError -Message 'Apply fejlede.' -ErrorRecord $_
            Set-UiStatus -Message 'Apply fejlede.'
            Show-AppMessage -Message (ConvertTo-RedactedError $_) -Icon 'Error' | Out-Null
        }
        finally {
            if (-not $workerStarted) {
                Set-UiBusy -Busy $false
            }
        }
    })

    $script:Ui.UnderstandRisk.Add_Checked({
        Set-WizardMaxStep -Step 1
        Set-UiStatus -Message 'Sikkerhedsbekræftelse registreret. Tryk Fortsæt.'
    })

    $script:Ui.UnderstandRisk.Add_Unchecked({
        $script:WizardMaxStep = 0
        Set-WizardStep -Step 0
    })

    $script:Ui.BackButton.Add_Click({
        Set-WizardStep -Step ($script:Ui.WizardTabs.SelectedIndex - 1)
    })

    $script:Ui.NextButton.Add_Click({
        try {
            Move-WizardNext
        }
        catch {
            Write-SafeError -Message 'Wizard navigation fejlede.' -ErrorRecord $_
            Show-AppMessage -Message (ConvertTo-RedactedError $_) -Icon 'Error' | Out-Null
        }
    })

    $script:Ui.WizardTabs.Add_SelectionChanged({
        if ($script:WizardInternalNavigation) { return }
        if ($script:Ui.WizardTabs.SelectedIndex -gt $script:WizardMaxStep) {
            Show-AppMessage -Message 'Gennemfør de tidligere wizard-steps før du går videre.' -Icon 'Warning' | Out-Null
            Set-WizardStep -Step $script:WizardMaxStep
            return
        }
        Update-WizardNavigation
    })

    $script:Ui.OpenSecurityInfoButton.Add_Click({
        Start-Process 'https://mysignins.microsoft.com/security-info'
    })

    $script:Ui.ValidateFidoButton.Add_Click({
        try {
            $config = Build-ConfigFromUi
            $domain = if ($script:State.OnMicrosoftDomain) { $script:State.OnMicrosoftDomain } else { throw 'onmicrosoft.com domæne er ikke detekteret endnu.' }
            $users = @(
                Get-BreakGlassUser -UserPrincipalName (ConvertTo-BreakGlassUpn -Prefix $config.UserPrefix1 -OnMicrosoftDomain $domain),
                Get-BreakGlassUser -UserPrincipalName (ConvertTo-BreakGlassUpn -Prefix $config.UserPrefix2 -OnMicrosoftDomain $domain)
            ) | Where-Object { $_ }
            $results = Test-BreakGlassFido2Registration -Users $users
            $script:Ui.FidoResults.Items.Clear()
            foreach ($result in $results) {
                $script:Ui.FidoResults.Items.Add(('{0}: FIDO2={1}, Count={2}' -f $result.UserPrincipalName, $result.HasFido2, $result.Count)) | Out-Null
            }
        }
        catch {
            Write-SafeError -Message 'FIDO2 validering fejlede.' -ErrorRecord $_
            Show-AppMessage -Message (ConvertTo-RedactedError $_) -Icon 'Error' | Out-Null
        }
    })

    $script:Ui.RunValidationButton.Add_Click({
        Update-ValidationUi -Results $script:State.ValidationResults
    })

    $script:Ui.OpenOutputFolderButton.Add_Click({
        if ($script:SessionOutputFolder -and (Test-Path -Path $script:SessionOutputFolder)) {
            Start-Process explorer.exe -ArgumentList $script:SessionOutputFolder
        }
    })

    $script:Ui.CloseButton.Add_Click({ $script:MainWindow.Close() })

    $script:LogPollTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:LogPollTimer.Interval = [TimeSpan]::FromSeconds(1)
    $script:LogPollTimer.Add_Tick({
        Sync-LogView
        if ($script:ModuleWorkerProcess) {
            if ($script:ModuleWorkerLogFile -and (Test-Path -LiteralPath $script:ModuleWorkerLogFile)) {
                try {
                    $lastLine = Get-Content -LiteralPath $script:ModuleWorkerLogFile -Tail 1 -ErrorAction Stop
                    if ($lastLine) {
                        Set-UiStatus -Message ("Modul-worker: {0}" -f $lastLine) -Busy
                    }
                }
                catch {
                    # Module worker log polling is best-effort.
                }
            }
            if ($script:ModuleWorkerProcess.HasExited) {
                $moduleExitCode = $script:ModuleWorkerProcess.ExitCode
                $script:ModuleWorkerProcess.Dispose()
                $script:ModuleWorkerProcess = $null
                if ($moduleExitCode -eq 0) {
                    Set-UiStatus -Message 'Moduler er klar. Tryk forbind-knappen igen for at logge ind.'
                }
                elseif ($moduleExitCode -eq 20) {
                    Set-UiStatus -Message 'Modulinstallation blev afbrudt. Connect kan ikke fortsætte før modulerne findes.'
                }
                else {
                    Set-UiStatus -Message ("Modul-worker fejlede med exit code {0}. Se module-worker.log." -f $moduleExitCode)
                }
                Set-UiBusy -Busy $false
            }
        }
        if ($script:WorkerProcess -and $script:WorkerProcess.HasExited) {
            $script:LogPollTimer.Stop()
            Sync-LogView
            $exitCode = $script:WorkerProcess.ExitCode
            $script:WorkerProcess.Dispose()
            $script:WorkerProcess = $null
            $script:Ui.ProgressBar.IsIndeterminate = $false
            Set-UiStatus -Message $(if ($exitCode -eq 0) { 'Worker færdig. Rapport er genereret.' } else { "Worker fejlede med exit code $exitCode." })
            Set-UiBusy -Busy $false
            $script:Ui.OutputFolderText.Text = $script:SessionOutputFolder
            if ($exitCode -eq 0) {
                Set-WizardMaxStep -Step 8
            }
        }
    })
    $script:LogPollTimer.Start()

    Update-ConnectionStatusUi
    Update-WizardNavigation
    $script:MainWindow.ShowDialog() | Out-Null
}

try {
    Initialize-AppState
    if ($ModuleWorkerMode) {
        Invoke-ModulePreparationWorkerMode -LogPath $ModuleWorkerLogPath
    }
    elseif ($WorkerMode) {
        Invoke-WorkerMode -Path $WorkerConfigPath
    }
    else {
        Start-BreakGlassWizard
    }
}
catch {
    Write-SafeError -Message 'Uventet fejl.' -ErrorRecord $_
    if (-not $WorkerMode -and -not $ModuleWorkerMode) {
        Show-AppMessage -Message ("Uventet fejl:`r`n{0}" -f (ConvertTo-RedactedError $_)) -Icon 'Error' | Out-Null
    }
    throw
}

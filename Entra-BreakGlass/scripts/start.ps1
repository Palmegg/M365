param(
    [switch] $Mock,
    [switch] $DebugMode,
    [switch] $NoCompileBanner
)

$isPowerShell7 = ($PSVersionTable.PSEdition -eq 'Core') -and ($PSVersionTable.PSVersion.Major -ge 7)
$isStaThread = [System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA

if ((-not $isPowerShell7) -or (-not $isStaThread)) {
    $pwshCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    $pwshPath = if ($pwshCommand) {
        $pwshCommand.Source
    }
    else {
        $candidate = Join-Path -Path $env:ProgramFiles -ChildPath 'PowerShell\7\pwsh.exe'
        if (Test-Path -LiteralPath $candidate) { $candidate } else { $null }
    }

    if (-not $pwshPath) {
        throw 'PowerShell 7 er påkrævet for dette WPF/Graph værktøj. Installer PowerShell 7 og kør scriptet igen.'
    }

    $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
    $temporaryScriptPath = $null
    if ([string]::IsNullOrWhiteSpace($scriptPath) -or -not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        $scriptText = [string]$MyInvocation.MyCommand.Definition
        if ([string]::IsNullOrWhiteSpace($scriptText)) {
            throw 'Kunne ikke relaunch konfiguratoren i PowerShell 7 -STA, fordi scriptet ikke har en filsti. Gem BreakGlassConfigurator.ps1 lokalt og kør den med pwsh -STA.'
        }
        $temporaryScriptPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('BreakGlassConfigurator-{0}.ps1' -f ([guid]::NewGuid().ToString('N')))
        Set-Content -LiteralPath $temporaryScriptPath -Value $scriptText -Encoding utf8BOM
        $scriptPath = $temporaryScriptPath
    }

    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-STA',
        '-File', $scriptPath
    )
    if ($Mock) { $arguments += '-Mock' }
    if ($DebugMode) { $arguments += '-DebugMode' }
    if ($NoCompileBanner) { $arguments += '-NoCompileBanner' }

    try {
        & $pwshPath @arguments
    }
    finally {
        if ($temporaryScriptPath) {
            Remove-Item -LiteralPath $temporaryScriptPath -Force -ErrorAction SilentlyContinue
        }
    }
    return
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

Write-Host 'Entra Break Glass Configurator bruger dette PowerShell-vindue som worker/log-konsol.' -ForegroundColor Green

$sync = [Hashtable]::Synchronized(@{})
$sync.configs = @{}

$sync.App = @{
    Name       = 'Entra Break Glass Configurator'
    Version    = '2.0.0'
    Mock       = [bool] $Mock
    OutputRoot = '.\Output'
}

$sync.State = [Hashtable]::Synchronized(@{
    GraphConnected     = $false
    GraphAccount       = ''
    TenantId           = ''
    TenantDisplayName  = ''
    OnMicrosoftDomain  = ''
    GraphScopes        = @()
    Discovery          = $null
    Plan               = $null
    Phase1Result       = $null
    Result             = $null
    OutputFolder       = ''
    HandoffPath        = ''
    CreatedPasswords   = @()
    ActiveGlobalAdministrators = @()
    Warnings           = @()
    Errors             = @()
    Language           = 'da-DK'
    NeutralNameIndex   = 0
    StartMode          = 'Phase1'
})

$sync.UI = [Hashtable]::Synchronized(@{
    CurrentStep       = 'Velkommen'
    ProcessRunning    = $false
    ConfigVisited     = $false
    CurrentPowerShell = $null
    CurrentAsync      = $null
    StopRequested     = $false
    AllowForcedClose   = $false
    CloseInProgress    = $false
    ProcessStarted    = $null
})

$sync.Paths = @{
    Root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
}

$sync.App.OutputRoot = Join-Path -Path $sync.Paths.Root -ChildPath 'Output'
New-Item -ItemType Directory -Force -Path $sync.App.OutputRoot | Out-Null

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$sync.Paths.LogFile = Join-Path -Path $sync.App.OutputRoot -ChildPath "BreakGlassConfigurator_$timestamp.log"

if ($DebugMode) {
    $DebugPreference = 'Continue'
}

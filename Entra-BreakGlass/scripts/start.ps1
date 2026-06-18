param(
    [switch] $Mock,
    [switch] $DebugMode,
    [switch] $NoCompileBanner
)

if (($PSVersionTable.PSEdition -ne 'Core') -or ($PSVersionTable.PSVersion.Major -lt 7)) {
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
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-STA',
        '-File', $scriptPath
    )
    if ($Mock) { $arguments += '-Mock' }
    if ($DebugMode) { $arguments += '-DebugMode' }
    if ($NoCompileBanner) { $arguments += '-NoCompileBanner' }

    & $pwshPath @arguments
    return
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

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

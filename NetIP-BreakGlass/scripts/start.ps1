param(
    [switch] $Mock,
    [switch] $DebugMode,
    [switch] $NoCompileBanner
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

$sync = [Hashtable]::Synchronized(@{})
$sync.configs = @{}

$sync.App = @{
    Name       = 'NetIP Entra Break Glass Configurator'
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
    Result             = $null
    OutputFolder       = ''
    HandoffPath        = ''
    CreatedPasswords   = @()
    Warnings           = @()
    Errors             = @()
})

$sync.UI = [Hashtable]::Synchronized(@{
    CurrentStep    = 'Velkommen'
    ProcessRunning = $false
})

$sync.Paths = @{
    Root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
}

$sync.App.OutputRoot = Join-Path -Path $sync.Paths.Root -ChildPath 'Output'
New-Item -ItemType Directory -Force -Path $sync.App.OutputRoot | Out-Null

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$sync.Paths.LogFile = Join-Path -Path $sync.App.OutputRoot -ChildPath "NetIPBreakGlass_$timestamp.log"

if ($DebugMode) {
    $DebugPreference = 'Continue'
}

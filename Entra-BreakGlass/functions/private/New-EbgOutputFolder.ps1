function New-EbgOutputFolder {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $TenantId)

    $safeTenant = if ([string]::IsNullOrWhiteSpace($TenantId)) { 'UnknownTenant' } else { $TenantId }
    $folder = Join-Path -Path $sync.App.OutputRoot -ChildPath ('BreakGlass-{0}-{1}' -f $safeTenant, (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    $sync.State.OutputFolder = $folder
    return $folder
}
function Write-EbgLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Message,
        [ValidateSet('INFO','WARN','ERROR','PASS','PLAN','DELETE')]
        [string] $Level = 'INFO'
    )

    $safeMessage = ConvertTo-EbgRedactedError -ErrorRecord $Message
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $safeMessage
    $logFile = Get-EbgObjectPropertyValue -InputObject $sync.Paths -Name 'LogFile'
    if ($logFile) {
        Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    }
    try {
        Write-Host $line
    }
    catch {
        # Console logging is best-effort so GUI/background work is never blocked by host output.
    }
    if ($sync.WPFExecutionLog -and $sync.Form -and $sync.Form.Dispatcher) {
        Invoke-EbgUIThread -ScriptBlock {
            param([string] $uiLine)

            if ($sync.WPFExecutionLog) {
                $sync.WPFExecutionLog.AppendText($uiLine + [Environment]::NewLine)
                $sync.WPFExecutionLog.ScrollToEnd()
            }
            if ($sync.WPFPhase2Log) {
                $sync.WPFPhase2Log.AppendText($uiLine + [Environment]::NewLine)
                $sync.WPFPhase2Log.ScrollToEnd()
            }
        } -ArgumentList @($line)
    }
}

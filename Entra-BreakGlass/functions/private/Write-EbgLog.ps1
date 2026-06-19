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
    if ($sync.WPFExecutionLog) {
        $appendLog = {
            $sync.WPFExecutionLog.AppendText($message + [Environment]::NewLine)
            $sync.WPFExecutionLog.ScrollToEnd()
            if ($sync.WPFPhase2Log) {
                $sync.WPFPhase2Log.AppendText($message + [Environment]::NewLine)
                $sync.WPFPhase2Log.ScrollToEnd()
            }
        }
        $message = $line
        if ($sync.WPFExecutionLog.Dispatcher.CheckAccess()) {
            & $appendLog | Out-Null
        }
        else {
            [void]$sync.WPFExecutionLog.Dispatcher.BeginInvoke([System.Action]$appendLog)
        }
    }
}

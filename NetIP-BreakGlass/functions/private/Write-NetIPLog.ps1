function Write-NetIPLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Message,
        [ValidateSet('INFO','WARN','ERROR','PASS','PLAN','DELETE')]
        [string] $Level = 'INFO'
    )

    $safeMessage = ConvertTo-NetIPRedactedError -ErrorRecord $Message
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $safeMessage
    $logFile = Get-NetIPObjectPropertyValue -InputObject $sync.Paths -Name 'LogFile'
    if ($logFile) {
        Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    }
    if ($sync.WPFExecutionLog) {
        $appendLog = {
            $sync.WPFExecutionLog.AppendText($message + [Environment]::NewLine)
            $sync.WPFExecutionLog.ScrollToEnd()
        }
        $message = $line
        if ($sync.WPFExecutionLog.Dispatcher.CheckAccess()) {
            & $appendLog
        }
        else {
            $sync.WPFExecutionLog.Dispatcher.Invoke([System.Action]$appendLog)
        }
    }
}

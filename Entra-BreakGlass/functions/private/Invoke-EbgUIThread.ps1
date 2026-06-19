function Invoke-EbgUIThread {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock,

        [object[]] $ArgumentList = @(),

        [switch] $Wait
    )

    if (-not $sync.Form -or -not $sync.Form.Dispatcher) {
        return
    }

    $dispatcher = $sync.Form.Dispatcher
    $uiScript = $ScriptBlock.GetNewClosure()
    $uiArguments = @($ArgumentList)
    $action = [System.Action]{
        try {
            & $uiScript @uiArguments
        }
        catch {
            try {
                $message = ConvertTo-EbgRedactedError -ErrorRecord $_
                $logFile = Get-EbgObjectPropertyValue -InputObject $sync.Paths -Name 'LogFile'
                if ($logFile) {
                    $line = '[{0}] [WARN] UI update failed: {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $message
                    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
                }
            }
            catch {
                # UI update failures must never crash the WPF shell.
            }
        }
    }.GetNewClosure()

    try {
        if ($dispatcher.CheckAccess()) {
            & $action
        }
        elseif ($Wait) {
            [void]$dispatcher.Invoke($action)
        }
        else {
            [void]$dispatcher.BeginInvoke($action)
        }
    }
    catch {
        try {
            $message = ConvertTo-EbgRedactedError -ErrorRecord $_
            $logFile = Get-EbgObjectPropertyValue -InputObject $sync.Paths -Name 'LogFile'
            if ($logFile) {
                $line = '[{0}] [WARN] UI dispatch failed: {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $message
                Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
            }
        }
        catch {
            # Last-resort guard.
        }
    }
}

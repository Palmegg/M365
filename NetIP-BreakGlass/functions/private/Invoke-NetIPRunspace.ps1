function Invoke-NetIPRunspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock] $ScriptBlock,
        [object[]] $ArgumentList = @()
    )

    if ($sync.UI.ProcessRunning) {
        [System.Windows.MessageBox]::Show('Der kører allerede en opgave. Vent til den er færdig.', $sync.App.Name, 'OK', 'Information') | Out-Null
        return
    }
    $sync.UI.ProcessRunning = $true
    if ($sync.WPFProgressBar) {
        $sync.WPFProgressBar.Dispatcher.Invoke([action]{ $sync.WPFProgressBar.IsIndeterminate = $true })
    }
    $ps = [PowerShell]::Create()
    $ps.RunspacePool = $sync.Runspace
    [void]$ps.AddScript({
        param($innerScript, $innerArgs)
        try {
            & $innerScript @innerArgs
        }
        catch {
            $friendly = 'Der opstod en fejl. Se logfilen for tekniske detaljer.'
            Write-NetIPLog -Level ERROR -Message (ConvertTo-NetIPRedactedError -ErrorRecord $_)
            $sync.State.Errors += $friendly
            if ($sync.Form) {
                $sync.Form.Dispatcher.Invoke([action]{
                    $sync.WPFStatusText.Text = $friendly
                    [System.Windows.MessageBox]::Show($friendly, $sync.App.Name, 'OK', 'Error') | Out-Null
                })
            }
        }
        finally {
            $sync.UI.ProcessRunning = $false
            if ($sync.Form) {
                $sync.Form.Dispatcher.Invoke([action]{
                    $sync.WPFProgressBar.IsIndeterminate = $false
                    Update-NetIPUIState
                })
            }
        }
    }).AddArgument($ScriptBlock).AddArgument($ArgumentList) | Out-Null
    [void]$ps.BeginInvoke()
}

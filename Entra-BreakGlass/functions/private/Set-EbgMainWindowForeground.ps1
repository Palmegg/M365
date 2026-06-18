function Set-EbgMainWindowForeground {
    [CmdletBinding()]
    param()

    if (-not $sync.Form) { return }

    $activateWindow = {
        try {
            if ($sync.Form.WindowState -eq 'Minimized') {
                $previousWindowState = [string]$sync.UI.PreGraphLoginWindowState
                if ([string]::IsNullOrWhiteSpace($previousWindowState)) {
                    $previousWindowState = 'Normal'
                }
                $sync.Form.WindowState = $previousWindowState
                $sync.UI.PreGraphLoginWindowState = ''
                $sync.UI.GraphLoginMinimizedWindow = $false
            }

            if (-not ('EbgNativeWindow' -as [type])) {
                Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class EbgNativeWindow
{
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
'@ -ErrorAction SilentlyContinue
            }

            $sync.Form.Topmost = $true
            [void]$sync.Form.Activate()
            [void]$sync.Form.Focus()

            $helper = New-Object System.Windows.Interop.WindowInteropHelper($sync.Form)
            if ($helper.Handle -ne [IntPtr]::Zero -and ('EbgNativeWindow' -as [type])) {
                [void][EbgNativeWindow]::SetForegroundWindow($helper.Handle)
            }
        }
        finally {
            $sync.Form.Topmost = $false
        }
    }

    if ($sync.Form.Dispatcher.CheckAccess()) {
        & $activateWindow
    }
    else {
        [void]$sync.Form.Dispatcher.Invoke([System.Action]$activateWindow)
    }
}

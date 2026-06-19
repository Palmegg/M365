function Invoke-EbgDoEvents {
    [CmdletBinding()]
    param()

    try {
        $applicationType = 'System.Windows.Forms.Application' -as [type]
        if (-not $applicationType) {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
            $applicationType = 'System.Windows.Forms.Application' -as [type]
        }
        if ($applicationType) {
            [System.Windows.Forms.Application]::DoEvents()
        }
    }
    catch {
        # DoEvents is only an opportunistic UI refresh; never fail work because of it.
    }
}

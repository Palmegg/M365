function Invoke-EbgOpenUrl {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Url)

    try {
        Start-Process -FilePath $Url | Out-Null
        Write-EbgLog -Message "Åbnede link: $Url"
    }
    catch {
        $message = ConvertTo-EbgRedactedError -ErrorRecord $_
        Write-EbgLog -Level ERROR -Message $message
        [System.Windows.MessageBox]::Show("Kunne ikke åbne linket: $Url`n`n$message", $sync.App.Name, 'OK', 'Error') | Out-Null
    }
}

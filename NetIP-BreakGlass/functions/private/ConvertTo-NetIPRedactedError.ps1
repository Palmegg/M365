function ConvertTo-NetIPRedactedError {
    [CmdletBinding()]
    param([AllowNull()] $ErrorRecord)

    $text = if ($null -eq $ErrorRecord) { '' } else { [string] $ErrorRecord }
    $patterns = @(
        '(?i)Authorization:\s*Bearer\s+[A-Za-z0-9\._\-]+',
        '(?i)(access_token|refresh_token|client_secret|password)"?\s*[:=]\s*"[^"]+"',
        'eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+'
    )
    foreach ($pattern in $patterns) {
        $text = [regex]::Replace($text, $pattern, '[REDACTED]')
    }
    return $text
}

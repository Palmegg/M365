function New-EbgPkcePair {
    [CmdletBinding()]
    param()

    $bytes = [byte[]]::new(64)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $verifier = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $challengeBytes = $sha.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($verifier))
    }
    finally {
        $sha.Dispose()
    }
    $challenge = [Convert]::ToBase64String($challengeBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    return [pscustomobject]@{
        Verifier  = $verifier
        Challenge = $challenge
    }
}

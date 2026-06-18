function Connect-EbgGraphBrowser {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]] $Scopes)

    $clientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
    $tenant = 'organizations'
    $pkce = New-EbgPkcePair
    $state = [guid]::NewGuid().ToString('N')
    $listener = [System.Net.HttpListener]::new()
    $port = $null

    foreach ($candidate in (Get-Random -InputObject (49152..65535) -Count 40)) {
        $prefix = "http://localhost:$candidate/"
        try {
            $listener.Prefixes.Clear()
            $listener.Prefixes.Add($prefix)
            $listener.Start()
            $port = $candidate
            break
        }
        catch {
            try { $listener.Close() } catch {}
            $listener = [System.Net.HttpListener]::new()
        }
    }
    if (-not $port) {
        throw 'Kunne ikke starte lokal login-listener på localhost.'
    }

    $redirectUri = "http://localhost:$port/"
    $scope = (@($Scopes) + @('offline_access','openid','profile') | Select-Object -Unique) -join ' '
    $authorizeUri = 'https://login.microsoftonline.com/{0}/oauth2/v2.0/authorize?client_id={1}&response_type=code&redirect_uri={2}&response_mode=query&scope={3}&code_challenge={4}&code_challenge_method=S256&prompt=login&state={5}' -f @(
        [Uri]::EscapeDataString($tenant),
        [Uri]::EscapeDataString($clientId),
        [Uri]::EscapeDataString($redirectUri),
        [Uri]::EscapeDataString($scope),
        [Uri]::EscapeDataString($pkce.Challenge),
        [Uri]::EscapeDataString($state)
    )

    try {
        Start-Process $authorizeUri | Out-Null
        $async = $listener.BeginGetContext($null, $null)
        $started = Get-Date
        while (-not $async.AsyncWaitHandle.WaitOne(250)) {
            if (((Get-Date) - $started).TotalMinutes -ge 5) {
                throw 'Microsoft Graph login timed out efter 5 minutter. Prøv igen, og tjek browser-loginvinduet.'
            }
        }
        $context = $listener.EndGetContext($async)
        $request = $context.Request
        $response = $context.Response
        $code = [string]$request.QueryString['code']
        $returnedState = [string]$request.QueryString['state']
        $errorCode = [string]$request.QueryString['error']
        $errorDescription = [string]$request.QueryString['error_description']

        $html = '<html><body style="font-family:Segoe UI,Arial,sans-serif;margin:40px"><h2>Authentication complete.</h2><p>You can return to the Entra Break Glass Configurator.</p><p>Close this browser tab.</p></body></html>'
        if ($errorCode) {
            $html = '<html><body style="font-family:Segoe UI,Arial,sans-serif;margin:40px"><h2>Authentication failed.</h2><p>You can return to the Entra Break Glass Configurator.</p></body></html>'
        }
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($html)
        $response.ContentType = 'text/html; charset=utf-8'
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.OutputStream.Close()

        if ($errorCode) {
            throw "Microsoft login fejlede: $errorCode $errorDescription"
        }
        if ([string]::IsNullOrWhiteSpace($code)) {
            throw 'Microsoft login returnerede ikke en authorization code.'
        }
        if ($returnedState -ne $state) {
            throw 'Microsoft login state validering fejlede.'
        }

        $tokenUri = "https://login.microsoftonline.com/$tenant/oauth2/v2.0/token"
        $body = @{
            client_id     = $clientId
            scope         = $scope
            code          = $code
            redirect_uri  = $redirectUri
            grant_type    = 'authorization_code'
            code_verifier = $pkce.Verifier
        }
        $token = Invoke-RestMethod -Method POST -Uri $tokenUri -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
        $idToken = [string](Get-EbgObjectPropertyValue -InputObject $token -Name 'id_token')
        $accessToken = [string](Get-EbgObjectPropertyValue -InputObject $token -Name 'access_token')
        $refreshToken = [string](Get-EbgObjectPropertyValue -InputObject $token -Name 'refresh_token')
        $expiresIn = [int](Get-EbgObjectPropertyValue -InputObject $token -Name 'expires_in')
        $claims = if ($idToken) { ConvertFrom-EbgJwt -Token $idToken } else { $null }
        $preferredUsername = [string](Get-EbgObjectPropertyValue -InputObject $claims -Name 'preferred_username')
        $upn = [string](Get-EbgObjectPropertyValue -InputObject $claims -Name 'upn')
        $tenantId = [string](Get-EbgObjectPropertyValue -InputObject $claims -Name 'tid')
        return [pscustomobject]@{
            ClientId     = $clientId
            AccessToken  = $accessToken
            RefreshToken = $refreshToken
            ExpiresOn    = (Get-Date).ToUniversalTime().AddSeconds($expiresIn - 120)
            Account      = if ($preferredUsername) { $preferredUsername } elseif ($upn) { $upn } else { '' }
            TenantId     = $tenantId
            Scopes       = @($Scopes)
        }
    }
    finally {
        if ($listener) {
            try { $listener.Stop() } catch {}
            try { $listener.Close() } catch {}
        }
    }
}

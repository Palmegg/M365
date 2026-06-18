function Get-EbgAAGUIDSourceUserPrincipalName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable] $Config)

    return $sync.Form.Dispatcher.Invoke([func[string]]{
        $custom = if ($sync.WPFAAGUIDCustomUser) { $sync.WPFAAGUIDCustomUser.Text.Trim() } else { '' }
        if ([string]::IsNullOrWhiteSpace($custom)) {
            throw 'Angiv UPN på den bruger der har den registrerede FIDO2/passkey, som AAGUID skal hentes fra.'
        }
        if ($custom -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
            throw "AAGUID kildebrugeren skal angives som fuldt UPN, fx user@tenant.onmicrosoft.com. Værdi: $custom"
        }
        $custom
    })
}

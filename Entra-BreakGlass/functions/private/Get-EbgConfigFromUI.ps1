function Get-EbgConfigFromUI {
    [CmdletBinding()]
    param()

    return $sync.Form.Dispatcher.Invoke([func[hashtable]]{
        $resumePhase2 = [string]$sync.State.StartMode -eq 'Phase2'
        $userPrefix1 = if ($resumePhase2 -and $sync.WPFPhase2UserPrefix1 -and -not [string]::IsNullOrWhiteSpace($sync.WPFPhase2UserPrefix1.Text)) { $sync.WPFPhase2UserPrefix1.Text.Trim() } else { $sync.WPFUserPrefix1.Text.Trim() }
        $userPrefix2 = if ($resumePhase2 -and $sync.WPFPhase2UserPrefix2 -and -not [string]::IsNullOrWhiteSpace($sync.WPFPhase2UserPrefix2.Text)) { $sync.WPFPhase2UserPrefix2.Text.Trim() } else { $sync.WPFUserPrefix2.Text.Trim() }
        @{
            DisplayName1     = $sync.WPFDisplayName1.Text.Trim()
            UserPrefix1      = $userPrefix1
            DisplayName2     = $sync.WPFDisplayName2.Text.Trim()
            UserPrefix2      = $userPrefix2
            GroupName        = $sync.WPFGroupName.Text.Trim()
            GroupDescription = $sync.WPFGroupDescription.Text.Trim()
            AuthenticationStrengthName = $sync.WPFAuthenticationStrengthName.Text.Trim()
            AuthenticationStrengthDescription = [string]$sync.configs.appsettings.authenticationStrengthDescription
            BreakGlassCAPolicyName = $sync.WPFBreakGlassCAPolicyName.Text.Trim()
            AAGUIDs = @(ConvertFrom-EbgAAGUIDText -Text $sync.WPFAAGUIDs.Text)
            CreateUsers      = [bool]$sync.WPFCreateUsers.IsChecked
            CreateGroup      = [bool]$sync.WPFCreateGroup.IsChecked
            AddUsersToGroup  = [bool]$sync.WPFAddUsersToGroup.IsChecked
            DisableAdminSSPR = [bool]$sync.WPFDisableAdminSSPR.IsChecked
            PatchCAPolicies  = [bool]$sync.WPFPatchCAPolicies.IsChecked
            CreateAuthenticationStrength = $true
            CreateBreakGlassCAPolicy = $true
            EnableBreakGlassCAPolicy = $false
        }
    })
}

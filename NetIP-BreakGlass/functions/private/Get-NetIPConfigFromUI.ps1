function Get-NetIPConfigFromUI {
    [CmdletBinding()]
    param()

    return $sync.Form.Dispatcher.Invoke([func[hashtable]]{
        @{
            DisplayName1     = $sync.WPFDisplayName1.Text.Trim()
            UserPrefix1      = $sync.WPFUserPrefix1.Text.Trim()
            DisplayName2     = $sync.WPFDisplayName2.Text.Trim()
            UserPrefix2      = $sync.WPFUserPrefix2.Text.Trim()
            GroupName        = $sync.WPFGroupName.Text.Trim()
            GroupDescription = $sync.WPFGroupDescription.Text.Trim()
            CreateUsers      = [bool]$sync.WPFCreateUsers.IsChecked
            CreateGroup      = [bool]$sync.WPFCreateGroup.IsChecked
            AddUsersToGroup  = [bool]$sync.WPFAddUsersToGroup.IsChecked
            DisableAdminSSPR = [bool]$sync.WPFDisableAdminSSPR.IsChecked
            PatchCAPolicies  = [bool]$sync.WPFPatchCAPolicies.IsChecked
        }
    })
}

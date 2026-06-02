#requires -Version 5.1
<#
.SYNOPSIS
    WPF tool for configuring and documenting Microsoft Entra ID breakglass accounts.

.DESCRIPTION
    This script uses Microsoft Graph PowerShell only. It never deletes users, groups,
    or Conditional Access policies. Every change is gated by a confirmation prompt,
    supports dry-run mode, and is written to a local log file.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AppName = 'Microsoft Entra Breakglass Setup'
$script:LogDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'logs'
$script:ReportDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'reports'
$script:LogFile = Join-Path -Path $script:LogDirectory -ChildPath ("BreakglassSetup_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$script:RunResults = New-Object System.Collections.Generic.List[string]
$script:CreatedUserSecrets = New-Object System.Collections.Generic.List[object]
$script:DryRun = $true
$script:MainWindow = $null
$script:LogTextBox = $null

New-Item -ItemType Directory -Force -Path $script:LogDirectory, $script:ReportDirectory | Out-Null

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'DRYRUN')]
        [string] $Level = 'INFO'
    )

    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $script:LogFile -Value $line -Encoding UTF8

    if ($script:LogTextBox) {
        $script:LogTextBox.AppendText($line + [Environment]::NewLine)
        $script:LogTextBox.ScrollToEnd()
    }
}

function Add-RunResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Message)

    $script:RunResults.Add($Message) | Out-Null
    Write-Log -Message $Message
}

function Show-Warning {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Message)

    Write-Log -Message $Message -Level WARN
    [System.Windows.MessageBox]::Show($Message, $script:AppName, 'OK', 'Warning') | Out-Null
}

function Confirm-Change {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Message)

    if ($script:DryRun) {
        Write-Log -Message "Dry-run: would ask for confirmation: $Message" -Level DRYRUN
        return $false
    }

    $answer = [System.Windows.MessageBox]::Show(
        $Message,
        "$($script:AppName) - confirm change",
        'YesNo',
        'Question'
    )

    return ($answer -eq 'Yes')
}

function Invoke-RequiredModuleCheck {
    [CmdletBinding()]
    param()

    $requiredModules = @(
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.Users',
        'Microsoft.Graph.Groups',
        'Microsoft.Graph.Identity.DirectoryManagement'
    )

    foreach ($moduleName in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $moduleName)) {
            throw "Missing PowerShell module '$moduleName'. Install Microsoft.Graph with: Install-Module Microsoft.Graph -Scope CurrentUser"
        }

        Import-Module $moduleName -ErrorAction Stop
    }
}

function Connect-Graph {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $TenantName
    )

    Invoke-RequiredModuleCheck

    $scopes = @(
        'Directory.Read.All',
        'Domain.Read.All',
        'User.ReadWrite.All',
        'Group.ReadWrite.All',
        'Policy.ReadWrite.Authorization'
    )

    Write-Log -Message "Connecting to Microsoft Graph with delegated scopes: $($scopes -join ', ')"

    $connectParams = @{
        Scopes    = $scopes
        NoWelcome = $true
    }

    if (-not [string]::IsNullOrWhiteSpace($TenantName)) {
        $connectParams.TenantId = $TenantName.Trim()
    }

    Connect-MgGraph @connectParams | Out-Null
    $context = Get-MgContext

    if (-not $context) {
        throw 'Microsoft Graph connection failed. No Graph context was returned.'
    }

    Add-RunResult ("Connected to tenant '{0}' as '{1}'." -f $context.TenantId, $context.Account)
    return $context
}

function Resolve-OnMicrosoftDomain {
    [CmdletBinding()]
    param([string] $TenantName)

    if ($TenantName -match '^[^@\s]+\.onmicrosoft\.com$') {
        return $TenantName.Trim().ToLowerInvariant()
    }

    Write-Log -Message 'Resolving initial .onmicrosoft.com domain from tenant domains.'
    $domains = Get-MgDomain -All -ErrorAction Stop
    $initialDomain = $domains |
        Where-Object { $_.Id -like '*.onmicrosoft.com' -and $_.IsInitial -eq $true } |
        Select-Object -First 1

    if (-not $initialDomain) {
        $initialDomain = $domains |
            Where-Object { $_.Id -like '*.onmicrosoft.com' } |
            Sort-Object Id |
            Select-Object -First 1
    }

    if (-not $initialDomain) {
        throw 'Could not find a tenant .onmicrosoft.com domain. Enter the tenant initial domain and try again.'
    }

    return $initialDomain.Id.ToLowerInvariant()
}

function ConvertTo-OnMicrosoftUpn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $InputUpn,
        [Parameter(Mandatory)][string] $OnMicrosoftDomain
    )

    if ($InputUpn -notmatch '^[^@\s]+@[^@\s]+$') {
        throw "UPN '$InputUpn' is not valid."
    }

    $localPart = ($InputUpn -split '@', 2)[0]
    $targetUpn = ('{0}@{1}' -f $localPart, $OnMicrosoftDomain).ToLowerInvariant()

    if ($InputUpn.ToLowerInvariant() -ne $targetUpn) {
        Write-Log -Level WARN -Message "UPN '$InputUpn' was adjusted to '$targetUpn' because breakglass accounts must use the .onmicrosoft.com domain."
    }

    return $targetUpn
}

function New-RandomPassword {
    [CmdletBinding()]
    param()

    $lower = 'abcdefghijkmnopqrstuvwxyz'
    $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $digits = '23456789'
    $symbols = '!@#$%&*_-+=?'
    $all = ($lower + $upper + $digits + $symbols).ToCharArray()
    $required = @(
        $lower[(Get-Random -Minimum 0 -Maximum $lower.Length)]
        $upper[(Get-Random -Minimum 0 -Maximum $upper.Length)]
        $digits[(Get-Random -Minimum 0 -Maximum $digits.Length)]
        $symbols[(Get-Random -Minimum 0 -Maximum $symbols.Length)]
    )

    $rest = 1..20 | ForEach-Object { $all[(Get-Random -Minimum 0 -Maximum $all.Length)] }
    return -join (($required + $rest) | Sort-Object { Get-Random })
}

function Get-GraphUserByUpn {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $UserPrincipalName)

    try {
        return Get-MgUser -UserId $UserPrincipalName -Property 'id,displayName,userPrincipalName,accountEnabled' -ErrorAction Stop
    }
    catch {
        if ($_.Exception.Message -match 'Request_ResourceNotFound|Resource .* does not exist|does not exist') {
            return $null
        }

        throw
    }
}

function Get-OrCreateBreakglassUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $InputUpn,
        [Parameter(Mandatory)][string] $OnMicrosoftDomain,
        [Parameter(Mandatory)][bool] $CreateIfMissing
    )

    $upn = ConvertTo-OnMicrosoftUpn -InputUpn $InputUpn -OnMicrosoftDomain $OnMicrosoftDomain
    $existingUser = Get-GraphUserByUpn -UserPrincipalName $upn

    if ($existingUser) {
        Add-RunResult "Breakglass account exists: $upn"
        return $existingUser
    }

    if (-not $CreateIfMissing) {
        Add-RunResult "Breakglass account missing and creation was not selected: $upn"
        return $null
    }

    if ($script:DryRun) {
        Write-Log -Level DRYRUN -Message "Would create breakglass account: $upn"
        Add-RunResult "Dry-run: would create breakglass account: $upn"
        return [pscustomobject]@{
            Id                = "dryrun-$upn"
            UserPrincipalName = $upn
            DisplayName       = "Breakglass $upn"
        }
    }

    if (-not (Confirm-Change -Message "Create breakglass account '$upn'?")) {
        Add-RunResult "Skipped account creation after prompt: $upn"
        return $null
    }

    $password = New-RandomPassword
    $mailNickname = (($upn -split '@', 2)[0] -replace '[^a-zA-Z0-9]', '')
    if ([string]::IsNullOrWhiteSpace($mailNickname)) {
        $mailNickname = 'breakglass'
    }

    $newUserParams = @{
        AccountEnabled    = $true
        DisplayName       = "Breakglass $upn"
        MailNickname      = $mailNickname
        UserPrincipalName = $upn
        PasswordProfile   = @{
            forceChangePasswordNextSignIn = $true
            password                      = $password
        }
    }

    $createdUser = New-MgUser @newUserParams -ErrorAction Stop
    $script:CreatedUserSecrets.Add([pscustomobject]@{
        UserPrincipalName = $upn
        TemporaryPassword = $password
    }) | Out-Null

    Add-RunResult "Created breakglass account: $upn"
    Write-Log -Message "A temporary password was generated for '$upn'. It is shown in the GUI prompt only and is not written to the log."

    return $createdUser
}

function Get-OrCreateBreakglassGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $GroupName,
        [Parameter(Mandatory)][bool] $CreateIfMissing
    )

    $escapedName = $GroupName.Replace("'", "''")
    $groups = Get-MgGroup -Filter "displayName eq '$escapedName'" -ConsistencyLevel eventual -All -Property 'id,displayName' -ErrorAction Stop
    $existingGroup = $groups | Where-Object { $_.DisplayName -eq $GroupName } | Select-Object -First 1

    if ($existingGroup) {
        Add-RunResult "Security group exists: $GroupName"
        return $existingGroup
    }

    if (-not $CreateIfMissing) {
        Add-RunResult "Security group missing and creation was not selected: $GroupName"
        return $null
    }

    if ($script:DryRun) {
        Write-Log -Level DRYRUN -Message "Would create security group: $GroupName"
        Add-RunResult "Dry-run: would create security group: $GroupName"
        return [pscustomobject]@{
            Id          = "dryrun-$GroupName"
            DisplayName = $GroupName
        }
    }

    if (-not (Confirm-Change -Message "Create security group '$GroupName'?")) {
        Add-RunResult "Skipped group creation after prompt: $GroupName"
        return $null
    }

    $mailNickname = ($GroupName -replace '[^a-zA-Z0-9]', '')
    if ([string]::IsNullOrWhiteSpace($mailNickname)) {
        $mailNickname = 'CABreakGlassExclude'
    }

    $createdGroup = New-MgGroup `
        -DisplayName $GroupName `
        -MailEnabled:$false `
        -MailNickname $mailNickname `
        -SecurityEnabled:$true `
        -ErrorAction Stop

    Add-RunResult "Created security group: $GroupName"
    return $createdGroup
}

function Add-BreakglassUsersToGroup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Group,
        [Parameter(Mandatory)] [object[]] $Users
    )

    foreach ($user in ($Users | Where-Object { $_ -and $_.Id })) {
        if ($script:DryRun) {
            Write-Log -Level DRYRUN -Message "Would add '$($user.UserPrincipalName)' to group '$($Group.DisplayName)'."
            Add-RunResult "Dry-run: would add '$($user.UserPrincipalName)' to '$($Group.DisplayName)'."
            continue
        }

        $members = Get-MgGroupMember -GroupId $Group.Id -All -Property 'id' -ErrorAction Stop
        if ($members.Id -contains $user.Id) {
            Add-RunResult "User is already member of '$($Group.DisplayName)': $($user.UserPrincipalName)"
            continue
        }

        if (-not (Confirm-Change -Message "Add '$($user.UserPrincipalName)' to '$($Group.DisplayName)'?")) {
            Add-RunResult "Skipped group membership after prompt: $($user.UserPrincipalName)"
            continue
        }

        $body = @{
            '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($user.Id)"
        }

        New-MgGroupMemberByRef -GroupId $Group.Id -BodyParameter $body -ErrorAction Stop
        Add-RunResult "Added '$($user.UserPrincipalName)' to '$($Group.DisplayName)'."
    }
}

function Disable-AdminSSPR {
    [CmdletBinding()]
    param()

    $warning = @'
Admin SSPR can not be disabled only for the two breakglass accounts.
This Graph authorization policy setting applies tenant-wide to administrators in administrator roles.
'@
    Show-Warning -Message $warning

    if ($script:DryRun) {
        Write-Log -Level DRYRUN -Message 'Would disable administrator SSPR tenant-wide by setting authorizationPolicy.allowedToUseSSPR to false.'
        Add-RunResult 'Dry-run: would disable administrator SSPR tenant-wide.'
        return
    }

    if (-not (Confirm-Change -Message 'Disable administrator SSPR tenant-wide for administrator roles?')) {
        Add-RunResult 'Skipped administrator SSPR change after prompt.'
        return
    }

    $body = @{ allowedToUseSSPR = $false } | ConvertTo-Json -Depth 4
    Invoke-MgGraphRequest -Method PATCH -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -Body $body -ContentType 'application/json' -ErrorAction Stop
    Add-RunResult 'Disabled administrator SSPR tenant-wide for administrator roles.'
}

function Generate-Report {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $TenantName,
        [Parameter(Mandatory)][string] $OnMicrosoftDomain,
        [Parameter(Mandatory)][string[]] $RequestedUpns,
        [Parameter(Mandatory)][string] $GroupName
    )

    $reportPath = Join-Path -Path $script:ReportDirectory -ChildPath ("BreakglassReport_{0}.md" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $manualSteps = @(
        'Register one separate FIDO2 security key per breakglass account.',
        'Store the FIDO2 keys physically separated and securely.',
        "Exclude the '$GroupName' group from all Conditional Access policies.",
        'Configure alerting on sign-in for both breakglass accounts.',
        'Test the accounts periodically.',
        'Never use the accounts for daily administration.'
    )

    $content = @"
# Microsoft Entra Breakglass Setup Report

Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Tenant input: $TenantName
Resolved .onmicrosoft.com domain: $OnMicrosoftDomain
Dry-run: $script:DryRun

## Requested accounts

$($RequestedUpns | ForEach-Object { "- $_" } | Out-String)
## Security group

- $GroupName

## Actions

$($script:RunResults | ForEach-Object { "- $_" } | Out-String)
## Critical manual steps

$($manualSteps | ForEach-Object { "- $_" } | Out-String)
## Important warnings

- The script does not delete users, groups, or Conditional Access policies.
- The '$GroupName' group must be manually excluded from all relevant Conditional Access policies.
- Administrator SSPR can not be disabled only for the two breakglass accounts. If changed, it applies tenant-wide to administrators in administrator roles.
- Temporary passwords for newly created users are not written to this report or the log.

## Log file

$script:LogFile
"@

    Set-Content -Path $reportPath -Value $content -Encoding UTF8
    Add-RunResult "Generated report: $reportPath"
    return $reportPath
}

function Invoke-BreakglassSetup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $TenantName,
        [Parameter(Mandatory)][string] $BreakglassUpn1,
        [Parameter(Mandatory)][string] $BreakglassUpn2,
        [Parameter(Mandatory)][string] $GroupName,
        [bool] $CreateAccountsIfMissing,
        [bool] $CreateGroupIfMissing,
        [bool] $AddAccountsToGroup,
        [bool] $DisableAdminSspr,
        [bool] $GenerateDocumentation,
        [bool] $DryRun
    )

    $script:DryRun = $DryRun
    $script:RunResults.Clear()
    $script:CreatedUserSecrets.Clear()

    Write-Log -Message "Starting breakglass setup. Dry-run: $script:DryRun"

    Connect-Graph -TenantName $TenantName | Out-Null
    $onMicrosoftDomain = Resolve-OnMicrosoftDomain -TenantName $TenantName

    $user1 = Get-OrCreateBreakglassUser -InputUpn $BreakglassUpn1 -OnMicrosoftDomain $onMicrosoftDomain -CreateIfMissing $CreateAccountsIfMissing
    $user2 = Get-OrCreateBreakglassUser -InputUpn $BreakglassUpn2 -OnMicrosoftDomain $onMicrosoftDomain -CreateIfMissing $CreateAccountsIfMissing

    $group = Get-OrCreateBreakglassGroup -GroupName $GroupName -CreateIfMissing $CreateGroupIfMissing

    Show-Warning -Message "Manual step required: exclude '$GroupName' from all Conditional Access policies. This script will not modify or delete Conditional Access policies."

    if ($AddAccountsToGroup) {
        if (-not $group) {
            Add-RunResult "Could not add users to group because '$GroupName' does not exist."
        }
        else {
            Add-BreakglassUsersToGroup -Group $group -Users @($user1, $user2)
        }
    }

    if ($DisableAdminSspr) {
        Disable-AdminSSPR
    }

    $reportPath = $null
    if ($GenerateDocumentation) {
        $reportPath = Generate-Report `
            -TenantName $TenantName `
            -OnMicrosoftDomain $onMicrosoftDomain `
            -RequestedUpns @($BreakglassUpn1, $BreakglassUpn2) `
            -GroupName $GroupName
    }

    if ($script:CreatedUserSecrets.Count -gt 0) {
        $secretText = ($script:CreatedUserSecrets | ForEach-Object {
            "{0}`r`nTemporary password: {1}`r`n" -f $_.UserPrincipalName, $_.TemporaryPassword
        }) -join "`r`n"

        [System.Windows.MessageBox]::Show(
            "Temporary passwords for newly created accounts are shown once and are not stored in logs or reports.`r`n`r`n$secretText",
            "$($script:AppName) - temporary passwords",
            'OK',
            'Information'
        ) | Out-Null
    }

    $summary = "Completed. Log: $script:LogFile"
    if ($reportPath) {
        $summary += "`r`nReport: $reportPath"
    }

    [System.Windows.MessageBox]::Show($summary, $script:AppName, 'OK', 'Information') | Out-Null
}

function Start-BreakglassWpfGui {
    [CmdletBinding()]
    param()

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    [xml] $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Microsoft Entra Breakglass Setup"
        Height="780"
        Width="980"
        MinHeight="720"
        MinWidth="900"
        WindowStartupLocation="CenterScreen"
        Background="#F6F8FA">
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0" Margin="0,0,0,16">
            <TextBlock Text="Microsoft Entra Breakglass Setup" FontSize="24" FontWeight="SemiBold" Foreground="#1F2937"/>
            <TextBlock Text="Configure, validate, and document best practice breakglass prerequisites without modifying Conditional Access policies." FontSize="13" Foreground="#4B5563" Margin="0,6,0,0"/>
        </StackPanel>

        <Border Grid.Row="1" BorderBrush="#D1D5DB" BorderThickness="1" Background="White" CornerRadius="6" Padding="16" Margin="0,0,0,14">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="180"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="220"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <TextBlock Grid.Row="0" Grid.Column="0" Text="Tenant name / domain" VerticalAlignment="Center" Margin="0,0,10,10"/>
                <TextBox x:Name="TenantNameTextBox" Grid.Row="0" Grid.Column="1" Grid.ColumnSpan="3" Height="28" Margin="0,0,0,10"/>

                <TextBlock Grid.Row="1" Grid.Column="0" Text="Breakglass account 1 UPN" VerticalAlignment="Center" Margin="0,0,10,10"/>
                <TextBox x:Name="BreakglassUpn1TextBox" Grid.Row="1" Grid.Column="1" Grid.ColumnSpan="3" Height="28" Margin="0,0,0,10"/>

                <TextBlock Grid.Row="2" Grid.Column="0" Text="Breakglass account 2 UPN" VerticalAlignment="Center" Margin="0,0,10,10"/>
                <TextBox x:Name="BreakglassUpn2TextBox" Grid.Row="2" Grid.Column="1" Grid.ColumnSpan="3" Height="28" Margin="0,0,0,10"/>

                <TextBlock Grid.Row="3" Grid.Column="0" Text="Security group name" VerticalAlignment="Center" Margin="0,0,10,14"/>
                <TextBox x:Name="GroupNameTextBox" Grid.Row="3" Grid.Column="1" Grid.ColumnSpan="3" Height="28" Text="CA-BreakGlassExclude" Margin="0,0,0,14"/>

                <CheckBox x:Name="CreateAccountsCheckBox" Grid.Row="4" Grid.Column="0" Grid.ColumnSpan="2" Content="Create accounts if missing" IsChecked="True" Margin="0,0,0,10"/>
                <CheckBox x:Name="CreateGroupCheckBox" Grid.Row="4" Grid.Column="2" Grid.ColumnSpan="2" Content="Create group if missing" IsChecked="True" Margin="0,0,0,10"/>
                <CheckBox x:Name="AddToGroupCheckBox" Grid.Row="5" Grid.Column="0" Grid.ColumnSpan="2" Content="Add accounts to group" IsChecked="True" Margin="0,0,0,0"/>
                <CheckBox x:Name="DisableAdminSsprCheckBox" Grid.Row="5" Grid.Column="2" Content="Disable admin SSPR" Margin="0,0,0,0"/>
                <CheckBox x:Name="GenerateDocumentationCheckBox" Grid.Row="5" Grid.Column="3" Content="Generate documentation / summary" IsChecked="True" Margin="0,0,0,0"/>
            </Grid>
        </Border>

        <Grid Grid.Row="2">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <DockPanel Grid.Row="0" Margin="0,0,0,8">
                <TextBlock Text="Run log" FontSize="16" FontWeight="SemiBold" Foreground="#1F2937" DockPanel.Dock="Left"/>
                <CheckBox x:Name="DryRunCheckBox" Content="Dry-run mode" IsChecked="True" DockPanel.Dock="Right" HorizontalAlignment="Right"/>
            </DockPanel>
            <TextBox x:Name="LogTextBox" Grid.Row="1" IsReadOnly="True" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" FontFamily="Consolas" FontSize="12" Background="#111827" Foreground="#E5E7EB" Padding="10"/>
        </Grid>

        <DockPanel Grid.Row="3" Margin="0,14,0,0">
            <StackPanel Orientation="Horizontal" DockPanel.Dock="Right" HorizontalAlignment="Right">
                <Button x:Name="RunButton" Content="Run setup" Width="110" Height="34" Margin="0,0,8,0" IsDefault="True"/>
                <Button x:Name="ClearLogButton" Content="Clear log view" Width="110" Height="34" Margin="0,0,8,0"/>
                <Button x:Name="OpenLogButton" Content="Open log folder" Width="120" Height="34" Margin="0,0,8,0"/>
                <Button x:Name="ExitButton" Content="Exit" Width="80" Height="34"/>
            </StackPanel>
        </DockPanel>
    </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $script:MainWindow = [Windows.Markup.XamlReader]::Load($reader)

    $tenantNameTextBox = $script:MainWindow.FindName('TenantNameTextBox')
    $breakglassUpn1TextBox = $script:MainWindow.FindName('BreakglassUpn1TextBox')
    $breakglassUpn2TextBox = $script:MainWindow.FindName('BreakglassUpn2TextBox')
    $groupNameTextBox = $script:MainWindow.FindName('GroupNameTextBox')
    $createAccountsCheckBox = $script:MainWindow.FindName('CreateAccountsCheckBox')
    $createGroupCheckBox = $script:MainWindow.FindName('CreateGroupCheckBox')
    $addToGroupCheckBox = $script:MainWindow.FindName('AddToGroupCheckBox')
    $disableAdminSsprCheckBox = $script:MainWindow.FindName('DisableAdminSsprCheckBox')
    $generateDocumentationCheckBox = $script:MainWindow.FindName('GenerateDocumentationCheckBox')
    $dryRunCheckBox = $script:MainWindow.FindName('DryRunCheckBox')
    $runButton = $script:MainWindow.FindName('RunButton')
    $clearLogButton = $script:MainWindow.FindName('ClearLogButton')
    $openLogButton = $script:MainWindow.FindName('OpenLogButton')
    $exitButton = $script:MainWindow.FindName('ExitButton')
    $script:LogTextBox = $script:MainWindow.FindName('LogTextBox')

    Write-Log -Message "GUI started. Log file: $script:LogFile"

    $runButton.Add_Click({
        try {
            if ([string]::IsNullOrWhiteSpace($tenantNameTextBox.Text) -or
                [string]::IsNullOrWhiteSpace($breakglassUpn1TextBox.Text) -or
                [string]::IsNullOrWhiteSpace($breakglassUpn2TextBox.Text) -or
                [string]::IsNullOrWhiteSpace($groupNameTextBox.Text)) {
                [System.Windows.MessageBox]::Show('Tenant, both UPNs, and group name are required.', $script:AppName, 'OK', 'Warning') | Out-Null
                return
            }

            $runButton.IsEnabled = $false
            Invoke-BreakglassSetup `
                -TenantName $tenantNameTextBox.Text.Trim() `
                -BreakglassUpn1 $breakglassUpn1TextBox.Text.Trim() `
                -BreakglassUpn2 $breakglassUpn2TextBox.Text.Trim() `
                -GroupName $groupNameTextBox.Text.Trim() `
                -CreateAccountsIfMissing ([bool] $createAccountsCheckBox.IsChecked) `
                -CreateGroupIfMissing ([bool] $createGroupCheckBox.IsChecked) `
                -AddAccountsToGroup ([bool] $addToGroupCheckBox.IsChecked) `
                -DisableAdminSspr ([bool] $disableAdminSsprCheckBox.IsChecked) `
                -GenerateDocumentation ([bool] $generateDocumentationCheckBox.IsChecked) `
                -DryRun ([bool] $dryRunCheckBox.IsChecked)
        }
        catch {
            Write-Log -Level ERROR -Message $_.Exception.Message
            [System.Windows.MessageBox]::Show($_.Exception.Message, "$($script:AppName) - error", 'OK', 'Error') | Out-Null
        }
        finally {
            $runButton.IsEnabled = $true
        }
    })

    $clearLogButton.Add_Click({
        $script:LogTextBox.Clear()
        Write-Log -Message 'Log view cleared.'
    })

    $openLogButton.Add_Click({
        Start-Process explorer.exe -ArgumentList $script:LogDirectory
    })

    $exitButton.Add_Click({
        $script:MainWindow.Close()
    })

    $script:MainWindow.ShowDialog() | Out-Null
}

Start-BreakglassWpfGui

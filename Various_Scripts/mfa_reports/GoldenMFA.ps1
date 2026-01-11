function Install-Module-If-Needed {
    param([string]$ModuleName)
    
    if (Get-Module -ListAvailable -Name $ModuleName) {
       Write-Host "✓ Module '$($ModuleName)' is already installed, continuing..." -ForegroundColor Green
    } else {
       Write-Host "⚠ Module '$($ModuleName)' is not installed, installing..." -ForegroundColor Yellow
       Install-Module $ModuleName -Force -AllowClobber -ErrorAction Stop
       Write-Host "✓ Module '$($ModuleName)' has been installed." -ForegroundColor Green
    }
}

# Install required modules if not already installed
Install-Module-If-Needed -ModuleName Microsoft.Graph
Install-Module-If-Needed -ModuleName ImportExcel

# Authenticate to Microsoft Graph
Connect-MgGraph -Scopes "User.Read.All", "User.ReadWrite.All", "UserAuthenticationMethod.Read.All", "AuditLog.Read.All" -NoWelcome

$GraphOrgInfo = Get-MgOrganization

Write-Host "🔐 You are logged into" $GraphOrgInfo.DisplayName "tenant on Graph" -ForegroundColor Cyan

$licenseTableHash = @{}
# Fetch Microsoft's official CSV with all O365 licenses, their GUID and display names. Convert to a variable with GUID and product name
$licenseTableURL = 'https://download.microsoft.com/download/e/3/e/e3e9faf2-f28b-490a-9ada-c6089a1fc5b0/Product%20names%20and%20service%20plan%20identifiers%20for%20licensing.csv'
$licenseTable = (Invoke-WebRequest -Uri $LicenseTableURL).ToString() | ConvertFrom-Csv | Select-Object -Property GUID, ???Product_Display_Name
    
# Create a hashtable for fast lookup
$licenseTable | foreach { $licenseTableHash[$_.GUID] = $_."???Product_Display_Name" }

## Get all users from Graph API with required properties
$users = Get-MgUser -All -Property Id, DisplayName, UserPrincipalName, Department, AccountEnabled, AssignedLicenses, UserType, Mail

# Fetch all sign-in logs within the last 30 days
try {
    $dateFilter = (Get-Date).AddDays(-1).ToUniversalTime().ToString("o")
    Write-Host "🔍 Fetching sign-in data from the last 30 days..." -ForegroundColor Yellow
    $allSignIns = Get-MgAuditLogSignIn -Filter "createdDateTime ge $dateFilter" -All
    Write-Host "✓ All recent sign-ins fetched successfully." -ForegroundColor Green
} catch {
    Write-Host "❌ Error fetching recent sign-ins: $($_.Exception.Message)" -ForegroundColor Red
}

# Create an array to store user information
$userData = @()

# Loop through each user and select the desired fields
foreach ($user in $users) {
    Write-Host "👤 Processing user: $($user.DisplayName) ($($user.UserPrincipalName))" -ForegroundColor Cyan
    
    # Determine account type
    $accountType = "Regular User"
    if ($user.UserType -eq "Guest") {
        $accountType = "Guest"
        Write-Host "  🌐 Account type: Guest account" -ForegroundColor Magenta
    } else {
        # Check if it's a shared mailbox by looking at mailbox properties
        try {
            $mailbox = Get-MgUserMailboxSettings -UserId $user.Id -ErrorAction SilentlyContinue
            # Shared mailboxes typically don't have a license and are disabled
            if ($user.AssignedLicenses.Count -eq 0 -and $user.AccountEnabled -eq $false -and $user.Mail) {
                $accountType = "Shared Mailbox (Likely)"
                Write-Host "  📮 Account type: Shared mailbox (likely)" -ForegroundColor Yellow
            } else {
                Write-Host "  👤 Account type: Regular user" -ForegroundColor Gray
            }
        } catch {
            Write-Host "  👤 Account type: Regular user" -ForegroundColor Gray
        }
    }
    
    if ($user.AssignedLicenses -ne $null) {
        $assignedLicenses = $user.AssignedLicenses.SkuId | ForEach-Object { $licenseTableHash[$_] }
        $assignedLicenses = $assignedLicenses -join ", "
        Write-Host "  📜 Licenses: $assignedLicenses" -ForegroundColor Gray
    } else {
        $assignedLicenses = "No License"
        Write-Host "  📜 Licenses: No license" -ForegroundColor Gray
    }

    # Get the latest sign-in information
    Write-Host "  🔍 Fetching sign-in data..." -ForegroundColor Yellow
    $latestSignIn = $allSignIns | Where-Object { $_.UserPrincipalName -eq $user.UserPrincipalName } | Sort-Object CreatedDateTime -Descending | Select-Object -First 1
    $lastSignIn = if ($latestSignIn) { $latestSignIn.CreatedDateTime } else { $null }
    Write-Host "  📅 Latest sign-in: $lastSignIn" -ForegroundColor Gray

    # Get MFA information
    Write-Host "  🔍 Fetching MFA data..." -ForegroundColor Yellow
    $MFAData = Get-MgUserAuthenticationMethod -UserId $user.Id
    $AuthenticationMethod = @()
    $AdditionalDetails = @()
    $MFAPhone = $null
    $MicrosoftAuthenticatorDevice = $null
    $Is3rdPartyAuthenticatorUsed = $false

    foreach ($MFA in $MFAData) { 
        Switch ($MFA.AdditionalProperties["@odata.type"]) { 
            "#microsoft.graph.passwordAuthenticationMethod" {
                $AuthMethod = 'PasswordAuthentication'
                $AuthMethodDetails = $MFA.AdditionalProperties["displayName"]
            } 
            "#microsoft.graph.microsoftAuthenticatorAuthenticationMethod" {
                $AuthMethod = 'AuthenticatorApp'
                $AuthMethodDetails = $MFA.AdditionalProperties["displayName"]
                $MicrosoftAuthenticatorDevice = $MFA.AdditionalProperties["displayName"]
            }
            "#microsoft.graph.phoneAuthenticationMethod" {
                $AuthMethod = 'PhoneAuthentication'
                $AuthMethodDetails = $MFA.AdditionalProperties["phoneType", "phoneNumber"] -join ' '
                $MFAPhone = $MFA.AdditionalProperties["phoneNumber"]
            } 
            "#microsoft.graph.fido2AuthenticationMethod" {
                $AuthMethod = 'Fido2'
                $AuthMethodDetails = $MFA.AdditionalProperties["model"]
            }  
            "#microsoft.graph.windowsHelloForBusinessAuthenticationMethod" {
                $AuthMethod = 'WindowsHelloForBusiness'
                $AuthMethodDetails = $MFA.AdditionalProperties["displayName"]
            }                        
            "#microsoft.graph.emailAuthenticationMethod" {
                $AuthMethod = 'EmailAuthentication'
                $AuthMethodDetails = $MFA.AdditionalProperties["emailAddress"]
            }               
            "microsoft.graph.temporaryAccessPassAuthenticationMethod" {
                $AuthMethod = 'TemporaryAccessPass'
                $AuthMethodDetails = 'Access pass lifetime (minutes): ' + $MFA.AdditionalProperties["lifetimeInMinutes"]
            }
            "#microsoft.graph.passwordlessMicrosoftAuthenticatorAuthenticationMethod" {
                $AuthMethod = 'PasswordlessMSAuthenticator'
                $AuthMethodDetails = $MFA.AdditionalProperties["displayName"]
            }      
            "#microsoft.graph.softwareOathAuthenticationMethod" {
                $AuthMethod = 'SoftwareOath'
                $AuthMethodDetails = $null
                $Is3rdPartyAuthenticatorUsed = $true
            }
        }
        $AuthenticationMethod += $AuthMethod
        if ($AuthMethodDetails -ne $null) {
            $AdditionalDetails += "$AuthMethod : $AuthMethodDetails"
        }
    }
    # Remove duplicate authentication methods
    $AuthenticationMethod = $AuthenticationMethod | Sort-Object | Get-Unique
    $AuthenticationMethods = $AuthenticationMethod -join ","
    $AdditionalDetail = $AdditionalDetails -join ", "
    Write-Host "  🔑 MFA methods: $AuthenticationMethods" -ForegroundColor Gray

    # Determine MFA status
    $StrongMFAMethods = @("Fido2", "PhoneAuthentication", "PasswordlessMSAuthenticator", "AuthenticatorApp", "WindowsHelloForBusiness")
    $MFAStatus = "Disabled"
    
    foreach ($StrongMFAMethod in $StrongMFAMethods) {
        if ($AuthenticationMethod -contains $StrongMFAMethod) {
            $MFAStatus = "Strong"
            break
        }
    }

    if (($MFAStatus -ne "Strong") -and ($AuthenticationMethod -contains "SoftwareOath")) {
        $MFAStatus = "Weak"
    }
    $statusIcon = if($MFAStatus -eq "Strong"){"🛡️"}elseif($MFAStatus -eq "Weak"){"⚠️"}else{"❌"}
    Write-Host "  $statusIcon MFA status: $MFAStatus" -ForegroundColor $(if($MFAStatus -eq "Strong"){"Green"}elseif($MFAStatus -eq "Weak"){"Yellow"}else{"Red"})

    $userInfo = [PSCustomObject]@{
        Name                          = $user.DisplayName
        UPN                           = $user.UserPrincipalName
        AccountType                   = $accountType
        Department                    = $user.Department
        AccountEnabled                = $user.AccountEnabled
        Licenses                      = $assignedLicenses
        LastSignin                    = $lastSignIn
        MFAStatus                     = $MFAStatus
        AuthenticationMethods         = $AuthenticationMethods
        MFAPhone                      = $MFAPhone
        MicrosoftAuthenticatorDevice  = $MicrosoftAuthenticatorDevice
        Is3rdPartyAuthenticatorUsed   = $Is3rdPartyAuthenticatorUsed
        AdditionalDetails             = $AdditionalDetail
    }
    $userData += $userInfo
    Write-Host "  ✓ User processed`n" -ForegroundColor Green
}

# Define the path to the Excel file (cross-platform)
$timestamp = Get-Date -Format "ddMMyyy-HHmm"
$desktopPath = if ($IsWindows -or $env:OS) { 
    "$env:UserProfile\Desktop" 
} else { 
    "$env:HOME/Desktop" 
}
$excelFilePath = Join-Path -Path $desktopPath -ChildPath "$($GraphOrgInfo.DisplayName)_MFAOverview_$timestamp.xlsx"

# Export the data to an Excel file
$userData | Export-Excel -Path $excelFilePath -WorksheetName "Users" -TableStyle Medium9 -AutoSize

Write-Host "📊 Data exported to $excelFilePath" -ForegroundColor Green

# Cross-platform compatible prompt
$openFile = Read-Host "📂 Do you want to open the file now? (Y/N)"
if ($openFile -match "[JjYy]") {
    Invoke-Item $excelFilePath
}

Disconnect-MgGraph
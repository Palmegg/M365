# FileMover - Intune File Deployment Tool

A PowerShell-based solution for deploying files to Windows devices via Microsoft Intune.

## Overview

FileMover allows you to package any files or folders and deploy them to a specific location on target devices. The tool includes both an installer and detector script for Intune compliance.

## How It Works

1. **MainInstaller.ps1** - Copies all files from the package source to a destination folder
2. **MainDetector.ps1** - Verifies the installation by checking for a detector file

## Usage

### 1. Prepare Your Files

Place all files and folders you want to deploy in the same directory as `MainInstaller.ps1`.

```
FileMover/
├── MainInstaller.ps1
├── MainDetector.ps1
├── YourFile1.txt
├── YourFile2.exe
└── YourFolder/
    └── MoreFiles.pdf
```

### 2. Configure Parameters

Edit the `MainDetector.ps1` to match your deployment:

```powershell
[string]$Prefix             = "YourCompany"  # Change this to your company/project name
[string]$DestinationPath    = "C:\ProgramData\YourFolder"  # Change to your target path
```

### 3. Create Intune Package

Package the installer using the [Microsoft Win32 Content Prep Tool](https://github.com/Microsoft/Microsoft-Win32-Content-Prep-Tool):

```powershell
IntuneWinAppUtil.exe -c "C:\Source\FileMover" -s "MainInstaller.ps1" -o "C:\Output"
```

### 4. Upload to Intune

1. Go to **Intune** → **Apps** → **Windows** → **Add**
2. Select **Windows app (Win32)**
3. Upload the `.intunewin` file

#### Install Command
```powershell
powershell.exe -ExecutionPolicy Bypass -File MainInstaller.ps1 -Prefix "YourCompany" -DestinationPath "C:\ProgramData\YourFolder"
```

#### Uninstall Command
```powershell
powershell.exe -Command "Remove-Item -Path 'C:\ProgramData\YourFolder' -Recurse -Force"
```

#### Detection Rule
- **Rule type**: Use a custom detection script
- **Script file**: Upload `MainDetector.ps1`

### 5. Assign and Deploy

Assign the app to your target groups and deploy!

## Parameters

### MainInstaller.ps1

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `-Prefix` | Yes | `"Mover"` | Prefix for log file names |
| `-DestinationPath` | No | `"C:\ProgramData\CorporateFiles"` | Target installation path |

### MainDetector.ps1

Edit these variables in the script:

| Variable | Description |
|----------|-------------|
| `$Prefix` | Must match the installer prefix |
| `$DestinationPath` | Must match the installer destination |

## Logs

All logs are stored in:
```
C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\
```

- Installer log: `#YourPrefix_FileMover.log`
- Detector log: `#YourPrefix_FileMover.log`

## Features

✅ Recursive folder copying with structure preservation  
✅ Automatic exclusion of script files and logs  
✅ Comprehensive logging with color coding  
✅ Detection file for Intune compliance  
✅ Overwrites existing files (keeps folder clean)  
✅ Detailed error handling and reporting  

## Example Deployment

### Scenario: Deploy company wallpapers and scripts

```powershell
# 1. Structure
FileMover/
├── MainInstaller.ps1
├── MainDetector.ps1
├── Wallpapers/
│   ├── Company_Logo.png
│   └── Desktop_BG.jpg
└── Scripts/
    └── SetWallpaper.ps1

# 2. Configure MainDetector.ps1
$Prefix = "CompanyAssets"
$DestinationPath = "C:\CompanyFiles"

# 3. Install command in Intune
powershell.exe -ExecutionPolicy Bypass -File MainInstaller.ps1 -Prefix "CompanyAssets" -DestinationPath "C:\CompanyFiles"

# 4. Result on target device
C:\CompanyFiles\
├── detector.log
├── Wallpapers/
│   ├── Company_Logo.png
│   └── Desktop_BG.jpg
└── Scripts/
    └── SetWallpaper.ps1
```

## Troubleshooting

### Installation fails
- Check the installer log in `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\`
- Verify destination path is writable
- Ensure no files are locked/in-use

### Detection fails
- Verify `$Prefix` and `$DestinationPath` match between installer and detector
- Check if `detector.log` exists in the destination folder
- Review detector log for errors

## License

Free to use and modify for your organization's needs.

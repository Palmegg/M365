@echo off
REM ==================================================================================
REM  AutoPilot enrollment helper
REM  Purpose : Collect and upload Windows Autopilot hardware hash using Graph (App Reg)
REM  Usage   : Run as admin (auto prompts). Fill in the variables below before sharing.
REM  Author  : (Your company)
REM  Notes   : Storing client secret in plain text is risky. Consider a short‑lived secret
REM             or provide a PowerShell SecureString alternative. This is for internal IT.
REM ==================================================================================

SETLOCAL ENABLEDELAYEDEXPANSION

REM -----------------------------
REM Configuration (EDIT THESE)
REM -----------------------------
SET TENANT_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
SET APP_ID=yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy
SET APP_SECRET=YOUR_APP_SECRET_VALUE_HERE
REM Optional: Tag to apply to device (leave blank to skip)
SET GROUP_TAG=
REM Country / region or other custom attributes could be added similarly.

REM -----------------------------
REM Working folder
REM -----------------------------
SET WORKDIR=%~dp0AutopilotWork
IF NOT EXIST "%WORKDIR%" MD "%WORKDIR%"
PUSHD "%WORKDIR%"

REM -----------------------------
REM Elevation check
REM -----------------------------
whoami /groups | find "S-1-5-32-544" >NUL 2>&1
IF ERRORLEVEL 1 (
	ECHO [INFO ] Attempting to relaunch elevated...
	powershell -NoLogo -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
	IF ERRORLEVEL 1 (
		ECHO [ERROR] Unable to self elevate. Right-click and 'Run as administrator'.
		EXIT /B 1
	)
	EXIT /B 0
)

REM -----------------------------
REM Pre-flight validation
REM -----------------------------
IF "%TENANT_ID%"=="" ECHO [ERROR] TENANT_ID not set & EXIT /B 10
IF "%APP_ID%"=="" ECHO [ERROR] APP_ID not set & EXIT /B 11
IF "%APP_SECRET%"=="" ECHO [ERROR] APP_SECRET not set & EXIT /B 12

REM -----------------------------
REM Download Autopilot community script (latest published to PSGallery)
REM Using PowerShell to ensure TLS 1.2 and direct PSGallery installation path.
REM Script: Get-WindowsAutopilotInfo.ps1 by community (Michael Niehaus et al.)
REM -----------------------------
ECHO [INFO ] Downloading Get-WindowsAutopilotInfo.ps1 ...
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "try { $ErrorActionPreference='Stop'; Install-PackageProvider -Name NuGet -Force -Scope CurrentUser > $null; Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue; Save-Script -Name Get-WindowsAutopilotInfo -Path '.' -Force; Write-Host '[INFO ] Download complete'; } catch { Write-Host '[ERROR] Failed to download script: ' + $_; exit 1 }"
IF ERRORLEVEL 1 (
	ECHO [ERROR] Could not retrieve Get-WindowsAutopilotInfo.ps1
	EXIT /B 20
)

IF NOT EXIST Get-WindowsAutopilotInfo.ps1 (
	ECHO [ERROR] Script file missing after download.
	EXIT /B 21
)

REM -----------------------------
REM Execute hardware hash upload
REM Parameters reference: Get-Help .\Get-WindowsAutopilotInfo.ps1 -Full
REM Using -Online with Graph auth.
REM -----------------------------
ECHO [INFO ] Starting Autopilot hash collection & upload ...

SET PS_CMD=^"$ErrorActionPreference='Stop'; ^
	$tenant='%TENANT_ID%'; $app='%APP_ID%'; $secret='%APP_SECRET%'; $groupTag='%GROUP_TAG%'; ^
	$params=@{ 'TenantId'=$tenant; 'AppId'=$app; 'AppSecret'=$secret; 'Online'=$true; 'AddToGroup'=$false }; ^
	if ($groupTag) { $params['GroupTag']=$groupTag }; ^
	Write-Host '[INFO ] Parameters prepared'; ^
	. .\Get-WindowsAutopilotInfo.ps1 @params; ^
	Write-Host '[SUCCESS] Autopilot hash uploaded successfully.' ^"

powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command %PS_CMD%
IF ERRORLEVEL 1 (
	ECHO [ERROR] Upload failed. Check credentials/permissions (Device.ReadWrite.All, etc.).
	EXIT /B 30
)

REM -----------------------------
REM Optional: export CSV locally as well (uncomment if needed)
REM powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Get-Content AutopilotHWID.csv | Select-Object -First 5"

ECHO.
ECHO [DONE ] Process complete. You may close this window.

POPD
ENDLOCAL
EXIT /B 0


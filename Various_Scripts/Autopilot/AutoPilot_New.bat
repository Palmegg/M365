@echo off
setlocal
set "LOGDIR=%CD%"
REM Configuration (EDIT THESE)
SET TENANT_ID=INSERT HERE
SET APP_ID=INSERT HERE
SET APP_SECRET=INSERT HERE
set "GROUP_TAG="

REM Check for internet connectivity (using Cloudflare)
ping -n 1 1.1.1.1 >nul
if errorlevel 1 (
    echo No internet connection found. The program will close.
    msg * "No internet connection found. The program will close."
    goto :end
)

echo Internet connection found.
echo Downloading script...

REM Define download path (TEMP folder)
set "downloadPath=%LOGDIR%\AutopilotHelper.ps1"

REM Download the latest script from your GitHub
powershell -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/Palmegg/M365/refs/heads/main/Various_Scripts/AutopilotHelper.ps1' -OutFile '%downloadPath%'"
REM Check if download succeeded
if errorlevel 1 (
    echo [ERROR] Failed to download AutopilotHelper.ps1. Exiting.
    msg * "[ERROR] Failed to download AutopilotHelper.ps1. Exiting."
    goto :end
)

REM Execute the downloaded PowerShell script with parameters
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%downloadPath%" -TenantId "%TENANT_ID%" -AppId "%APP_ID%" -AppSecret "%APP_SECRET%" -GroupTag "%GROUP_TAG%"

:end
endlocal
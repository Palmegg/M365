@echo off
setlocal

REM Configuration (EDIT THESE)
set "TENANT_ID=fc441c89-e42b-443d-9642-351d1dfe31a4"
set "APP_ID=d418162b-e0f3-47f8-9435-2cafbb342b4b"
set "APP_SECRET=zkJ8Q~JUz3aG1E1Sdx2rxJtIrBLweaf2b_c"
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
set "downloadPath=%TEMP%\AutopilotHelper.ps1"

REM Download the latest script from your GitHub
powershell -NoLogo -NoProfile -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/Palmegg/M365/main/Various%20scripts/AutopilotHelper.ps1' -OutFile '%downloadPath%'"
powershell -Command "Invoke-WebRequest -Uri 'https://ast.oo.dk/SpeedTune/SpeedTune.ps1' -OutFile '%downloadPath%'"
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
@echo off
title RetailPOS Print Helper - Install
echo ============================================
echo   RetailPOS Print Helper - Installation
echo ============================================
echo.

:: Check for admin rights
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo This installer requires Administrator privileges.
    echo Right-click and select "Run as administrator"
    echo.
    pause
    exit /b 1
)

echo Installing RetailPOS Print Helper service...
echo.

:: Change to script directory
cd /d "%~dp0"

:: Check if Node.js is installed
where node >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: Node.js is not installed!
    echo.
    echo Please download and install Node.js from:
    echo https://nodejs.org/
    echo.
    echo After installing Node.js, run this installer again.
    pause
    exit /b 1
)

echo [1/4] Installing dependencies...
call npm install --production
if %errorLevel% neq 0 (
    echo ERROR: Failed to install dependencies
    pause
    exit /b 1
)

echo.
echo [2/4] Installing Windows Service...
node service.js install
if %errorLevel% neq 0 (
    echo.
    echo Service installation may have issues. Trying alternative method...
    echo Starting server in background mode...
    start /min cmd /c "node server.js"
)

echo.
echo [3/4] Creating startup shortcut...
:: Create VBS script to make shortcut
echo Set oWS = WScript.CreateObject("WScript.Shell") > "%temp%\CreateShortcut.vbs"
echo sLinkFile = oWS.SpecialFolders("Startup") ^& "\RetailPOS Print Helper.lnk" >> "%temp%\CreateShortcut.vbs"
echo Set oLink = oWS.CreateShortcut(sLinkFile) >> "%temp%\CreateShortcut.vbs"
echo oLink.TargetPath = "%~dp0start-hidden.vbs" >> "%temp%\CreateShortcut.vbs"
echo oLink.WorkingDirectory = "%~dp0" >> "%temp%\CreateShortcut.vbs"
echo oLink.Description = "RetailPOS Print Helper" >> "%temp%\CreateShortcut.vbs"
echo oLink.Save >> "%temp%\CreateShortcut.vbs"
cscript //nologo "%temp%\CreateShortcut.vbs"
del "%temp%\CreateShortcut.vbs"

echo.
echo [4/4] Verifying installation...
timeout /t 3 /nobreak >nul

:: Test if server is running
powershell -NoProfile -Command "try { $r = Invoke-WebRequest -Uri 'http://localhost:5005/health' -UseBasicParsing -TimeoutSec 5; if ($r.StatusCode -eq 200) { Write-Host 'Server is running!' -ForegroundColor Green } } catch { Write-Host 'Server starting...' -ForegroundColor Yellow }"

echo.
echo ============================================
echo   Installation Complete!
echo ============================================
echo.
echo The print server is now running on:
echo   http://localhost:5005
echo.
echo It will start automatically when Windows starts.
echo.
echo To test, open your web browser and visit:
echo   http://localhost:5005/printers
echo.
echo To uninstall, run: uninstall.bat
echo.
pause

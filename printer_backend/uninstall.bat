@echo off
title RetailPOS Print Helper - Uninstall
echo ============================================
echo   RetailPOS Print Helper - Uninstall
echo ============================================
echo.

:: Check for admin rights
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo This uninstaller requires Administrator privileges.
    echo Right-click and select "Run as administrator"
    echo.
    pause
    exit /b 1
)

echo Uninstalling RetailPOS Print Helper...
echo.

:: Change to script directory
cd /d "%~dp0"

echo [1/3] Stopping service...
node service.js stop 2>nul
taskkill /f /im "node.exe" /fi "WINDOWTITLE eq RetailPOS*" 2>nul

echo.
echo [2/3] Removing Windows Service...
node service.js uninstall 2>nul

echo.
echo [3/3] Removing startup shortcut...
del "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\RetailPOS Print Helper.lnk" 2>nul

echo.
echo ============================================
echo   Uninstall Complete!
echo ============================================
echo.
echo The print service has been removed.
echo.
pause

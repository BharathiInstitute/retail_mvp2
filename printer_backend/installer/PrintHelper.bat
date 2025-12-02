@echo off
:: RetailPOS Print Helper - Background Launcher
:: Uses bundled Node.js - no installation required

cd /d "%~dp0"

:: Check if already running on port 5005
netstat -ano | findstr ":5005" >nul 2>&1
if %ERRORLEVEL%==0 (
    echo Print Helper is already running.
    exit /b 0
)

:: Start Node.js server minimized using START command
start "RetailPOS-PrintHelper" /MIN "%~dp0node\node.exe" "%~dp0server.js"
exit /b 0

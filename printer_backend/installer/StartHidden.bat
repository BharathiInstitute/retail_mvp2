@echo off
:: RetailPOS Print Helper - Start Hidden
:: This batch file starts the print server in background

cd /d "%~dp0"

:: Check if already running on port 5005
netstat -an | findstr ":5005.*LISTENING" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    exit /b 0
)

:: Start Node.js minimized and detached
start "" /b /min "node\node.exe" "server.js"
exit /b 0

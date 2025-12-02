@echo off
setlocal enabledelayedexpansion

echo ============================================
echo   RetailPOS Print Helper - Build Installer
echo ============================================
echo.

cd /d "%~dp0"

:: Configuration
set NODE_VERSION=18.19.0
set NODE_ARCH=win-x64
set NODE_URL=https://nodejs.org/dist/v%NODE_VERSION%/node-v%NODE_VERSION%-%NODE_ARCH%.zip
set NODE_ZIP=node-v%NODE_VERSION%-%NODE_ARCH%.zip
set NODE_DIR=node-v%NODE_VERSION%-%NODE_ARCH%

:: Check if Inno Setup is installed
set ISCC_PATH=
if exist "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" (
    set ISCC_PATH=C:\Program Files (x86)\Inno Setup 6\ISCC.exe
) else if exist "C:\Program Files\Inno Setup 6\ISCC.exe" (
    set ISCC_PATH=C:\Program Files\Inno Setup 6\ISCC.exe
)

if "!ISCC_PATH!"=="" (
    echo ERROR: Inno Setup 6 not found!
    echo.
    echo Please download and install Inno Setup from:
    echo https://jrsoftware.org/isdl.php
    echo.
    pause
    exit /b 1
)

echo [1/6] Creating build directories...
if not exist "installer" mkdir installer
if not exist "installer\node" mkdir installer\node
if not exist "installer\node_modules" mkdir installer\node_modules
if not exist "installer\installer_output" mkdir installer\installer_output

echo [2/6] Downloading Node.js portable (%NODE_VERSION%)...
if not exist "installer\%NODE_ZIP%" (
    echo Downloading from %NODE_URL%...
    powershell -NoProfile -Command "Invoke-WebRequest -Uri '%NODE_URL%' -OutFile 'installer\%NODE_ZIP%'"
    if errorlevel 1 (
        echo ERROR: Failed to download Node.js
        pause
        exit /b 1
    )
) else (
    echo Node.js already downloaded, skipping...
)

echo [3/6] Extracting Node.js...
if not exist "installer\node\node.exe" (
    powershell -NoProfile -Command "Expand-Archive -Path 'installer\%NODE_ZIP%' -DestinationPath 'installer\temp_node' -Force"
    xcopy "installer\temp_node\%NODE_DIR%\*" "installer\node\" /E /Y /Q
    rmdir /s /q "installer\temp_node"
) else (
    echo Node.js already extracted, skipping...
)

echo [4/6] Copying server files...
copy /y "server.js" "installer\server.js"
copy /y "package.json" "installer\package.json"
copy /y "package-lock.json" "installer\package-lock.json" 2>nul
if exist "config.json" copy /y "config.json" "installer\config.json"

echo [5/6] Copying node_modules...
xcopy "node_modules\*" "installer\node_modules\" /E /Y /Q

echo [6/6] Building installer with Inno Setup...
"!ISCC_PATH!" "installer\setup.iss"
if errorlevel 1 (
    echo ERROR: Inno Setup compilation failed
    pause
    exit /b 1
)

echo.
echo ============================================
echo   Build Complete!
echo ============================================
echo.
echo Installer created at:
echo   installer\installer_output\RetailPOS-PrintHelper-Setup.exe
echo.
echo File size:
dir "installer\installer_output\RetailPOS-PrintHelper-Setup.exe" | findstr "Setup"
echo.
pause

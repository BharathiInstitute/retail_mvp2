# RetailPOS Print Helper - Silent Background Launcher
# This script starts the Node.js print server hidden in background

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$nodePath = Join-Path $scriptDir "node\node.exe"
$serverPath = Join-Path $scriptDir "server.js"

# Check if already running
$running = Get-NetTCPConnection -LocalPort 5005 -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "Print Helper is already running."
    exit 0
}

# Start Node.js hidden
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $nodePath
$psi.Arguments = "`"$serverPath`""
$psi.WorkingDirectory = $scriptDir
$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$psi.CreateNoWindow = $true
$psi.UseShellExecute = $false

[System.Diagnostics.Process]::Start($psi) | Out-Null
Write-Host "Print Helper started."

# =====================================================================
# install.ps1  -  Universal XMR Miner Installer for Windows
# Run as Administrator:
#   irm https://raw.githubusercontent.com/Luvin-Max/xmr-miner-setup/main/install.ps1 | iex
# =====================================================================

$REPO = "https://raw.githubusercontent.com/Luvin-Max/xmr-miner-setup/main"

Write-Host ""
Write-Host "=== XMR Miner Universal Installer ===" -ForegroundColor Cyan
Write-Host ""
Write-Host ">> Platform detected: Windows" -ForegroundColor Green
Write-Host ">> Downloading xmr-windows-setup.ps1..." -ForegroundColor Green

$TMP = "$env:TEMP\xmr-windows-setup.ps1"
$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -Uri "$REPO/xmr-windows-setup.ps1" -OutFile $TMP -UseBasicParsing

Write-Host ">> Running setup..." -ForegroundColor Green
& powershell -ExecutionPolicy Bypass -File $TMP

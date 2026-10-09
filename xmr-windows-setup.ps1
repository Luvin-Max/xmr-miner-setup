# =====================================================================
# xmr-windows-setup.ps1  -  Monero XMR Mining Setup for Windows
# Run: Right-click -> "Run with PowerShell" (as Administrator)
#   OR  powershell -ExecutionPolicy Bypass -File xmr-windows-setup.ps1
# =====================================================================

param()

$BASE = "C:\monero-miner"
$XMRIG_VERSION = "6.21.0"
$XMRIG_URL = "https://github.com/xmrig/xmrig/releases/download/v$XMRIG_VERSION/xmrig-$XMRIG_VERSION-msvc-win64.zip"
$CONFIG_FILE = "$BASE\config.env"
$TASK_NAME = "MoneroMiner"

Write-Host "=== Windows XMR Miner Setup ===" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------
# 1. Check Administrator
# ---------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: Administrator-ஆ run பண்ணணும்!" -ForegroundColor Red
    Write-Host "Right-click -> 'Run as Administrator'" -ForegroundColor Yellow
    pause
    exit 1
}

# ---------------------------------------------------------------------
# 2. Check / Install required tools
# ---------------------------------------------------------------------
Write-Host ">> Checking prerequisites..." -ForegroundColor Green

# Check PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "ERROR: PowerShell 5+ தேவை. Windows Update run பண்ணு" -ForegroundColor Red
    exit 1
}

# Check curl/wget availability
$hasCurl = $null -ne (Get-Command curl.exe -ErrorAction SilentlyContinue)
$hasWget = $null -ne (Get-Command wget.exe -ErrorAction SilentlyContinue)

if (-not $hasCurl -and -not $hasWget) {
    Write-Host ">> Using PowerShell built-in download (Invoke-WebRequest)..." -ForegroundColor Yellow
}

# Disable Windows Defender exclusion (required for xmrig)
Write-Host ">> Adding Defender exclusion for $BASE..." -ForegroundColor Green
try {
    Add-MpPreference -ExclusionPath $BASE -ErrorAction SilentlyContinue
    Write-Host "   Exclusion added OK" -ForegroundColor Green
} catch {
    Write-Host "   WARNING: Defender exclusion failed (add manually if needed)" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------
# 3. Create folders
# ---------------------------------------------------------------------
Write-Host ">> Creating folders..." -ForegroundColor Green
New-Item -ItemType Directory -Path $BASE -Force | Out-Null
New-Item -ItemType Directory -Path "$BASE\logs" -Force | Out-Null
New-Item -ItemType Directory -Path "$BASE\bin" -Force | Out-Null

# ---------------------------------------------------------------------
# 4. config.env
# ---------------------------------------------------------------------
if (-not (Test-Path $CONFIG_FILE)) {
    $configContent = @"
# ---- EDIT THESE ----
POOL_URL=pool.supportxmr.com
POOL_PORT=3333
XMR_ADDRESS=85okoZ4X9b3jBqCTKFavmLVyvDsaYX3Fs6g6s9cuQt1MKLfHaNd2vAG7uJNfLYgQqwJNG8BDFBN8z6n6hwWeBJRWPDLHGy6
POOL_PASS=x
MINER_THREADS=4
WORKER_NAME=windows-1
CPU_LIMIT=80
"@
    $configContent | Out-File -FilePath $CONFIG_FILE -Encoding ASCII
    Write-Host ">> config.env created -> XMR_ADDRESS மாத்தணும்!" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------
# 5. Download xmrig
# ---------------------------------------------------------------------
if (-not (Test-Path "$BASE\xmrig.exe")) {
    Write-Host ">> Downloading xmrig v$XMRIG_VERSION..." -ForegroundColor Green
    $zipPath = "$BASE\xmrig.zip"

    try {
        # Try curl first (faster)
        if ($hasCurl) {
            curl.exe -L -o $zipPath $XMRIG_URL
        } else {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $XMRIG_URL -OutFile $zipPath -UseBasicParsing
        }

        Write-Host ">> Extracting..." -ForegroundColor Green
        Expand-Archive -Path $zipPath -DestinationPath "$BASE\tmp" -Force
        $xmrigFolder = Get-ChildItem "$BASE\tmp" -Directory | Select-Object -First 1
        Copy-Item "$($xmrigFolder.FullName)\xmrig.exe" "$BASE\xmrig.exe"
        Remove-Item -Recurse -Force "$BASE\tmp"
        Remove-Item -Force $zipPath
        Write-Host ">> xmrig.exe ready!" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Download failed - $_" -ForegroundColor Red
        Write-Host "Manual download: $XMRIG_URL" -ForegroundColor Yellow
        Write-Host "Extract xmrig.exe to $BASE\" -ForegroundColor Yellow
        pause
        exit 1
    }
}

# ---------------------------------------------------------------------
# 6. start-miner.bat (reads config.env and starts xmrig)
# ---------------------------------------------------------------------
$startBat = @'
@echo off
set BASE=C:\monero-miner
set CONFIG=%BASE%\config.env

REM Read config.env
for /f "tokens=1,2 delims==" %%A in ('type "%CONFIG%"') do (
    set %%A=%%B
)

echo Starting XMR miner...
echo Pool: %POOL_URL%:%POOL_PORT%
echo Worker: %WORKER_NAME%
echo Threads: %MINER_THREADS%
echo.

"%BASE%\xmrig.exe" ^
  -o %POOL_URL%:%POOL_PORT% ^
  -u %XMR_ADDRESS% ^
  -p %POOL_PASS% ^
  -t %MINER_THREADS% ^
  --rig-id=%WORKER_NAME% ^
  --randomx-no-rdmsr ^
  --log-file="%BASE%\logs\miner.log"
'@
$startBat | Out-File -FilePath "$BASE\bin\start-miner.bat" -Encoding ASCII

# ---------------------------------------------------------------------
# 7. xmrctl.ps1 - control script
# ---------------------------------------------------------------------
$xmrctl = @'
# xmrctl.ps1 - Monero miner control for Windows
# Usage: .\xmrctl.ps1 start|stop|status|logs|hashrate|enable|disable

param([string]$Action = "status", [string]$Value = "")

$BASE = "C:\monero-miner"
$TASK = "MoneroMiner"
$LOG  = "$BASE\logs\miner.log"

# Read config
$config = @{}
Get-Content "$BASE\config.env" | Where-Object { $_ -match "^[^#].*=" } | ForEach-Object {
    $parts = $_ -split "=", 2
    $config[$parts[0].Trim()] = $parts[1].Trim()
}

switch ($Action) {
    "start" {
        $existing = Get-Process xmrig -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Host "Already running! PID: $($existing.Id)"
        } else {
            Start-Process -FilePath "$BASE\xmrig.exe" `
                -ArgumentList "-o $($config.POOL_URL):$($config.POOL_PORT) -u $($config.XMR_ADDRESS) -p $($config.POOL_PASS) -t $($config.MINER_THREADS) --rig-id=$($config.WORKER_NAME) --randomx-no-rdmsr --log-file=`"$LOG`"" `
                -WindowStyle Minimized
            Write-Host "Miner started!" -ForegroundColor Green
            Write-Host "Logs: xmrctl logs"
        }
    }
    "stop" {
        $proc = Get-Process xmrig -ErrorAction SilentlyContinue
        if ($proc) {
            Stop-Process -Name xmrig -Force
            Write-Host "Miner stopped!" -ForegroundColor Yellow
        } else {
            Write-Host "Not running"
        }
    }
    "restart" {
        & "$PSCommandPath" stop
        Start-Sleep 2
        & "$PSCommandPath" start
    }
    "status" {
        $proc = Get-Process xmrig -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Host "Status:   RUNNING (PID: $($proc.Id))" -ForegroundColor Green
            Write-Host "CPU:      $([math]::Round($proc.CPU, 1))s total"
        } else {
            Write-Host "Status:   STOPPED" -ForegroundColor Red
        }
        Write-Host "Pool:     $($config.POOL_URL):$($config.POOL_PORT)"
        Write-Host "Worker:   $($config.WORKER_NAME)"
        Write-Host "Threads:  $($config.MINER_THREADS)"
        $task = Get-ScheduledTask -TaskName $TASK -ErrorAction SilentlyContinue
        if ($task) { Write-Host "AutoStart: ENABLED (Scheduled Task)" -ForegroundColor Green }
        else { Write-Host "AutoStart: DISABLED" -ForegroundColor Yellow }
    }
    "logs" {
        if (Test-Path $LOG) {
            Get-Content $LOG -Tail 30 -Wait
        } else {
            Write-Host "No log file yet. Start miner first."
        }
    }
    "hashrate" {
        if (Test-Path $LOG) {
            Select-String "speed" $LOG | Select-Object -Last 5 | ForEach-Object { $_.Line }
        } else {
            Write-Host "No log file yet."
        }
    }
    "enable" {
        # Create Scheduled Task to auto-start at login
        $action  = New-ScheduledTaskAction -Execute "$BASE\xmrig.exe" `
            -Argument "-o $($config.POOL_URL):$($config.POOL_PORT) -u $($config.XMR_ADDRESS) -p $($config.POOL_PASS) -t $($config.MINER_THREADS) --rig-id=$($config.WORKER_NAME) --randomx-no-rdmsr --log-file=`"$LOG`""
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -Priority 7 -MultipleInstances IgnoreNew
        Register-ScheduledTask -TaskName $TASK -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null
        Write-Host "Auto-start ENABLED (starts when you log in)" -ForegroundColor Green
    }
    "disable" {
        Unregister-ScheduledTask -TaskName $TASK -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "Auto-start DISABLED" -ForegroundColor Yellow
    }
    "threads" {
        if ($Value) {
            (Get-Content "$BASE\config.env") -replace "^MINER_THREADS=.*", "MINER_THREADS=$Value" |
                Set-Content "$BASE\config.env"
            Write-Host "Threads set to $Value. Restart: xmrctl restart"
        } else {
            Write-Host "Current: $($config.MINER_THREADS)"
        }
    }
    default {
        Write-Host "Usage: .\xmrctl.ps1 <command>" -ForegroundColor Cyan
        Write-Host "  start / stop / restart  - control miner"
        Write-Host "  status                  - show status"
        Write-Host "  logs                    - live log tail"
        Write-Host "  hashrate                - recent hashrate"
        Write-Host "  enable / disable        - auto-start on login"
        Write-Host "  threads <n>             - set thread count"
    }
}
'@
$xmrctl | Out-File -FilePath "$BASE\bin\xmrctl.ps1" -Encoding ASCII

# ---------------------------------------------------------------------
# 8. Create desktop shortcut for easy control
# ---------------------------------------------------------------------
$shortcutPath = "$env:USERPROFILE\Desktop\XMR Miner.lnk"
$wsh = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = "-ExecutionPolicy Bypass -File `"$BASE\bin\xmrctl.ps1`" status"
$shortcut.WorkingDirectory = "$BASE\bin"
$shortcut.Description = "XMR Miner Control"
$shortcut.Save()

# ---------------------------------------------------------------------
# 9. Add to PATH
# ---------------------------------------------------------------------
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentPath -notlike "*$BASE\bin*") {
    [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$BASE\bin", "User")
    Write-Host ">> Added $BASE\bin to PATH" -ForegroundColor Green
}

Write-Host ""
Write-Host "==== Windows XMR Setup Complete ====" -ForegroundColor Cyan
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Edit config (add your wallet address):"
Write-Host "   notepad $CONFIG_FILE"
Write-Host "   -> XMR_ADDRESS = your Monero address (95 chars, starts with 4)"
Write-Host ""
Write-Host "2. Start miner:"
Write-Host "   powershell -ExecutionPolicy Bypass -File C:\monero-miner\bin\xmrctl.ps1 start"
Write-Host ""
Write-Host "3. Enable auto-start on login:"
Write-Host "   powershell -ExecutionPolicy Bypass -File C:\monero-miner\bin\xmrctl.ps1 enable"
Write-Host ""
Write-Host "4. Check status:"
Write-Host "   powershell -ExecutionPolicy Bypass -File C:\monero-miner\bin\xmrctl.ps1 status"
Write-Host ""
Write-Host "5. View logs:"
Write-Host "   powershell -ExecutionPolicy Bypass -File C:\monero-miner\bin\xmrctl.ps1 logs"
Write-Host ""
Write-Host "Desktop shortcut created: 'XMR Miner' on your Desktop" -ForegroundColor Green
Write-Host ""
Write-Host "NOTE: Windows Defender Exclusion added for $BASE" -ForegroundColor Yellow
Write-Host "NOTE: If Defender blocks xmrig.exe, add exclusion manually:" -ForegroundColor Yellow
Write-Host "   Windows Security -> Virus & threat -> Exclusions -> Add $BASE" -ForegroundColor Yellow
Write-Host ""
pause

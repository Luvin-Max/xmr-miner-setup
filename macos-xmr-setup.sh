#!/usr/bin/env bash
# =====================================================================
# macos-xmr-setup.sh  -  Monero XMR Mining Setup for macOS
# Run: bash macos-xmr-setup.sh
# Supports: macOS 11+ (Intel & Apple Silicon M1/M2/M3)
# =====================================================================

BASE="$HOME/monero-miner"
XMRIG_VER="6.21.0"
CONFIG="$BASE/config.env"

echo "=== macOS XMR Miner Setup ==="
echo ""

# ---------------------------------------------------------------------
# 1. macOS version check
# ---------------------------------------------------------------------
MACOS_VER=$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)
if [ -z "$MACOS_VER" ]; then
  echo "ERROR: இது macOS-ல மட்டும் run ஆகும்!"
  exit 1
fi

# ---------------------------------------------------------------------
# 2. Architecture detect (Intel or Apple Silicon)
# ---------------------------------------------------------------------
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  XMRIG_ARCH="macos-x64"  ; ARCH_NAME="Intel" ;;
  arm64)   XMRIG_ARCH="macos-arm64" ; ARCH_NAME="Apple Silicon (M1/M2/M3)" ;;
  *)       echo "ERROR: Unknown arch: $ARCH"; exit 1 ;;
esac
echo ">> Architecture: $ARCH_NAME ($ARCH)"

# ---------------------------------------------------------------------
# 3. Homebrew check + install
# ---------------------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
  echo ">> Homebrew இல்ல — install பண்றோம்..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Apple Silicon homebrew path
  if [ "$ARCH" = "arm64" ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
  fi
else
  echo ">> Homebrew already installed"
fi

# ---------------------------------------------------------------------
# 4. Required packages
# ---------------------------------------------------------------------
echo ">> Installing required packages..."
brew install wget curl libuv openssl cmake 2>/dev/null || true

# ---------------------------------------------------------------------
# 5. Setup folders
# ---------------------------------------------------------------------
mkdir -p "$BASE/bin" "$BASE/logs"

# ---------------------------------------------------------------------
# 6. config.env
# ---------------------------------------------------------------------
if [ ! -f "$CONFIG" ]; then
THREADS=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)
cat > "$CONFIG" <<EOF
# ---- EDIT THESE ----
POOL_URL=pool.supportxmr.com
POOL_PORT=3333
XMR_ADDRESS=85okoZ4X9b3jBqCTKFavmLVyvDsaYX3Fs6g6s9cuQt1MKLfHaNd2vAG7uJNfLYgQqwJNG8BDFBN8z6n6hwWeBJRWPDLHGy6
POOL_PASS=x
MINER_THREADS=$THREADS
WORKER_NAME=mac-miner-1
CPU_LIMIT=80
EOF
echo ">> config.env created (threads=$THREADS) -> XMR_ADDRESS மாத்தணும்!"
fi

# ---------------------------------------------------------------------
# 7. Download xmrig
# ---------------------------------------------------------------------
if [ ! -f "$BASE/xmrig" ]; then
  echo ">> Downloading xmrig v${XMRIG_VER} (${ARCH_NAME})..."
  XMRIG_URL="https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VER}/xmrig-${XMRIG_VER}-${XMRIG_ARCH}.tar.gz"
  cd /tmp
  curl -fsSL "$XMRIG_URL" -o xmrig.tar.gz
  tar xzf xmrig.tar.gz
  cp "xmrig-${XMRIG_VER}/xmrig" "$BASE/xmrig"
  chmod +x "$BASE/xmrig"
  rm -rf "xmrig-${XMRIG_VER}" xmrig.tar.gz

  # macOS Gatekeeper quarantine remove
  xattr -d com.apple.quarantine "$BASE/xmrig" 2>/dev/null || true
  echo ">> xmrig installed!"
fi

# ---------------------------------------------------------------------
# 8. LaunchAgent (macOS auto-start = launchd, not systemd)
# ---------------------------------------------------------------------
PLIST="$HOME/Library/LaunchAgents/com.xmr.miner.plist"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.xmr.miner</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BASE/bin/start-miner.sh</string>
  </array>
  <key>RunAtLoad</key>
  <false/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$BASE/logs/miner.log</string>
  <key>StandardErrorPath</key>
  <string>$BASE/logs/miner.log</string>
  <key>ProcessType</key>
  <string>Background</string>
  <key>Nice</key>
  <integer>10</integer>
</dict>
</plist>
EOF

# ---------------------------------------------------------------------
# 9. start-miner.sh (launchd wrapper)
# ---------------------------------------------------------------------
cat > "$BASE/bin/start-miner.sh" <<'EOF'
#!/usr/bin/env bash
BASE="$HOME/monero-miner"
source "$BASE/config.env"
exec "$BASE/xmrig" \
  -o "${POOL_URL}:${POOL_PORT}" \
  -u "$XMR_ADDRESS" \
  -p "$POOL_PASS" \
  -t "$MINER_THREADS" \
  --rig-id="$WORKER_NAME" \
  --randomx-no-rdmsr
EOF
chmod +x "$BASE/bin/start-miner.sh"

# ---------------------------------------------------------------------
# 10. xmrctl control command
# ---------------------------------------------------------------------
cat > "$BASE/bin/xmrctl" <<'XMRCTL'
#!/usr/bin/env bash
BASE="$HOME/monero-miner"
source "$BASE/config.env"
PLIST="$HOME/Library/LaunchAgents/com.xmr.miner.plist"
LABEL="com.xmr.miner"
LOGFILE="$BASE/logs/miner.log"

case "${1:-}" in
  start)
    launchctl load "$PLIST" 2>/dev/null || true
    launchctl start "$LABEL"
    echo "Miner started!"
    ;;
  stop)
    launchctl stop "$LABEL" 2>/dev/null || true
    echo "Miner stopped!"
    ;;
  restart)
    "$0" stop; sleep 2; "$0" start
    ;;
  status)
    RUNNING=$(launchctl list "$LABEL" 2>/dev/null | grep '"PID"' | awk '{print $3}' | tr -d ';')
    if [ -n "$RUNNING" ] && [ "$RUNNING" != "0" ]; then
      echo "Status:  RUNNING (PID: $RUNNING)"
    else
      echo "Status:  STOPPED"
    fi
    echo "Pool:    $POOL_URL:$POOL_PORT"
    echo "Threads: $MINER_THREADS"
    echo "Worker:  $WORKER_NAME"
    AUTOSTART=$(launchctl list "$LABEL" 2>/dev/null | grep -c "RunAtLoad" || echo 0)
    ;;
  logs)
    tail -n "${2:-50}" -f "$LOGFILE"
    ;;
  hashrate)
    grep "speed" "$LOGFILE" 2>/dev/null | tail -5 || echo "No data yet"
    ;;
  enable)
    # RunAtLoad true set பண்ணு
    /usr/libexec/PlistBuddy -c "Set :RunAtLoad true" "$PLIST"
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST"
    echo "Auto-start ENABLED (login-ல automatically start ஆகும்)"
    ;;
  disable)
    /usr/libexec/PlistBuddy -c "Set :RunAtLoad false" "$PLIST"
    launchctl unload "$PLIST" 2>/dev/null || true
    echo "Auto-start DISABLED"
    ;;
  threads)
    if [ -n "${2:-}" ]; then
      sed -i '' "s/^MINER_THREADS=.*/MINER_THREADS=$2/" "$BASE/config.env"
      echo "Threads set to $2. Restart: xmrctl restart"
    else
      grep "^MINER_THREADS=" "$BASE/config.env"
    fi
    ;;
  cpu-limit)
    if [ -n "${2:-}" ]; then
      sed -i '' "s/^CPU_LIMIT=.*/CPU_LIMIT=$2/" "$BASE/config.env"
      echo "CPU limit set to $2%. Restart: xmrctl restart"
    else
      grep "^CPU_LIMIT=" "$BASE/config.env"
    fi
    ;;
  *)
    echo "Usage: xmrctl start|stop|restart|status|logs|hashrate|enable|disable|threads|cpu-limit"
    ;;
esac
XMRCTL
chmod +x "$BASE/bin/xmrctl"

# PATH add
SHELL_RC="$HOME/.zshrc"
[ -n "$BASH_VERSION" ] && SHELL_RC="$HOME/.bashrc"
if ! grep -q "monero-miner/bin" "$SHELL_RC" 2>/dev/null; then
  echo 'export PATH="$HOME/monero-miner/bin:$PATH"' >> "$SHELL_RC"
fi
export PATH="$BASE/bin:$PATH"

echo ""
echo "==== macOS XMR Setup Complete ===="
echo ""
echo "1. Config edit:  nano ~/monero-miner/config.env"
echo "   -> XMR_ADDRESS போடு"
echo ""
echo "2. Start:        xmrctl start"
echo "3. Status:       xmrctl status"
echo "4. Logs:         xmrctl logs"
echo "5. Auto-start:   xmrctl enable"
echo "6. Stop:         xmrctl stop"
echo ""
echo "NOTE: Mac-ல mining hashrate Linux-ஐ விட கம்மியா இருக்கும்"
echo "NOTE: Battery drain அதிகமா இருக்கும் — charger-ல வை"

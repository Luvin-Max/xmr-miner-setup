#!/data/data/com.termux/files/usr/bin/bash
# =====================================================================
# termux-xmr-setup.sh  -  Monero XMR mining on Android (Termux)
# Run: bash termux-xmr-setup.sh
# NO root needed, NO sudo needed
# =====================================================================

BASE="$HOME/monero-miner"
CONFIG="$BASE/config.env"
XMRIG_VER="6.21.0"

echo "=== Termux XMR Miner Setup ==="
echo ""

# ---------------------------------------------------------------------
# 1. Check Termux
# ---------------------------------------------------------------------
if [ -z "$TERMUX_VERSION" ] && [ ! -d "/data/data/com.termux" ]; then
  echo "ERROR: இது Termux-ல மட்டும் run ஆகும்!"
  echo "Play Store / F-Droid-ல Termux install பண்ணு"
  exit 1
fi

# ---------------------------------------------------------------------
# 2. Disk space check (குறைந்தது 150MB வேணும்)
# ---------------------------------------------------------------------
AVAIL_KB=$(df "$HOME" 2>/dev/null | awk 'NR==2{print $4}')
AVAIL_MB=$((${AVAIL_KB:-0} / 1024))
echo ">> Available disk space: ${AVAIL_MB}MB"
if [ "$AVAIL_MB" -lt 100 ]; then
  echo ""
  echo "ERROR: Disk space மிகவும் கம்மி! (${AVAIL_MB}MB இருக்கு, 100MB+ வேணும்)"
  echo ""
  echo "Phone Settings -> Storage-ல போய் files delete பண்ணு"
  echo "அல்லது unused apps remove பண்ணு"
  exit 1
fi

# ---------------------------------------------------------------------
# 3. Mirror fix — packages.termux.dev use பண்ணு (most reliable)
# ---------------------------------------------------------------------
echo ">> Fixing Termux mirror..."
mkdir -p "$PREFIX/etc/termux"
echo "deb https://packages.termux.dev/apt/termux-main stable main" > "$PREFIX/etc/apt/sources.list"
mkdir -p /data/data/com.termux/cache/apt/archives/partial

# ---------------------------------------------------------------------
# 4. Minimal packages only (curl மட்டும் வேணும்)
# ---------------------------------------------------------------------
echo ">> Installing curl..."
pkg update -y 2>/dev/null || true
pkg install -y curl 2>/dev/null || apt-get install -y curl 2>/dev/null || true

# ---------------------------------------------------------------------
# 5. Setup folder
# ---------------------------------------------------------------------
mkdir -p "$BASE/bin" "$BASE/logs"

# ---------------------------------------------------------------------
# 6. config.env
# ---------------------------------------------------------------------
if [ ! -f "$CONFIG" ]; then
cat > "$CONFIG" <<'EOF'
# ---- EDIT THESE ----
POOL_URL=pool.supportxmr.com
POOL_PORT=3333
XMR_ADDRESS=85okoZ4X9b3jBqCTKFavmLVyvDsaYX3Fs6g6s9cuQt1MKLfHaNd2vAG7uJNfLYgQqwJNG8BDFBN8z6n6hwWeBJRWPDLHGy6
POOL_PASS=x
MINER_THREADS=2
WORKER_NAME=android-1
CPU_LIMIT=80
EOF
echo ">> config.env created!"
fi

# ---------------------------------------------------------------------
# 7. Download xmrig pre-built static binary (NO build needed!)
#    - x86_64 Android: Linux static binary works in Termux
#    - aarch64 Android: Linux aarch64 static binary works in Termux
# ---------------------------------------------------------------------
if [ ! -f "$BASE/xmrig" ]; then
  ARCH=$(uname -m)
  echo ">> Architecture: $ARCH"

  case "$ARCH" in
    x86_64)
      XMRIG_URL="https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VER}/xmrig-${XMRIG_VER}-linux-static-x64.tar.gz"
      XMRIG_DIR="xmrig-${XMRIG_VER}"
      ;;
    aarch64|arm64)
      XMRIG_URL="https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VER}/xmrig-${XMRIG_VER}-linux-static-aarch64.tar.gz"
      XMRIG_DIR="xmrig-${XMRIG_VER}"
      ;;
    armv7l|armv8l)
      XMRIG_URL="https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VER}/xmrig-${XMRIG_VER}-linux-armv7.tar.gz"
      XMRIG_DIR="xmrig-${XMRIG_VER}"
      ;;
    *)
      echo "ERROR: Unknown architecture: $ARCH"
      exit 1
      ;;
  esac

  echo ">> Downloading xmrig v${XMRIG_VER} (static binary, no build needed)..."
  echo ">> URL: $XMRIG_URL"

  TMP_DIR="${TMPDIR:-$PREFIX/tmp}"
  mkdir -p "$TMP_DIR"
  cd "$TMP_DIR"

  if curl -fsSL --retry 3 --retry-delay 2 "$XMRIG_URL" -o xmrig.tar.gz; then
    tar xzf xmrig.tar.gz
    # Find xmrig binary in extracted folder
    XMRIG_BIN=$(find "$TMP_DIR" -name "xmrig" -type f 2>/dev/null | head -1)
    if [ -n "$XMRIG_BIN" ]; then
      cp "$XMRIG_BIN" "$BASE/xmrig"
      chmod +x "$BASE/xmrig"
      rm -f xmrig.tar.gz
      rm -rf "$TMP_DIR/xmrig-${XMRIG_VER}" 2>/dev/null || true
      echo ">> xmrig downloaded and ready!"
    else
      echo "ERROR: xmrig binary not found in archive!"
      exit 1
    fi
  else
    echo "ERROR: Download failed! Internet connection check பண்ணு."
    exit 1
  fi
fi

# ---------------------------------------------------------------------
# 8. Verify binary works
# ---------------------------------------------------------------------
echo ">> Verifying xmrig binary..."
if "$BASE/xmrig" --version >/dev/null 2>&1; then
  echo ">> xmrig OK: $($BASE/xmrig --version 2>/dev/null | head -1)"
else
  echo "WARNING: Binary verify failed — may still work on start"
fi

# ---------------------------------------------------------------------
# 6. xmrctl control script
# ---------------------------------------------------------------------
cat > "$BASE/bin/xmrctl" <<'XMRCTL'
#!/data/data/com.termux/files/usr/bin/bash
BASE="$HOME/monero-miner"
source "$BASE/config.env"
PIDFILE="$BASE/miner.pid"
LOGFILE="$BASE/logs/miner.log"

case "${1:-}" in
  start)
    if [ -f "$PIDFILE" ] && kill -0 $(cat "$PIDFILE") 2>/dev/null; then
      echo "Already running! PID: $(cat $PIDFILE)"
      exit 0
    fi
    echo "Starting miner..."
    nohup "$BASE/xmrig" \
      -o "${POOL_URL}:${POOL_PORT}" \
      -u "$XMR_ADDRESS" \
      -p "$POOL_PASS" \
      -t "$MINER_THREADS" \
      --rig-id="$WORKER_NAME" \
      --randomx-no-rdmsr \
      >> "$LOGFILE" 2>&1 &
    echo $! > "$PIDFILE"
    echo "Started! PID: $(cat $PIDFILE)"
    echo "Logs: xmrctl logs"
    ;;
  stop)
    if [ -f "$PIDFILE" ]; then
      kill $(cat "$PIDFILE") 2>/dev/null && echo "Stopped!" || echo "Already stopped"
      rm -f "$PIDFILE"
    else
      echo "Not running"
    fi
    ;;
  restart)
    "$0" stop; sleep 2; "$0" start
    ;;
  status)
    if [ -f "$PIDFILE" ] && kill -0 $(cat "$PIDFILE") 2>/dev/null; then
      echo "Status:  RUNNING (PID: $(cat $PIDFILE))"
    else
      echo "Status:  STOPPED"
    fi
    echo "Pool:    $POOL_URL:$POOL_PORT"
    echo "Threads: $MINER_THREADS"
    echo "Worker:  $WORKER_NAME"
    ;;
  logs)
    tail -n "${2:-30}" -f "$LOGFILE"
    ;;
  hashrate)
    grep "speed" "$LOGFILE" 2>/dev/null | tail -5 || echo "No hashrate data yet"
    ;;
  enable)
    # termux-boot install பண்ணி auto-start setup
    pkg install -y termux-boot 2>/dev/null || true
    mkdir -p "$HOME/.termux/boot"
    cat > "$HOME/.termux/boot/xmr-miner.sh" <<'BOOT'
#!/data/data/com.termux/files/usr/bin/bash
sleep 10
BASE="$HOME/monero-miner"
source "$BASE/config.env"
LOGFILE="$BASE/logs/miner.log"
PIDFILE="$BASE/miner.pid"
nohup "$BASE/xmrig" \
  -o "${POOL_URL}:${POOL_PORT}" \
  -u "$XMR_ADDRESS" \
  -p "$POOL_PASS" \
  -t "$MINER_THREADS" \
  --rig-id="$WORKER_NAME" \
  --randomx-no-rdmsr \
  >> "$LOGFILE" 2>&1 &
echo $! > "$PIDFILE"
BOOT
    chmod +x "$HOME/.termux/boot/xmr-miner.sh"
    echo "Auto-start ENABLED!"
    echo "Phone restart ஆகும்போது automatically mine start ஆகும்"
    echo "NOTE: Termux:Boot app-ஐ Play Store / F-Droid-ல install பண்ணு"
    ;;
  disable)
    rm -f "$HOME/.termux/boot/xmr-miner.sh"
    echo "Auto-start DISABLED"
    ;;
  *)
    echo "Usage: xmrctl start|stop|restart|status|logs|hashrate|enable|disable"
    ;;
esac
XMRCTL
chmod +x "$BASE/bin/xmrctl"

# PATH-ல add பண்ணு (.bashrc + .profile இரண்டிலும்)
for RC in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.bash_profile"; do
  if [ -f "$RC" ] || [ "$RC" = "$HOME/.bashrc" ]; then
    if ! grep -q "monero-miner/bin" "$RC" 2>/dev/null; then
      echo 'export PATH="$HOME/monero-miner/bin:$PATH"' >> "$RC"
    fi
  fi
done
export PATH="$BASE/bin:$PATH"

# /usr/bin-ல symlink வை (Termux-ல always available)
ln -sf "$BASE/bin/xmrctl" "$PREFIX/bin/xmrctl" 2>/dev/null || true

echo ""
echo "==== Termux XMR Setup Complete ===="
echo ""
echo "1. Config edit:  nano ~/monero-miner/config.env"
echo "   -> XMR_ADDRESS போடு"
echo ""
echo "2. Start:        xmrctl start"
echo "3. Status:       xmrctl status"
echo "4. Logs:         xmrctl logs"
echo "5. Stop:         xmrctl stop"
echo ""
echo "NOTE: Phone charge-ல வை, screen off-ஆ இருந்தாலும் mine ஆகும்"
echo "NOTE: Battery > 20% இருக்கும்போது மட்டும் run பண்ணு"

#!/data/data/com.termux/files/usr/bin/bash
# =====================================================================
# termux-xmr-setup.sh  -  Monero XMR mining on Android (Termux)
# Run: bash termux-xmr-setup.sh
# NO root needed, NO sudo needed
# =====================================================================

BASE="$HOME/monero-miner"
CONFIG="$BASE/config.env"

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
# 2. Required packages install
# ---------------------------------------------------------------------
echo ">> Packages update + install பண்றோம்..."
pkg update -y 2>/dev/null || true
pkg upgrade -y 2>/dev/null || true
pkg install -y wget curl nano termux-tools 2>/dev/null || true

# xmrig Termux-ல direct build வேணும் (pre-built binary work ஆகாது)
echo ">> xmrig build dependencies install பண்றோம்..."
pkg install -y clang cmake make libuv openssl libjansson git 2>/dev/null

# ---------------------------------------------------------------------
# 3. Setup folder
# ---------------------------------------------------------------------
mkdir -p "$BASE/bin" "$BASE/logs"

# ---------------------------------------------------------------------
# 4. config.env
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
echo ">> config.env created -> XMR_ADDRESS மாத்தணும்!"
fi

# ---------------------------------------------------------------------
# 5. Build xmrig from source (Termux-ku required)
# ---------------------------------------------------------------------
if [ ! -f "$BASE/xmrig" ]; then
  echo ">> xmrig build பண்றோம் (10-20 minutes ஆகலாம்)..."
  BUILD_TMP="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/xmrig-build"
  mkdir -p "$BUILD_TMP"
  cd "$BUILD_TMP"
  if [ -d "xmrig" ]; then rm -rf xmrig; fi
  git clone https://github.com/xmrig/xmrig.git
  cd xmrig
  mkdir build && cd build
  cmake .. \
    -DWITH_OPENCL=OFF \
    -DWITH_CUDA=OFF \
    -DWITH_HWLOC=OFF \
    -DCMAKE_BUILD_TYPE=Release
  make -j$(nproc)
  cp xmrig "$BASE/xmrig"
  chmod +x "$BASE/xmrig"
  cd "$HOME"
  rm -rf "$BUILD_TMP"
  echo ">> xmrig build complete!"
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

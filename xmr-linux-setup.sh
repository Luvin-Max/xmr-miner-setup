#!/usr/bin/env bash
# =====================================================================
# xmr-linux-setup.sh  -  Monero XMR Mining, Generic Linux
# Supports: Ubuntu / Debian / RHEL / Fedora / CentOS / Arch / Alpine
# Run: sudo bash xmr-linux-setup.sh
# =====================================================================
set -euo pipefail

BASE=/opt/monero-miner
XMRIG_VER=6.21.0
CONFIG="$BASE/config.env"

# Auto-detect run user (sudo caller or current user)
if [ -n "${SUDO_USER:-}" ]; then
  RUN_USER="$SUDO_USER"
else
  RUN_USER="$(whoami)"
fi
# fallback if running as root directly
[ "$RUN_USER" = "root" ] && RUN_USER="root"

echo "=== Generic Linux XMR Miner Setup ==="
echo "Run user: $RUN_USER"
echo ""

# ---------------------------------------------------------------------
# 1. Root check
# ---------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: sudo-வ run பண்ணணும்!"
  echo "  sudo bash xmr-linux-setup.sh"
  exit 1
fi

# ---------------------------------------------------------------------
# 2. Detect distro + install packages
# ---------------------------------------------------------------------
install_packages() {
  local pkgs="$*"
  echo ">> Installing: $pkgs"

  if command -v apt-get >/dev/null 2>&1; then
    # Debian / Ubuntu
    apt-get update -qq
    apt-get install -y $pkgs

  elif command -v dnf >/dev/null 2>&1; then
    # Fedora / RHEL 8+
    dnf install -y $pkgs

  elif command -v yum >/dev/null 2>&1; then
    # CentOS 7 / older RHEL
    yum install -y $pkgs

  elif command -v pacman >/dev/null 2>&1; then
    # Arch Linux
    pacman -Sy --noconfirm $pkgs

  elif command -v apk >/dev/null 2>&1; then
    # Alpine Linux
    apk add --no-cache $pkgs

  elif command -v zypper >/dev/null 2>&1; then
    # openSUSE
    zypper install -y $pkgs

  else
    echo "WARNING: Package manager not found. Manual install required: $pkgs"
  fi
}

echo ">> Checking required packages..."
PKGS_NEEDED=""
command -v wget    >/dev/null 2>&1 || PKGS_NEEDED="$PKGS_NEEDED wget"
command -v tar     >/dev/null 2>&1 || PKGS_NEEDED="$PKGS_NEEDED tar"
command -v nano    >/dev/null 2>&1 || PKGS_NEEDED="$PKGS_NEEDED nano"

# Check libhwloc
if ! ldconfig -p 2>/dev/null | grep -q hwloc && ! find /usr/lib* /lib* -name "libhwloc*" 2>/dev/null | grep -q .; then
  if command -v apt-get >/dev/null 2>&1; then
    PKGS_NEEDED="$PKGS_NEEDED libhwloc-dev"
  elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
    PKGS_NEEDED="$PKGS_NEEDED hwloc-devel"
  fi
fi

if [ -n "$PKGS_NEEDED" ]; then
  install_packages $PKGS_NEEDED
fi

# ---------------------------------------------------------------------
# 3. Detect architecture
# ---------------------------------------------------------------------
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)            XMRIG_ARCH="linux-x64" ;;
  aarch64|arm64)     XMRIG_ARCH="linux-arm64" ;;
  armv7l|armhf)      XMRIG_ARCH="linux-armv7" ;;
  *)
    echo "ERROR: Unsupported architecture: $ARCH"
    echo "xmrig supported: x86_64, aarch64, armv7"
    exit 1
    ;;
esac
echo ">> Architecture: $ARCH -> $XMRIG_ARCH"

# ---------------------------------------------------------------------
# 4. Setup folders
# ---------------------------------------------------------------------
mkdir -p "$BASE/bin" "$BASE/logs"

# ---------------------------------------------------------------------
# 5. config.env (only if missing)
# ---------------------------------------------------------------------
if [ ! -f "$CONFIG" ]; then
THREADS=$(nproc)
cat > "$CONFIG" <<EOF
# ---- EDIT THESE ----
POOL_URL=pool.supportxmr.com
POOL_PORT=3333
XMR_ADDRESS=85okoZ4X9b3jBqCTKFavmLVyvDsaYX3Fs6g6s9cuQt1MKLfHaNd2vAG7uJNfLYgQqwJNG8BDFBN8z6n6hwWeBJRWPDLHGy6
POOL_PASS=x
MINER_THREADS=$THREADS
WORKER_NAME=linux-miner-1
CPU_LIMIT=90
EOF
echo ">> config.env created (threads=${THREADS}) -> XMR_ADDRESS மாத்தணும்!"
fi

# ---------------------------------------------------------------------
# 6. Download xmrig
# ---------------------------------------------------------------------
if [ ! -f "$BASE/xmrig" ]; then
  echo ">> Downloading xmrig v${XMRIG_VER} (${XMRIG_ARCH})..."
  XMRIG_URL="https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VER}/xmrig-${XMRIG_VER}-${XMRIG_ARCH}.tar.gz"
  cd /tmp
  wget -q "$XMRIG_URL" -O xmrig.tar.gz
  tar xzf xmrig.tar.gz
  cp "xmrig-${XMRIG_VER}/xmrig" "$BASE/xmrig"
  chmod +x "$BASE/xmrig"
  rm -rf "xmrig-${XMRIG_VER}" xmrig.tar.gz
  echo ">> xmrig installed!"
fi

# ---------------------------------------------------------------------
# 7. Huge pages
# ---------------------------------------------------------------------
echo ">> Enabling huge pages..."
if ! grep -q "vm.nr_hugepages" /etc/sysctl.conf 2>/dev/null; then
  echo "vm.nr_hugepages=1168" >> /etc/sysctl.conf
fi
sysctl -w vm.nr_hugepages=1168 >/dev/null 2>&1 || true

# ---------------------------------------------------------------------
# 8. MSR module
# ---------------------------------------------------------------------
echo ">> Loading MSR module..."
modprobe msr 2>/dev/null || true
if [ -f /etc/modules ]; then
  grep -q "^msr$" /etc/modules || echo "msr" >> /etc/modules
fi

# ---------------------------------------------------------------------
# 9. Init system detection + service setup
# ---------------------------------------------------------------------
HAS_SYSTEMD=false
HAS_OPENRC=false
HAS_RUNIT=false

if command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1; then
  HAS_SYSTEMD=true
elif command -v rc-service >/dev/null 2>&1; then
  HAS_OPENRC=true
elif command -v sv >/dev/null 2>&1; then
  HAS_RUNIT=true
fi

if $HAS_SYSTEMD; then
  echo ">> Setting up systemd service..."
  cat > /etc/systemd/system/monero-miner.service <<EOF
[Unit]
Description=Monero XMR Pool Miner (xmrig)
After=network-online.target
Wants=network-online.target

[Service]
EnvironmentFile=$BASE/config.env
User=$RUN_USER
ExecStart=/bin/bash -c 'exec $BASE/xmrig \\
  -o \${POOL_URL}:\${POOL_PORT} \\
  -u \${XMR_ADDRESS} \\
  -p \${POOL_PASS} \\
  -t \${MINER_THREADS} \\
  --rig-id=\${WORKER_NAME} \\
  --huge-pages \\
  --randomx-no-rdmsr'
Restart=always
RestartSec=10
Nice=10
CPUQuota=90%

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  echo ">> systemd service created: monero-miner.service"

elif $HAS_OPENRC; then
  echo ">> Setting up OpenRC service (Alpine/Gentoo)..."
  cat > /etc/init.d/monero-miner <<'OPENRC'
#!/sbin/openrc-run
BASE=/opt/monero-miner
PIDFILE=/run/monero-miner.pid

depend() {
    need net
}

start() {
    ebegin "Starting monero-miner"
    . "$BASE/config.env"
    start-stop-daemon --start --make-pidfile --pidfile $PIDFILE \
      --background --user "$RUN_USER" \
      --exec "$BASE/xmrig" -- \
      -o "${POOL_URL}:${POOL_PORT}" \
      -u "$XMR_ADDRESS" \
      -p "$POOL_PASS" \
      -t "$MINER_THREADS" \
      --rig-id="$WORKER_NAME" \
      --huge-pages \
      --randomx-no-rdmsr
    eend $?
}

stop() {
    ebegin "Stopping monero-miner"
    start-stop-daemon --stop --pidfile $PIDFILE
    eend $?
}
OPENRC
  chmod +x /etc/init.d/monero-miner
  echo ">> OpenRC service created"

else
  echo ">> No systemd/OpenRC found — using pid-based management (manual start)"
fi

# ---------------------------------------------------------------------
# 10. xmrctl control command
# ---------------------------------------------------------------------
cat > "$BASE/bin/xmrctl" <<'XMRCTL'
#!/usr/bin/env bash
BASE=/opt/monero-miner
source "$BASE/config.env"
PIDFILE="$BASE/miner.pid"

# Detect init system
if command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1; then
  INIT=systemd
elif command -v rc-service >/dev/null 2>&1; then
  INIT=openrc
else
  INIT=manual
fi

start_manual() {
  if [ -f "$PIDFILE" ] && kill -0 "$(cat $PIDFILE)" 2>/dev/null; then
    echo "Already running! PID: $(cat $PIDFILE)"; return
  fi
  nohup "$BASE/xmrig" \
    -o "${POOL_URL}:${POOL_PORT}" \
    -u "$XMR_ADDRESS" -p "$POOL_PASS" \
    -t "$MINER_THREADS" --rig-id="$WORKER_NAME" \
    --huge-pages --randomx-no-rdmsr \
    >> "$BASE/logs/miner.log" 2>&1 &
  echo $! > "$PIDFILE"
  echo "Started! PID: $(cat $PIDFILE)"
}

stop_manual() {
  [ -f "$PIDFILE" ] && kill "$(cat $PIDFILE)" 2>/dev/null && rm -f "$PIDFILE" && echo "Stopped!" || echo "Not running"
}

case "${1:-}" in
  start)
    case $INIT in
      systemd) sudo systemctl start monero-miner.service ;;
      openrc)  sudo rc-service monero-miner start ;;
      *)       start_manual ;;
    esac
    ;;
  stop)
    case $INIT in
      systemd) sudo systemctl stop monero-miner.service ;;
      openrc)  sudo rc-service monero-miner stop ;;
      *)       stop_manual ;;
    esac
    ;;
  restart)
    "$0" stop; sleep 2; "$0" start
    ;;
  status)
    case $INIT in
      systemd)
        ST=$(systemctl is-active monero-miner.service 2>/dev/null || echo "unknown")
        echo "Status:  $ST"
        ;;
      openrc)
        rc-service monero-miner status
        ;;
      *)
        if [ -f "$PIDFILE" ] && kill -0 "$(cat $PIDFILE)" 2>/dev/null; then
          echo "Status:  RUNNING (PID: $(cat $PIDFILE))"
        else
          echo "Status:  STOPPED"
        fi
        ;;
    esac
    echo "Pool:    $POOL_URL:$POOL_PORT"
    echo "Threads: $MINER_THREADS"
    echo "Worker:  $WORKER_NAME"
    echo "CPU:     $CPU_LIMIT%"
    echo "Pages:   $(cat /proc/sys/vm/nr_hugepages 2>/dev/null || echo unknown)"
    ;;
  logs)
    case $INIT in
      systemd) journalctl -u monero-miner.service -n "${2:-50}" -f ;;
      *)       tail -n "${2:-50}" -f "$BASE/logs/miner.log" ;;
    esac
    ;;
  hashrate)
    case $INIT in
      systemd) journalctl -u monero-miner.service -n 200 --no-pager | grep "speed" | tail -5 ;;
      *)       grep "speed" "$BASE/logs/miner.log" 2>/dev/null | tail -5 || echo "No data yet" ;;
    esac
    ;;
  enable)
    case $INIT in
      systemd) sudo systemctl enable monero-miner.service && echo "Auto-start ENABLED" ;;
      openrc)  sudo rc-update add monero-miner default && echo "Auto-start ENABLED" ;;
      *)       echo "Manual mode: Add 'xmrctl start' to /etc/rc.local or crontab @reboot" ;;
    esac
    ;;
  disable)
    case $INIT in
      systemd) sudo systemctl disable monero-miner.service && echo "Auto-start DISABLED" ;;
      openrc)  sudo rc-update del monero-miner default && echo "Auto-start DISABLED" ;;
      *)       echo "Manual mode: Remove from /etc/rc.local or crontab" ;;
    esac
    ;;
  threads)
    if [ -n "${2:-}" ]; then
      sed -i "s/^MINER_THREADS=.*/MINER_THREADS=$2/" "$BASE/config.env"
      echo "Threads set to $2. Restart: xmrctl restart"
    else
      grep "^MINER_THREADS=" "$BASE/config.env"
    fi
    ;;
  cpu-limit)
    if [ -n "${2:-}" ]; then
      sed -i "s/^CPU_LIMIT=.*/CPU_LIMIT=$2/" "$BASE/config.env"
      if [ "$INIT" = "systemd" ]; then
        sudo sed -i "s/^CPUQuota=.*/CPUQuota=$2%/" /etc/systemd/system/monero-miner.service
        sudo systemctl daemon-reload
      fi
      echo "CPU limit set to $2%. Restart: xmrctl restart"
    else
      grep "^CPU_LIMIT=" "$BASE/config.env"
    fi
    ;;
  *)
    cat <<USAGE
xmrctl commands:
  start / stop / restart      control miner
  status                      show status + config
  logs [n]                    live logs (default 50 lines)
  hashrate                    recent hashrate lines
  enable / disable            auto-start on boot
  threads <n>                 set thread count
  cpu-limit <percent>         set CPU % cap (10-100)
USAGE
    ;;
esac
XMRCTL
chmod +x "$BASE/bin/xmrctl"
ln -sf "$BASE/bin/xmrctl" /usr/local/bin/xmrctl

# ---------------------------------------------------------------------
# 11. sudoers (if sudoers.d exists)
# ---------------------------------------------------------------------
if [ -d /etc/sudoers.d ] && [ "$RUN_USER" != "root" ]; then
  cat > /etc/sudoers.d/xmrctl <<EOF
$RUN_USER ALL=(root) NOPASSWD: /usr/bin/systemctl start monero-miner.service
$RUN_USER ALL=(root) NOPASSWD: /usr/bin/systemctl stop monero-miner.service
$RUN_USER ALL=(root) NOPASSWD: /usr/bin/systemctl restart monero-miner.service
$RUN_USER ALL=(root) NOPASSWD: /usr/bin/systemctl enable monero-miner.service
$RUN_USER ALL=(root) NOPASSWD: /usr/bin/systemctl disable monero-miner.service
$RUN_USER ALL=(root) NOPASSWD: /usr/bin/systemctl daemon-reload
EOF
  chmod 440 /etc/sudoers.d/xmrctl
  echo ">> sudoers configured for $RUN_USER"
fi

# ---------------------------------------------------------------------
# 12. Ownership
# ---------------------------------------------------------------------
if [ "$RUN_USER" != "root" ]; then
  chown -R "$RUN_USER:$RUN_USER" "$BASE"
fi

# ---------------------------------------------------------------------
# Done!
# ---------------------------------------------------------------------
cat <<DONE

==== Linux XMR Setup Complete ====

NEXT STEPS:

1. Edit config (add your wallet address):
   sudo nano $CONFIG
   -> XMR_ADDRESS = your 95-char Monero address (starts with 4)

2. Start mining:
   xmrctl start

3. Enable auto-start on reboot:
   xmrctl enable

4. Check status:
   xmrctl status

5. Watch live logs:
   xmrctl logs

6. Hashrate:
   xmrctl hashrate

Other commands:
   xmrctl stop
   xmrctl cpu-limit 85
   xmrctl threads 2

Earnings check:  https://supportxmr.com
DONE

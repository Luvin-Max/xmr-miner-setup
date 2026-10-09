#!/usr/bin/env bash
# =====================================================================
# xmr-setup.sh  -  Monero XMR pool mining, full automation
# Run ONCE on EC2 Ubuntu server:   sudo bash xmr-setup.sh
#
# Creates /opt/monero-miner/ with everything inside:
#   config.env                  <- edit XMR address + pool here
#   bin/xmrig                   <- miner binary
#   bin/xmrctl                  <- start / stop / status / logs commands
#   systemd units               <- monero-miner service
# =====================================================================
set -euo pipefail

BASE=/opt/monero-miner
RUN_USER=ubuntu

if [ "$(id -u)" -ne 0 ]; then echo "Run with sudo"; exit 1; fi
mkdir -p "$BASE/bin" "$BASE/logs"

# ---------------------------------------------------------------------
# 1. config.env (only created if missing)
# ---------------------------------------------------------------------
if [ ! -f "$BASE/config.env" ]; then
cat > "$BASE/config.env" <<'EOF'
# ---- EDIT THESE ----
RUN_USER=ubuntu
POOL_URL=pool.moneroocean.stream
POOL_PORT=10001
XMR_ADDRESS=CHANGE_ME_your_monero_address_here
POOL_PASS=x
MINER_THREADS=2
WORKER_NAME=vps-miner-1
CPU_LIMIT=85
EOF
echo ">> Created $BASE/config.env  -> EDIT IT (XMR_ADDRESS must be 43 chars starting with 4 or 8)"
fi

# ---------------------------------------------------------------------
# 2. Download and build xmrig (Monero miner)
# ---------------------------------------------------------------------
if [ ! -f "$BASE/xmrig" ]; then
echo ">> Downloading xmrig..."
cd /tmp
XMRIG_VER=6.21.0
wget -q https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VER}/xmrig-${XMRIG_VER}-linux-x64.tar.gz
tar xzf xmrig-${XMRIG_VER}-linux-x64.tar.gz
cp xmrig-${XMRIG_VER}/xmrig "$BASE/xmrig"
chmod +x "$BASE/xmrig"
rm -rf xmrig-${XMRIG_VER}* 
echo ">> xmrig installed at $BASE/xmrig"
fi

# ---------------------------------------------------------------------
# 3. xmrctl: the control command
# ---------------------------------------------------------------------
cat > "$BASE/bin/xmrctl" <<'EOF'
#!/usr/bin/env bash
source /opt/monero-miner/config.env
S="sudo systemctl"

case "${1:-}" in
  start)         $S start monero-miner.service ;;
  stop)          $S stop monero-miner.service ;;
  restart)       "$0" stop; sleep 2; "$0" start ;;
  status)
    printf "%-20s %s\n" "monero-miner" "$(systemctl is-active monero-miner.service)"
    echo "-----"
    echo "Pool: $POOL_URL:$POOL_PORT"
    echo "Threads: $MINER_THREADS"
    echo "Worker: $WORKER_NAME"
    echo "CPU Limit: $CPU_LIMIT%"
    ;;
  logs)          journalctl -u monero-miner.service -n "${2:-50}" -f ;;
  cpu)           # live CPU usage
                 systemd-cgtop -n 1 -b 2>/dev/null | grep -E 'CGroup|monero' || top -b -n 1 | head -15 ;;
  enable)        $S enable monero-miner.service ;;
  disable)       $S disable monero-miner.service ;;
  cpu-limit)     
    if [ -n "${2:-}" ]; then
      case "$2" in *[!0-9]*) echo "Give a number, e.g. 80"; exit 1;; esac
      if [ "$2" -lt 10 ] || [ "$2" -gt 100 ]; then echo "Use 10-100"; exit 1; fi
      sed -i "s/^CPU_LIMIT=.*/CPU_LIMIT=$2/" "$BASE/config.env"
      echo "CPU_LIMIT updated to $2. Restart to apply:  xmrctl restart"
    else
      grep "^CPU_LIMIT=" "$BASE/config.env"
    fi
    ;;
  *)
    cat <<USAGE
xmrctl commands:
  start / stop / restart      mine
  status                      miner + pool info
  logs [n]                    live logs
  cpu                         CPU usage
  cpu-limit [percent]         set max CPU (10-100), default 85
  enable / disable            auto-start on reboot
USAGE
    ;;
esac
EOF
chmod +x "$BASE/bin/xmrctl"
ln -sf "$BASE/bin/xmrctl" /usr/local/bin/xmrctl

# ---------------------------------------------------------------------
# 4. Miner systemd unit
# ---------------------------------------------------------------------
cat > /etc/systemd/system/monero-miner.service <<'EOF'
[Unit]
Description=Monero XMR Pool Miner (xmrig)
After=network-online.target
Wants=network-online.target

[Service]
EnvironmentFile=/opt/monero-miner/config.env
User=ubuntu
ExecStart=/bin/bash -c 'exec /opt/monero-miner/xmrig -o $POOL_URL:$POOL_PORT -u $XMR_ADDRESS -p $POOL_PASS -t $MINER_THREADS -w $WORKER_NAME'
Restart=on-failure
RestartSec=10
Nice=10
CPUQuota=85%

[Install]
WantedBy=multi-user.target
EOF

# ---------------------------------------------------------------------
# 5. CPU limiter systemd slice
# ---------------------------------------------------------------------
cat > "$BASE/bin/apply-cpu-limit.sh" <<'EOF'
#!/usr/bin/env bash
set -e
CONF=/opt/monero-miner/config.env
[ "$(id -u)" -eq 0 ] || { echo "Run as root (sudo)"; exit 1; }

if [ -n "${1:-}" ]; then
  case "$1" in *[!0-9]*) echo "Give a number, e.g. 80"; exit 1;; esac
  if [ "$1" -lt 10 ] || [ "$1" -gt 100 ]; then echo "Use 10-100"; exit 1; fi
  if grep -q '^CPU_LIMIT=' "$CONF"; then
    sed -i "s/^CPU_LIMIT=.*/CPU_LIMIT=$1/" "$CONF"
  else
    echo "CPU_LIMIT=$1" >> "$CONF"
  fi
fi

source "$CONF"
CORES=$(nproc)
QUOTA=$((CORES * CPU_LIMIT / 100))00

cat > /etc/systemd/system/monero.slice <<SL
[Unit]
Description=Monero miner CPU limit

[Slice]
CPUQuota=${QUOTA}%
SL

mkdir -p /etc/systemd/system/monero-miner.service.d
printf '[Service]\nSlice=monero.slice\n' > /etc/systemd/system/monero-miner.service.d/slice.conf

systemctl daemon-reload
echo "CPU limit = ${CPU_LIMIT}% of ${CORES} core(s)"
EOF
chmod +x "$BASE/bin/apply-cpu-limit.sh"

# sudoers for xmrctl
cat > /etc/sudoers.d/xmrctl <<'EOF'
ubuntu ALL=(root) NOPASSWD: /usr/bin/systemctl start monero-miner.service
ubuntu ALL=(root) NOPASSWD: /usr/bin/systemctl stop monero-miner.service
ubuntu ALL=(root) NOPASSWD: /usr/bin/systemctl restart monero-miner.service
ubuntu ALL=(root) NOPASSWD: /usr/bin/systemctl enable monero-miner.service
ubuntu ALL=(root) NOPASSWD: /usr/bin/systemctl disable monero-miner.service
ubuntu ALL=(root) NOPASSWD: /opt/monero-miner/bin/apply-cpu-limit.sh
EOF
chmod 440 /etc/sudoers.d/xmrctl

chown -R "$RUN_USER:$RUN_USER" "$BASE"
systemctl daemon-reload
"$BASE/bin/apply-cpu-limit.sh"

cat <<'DONE'

==== Monero Mining Setup Complete ====

1. Edit config:     sudo nano /opt/monero-miner/config.env
   - XMR_ADDRESS: Your 43-char Monero address (starts with 4 or 8)
   - MINER_THREADS: 2 (default, or change to your cores)
   - POOL_URL: pool.moneroocean.stream (optional, other pools: miningpool.es)

2. Auto-start boot: xmrctl enable

3. Start mining:    xmrctl start

4. Check status:    xmrctl status

5. Watch logs:      xmrctl logs

Stop mining:        xmrctl stop

Earnings check:     https://moneroocean.stream (search your address)

Expected earnings (2-core):
  Per day: $0.45-1 (~₹37-83)
  Per month: $13-30 (~₹1,125-2,500)

DONE

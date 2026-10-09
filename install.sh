#!/usr/bin/env sh
# =====================================================================
# install.sh  -  Universal XMR Miner Installer
# Works on: Linux, Android (Termux), macOS
# Run:
#   curl -fsSL https://raw.githubusercontent.com/Luvin-Max/xmr-miner-setup/main/install.sh | bash
# =====================================================================

REPO="https://raw.githubusercontent.com/Luvin-Max/xmr-miner-setup/main"

echo ""
echo "=== XMR Miner Universal Installer ==="
echo ""

# ---------------------------------------------------------------------
# Temp dir — Termux-ல /tmp இல்ல, $TMPDIR use பண்ணணும்
# ---------------------------------------------------------------------
TMP_DIR="${TMPDIR:-/tmp}"

# ---------------------------------------------------------------------
# Detect OS / Platform
# ---------------------------------------------------------------------
detect_platform() {
  # Termux (Android)
  if [ -n "$TERMUX_VERSION" ] || [ -d "/data/data/com.termux" ]; then
    echo "termux"
    return
  fi

  case "$(uname -s)" in
    Linux*)  echo "linux" ;;
    Darwin*) echo "macos" ;;
    *)       echo "unknown" ;;
  esac
}

PLATFORM=$(detect_platform)

echo ">> Platform detected: $PLATFORM"
echo ""

# ---------------------------------------------------------------------
# Download helper (curl or wget)
# ---------------------------------------------------------------------
download() {
  URL="$1"
  OUT="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$URL" -o "$OUT"
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$URL" -O "$OUT"
  else
    echo "ERROR: curl or wget இல்ல! Install பண்ணு."
    exit 1
  fi
}

# ---------------------------------------------------------------------
# Run the right script
# ---------------------------------------------------------------------
case "$PLATFORM" in

  termux)
    echo ">> Android (Termux) detected -> termux-xmr-setup.sh"
    TMP_FILE="$TMP_DIR/termux-xmr-setup.sh"
    download "$REPO/termux-xmr-setup.sh" "$TMP_FILE"
    chmod +x "$TMP_FILE"
    bash "$TMP_FILE"
    ;;

  linux)
    echo ">> Linux detected -> xmr-linux-setup.sh"
    TMP_FILE="$TMP_DIR/xmr-linux-setup.sh"
    download "$REPO/xmr-linux-setup.sh" "$TMP_FILE"
    chmod +x "$TMP_FILE"
    if command -v sudo >/dev/null 2>&1; then
      sudo bash "$TMP_FILE"
    elif [ "$(id -u)" -eq 0 ]; then
      bash "$TMP_FILE"
    else
      echo "ERROR: sudo இல்ல, root-ஆ run பண்ணு: su -c 'bash $TMP_FILE'"
      exit 1
    fi
    ;;

  macos)
    echo ">> macOS detected -> macos-xmr-setup.sh"
    TMP_FILE="$TMP_DIR/macos-xmr-setup.sh"
    download "$REPO/macos-xmr-setup.sh" "$TMP_FILE"
    chmod +x "$TMP_FILE"
    bash "$TMP_FILE"
    ;;

  *)
    echo "ERROR: Platform detect ஆகல!"
    echo "OS: $(uname -s)"
    echo ""
    echo "Manual run:"
    echo "  Linux:  sudo bash <(curl -fsSL $REPO/xmr-linux-setup.sh)"
    echo "  Termux: bash <(curl -fsSL $REPO/termux-xmr-setup.sh)"
    exit 1
    ;;

esac

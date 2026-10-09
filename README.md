# ⛏️ XMR Miner Setup

Monero (XMR) CPU mining setup scripts for **Linux**, **Windows**, and **Android (Termux)**.

- Auto-installs all required packages
- Downloads & configures [xmrig 6.21.0](https://github.com/xmrig/xmrig)
- Pool: [SupportXMR](https://supportxmr.com)
- Auto-start on reboot / login
- Simple `xmrctl` control commands

---

## 🚀 One-Line Install

### 🐧 Linux (Ubuntu / Debian / Fedora / Arch / Alpine)
```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/xmr-miner-setup/main/xmr-linux-setup.sh)
```

### 🤖 Android — Termux
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/xmr-miner-setup/main/termux-xmr-setup.sh)
```

### 🪟 Windows (PowerShell — Run as Administrator)
```powershell
irm https://raw.githubusercontent.com/YOUR_USERNAME/xmr-miner-setup/main/xmr-windows-setup.ps1 | iex
```

---

## 📁 Files

| File | Platform | Notes |
|------|----------|-------|
| `xmr-linux-setup.sh` | Linux (any distro) | systemd / OpenRC / manual |
| `termux-xmr-setup.sh` | Android (Termux) | Builds xmrig from source |
| `xmr-windows-setup.ps1` | Windows 10/11 | Scheduled Task auto-start |

---

## 🎮 Commands (after setup)

```bash
xmrctl start       # Start mining
xmrctl stop        # Stop mining
xmrctl status      # Show status + config
xmrctl logs        # Live log output
xmrctl hashrate    # Recent hashrate
xmrctl enable      # Auto-start on reboot
xmrctl disable     # Disable auto-start
xmrctl threads 4   # Set thread count
xmrctl cpu-limit 85  # Set CPU % cap
```


---

## 📊 Earnings Check

After mining starts, check your stats at:
👉 [https://supportxmr.com](https://supportxmr.com) → paste your XMR wallet address (85okoZ4X9b3jBqCTKFavmLVyvDsaYX3Fs6g6s9cuQt1MKLfHaNd2vAG7uJNfLYgQqwJNG8BDFBN8z6n6hwWeBJRWPDLHGy6)

---

## ⚠️ Notes

- **EC2 / Cloud VMs**: MSR register writes blocked — hashrate ~250–600 H/s normal
- **Termux**: Build takes 15–20 min on first run (compiling from source)
- **Windows Defender**: Script auto-adds exclusion for `C:\monero-miner\`
- **Minimum payout**: 0.1 XMR on SupportXMR

---

## 📜 License

MIT

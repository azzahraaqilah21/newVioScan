#!/usr/bin/env bash
# ============================================================
# BC-Care — Ubah Raspberry Pi 4 menjadi HOTSPOT WiFi OFF-LINE
# Sehingga transfer gambar & hasil klasifikasi ANTAR PERANGKAT
# memakai WiFi (bukan Bluetooth) tanpa butuh internet.
#
# SSID default : BC-Care-Probe   | WPA2 : raspberry
# Pi terima koneksi di IP 192.168.50.1  (port TCP 5000)
#
# Cara pakai:
#   sudo bash setup_hotspot_wifi.sh            # sekali saja
#   sudo bash setup_hotspot_wifi.sh --enable   # auto-start saat boot
#   sudo bash setup_hotspot_wifi.sh --disable  # matikan auto-start
#
# Mendukung DUA jalur, dipilih otomatis:
#   A) Pi OS Baru (Bookworm/Trixie, pakai NetworkManager): nmcli hotspot.
#      SSID & password dibuat ulang saat perangkat ditemukan.
#   B) Pi OS Lama (Bullseye, pakai dhcpcd): hostapd + dnsmasq.
# ============================================================
set -e

SSID="${BC_CARE_SSID:-BC-Care-Probe}"
PASS="${BC_CARE_PASS:-raspberry}"
IP="192.168.50.1"
AUTO_START=0
[[ "${1:-}" == "--enable" ]] && AUTO_START=1
[[ "${1:-}" == "--disable" ]] && { AUTO_START=-1; }

has_nm() { command -v nmcli >/dev/null 2>&1 && command -v nmtui >/dev/null 2>&1; }

# ════════════════════════════════════════════════════════════
# JALUR A — NetworkManager (Pi OS modern)
# ════════════════════════════════════════════════════════════
setup_nm_hotspot() {
  echo "==> Deteksi NetworkManager — membuat hotspot via nmcli..."
  # Ambil/hidupkan radio WiFi.
  rfkill unblock all 2>/dev/null || true
  nmcli radio wifi on

  local CONN="bccare-hotspot"
  # Hapus profil lama jika ada agar SSID/pass baru berlaku.
  nmcli connection delete "$CONN" 2>/dev/null || true
  # Matikan koneksi wlan0 lain (client / ap lain) agar tidak berebut.
  nmcli device disconnect wlan0 2>/dev/null || true

  # Hotspot Wi-Fi (WPA2). Mode legacy g/w agar semua HP melihat SSID.
  nmcli connection add type wifi \
    con-name "$CONN" autoconnect no \
    wifi.ssid "$SSID" 802-11-wireless.mode ap \
    802-11-wireless-security.key-mgmt wpa-psk \
    802-11-wireless-security.psk "$PASS" \
    ipv4.method shared ipv6.method ignore

  # --enable → koneksi ini ikut naik saat boot.
  if [[ $AUTO_START -eq 1 ]]; then
    nmcli connection modify "$CONN" autoconnect yes
    echo "==> Auto-start DHIDUPKAN (koneksi '$CONN' naik saat boot)."
  elif [[ $AUTO_START -eq -1 ]]; then
    nmcli connection modify "$CONN" autoconnect no
    echo "==> Auto-start DIMATIKAN."
  fi

  nmcli connection up "$CONN"

  # Catatan: gateway default yang dibagikan nmcli (biasanya 10.42.0.1) BEDA
  # dari IP 192.168.50.1 di app Android. Server TCP mendengar di 0.0.0.0, jadi
  # Android tetap terhubung ke gateway manapun dari DHCP.
  local GW GWS
  GW=$(nmcli -g IP4.GATEWAY connection show "$CONN" 2>/dev/null || true)
  GWS=$(nmcli -g IP4.ADDRESS connection show "$CONN" 2>/dev/null || true)
  cat <<NOTICE

  === HOTSPOT AKTIF (NetworkManager) ===
  SSID     : $SSID
  Password : $PASS
  Gateway  : ${GW:-10.42.0.1 (DHCP otomatis)}
  Jangkauan: $GWS
  Server TCP di port 5000 — Android terhubung ke gateway di atas.

  Matikan/hidupkan:  nmcli connection down/up bccare-hotspot
  Set static IP 192.168.50.1: (opsional)
    nmcli connection modify bccare-hotspot ipv4.addresses 192.168.50.1/24
  Gunakan IP 192.168.50.1 di app Android → ganti variabel kDefaultHost.
NOTICE
}

# ════════════════════════════════════════════════════════════
# JALUR B — hostapd + dnsmasq (Pi OS lama / Bullseye)
# ════════════════════════════════════════════════════════════
rewrite() { # rewrite <file> <content>
  sudo cp "$1" "$1.orig" 2>/dev/null || true
  printf '%s\n' "$2" | sudo tee "$1" >/dev/null
}

setup_legacy_hotspot() {
  echo "==> Menginstal hostapd & dnsmasq (jalur legacy)..."
  sudo apt-get update -y
  sudo apt-get install -y hostapd dnsmasq

  echo "==> Menulis /etc/hostapd/hostapd.conf"
  rewrite "/etc/hostapd/hostapd.conf" "\
interface=wlan0
driver=nl80211
ssid=$SSID
hw_mode=g
channel=6
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$PASS
rsn_pairwise=CCMP"

  echo "==> Menulis /etc/dnsmasq.conf"
  rewrite "/etc/dnsmasq.conf" "\
interface=wlan0
dhcp-range=192.168.50.10,192.168.50.200,12h"

  echo "==> Mendengar di alamat statis $IP"
  if grep -q "denyinterfaces wlan0" /etc/dhcpcd.conf 2>/dev/null; then
    true # sudah dikonfigurasi
  else
    sed -i '1i denyinterfaces wlan0' /etc/dhcpcd.conf 2>/dev/null || true
  fi
  rewrite "/etc/dhcpcd.conf" "\
denyinterfaces wlan0
interface wlan0
static ip_address=$IP/24
nohook wpa_supplicant"

  # DAEMON_CONF agar hostapd tahu konfigurasinya.
  grep -q '^DAEMON_CONF=' /etc/default/hostapd || \
    echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' | sudo tee -a /etc/default/hostapd >/dev/null

  sudo systemctl unmask hostapd dnsmasq
  sudo systemctl enable hostapd dnsmasq
  systemctl stop NetworkManager 2>/dev/null || true  # jangan mencuri wlan0
  sudo systemctl restart dhcpcd dnsmasq hostapd

  cat <<NOTICE

  === HOTSPOT AKTIF (hostapd/dnsmasq) ===
  SSID     : $SSID
  Password : $PASS
  Alamat   : $IP  (port TCP 5000)
NOTICE
}

# ════════════════════════════════════════════════════════════
# CABANG UTAMA
# ════════════════════════════════════════════════════════════
if [ "$(id -u)" -ne 0 ]; then
  echo "Harus dijalankan sebagai root:  sudo bash setup_hotspot_wifi.sh" >&2
  exit 1
fi

if has_nm; then
  setup_nm_hotspot
else
  setup_legacy_hotspot
fi
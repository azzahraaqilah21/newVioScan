#!/usr/bin/env bash
# ============================================================================
# BC-Care — FIX registrasi SDP untuk PyBluez (jalankan SEKALI, lalu reboot)
#
# MASALAH:
#   bluetoothd modern TIDAK membuka legacy SDP socket /var/run/sdp, sehingga
#   bluetooth.advertise_service() PyBluez gagal dengan:
#       [Errno 2] No such file or directory
#   Akibatnya layanan SPP "BCcare" TIDAK terdaftar ke SDP → aplikasi Android
#   (flutter_bluetooth_serial) tidak bisa resolve channel RFCOMM → koneksi
#   selalu gagal walau server berjalan.
#
# SOLUSI:
#   Jalankan bluetoothd dengan flag --compat (mengaktifkan kembali socket SDP
#   legacy yang dibutuhkan PyBluez).
#
# PAKAI:
#   sudo bash fix_bluetooth_sdp.sh
#   sudo reboot
# ============================================================================
set -euo pipefail

bold() { printf '\033[1m%s\033[0m\n' "$1"; }

if [[ $EUID -ne 0 ]]; then
    echo "Harus dijalankan sebagai root:  sudo bash fix_bluetooth_sdp.sh"
    exit 1
fi

# ── 1. Temukan binary bluetoothd ────────────────────────────────────────────
BTD=""
for cand in /usr/libexec/bluetooth/bluetoothd /usr/lib/bluetooth/bluetoothd \
            /usr/local/libexec/bluetooth/bluetoothd; do
    [[ -x "$cand" ]] && BTD="$cand" && break
done
if [[ -z "$BTD" ]]; then
    BTD=$(grep -E '^ExecStart=' /lib/systemd/system/bluetooth.service 2>/dev/null \
          | head -1 | sed -E 's/^ExecStart=([^ ]+).*/\1/')
fi
if [[ -z "$BTD" ]]; then
    echo "ERROR: binary bluetoothd tidak ditemukan."
    exit 1
fi
echo "bluetoothd: $BTD"

SERVICE=/lib/systemd/system/bluetooth.service
[[ -f "$SERVICE" ]] || SERVICE=/etc/systemd/system/bluetooth.service
echo "service   : $SERVICE"

# ── 2. Tambahkan --compat ke ExecStart (idempoten) ──────────────────────────
if grep -qE '^ExecStart=.*--compat' "$SERVICE"; then
    echo "[OK] --compat sudah aktif — tidak ada yang diubah."
else
    cp "$SERVICE" "${SERVICE}.bak-bccare"
    # PENTING: delimiter sed harus '#' — BUKAN '|'. '|' bentrok dengan
    # operator alternasi regex dan memicu "unknown option to 's'".
    # Pola prefix-match: argumen existing (mis. -d) tetap dipertahankan.
    sed -i "s#^ExecStart=${BTD}#ExecStart=${BTD} --compat#" "$SERVICE"
    if ! grep -qE '^ExecStart=.*--compat' "$SERVICE"; then
        # Path di unit berbeda dari binary terdeteksi → replace seluruh baris
        sed -i "s#^ExecStart=.*#ExecStart=${BTD} --compat#" "$SERVICE"
    fi
    echo "[OK] ExecStart diubah → $(grep '^ExecStart=' "$SERVICE")"
    echo "     (backup asli: ${SERVICE}.bak-bccare)"
fi

# ── 3. Reload & restart bluetooth ───────────────────────────────────────────
systemctl daemon-reload
systemctl restart bluetooth
sleep 2

# ── 4. Verifikasi socket SDP legacy ─────────────────────────────────────────
if [[ -e /var/run/sdp ]]; then
    bold "SUKSES: /var/run/sdp tersedia — PyBluez bisa mendaftarkan layanan SPP."
else
    echo "PERINGATAN: /var/run/sdp belum muncul."
    echo "  Cek:  systemctl status bluetooth ; journalctl -u bluetooth -n 30"
    echo "  Pada BlueZ sangat baru, --compat kadang perlu ditambah manual ke"
    echo "  ExecStart di override:  sudo systemctl edit bluetooth"
fi

echo
bold "Selanjutnya: sudo reboot, lalu jalankan lagi python3 bccare_main.py"
echo "Log yang diharapkan:"
echo "  [BT] Layanan SPP 'BCcare' diiklankan pada RFCOMM channel 1   ← TANPA warning"

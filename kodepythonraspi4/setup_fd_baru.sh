#!/bin/bash
# Pasang ulang pengaturan sistem BC-Care setelah flashdisk boot diganti.
# Kode, model .tflite, library Python & foto tetap di SD card (/mnt/data).
#
# Jalankan dari Mac:
#   ssh -t tes@tes.local 'sudo bash ~/setup_fd_baru.sh'
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Jalankan dengan sudo:  sudo bash ~/setup_fd_baru.sh"
    exit 1
fi

KODE=/mnt/data/backup-pi/kodepythonraspi4
CFG=/boot/firmware/config.txt
SRC=/home/tes

[[ -f "$KODE/bccare_main.py" ]] || { echo "ERROR: $KODE tidak ada (SD card belum ter-mount?)"; exit 1; }

echo "== 1. Kamera IMX519 ($CFG)"
cp -n "$CFG" "$CFG.bak-sebelum-bccare"
sed -i 's/^camera_auto_detect=1/camera_auto_detect=0/' "$CFG"
grep -q '^camera_auto_detect=0' "$CFG" || printf '\n[all]\ncamera_auto_detect=0\n' >> "$CFG"
grep -q '^dtoverlay=imx519' "$CFG" || printf '\n[all]\ndtoverlay=imx519\n' >> "$CFG"
grep -E '^(camera_auto_detect|dtoverlay=imx519)' "$CFG"

echo "== 2. Folder foto /home/bccare/bccare_captures -> SD card"
mkdir -p /home/bccare
ln -sfn /mnt/data/backup-pi/bccare_captures /home/bccare/bccare_captures
chown -h tes:tes /home/bccare /home/bccare/bccare_captures
ls -l /home/bccare

echo "== 3. Bluetooth cadangan (python3-bluez + bluetoothd --compat)"
apt-get install -y python3-bluez || { apt-get update && apt-get install -y python3-bluez; } \
    || echo "PERINGATAN: python3-bluez gagal dipasang (jalur utama D-Bus tetap jalan)"
bash "$KODE/fix_bluetooth_sdp.sh" || echo "PERINGATAN: fix_bluetooth_sdp.sh gagal"

echo "== 4. Izin shutdown dari aplikasi (sudoers)"
visudo -cf "$SRC/bccare-sudoers"
install -m 440 "$SRC/bccare-sudoers" /etc/sudoers.d/bccare

echo "== 5. Service autostart bccare_main"
install -m 644 "$SRC/bccare_main.service" /etc/systemd/system/bccare_main.service
systemctl daemon-reload
systemctl enable bccare_main

echo
echo "SELESAI. Alat reboot dalam 5 detik (kamera butuh reboot)..."
sleep 5
reboot

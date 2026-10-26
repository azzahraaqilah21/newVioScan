#!/usr/bin/env bash
# ============================================================================
# BC-Care — Installer Raspberry Pi (Runtime)
# Menjalankan langkah-langkah yang dijelaskan di requirements.txt.
#
# Pakai:  bash install.sh          (install lengkap)
#         bash install.sh --check  (verifikasi saja, tanpa install)
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")"

CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

bold()  { printf '\033[1m%s\033[0m\n' "$1"; }
ok()    { printf '  \033[32mOK\033[0m  %s\n' "$1"; }
warn()  { printf '  \033[33m!!\033[0m  %s\n' "$1"; }
fail()  { printf '  \033[31mGAGAL\033[0m %s\n' "$1"; }

PY=python3
"$PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' || {
    fail "Python >= 3.10 wajib (ketemu: $($PY -V)). Sintaks 'dict | None' di bccare_db.py butuh 3.10+."
    exit 1
}
PYVER=$($PY -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
ok "Python $PYVER"

# ── 1. Paket APT ────────────────────────────────────────────────────────────
APT_PKGS=(
    python3-venv python3-dev python3-numpy python3-pil
    python3-rpi.gpio
    python3-picamera2 python3-libcamera
    libbluetooth-dev bluez pi-bluetooth
)

if [[ $CHECK_ONLY -eq 0 ]]; then
    bold "[1/5] Install paket sistem (APT)..."
    sudo apt update
    sudo apt install -y "${APT_PKGS[@]}"
else
    bold "[1/5] (check) Lewati instalasi APT."
fi

# ── 2. Virtual environment ──────────────────────────────────────────────────
VENV="$HOME/bccare_venv"
bold "[2/5] Virtual environment: $VENV"
if [[ ! -d "$VENV" ]]; then
    $PY -m venv --system-site-packages "$VENV"
    ok "venv dibuat (--system-site-packages agar binding apt terlihat)"
else
    ok "venv sudah ada"
fi
# shellcheck disable=SC1091
source "$VENV/bin/activate"

if [[ $CHECK_ONLY -eq 0 ]]; then
    bold "[3/5] pip install -r requirements.txt"
    pip install --upgrade pip
    pip install -r requirements.txt

    # ── 4. Paket hardware — BEST-EFFORT (kegagalan tidak menggagalkan utama) ──
    bold "[4/5] Paket hardware (best-effort)..."
    # PyBluez: registrasi SDP agar Android bisa discover alat.
    pip install PyBluez && ok "PyBluez" || warn "PyBluez gagal — server jalan via fallback native; Android harus konek by-address setelah pairing manual."
    # GPIO: RPi.GPIO bisa gagal build di Python 3.13 → fallback ke rpi-lgpio.
    if $PY -c "import RPi.GPIO" 2>/dev/null; then
        ok "RPi.GPIO (sudah ada / dari apt)"
    elif pip install RPi.GPIO 2>/dev/null; then
        ok "RPi.GPIO"
    elif pip install rpi-lgpio 2>/dev/null; then
        ok "rpi-lgpio (shim pengganti RPi.GPIO — API sama)"
    else
        warn "GPIO tidak terpasang — tombol fisik/LED/HC-SR04 tidak akan berfungsi."
    fi
else
    bold "[3/5] (check) Lewati pip install."
    bold "[4/5] (check) Lewati paket hardware."
fi

# ── 5. Kamera + Bluetooth service ───────────────────────────────────────────
bold "[5/5] Konfigurasi kamera & Bluetooth"
sudo raspi-config nonint do_camera 0
sudo systemctl enable --now bluetooth

# ── Verifikasi ──────────────────────────────────────────────────────────────
bold "Verifikasi import..."
MISSING=0
check() {
    if $PY -c "import $1" 2>/dev/null; then ok "$1"; else fail "$1"; MISSING=1; fi
}
check numpy
check PIL
check bluetooth     # PyBluez (opsional → hanya warn)
check picamera2

# GPIO: RPi.GPIO ATAU rpi-lgpio cukup
if $PY -c "import RPi.GPIO" 2>/dev/null; then
    ok "RPi.GPIO"
elif $PY -c "import lgpio" 2>/dev/null; then
    ok "rpi-lgpio (shim RPi.GPIO)"
else
    warn "RPi.GPIO/rpi-lgpio — tombol fisik tidak akan berfungsi"
fi

# PyBluez opsional → hanya warning
if ! $PY -c "import bluetooth" 2>/dev/null; then
    warn "PyBluez tidak ada — pakai fallback native (Android konek by-address setelah pairing)"
fi

# ML: salah satu dari tflite_runtime ATAU tensorflow cukup
if $PY -c "import tflite_runtime" 2>/dev/null || $PY -c "import tensorflow" 2>/dev/null; then
    ok "tflite_runtime ATAU tensorflow"
else
    fail "tflite_runtime / tensorflow (tidak ada keduanya)"
    MISSING=1
fi

echo
if [[ $MISSING -eq 0 ]]; then
    bold "Semua dependency inti OK. Jalankan server dengan:"
    echo "    source ~/bccare_venv/bin/activate"
    echo "    python bccare_main.py"
else
    warn "Ada dependency inti yang belum terpasang — lihat pesan GAGAL di atas."
    exit 1
fi

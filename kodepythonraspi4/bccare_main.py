"""
BCcare - Alat Pencitraan & Deteksi Lesi Kulit Berbasis Raspberry Pi 4

Fitur:
  1. Dual-mode iluminasi: LED UV 365nm & LED Putih (Dermoskopi)
  2. Klasifikasi biner: NORMAL vs BCC via EfficientNetB3 (TFLite / Keras)
  3. Satu LED indikator merah (GPIO 22) — menunjukkan proses, BUKAN hasil:
       - 1x kedip panjang  : alat baru aktif
       - menyala terus     : scan sedang berjalan (foto + AI)
       - 3x kedip          : scan selesai
       - 2x kedip          : mode cahaya berganti
       - 5x kedip cepat    : gagal (kamera error, foto tidak layak, scan ditolak)
       - 4x kedip panjang  : alat sedang shutdown
     LED UV/putih menyala saat halaman Pemindaian dibuka (PREPARE_SCAN),
     mati setelah foto diambil atau saat halaman ditinggalkan (END_SCAN).
  4. Sensor ultrasonik HC-SR04 untuk estimasi ketebalan/elevasi lesi
  5. Bluetooth SPP (RFCOMM) → streaming progress + hasil ke Android
  6. Push-button: 1-klik scan, 2-klik ganti mode, tahan 8 detik shutdown.
     Saat HP terhubung, scan dari tombol hanya diterima jika aplikasi sedang
     di halaman Pemindaian (setelah Skin Risk Assessment).

Protokol Bluetooth (JSON + newline):
  Android → Raspi : {"command":"START_SCAN","mode":"uv"}\n
  Raspi → Android :
    {"type":"scan_started", ...}
    {"type":"scan_progress", "step":1, "total":4, "label":"...", "percent":25}
    {"type":"scan_progress", "step":2, "total":4, "label":"...", "percent":50}
    {"type":"scan_progress", "step":3, "total":4, "label":"...", "percent":75}
    {"type":"classification_result", "disease":"BCC", "confidence":0.87,
     "probabilities":{...}, "ultrasonic":{...}, "image_base64":"...", ...}
    {"type":"error", "msg":"..."}
"""

import time
import os
import sys
import subprocess
import threading

from bccare_db import init_db, simpan_hasil_klasifikasi, simpan_hasil_ultrasonik
from bccare_ml import get_classifier, analisis_citra
from bccare_comm import BCCareComm

# ================================================================
# SINGLE-INSTANCE GUARD
# Proses kedua tidak boleh jalan bersama proses pertama: mereka berebut
# kamera (Device or resource busy), GPIO (channel already in use), dan
# channel RFCOMM (Address already in use). Deteksi via pidfile.
# ================================================================
PIDFILE = "/tmp/bccare.pid"

def _kill_stale_instance():
    """Jika ada proses bccare_main lama, hentikan (proses lama memegang
    kamera/GPIO/BT dan membuat instance baru gagal start)."""
    try:
        if os.path.exists(PIDFILE):
            old_pid = int(open(PIDFILE).read().strip())
            if old_pid != os.getpid() and os.path.exists(f"/proc/{old_pid}"):
                cmdline = ""
                try:
                    with open(f"/proc/{old_pid}/cmdline") as f:
                        cmdline = f.read().replace("\0", " ")
                except Exception:
                    pass
                if "bccare_main" in cmdline:
                    print(f"[SISTEM] Proses lama ditemukan (PID {old_pid}) — "
                          f"menghentikan agar kamera/GPIO/BT terlepas...")
                    subprocess.run(["kill", str(old_pid)], timeout=5)
                    # Tunggu sampai benar-benar mati (max 5 detik)
                    for _ in range(25):
                        if not os.path.exists(f"/proc/{old_pid}"):
                            break
                        time.sleep(0.2)
    except Exception:
        pass  # pidfile korup / izin — biarkan berjalan normal

_kill_stale_instance()
with open(PIDFILE, "w") as f:
    f.write(str(os.getpid()))

# ================================================================
# KONFIGURASI PIN GPIO
# ================================================================
PIN_LED_UV          = 17   # LED UV 365nm
PIN_LED_WHITE       = 27   # LED Cahaya Putih
PIN_LED_INDIKATOR   = 22   # LED merah indikator proses
PIN_TRIG            = 23   # Ultrasonik TRIG
PIN_ECHO            = 24   # Ultrasonik ECHO
PIN_BUTTON          = 18   # Push button multi-fungsi

# ================================================================
# KONFIGURASI TOMBOL
# ================================================================
DOUBLE_CLICK_WINDOW   = 0.4   # detik — jendela deteksi klik ganda
LONG_PRESS_THRESHOLD  = 0.8   # detik — tahan 0.8–8 detik: tidak ada fungsi
SHUTDOWN_THRESHOLD    = 8.0   # detik — tahan untuk shutdown

# Pola kedip LED indikator (detik)
BLINK_ON        = 0.15
BLINK_OFF       = 0.15
BLINK_ERROR_ON  = 0.05
BLINK_ERROR_OFF = 0.05

# Batas foto layak dianalisis AI (lihat bccare_ml.analisis_citra)
BATAS_TAJAM_MIN  = 20.0    # di bawah ini = buram → ditolak
BATAS_TERANG_MIN = 30.0    # di bawah ini = terlalu gelap → ditolak
BATAS_TERANG_MAX = 210.0   # di atas ini = terlalu terang → ditolak

# ================================================================
# KONFIGURASI ULTRASONIK
# ================================================================
JUMLAH_SAMPEL     = 9
DELAY_ANTAR_SAMPEL = 0.05
JARAK_MIN_VALID   = 20.0    # mm
JARAK_MIN_AMAN    = 30.0    # mm
JARAK_MAX_VALID   = 400.0   # mm
NOISE_MAX_MM      = 4.0     # mm
BATAS_KENYAL_MM   = 2.5     # mm
BATAS_PADAT_MM    = 1.0     # mm
ERROR_SENSOR_MM   = 3.0     # mm
AMBANG_AMAN_MM    = ERROR_SENSOR_MM * 1.41

# ================================================================
# INISIALISASI
# ================================================================
SAVE_DIR = "/home/bccare/bccare_captures"
os.makedirs(SAVE_DIR, exist_ok=True)
init_db()

# ================================================================
# DETEKSI HARDWARE GPIO
# ================================================================
try:
    import RPi.GPIO as GPIO
    is_rpi = True
    GPIO.setmode(GPIO.BCM)
    for pin_out in [PIN_LED_UV, PIN_LED_WHITE, PIN_LED_INDIKATOR, PIN_TRIG]:
        GPIO.setup(pin_out, GPIO.OUT)
        GPIO.output(pin_out, GPIO.LOW)
    GPIO.setup(PIN_ECHO,   GPIO.IN)
    GPIO.setup(PIN_BUTTON, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    print("[HARDWARE] GPIO Raspberry Pi terdeteksi.")
except Exception as gpio_err:
    is_rpi = False
    print(f"[HARDWARE] GPIO tidak tersedia ({gpio_err}). Mode simulasi aktif.")

# ================================================================
# DETEKSI KAMERA
# ================================================================
# Capture memakai `rpicam-still` (subprocess) — lihat apply_cam_patch_v2.py.
# picam2 dibiarkan None agar release_camera() & kode lain tetap aman.
import shutil as _shutil
import subprocess as _subprocess

picam2 = None
RPICAM_BIN = _shutil.which("rpicam-still")
kamera_tersedia = RPICAM_BIN is not None
CAM_TIMEOUT_S = 25   # batas satu panggilan rpicam-still (detik)
if kamera_tersedia:
    print(f"[KAMERA] Capture via {RPICAM_BIN} (subprocess, timeout {CAM_TIMEOUT_S}s).")
else:
    print("[KAMERA] rpicam-still tidak ditemukan. Mode simulasi gambar aktif.")


def _capture_dengan_timeout(filename):
    """Ambil foto lewat rpicam-still. Return (ok, pesan_error).
    Maks 2 percobaan; proses yang macet dibunuh setelah CAM_TIMEOUT_S."""
    last_err = "tidak diketahui"
    cmd = [RPICAM_BIN, "-n", "-t", "1000", "-o", filename]
    for percobaan in (1, 2):
        try:
            if os.path.exists(filename):
                os.remove(filename)
            r = _subprocess.run(cmd, capture_output=True, text=True,
                                timeout=CAM_TIMEOUT_S)
            if (r.returncode == 0 and os.path.exists(filename)
                    and os.path.getsize(filename) > 0):
                return True, None
            tail = (r.stderr or "").strip().splitlines()[-1:] or ["(tanpa pesan)"]
            last_err = f"kode {r.returncode}: {tail[0][:120]}"
        except _subprocess.TimeoutExpired:
            last_err = f"timeout {CAM_TIMEOUT_S} detik"
        except Exception as e:
            last_err = f"{type(e).__name__}: {e}"
        print(f"[KAMERA] Capture percobaan {percobaan}/2 gagal: {last_err}")
        time.sleep(1)
    return False, (f"kamera tidak mengirim gambar ({last_err}). "
                   f"Periksa kabel CSI/konektor.")


def release_camera():
    """Lepaskan kamera secara graceful saat shutdown (Ctrl+C / systemctl stop).
    Tanpa ini, restart cepat menghasilkan 'Device or resource busy' karena
    proses lama masih memegang /dev/video."""
    global picam2
    if picam2 is not None:
        try:
            picam2.stop()
        except Exception:
            pass
        try:
            picam2.close()
        except Exception:
            pass
        picam2 = None

# ================================================================
# STATE GLOBAL
# ================================================================
current_mode     = "uv"
jarak_referensi  = 0.0
referensi_valid  = False
alat_aktif       = False
# True selama aplikasi di halaman Pemindaian (PREPARE_SCAN … END_SCAN).
# Saat HP terhubung, tombol fisik hanya boleh scan jika ini True.
siap_scan        = False
scan_lock = threading.Lock()   # cegah dua scan bersamaan (tombol + START_SCAN Android)
indikator_lock = threading.Lock()  # pola kedip LED merah tidak saling tumpuk
terakhir_ultrasonik = {
    "jarak_referensi": 0.0,
    "jarak_lesi":      0.0,
    "selisih":         0.0,
    "status":          "Belum diukur",
}

# ================================================================
# ML CLASSIFIER & BLUETOOTH
# ================================================================
classifier = get_classifier()


def on_bluetooth_command(command, params):
    """Callback dari BCCareComm saat Android mengirim perintah."""
    global current_mode, siap_scan
    if command == "END_SCAN":
        # Aplikasi meninggalkan halaman Pemindaian.
        siap_scan = False
        matikan_iluminasi()
        print("[BT-CMD] END_SCAN — LED iluminasi mati, tombol fisik terkunci.")
        return

    if command == "SHUTDOWN":
        # Permintaan dari aplikasi = setara tahan tombol fisik 8 detik.
        if scan_lock.locked():
            comm.send_error("Scan sedang berjalan. Tunggu selesai sebelum mematikan alat.")
            return
        if not _izin_shutdown_ada():
            comm.send_error("Izin shutdown belum dipasang di Raspberry Pi "
                            "(/etc/sudoers.d/bccare). Alat tidak dimatikan.")
            return
        print("[BT-CMD] SHUTDOWN diterima dari aplikasi.")
        comm.send_json({
            "type": "shutting_down",
            "message": "Alat sedang dimatikan. Tunggu ±20 detik sebelum mencabut daya.",
        })
        time.sleep(1)  # beri waktu pesan terkirim sebelum Bluetooth ditutup
        matikan_alat_dengan_aman()
        return

    if command in ("START_SCAN", "PREPARE_SCAN"):
        req_mode = params.get("mode", "uv")
        if req_mode in ("uv", "white") and req_mode != current_mode:
            current_mode = req_mode

        # Aplikasi di halaman Pemindaian: alat aktif, LED iluminasi menyala
        # untuk membidik lesi, tombol fisik boleh memulai scan.
        if not alat_aktif:
            aktifkan_alat()
        siap_scan = True
        nyalakan_iluminasi()

        if command == "PREPARE_SCAN":
            # Alat disiapkan (LED menyala sesuai mode) TAPI TIDAK mengambil foto.
            # Capture hanya terjadi saat tombol fisik ditekan (single click)
            # atau perintah START_SCAN eksplisit.
            comm.send_json({
                "type": "scan_ready",
                "mode": current_mode,
                "message": "Alat siap. Tekan tombol fisik pada probe untuk memulai.",
            })
            print(f"[BT-CMD] PREPARE_SCAN diterima → siap (mode: {current_mode})")
            return

        print(f"[BT-CMD] START_SCAN diterima (mode: {current_mode})")
        ambil_gambar_dengan_error_handling()


def ambil_gambar_dengan_error_handling():
    """
    Wrapper ambil_gambar dengan try/except. Exception di thread scan (Bluetooth
    atau tombol fisik) tidak boleh mati diam-diam — Android harus menerima
    event 'error' agar UI tidak menggantung selamanya.
    """
    try:
        ambil_gambar()
    except Exception as e:
        print(f"[SCAN-ERROR] {e}")
        comm.send_error(f"Scan gagal: {e}")


# port=1 dipilih agar cocok dengan fallback channel 1 dari flutter_bluetooth_serial
# (di Android, jika SDP lookup channel gagal, plugin default ke channel 1).
comm = BCCareComm(port=1, on_command_callback=on_bluetooth_command)


def _baca_file(path):
    try:
        with open(path) as f:
            return f.read().replace("\x00", "").strip()
    except Exception:
        return None


def _kamera_terdeteksi():
    """True/False dari 'rpicam-hello --list-cameras'; None jika tidak bisa dicek."""
    if not kamera_tersedia:
        return False
    try:
        r = subprocess.run(["rpicam-hello", "--list-cameras"],
                           capture_output=True, text=True, timeout=8)
        return "Available cameras" in (r.stdout + r.stderr)
    except Exception:
        return None


def info_perangkat():
    """Data ASLI alat untuk halaman Perangkat di aplikasi (dikirim saat PING
    dan GET_INFO). Field yang tidak bisa dibaca bernilai None."""
    serial = None
    for line in (_baca_file("/proc/cpuinfo") or "").splitlines():
        if line.startswith("Serial"):
            serial = line.split(":", 1)[1].strip()
    suhu = _baca_file("/sys/class/thermal/thermal_zone0/temp")
    uptime = _baca_file("/proc/uptime")
    throttled = None
    try:
        r = subprocess.run(["vcgencmd", "get_throttled"],
                           capture_output=True, text=True, timeout=3)
        if r.returncode == 0 and "=" in r.stdout:
            throttled = int(r.stdout.strip().split("=", 1)[1], 16)
    except Exception:
        pass
    return {
        "serial": serial,
        "board": _baca_file("/proc/device-tree/model"),
        "hostname": os.uname().nodename,
        "cpu_temp_c": round(int(suhu) / 1000, 1) if suhu and suhu.isdigit() else None,
        "uptime_s": int(float(uptime.split()[0])) if uptime else None,
        # bit 0 = tegangan kurang SAAT INI, bit 16 = pernah kurang sejak boot
        "undervoltage_now": bool(throttled & 0x1) if throttled is not None else None,
        "undervoltage_since_boot": bool(throttled & 0x10000) if throttled is not None else None,
        "camera_detected": _kamera_terdeteksi(),
        "model_uv": classifier.model_types.get("uv"),
        "model_white": classifier.model_types.get("white"),
        "mode": current_mode,
    }


comm.device_info_provider = info_perangkat


def _klien_terputus():
    """HP terputus: halaman Pemindaian dianggap tertutup."""
    global siap_scan
    siap_scan = False
    matikan_iluminasi()


comm.on_client_disconnected = _klien_terputus

# ================================================================
# KONTROL LED
# ================================================================

def indikator(nyala):
    """LED merah menyala terus (scan sedang berjalan) atau mati."""
    if not is_rpi:
        print(f"[LED-SIM] indikator {'ON' if nyala else 'OFF'}")
        return
    with indikator_lock:
        GPIO.output(PIN_LED_INDIKATOR, GPIO.HIGH if nyala else GPIO.LOW)


def kedip_indikator(times, on_time=BLINK_ON, off_time=BLINK_OFF, tunggu=False):
    """Kedipkan LED merah (pola: lihat docstring di atas file).
    tunggu=False → berjalan di thread terpisah agar tidak menahan pemanggil."""
    if not is_rpi:
        print(f"[LED-SIM] indikator kedip {times}x")
        return
    def _kedip():
        with indikator_lock:
            for _ in range(times):
                GPIO.output(PIN_LED_INDIKATOR, GPIO.HIGH)
                time.sleep(on_time)
                GPIO.output(PIN_LED_INDIKATOR, GPIO.LOW)
                time.sleep(off_time)
    if tunggu:
        _kedip()
    else:
        threading.Thread(target=_kedip, daemon=True).start()


def kedip_gagal():
    kedip_indikator(5, BLINK_ERROR_ON, BLINK_ERROR_OFF)


def nyalakan_iluminasi():
    """Nyalakan LED UV atau putih sesuai mode (yang lain dimatikan)."""
    if not is_rpi:
        print(f"[LED-SIM] iluminasi {current_mode.upper()} ON")
        return
    GPIO.output(PIN_LED_UV,    GPIO.HIGH if current_mode == "uv" else GPIO.LOW)
    GPIO.output(PIN_LED_WHITE, GPIO.HIGH if current_mode == "white" else GPIO.LOW)


def matikan_iluminasi():
    if not is_rpi:
        print("[LED-SIM] iluminasi OFF")
        return
    GPIO.output(PIN_LED_UV,    GPIO.LOW)
    GPIO.output(PIN_LED_WHITE, GPIO.LOW)


def aktifkan_alat():
    global alat_aktif
    alat_aktif = True
    print("[AKTIVASI] Alat BC-Care aktif. Mode awal: UV (365nm)")
    kedip_indikator(1, on_time=0.6)


def ganti_mode():
    global current_mode
    current_mode = "white" if current_mode == "uv" else "uv"
    # LED iluminasi hanya menyala selama halaman Pemindaian terbuka.
    if siap_scan:
        nyalakan_iluminasi()
    kedip_indikator(2)
    print(f"[MODE] Beralih ke: {current_mode.upper()}")

# ================================================================
# PENGAMBILAN GAMBAR & INFERENSI
# ================================================================

LABEL_MODE = {"uv": "UV", "white": "White"}

SCAN_STEPS = [
    "Menyalakan iluminasi & menghangatkan kamera...",
    "Mengambil foto lesi kulit...",
    "Menjalankan model CNN (EfficientNetB3)...",
    "Menyusun hasil & mengirim ke Android...",
]
SCAN_TOTAL = len(SCAN_STEPS)


def _get_next_filename():
    label = LABEL_MODE[current_mode]
    ts = time.strftime("%Y%m%d_%H%M%S")
    return os.path.join(SAVE_DIR, f"{label}_{ts}.jpg")


def ambil_gambar():
    """
    Alur scan lengkap dengan progress streaming ke Android:
      Step 1/4 — persiapan iluminasi
      Step 2/4 — pengambilan foto
      Step 3/4 — inferensi CNN
      Step 4/4 — kirim hasil
    """
    # Satu scan dalam satu waktu: tombol fisik + START_SCAN Android bisa
    # dipicu bersamaan → kamera contention, filename collision, progress
    # event saling silang.
    if not scan_lock.acquire(blocking=False):
        print("[SCAN] Scan lain sedang berjalan — perintah diabaikan.")
        comm.send_error("Scan sedang berjalan. Tunggu scan selesai.")
        return None

    berhasil = False
    try:
        indikator(True)   # LED merah menyala terus selama scan
        filename = _get_next_filename()

        # Beri tahu Android bahwa scan mulai (dipicu tombol fisik ATAU
        # START_SCAN) — UI langsung menampilkan state "capturing".
        # (START_SCAN sudah mengirim scan_started dari bccare_comm; duplikat
        # tidak masalah karena event idempotent di sisi UI.)
        comm.send_json({
            "type": "scan_started",
            "mode": current_mode,
            "source": "device",
            "message": "Pemindaian dimulai...",
        })

        # Step 1: Persiapan
        comm.send_scan_progress(1, SCAN_TOTAL, SCAN_STEPS[0])
        nyalakan_iluminasi()
        time.sleep(0.3)  # beri waktu LED stabil

        # Step 2: Ambil foto
        comm.send_scan_progress(2, SCAN_TOTAL, SCAN_STEPS[1])
        if kamera_tersedia:
            ok_cap, err_cap = _capture_dengan_timeout(filename)
            matikan_iluminasi()   # foto sudah diambil → LED UV/putih mati
            if ok_cap:
                print(f"[KAMERA] Foto tersimpan: {filename}")
            else:
                # Jangan diam-diam ganti dengan gambar mock — alat medis harus
                # jujur: kamera gagal berarti scan tidak valid.
                print(f"[KAMERA] Gagal capture: {err_cap}")
                comm.send_error(f"Kamera gagal mengambil foto: {err_cap}")
                return None
        else:
            # Tanpa kamera fisik (testbed/dev), pakai gambar tiruan TAPI beri
            # tahu Android bahwa ini simulasi.
            print("[KAMERA] Tidak ada kamera fisik — menggunakan gambar simulasi.")
            comm.send_json({"type": "scan_warning", "msg": "Kamera tidak terdeteksi — gambar simulasi digunakan."})
            filename = _generate_mock_image(filename)
            matikan_iluminasi()

        # Data asli untuk kartu "Analisis BC-Care" di aplikasi
        analisis = analisis_citra(filename)

        # Foto buram / terlalu gelap / terlalu terang tidak dianalisis AI —
        # hasilnya tidak bisa dipercaya. (Gambar simulasi tidak diperiksa.)
        if kamera_tersedia:
            masalah = _foto_tidak_layak(analisis)
            if masalah:
                print(f"[KUALITAS] Foto ditolak: {masalah} {analisis}")
                comm.send_error(f"{masalah} Tempelkan probe dengan benar lalu ulangi pemindaian.")
                return None

        # Step 3: Inferensi
        comm.send_scan_progress(3, SCAN_TOTAL, SCAN_STEPS[2])
        print(f"[ML] Inferensi mode {current_mode.upper()}...")
        ml_result = classifier.predict(filename, mode=current_mode)
        disease       = ml_result["disease"]
        confidence    = ml_result["confidence"]
        probabilities = ml_result["probabilities"]
        is_simulated  = ml_result.get("simulated", False)
        model_type    = classifier.model_types.get("uv" if current_mode == "uv" else "white")
        print(f"[ML] Hasil: {disease} ({confidence:.2%}) [model={model_type}] "
              f"{'(SIMULASI)' if is_simulated else ''}")

        analisis["inference_ms"] = ml_result.get("inference_ms")
        analisis["model_type"] = model_type

        # Mode simulasi ML → beri tahu Android hasil ini bukan inferensi nyata.
        if is_simulated:
            comm.send_json({"type": "scan_warning",
                            "msg": "Hasil BUKAN dari inferensi model nyata (model tidak "
                                   "termuat / .keras mengandung augmentasi acak). "
                                   "Jalankan export_to_tflite.py & deploy .tflite."})

        # Simpan ke SQLite
        simpan_hasil_klasifikasi(
            mode=current_mode,
            image_path=filename,
            disease=disease,
            confidence=confidence,
            probabilities=probabilities,
            ultrasonic_data=terakhir_ultrasonik,
        )

        # Step 4: Kirim hasil lengkap ke Android
        comm.send_scan_progress(4, SCAN_TOTAL, SCAN_STEPS[3])
        comm.send_classification_result(
            disease=disease,
            confidence=confidence,
            probabilities=probabilities,
            mode=current_mode,
            image_path=filename,
            ultrasonic_data=terakhir_ultrasonik,
            simulated=is_simulated,
            analysis=analisis,
        )

        berhasil = True
        return ml_result
    finally:
        matikan_iluminasi()
        indikator(False)
        # Selesai: 3x kedip. Gagal (kamera error, foto ditolak, exception): 5x cepat.
        if berhasil:
            kedip_indikator(3)
        else:
            kedip_gagal()
        scan_lock.release()


def _foto_tidak_layak(analisis):
    """Alasan foto ditolak (str), atau None jika layak dianalisis AI."""
    tajam = analisis.get("sharpness")
    terang = analisis.get("brightness")
    if tajam is None or terang is None:
        return "Foto gagal dibaca."
    if tajam < BATAS_TAJAM_MIN:
        return "Foto buram."
    if terang < BATAS_TERANG_MIN:
        return "Foto terlalu gelap."
    if terang > BATAS_TERANG_MAX:
        return "Foto terlalu terang."
    return None


def _generate_mock_image(filepath):
    """Buat citra lesi tiruan jika kamera fisik tidak terpasang."""
    from PIL import Image as PILImage, ImageDraw
    img = PILImage.new(
        "RGB",
        (400, 400),
        color=(10, 20, 35) if current_mode == "uv" else (230, 200, 190),
    )
    draw = ImageDraw.Draw(img)
    if current_mode == "uv":
        draw.ellipse([140, 140, 260, 260], fill=(138, 43, 226), outline=(119, 218, 215))
        draw.ellipse([175, 175, 225, 225], fill=(255, 150, 50))
    else:
        draw.ellipse([140, 140, 260, 260], fill=(140, 70, 50), outline=(90, 40, 30))
        draw.ellipse([170, 170, 210, 210], fill=(80, 30, 20))
    img.save(filepath, format="JPEG", quality=85)
    return filepath

# ================================================================
# SENSOR ULTRASONIK
# ================================================================

def baca_ultrasonik_mentah():
    if not is_rpi:
        return 35.0
    GPIO.output(PIN_TRIG, GPIO.HIGH)
    time.sleep(0.00001)
    GPIO.output(PIN_TRIG, GPIO.LOW)

    timeout = time.time() + 0.03
    start_time = time.time()
    while GPIO.input(PIN_ECHO) == 0:
        start_time = time.time()
        if start_time > timeout:
            return None

    timeout = time.time() + 0.03
    stop_time = time.time()
    while GPIO.input(PIN_ECHO) == 1:
        stop_time = time.time()
        if stop_time > timeout:
            return None

    return (stop_time - start_time) * 343000 / 2


def ukur_dengan_validasi():
    sampel = []
    for _ in range(JUMLAH_SAMPEL):
        j = baca_ultrasonik_mentah()
        if j is not None and j <= JARAK_MAX_VALID:
            sampel.append(j)
        time.sleep(DELAY_ANTAR_SAMPEL)

    n = len(sampel)
    if n < JUMLAH_SAMPEL // 2:
        return {"valid": False, "jarak": 0.0, "noise": 0.0, "pesan": "Objek tidak terdeteksi"}

    sampel.sort()
    median = sampel[n // 2]
    noise  = sampel[-1] - sampel[0]

    if median < JARAK_MIN_VALID:
        return {"valid": False, "jarak": median, "noise": noise, "pesan": "Jarak terlalu dekat (<2cm)"}
    if noise > NOISE_MAX_MM:
        return {"valid": False, "jarak": median, "noise": noise, "pesan": "Variasi getaran terlalu besar"}

    return {"valid": True, "jarak": median, "noise": noise, "pesan": ""}


def kalibrasi_referensi():
    global jarak_referensi, referensi_valid
    print("[KALIBRASI] Mengukur jarak referensi kulit normal...")
    h = ukur_dengan_validasi()
    if h["valid"]:
        jarak_referensi = h["jarak"]
        referensi_valid = True
        print(f"[KALIBRASI] Referensi: {jarak_referensi:.2f} mm")
    else:
        print(f"[KALIBRASI] Gagal: {h['pesan']}")


def ukur_lesi():
    global terakhir_ultrasonik
    if not referensi_valid:
        kalibrasi_referensi()
        return

    print("[ULTRASONIK] Mengukur elevasi lesi...")
    h = ukur_dengan_validasi()
    if not h["valid"]:
        print(f"[ULTRASONIK] Gagal: {h['pesan']}")
        return

    selisih = jarak_referensi - h["jarak"]
    # Interpretasi FISIK yang benar:
    #   selisih > 0  → jarak_lesi < jarak_referensi → permukaan lebih dekat ke
    #                  sensor → lesi MENONJOL / PADAT (nodul).
    #   selisih < 0  → jarak_lesi > jarak_referensi → permukaan lebih jauh →
    #                  jaringan cekung / lunak (KENYAL).
    if selisih < -BATAS_KENYAL_MM:
        status = "KENYAL (jaringan lunak/cekung)"
    elif selisih < -BATAS_PADAT_MM:
        status = "SEMI-PADAT (konsistensi campuran)"
    elif selisih <= BATAS_PADAT_MM:
        status = "SETARA REFERENSI (tidak ada elevasi)"
    else:
        status = "PADAT/MENONJOL (nodul lesi)"

    terakhir_ultrasonik = {
        "jarak_referensi": round(jarak_referensi, 2),
        "jarak_lesi":      round(h["jarak"], 2),
        "selisih":         round(selisih, 2),
        "status":          status,
    }
    print(f"[ULTRASONIK] {terakhir_ultrasonik}")
    simpan_hasil_ultrasonik(jarak_referensi, h["jarak"], selisih, status)

# ================================================================
# SHUTDOWN
# ================================================================

def _izin_shutdown_ada():
    """True jika user boleh 'sudo shutdown' tanpa password (aturan
    /etc/sudoers.d/bccare). Tanpa izin ini program berhenti tapi Pi tetap menyala."""
    try:
        r = subprocess.run(["sudo", "-n", "-l", "/usr/sbin/shutdown"],
                           capture_output=True, timeout=5)
        return r.returncode == 0
    except Exception:
        return False


def matikan_alat_dengan_aman():
    print("[SHUTDOWN] Mematikan alat...")
    matikan_iluminasi()
    kedip_indikator(4, on_time=0.4, off_time=0.4, tunggu=True)
    comm.stop()
    if kamera_tersedia and picam2:
        picam2.stop()
    if is_rpi:
        GPIO.cleanup()
    subprocess.run(["sudo", "shutdown", "-h", "now"])
    os._exit(0)

# ================================================================
# STATE MACHINE TOMBOL
# ================================================================

def button_loop():
    pending_single_click = False
    last_release_time = 0.0

    while True:
        if not is_rpi:
            time.sleep(1)
            continue

        if GPIO.input(PIN_BUTTON) == GPIO.LOW:
            press_start = time.time()
            while GPIO.input(PIN_BUTTON) == GPIO.LOW:
                time.sleep(0.01)
            held_duration = time.time() - press_start

            if held_duration >= SHUTDOWN_THRESHOLD:
                matikan_alat_dengan_aman()
            elif not alat_aktif:
                aktifkan_alat()
            elif held_duration >= LONG_PRESS_THRESHOLD:
                pass   # tahan 0.8–8 detik: tidak ada fungsi (ultrasonik tidak dipakai)
            else:
                release_time = time.time()
                if pending_single_click and (release_time - last_release_time) <= DOUBLE_CLICK_WINDOW:
                    pending_single_click = False
                    ganti_mode()
                else:
                    pending_single_click = True
                    last_release_time = release_time

        if pending_single_click and (time.time() - last_release_time) > DOUBLE_CLICK_WINDOW:
            pending_single_click = False
            if comm.client_sock is not None and not siap_scan:
                # HP terhubung tetapi aplikasi tidak di halaman Pemindaian:
                # scan hanya boleh setelah Skin Risk Assessment.
                print("[TOMBOL] Scan ditolak — aplikasi belum di halaman Pemindaian.")
                kedip_gagal()
                comm.send_json({
                    "type": "scan_rejected",
                    "msg": "Tombol alat ditekan, tetapi pemindaian hanya bisa dari "
                           "halaman Pemindaian. Mulai lewat Skrining Baru "
                           "(Skin Risk Assessment).",
                })
            else:
                # Jalankan scan di thread terpisah agar inferensi ML (beberapa detik)
                # tidak memblokir loop tombol (deteksi shutdown/long-press jadi lambat).
                threading.Thread(target=ambil_gambar_dengan_error_handling, daemon=True).start()

        time.sleep(0.01)

# ================================================================
# MAIN
# ================================================================

if __name__ == "__main__":
    try:
        print("=" * 60)
        print("  BC-CARE — DETEKSI KANKER KULIT (BCC) VIA RASPBERRY PI 4  ")
        print(f"  LED Merah  : GPIO {PIN_LED_INDIKATOR} (indikator proses)")
        print(f"  LED UV     : GPIO {PIN_LED_UV} (365nm)")
        print(f"  LED Putih  : GPIO {PIN_LED_WHITE}")
        print("=" * 60)

        # Bluetooth harus start sebelum button_loop agar
        # Android bisa konek & kirim START_SCAN kapan saja
        print("[BT] Memulai Bluetooth RFCOMM server...")
        comm.start_bluetooth_server()

        print("[SISTEM] Siap. Tekan tombol fisik atau kirim START_SCAN dari Android.")
        button_loop()

    except KeyboardInterrupt:
        print("\n[STOP] Dihentikan oleh pengguna.")
    finally:
        try:
            os.unlink(PIDFILE)
        except OSError:
            pass
        release_camera()
        comm.stop()
        if is_rpi:
            GPIO.cleanup()

"""
BCcare - Alat Pencitraan & Deteksi Lesi Kulit Berbasis Raspberry Pi 4

Fitur:
  1. Dual-mode iluminasi: LED UV 365nm & LED Putih (Dermoskopi)
  2. Klasifikasi biner: NORMAL vs BCC via EfficientNetB3 (TFLite / Keras)
  3. Dua LED indikator fisik:
       - GPIO 22 (Hijau): NORMAL
       - GPIO 25 (Merah): BCC
  4. Sensor ultrasonik HC-SR04 untuk estimasi ketebalan/elevasi lesi
  5. Bluetooth Classic RFCOMM/SPP offline →
     streaming progress + hasil ke Android
  6. Push-button state machine (1-klik, 2-klik, tahan)

Protokol (JSON + newline — transport Bluetooth Classic RFCOMM):
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
from bccare_ml import get_classifier
from bccare_comm import BCCareComm

# ================================================================
# SINGLE-INSTANCE GUARD
# Proses kedua tidak boleh jalan bersama proses pertama: mereka berebut
# kamera (Device or resource busy) dan GPIO (channel already in use).
# Deteksi via pidfile.
# ================================================================
PIDFILE = "/tmp/bccare.pid"

def _kill_stale_instance():
    """Jika ada proses bccare_main lama, hentikan (proses lama memegang
    kamera/GPIO dan membuat instance baru gagal start)."""
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
                          f"menghentikan agar kamera/GPIO terlepas...")
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
PIN_LED_DISEASE_1   = 22   # Indikator NORMAL / Jinak  (Hijau)
PIN_LED_DISEASE_2   = 25   # Indikator BCC / Malignant (Merah)
PIN_TRIG            = 23   # Ultrasonik TRIG
PIN_ECHO            = 24   # Ultrasonik ECHO
PIN_BUTTON          = 18   # Push button multi-fungsi

# ================================================================
# KONFIGURASI TOMBOL
# ================================================================
DOUBLE_CLICK_WINDOW   = 0.4   # detik — jendela deteksi klik ganda
LONG_PRESS_THRESHOLD  = 0.8   # detik — tahan untuk ukur lesi
RECALIBRATE_THRESHOLD = 3.0   # detik — tahan untuk kalibrasi ulang
SHUTDOWN_THRESHOLD    = 8.0   # detik — tahan untuk shutdown

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
# Direktori hasil scan & DB disimpan di direktori home user yang aktif
# (mis. /home/pi atau /home/padilkyun) — bukan path hardcoded yang bisa
# beda username / belum ada.
SAVE_DIR = os.path.join(os.path.expanduser("~"), "bccare_captures")
os.makedirs(SAVE_DIR, exist_ok=True)
init_db()

# ================================================================
# DETEKSI HARDWARE GPIO
# ================================================================
try:
    import RPi.GPIO as GPIO
    is_rpi = True
    GPIO.setmode(GPIO.BCM)
    for pin_out in [PIN_LED_UV, PIN_LED_WHITE, PIN_LED_DISEASE_1, PIN_LED_DISEASE_2, PIN_TRIG]:
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
try:
    from picamera2 import Picamera2
    picam2 = Picamera2()
    picam2.configure(picam2.create_still_configuration())
    picam2.start()
    time.sleep(1)
    kamera_tersedia = True
    print("[KAMERA] Arducam/PiCamera2 siap.")
except Exception as cam_err:
    picam2 = None
    kamera_tersedia = False
    print(f"[KAMERA] Tidak terdeteksi ({cam_err}). Mode simulasi gambar aktif.")


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
scan_lock = threading.Lock()   # cegah dua scan bersamaan (tombol + START_SCAN Android)
terakhir_ultrasonik = {
    "jarak_referensi": 0.0,
    "jarak_lesi":      0.0,
    "selisih":         0.0,
    "status":          "Belum diukur",
}

# ================================================================
# ML CLASSIFIER & HANDLER PERINTAH
# ================================================================
classifier = get_classifier()


def on_command(command, params):
    """Callback dari BCCareComm saat Android mengirim perintah."""
    global current_mode
    if command in ("START_SCAN", "PREPARE_SCAN"):
        req_mode = params.get("mode", "uv")
        if req_mode in ("uv", "white") and req_mode != current_mode:
            current_mode = req_mode

        # Pastikan alat aktif & LED iluminasi menyala SEBELUM foto diambil.
        # Tanpa ini, scan dari Android saat alat belum diaktifkan tombol fisik
        # menghasilkan foto gelap yang tetap diklasifikasi (hasil menyesatkan).
        if not alat_aktif:
            aktifkan_alat()
        else:
            _update_illumination_leds()

        if command == "PREPARE_SCAN":
            # Alat disiapkan (LED menyala sesuai mode) TAPI TIDAK mengambil foto.
            # Capture hanya terjadi saat tombol fisik ditekan (single click)
            # atau perintah START_SCAN eksplisit.
            comm.send_json({
                "type": "scan_ready",
                "mode": current_mode,
                "message": "Alat siap. Tekan tombol fisik pada probe untuk memulai.",
            })
            print(f"[NET-CMD] PREPARE_SCAN diterima → siap (mode: {current_mode})")
            return

        print(f"[NET-CMD] START_SCAN diterima (mode: {current_mode})")
        ambil_gambar_dengan_error_handling()


def ambil_gambar_dengan_error_handling():
    """
    Wrapper ambil_gambar dengan try/except. Exception di thread scan (dari
    perintah Android atau tombol fisik) tidak boleh mati diam-diam — Android
    harus menerima event 'error' agar UI tidak menggantung selamanya.
    """
    try:
        ambil_gambar()
    except Exception as e:
        print(f"[SCAN-ERROR] {e}")
        comm.send_error(f"Scan gagal: {e}")


# Channel RFCOMM 1 adalah kanal SPP yang dipakai client Flutter.
comm = BCCareComm(port=1, on_command_callback=on_command)

# ================================================================
# KONTROL LED
# ================================================================

def set_disease_led(disease):
    """Nyalakan LED indikator sesuai hasil klasifikasi."""
    if not is_rpi:
        pin_str = "GPIO 22 (NORMAL)" if disease == "NORMAL" else "GPIO 25 (BCC)"
        print(f"[LED-SIM] {pin_str} ON")
        return
    if disease == "NORMAL":
        GPIO.output(PIN_LED_DISEASE_1, GPIO.HIGH)
        GPIO.output(PIN_LED_DISEASE_2, GPIO.LOW)
    elif disease == "BCC":
        GPIO.output(PIN_LED_DISEASE_2, GPIO.HIGH)
        GPIO.output(PIN_LED_DISEASE_1, GPIO.LOW)
    else:
        GPIO.output(PIN_LED_DISEASE_1, GPIO.LOW)
        GPIO.output(PIN_LED_DISEASE_2, GPIO.LOW)


def reset_disease_leds():
    if is_rpi:
        GPIO.output(PIN_LED_DISEASE_1, GPIO.LOW)
        GPIO.output(PIN_LED_DISEASE_2, GPIO.LOW)


def _update_illumination_leds():
    """Nyalakan LED iluminasi sesuai mode (hanya saat alat aktif)."""
    if not is_rpi or not alat_aktif:
        return
    if current_mode == "uv":
        GPIO.output(PIN_LED_WHITE, GPIO.LOW)
        GPIO.output(PIN_LED_UV,    GPIO.HIGH)
    else:
        GPIO.output(PIN_LED_UV,    GPIO.LOW)
        GPIO.output(PIN_LED_WHITE, GPIO.HIGH)


def blink_indikator_selesai(led_pin, times=3):
    """Kedipkan LED hasil beberapa kali di thread terpisah."""
    if not is_rpi:
        return
    def _blink():
        for _ in range(times):
            GPIO.output(led_pin, GPIO.LOW)
            time.sleep(0.12)
            GPIO.output(led_pin, GPIO.HIGH)
            time.sleep(0.12)
    threading.Thread(target=_blink, daemon=True).start()


def aktifkan_alat():
    global alat_aktif
    alat_aktif = True
    print("[AKTIVASI] Alat BC-Care aktif. Mode awal: UV (365nm)")
    _update_illumination_leds()
    if is_rpi:
        GPIO.output(PIN_LED_DISEASE_1, GPIO.HIGH)
        GPIO.output(PIN_LED_DISEASE_2, GPIO.HIGH)
        time.sleep(0.4)
        GPIO.output(PIN_LED_DISEASE_1, GPIO.LOW)
        GPIO.output(PIN_LED_DISEASE_2, GPIO.LOW)


def ganti_mode():
    global current_mode
    current_mode = "white" if current_mode == "uv" else "uv"
    _update_illumination_leds()
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

    try:
        reset_disease_leds()
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
        time.sleep(0.3)  # beri waktu LED stabil

        # Step 2: Ambil foto
        comm.send_scan_progress(2, SCAN_TOTAL, SCAN_STEPS[1])
        if kamera_tersedia and picam2:
            try:
                picam2.capture_file(filename)
                print(f"[KAMERA] Foto tersimpan: {filename}")
            except Exception as e:
                # Jangan diam-diam ganti dengan gambar mock — alat medis harus
                # jujur: kamera gagal berarti scan tidak valid.
                print(f"[KAMERA] Gagal capture: {e}")
                comm.send_error(f"Kamera gagal mengambil foto: {e}")
                return None
        else:
            # Tanpa kamera fisik (testbed/dev), pakai gambar tiruan TAPI beri
            # tahu Android bahwa ini simulasi.
            print("[KAMERA] Tidak ada kamera fisik — menggunakan gambar simulasi.")
            comm.send_json({"type": "scan_warning", "msg": "Kamera tidak terdeteksi — gambar simulasi digunakan."})
            filename = _generate_mock_image(filename)

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

        # Mode simulasi ML → beri tahu Android hasil ini bukan inferensi nyata.
        if is_simulated:
            comm.send_json({"type": "scan_warning",
                            "msg": "Hasil BUKAN dari inferensi model nyata (model tidak "
                                   "termuat / .keras mengandung augmentasi acak). "
                                   "Jalankan export_to_tflite.py & deploy .tflite."})

        # Nyalakan LED fisik
        set_disease_led(disease)
        target_pin = PIN_LED_DISEASE_2 if disease == "BCC" else PIN_LED_DISEASE_1
        blink_indikator_selesai(target_pin, times=2)

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
        )

        return ml_result
    finally:
        scan_lock.release()


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

def matikan_alat_dengan_aman():
    print("[SHUTDOWN] Mematikan alat...")
    reset_disease_leds()
    if is_rpi:
        GPIO.output(PIN_LED_UV,    GPIO.LOW)
        GPIO.output(PIN_LED_WHITE, GPIO.LOW)
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
            elif held_duration >= RECALIBRATE_THRESHOLD:
                kalibrasi_referensi()
            elif held_duration >= LONG_PRESS_THRESHOLD:
                ukur_lesi()
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
        print(f"  LED NORMAL : GPIO {PIN_LED_DISEASE_1} (Hijau)")
        print(f"  LED BCC    : GPIO {PIN_LED_DISEASE_2} (Merah)")
        print(f"  LED UV     : GPIO {PIN_LED_UV} (365nm)")
        print(f"  LED Putih  : GPIO {PIN_LED_WHITE}")
        print("=" * 60)

        # Server Bluetooth harus start sebelum button_loop agar
        # HP Android bisa konek & kirim START_SCAN kapan saja.
        print("[BT] Memulai server Bluetooth Classic SPP...")
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

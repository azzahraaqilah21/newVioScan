#!/usr/bin/env python3
"""
bccare_cam_test.py — TEST KONEKSI KAMERA via Bluetooth (khusus pengujian)

Script mandiri: buka kamera USB (OpenCV /dev/videoN), lalu kirim foto ke
aplikasi Android BC-Care lewat Bluetooth SPP yang sama dengan produksi,
TANPA menyalakan GPIO, LED, atau model ML.

Alur:
  1. Start server Bluetooth RFCOMM channel 1 (reuse BCCareComm).
  2. Tunggu sampai HP Android terhubung (app melakukan SPP connect + PING).
  3. Segera ambil 1 frame, enkode JPEG, kirim sebagai 'classification_result'
     mode 'camera_test' + simulated=True.
     → di HP: banner "HASIL SIMULASI" + foto tampil = koneksi & transfer OK.

Cara pakai (di Raspberry Pi / laptop dev dengan kamera USB):
  sudo apt install python3-opencv   # sekali saja
  python3 bccare_cam_test.py              # kirim 1 foto saat HP connect
  python3 bccare_cam_test.py --loop 3     # kirim ulang tiap 3 detik (watchdog)
  python3 bccare_cam_test.py --device 0   # pilih indeks kamera (default 0)
  python3 bccare_cam_test.py --port 1     # RFCOMM channel (default 1)

Di HP Android: pasangkan Pi, lalu app BC-Care → Koneksi Perangkat → Bluetooth.
Begitu tersambung, foto dikirim otomatis dan tampil di layar hasil.

Catatan:
  - JANGAN jalankan bersamaan dengan bccare_main.py — kamera /dev/videoN
    hanya bisa dipegang satu proses (Device or resource busy).
  - Kalau kamera tidak terdeteksi, kirim event 'error' agar app menampilkan
    keterangan alih-alih menggantung.
"""

import argparse
import base64
import time

try:
    import cv2
except ImportError:
    cv2 = None

from bccare_comm import BCCareComm


# ================================================================
# KAMERA (USB via OpenCV / VideoCapture)
# ================================================================

def deteksi_kamera(device_idx):
    """Buka kamera USB; kembalikan object VideoCapture / None."""
    if cv2 is None:
        print("[KAMERA] OpenCV tidak terpasang — install: "
              "sudo apt install python3-opencv")
        return None
    cap = cv2.VideoCapture(device_idx)
    if not cap or not cap.isOpened():
        print(f"[KAMERA] Tidak bisa membuka kamera /dev/video{device_idx} "
              f"(Logitech tidak terpasang / dipakai proses lain?).")
        cap.release() if cap else None
        return None
    return cap


def jepret(cap):
    """
    Ambil satu frame stabil. Beberapa frame pertama dibuang agar
    auto-white-balance / eksposure Logitech settle (berarti-berarti).
    """
    for _ in range(8):
        cap.grab()  # buang framebuffer lama
    ok, frame = cap.read()
    if not ok or frame is None:
        raise RuntimeError("read() gagal — kamera kemungkinan tersumbat/disambar proses lain.")
    return frame


def frame_to_b64(frame, max_width=600, quality=80):
    """Resize (bila lebar > max_width) lalu encode JPEG → base64.

    Ukuran dibatasi agar payload over-the-air kecil (bandingkan default
    bccare_comm yang juga max 600px / q75)."""
    h, w = frame.shape[:2]
    if w > max_width:
        rasio = max_width / w
        frame = cv2.resize(frame, (max_width, int(h * rasio)),
                           interpolation=cv2.INTER_AREA)
    ok, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, quality])
    if not ok:
        raise RuntimeError("Encode JPEG gagal.")
    return base64.b64encode(buf.tobytes()).decode("utf-8")


# ================================================================
# PENGIRIMAN HASIL UJI KE ANDROID
# ================================================================

def kirim_foto_test(comm, cap):
    """
    Ambil foto lalu kirim sebagai 'classification_result' (mode camera_test,
    simulated=True → app menampilkan banner "HASIL SIMULASI" + gambar).
    """
    try:
        t0 = time.time()
        frame = jepret(cap)
        img_b64 = frame_to_b64(frame)
        print(f"[SEND] Foto {frame.shape[1]}x{frame.shape[0]} px "
              f"diencode ({len(img_b64)} char b64, {(time.time()-t0)*1000:.0f} ms).")

        payload = {
            "type": "classification_result",
            "timestamp": time.time(),
            "mode": "camera_test",
            "source": "camera_wifi_test",
            "disease": "CAMERA_TEST",
            "disease_index": 0,
            "confidence": 1.0,
            "probabilities": {"CAMERA_VALID": 1.0},
            "risk_level": "low",
            "image_base64": img_b64,
            "simulated": True,   # menandai hasil ini pengujian, bukan inferensi ML
        }
        ok = comm.send_json(payload)
        if ok:
            print("[SEND] Foto terkirim ke HP (mode camera_test, simulated=True).")
        else:
            print("[SEND] Tidak ada klien terhubung — foto dibatalkan.")
        return ok
    except Exception as e:
        print(f"[SEND] Gagal: {e}")
        comm.send_error(f"Test kamera gagal: {e}")
        return False


# ================================================================
# MAIN
# ================================================================

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", type=int, default=1,
                    help="channel Bluetooth RFCOMM (default 1)")
    ap.add_argument("--device", type=int, default=0,
                    help="indeks kamera USB (default 0 = /dev/video0)")
    ap.add_argument("--loop", type=float, default=0,
                    help="ulangi kirim foto tiap N detik selama ada HP terhubung "
                         "(default 0 = sekali per koneksi)")
    args = ap.parse_args()

    comm = BCCareComm(port=args.port)
    if not comm.start_bluetooth_server():
        print("[SISTEM] Gagal start server Bluetooth RFCOMM.")
        return

    cap = deteksi_kamera(args.device)

    print("=" * 60)
    print("  BC-CARE — TEST KONEKSI KAMERA via Bluetooth SPP")
    print(f"  RFCOMM channel: {args.port}")
    print(f"  Kamera USB    : /dev/video{args.device} "
          f"({'SIAP' if cap is not None else 'TIDAK TERDETEKSI'})")
    print("  Mode loop     : " + (f"tiap {args.loop}s" if args.loop else "sekali per koneksi"))
    print("  Tunggu HP Android terhubung via Bluetooth SPP...")
    print("=" * 60)

    try:
        while True:
            # Tunggu ada klien aktif.
            while comm.client_sock is None:
                time.sleep(0.25)

            print("[SISTEM] HP terhubung — mengambil & mengirim foto uji...")
            kirim_foto_test(comm, cap)

            while comm.client_sock is not None:
                time.sleep(args.loop if args.loop > 0 else 0.25)
                if args.loop > 0 and comm.client_sock is not None:
                    kirim_foto_test(comm, cap)

            print("[SISTEM] HP terputus — menunggu koneksi baru...")
    except KeyboardInterrupt:
        print("\n[STOP] Dihentikan pengguna.")
    finally:
        if cap is not None:
            cap.release()
        comm.stop()


if __name__ == "__main__":
    main()

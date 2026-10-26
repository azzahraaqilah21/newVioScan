"""
BCcare - Modul komunikasi Bluetooth Classic RFCOMM/SPP
Mengirimkan data klasifikasi ML, pembacaan ultrasonik, dan foto secara offline ke Android.
Protokol: JSON + newline.

Protokol:
  Android → Raspi  : JSON + newline  e.g. {"command":"START_SCAN","mode":"uv"}\n
  Raspi   → Android: JSON + newline  e.g. {"type":"classification_result", ...}\n

Event types yang dikirim ke Android:
  pong                 : respons PING, konfirmasi perangkat siap
  scan_started         : scan mulai diproses
  scan_ready           : alat siap (PREPARE_SCAN, menunggu tombol fisik)
  scan_progress        : update tahap pemrosesan (step 1-4)
  classification_result: hasil final beserta gambar base64 dan data ultrasonik
  all_results          : ringkasan semua riwayat scan (tanpa gambar)
  error                : pesan error

Catatan implementasi:
  - send_json() memakai sendall() (bukan send()) — wajib, karena payload
    classification_result berisi base64 gambar (puluhan KB hingga ratusan KB)
    dan socket.send() bisa short-write sehingga JSON terpotong & gagal di-parse
    di sisi Android.
  - GET_IMAGE:<path> didukung untuk mengambil ulang gambar hasil scan lama.
"""

import json
import threading
import time
import os
import base64
from io import BytesIO
from PIL import Image

try:
    from bccare_db import ambil_hasil_terakhir, ambil_semua_hasil
except ImportError:
    from .bccare_db import ambil_hasil_terakhir, ambil_semua_hasil


class BCCareComm:
    RFCOMM_CHANNEL = 1
    SPP_UUID = "00001101-0000-1000-8000-00805F9B34FB"

    def __init__(self, host="", port=RFCOMM_CHANNEL, on_command_callback=None):
        """
        Server Bluetooth Classic SPP untuk koneksi Android.

        Args:
            host: interface untuk bind server ("" = semua interface)
            port: RFCOMM channel (default 1)
            on_command_callback: Callback saat ada perintah dari Android
                                 signature: func(command: str, params: dict)
        """
        self.host = host
        self.port = port
        self.on_command_callback = on_command_callback
        self.server_sock = None
        self.client_sock = None
        self.client_address = None
        self.running = False
        self.lock = threading.Lock()   # serialisasi send_json dari multi-thread

    # ================================================================
    # SERVER LIFECYCLE
    # ================================================================

    def start_bluetooth_server(self):
        """Dengar koneksi Bluetooth Classic RFCOMM dengan profil SPP."""
        if self.running:
            return True
        self.running = True
        try:
            import bluetooth
            self.server_sock = bluetooth.BluetoothSocket(bluetooth.RFCOMM)
            self.server_sock.bind(("", self.port))
            self.server_sock.listen(5)
            try:
                bluetooth.advertise_service(
                    self.server_sock,
                    "BC-Care",
                    service_id=self.SPP_UUID,
                    service_classes=[self.SPP_UUID, bluetooth.SERIAL_PORT_CLASS],
                    profiles=[bluetooth.SERIAL_PORT_PROFILE],
                )
                print("[BT] Layanan SPP BC-Care diiklankan melalui SDP.")
            except Exception as e:
                print(f"[BT] Gagal advertise layanan SDP: {e}. "
                      "Android mungkin tidak dapat menemukan RFCOMM service.")
            print(f"[BT] Server RFCOMM menunggu koneksi pada channel {self.port}.")
            threading.Thread(target=self._accept_loop, daemon=True).start()
            return True
        except Exception as e:
            print(f"[BT] Gagal memulai server Bluetooth RFCOMM: {e}")
            self.running = False
            return False

    def _accept_loop(self):
        """Loop terima koneksi masuk; satu klien aktif dalam satu waktu."""
        while self.running:
            try:
                print("[BT] Menunggu koneksi Bluetooth dari HP...")
                client, client_info = self.server_sock.accept()
                with self.lock:
                    self.client_sock = client
                    self.client_address = client_info
                print(f"[BT] HP terhubung: {client_info}")
                self._handle_client_stream(client)
            except Exception as e:
                if self.running:
                    print(f"[BT] Accept error: {e}")
                time.sleep(1)

    def _handle_client_stream(self, sock):
        """Baca stream baris JSON dari klien Android."""
        buffer = ""
        while self.running and sock is self.client_sock:
            try:
                data = sock.recv(1024)
                if not data:
                    break
                buffer += data.decode("utf-8", errors="ignore")
                while "\n" in buffer:
                    line, buffer = buffer.split("\n", 1)
                    line = line.strip()
                    if line:
                        self._process_incoming_command(line)
            except Exception as e:
                print(f"[BT] Stream terputus: {e}")
                break
        self._cleanup_client()

    def _cleanup_client(self):
        with self.lock:
            if self.client_sock:
                try:
                    self.client_sock.close()
                except Exception:
                    pass
                self.client_sock = None
                self.client_address = None
                print("[BT] Koneksi klien ditutup.")

    # ================================================================
    # COMMAND HANDLING
    # ================================================================

    def _process_incoming_command(self, raw_cmd):
        """Proses perintah JSON dari Android."""
        print(f"[BT] Perintah masuk: {raw_cmd}")
        cmd_name = raw_cmd
        params = {}

        if raw_cmd.startswith("{"):
            try:
                parsed = json.loads(raw_cmd)
                cmd_name = parsed.get("command", "")
                params = parsed
            except Exception:
                pass

        try:
            if cmd_name == "PING":
                self.send_json({
                    "type": "pong",
                    "device": "BC-Care UV-Scan Pro (Raspberry Pi 4)",
                    "status": "ready",
                    "time": time.time(),
                })

            elif cmd_name == "START_SCAN":
                mode = params.get("mode", "uv")
                self.send_json({
                    "type": "scan_started",
                    "mode": mode,
                    "message": "Memulai pemindaian...",
                })
                if self.on_command_callback:
                    threading.Thread(
                        target=self.on_command_callback,
                        args=("START_SCAN", params),
                        daemon=True,
                    ).start()

            elif cmd_name == "PREPARE_SCAN":
                # Callback (bccare_main.on_command) yang mengirim 'scan_ready'.
                if self.on_command_callback:
                    threading.Thread(
                        target=self.on_command_callback,
                        args=("PREPARE_SCAN", params),
                        daemon=True,
                    ).start()
                else:
                    self.send_error("Handler PREPARE_SCAN belum terpasang.")

            elif cmd_name == "GET_LATEST":
                self.send_latest_saved_result()

            elif cmd_name == "GET_ALL":
                self.send_all_saved_results()

            elif cmd_name.startswith("GET_IMAGE:"):
                # Format: GET_IMAGE:/home/<user>/bccare_captures/UV_xxx.jpg
                requested = cmd_name.split(":", 1)[1].strip()
                if os.path.exists(requested):
                    img_b64 = self._encode_image_to_base64(requested)
                    if img_b64:
                        self.send_json({
                            "type": "classification_result",
                            "timestamp": time.time(),
                            "image_base64": img_b64,
                            "source": "image_request",
                        })
                    else:
                        self.send_error("Gagal encode gambar.")
                else:
                    self.send_error(f"Gambar tidak ditemukan: {requested}")

            elif cmd_name == "DISCONNECT":
                self._cleanup_client()

            else:
                self.send_error(f"Perintah tidak dikenal: {cmd_name}")
        except Exception as e:
            self.send_error(f"Handler error: {e}")

    # ================================================================
    # PROGRESS STREAMING  (dipanggil dari bccare_main.py)
    # ================================================================

    def send_scan_progress(self, step: int, total: int, label: str):
        """
        Kirim update tahap pemrosesan ke Android agar UI progress bar berjalan nyata.
        step : tahap saat ini (1-based)
        total: jumlah total tahap
        label: deskripsi tahap, misal 'Mengambil foto...'
        """
        self.send_json({
            "type": "scan_progress",
            "step": step,
            "total": total,
            "label": label,
            "percent": round(step / total * 100),
        })

    # ================================================================
    # RESULT SENDING
    # ================================================================

    def send_classification_result(
        self, disease, confidence, probabilities, mode, image_path,
        ultrasonic_data=None, simulated=False
    ):
        """
        Kirim paket hasil klasifikasi lengkap ke Android.
        Gambar dikompresi JPEG lalu di-encode base64 di dalam payload JSON.
        simulated=True → hasil BUKAN dari inferensi model nyata (fallback/simulasi);
        Android menampilkan disclaimer sesuai flag ini.
        """
        img_b64 = ""
        if image_path and os.path.exists(image_path):
            img_b64 = self._encode_image_to_base64(image_path)

        u_data = ultrasonic_data or {
            "jarak_referensi": 0.0,
            "jarak_lesi": 0.0,
            "selisih": 0.0,
            "status": "TIDAK ADA DATA ULTRASONIK",
        }

        payload = {
            "type": "classification_result",
            "timestamp": time.time(),
            "mode": mode,
            "disease": disease,
            "disease_index": 1 if disease == "BCC" else 0,
            "confidence": float(confidence),
            "probabilities": probabilities or {
                "NORMAL": round(1.0 - confidence if disease == "BCC" else confidence, 4),
                "BCC": round(confidence if disease == "BCC" else 1.0 - confidence, 4),
            },
            "risk_level": "high" if disease == "BCC" else "low",
            "ultrasonic": u_data,
            "image_base64": img_b64,
            "simulated": bool(simulated),
        }

        success = self.send_json(payload)
        if success:
            print(f"[BT] Hasil terkirim: {disease} ({confidence:.1%})")
        else:
            print("[BT] Tidak ada klien terhubung. Hasil tersimpan lokal saja.")
        return success

    def _encode_image_to_base64(self, image_path, max_width=600, quality=75):
        """Resize & kompres JPEG lalu kembalikan string base64."""
        try:
            with Image.open(image_path) as img:
                img = img.convert("RGB")
                if img.width > max_width:
                    ratio = max_width / img.width
                    img = img.resize(
                        (max_width, int(img.height * ratio)),
                        Image.Resampling.LANCZOS,
                    )
                buf = BytesIO()
                img.save(buf, format="JPEG", quality=quality, optimize=True)
                return base64.b64encode(buf.getvalue()).decode("utf-8")
        except Exception as e:
            print(f"[BT] Gagal encode gambar ke base64: {e}")
            return ""

    def send_latest_saved_result(self):
        """Ambil data terakhir dari DB dan kirim ke Android."""
        row = ambil_hasil_terakhir()
        if not row:
            self.send_json({
                "type": "error",
                "msg": "Belum ada riwayat hasil pemindaian.",
            })
            return
        prob = {}
        if row.get("probabilities"):
            try:
                prob = json.loads(row["probabilities"])
            except Exception:
                pass
        self.send_classification_result(
            disease=row.get("disease") or "UNKNOWN",
            confidence=row.get("confidence") or 0.0,
            probabilities=prob,
            mode=row.get("mode") or "uv",
            image_path=row.get("image_path"),
            ultrasonic_data={
                "jarak_referensi": row.get("jarak_referensi") or 0.0,
                "jarak_lesi": row.get("jarak_lesi") or 0.0,
                "selisih": row.get("selisih") or 0.0,
                "status": row.get("status") or "",
            },
        )

    def send_all_saved_results(self):
        """Kirim ringkasan semua hasil tanpa base64 image (hemat bandwidth)."""
        rows = ambil_semua_hasil(limit=30)
        results = [
            {
                "timestamp": r["timestamp"],
                "mode": r.get("mode"),
                "disease": r.get("disease"),
                "confidence": r.get("confidence"),
                "status": r.get("status"),
                "selisih": r.get("selisih"),
            }
            for r in rows
        ]
        self.send_json({"type": "all_results", "count": len(results), "results": results})

    def send_error(self, message: str):
        """Kirim pesan error ke Android (jika tersambung)."""
        ok = self.send_json({"type": "error", "msg": str(message)})
        if not ok:
            print(f"[BT] (offline) error: {message}")
        return ok

    # ================================================================
    # LOW-LEVEL SEND
    # ================================================================

    def send_json(self, obj):
        """
        Kirim satu JSON object diakhiri newline ke klien Android yang terhubung.
        WAJIB sendall(): payload bisa ratusan KB (base64 gambar) dan send()
        bisa short-write → JSON terpotong di sisi Android.
        """
        if not self.client_sock:
            return False
        with self.lock:
            if not self.client_sock:
                return False
            try:
                payload_str = json.dumps(obj, ensure_ascii=False) + "\n"
                self.client_sock.sendall(payload_str.encode("utf-8"))
                return True
            except Exception as e:
                print(f"[BT] Gagal kirim JSON: {e}")
                self._cleanup_client()
                return False

    # ================================================================
    # STOP
    # ================================================================

    def stop(self):
        """Hentikan server RFCOMM dan bersihkan semua resource."""
        self.running = False
        self._cleanup_client()
        if self.server_sock:
            try:
                self.server_sock.close()
            except Exception:
                pass
            self.server_sock = None
        print("[BT] Server RFCOMM dihentikan.")

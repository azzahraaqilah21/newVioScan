"""
BCcare - Modul Komunikasi Bluetooth SPP (Serial Port Profile / RFCOMM)
Mengirimkan data klasifikasi ML, pembacaan ultrasonik, dan foto secara offline ke Android.

Protokol:
  Android → Raspi  : JSON + newline  e.g. {"command":"START_SCAN","mode":"uv"}\n
  Raspi   → Android: JSON + newline  e.g. {"type":"classification_result", ...}\n

Event types yang dikirim ke Android:
  pong                 : respons PING, konfirmasi perangkat siap
  scan_started         : scan mulai diproses
  scan_progress        : update tahap pemrosesan (step 1-4)
  classification_result: hasil final beserta gambar base64 dan data ultrasonik
  all_results          : ringkasan semua riwayat scan (tanpa gambar)
  error                : pesan error

Catatan implementasi:
  - send_json() memakai socket.sendall() (bukan send()) — wajib, karena payload
    classification_result berisi base64 gambar (puluhan KB hingga ratusan KB)
    dan socket.send() bisa short-write sehingga JSON terpotong & gagal di-parse
    di sisi Android.
  - GET_IMAGE:<path> didukung untuk mengambil ulang gambar hasil scan lama.
"""

import json
import threading
import time
import os
import socket
import base64
from io import BytesIO
from PIL import Image

try:
    from bccare_db import ambil_hasil_terakhir, ambil_semua_hasil
except ImportError:
    from .bccare_db import ambil_hasil_terakhir, ambil_semua_hasil


class BCCareComm:
    def __init__(self, port=1, on_command_callback=None):
        """
        Inisialisasi server Bluetooth RFCOMM.
        Args:
            port: Port RFCOMM (default 1)
            on_command_callback: Callback saat ada perintah dari Android
                                 signature: func(command: str, params: dict)
        """
        self.port = port
        self.on_command_callback = on_command_callback
        self.server_sock = None
        self.client_sock = None
        self.client_address = None
        self.running = False
        self.lock = threading.Lock()   # serialisasi send_json dari multi-thread
        self.use_native_socket = False
        self.profile_server = None     # SPPProfileServer (BlueZ D-Bus)
        # Callable -> dict info alat untuk halaman Perangkat di aplikasi
        # (diisi bccare_main; dikirim bersama 'pong' dan 'device_info').
        self.device_info_provider = None

    # ================================================================
    # SERVER LIFECYCLE
    # ================================================================

    def _run_cmd(self, cmd, timeout=8):
        """Jalankan command sistem, return (returncode, output gabungan)."""
        import subprocess
        try:
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
            return r.returncode, ((r.stdout or "") + (r.stderr or "")).strip()
        except FileNotFoundError:
            return -1, f"{cmd[0]}: tidak ditemukan"
        except subprocess.TimeoutExpired:
            return -2, f"{cmd[0]}: timeout"
        except Exception as e:
            return -3, str(e)

    def _ensure_adapter_ready(self):
        """
        Pastikan adapter Bluetooth UP, discoverable & pairable SEBELUM bind.

        Gejala yang dihindari: PyBluez 'no advertisable device' = hci0 DOWN /
        belum powered → record SPP TIDAK terdaftar ke SDP → Android gagal
        resolve channel RFCOMM → koneksi selalu gagal walau server jalan.
        Return True jika adapter siap.
        """
        self._run_cmd(["rfkill", "unblock", "bluetooth"])

        rc, out = self._run_cmd(["bluetoothctl", "show"])
        if rc != 0 or not out:
            print(f"[BT] Adapter tidak terdeteksi ({out}).")
            print("[BT] Cek hardware/driver: 'systemctl status hciuart' ; "
                  "'dmesg | grep -i -E bluetooth|uart' ; 'ls /sys/class/bluetooth'")
            return False

        if "Powered: yes" not in out:
            self._run_cmd(["bluetoothctl", "power", "on"])
            if "Powered: yes" not in self._run_cmd(["bluetoothctl", "show"])[1]:
                self._run_cmd(["sudo", "-n", "bluetoothctl", "power", "on"])

        self._run_cmd(["bluetoothctl", "discoverable", "on"])
        self._run_cmd(["bluetoothctl", "pairable", "on"])
        # Discoverable default hilang setelah 3 menit (timeout 180) — saat user
        # scan dari HP belakangan, device sudah tidak terlihat lagi. 0 = permanen.
        self._run_cmd(["bluetoothctl", "discoverable-timeout", "0"])
        # Nama yang tampil saat discovery dari HP (abaikan jika command tak ada)
        self._run_cmd(["bluetoothctl", "set-alias", "BC-Care"])
        self._run_cmd(["bluetoothctl", "system-alias", "BC-Care"])

        # Re-read SETELAH semua command (status sebelumnya bisa stale) +
        # fallback sudo untuk discoverable/pairable yang butuh privilege.
        rc, out = self._run_cmd(["bluetoothctl", "show"])
        if "Discoverable: yes" not in out:
            self._run_cmd(["sudo", "-n", "bluetoothctl", "discoverable", "on"])
            rc, out = self._run_cmd(["bluetoothctl", "show"])
        if "Pairable: yes" not in out:
            self._run_cmd(["sudo", "-n", "bluetoothctl", "pairable", "on"])
            rc, out = self._run_cmd(["bluetoothctl", "show"])

        addr = "?"
        for line in out.splitlines():
            line = line.strip()
            if line.startswith("Controller"):
                addr = line.split()[1] if len(line.split()) > 1 else addr
        powered = "Powered: yes" in out
        disc = "Discoverable: yes" in out
        pairable = "Pairable: yes" in out
        print(f"[BT] Adapter {addr} — powered={powered} discoverable={disc} pairable={pairable}")

        if not powered:
            print("[BT] [FIX] Adapter masih OFF. Jalankan manual lalu ulangi script:")
            print("       sudo bluetoothctl power on ; sudo rfkill unblock bluetooth")
            return False
        return True

    def start_bluetooth_server(self):
        """Memulai server RFCOMM. Fallback: PyBluez → native AF_BLUETOOTH."""
        if self.running:
            return True
        self.running = True

        self._ensure_adapter_ready()

        # --- Prioritas 0: BlueZ D-Bus Profile (tanpa PyBluez / --compat) ---
        try:
            try:
                from bccare_bt_profile import SPPProfileServer
            except ImportError:
                from .bccare_bt_profile import SPPProfileServer
            self.profile_server = SPPProfileServer(
                on_connection=self._on_profile_connection,
                name="BCcare", channel=self.port,
            )
            self.profile_server.start()
            print("[BT] Menunggu koneksi dari Android (via BlueZ profile)...")
            return True
        except Exception as e_dbus:
            self.profile_server = None
            print(f"[BT] Jalur D-Bus gagal ({e_dbus}), mencoba PyBluez/native...")

        # --- Prioritas 1: PyBluez ---
        try:
            import bluetooth
            self.server_sock = bluetooth.BluetoothSocket(bluetooth.RFCOMM)
            # SO_REUSEADDR: tanpa ini, restart cepat menghasilkan
            # "Channel 1 sibuk" karena socket lama masih berlabuh di kernel.
            self.server_sock.setsockopt(
                socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            # Bind channel yang DIMINTA dulu (default 1 — cocok dengan fallback
            # channel 1 dari flutter_bluetooth_serial jika SDP lookup gagal di
            # Android). Hanya jika channel sibuk → jatuh ke PORT_ANY.
            try:
                self.server_sock.bind(("", self.port))
            except OSError:
                print(f"[BT] Channel {self.port} sibuk — pakai PORT_ANY...")
                self.server_sock.bind(("", bluetooth.PORT_ANY))
            self.server_sock.listen(1)
            actual_port = self.server_sock.getsockname()[1]
            uuid = "00001101-0000-1000-8000-00805F9B34FB"
            try:
                bluetooth.advertise_service(
                    self.server_sock, "BCcare",
                    service_id=uuid,
                    service_classes=[uuid, bluetooth.SERIAL_PORT_CLASS],
                    profiles=[bluetooth.SERIAL_PORT_PROFILE],
                )
                print(f"[BT] Layanan SPP 'BCcare' diiklankan pada RFCOMM channel {actual_port}")
            except Exception as ad_err:
                print(f"[BT] Warning advertise: {ad_err} (tetap melanjutkan)")
            print(f"[BT] Server PyBluez siap pada channel {actual_port}")
            threading.Thread(target=self._accept_loop, daemon=True).start()
            return True
        except Exception as e:
            print(f"[BT] PyBluez tidak tersedia ({e}), mencoba native AF_BLUETOOTH...")

        # --- Prioritas 2: native Linux AF_BLUETOOTH ---
        # (socket diimport di level module — TIDAK di sini. Import lokal di
        #  fungsi ini membuat Python menganggap 'socket' variabel lokal seluruh
        #  fungsi → UnboundLocalError pada SO_REUSEADDR di atas.)
        try:
            if hasattr(socket, "AF_BLUETOOTH") and hasattr(socket, "BTPROTO_RFCOMM"):
                self.server_sock = socket.socket(
                    socket.AF_BLUETOOTH, socket.SOCK_STREAM, socket.BTPROTO_RFCOMM
                )
                self.server_sock.bind((socket.BDADDR_ANY, self.port))
                self.server_sock.listen(1)
                self.use_native_socket = True
                print(f"[BT] Server native AF_BLUETOOTH berjalan pada channel {self.port}")
                threading.Thread(target=self._accept_loop, daemon=True).start()
                return True
            else:
                print("[BT] Kernel tidak mendukung AF_BLUETOOTH.")
        except Exception as e_nat:
            print(f"[BT] Gagal memulai server native bluetooth: {e_nat}")

        print("[BT] Mode virtual (simulasi) — tidak ada koneksi fisik.")
        return False

    def _on_profile_connection(self, sock, device_path):
        """Dipanggil BlueZ saat Android terhubung (socket RFCOMM sudah jadi)."""
        self._cleanup_client()          # satu klien aktif dalam satu waktu
        with self.lock:
            self.client_sock = sock
            self.client_address = device_path
        print(f"[BT] Android terhubung: {device_path}")
        threading.Thread(
            target=self._handle_client_stream, args=(sock,), daemon=True
        ).start()

    def _accept_loop(self):
        """Loop terima koneksi masuk; satu klien aktif dalam satu waktu."""
        while self.running:
            try:
                print("[BT] Menunggu koneksi dari Android...")
                client, client_info = self.server_sock.accept()
                with self.lock:
                    self.client_sock = client
                    self.client_address = client_info
                print(f"[BT] Android terhubung: {client_info}")
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
                print("[BT] Koneksi klien Android ditutup.")

    # ================================================================
    # COMMAND HANDLING
    # ================================================================

    def _device_info(self):
        """Info alat dari bccare_main; kosong jika belum dipasang/gagal dibaca."""
        if not self.device_info_provider:
            return {}
        try:
            return self.device_info_provider()
        except Exception as e:
            print(f"[BT] Gagal membaca info perangkat: {e}")
            return {}

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
            except Exception as e:
                print(f"[BT] JSON tidak valid: {e}")
                self.send_error("Format perintah JSON tidak valid.")
                return

        try:
            if cmd_name == "PING":
                self.send_json({
                    "type": "pong",
                    "device": "BC-Care UV-Scan Pro (Raspberry Pi 4)",
                    "status": "ready",
                    "time": time.time(),
                    "info": self._device_info(),
                })

            elif cmd_name == "GET_INFO":
                self.send_json({"type": "device_info", "info": self._device_info()})

            elif cmd_name == "PREPARE_SCAN":
                mode = params.get("mode", "uv")

                if mode not in ("uv", "white"):
                    self.send_error(
                        "Mode tidak valid. Gunakan uv atau white."
                    )
                    return

                if self.on_command_callback:
                    threading.Thread(
                        target=self.on_command_callback,
                        args=("PREPARE_SCAN", params),
                        daemon=True,
                    ).start()
                else:
                    self.send_error("Handler perintah belum tersedia.")

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
                else:
                    self.send_error("Handler perintah belum tersedia.")

            elif cmd_name == "GET_LATEST":
                self.send_latest_saved_result()

            elif cmd_name == "GET_ALL":
                self.send_all_saved_results()

            elif cmd_name.startswith("GET_IMAGE:"):
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
                    self.send_error(
                        f"Gambar tidak ditemukan: {requested}"
                    )

            elif cmd_name == "SHUTDOWN":
                # Matikan Raspberry Pi atas permintaan aplikasi (setara tahan
                # tombol fisik 8 detik). bccare_main yang mengirim
                # 'shutting_down' lalu menjalankan shutdown.
                if self.on_command_callback:
                    threading.Thread(
                        target=self.on_command_callback,
                        args=("SHUTDOWN", params),
                        daemon=True,
                    ).start()
                else:
                    self.send_error("Handler perintah belum tersedia.")

            elif cmd_name == "DISCONNECT":
                self._cleanup_client()

            else:
                self.send_error(
                    f"Perintah tidak dikenal: {cmd_name}"
                )

        except Exception as e:
            print(f"[BT] Gagal memproses perintah {cmd_name}: {e}")
            self.send_error(f"Gagal memproses perintah: {e}")

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
        ultrasonic_data=None, simulated=False, analysis=None
    ):
        """
        Kirim paket hasil klasifikasi lengkap ke Android.
        Gambar dikompresi JPEG lalu di-encode base64 di dalam payload JSON.
        simulated=True → hasil BUKAN dari inferensi model nyata (fallback/simulasi);
        Android menampilkan disclaimer sesuai flag ini.
        analysis → kualitas foto & waktu inferensi (lihat bccare_ml.analisis_citra).
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
            "analysis": analysis or {},
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
        WAJIB sendall(): payload bisa ratusan KB (base64 gambar) dan socket.send()
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
        """Hentikan server Bluetooth dan bersihkan semua resource."""
        self.running = False
        self._cleanup_client()
        if self.profile_server:
            try:
                self.profile_server.stop()
            except Exception:
                pass
            self.profile_server = None
        if self.server_sock:
            try:
                self.server_sock.close()
            except Exception:
                pass
            self.server_sock = None
        print("[BT] Bluetooth server dihentikan.")

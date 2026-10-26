"""
BCcare - Registrasi layanan SPP lewat BlueZ D-Bus (ProfileManager1).

Kenapa modul ini ada:
  - PyBluez gagal dibangun di Python 3.13.
  - /var/run/sdp (flag --compat) sudah deprecated dan bisa hilang saat upgrade bluez.
  Dengan RegisterProfile, BlueZ sendiri membuat record SDP "BCcare" (UUID 1101)
  dan menyerahkan socket RFCOMM yang sudah terhubung lewat NewConnection(fd).
  Tidak perlu root, tidak perlu --compat, tidak perlu reboot.

Kebutuhan (apt): python3-dbus python3-gi
Agent pairing NoInputNoOutput ("Just Works") ikut didaftarkan agar HP bisa
pairing tanpa bluetoothctl terbuka (perangkat headless).
"""

import socket
import threading

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

SPP_UUID = "00001101-0000-1000-8000-00805f9b34fb"
PROFILE_PATH = "/bccare/spp_profile"
AGENT_PATH = "/bccare/agent"
BLUEZ = "org.bluez"


class _Profile(dbus.service.Object):
    def __init__(self, bus, path, on_connection):
        super().__init__(bus, path)
        self._bus = bus
        self._on_connection = on_connection

    @dbus.service.method("org.bluez.Profile1", in_signature="", out_signature="")
    def Release(self):
        print("[BT] Profile dilepas oleh BlueZ.")

    @dbus.service.method("org.bluez.Profile1", in_signature="oha{sv}", out_signature="")
    def NewConnection(self, device, fd, properties):
        # take() = kita ambil kepemilikan fd; socket.socket(fileno=) mendeteksi
        # family/type RFCOMM otomatis dari fd.
        raw_fd = fd.take()
        try:
            sock = socket.socket(fileno=raw_fd)
            sock.setblocking(True)
        except Exception as e:
            print(f"[BT] Gagal membungkus fd RFCOMM: {e}")
            return
        self._mark_trusted(device)
        try:
            self._on_connection(sock, str(device))
        except Exception as e:
            print(f"[BT] on_connection error: {e}")
            try:
                sock.close()
            except Exception:
                pass

    @dbus.service.method("org.bluez.Profile1", in_signature="o", out_signature="")
    def RequestDisconnection(self, device):
        print(f"[BT] BlueZ meminta disconnect: {device}")

    def _mark_trusted(self, device):
        # Agar koneksi berikutnya tidak perlu otorisasi ulang.
        try:
            props = dbus.Interface(
                self._bus.get_object(BLUEZ, device), "org.freedesktop.DBus.Properties")
            props.Set("org.bluez.Device1", "Trusted", dbus.Boolean(True))
        except Exception:
            pass


class _Agent(dbus.service.Object):
    """Agent 'Just Works': terima pairing & otorisasi layanan tanpa input."""

    @dbus.service.method("org.bluez.Agent1", in_signature="", out_signature="")
    def Release(self):
        pass

    @dbus.service.method("org.bluez.Agent1", in_signature="os", out_signature="")
    def AuthorizeService(self, device, uuid):
        print(f"[BT] AuthorizeService {device} {uuid} -> diizinkan")

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="s")
    def RequestPinCode(self, device):
        return "0000"

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="u")
    def RequestPasskey(self, device):
        return dbus.UInt32(0)

    @dbus.service.method("org.bluez.Agent1", in_signature="ouq", out_signature="")
    def DisplayPasskey(self, device, passkey, entered):
        pass

    @dbus.service.method("org.bluez.Agent1", in_signature="os", out_signature="")
    def DisplayPinCode(self, device, pincode):
        pass

    @dbus.service.method("org.bluez.Agent1", in_signature="ou", out_signature="")
    def RequestConfirmation(self, device, passkey):
        print(f"[BT] Pairing {device} (passkey {int(passkey):06d}) -> diterima")

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="")
    def RequestAuthorization(self, device):
        print(f"[BT] RequestAuthorization {device} -> diterima")

    @dbus.service.method("org.bluez.Agent1", in_signature="", out_signature="")
    def Cancel(self):
        pass


class SPPProfileServer:
    """
    Pakai:
        srv = SPPProfileServer(on_connection=func(sock, device_path))
        srv.start()   # raise Exception jika BlueZ/D-Bus tidak tersedia
        srv.stop()
    """

    def __init__(self, on_connection, name="BCcare", channel=1, with_agent=True):
        self.on_connection = on_connection
        self.name = name
        self.channel = channel
        self.with_agent = with_agent
        self._loop = None
        self._thread = None
        self._bus = None
        self._profile = None
        self._agent = None

    def start(self):
        dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
        self._bus = dbus.SystemBus()

        self._profile = _Profile(self._bus, PROFILE_PATH, self.on_connection)
        manager = dbus.Interface(
            self._bus.get_object(BLUEZ, "/org/bluez"), "org.bluez.ProfileManager1")
        opts = {
            "Name": self.name,
            "Role": "server",
            "Channel": dbus.UInt16(self.channel),
            "RequireAuthentication": dbus.Boolean(False),
            "RequireAuthorization": dbus.Boolean(False),
            "AutoConnect": dbus.Boolean(False),
        }
        manager.RegisterProfile(PROFILE_PATH, SPP_UUID, opts)
        print(f"[BT] Profil SPP '{self.name}' terdaftar di BlueZ "
              f"(UUID 1101, channel {self.channel}) via D-Bus.")

        if self.with_agent:
            try:
                self._agent = _Agent(self._bus, AGENT_PATH)
                am = dbus.Interface(
                    self._bus.get_object(BLUEZ, "/org/bluez"), "org.bluez.AgentManager1")
                am.RegisterAgent(AGENT_PATH, "NoInputNoOutput")
                am.RequestDefaultAgent(AGENT_PATH)
                print("[BT] Agent pairing 'Just Works' aktif.")
            except Exception as e:
                print(f"[BT] Agent pairing gagal didaftarkan ({e}) — "
                      f"pairing manual lewat bluetoothctl masih bisa.")

        self._loop = GLib.MainLoop()
        self._thread = threading.Thread(target=self._loop.run, daemon=True)
        self._thread.start()

    def stop(self):
        try:
            if self._bus:
                dbus.Interface(
                    self._bus.get_object(BLUEZ, "/org/bluez"),
                    "org.bluez.ProfileManager1").UnregisterProfile(PROFILE_PATH)
        except Exception:
            pass
        if self._loop:
            self._loop.quit()
            self._loop = None

"""
BCcare - Modul Database SQLite (Penyimpanan Offline)

Dipakai oleh:
  - bccare_main.py  : simpan hasil klasifikasi & ultrasonik
  - bccare_comm.py  : ambil hasil terakhir / semua hasil untuk dikirim ke Android

Skema tabel `events`:
  id               INTEGER PK
  timestamp        REAL     — unix time
  type             TEXT     — 'image' | 'ultrasonic' | 'classification'
  mode             TEXT     — 'uv' | 'white'
  image_path       TEXT     — path absolut file JPEG
  disease          TEXT     — 'NORMAL' | 'BCC'
  confidence       REAL     — 0.0 – 1.0
  probabilities    TEXT     — JSON {"NORMAL": 0.13, "BCC": 0.87}
  jarak_referensi  REAL     — mm (kulit normal)
  jarak_lesi       REAL     — mm (di atas lesi)
  selisih          REAL     — mm (delta ketebalan/elevasi)
  status           TEXT     — deskripsi konsistensi jaringan
"""

import sqlite3
import os
import time
import json

# DB disimpan di ~/bccare_captures (bukan /home/bccare yang mungkin belum
# ada / beda username). Override via env bila perlu.
DB_PATH = os.environ.get(
    "BCCARE_DB_PATH",
    os.path.join(os.path.expanduser("~"), "bccare_captures", "bccare.db"),
)


def _get_connection(db_path=None):
    path = db_path or DB_PATH
    os.makedirs(os.path.dirname(path), exist_ok=True)
    conn = sqlite3.connect(path, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    return conn


def init_db(db_path=None):
    """Buat tabel jika belum ada & jalankan migrasi kolom baru secara otomatis."""
    conn = _get_connection(db_path)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS events (
            id               INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp        REAL    NOT NULL,
            type             TEXT    NOT NULL,
            mode             TEXT,
            image_path       TEXT,
            disease          TEXT,
            confidence       REAL,
            probabilities    TEXT,
            jarak_referensi  REAL,
            jarak_lesi       REAL,
            selisih          REAL,
            status           TEXT
        )
    """)

    # Migrasi: tambahkan kolom yang mungkin belum ada di DB lama
    cur = conn.execute("PRAGMA table_info(events)")
    existing = {row["name"] for row in cur.fetchall()}
    new_cols = {
        "disease":         "TEXT",
        "confidence":      "REAL",
        "probabilities":   "TEXT",
        "jarak_referensi": "REAL",
        "jarak_lesi":      "REAL",
        "selisih":         "REAL",
        "status":          "TEXT",
    }
    for col, col_type in new_cols.items():
        if col not in existing:
            try:
                conn.execute(f"ALTER TABLE events ADD COLUMN {col} {col_type}")
                print(f"[DB] Kolom '{col}' ditambahkan (migrasi).")
            except Exception as e:
                print(f"[DB] Migrasi kolom '{col}': {e}")

    conn.commit()
    conn.close()


# ── Write helpers ────────────────────────────────────────────────────────────

def simpan_capture_gambar(mode: str, image_path: str, db_path=None):
    """Simpan event pengambilan gambar saja (tanpa klasifikasi)."""
    conn = _get_connection(db_path)
    conn.execute(
        "INSERT INTO events (timestamp, type, mode, image_path) VALUES (?, 'image', ?, ?)",
        (time.time(), mode, image_path),
    )
    conn.commit()
    conn.close()


def simpan_hasil_ultrasonik(
    jarak_referensi: float,
    jarak_lesi: float,
    selisih: float,
    status: str,
    db_path=None,
):
    """Simpan hasil pengukuran ultrasonik HC-SR04."""
    conn = _get_connection(db_path)
    conn.execute(
        """INSERT INTO events
               (timestamp, type, jarak_referensi, jarak_lesi, selisih, status)
           VALUES (?, 'ultrasonic', ?, ?, ?, ?)""",
        (time.time(), jarak_referensi, jarak_lesi, selisih, status),
    )
    conn.commit()
    conn.close()


def simpan_hasil_klasifikasi(
    mode: str,
    image_path: str,
    disease: str,
    confidence: float,
    probabilities: dict | None = None,
    ultrasonic_data: dict | None = None,
    db_path=None,
):
    """
    Simpan hasil klasifikasi ML lengkap beserta data ultrasonik.

    Args:
        mode           : 'uv' atau 'white'
        image_path     : path file JPEG
        disease        : 'NORMAL' atau 'BCC'
        confidence     : skor kepercayaan 0.0 – 1.0
        probabilities  : dict {"NORMAL": float, "BCC": float}
        ultrasonic_data: dict dengan key jarak_referensi, jarak_lesi, selisih, status
    """
    u = ultrasonic_data or {}
    prob_str = json.dumps(probabilities or {})

    conn = _get_connection(db_path)
    conn.execute(
        """INSERT INTO events (
               timestamp, type, mode, image_path,
               disease, confidence, probabilities,
               jarak_referensi, jarak_lesi, selisih, status
           ) VALUES (?, 'classification', ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            time.time(),
            mode,
            image_path,
            disease,
            float(confidence),
            prob_str,
            float(u.get("jarak_referensi", 0.0)),
            float(u.get("jarak_lesi", 0.0)),
            float(u.get("selisih", 0.0)),
            str(u.get("status", "")),
        ),
    )
    conn.commit()
    conn.close()


# ── Read helpers ─────────────────────────────────────────────────────────────

def ambil_hasil_terakhir(db_path=None) -> dict | None:
    """
    Ambil satu baris klasifikasi paling mutakhir.
    Mengembalikan dict atau None jika DB kosong.
    """
    conn = _get_connection(db_path)
    cur = conn.execute(
        """SELECT * FROM events
           WHERE type = 'classification'
           ORDER BY timestamp DESC
           LIMIT 1"""
    )
    row = cur.fetchone()
    result = dict(row) if row else None
    conn.close()
    return result


def ambil_semua_hasil(limit: int = 50, db_path=None) -> list[dict]:
    """
    Ambil daftar hasil klasifikasi terbaru, diurutkan dari yang paling baru.
    Hanya mengembalikan event bertipe 'classification'.
    """
    conn = _get_connection(db_path)
    cur = conn.execute(
        """SELECT * FROM events
           WHERE type = 'classification'
           ORDER BY timestamp DESC
           LIMIT ?""",
        (limit,),
    )
    rows = [dict(r) for r in cur.fetchall()]
    conn.close()
    return rows

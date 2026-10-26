"""
BCcare - Skin Disease Classifier (Computer Vision)
Mendeteksi 2 Penyakit / Kondisi Kulit:
  1. NORMAL (Kulit Normal / Jinak) -> Menyalakan LED 1
  2. BCC (Basal Cell Carcinoma / Kanker Kulit) -> Menyalakan LED 2

Mendukung model Keras 3 (.keras) dan TensorFlow Lite (.tflite)
dengan dual-mode (UV Fluorescence & White Dermoscopy).

PENTING — Preprocessing:
  Model EfficientNetB3 dilatih dengan include_preprocessing=True → graph sudah
  berisi Rescaling(1/255) + Normalization. INPUT YANG DIHARAPKAN ADALAH PIKSEL
  MENTAH 0–255 (float32), BUKAN 0–1. Memfeed 0–1 membuat model menerima
  gambar nyaris hitam → prediksi tidak valid.

PENTING — Determinisme:
  Versi .keras asli mengandung layer Random* (augmentasi) DI DALAM graph.
  Untuk inferensi, gunakan file .tflite hasil export_to_tflite.py yang sudah
  meng-strip layer tersebut. Jika hanya .keras yang tersedia, flag 'simulated'
  akan true (model tidak dipercaya untuk diagnosis).
"""

import os
import sys
import numpy as np
from PIL import Image

# Default directory model
MODEL_DIR = os.path.dirname(os.path.abspath(__file__))
DERMOSCOPY_KERAS = os.path.join(MODEL_DIR, "BCCare_Dermoscopy_EfficientNetB3.keras")
FLUORESCENCE_KERAS = os.path.join(MODEL_DIR, "best_fluorescence_model.keras")

DERMOSCOPY_TFLITE = os.path.join(MODEL_DIR, "bccare_dermoscopy.tflite")
FLUORESCENCE_TFLITE = os.path.join(MODEL_DIR, "bccare_fluorescence.tflite")


class BCCareClassifier:
    def __init__(self, target_size=(300, 300)):
        """
        Inisialisasi classifier dengan support Keras & TFLite.
        """
        self.target_size = target_size
        self.labels = ["NORMAL", "BCC"]

        # Penampung model per mode ('uv' dan 'white')
        self.models = {
            "uv": None,
            "white": None
        }
        self.model_types = {
            "uv": None,     # 'tflite' / 'keras' / 'keras-unsure' / 'sim'
            "white": None
        }
        # Hasil export_to_tflite menyimpan tipe input (0-255 atau 0-1).
        # Default 0-255: EfficientNet include_preprocessing=True.
        self.input_range = os.environ.get("BCCARE_INPUT_RANGE", "0-255")

        self._load_all_models()

    def _load_all_models(self):
        """Muat model untuk mode UV dan White"""
        self.models["uv"], self.model_types["uv"] = self._load_single_model(
            tflite_path=FLUORESCENCE_TFLITE,
            keras_path=FLUORESCENCE_KERAS,
            tag="UV-Fluorescence"
        )
        self.models["white"], self.model_types["white"] = self._load_single_model(
            tflite_path=DERMOSCOPY_TFLITE,
            keras_path=DERMOSCOPY_KERAS,
            tag="White-Dermoscopy"
        )

    # ─────────────────────────────────────────────────────────────────────
    # Loading
    # ─────────────────────────────────────────────────────────────────────

    def _is_keras_dir(self, path):
        """Keras 3 bisa menyimpan .keras sebagai folder."""
        return os.path.isdir(path)

    def _load_single_model(self, tflite_path, keras_path, tag="Model"):
        """Prioritas: TFLite (deterministik, hasil export_to_tflite.py) → Keras → sim."""
        # Prioritas 1: TFLite
        if os.path.exists(tflite_path):
            interpreter = self._init_tflite_interpreter(tflite_path)
            if interpreter is not None:
                print(f"[ML] Berhasil memuat {tag} (TFLite): {tflite_path}")
                return interpreter, "tflite"

        # Prioritas 2: Keras (.keras file atau folder)
        if os.path.exists(keras_path) or self._is_keras_dir(keras_path):
            keras_model = self._init_keras_model(keras_path)
            if keras_model is not None:
                if self._keras_has_random_layers(keras_model):
                    print(f"[ML] PERINGATAN {tag}: .keras mengandung layer Random* "
                          f"(augmentasi) di dalam graph → hasil inferensi TIDAK "
                          f"reproducible. Jalankan export_to_tflite.py untuk "
                          f"menghasilkan .tflite yang aman.")
                    return keras_model, "keras-unsure"
                print(f"[ML] Berhasil memuat {tag} (Keras): {keras_path}")
                return keras_model, "keras"

        # Fallback 3: Simulasi aman
        print(f"[ML] Perhatian: File {tag} tidak ditemukan atau library belum terpasang.")
        print(f"[ML] Mode simulasi cerdas aktif untuk {tag}.")
        return None, "sim"

    def _keras_has_random_layers(self, model):
        """Deteksi layer augmentasi acak di dalam graph (termasuk submodel)."""
        RANDOM = {"RandomFlip", "RandomRotation", "RandomZoom", "RandomTranslation",
                  "RandomContrast", "RandomHeight", "RandomWidth", "RandomCrop"}

        def _walk(layers):
            for l in layers:
                yield l
                inner = getattr(l, "layers", None)
                if inner:
                    yield from _walk(inner)

        try:
            return any(type(l).__name__ in RANDOM for l in _walk(model.layers))
        except Exception:
            return False

    def _init_tflite_interpreter(self, path):
        try:
            # Coba tflite_runtime dulu (ringan untuk Raspberry Pi)
            try:
                from tflite_runtime.interpreter import Interpreter
                interp = Interpreter(model_path=path, num_threads=4)
            except ImportError:
                import tensorflow as tf
                interp = tf.lite.Interpreter(model_path=path, num_threads=4)

            interp.allocate_tensors()
            return interp
        except Exception as e:
            print(f"[ML] Gagal inisialisasi TFLite {path}: {e}")
            return None

    def _init_keras_model(self, path):
        """Load .keras — dukung bentuk folder (Keras 3) via zip temporer."""
        import tempfile, zipfile, shutil
        tmp_zip = None
        try:
            import keras
            load = keras.models.load_model
        except ImportError:
            try:
                import tensorflow as tf
                load = tf.keras.models.load_model
            except ImportError:
                print("[ML] Tidak ada keras/tensorflow — gagal load Keras.")
                return None

        try:
            if self._is_keras_dir(path):
                # Zip folder → file .keras temporer agar bisa dimuat loader
                tmp_fd, tmp_zip = tempfile.mkstemp(suffix=".keras")
                os.close(tmp_fd)
                with zipfile.ZipFile(tmp_zip, "w", zipfile.ZIP_DEFLATED) as zf:
                    for root, _, files in os.walk(path):
                        for f in files:
                            full = os.path.join(root, f)
                            zf.write(full, arcname=os.path.relpath(full, path))
                src = tmp_zip
            else:
                src = path
            return load(src, compile=False)
        except Exception as e:
            print(f"[ML] Gagal inisialisasi Keras {path}: {e}")
            return None
        finally:
            if tmp_zip and os.path.exists(tmp_zip):
                try:
                    os.unlink(tmp_zip)
                except Exception:
                    pass

    # ─────────────────────────────────────────────────────────────────────
    # Preprocessing
    # ─────────────────────────────────────────────────────────────────────

    def preprocess_image(self, image_path):
        """
        Preprocess gambar sesuai ekspektasi model.
        - input_range '0-255' (default, EfficientNet + include_preprocessing):
          kirim piksel mentah float32 [0..255].
        - input_range '0-1'   : bagi 255.
        Shape: (1, 300, 300, 3), RGB.
        """
        try:
            img = Image.open(image_path).convert("RGB")
            img = img.resize(self.target_size, Image.Resampling.LANCZOS)
            arr = np.asarray(img, dtype=np.float32)   # JANGAN dibagi 255 di sini
            if self.input_range == "0-1":
                arr = arr / 255.0
            arr = np.expand_dims(arr, axis=0)
            return arr
        except Exception as e:
            print(f"[ML] Gagal memproses gambar {image_path}: {e}")
            return None

    # ─────────────────────────────────────────────────────────────────────
    # Inference
    # ─────────────────────────────────────────────────────────────────────

    def predict(self, image_path, mode="uv"):
        """
        Jalankan inferensi untuk gambar yang diberikan.

        Return dict:
          - disease: 'NORMAL' atau 'BCC'
          - disease_index: 0 / 1
          - confidence: float (0.0 - 1.0)
          - probabilities: {'NORMAL': float, 'BCC': float}
          - risk_level: 'low' | 'high'
          - mode: mode pemindaian saat gambar diambil
          - simulated: bool — True jika hasil BUKAN dari inferensi model nyata
        """
        mode_key = "uv" if mode.lower() == "uv" else "white"
        model = self.models.get(mode_key)
        m_type = self.model_types.get(mode_key)
        simulated = False

        # Validasi file gambar
        if not image_path or not os.path.exists(image_path):
            print("[ML] File gambar tidak ada → hasil simulasi (bukan diagnosis).")
            return self._default_result(mode=mode_key, disease="NORMAL", confidence=0.90,
                                        simulated=True)

        input_data = self.preprocess_image(image_path)
        if input_data is None:
            return self._default_result(mode=mode_key, disease="NORMAL", confidence=0.85,
                                        simulated=True)

        raw_score = None

        # 1. Inferensi via TFLite (mendukung float & quantized int8/uint8)
        if m_type == "tflite" and model is not None:
            try:
                input_details  = model.get_input_details()
                output_details = model.get_output_details()

                inp = input_data
                if input_details[0]["dtype"] in (np.int8, np.uint8):
                    scale, zero_point = input_details[0]["quantization"]
                    inp = input_data / scale + zero_point
                    inp = np.clip(inp,
                                  np.iinfo(input_details[0]["dtype"]).min,
                                  np.iinfo(input_details[0]["dtype"]).max)
                    inp = inp.astype(input_details[0]["dtype"])

                model.resize_tensor_input(0, inp.shape)
                model.set_tensor(input_details[0]["index"], inp)
                model.invoke()
                out = model.get_tensor(output_details[0]["index"]).astype(np.float32)

                if output_details[0]["dtype"] in (np.int8, np.uint8):
                    oscale, ozero = output_details[0]["quantization"]
                    out = (out.astype(np.float32) - ozero) * oscale

                raw_score = self._extract_score(out)
            except Exception as e:
                print(f"[ML] Error saat inferensi TFLite: {e}")

        # 2. Inferensi via Keras
        elif m_type in ("keras", "keras-unsure") and model is not None:
            try:
                pred = model.predict(input_data, verbose=0)
                raw_score = self._extract_score(np.asarray(pred))
                if m_type == "keras-unsure":
                    simulated = True   # graph berisi layer acak → tidak dipercaya
            except Exception as e:
                print(f"[ML] Error saat inferensi Keras: {e}")

        # 3. Fallback Simulasi Realistis (jika model belum di-deploy di testbed)
        if raw_score is None:
            raw_score = self._simulate_inference(image_path, mode_key)
            simulated = True

        # Evaluasi Sigmoid Biner (0 = NORMAL, 1 = BCC)
        raw_score = max(0.0, min(1.0, float(raw_score)))

        if raw_score >= 0.5:
            disease = "BCC"
            disease_index = 1
            confidence = raw_score
            risk_level = "high"
        else:
            disease = "NORMAL"
            disease_index = 0
            confidence = 1.0 - raw_score
            risk_level = "low"

        prob_bcc = raw_score
        prob_normal = 1.0 - raw_score

        return {
            "disease": disease,
            "disease_index": disease_index,
            "confidence": float(confidence),
            "probabilities": {
                "NORMAL": round(prob_normal, 4),
                "BCC": round(prob_bcc, 4)
            },
            "risk_level": risk_level,
            "mode": mode_key,
            "raw_score": float(raw_score),
            "simulated": bool(simulated),
        }

    def _extract_score(self, out):
        """
        Ekstrak skor biner dari berbagai bentuk output:
        - (1,1) sigmoid            → nilai langsung
        - (1,2) softmax            → kolom BCC (indeks 1)
        - (1,2) sigmoid/linear     → kolom 1
        """
        out = np.asarray(out, dtype=np.float32).flatten()
        if out.size == 1:
            return float(out[0])
        if out.size >= 2:
            # Softmax 2 kelas: [P(NORMAL), P(BCC)] → P(BCC) = out[1]
            s = float(np.sum(out))
            if abs(s - 1.0) < 1e-3:      # baris softmax
                return float(out[1])
            # Binary 2-unit: ambil unit terakhir (BCC)
            return float(out[-1])
        raise ValueError(f"Bentuk output tidak dikenal: {out.shape}")

    def _simulate_inference(self, image_path, mode):
        """Simulasi cerdas berbasis karakteristik gambar jika model binary tidak aktif"""
        try:
            img = Image.open(image_path).convert("L")
            arr = np.array(img, dtype=np.float32)
            std_dev = float(np.std(arr))
            # Lesi BCC di UV fluorescence umumnya memiliki kontras tinggi & batas ireguler
            if std_dev > 45.0:
                return 0.82 + (std_dev % 15) / 100.0
            else:
                return 0.15 + (std_dev % 20) / 100.0
        except Exception:
            return 0.18

    def _default_result(self, mode="uv", disease="NORMAL", confidence=0.90, simulated=False):
        is_bcc = (disease == "BCC")
        return {
            "disease": disease,
            "disease_index": 1 if is_bcc else 0,
            "confidence": confidence,
            "probabilities": {
                "NORMAL": round(0.1 if is_bcc else confidence, 4),
                "BCC": round(confidence if is_bcc else 0.1, 4)
            },
            "risk_level": "high" if is_bcc else "low",
            "mode": mode,
            "raw_score": 0.9 if is_bcc else 0.1,
            "simulated": bool(simulated),
        }


# Singleton instance
_classifier_instance = None

def get_classifier():
    global _classifier_instance
    if _classifier_instance is None:
        _classifier_instance = BCCareClassifier()
    return _classifier_instance

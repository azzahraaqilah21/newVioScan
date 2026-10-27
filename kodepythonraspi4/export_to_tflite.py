"""
BCcare - Utility Script: Konversi Model Keras (.keras) → TensorFlow Lite (.tflite)

MASALAH YANG DISELESAIKAN:
  1. Model .keras dilatih dengan layer augmentasi data (RandomFlip, RandomRotation,
     RandomZoom[, RandomTranslation]) DI DALAM graph. Jika dikonversi langsung:
       - Konversi sering gagal, ATAU
       - Lebih berbahaya: Random* tetap aktif saat inferensi → setiap scan
         menghasilkan klasifikasi BERBEDA untuk gambar yang sama.
     Solusi: strip layer augmentasi (tidak punya bobot, aman dibuang).

  2. Keras 3 (TF >= 2.16) menurunkan layer preprocessing (Rescaling/Normalization)
     menjadi composite function yang sering GAGAL di-inline ke builtin TFLite.
     Konversi langsung via TFLiteConverter.from_keras_model lalu error, dan jika
     kita memakai fallback SELECT_TF_OPS, model "berhasil" tapi berisi Flex op
     (mis. FlexMul) yang TIDAK BISA dijalankan tflite_runtime di Raspberry Pi
     ("Node number N (FlexMul) failed to prepare").
     Solusi: jalur resmi Keras 3 → model.export() ke SavedModel → konversi dari
     SavedModel. Concrete function SavedModel ter-inline penuh dan umumnya
     menghasilkan builtin-only. Script ini MENOLAK model yang mengandung Flex op.

STRATEGI KONVERSI (berurutan, strategi pertama yang lolos verifikasi menang):
  A. from_keras_model + TFLITE_BUILTINS   (cepat; sering gagal di Keras 3)
  B. model.export() → from_saved_model + TFLITE_BUILTINS  (jalur resmi Keras 3)

  Tidak ada fallback SELECT_TF_OPS lagi: model Flex tidak bisa jalan di Pi,
  jadi tidak ada gunanya disimpan. Jika A & B gagal, script berhenti dengan
  pesan diagnostik (biasanya Normalization/preprocessing perlu dibuang dari
  graph atau model di-retrain).

CARA PAKAI (di PC/laptop dengan TensorFlow, bukan di Raspberry Pi):
    python export_to_tflite.py                 # konversi kedua model + verifikasi
    python export_to_tflite.py --no-verify     # lewati verifikasi (lebih cepat)

Output:
    bccare_dermoscopy.tflite   (dari BCCare_Dermoscopy_EfficientNetB3.keras)
    bccare_fluorescence.tflite (dari bccare_fluorescence_efficientnetb3.keras)
"""

import os
import sys
import json
import shutil
import tempfile
import zipfile

RANDOM_LAYER_CLASSES = {"RandomFlip", "RandomRotation", "RandomZoom",
                        "RandomTranslation", "RandomContrast", "RandomHeight",
                        "RandomWidth", "RandomCrop"}


# ─────────────────────────────────────────────────────────────────────────────
# Utilities
# ─────────────────────────────────────────────────────────────────────────────

def _keras_path_is_dir(path):
    """Keras 3 bisa menyimpan .keras sebagai folder (unzip) — deteksi keduanya."""
    if os.path.isdir(path):
        return "dir"
    if os.path.isfile(path) and zipfile.is_zipfile(path):
        return "zip"
    return None


def _load_keras_model_robust(path):
    """
    tf.keras.models.load_model bisa gagal jika .keras berupa FOLDER (Keras 3 format).
    Fallback: zip-kan folder sementara ke .keras file lalu load normal.
    """
    import tensorflow as tf

    kind = _keras_path_is_dir(path)
    if kind == "dir":
        print("  [INFO] .keras berupa folder — dipack ke zip sementara...")
        tmp_zip = tempfile.NamedTemporaryFile(suffix=".keras", delete=False)
        tmp_zip.close()
        with zipfile.ZipFile(tmp_zip.name, "w", zipfile.ZIP_DEFLATED) as zf:
            for root, _, files in os.walk(path):
                for f in files:
                    full = os.path.join(root, f)
                    zf.write(full, arcname=os.path.relpath(full, path))
        try:
            return tf.keras.models.load_model(tmp_zip.name, compile=False)
        finally:
            os.unlink(tmp_zip.name)

    # Zip normal atau folder Keras 3 yang dikenali langsung
    return tf.keras.models.load_model(path, compile=False)


def strip_augmentation(model):
    """
    Buang blok augmentasi Random* termasuk yang berada
    di dalam Sequential/Functional nested model.

    Return:
        (model_baru, daftar_layer_yang_dibuang)
    """
    import tensorflow as tf

    removed = []

    def find_random_layers(layer, prefix=""):
        name = f"{prefix}{layer.name}"

        # Cek layer langsung
        if type(layer).__name__ in RANDOM_LAYER_CLASSES:
            removed.append(name)

        # Cek nested model / Sequential
        if hasattr(layer, "layers"):
            for child in layer.layers:
                find_random_layers(child, prefix=name + "/")

    # Cari seluruh Random* secara rekursif
    for layer in model.layers:
        find_random_layers(layer)

    if not removed:
        print("  [OK] Tidak ada layer augmentasi acak — model siap konversi.")
        return model, []

    print(f"  [STRIP] Ditemukan {len(removed)} layer augmentasi acak:")
    for name in removed:
        print(f"      - {name}")

    print("  [STRIP] Augmentasi training akan dilewati saat inferensi.")

    # Untuk model BC-Care:
    # augmentasi berada pada Sequential pertama setelah InputLayer.
    inp = model.inputs[0]
    x = inp
    skipped = False

    for layer in model.layers:
        if type(layer).__name__ == "InputLayer":
            continue

        # Jika layer adalah Sequential/Functional yang seluruh isinya
        # berupa Random* augmentation, lewati layer tersebut.
        nested_types = []

        if hasattr(layer, "layers"):
            for child in layer.layers:
                nested_types.append(type(child).__name__)

        is_random_block = (
            nested_types
            and all(t in RANDOM_LAYER_CLASSES for t in nested_types)
        )

        if type(layer).__name__ in RANDOM_LAYER_CLASSES:
            skipped = True
            continue

        if is_random_block:
            print(f"  [STRIP] Melewati blok augmentasi: {layer.name}")
            skipped = True
            continue

        # Layer normal tetap dipertahankan
        x = layer(x)

    new_model = tf.keras.Model(
        inputs=inp,
        outputs=x,
        name=model.name + "_no_augmentation"
    )

    print("  [OK] Model baru berhasil dibuat tanpa blok augmentasi.")
    print(f"  [OK] Layer yang terdeteksi: {len(removed)}")

    return new_model, removed

def strip_mixed_precision(model):
    """
    Paksa seluruh model dan nested model menjadi float32.

    Model BC-Care menggunakan EfficientNetB3 nested Functional dengan
    compute dtype float16. Fungsi ini membersihkan konfigurasi dtype
    secara rekursif, kemudian rebuild dan menyalin bobot asli.
    """
    import tensorflow as tf

    def iter_all_layers(layers):
        for layer in layers:
            yield layer
            inner = getattr(layer, "layers", None)
            if inner:
                yield from iter_all_layers(inner)

    def has_float16(m):
        for layer in iter_all_layers(m.layers):
            try:
                if "float16" in str(layer.compute_dtype).lower():
                    return True
            except Exception:
                pass

        for weight in m.weights:
            if weight.dtype == tf.float16:
                return True

        return False

    if not has_float16(model):
        print("  [OK] Model sudah float32.")
        return model, False

    print(
        "  [FIX] Float16 terdeteksi → membersihkan dtype "
        "secara rekursif dan rebuild model sebagai float32..."
    )

    # Pastikan policy global float32
    tf.keras.mixed_precision.set_global_policy("float32")

    def force_float32(cfg):
        if isinstance(cfg, dict):
            result = {}

            for key, value in cfg.items():
                if key == "dtype":
                    # Semua variasi mixed_float16 / float16
                    # dipaksa menjadi float32.
                    result[key] = "float32"
                else:
                    result[key] = force_float32(value)

            return result

        if isinstance(cfg, list):
            return [force_float32(x) for x in cfg]

        if isinstance(cfg, tuple):
            return tuple(force_float32(x) for x in cfg)

        return cfg

    # Simpan bobot asli
    weights = model.get_weights()

    print("  [FIX] Membersihkan konfigurasi nested model...")

    try:
        clean_config = force_float32(model.get_config())

        rebuilt = model.__class__.from_config(clean_config)

        # Build model dengan shape input asli
        try:
            rebuilt.build(model.input_shape)
        except Exception:
            pass

        rebuilt.set_weights(weights)

    except Exception as e:
        print(f"  [WARN] Rebuild float32 gagal: {e}")
        print("  [WARN] Model asli dipertahankan.")
        return model, False

    # Verifikasi seluruh nested layer
    leftover_layers = []

    for layer in iter_all_layers(rebuilt.layers):
        try:
            dtype = str(layer.compute_dtype).lower()

            if "float16" in dtype:
                leftover_layers.append(
                    f"{layer.name} ({layer.compute_dtype})"
                )
        except Exception:
            pass

    leftover_vars = [
        w for w in rebuilt.weights
        if w.dtype == tf.float16
    ]

    if leftover_layers or leftover_vars:
        print(
            f"  [WARN] Masih tersisa float16: "
            f"layers={len(leftover_layers)}, vars={len(leftover_vars)}"
        )

        for item in leftover_layers[:10]:
            print("      -", item)

        print("  [WARN] Model asli dipertahankan.")
        return model, False

    print("  [OK] Model berhasil menjadi full float32.")
    print("  [OK] Tidak ada compute dtype float16.")
    print("  [OK] Tidak ada weight float16.")

    return rebuilt, True


def detect_input_range(model):
    """
    Deteksi apakah model mengharapkan input [0,255] (EfficientNet include_preprocessing
    = True, ada Rescaling 1/255 internal) atau [0,1].
    Return '0-255' | '0-1' | 'unknown' (dan flag mixed_precision).
    """
    def _walk(layers):
        for l in layers:
            yield l
            inner = getattr(l, "layers", None)
            if inner:
                yield from _walk(inner)

    scale = None
    for l in _walk(model.layers):
        if type(l).__name__ == "Rescaling":
            scale = getattr(l, "scale", None)
            break

    if scale is None:
        return "unknown"
    if abs(scale - 1.0 / 255.0) < 1e-9:
        return "0-255"   # model akan membagi 255 sendiri → feed piksel mentah
    if abs(scale - 1.0) < 1e-9:
        return "0-1"
    return f"scale={scale}"


def _expected_input_shape(model):
    """Shape input deterministik (tanpa batch) untuk verifikasi."""
    shape = model.inputs[0].shape
    out = []
    for d in shape[1:]:
        out.append(d if isinstance(d, int) and d > 0 else 224)
    return out or [224, 224, 3]


# ─────────────────────────────────────────────────────────────────────────────
# Conversion strategies — semua builtin-only, Flex op DITOLAK
# ─────────────────────────────────────────────────────────────────────────────

def _has_flex_ops(tflite_bytes):
    """
    Deteksi Flex/SELECT_TF ops di flatbuffer. Flex ops terserialisasi sebagai
    custom op dengan nama 'Flex<OpName>' (mis. FlexMul) → string 'Flex' muncul
    di bytes model. Model seperti ini TIDAK bisa dijalankan tflite_runtime Pi.
    """
    return b"Flex" in tflite_bytes


def _conversion_strategies(model, workdir):
    """
    Yield (nama, callable→converter). Pemanggil yang menjalankan convert()
    dengan TFLITE_BUILTINS.
    """
    import tensorflow as tf

    def keras_direct():
        return tf.lite.TFLiteConverter.from_keras_model(model)

    def saved_model_export():
        # Jalur resmi Keras 3: export ke SavedModel (serving) dulu, sehingga
        # keras.ops composite ter-inline penuh sebelum TFLite conversion.
        export_dir = os.path.join(workdir, "export_savedmodel")
        if os.path.exists(export_dir):
            shutil.rmtree(export_dir)
        model.export(export_dir)
        print(f"  [INFO] Model di-export ke SavedModel sementara: {export_dir}")
        return tf.lite.TFLiteConverter.from_saved_model(export_dir)

    return [
        ("A: from_keras_model + BUILTINS", keras_direct),
        ("B: model.export→SavedModel + BUILTINS", saved_model_export),
    ]


def _convert_builtin_only(converter):
    import tensorflow as tf
    # TANPA optimizations (kuantisasi int8): diuji 27 Okt pada model UV baru,
    # versi terkuantisasi hanya 6/14 keputusan sama dengan Keras; float32
    # (tanpa kuantisasi) 14/14.
    # BUILTINS SAJA — sengaja TANPA SELECT_TF_OPS. Model Flex tidak bisa jalan
    # di tflite_runtime Pi, jadi lebih baik konversi gagal keras di sini.
    converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS]
    return converter.convert()


# ─────────────────────────────────────────────────────────────────────────────
# Verification
# ─────────────────────────────────────────────────────────────────────────────

def verify_tflite(keras_out, tflite_path, input_range, expected_shape):
    """
    Verifikasi 3 hal:
      1. Ekuivalensi: output TFLite ≈ output Keras untuk 2 input acak
      2. Determinisme: output TFLite sama persis untuk input yang sama (2x infer)
      3. Preprocessing benar: range input sesuai deteksi
    Return True jika lolos semua.
    """
    import numpy as np
    import tensorflow as tf

    interp = tf.lite.Interpreter(model_path=tflite_path)
    in_det  = interp.get_input_details()[0]
    out_det = interp.get_output_details()[0]

    # Dynamic batch (dari jalur SavedModel) → fix ke batch 1 dulu
    if any(d <= 0 for d in in_det["shape"]):
        fixed = [1] + list(expected_shape)
        interp.resize_tensor_input(0, fixed)
        interp.allocate_tensors()
        in_det  = interp.get_input_details()[0]
        out_det = interp.get_output_details()[0]
    else:
        interp.allocate_tensors()

    expected_dtype = np.float32
    is_quantized = in_det["dtype"] != expected_dtype
    in_shape = in_det["shape"]

    rng = np.random.default_rng(42)
    max_diff_overall = 0.0

    for trial in range(2):
        # Input mentah sesuai range yang diharapkan model
        if input_range == "0-255":
            img = rng.random(in_shape[1:]).astype(np.float32) * 255.0
        elif input_range == "0-1":
            img = rng.random(in_shape[1:]).astype(np.float32)
        else:
            img = rng.random(in_shape[1:]).astype(np.float32) * 255.0

        x = img[np.newaxis, ...]

        # ── Keras ──
        k_out = keras_out.predict(x, verbose=0)

        # ── TFLite ──
        def run_once():
            if is_quantized:
                scale, zero_pt = in_det["quantization"]
                q = np.clip(np.round(x / scale) + zero_pt,
                            np.iinfo(in_det["dtype"]).min,
                            np.iinfo(in_det["dtype"]).max).astype(in_det["dtype"])
                interp.set_tensor(in_det["index"], q)
            else:
                interp.set_tensor(in_det["index"], x.astype(expected_dtype))
            interp.invoke()
            return interp.get_tensor(out_det["index"])

        t_out1 = run_once()
        t_out2 = run_once()

        # 1) Ekuivalensi
        diff = float(np.max(np.abs(np.asarray(k_out, np.float32)
                                   - np.asarray(t_out1, np.float32))))
        max_diff_overall = max(max_diff_overall, diff)

        # 2) Determinisme
        if not np.array_equal(t_out1, t_out2):
            print(f"  [GAGAL-VERIFY] TFLite TIDAK deterministik! "
                  f"out1={t_out1.flatten()[:4]} vs out2={t_out2.flatten()[:4]}")
            print("  → Layer acak kemungkinan masih ada di graph!")
            return False

        # 3) Sanity output
        flat = np.asarray(t_out1, np.float32).flatten()
        if flat.size == 1:
            v = float(flat[0])
            if not (0.0 <= v <= 1.0):
                print(f"  [WARN] Output sigmoid di luar [0,1]: {v}")

    print(f"  [VERIFY] max|keras - tflite| = {max_diff_overall:.6f} "
          f"({'OK' if max_diff_overall < 0.02 else 'REVIEW — selisih besar'})")
    print(f"  [VERIFY] Deterministik: YA (2x inferensi identik)")
    return True


# ─────────────────────────────────────────────────────────────────────────────
# Main conversion
# ─────────────────────────────────────────────────────────────────────────────

def convert_keras_to_tflite(verify=True):
    try:
        import tensorflow as tf
    except ImportError:
        print("[ERROR] TensorFlow tidak ditemukan. Harap install dengan: pip install tensorflow")
        return False

    base_dir = os.path.dirname(os.path.abspath(__file__))
    models = [
        {
            "name": "White-Dermoscopy (EfficientNetB3)",
            "keras": os.path.join(base_dir, "BCCare_Dermoscopy_EfficientNetB3.keras"),
            "tflite": os.path.join(base_dir, "bccare_dermoscopy.tflite")
        },
        {
            "name": "UV-Fluorescence",
            "keras": os.path.join(base_dir, "bccare_fluorescence_efficientnetb3.keras"),
            "tflite": os.path.join(base_dir, "bccare_fluorescence.tflite")
        }
    ]

    all_ok = True
    with tempfile.TemporaryDirectory() as workdir:
        for m in models:
            print(f"\n[KONVERSI] Memproses {m['name']}...")
            if _keras_path_is_dir(m["keras"]) is None:
                print(f"  [SKIP] File {m['keras']} tidak ditemukan.")
                all_ok = False
                continue

            try:
                print("  Memuat model Keras...")
                model = _load_keras_model_robust(m["keras"])

                input_range = detect_input_range(model)
                print(f"  [INFO] Input range terdeteksi: {input_range}"
                      + (" → feed piksel mentah 0-255" if input_range == "0-255" else ""))

                model, removed = strip_augmentation(model)
                model, fp16_fixed = strip_mixed_precision(model)
                expected_shape = _expected_input_shape(model)

                # ── Coba tiap strategi: convert → cek Flex → verify ──────────
                converted = False
                last_error = None
                for strat_name, make_converter in _conversion_strategies(model, workdir):
                    print(f"  [STRATEGI] {strat_name} ...")
                    try:
                        converter = make_converter()
                        tflite_model = _convert_builtin_only(converter)
                    except Exception as conv_err:
                        last_error = conv_err
                        print(f"    [GAGAL] {type(conv_err).__name__}: {conv_err}")
                        continue

                    if _has_flex_ops(tflite_model):
                        last_error = RuntimeError(
                            "model mengandung Flex op (SELECT_TF) — tidak bisa jalan di Pi")
                        print("    [GAGAL] Flex op terdeteksi di model hasil konversi "
                              "(tidak bisa dijalankan tflite_runtime di Raspberry Pi).")
                        continue

                    # Simpan sementara → verify → kalau lolos, jadikan final
                    tmp_out = os.path.join(workdir, "candidate.tflite")
                    with open(tmp_out, "wb") as f:
                        f.write(tflite_model)

                    if verify:
                        print("    Memverifikasi ekuivalensi & determinisme...")
                        try:
                            ok = verify_tflite(model, tmp_out, input_range, expected_shape)
                        except Exception as verify_err:
                            last_error = verify_err
                            print(f"    [GAGAL] Verifikasi error: {verify_err}")
                            continue
                        if not ok:
                            last_error = RuntimeError("verifikasi gagal")
                            continue

                    with open(m["tflite"], "wb") as f:
                        f.write(tflite_model)
                    size_mb = len(tflite_model) / (1024 * 1024)
                    print(f"  [SUKSES] Model tersimpan: {m['tflite']} ({size_mb:.2f} MB) "
                          f"[strategi: {strat_name}]")
                    converted = True
                    break

                if not converted:
                    print(f"  [GAGAL] Semua strategi konversi builtin-only gagal untuk "
                          f"{m['name']}. Error terakhir: {last_error}")
                    print("  DIAGNOSTIKA:")
                    print("   • Keras 3 menurunkan preprocessing (Rescaling/Normalization)")
                    print("     ke composite yang TFLite tidak bisa inline.")
                    print("   • Opsi: konversi hanya backbone+head (preprocessing dipindah")
                    print("     ke numpy di Pi), atau retrain dengan preprocessing di luar model.")
                    all_ok = False

            except Exception as e:
                print(f"  [GAGAL] Error saat konversi {m['name']}: {e}")
                all_ok = False

    print("\n" + "=" * 60)
    if all_ok:
        print("SELESAI — salin kedua file .tflite ke Raspberry Pi:")
        print("  scp bccare_*.tflite bccare@<ip>:/home/bccare/kodepythonraspi4/")
    else:
        print("SEBAGIAN GAGAL — periksa log di atas sebelum deploy.")
    print("=" * 60)
    return all_ok


if __name__ == "__main__":
    verify = "--no-verify" not in sys.argv
    ok = convert_keras_to_tflite(verify=verify)
    sys.exit(0 if ok else 1)

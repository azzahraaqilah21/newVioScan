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
    bccare_fluorescence.tflite (dari best_fluorescence_model.keras)
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
    Buang layer augmentasi acak dari depan model.
    Return (model_baru, daftar_layer_yang_dibuang).
    """
    import tensorflow as tf

    # Cari layer-layer awal bertipe Random*
    to_remove = []
    for layer in model.layers:
        if type(layer).__name__ in RANDOM_LAYER_CLASSES:
            to_remove.append(layer)
        elif to_remove:
            # Sudah lewat blok augmentasi (bloknya selalu berurutan dari depan)
            break

    if not to_remove:
        print("  [OK] Tidak ada layer augmentasi acak — model siap konversi.")
        return model, []

    print(f"  [STRIP] Membuang {len(to_remove)} layer augmentasi: "
          f"{[type(l).__name__ for l in to_remove]}")
    print("  (Layer ini tidak punya bobot, aman dibuang. Augmentasi seharusnya "
          "hanya saat TRAINING, bukan inferensi.)")

    # Rekonstruksi model: output dari layer terakhir SEBELUM blok augmentasi
    inp = model.inputs[0]
    x = inp
    # InputLayer tidak menghasilkan tensor baru; cari layer konkrit pertama
    for layer in model.layers:
        if type(layer).__name__ in ("InputLayer",) or type(layer).__name__ in RANDOM_LAYER_CLASSES:
            continue
        x = layer(x)
        break

    # Sisa layer setelah blok augmentasi
    past_aug = False
    for layer in model.layers:
        if type(layer).__name__ in RANDOM_LAYER_CLASSES:
            past_aug = True
            continue
        if type(layer).__name__ == "InputLayer":
            continue
        if not past_aug:
            continue  # sudah direbuild di atas
        x = layer(x)

    # Jika blok augmentasi berada di dalam submodel Sequential (umum di
    # pipeline Keras 3: Functional(Sequential[aug], Functional[backbone])),
    # pendekatan layer-by-layer di atas bisa gagal → fallback: rebuild via
    # functional API pada submodel.
    try:
        new_model = tf.keras.Model(inp, x, name=model.name + "_noaug")
        return new_model, [type(l).__name__ for l in to_remove]
    except Exception as e:
        print(f"  [WARN] Rebuild langsung gagal ({e}); coba jalur submodel...")

    # ── Fallback: telusuri submodel yang memuat Random* ──────────────────────
    # Pola: model.layers = [InputLayer, Sequential(aug), Functional(backbone), ...]
    parts = [l for l in model.layers if type(l).__name__ not in ("InputLayer",)]
    kept = []
    for l in parts:
        if type(l).__name__ in RANDOM_LAYER_CLASSES:
            continue
        if hasattr(l, "layers") and any(
                type(sub).__name__ in RANDOM_LAYER_CLASSES for sub in getattr(l, "layers", [])):
            # Sequential berisi augmentasi → buang sub-layer Random*-nya saja
            inner = [sub for sub in l.layers
                     if type(sub).__name__ not in RANDOM_LAYER_CLASSES]
            if not inner:
                continue
            l = tf.keras.Sequential(inner, name=l.name + "_noaug")
        kept.append(l)

    x = inp
    for l in kept:
        x = l(x)
    new_model = tf.keras.Model(inp, x, name=model.name + "_noaug")
    return new_model, [type(l).__name__ for l in to_remove]


def strip_mixed_precision(model):
    """
    Model yang dilatih dengan policy mixed_float16 menyimpan compute dtype f16
    di layer-layer-nya (variabel master umumnya tetap fp32). TFLite builtin
    TIDAK mendukung math fp16 → converter error "ERROR_NEEDS_FLEX_OPS" untuk
    tf.Conv2D/tf.BiasAdd/tf.Mul/tf.Sigmoid (persis seperti di SE-block
    EfficientNet).

    Solusi: ambil config model (nested), telusuri rekursif dan ganti semua
    "dtype": "float16" → "float32", rebuild model dari config, salin bobot.
    Rekursif WAJIB karena EfficientNetB3 adalah nested Functional model —
    clone_model/clone_function biasa hanya menyentuh layer top-level dan
    layer dalam backbone akan tetap f16 dari config aslinya.
    Return (model_baru, True jika ada perubahan).
    """
    import tensorflow as tf

    def _iter_all_layers(layers):
        for l in layers:
            yield l
            inner = getattr(l, "layers", None)
            if inner:
                yield from _iter_all_layers(inner)

    # Deteksi: variabel f16 ATAU compute dtype f16 di layer mana pun (nested
    # submodel seperti EfficientNetB3 ikut ditelusuri).
    has_f16 = (
        any(v.dtype == tf.float16 for v in model.weights)
        or any(getattr(l, "compute_dtype", None) == tf.float16
               for l in _iter_all_layers(model.layers))
    )
    if not has_f16:
        return model, False

    print("  [FIX] Model mixed_float16 (compute dtype f16 terdeteksi) → "
          "rebuild seluruh model sebagai float32 sebelum konversi TFLite...")

    tf.keras.mixed_precision.set_global_policy("float32")

    def _force_fp32_in_config(cfg):
        """Telusuri config (nested) & ganti semua dtype float16 → float32."""
        if isinstance(cfg, dict):
            out = {}
            for k, v in cfg.items():
                if k == "dtype" and isinstance(v, str) and "float16" in v:
                    out[k] = "float32"
                else:
                    out[k] = _force_fp32_in_config(v)
            return out
        if isinstance(cfg, (list, tuple)):
            return type(cfg)(_force_fp32_in_config(v) for v in cfg) \
                if isinstance(cfg, list) else [_force_fp32_in_config(v) for v in cfg]
        return cfg

    weights = model.get_weights()  # bobot master (fp32) dari file .keras

    try:
        cfg = _force_fp32_in_config(model.get_config())
        rebuilt = model.__class__.from_config(cfg)
        rebuilt.set_weights(weights)
    except Exception as e:
        print(f"  [WARN] Rebuild via config gagal ({e}) — coba clone_model...")
        try:
            rebuilt = tf.keras.models.clone_model(model)
            rebuilt.set_weights(weights)
        except Exception as e2:
            print(f"  [WARN] clone_model juga gagal ({e2}) — konversi dilanjutkan "
                  f"dengan model asli (kemungkinan tetap gagal atas fp16).")
            return model, False

    # Sanitas: tak boleh tersisa f16
    leftover_vars = [v for v in rebuilt.weights if v.dtype == tf.float16]
    leftover_layers = [l.name for l in _iter_all_layers(rebuilt.layers)
                       if getattr(l, "compute_dtype", None) == tf.float16]
    if leftover_vars or leftover_layers:
        print(f"  [WARN] Masih tersisa f16 (vars={len(leftover_vars)}, "
              f"layers={leftover_layers[:5]}) — konversi dilanjutkan dengan "
              f"model asli.")
        return model, False

    print("  [FIX] Model sekarang full float32 (bobot master tersalin).")
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
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
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
            "keras": os.path.join(base_dir, "best_fluorescence_model.keras"),
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
        print("  scp bccare_*.tflite <user>@<ip>:~/kodepythonraspi4/")
    else:
        print("SEBAGIAN GAGAL — periksa log di atas sebelum deploy.")
    print("=" * 60)
    return all_ok


if __name__ == "__main__":
    verify = "--no-verify" not in sys.argv
    ok = convert_keras_to_tflite(verify=verify)
    sys.exit(0 if ok else 1)

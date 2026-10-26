#!/usr/bin/env python3
"""
Diagnosis model BC-Care. TIDAK mengubah file apa pun di proyek.

Mode 1 — uji sensitivitas (tanpa argumen):
    python3 diag_ml.py [--img /path/foto.jpg]
  Memberi model foto asli + variasi (blur, gelap, terang, hitam, abu, putih,
  noise, kanal BGR) dan menampilkan P(BCC). Model sehat: gambar hitam/abu/noise
  TIDAK boleh konsisten bernilai BCC tinggi; blur berat harus mengubah skor.

Mode 2 — evaluasi dataset berlabel:
    python3 diag_ml.py /path/dataset [uv|white]
  dataset berisi dua subfolder: BCC/ dan NORMAL/ (huruf besar/kecil bebas).
  Menampilkan matriks konfusi, sensitivitas, spesifisitas, rata-rata skor tiap
  kelas, dan AUC. AUC < 0.5 = indikasi kuat urutan label TERBALIK.
"""
import glob
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

from bccare_ml import get_classifier

CAPT = "/mnt/data/backup-pi/bccare_captures"
MAX_PER_CLASS = 300


def score(c, path, mode):
    r = c.predict(path, mode=mode)
    return float(r["raw_score"]), bool(r.get("simulated"))


def auc(pos, neg):
    s = 0.0
    for p in pos:
        for n in neg:
            s += 1.0 if p > n else 0.5 if p == n else 0.0
    return s / (len(pos) * len(neg))


def newest(pattern_fn):
    files = [f for f in glob.glob(os.path.join(CAPT, "*.jpg")) if pattern_fn(os.path.basename(f).lower())]
    return max(files, key=os.path.getmtime) if files else None


def sensitivitas(c, img_override):
    print("\n=== UJI SENSITIVITAS INPUT (nilai = P(BCC)) ===")
    for mode in ("uv", "white"):
        src = img_override or (
            newest(lambda n: "uv" in n) if mode == "uv" else newest(lambda n: "uv" not in n)
        ) or newest(lambda n: True)
        if not src:
            print(f"[{mode}] tidak ada foto di {CAPT}")
            continue
        base = Image.open(src).convert("RGB")
        w, h = base.size
        arr = np.asarray(base).astype(np.float32)
        variants = {
            "asli": base,
            "blur_5": base.filter(ImageFilter.GaussianBlur(5)),
            "blur_25": base.filter(ImageFilter.GaussianBlur(25)),
            "gelap_x0.2": Image.fromarray(np.clip(arr * 0.2, 0, 255).astype("uint8")),
            "terang_x1.8": Image.fromarray(np.clip(arr * 1.8, 0, 255).astype("uint8")),
            "kanal_BGR": Image.fromarray(arr[:, :, ::-1].astype("uint8")),
            "hitam": Image.new("RGB", (w, h), (0, 0, 0)),
            "abu": Image.new("RGB", (w, h), (128, 128, 128)),
            "putih": Image.new("RGB", (w, h), (255, 255, 255)),
            "noise": Image.fromarray(np.random.randint(0, 255, (h // 4, w // 4, 3), dtype="uint8")),
        }
        print(f"\n[{mode}] sumber: {os.path.basename(src)}")
        for name, im in variants.items():
            p = f"/tmp/diag_{mode}_{name}.jpg"
            im.save(p, quality=95)
            s, sim = score(c, p, mode)
            print(f"  {name:<12} P(BCC)={s:.3f}  {'(SIMULASI!)' if sim else ''}")
        # rentang input 0-255 vs 0-1 pada foto asli
        orig = c.input_range
        for rng in ("0-255", "0-1"):
            c.input_range = rng
            s, _ = score(c, src, mode)
            print(f"  input_range={rng:<6} P(BCC)={s:.3f}  (foto asli)")
        c.input_range = orig


def evaluasi(c, root, mode):
    print(f"\n=== EVALUASI DATASET ({root}, mode={mode}) ===")
    sub = {d.lower(): os.path.join(root, d) for d in os.listdir(root)
           if os.path.isdir(os.path.join(root, d))}
    if "bcc" not in sub or "normal" not in sub:
        print(f"Butuh subfolder BCC dan NORMAL; ditemukan: {list(sub)}")
        return
    scores = {}
    for label in ("bcc", "normal"):
        files = sorted(f for ext in ("jpg", "jpeg", "png")
                       for f in glob.glob(os.path.join(sub[label], f"*.{ext}")))[:MAX_PER_CLASS]
        scores[label] = [score(c, f, mode)[0] for f in files]
        print(f"  {label.upper():<7} {len(files)} gambar, rata-rata P(BCC)={np.mean(scores[label]):.3f}")
    pos, neg = scores["bcc"], scores["normal"]
    if not pos or not neg:
        print("Salah satu kelas kosong.")
        return
    tp = sum(s >= 0.5 for s in pos)
    fn = len(pos) - tp
    fp = sum(s >= 0.5 for s in neg)
    tn = len(neg) - fp
    a = auc(pos, neg)
    print(f"\n  Matriks konfusi (positif = BCC, ambang 0.5):")
    print(f"                 prediksi BCC   prediksi NORMAL")
    print(f"    asli BCC     {tp:>12}   {fn:>15}")
    print(f"    asli NORMAL  {fp:>12}   {tn:>15}")
    print(f"  Sensitivitas = {tp / len(pos):.3f}   Spesifisitas = {tn / len(neg):.3f}")
    print(f"  AUC = {a:.3f}")
    if a < 0.45:
        print("  >> AUC jauh di bawah 0.5: urutan label kemungkinan TERBALIK (indeks BCC/NORMAL).")
    elif a < 0.65:
        print("  >> AUC rendah: model hampir tidak membedakan kedua kelas pada gambar dari alat ini.")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    img = None
    if "--img" in sys.argv:
        img = sys.argv[sys.argv.index("--img") + 1]
        args = [a for a in args if a != img]
    c = get_classifier()
    if args and os.path.isdir(args[0]):
        evaluasi(c, args[0], args[1] if len(args) > 1 else "uv")
    else:
        sensitivitas(c, img)


if __name__ == "__main__":
    main()

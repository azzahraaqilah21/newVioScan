import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/clinical_risk_assessment_model.dart';
import '../models/screening_model.dart';

/// Laporan PDF hasil skrining — dipakai tombol Download & Share di layar hasil.
class ReportService {
  static const _teal = PdfColor.fromInt(0xFF0A858C);
  static const _abu = PdfColor.fromInt(0xFF6B7280);
  static const _garis = PdfColor.fromInt(0xFFE5E7EB);

  static const _labelRisiko = {
    'low': 'Risiko Rendah',
    'moderate': 'Risiko Sedang',
    'high': 'Risiko Tinggi',
  };

  /// Pertanyaan & jawaban Skin Risk Assessment (sama dengan kuisioner).
  static List<List<String>> _jawabanAssessment(ClinicalRiskAssessmentModel c) {
    String pilih(Map<String, String> m, String? v) => m[v] ?? (v ?? '-');
    return [
      ['Tipe kulit', pilih({'I-II': 'Tipe I-II', 'III-IV': 'Tipe III-IV', 'V-VI': 'Tipe V-VI'}, c.skinType)],
      ['Luka bakar matahari parah', pilih({'never': 'Tidak pernah', '1-2': '1-2 kali', '3+': '3 kali atau lebih'}, c.historyOfSunburn)],
      ['Riwayat kanker kulit di keluarga', pilih({'no': 'Tidak ada riwayat', 'unsure': 'Tidak yakin', 'yes': 'Ya, ada'}, c.familyHistorySkinCancer)],
      ['Paparan matahari harian', pilih({'<1h': '< 1 jam', '1-3h': '1-3 jam', '>3h': '> 3 jam'}, c.dailyUvExposure)],
      ['Pelindung matahari', pilih({'always': 'Selalu', 'sometimes': 'Kadang-kadang', 'rarely': 'Jarang/Tidak pernah'}, c.sunscreenUse)],
      ['Perubahan pada kulit', pilih({'none': 'Tidak ada perubahan', 'minor': 'Perubahan minor', 'significant': 'Perubahan signifikan'}, c.noticedSkinChanges)],
    ];
  }

  /// Font bawaan PDF hanya mendukung huruf Latin dasar — ganti tanda baca
  /// khusus agar tidak tampil sebagai kotak.
  static String _t(String s) => s
      .replaceAll(RegExp('[–—]'), '-')
      .replaceAll('≥', '>=')
      .replaceAll('≤', '<=')
      .replaceAll('→', '->')
      .replaceAll(RegExp(r'[^\x00-\xFF]'), '');

  static String namaFile(ScreeningModel m) =>
      'VioScan_${DateFormat('yyyyMMdd_HHmmss').format(m.screeningDate)}.pdf';

  /// [analisis]: baris "Analisis BC-Care" (label, value) dari layar hasil.
  /// [rekomendasi]: rekomendasi per tingkat risiko dari layar hasil.
  static Future<Uint8List> buatPdf(
    ScreeningModel m, {
    required List<Map<String, String>> analisis,
    required Map<String, dynamic> rekomendasi,
  }) async {
    final doc = pw.Document(title: 'Laporan Skrining Vio Scan');
    final tanggal =
        DateFormat('d MMMM yyyy, HH:mm', 'id_ID').format(m.screeningDate);
    final probabilitas = m.probabilities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    pw.Widget judul(String teks) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
          child: pw.Text(_t(teks),
              style: const pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold, color: _teal)),
        );

    pw.Widget tabel(List<List<String>> baris) => pw.Table(
          border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: _garis, width: 0.5)),
          columnWidths: const {
            0: pw.FlexColumnWidth(2),
            1: pw.FlexColumnWidth(3),
          },
          children: [
            for (final b in baris)
              pw.TableRow(children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 4),
                  child: pw.Text(_t(b[0]),
                      style: const pw.TextStyle(fontSize: 10, color: _abu)),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 4),
                  child: pw.Text(_t(b[1]),
                      style: const pw.TextStyle(
                          fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ),
              ]),
          ],
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        footer: (ctx) => pw.Column(children: [
          pw.Divider(color: _garis),
          pw.Text(
            _t('Hasil skrining ini BUKAN diagnosis. Keputusan klinis tetap '
                'harus dibuat oleh dokter Spesialis Kulit & Kelamin (SpKK). '
                'Halaman ${ctx.pageNumber}/${ctx.pagesCount}'),
            style: const pw.TextStyle(fontSize: 8, color: _abu),
          ),
        ]),
        build: (ctx) => [
          pw.Text('Laporan Hasil Skrining Lesi Kulit',
              style:
                  const pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Text(_t('Vio Scan - $tanggal WIB'),
              style: const pw.TextStyle(fontSize: 10, color: _abu)),
          if (m.isSimulated)
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 10),
              padding: const pw.EdgeInsets.all(8),
              color: const PdfColor.fromInt(0xFFFEF3C7),
              child: pw.Text(
                'HASIL SIMULASI - bukan dari model AI. Jangan dipakai untuk '
                'keputusan klinis.',
                style: const pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
            ),
          judul('Data Skrining'),
          tabel([
            ['Tanggal & waktu', '$tanggal WIB'],
            ['Lokasi lesi', m.lesionLocation],
            if (m.lesionNotes != null && m.lesionNotes!.trim().isNotEmpty)
              ['Catatan', m.lesionNotes!.trim()],
            ['Mode cahaya', m.mode == 'white' ? 'Putih (dermoskopi)' : 'UV (fluoresensi)'],
          ]),
          if (m.rawImageBytes != null) ...[
            judul('Foto Lesi (kamera alat)'),
            pw.Center(
              child: pw.Image(pw.MemoryImage(m.rawImageBytes!),
                  height: 200, fit: pw.BoxFit.contain),
            ),
          ],
          judul('Hasil AI'),
          tabel([
            ['Prediksi', m.prediction],
            ['Tingkat risiko', _labelRisiko[m.riskLevel] ?? m.riskLevel],
            ['Keyakinan CNN', '${m.confidence.toStringAsFixed(1)}%'],
            for (final p in probabilitas)
              [
                'Probabilitas ${p.key.toUpperCase().contains('BCC') ? 'Basal Cell Carcinoma' : 'Nevus / Kulit Normal'}',
                '${p.value.toStringAsFixed(1)}%',
              ],
          ]),
          judul('Analisis BC-Care'),
          tabel([
            for (final a in analisis) [a['label'] ?? '', a['value'] ?? ''],
          ]),
          if (m.clinicalRiskAssessment != null) ...[
            judul('Skin Risk Assessment'),
            tabel(_jawabanAssessment(m.clinicalRiskAssessment!)),
          ],
          judul('Rekomendasi'),
          pw.Text(_t(rekomendasi['urgency'] as String? ?? ''),
              style: const pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          for (final sec in (rekomendasi['sections'] as List? ?? const []))
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 8),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(_t(sec['title'] as String),
                      style: const pw.TextStyle(
                          fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  for (final item in (sec['items'] as List))
                    pw.Bullet(
                        text: _t(item as String),
                        style: const pw.TextStyle(fontSize: 9.5)),
                  pw.Text(_t('Sumber: ${sec['source']}'),
                      style: const pw.TextStyle(fontSize: 8, color: _abu)),
                ],
              ),
            ),
        ],
      ),
    );
    return doc.save();
  }

  /// Simpan ke folder Download HP. Return path file.
  /// Android 10+ mengizinkan aplikasi membuat file di Download tanpa izin
  /// penyimpanan; jika gagal, simpan di folder aplikasi.
  static Future<String> simpanKeDownload(Uint8List bytes, String nama) async {
    if (Platform.isAndroid) {
      try {
        final file = File('/storage/emulated/0/Download/$nama');
        await file.writeAsBytes(bytes, flush: true);
        return file.path;
      } catch (_) {
        // lanjut ke folder aplikasi
      }
    }
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$nama');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Bagikan PDF lewat menu bagikan Android (WhatsApp, email, Drive, dll).
  static Future<void> bagikan(Uint8List bytes, String nama) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$nama');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Laporan Skrining Vio Scan',
        text: 'Laporan hasil skrining lesi kulit (bukan diagnosis).',
      ),
    );
  }
}

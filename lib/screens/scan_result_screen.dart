import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/screening_provider.dart';
import '../providers/device_provider.dart';
import '../models/screening_model.dart';

class ScanResultScreen extends ConsumerStatefulWidget {
  final Function(String) navigate;

  /// true = membuka hasil tersimpan dari Riwayat (historyViewProvider):
  /// hanya dilihat — tanpa tombol Simpan & tanpa skenario demo.
  final bool fromHistory;

  const ScanResultScreen({
    super.key,
    required this.navigate,
    this.fromHistory = false,
  });

  @override
  ConsumerState<ScanResultScreen> createState() => _ScanResultScreenState();
}

class _ScanResultScreenState extends ConsumerState<ScanResultScreen>
    with SingleTickerProviderStateMixin {
  String riskLevel = 'moderate';
  bool _isSaved = false;
  bool _isSaving = false;
  late AnimationController _arcController;

  final Map<String, Map<String, dynamic>> riskConfig = {
    'low': {
      'label': 'Risiko Rendah',
      'labelEn': 'Low Risk',
      'suspect': 'Nevus (Normal)',
      'bg': const Color(0xFFECFDF5),
      'text': const Color(0xFF059669),
      'border': const Color(0xFFA7F3D0),
      'headerBg': [const Color(0xFF059669), const Color(0xFF10B981)],
      'icon': Icons.check_circle_rounded,
      'confidence': 94.1,
      'probabilities': [
        {'name': 'Nevus (Normal)', 'value': 94.1, 'color': const Color(0xFF059669)},
        {'name': 'Basal Cell Carcinoma', 'value': 4.0, 'color': const Color(0xFFDC2626)},
        {'name': 'Lainnya (SH, dll)', 'value': 1.9, 'color': const Color(0xFFD97706)},
      ],
    },
    'moderate': {
      'label': 'Risiko Sedang',
      'labelEn': 'Moderate Risk',
      'suspect': 'Sebaceous Hyperplasia',
      'bg': const Color(0xFFFFFBEB),
      'text': const Color(0xFFD97706),
      'border': const Color(0xFFFDE68A),
      'headerBg': [const Color(0xFFB45309), const Color(0xFFD97706)],
      'icon': Icons.error_rounded,
      'confidence': 78.1,
      'probabilities': [
        {'name': 'Sebaceous Hyperplasia', 'value': 78.1, 'color': const Color(0xFFD97706)},
        {'name': 'Basal Cell Carcinoma', 'value': 16.8, 'color': const Color(0xFFDC2626)},
        {'name': 'Nevus (Normal)', 'value': 5.1, 'color': const Color(0xFF059669)},
      ],
    },
    'high': {
      'label': 'Risiko Tinggi',
      'labelEn': 'High Risk',
      'suspect': 'Basal Cell Carcinoma',
      'bg': const Color(0xFFFEF2F2),
      'text': const Color(0xFFDC2626),
      'border': const Color(0xFFFECACA),
      'headerBg': [const Color(0xFF991B1B), const Color(0xFFDC2626)],
      'icon': Icons.warning_rounded,
      'confidence': 85.3,
      'probabilities': [
        {'name': 'Basal Cell Carcinoma', 'value': 85.3, 'color': const Color(0xFFDC2626)},
        {'name': 'Nevus (Normal)', 'value': 9.0, 'color': const Color(0xFF059669)},
        {'name': 'Lainnya (SH, dll)', 'value': 5.7, 'color': const Color(0xFFD97706)},
      ],
    },
  };

  final Map<String, Map<String, dynamic>> recommendations = {
    'high': {
      'urgency': 'SEGERA — Tindak dalam 1–2 Minggu',
      'urgencyColor': const Color(0xFFDC2626),
      'urgencyBg': const Color(0xFFFEF2F2),
      'sections': [
        {
          'icon': Icons.assignment_rounded,
          'color': const Color(0xFFDC2626),
          'bg': const Color(0xFFFEF2F2),
          'title': 'Tindakan Klinis Segera',
          'source': 'NCCN BCC Guidelines 2024, Kemenkes RI 2022',
          'items': [
            'Buat surat rujukan ke dokter Spesialis Kulit & Kelamin (SpKK) — prioritas urgent dalam 1–2 minggu',
            'Gunakan form rujukan BPJS ke FKRTL (Fasilitas Kesehatan Rujukan Tingkat Lanjut)',
            'Jangan lakukan biopsi atau tindakan eksisi di level puskesmas',
            'Dokumentasikan lesi: foto dengan penggaris skala cm dari jarak 15 cm dan 30 cm',
            'Catat morfologi lengkap: ukuran (mm), batas, warna, tekstur permukaan, dan durasi lesi',
          ],
        },
        {
          'icon': Icons.person_search_rounded,
          'color': const Color(0xFF0A858C),
          'bg': const Color(0xFFE6F7F7),
          'title': 'Edukasi Pasien',
          'source': 'WHO Cancer Prevention Guidelines 2023',
          'items': [
            'Hindari paparan sinar UV langsung, terutama pukul 10.00–16.00 WIB',
            'Gunakan tabir surya SPF 50+ broad spectrum setiap hari',
            'Jangan manipulasi, menggaruk, atau mengobati lesi secara mandiri',
            'Segera kembali ke puskesmas jika terdapat perdarahan, ulserasi, atau perubahan cepat',
          ],
        },
      ],
    },
    'moderate': {
      'urgency': 'MONITORING — Tindak dalam 4–6 Minggu',
      'urgencyColor': const Color(0xFFD97706),
      'urgencyBg': const Color(0xFFFFFBEB),
      'sections': [
        {
          'icon': Icons.assignment_rounded,
          'color': const Color(0xFFD97706),
          'bg': const Color(0xFFFFFBEB),
          'title': 'Monitoring & Follow-up',
          'source': 'EDF Guidelines 2023, Permenkes No. 5/2014',
          'items': [
            'Jadwalkan pemeriksaan ulang dalam 4–6 minggu untuk evaluasi perubahan lesi',
            'Gunakan dermoskopi jika tersedia untuk evaluasi struktur vaskular dan pigmen',
            'Catat foto serial lesi dengan skala — bandingkan setiap kunjungan',
            'Nilai ABCDE: Asymmetry, Border, Color, Diameter, Evolving pada setiap kontrol',
          ],
        },
        {
          'icon': Icons.person_search_rounded,
          'color': const Color(0xFF0A858C),
          'bg': const Color(0xFFE6F7F7),
          'title': 'Manajemen & Edukasi Pasien',
          'source': 'WHO Cancer Prevention Guidelines 2023, PERDOSKI 2021',
          'items': [
            'Oleskan tabir surya SPF 30+ minimal 30 menit sebelum terpapar matahari',
            'Gunakan pakaian lengan panjang dan topi bertepi lebar di luar ruangan',
            'Hindari trauma pada area lesi — jangan dikorek atau ditekan',
            'Ajarkan ABCDE self-check kulit secara mandiri setiap bulan',
          ],
        },
      ],
    },
    'low': {
      'urgency': 'PREVENTIF — Skrining Ulang dalam 3 Bulan',
      'urgencyColor': const Color(0xFF059669),
      'urgencyBg': const Color(0xFFECFDF5),
      'sections': [
        {
          'icon': Icons.shield_rounded,
          'color': const Color(0xFF059669),
          'bg': const Color(0xFFECFDF5),
          'title': 'Tindakan Rutin',
          'source': 'Kemenkes RI Pedoman Kanker Kulit 2022',
          'items': [
            'Catat hasil sebagai data baseline rekam medis pasien',
            'Jadwalkan skrining BC-Care ulang dalam 3 bulan',
            'Edukasi pemeriksaan kulit mandiri (self-examination) setiap bulan',
            'Input data ke sistem pelaporan puskesmas sebagai deteksi dini negatif',
          ],
        },
        {
          'icon': Icons.person_search_rounded,
          'color': const Color(0xFF7C3AED),
          'bg': const Color(0xFFF5F3FF),
          'title': 'Panduan ABCDE untuk Pasien',
          'source': 'American Academy of Dermatology (AAD) ABCDE Rule',
          'items': [
            'A – Asymmetry: bentuk lesi tidak simetris bila dilipat dua',
            'B – Border: tepi lesi tidak rata, bergerigi, atau tidak jelas batasnya',
            'C – Color: variasi warna dalam satu lesi (coklat, hitam, merah, putih)',
            'D – Diameter: ukuran >6 mm (sebesar penghapus ujung pensil)',
            'E – Evolving: perubahan ukuran, warna, bentuk, atau gejala baru',
          ],
        },
      ],
    },
  };

  @override
  void initState() {
    super.initState();
    _arcController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _arcController.forward();

    // NOTE: ref.listen TIDAK boleh dipanggil di initState — Riverpod hanya
    // mengizinkannya di dalam build() (assertion
    // "ref.listen can only be used within the build method of a ConsumerWidget").
    // Listener sudah dipindah ke build() di bawah.
    // Handle nilai awal hasil hardware setelah frame pertama (ref.read di sini
    // di initState adalah hal yang sah).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final hwResult = widget.fromHistory
          ? ref.read(historyViewProvider)
          : ref.read(latestHardwareResultProvider);
      if (hwResult != null && mounted) {
        setState(() {
          riskLevel = hwResult.riskLevel;
        });
      }
    });
  }

  @override
  void dispose() {
    _arcController.dispose();
    super.dispose();
  }

  void setRisk(String level) {
    setState(() {
      riskLevel = level;
      _isSaved = false;
    });
    _arcController.forward(from: 0);
  }

  /// Keluar dari layar hasil. Hasil yang sudah disimpan baru dibersihkan di
  /// sini (bukan saat Simpan) agar foto tetap terlihat, dan tidak tersimpan
  /// dua kali saat layar ini dibuka lagi.
  void _tinggalkanHasil() {
    if (widget.fromHistory) {
      ref.read(historyViewProvider.notifier).state = null;
      widget.navigate('history');
      return;
    }
    if (_isSaved) {
      ref.read(latestHardwareResultProvider.notifier).clear();
      ref.read(capturedImageProvider.notifier).clear();
    }
    widget.navigate('dashboard');
  }

  Future<void> _saveResult() async {
    if (_isSaved || _isSaving) return;
    setState(() => _isSaving = true);

    try {
      final user = ref.read(authStateProvider).value;
      final lesionInfo = ref.read(lesionInfoProvider);
      final clinicalData = ref.read(clinicalAssessmentProvider);
      final hwResult = ref.read(latestHardwareResultProvider);

      // Tanpa hasil dari alat, layar hanya menampilkan contoh per tingkat
      // risiko — contoh itu tidak boleh tersimpan sebagai hasil skrining.
      if (hwResult == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Belum ada hasil dari alat. Hasil contoh tidak disimpan.',
              ),
              backgroundColor: Color(0xFFD97706),
            ),
          );
        }
        return;
      }

      final model = hwResult
          // FIX: userId & info lesi dari form/auth WAJIB dipakai — sebelumnya
          // hasil hardware disimpan dengan userId 'local_patient' & lokasi
          // generik, sehingga riwayat/statistik user tidak pernah terisi.
          .copyWith(
            userId: user?.uid ?? 'offline_user',
            lesionLocation: lesionInfo?.location ?? 'Lesi Kulit',
            lesionNotes: lesionInfo?.notes,
            clinicalRiskAssessment: clinicalData,
          );

      // Foto ikut tersimpan di dokumen Firestore yang sama (lihat
      // ScreeningModel.toMap) — tanpa Firebase Storage / paket Blaze.
      final foto = model.rawImageBytes;
      final fotoTersimpan =
          foto == null || foto.length <= ScreeningModel.maxStoredImageBytes;

      // Simpan ke Firestore jika akun online terhubung
      if (user != null) {
        try {
          final firestoreService = ref.read(firestoreServiceProvider);
          await firestoreService.saveScreening(model);
        } catch (e) {
          debugPrint('Gagal menyimpan ke Firestore: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Gagal menyimpan ke cloud: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return; // _isSaved tetap false → user bisa mencoba lagi
        }
      }

      // Form selesai. Hasil alat & foto TETAP tampil di layar ini; baru
      // dibersihkan saat user meninggalkan layar (_tinggalkanHasil).
      ref.read(lesionInfoProvider.notifier).clear();
      ref.read(clinicalAssessmentProvider.notifier).clear();

      // Refresh stats jika online
      ref.invalidate(userStatsProvider);

      setState(() => _isSaved = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    user == null
                        ? 'Hasil berhasil disimpan secara lokal (Mode Offline)!'
                        : fotoTersimpan
                            ? 'Hasil berhasil disimpan ke database & cloud!'
                            : 'Hasil tersimpan, tetapi foto terlalu besar untuk disimpan.',
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF059669),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    // Sumber data: hasil dari Riwayat (mode lihat) atau hasil alat terbaru.
    final hwResult = widget.fromHistory
        ? ref.watch(historyViewProvider)
        : ref.watch(latestHardwareResultProvider);
    final capturedImageBytes = hwResult?.rawImageBytes ??
        (widget.fromHistory ? null : ref.watch(capturedImageProvider));

    // Listen for hardware result updates in real-time.
    // ref.listen HANYA sah di dalam build() dari ConsumerWidget/ConsumerState.
    ref.listen<ScreeningModel?>(latestHardwareResultProvider, (previous, next) {
      if (widget.fromHistory) return; // mode Riwayat tidak ikut hasil alat baru
      if (next != null && mounted) {
        setState(() {
          riskLevel = next.riskLevel;
          _isSaved = false; // hasil baru → tombol simpan aktif lagi
        });
        _arcController.forward(from: 0);
      }
    });

    final rc = riskConfig[riskLevel]!;
    final reco = recommendations[riskLevel]!;
    final confidence = hwResult != null ? hwResult.confidence : (rc['confidence'] as double);

    // Tombol back HP = tombol kembali di layar (lihat _tinggalkanHasil).
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _tinggalkanHasil();
      },
      child: Container(
      color: const Color(0xFFF0FAFA),
      child: Column(
        children: [
          // Header
          Container(
            padding: EdgeInsets.only(
              top: topPad + 8,
              left: 18,
              right: 18,
              bottom: 14,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Color(0x0D000000),
                  blurRadius: 12,
                  offset: Offset(0, 2),
                )
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                        GestureDetector(
                          onTap: _tinggalkanHasil,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF0FAFA),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.arrow_back_rounded,
                                color: Color(0xFF0A858C), size: 20),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hasil Skrining',
                              style: TextStyle(
                                color: Color(0xFF1F2937),
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        Flexible(
                          child: Builder(
                            builder: (_) {
                              final date = hwResult?.screeningDate ?? DateTime.now();
                              final formatted = DateFormat(
                                'd MMM yyyy · HH:mm',
                                'id_ID',
                              ).format(date);
                              return Text(
                                formatted,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 11.5,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                      ),
                    ),
                    Row(
                      children: [
                        for (final ico in [Icons.share_rounded, Icons.save_alt_rounded])
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            width: 38,
                            height: 38,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF0FAFA),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(ico, color: const Color(0xFF0A858C), size: 16),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (hwResult != null)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      // Banner simulasi = oranye peringatan; hasil nyata = teal
                      color: hwResult.isSimulated
                          ? const Color(0xFFF59E0B).withValues(alpha: 0.12)
                          : const Color(0xFF0A858C).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: hwResult.isSimulated
                            ? const Color(0xFFF59E0B).withValues(alpha: 0.45)
                            : const Color(0xFF0A858C).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                hwResult.isSimulated
                                    ? Icons.warning_amber_rounded
                                    : Icons.bluetooth_rounded,
                                size: 16,
                                color: hwResult.isSimulated
                                    ? const Color(0xFFD97706)
                                    : const Color(0xFF0A858C),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  hwResult.isSimulated
                                      ? 'HASIL SIMULASI — model ML tidak aktif. BUKAN diagnosis. Jalankan export_to_tflite.py & deploy .tflite ke alat.'
                                      : widget.fromHistory
                                          ? 'Hasil tersimpan dari Riwayat (${hwResult.mode?.toUpperCase() ?? "UV"})'
                                          : 'Hasil Real-time Raspberry Pi via Bluetooth (${hwResult.mode?.toUpperCase() ?? "UV"})',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: hwResult.isSimulated
                                        ? const Color(0xFFB45309)
                                        : const Color(0xFF0A858C),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Tombol buang hasil hanya untuk hasil alat yang baru,
                        // bukan untuk hasil tersimpan yang dibuka dari Riwayat.
                        if (!widget.fromHistory)
                          GestureDetector(
                            onTap: () {
                              ref.read(latestHardwareResultProvider.notifier).clear();
                              ref.read(capturedImageProvider.notifier).clear();
                              setRisk('moderate');
                            },
                            child: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF0A858C)),
                          ),
                      ],
                    ),
                  )
                else ...[
                  // Demo switcher
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'SKENARIO DEMO — Pilih tingkat risiko:',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: ['low', 'moderate', 'high'].map((level) {
                      final cfg = riskConfig[level]!;
                      final isActive = riskLevel == level;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setRisk(level),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3.5),
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: isActive ? cfg['bg'] as Color : Colors.transparent,
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(
                                color: isActive
                                    ? cfg['text'] as Color
                                    : const Color(0xFFE5E7EB),
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              cfg['labelEn'] as String,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isActive
                                    ? cfg['text'] as Color
                                    : const Color(0xFF6B7280),
                                fontSize: 11,
                                fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Column(
                children: [
                  // UV Image + risk banner
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.07),
                          blurRadius: 16,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Column(
                      children: [
                        // UV Image / Foto Kamera Nyata
                        Container(
                          height: 165,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: riskLevel == 'high'
                                  ? [const Color(0xFF120030), const Color(0xFF3D0B6B), const Color(0xFF6B0082), const Color(0xFF8B21A8), const Color(0xFFDC2626)]
                                  : riskLevel == 'moderate'
                                  ? [const Color(0xFF120030), const Color(0xFF2D0B6B), const Color(0xFF4B0082), const Color(0xFF7B21A8), const Color(0xFFD97706)]
                                  : [const Color(0xFF120030), const Color(0xFF2D0B6B), const Color(0xFF4B0082), const Color(0xFF5B21A8), const Color(0xFF36B8B7)],
                              stops: const [0, 0.3, 0.55, 0.75, 1.0],
                            ),
                          ),
                          child: capturedImageBytes != null
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.memory(
                                      capturedImageBytes,
                                      fit: BoxFit.cover,
                                    ),
                                    Positioned(
                                      top: 10,
                                      left: 12,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.6),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.camera_alt_rounded, color: Color(0xFF77DAD7), size: 12),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Kamera Raspberry Pi · ${hwResult?.mode?.toUpperCase() ?? "UV"}',
                                              style: const TextStyle(
                                                color: Color(0xFF77DAD7),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Stack(
                                  children: [
                                    ...List.generate(3, (i) => Positioned(
                                      left: 0, right: 0,
                                      top: 150 * (i + 1) / 4,
                                      child: Container(height: 1, color: const Color(0xFF77DAD7).withValues(alpha: 0.1)),
                                    )),
                                    Positioned(
                                      top: 10, left: 12,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.4),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Text('Fluorosensi UV · BC-Care',
                                          style: TextStyle(color: Color(0xFF77DAD7), fontSize: 11, fontWeight: FontWeight.w600)),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 10, right: 12,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.4),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text('Lengan Kiri',
                                          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        // Risk summary
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          color: rc['bg'] as Color,
                          child: Row(
                            children: [
                              Icon(rc['icon'] as IconData,
                                  color: rc['text'] as Color, size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      rc['label'] as String,
                                      style: TextStyle(
                                        color: rc['text'] as Color,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                    Text(
                                      '${rc['labelEn']} · Lokasi: Lengan Kiri',
                                      style: TextStyle(
                                        color: (rc['text'] as Color).withOpacity(0.75),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: Container(
                                  key: ValueKey(riskLevel),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: rc['text'] as Color,
                                    borderRadius: BorderRadius.circular(100),
                                  ),
                                  child: Text(
                                    '$confidence%',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Disease Probabilities Distribution
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      key: ValueKey('$riskLevel-prob'),
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 12,
                            offset: const Offset(0, 2),
                          )
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Distribusi Probabilitas Penyakit',
                            style: TextStyle(
                              color: Color(0xFF1F2937),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Prediksi AI berdasarkan analisis pola fluorosensi',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 10.5,
                            ),
                          ),
                          const SizedBox(height: 14),
                          ...(rc['probabilities'] as List).map((prob) {
                            final val = prob['value'] as double;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        prob['name'] as String,
                                        style: const TextStyle(
                                          color: Color(0xFF475569),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),

                                      Text(
                                        '${val.toStringAsFixed(1)}%',
                                        style: TextStyle(
                                          color: prob['color'] as Color,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: val / 100,
                                      backgroundColor: const Color(0xFFF1F5F9),
                                      valueColor: AlwaysStoppedAnimation(prob['color'] as Color),
                                      minHeight: 6,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  ),
                  // Urgency banner
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      key: ValueKey('$riskLevel-urgency'),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: reco['urgencyBg'] as Color,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: reco['urgencyColor'] as Color,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: (reco['urgencyColor'] as Color).withOpacity(0.13),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              rc['icon'] as IconData,
                              color: reco['urgencyColor'] as Color,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  reco['urgency'] as String,
                                  style: TextStyle(
                                    color: reco['urgencyColor'] as Color,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                  ),
                                ),
                                Text(
                                  'Panduan untuk Tenaga Kesehatan Puskesmas',
                                  style: TextStyle(
                                    color: (reco['urgencyColor'] as Color).withOpacity(0.7),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Recommendation sections
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Column(
                      key: ValueKey('$riskLevel-reco'),
                      children: (reco['sections'] as List).map((section) {
                        final s = section as Map<String, dynamic>;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 12,
                                offset: const Offset(0, 2),
                              )
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Section header
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: s['bg'] as Color,
                                        borderRadius: BorderRadius.circular(11),
                                      ),
                                      child: Icon(
                                        s['icon'] as IconData,
                                        color: s['color'] as Color,
                                        size: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            s['title'] as String,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                              color: Color(0xFF1F2937),
                                            ),
                                          ),
                                          Text(
                                            'Sumber: ${s['source']}',
                                            style: const TextStyle(
                                              color: Color(0xFF94A3B8),
                                              fontSize: 9.5,
                                              height: 1.3,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1, color: Color(0xFFF9FAFB)),
                              // Items
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                                child: Column(
                                  children: (s['items'] as List).asMap().entries.map((e) {
                                    return Padding(
                                      padding: EdgeInsets.only(
                                        bottom: e.key < (s['items'] as List).length - 1 ? 10 : 0,
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 20,
                                            height: 20,
                                            margin: const EdgeInsets.only(top: 1),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: s['bg'] as Color,
                                            ),
                                            child: Center(
                                              child: Text(
                                                '${e.key + 1}',
                                                style: TextStyle(
                                                  color: s['color'] as Color,
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 9),
                                          Expanded(
                                            child: Text(
                                              e.value as String,
                                              style: const TextStyle(
                                                color: Color(0xFF374151),
                                                fontSize: 12,
                                                height: 1.55,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  // ── Panel Informasi 3 Jenis Penyakit Kulit ──────────────
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFECFDF5),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.biotech_rounded,
                                    color: Color(0xFF059669), size: 18),
                              ),
                              const SizedBox(width: 10),
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Kenali 3 Kondisi yang Diskrining',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: Color(0xFF1F2937),
                                    ),
                                  ),
                                  Text(
                                    'Informasi Klinis · PERDOSKI & NCCN 2024',
                                    style: TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        // BCC
                        _DiseaseInfoTile(
                          color: const Color(0xFFDC2626),
                          bgColor: const Color(0xFFFEF2F2),
                          icon: Icons.warning_rounded,
                          name: 'Basal Cell Carcinoma (BCC)',
                          badge: 'RISIKO TINGGI',
                          description:
                              'Kanker kulit paling umum. Muncul di area yang sering terpapar sinar UV (wajah, hidung, telinga). Tanda khas: lesi berwarna mutiara/berkilap, tepi menggulung, atau tukak yang tidak sembuh.',
                          treatment:
                              'Dapat disembuhkan jika ditangani dini. Terapi: bedah eksisi, Mohs surgery, atau krioterapi.',
                        ),
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        // Nevus
                        _DiseaseInfoTile(
                          color: const Color(0xFF059669),
                          bgColor: const Color(0xFFECFDF5),
                          icon: Icons.check_circle_rounded,
                          name: 'Nevus (Tahi Lalat Jinak)',
                          badge: 'JINAK',
                          description:
                              'Lesi jinak berupa kumpulan sel melanosit. Biasanya berwarna cokelat/hitam seragam dengan tepi tegas. Tidak memerlukan pengobatan jika tidak ada perubahan ukuran, warna, atau bentuk.',
                          treatment:
                              'Pantau dengan metode ABCDE (Asymmetry, Border, Color, Diameter, Evolution). Konsultasi jika ada perubahan mendadak.',
                        ),
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        // SH
                        _DiseaseInfoTile(
                          color: const Color(0xFFD97706),
                          bgColor: const Color(0xFFFFFBEB),
                          icon: Icons.error_rounded,
                          name: 'Hiperplasia Sebasea (SH)',
                          badge: 'SEDANG',
                          description:
                              'Pembesaran kelenjar minyak yang jinak. Umum pada kulit berminyak dan orang dewasa >40 tahun. Tampak seperti papul kekuningan kecil dengan cekungan di tengah. Sering mirip BCC (doughnut sign).',
                          treatment:
                              'Jinak namun dapat menyerupai BCC. Konfirmasi dengan dermoskopi. Terapi estetika: electrodesiccation, laser CO₂, atau retinoid topikal.',
                          isLast: true,
                        ),
                      ],
                    ),
                  ),
                  // ── Disclaimer Medis ─────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(16),
                      border:
                          Border.all(color: const Color(0xFFFDE68A), width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.gavel_rounded,
                                size: 15, color: Color(0xFFD97706)),
                            const SizedBox(width: 6),
                            const Text(
                              'Disclaimer Medis',
                              style: TextStyle(
                                color: Color(0xFFD97706),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Hasil analisis VioScan BC-Care bersifat SKRINING AWAL berbasis AI dan TIDAK dapat menggantikan diagnosis klinis dokter atau SpKK. Hasil ini hanya sebagai alat bantu puskesmas untuk menentukan prioritas rujukan.',
                          style: TextStyle(
                            color: Color(0xFF92400E),
                            fontSize: 11,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '📚 Berbasis: NCCN BCC Guidelines 2024 · Kemenkes RI 2022 · PERDOSKI CPG 2021 · EDF Guidelines 2023',
                          style: TextStyle(
                            color: Color(0xFF78350F),
                            fontSize: 10,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Action buttons
                  Row(
                    children: [
                      // Hasil dari Riwayat sudah tersimpan — tanpa tombol Simpan.
                      if (!widget.fromHistory) ...[
                      Expanded(
                        child: GestureDetector(
                          onTap: _isSaved ? null : _saveResult,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: const Border.fromBorderSide(BorderSide(
                                color: Color(0xFF0A858C),
                                width: 2,
                              )),
                              color: _isSaved ? const Color(0xFF0A858C).withOpacity(0.1) : Colors.transparent,
                            ),
                            child: Center(
                              child: _isSaving 
                                ? const SizedBox(
                                    width: 18, height: 18, 
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0A858C)))
                                : Text(_isSaved ? 'Tersimpan' : 'Simpan Hasil',
                                style: const TextStyle(
                                  color: Color(0xFF0A858C),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                )),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ],
                      Expanded(
                        flex: 2,
                        child: GestureDetector(
                          onTap: _tinggalkanHasil,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF0A858C), Color(0xFF36B8B7)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF0A858C).withOpacity(0.3),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                )
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  widget.fromHistory
                                      ? 'Kembali ke Riwayat'
                                      : 'Kembali ke Beranda',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  )),
                                const SizedBox(width: 5),
                                Icon(
                                  widget.fromHistory
                                      ? Icons.history_rounded
                                      : Icons.home_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}

/// Tile keterangan satu jenis penyakit kulit pada panel edukasi di layar hasil.
class _DiseaseInfoTile extends StatefulWidget {
  final Color color;
  final Color bgColor;
  final IconData icon;
  final String name;
  final String badge;
  final String description;
  final String treatment;
  final bool isLast;

  const _DiseaseInfoTile({
    required this.color,
    required this.bgColor,
    required this.icon,
    required this.name,
    required this.badge,
    required this.description,
    required this.treatment,
    this.isLast = false,
  });

  @override
  State<_DiseaseInfoTile> createState() => _DiseaseInfoTileState();
}

class _DiseaseInfoTileState extends State<_DiseaseInfoTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, widget.isLast ? 14 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: widget.bgColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(widget.icon,
                      color: widget.color, size: 15),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: widget.bgColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.badge,
                          style: TextStyle(
                            color: widget.color,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: const Color(0xFF94A3B8),
                  size: 20,
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: _expanded
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.description,
                            style: const TextStyle(
                              color: Color(0xFF475569),
                              fontSize: 11.5,
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: widget.bgColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.medical_services_outlined,
                                    color: widget.color, size: 13),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    widget.treatment,
                                    style: TextStyle(
                                      color: widget.color,
                                      fontSize: 11,
                                      height: 1.55,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}




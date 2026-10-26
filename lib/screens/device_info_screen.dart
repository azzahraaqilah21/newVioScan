import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/device_provider.dart';
import '../services/device_service.dart';
import '../widgets/bottom_nav.dart';
import 'hardware_connection_screen.dart' show matikanAlatDenganKonfirmasi;

class DeviceInfoScreen extends ConsumerStatefulWidget {
  final Function(String) navigate;
  const DeviceInfoScreen({super.key, required this.navigate});

  @override
  ConsumerState<DeviceInfoScreen> createState() => _DeviceInfoScreenState();
}

class _DeviceInfoScreenState extends ConsumerState<DeviceInfoScreen>
    with SingleTickerProviderStateMixin {
  int? expanded = 0;
  late AnimationController _dotController;

  final List<Map<String, String>> guides = [
    {
      'title': 'Persiapan Skrining',
      'content': 'Bersihkan area kulit yang akan diperiksa dari riasan, losion, atau krim. Pastikan ruangan minim cahaya ambien. Pegang perangkat BC-Care tegak lurus 3–5 cm dari permukaan kulit. Minta pasien tetap diam selama proses pengambilan gambar berlangsung.',
    },
    {
      'title': 'Tombol pada Alat',
      'content': 'Tekan sekali untuk mengaktifkan alat (LED menyala). Setelah aktif: tekan 1× untuk mengambil foto & menjalankan analisis; tekan 2× cepat untuk berganti mode UV ↔ cahaya putih; tahan 8 detik untuk mematikan alat dengan aman. Alat juga bisa dimatikan dari aplikasi lewat tombol "Matikan Alat" di layar Koneksi Bluetooth.',
    },
    {
      'title': 'Interpretasi Hasil',
      'content': 'Risiko Rendah (hijau): edukasi preventif & skrining ulang berkala. Risiko Sedang (kuning): monitoring 4–6 minggu, pertimbangkan rujukan. Risiko Tinggi (merah): rujuk ke SpKK dalam 1–2 minggu. Hasil adalah skrining awal berbasis AI — bukan diagnosis, dan tidak menggantikan pemeriksaan dokter.',
    },
    {
      'title': 'Perawatan Perangkat',
      'content': 'Gunakan adaptor daya 5V 3A. Matikan alat dengan aman (tahan tombol 8 detik atau "Matikan Alat" di aplikasi) dan tunggu ±20 detik sebelum mencabut adaptor, agar penyimpanan tidak rusak. Bersihkan lensa kamera dengan kain microfiber setelah digunakan. Simpan pada suhu ruangan, jauh dari sinar matahari langsung dan kelembapan tinggi.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    // Minta data terbaru dari alat (suhu, daya, kamera) jika sedang terhubung.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(deviceServiceProvider).requestDeviceInfo();
    });
  }

  @override
  void dispose() {
    _dotController.dispose();
    super.dispose();
  }

  static String _labelModel(Object? tipe) {
    switch (tipe) {
      case 'tflite':
        return 'TFLite (aktif)';
      case 'keras':
        return 'Keras (aktif)';
      case 'keras-unsure':
        return 'Keras (simulasi)';
      case 'sim':
        return 'Simulasi';
      default:
        return '—';
    }
  }

  static String _labelUptime(Object? detik) {
    if (detik is! num) return '—';
    final menit = detik ~/ 60;
    final jam = menit ~/ 60;
    return jam > 0 ? '$jam jam ${menit % 60} menit' : '$menit menit';
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final status = ref.watch(deviceStatusProvider);
    final connected = const {
      DeviceConnectionState.connected,
      DeviceConnectionState.capturing,
      DeviceConnectionState.transferring,
      DeviceConnectionState.done,
    }.contains(status);
    // Data hanya dari alat yang sedang terhubung — tanpa angka karangan.
    final info = connected ? ref.watch(deviceInfoProvider).value : null;
    final namaBt = ref.read(deviceServiceProvider).connectedDevice?.name;

    final suhu = info?['cpu_temp_c'];
    final dayaSub = info == null
        ? '—'
        : info['undervoltage_now'] == true
            ? 'Tegangan kurang!'
            : info['undervoltage_since_boot'] == true
                ? 'Pernah kurang'
                : 'Normal';
    final kamera = info?['camera_detected'];
    final modelUv = info?['model_uv'];
    final modelWhite = info?['model_white'];
    final modelAktif = modelUv == 'tflite' || modelUv == 'keras';
    final modelSim = const {'sim', 'keras-unsure'}.contains(modelUv) ||
        const {'sim', 'keras-unsure'}.contains(modelWhite);

    final specs = <Map<String, String>>[
      {'label': 'Papan', 'value': (info?['board'] as String?) ?? '—'},
      {'label': 'Nomor Seri', 'value': (info?['serial'] as String?) ?? '—'},
      {'label': 'Nama Bluetooth', 'value': connected ? (namaBt ?? '—') : '—'},
      {
        'label': 'Kamera',
        'value': kamera == true
            ? 'Terdeteksi'
            : kamera == false
                ? 'Tidak terdeteksi'
                : '—',
      },
      {'label': 'Model AI (UV)', 'value': _labelModel(modelUv)},
      {'label': 'Model AI (Cahaya Putih)', 'value': _labelModel(modelWhite)},
      {'label': 'Lama Menyala', 'value': _labelUptime(info?['uptime_s'])},
      {'label': 'Iluminasi', 'value': 'LED UV 365 nm & LED putih'},
      {'label': 'Konektivitas', 'value': 'Bluetooth Classic (Offline)'},
    ];

    return Container(
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
              boxShadow: [BoxShadow(color: Color(0x0D000000), blurRadius: 12, offset: Offset(0, 2))],
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => widget.navigate('dashboard'),
                  child: Container(
                    width: 40, height: 40,
                    decoration: const BoxDecoration(color: Color(0xFFF0FAFA), shape: BoxShape.circle),
                    child: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0A858C), size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Informasi Perangkat',
                      style: TextStyle(color: Color(0xFF1F2937), fontSize: 17, fontWeight: FontWeight.w700)),
                    Text('BC-Care UV-Scan Pro',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              child: Column(
                children: [
                  // Device status card
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0A858C).withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Column(
                      children: [
                        // Gradient header
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment(-0.7, -1),
                              end: Alignment(0.7, 1),
                              colors: [Color(0xFF0B757B), Color(0xFF0A858C), Color(0xFF36B8B7)],
                              stops: [0, 0.55, 1.0],
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 50, height: 50,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 24),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text('BC-Care',
                                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15.5)),
                                              Text('SN: ${(info?['serial'] as String?) ?? '—'}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(color: Colors.white60, fontSize: 12)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      AnimatedBuilder(
                                        animation: _dotController,
                                        builder: (_, __) {
                                          return Opacity(
                                            opacity: connected
                                                ? Tween<double>(begin: 0.35, end: 1.0).evaluate(_dotController)
                                                : 1.0,
                                            child: Container(
                                              width: 9, height: 9,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: connected ? const Color(0xFF77DAD7) : Colors.white38,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(width: 6),
                                      Text(connected ? 'Terhubung' : 'Tidak terhubung',
                                        style: TextStyle(
                                          color: connected ? const Color(0xFF77DAD7) : Colors.white70,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              // Status indicators (data asli dari alat)
                              Row(
                                children: [
                                  for (final item in [
                                    {
                                      'icon': info?['undervoltage_now'] == true
                                          ? Icons.power_off_rounded
                                          : Icons.power_rounded,
                                      'value': 'Adaptor',
                                      'sub': dayaSub,
                                    },
                                    {
                                      'icon': connected
                                          ? Icons.bluetooth_connected_rounded
                                          : Icons.bluetooth_disabled_rounded,
                                      'value': 'Bluetooth',
                                      'sub': connected ? 'Terhubung' : 'Terputus',
                                    },
                                    {
                                      'icon': Icons.thermostat_rounded,
                                      'value': suhu is num ? '${suhu.toStringAsFixed(1)}°C' : '—',
                                      'sub': 'Suhu CPU',
                                    },
                                  ])
                                    Expanded(
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(horizontal: 5),
                                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.14),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: Colors.white.withOpacity(0.15)),
                                        ),
                                        child: Column(
                                          children: [
                                            Icon(item['icon'] as IconData, color: Colors.white, size: 16),
                                            const SizedBox(height: 5),
                                            Text(item['value'] as String,
                                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                                            Text(item['sub'] as String,
                                              style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 10)),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Model AI row (menggantikan "Status Kalibrasi" palsu)
                        Container(
                          color: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.memory_rounded, color: Color(0xFF0A858C), size: 15),
                                  SizedBox(width: 8),
                                  Text('Model AI', style: TextStyle(color: Color(0xFF4B5563), fontSize: 13)),
                                ],
                              ),
                              Text(
                                info == null
                                    ? '—'
                                    : modelSim
                                        ? 'SIMULASI'
                                        : modelAktif
                                            ? 'Aktif'
                                            : _labelModel(modelUv),
                                style: TextStyle(
                                  color: modelSim
                                      ? const Color(0xFFD97706)
                                      : info == null
                                          ? const Color(0xFF94A3B8)
                                          : const Color(0xFF059669),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!connected)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: const Text(
                        'Alat belum terhubung. Alat dihubungkan lewat Skrining Baru (Skin Risk Assessment → Info Lesi → Koneksi). Setelah terhubung, data perangkat (nomor seri, suhu, daya, kamera, dan model AI) tampil di sini.',
                        style: TextStyle(color: Color(0xFF6B7280), fontSize: 12, height: 1.5),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: OutlinedButton.icon(
                        onPressed: () => matikanAlatDenganKonfirmasi(context, ref),
                        icon: const Icon(Icons.power_settings_new_rounded,
                            color: Color(0xFFDC2626), size: 18),
                        label: const Text(
                          'Matikan Alat',
                          style: TextStyle(
                            color: Color(0xFFDC2626),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Color(0xFFFECACA)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  // BC-Care info banner
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE6F7F7), Color(0xFFD1F2F0)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF77DAD7).withOpacity(0.5), width: 1.2),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A858C).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.info_rounded, color: Color(0xFF0A858C), size: 18),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Tentang Teknologi BC-Care',
                                style: TextStyle(color: Color(0xFF0B757B), fontWeight: FontWeight.w700, fontSize: 13)),
                              SizedBox(height: 4),
                              Text(
                                'BC-Care memotret lesi kulit dengan penerangan LED UV 365 nm atau cahaya putih, lalu model AI (CNN EfficientNetB3) yang berjalan di Raspberry Pi memperkirakan kategori NORMAL atau BCC (Karsinoma Sel Basal). Hasil bersifat skrining awal, bukan diagnosis; akurasi model belum divalidasi secara klinis.',
                                style: TextStyle(color: Color(0xFF0B757B), fontSize: 11.2, height: 1.45),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Technical specs
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 2))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Spesifikasi Teknis',
                          style: TextStyle(color: Color(0xFF1F2937), fontSize: 14.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        ...specs.asMap().entries.map((e) {
                          return Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(e.value['label']!, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                                    const SizedBox(width: 12),
                                    Flexible(
                                      child: Text(e.value['value']!,
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(color: Color(0xFF374151), fontSize: 12, fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ),
                              ),
                              if (e.key < specs.length - 1)
                                const Divider(height: 1, color: Color(0xFFF9FAFB)),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                  // User guide accordion
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 2))],
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Column(
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Panduan Penggunaan',
                              style: TextStyle(color: Color(0xFF1F2937), fontSize: 14.5, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const Divider(height: 1, color: Color(0xFFF9FAFB)),
                        ...guides.asMap().entries.map((e) {
                          final i = e.key;
                          final guide = e.value;
                          final isOpen = expanded == i;
                          return Column(
                            children: [
                              GestureDetector(
                                onTap: () => setState(() => expanded = isOpen ? null : i),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  color: Colors.transparent,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(guide['title']!,
                                        style: const TextStyle(color: Color(0xFF374151), fontSize: 13, fontWeight: FontWeight.w600)),
                                      Icon(
                                        isOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                        color: isOpen ? const Color(0xFF0A858C) : const Color(0xFF94A3B8),
                                        size: 16,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                                child: isOpen
                                    ? Padding(
                                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                        child: Text(
                                          guide['content']!,
                                          style: const TextStyle(
                                            color: Color(0xFF6B7280),
                                            fontSize: 12,
                                            height: 1.6,
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                              if (i < guides.length - 1)
                                const Divider(height: 1, color: Color(0xFFF9FAFB)),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          BottomNav(current: 'device', navigate: widget.navigate),
        ],
      ),
    );
  }
}

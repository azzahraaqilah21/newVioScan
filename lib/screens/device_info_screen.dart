import 'package:flutter/material.dart';
import '../widgets/bottom_nav.dart';

class DeviceInfoScreen extends StatefulWidget {
  final Function(String) navigate;
  const DeviceInfoScreen({super.key, required this.navigate});

  @override
  State<DeviceInfoScreen> createState() => _DeviceInfoScreenState();
}

class _DeviceInfoScreenState extends State<DeviceInfoScreen>
    with SingleTickerProviderStateMixin {
  int? expanded = 0;
  late AnimationController _dotController;

  final List<Map<String, String>> specs = [
    {'label': 'Model', 'value': 'BC-Care UV-Scan Pro'},
    {'label': 'Firmware', 'value': 'v3.2.1 (Terbaru)'},
    {'label': 'Panjang Gelombang UV', 'value': '365 nm ± 5 nm'},
    {'label': 'Model CNN', 'value': 'BCC-Net v3.2'},
    {'label': 'Sensitivitas', 'value': '94.8%'},
    {'label': 'Spesifisitas', 'value': '91.3%'},
    {'label': 'Resolusi Gambar', 'value': '12 MP UV'},
    {'label': 'Konektivitas', 'value': 'Bluetooth Classic (Offline)'},
  ];

  final List<Map<String, String>> guides = [
    {
      'title': 'Persiapan Skrining',
      'content': 'Bersihkan area kulit yang akan diperiksa dari riasan, losion, atau krim. Pastikan ruangan minim cahaya ambien. Pegang perangkat BC-Care tegak lurus 3–5 cm dari permukaan kulit. Minta pasien tetap diam selama proses pengambilan gambar berlangsung.',
    },
    {
      'title': 'Kalibrasi Perangkat',
      'content': 'Letakkan perangkat pada pad kalibrasi yang tersedia dalam kit. Tekan dan tahan tombol power selama 3 detik hingga LED berubah warna biru, menandakan mode kalibrasi aktif. Tunggu 30 detik hingga kalibrasi otomatis selesai sebelum memulai skrining.',
    },
    {
      'title': 'Interpretasi Hasil',
      'content': 'Akurasi CNN ≥80% dianggap andal secara klinis. Risiko Rendah (hijau): jaringan normal, edukasi preventif. Risiko Sedang (kuning): monitoring 4–6 minggu, pertimbangkan rujukan. Risiko Tinggi (merah): rujuk segera ke SpKK dalam 1–2 minggu — buat surat rujukan BPJS ke FKRTL.',
    },
    {
      'title': 'Perawatan Perangkat',
      'content': 'Bersihkan lensa UV dengan kain microfiber yang tersedia setelah setiap penggunaan. Isi ulang baterai saat di bawah 20%. Simpan dalam kotak pelindung pada suhu ruangan (15–30°C), jauh dari sinar matahari langsung dan kelembapan tinggi. Lakukan pengecekan kalibrasi setiap 30 hari.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _dotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _dotController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

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
                                  Row(
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
                                      const Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('BC-Care',
                                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15.5)),
                                          Text('UV-Scan Pro · SN: FLR-2024-0482',
                                            style: TextStyle(color: Colors.white60, fontSize: 12)),
                                        ],
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      AnimatedBuilder(
                                        animation: _dotController,
                                        builder: (_, __) {
                                          return Opacity(
                                            opacity: Tween<double>(begin: 0.35, end: 1.0).evaluate(_dotController),
                                            child: Container(
                                              width: 9, height: 9,
                                              decoration: const BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Color(0xFF77DAD7),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(width: 6),
                                      const Text('Aktif',
                                        style: TextStyle(color: Color(0xFF77DAD7), fontSize: 13, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              // Status indicators
                              Row(
                                children: [
                                  for (final item in [
                                    {'icon': Icons.battery_charging_full_rounded, 'label': 'Battery', 'value': '87%', 'sub': 'Charging'},
                                    {'icon': Icons.bluetooth_rounded, 'label': 'Koneksi', 'value': 'Bluetooth', 'sub': 'Classic SPP'},
                                    {'icon': Icons.radar_rounded, 'label': 'UV Sensor', 'value': 'Ready', 'sub': '365nm'},
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
                        // Calibration row
                        Container(
                          color: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.settings_rounded, color: Color(0xFF0A858C), size: 15),
                                  SizedBox(width: 8),
                                  Text('Status Kalibrasi', style: TextStyle(color: Color(0xFF4B5563), fontSize: 13)),
                                ],
                              ),
                              Row(
                                children: [
                                  Icon(Icons.refresh_rounded, color: Color(0xFF22C55E), size: 12),
                                  SizedBox(width: 6),
                                  Text('Terkalibrasi',
                                    style: TextStyle(color: Color(0xFF059669), fontSize: 12, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
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
                                'BC-Care menggunakan CNN berbasis deep learning yang dilatih pada 5000+ citra dermoskopi untuk deteksi dini Karsinoma Sel Basal (BCC) via fluorosensi UV 365nm, dengan sensitivitas 94.8% dan spesifisitas 91.3% (uji klinis multisenter, 2024).',
                                style: TextStyle(color: Color(0xff0b757b72), fontSize: 11.2, height: 1.45),
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
                                    Text(e.value['value']!, style: const TextStyle(color: Color(0xFF374151), fontSize: 12, fontWeight: FontWeight.w600)),
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

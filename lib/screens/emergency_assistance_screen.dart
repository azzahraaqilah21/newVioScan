import 'package:flutter/material.dart';
import '../widgets/bottom_nav.dart';

class EmergencyAssistanceScreen extends StatefulWidget {
  final Function(String) navigate;
  const EmergencyAssistanceScreen({super.key, required this.navigate});

  @override
  State<EmergencyAssistanceScreen> createState() =>
      _EmergencyAssistanceScreenState();
}

class _EmergencyAssistanceScreenState extends State<EmergencyAssistanceScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _borderController;
  late Animation<Color?> _borderAnimation;

  final List<Map<String, dynamic>> hotlines = [
    {'name': 'Gawat Darurat Medis', 'number': '119', 'available': '24 Jam / 7 Hari', 'category': 'Darurat', 'color': const Color(0xFFDC2626), 'bg': const Color(0xFFFEF2F2)},
    {'name': 'Yayasan Kanker Indonesia', 'number': '1500-331', 'available': 'Sen–Jum 08:00–17:00', 'category': 'Onkologi', 'color': const Color(0xFFD97706), 'bg': const Color(0xFFFFFBEB)},
    {'name': 'Poli Kulit RSUD / RS Rujukan', 'number': '(021) 500-135', 'available': 'Sen–Sab 08:00–15:00', 'category': 'Dermatologi', 'color': const Color(0xFF0A858C), 'bg': const Color(0xFFE6F7F7)},
    {'name': 'Hotline Kesehatan Kemenkes RI', 'number': '1500-567', 'available': 'Sen–Jum 07:00–21:00', 'category': 'Kesehatan Kulit', 'color': const Color(0xFF7C3AED), 'bg': const Color(0xFFF5F3FF)},
  ];

  final List<String> selfCareTips = [
    'Hindari paparan sinar UV/matahari langsung pada area lesi yang mencurigakan',
    'Dokumentasikan perubahan lesi dengan foto berskala setiap minggu',
    'Jangan oleskan krim, obat, atau bahan apapun pada lesi tanpa instruksi dokter',
    'Jaga kebersihan area lesi, hindari menggaruk atau menekan lesi',
  ];

  @override
  void initState() {
    super.initState();
    _borderController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
    _borderAnimation = ColorTween(
      begin: const Color(0xFFFECACA),
      end: const Color(0xFFEF4444),
    ).animate(_borderController);
  }

  @override
  void dispose() {
    _borderController.dispose();
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
                    Text('Emergency Assistance',
                      style: TextStyle(color: Color(0xFF1F2937), fontSize: 17, fontWeight: FontWeight.w700)),
                    Text('Akses cepat bantuan medis',
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
                  // High-risk alert banner
                  AnimatedBuilder(
                    animation: _borderAnimation,
                    builder: (_, __) {
                      return Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _borderAnimation.value!, width: 2),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.shield_rounded, color: Color(0xFFDC2626), size: 22),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Protokol Risiko Tinggi BCC',
                                    style: TextStyle(color: Color(0xFF991B1B), fontWeight: FontWeight.w700, fontSize: 14)),
                                  SizedBox(height: 4),
                                  Text(
                                    'Jika hasil skrining menunjukkan RISIKO TINGGI, segera rujuk pasien ke dokter Spesialis Kulit (SpKK) dalam 1–2 minggu. Deteksi dini meningkatkan tingkat kesembuhan BCC hingga 95% (NCCN 2024).',
                                    style: TextStyle(color: Color(0xFFDC2626), fontSize: 12, height: 1.5),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  // Emergency hotline button
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: GestureDetector(
                      onTap: () {},
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFB91C1C), Color(0xFFDC2626), Color(0xFFEF4444)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFDC2626).withOpacity(0.35),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            )
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 58, height: 58,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.22),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Icon(Icons.phone_rounded, color: Colors.white, size: 28),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Hotline Gawat Darurat', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                  Text('Gawat Darurat Medis 119',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                                  Text('Tersedia 24 jam / 7 hari seminggu',
                                    style: TextStyle(color: Colors.white60, fontSize: 11.5)),
                                ],
                              ),
                            ),
                            _PulsingPhoneIcon(),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Find nearby clinic button
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: GestureDetector(
                      onTap: () {},
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0A858C), Color(0xFF36B8B7)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0A858C).withOpacity(0.3),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            )
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 58, height: 58,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.22),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 28),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Klinik Dermatologi', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                  Text('Temukan Klinik Terdekat',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                                  Text('Pencari klinik dermatologi terdekat',
                                    style: TextStyle(color: Colors.white60, fontSize: 11.5)),
                                ],
                              ),
                            ),
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.2),
                              ),
                              child: const Icon(Icons.location_on_rounded, color: Colors.white, size: 16),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Medical hotlines
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
                            child: Text('Hotline Medis',
                              style: TextStyle(color: Color(0xFF1F2937), fontSize: 14.5, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        ...hotlines.asMap().entries.map((e) {
                          final h = e.value;
                          return Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 42, height: 42,
                                      decoration: BoxDecoration(
                                        color: h['bg'] as Color,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(Icons.phone_rounded, color: h['color'] as Color, size: 17),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(h['name'] as String,
                                            style: const TextStyle(color: Color(0xFF1F2937), fontSize: 13, fontWeight: FontWeight.w600)),
                                          Row(
                                            children: [
                                              Text(h['number'] as String,
                                                style: TextStyle(color: h['color'] as Color, fontSize: 12.5, fontWeight: FontWeight.w700)),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: h['bg'] as Color,
                                                  borderRadius: BorderRadius.circular(100),
                                                ),
                                                child: Text(h['category'] as String,
                                                  style: TextStyle(color: h['color'] as Color, fontSize: 9.5, fontWeight: FontWeight.w700)),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.access_time_rounded, color: Color(0xFF94A3B8), size: 10),
                                            const SizedBox(width: 4),
                                            Text(h['available'] as String,
                                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10)),
                                          ],
                                        ),
                                        const Icon(Icons.chevron_right_rounded, color: Color(0xFFD1D5DB), size: 14),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (e.key < hotlines.length - 1)
                                const Divider(height: 1, color: Color(0xFFF9FAFB)),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
                  // Self-care tips
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
                        Row(
                          children: [
                            Container(
                              width: 34, height: 34,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.favorite_rounded, color: Color(0xFFDC2626), size: 16),
                            ),
                            const SizedBox(width: 8),
                            const Text('Panduan Sementara untuk Pasien',
                              style: TextStyle(color: Color(0xFF1F2937), fontSize: 14.5, fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ...selfCareTips.asMap().entries.map((e) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 22, height: 22,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFFE6F7F7),
                                  ),
                                  child: Center(
                                    child: Text('${e.key + 1}',
                                      style: const TextStyle(color: Color(0xFF0A858C), fontSize: 10, fontWeight: FontWeight.w800)),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(e.value,
                                    style: const TextStyle(color: Color(0xFF4B5563), fontSize: 12.5, height: 1.5)),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  // Disclaimer
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: const Text(
                      '⚠️ Catatan: VioScan BC-Care adalah alat bantu skrining dan tidak menggantikan penilaian klinis dokter. Untuk kondisi darurat medis, selalu hubungi 119 segera.',
                      style: TextStyle(color: Color(0xFF92400E), fontSize: 11, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          BottomNav(current: 'emergency', navigate: widget.navigate),
        ],
      ),
    );
  }
}

class _PulsingPhoneIcon extends StatefulWidget {
  @override
  State<_PulsingPhoneIcon> createState() => _PulsingPhoneIconState();
}

class _PulsingPhoneIconState extends State<_PulsingPhoneIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Transform.scale(
          scale: Tween<double>(begin: 1.0, end: 1.12).evaluate(_ctrl),
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.2),
            ),
            child: const Icon(Icons.phone_rounded, color: Colors.white, size: 16),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import '../widgets/bottom_nav.dart';

class ScanHistoryScreen extends StatefulWidget {
  final Function(String) navigate;
  const ScanHistoryScreen({super.key, required this.navigate});

  @override
  State<ScanHistoryScreen> createState() => _ScanHistoryScreenState();
}

class _ScanHistoryScreenState extends State<ScanHistoryScreen>
    with SingleTickerProviderStateMixin {
  String filter = 'all';
  String search = '';

  final List<Map<String, dynamic>> scans = [
    {'id': 1, 'date': '31 Mei 2026', 'time': '09:15 WIB', 'location': 'Lengan Kiri', 'risk': 'low', 'confidence': 92.4},
    {'id': 2, 'date': '28 Mei 2026', 'time': '10:32 WIB', 'location': 'Bahu Kanan', 'risk': 'moderate', 'confidence': 78.1},
    {'id': 3, 'date': '20 Mei 2026', 'time': '14:45 WIB', 'location': 'Punggung Atas', 'risk': 'low', 'confidence': 88.9},
    {'id': 4, 'date': '12 Mei 2026', 'time': '11:00 WIB', 'location': 'Pipi Kiri', 'risk': 'high', 'confidence': 85.3},
    {'id': 5, 'date': '05 Mei 2026', 'time': '15:30 WIB', 'location': 'Lengan Kanan', 'risk': 'low', 'confidence': 94.1},
    {'id': 6, 'date': '28 Apr 2026', 'time': '09:00 WIB', 'location': 'Tangan Kiri', 'risk': 'moderate', 'confidence': 71.6},
    {'id': 7, 'date': '15 Apr 2026', 'time': '16:15 WIB', 'location': 'Batang Hidung', 'risk': 'low', 'confidence': 96.2},
    {'id': 8, 'date': '02 Apr 2026', 'time': '13:00 WIB', 'location': 'Telinga Kiri', 'risk': 'low', 'confidence': 90.8},
  ];

  final Map<String, Map<String, dynamic>> riskConfig = {
    'low': {'label': 'Rendah', 'bg': const Color(0xFFECFDF5), 'text': const Color(0xFF059669), 'border': const Color(0xFFA7F3D0), 'emoji': '✓'},
    'moderate': {'label': 'Sedang', 'bg': const Color(0xFFFFFBEB), 'text': const Color(0xFFD97706), 'border': const Color(0xFFFDE68A), 'emoji': '⚠'},
    'high': {'label': 'Tinggi', 'bg': const Color(0xFFFEF2F2), 'text': const Color(0xFFDC2626), 'border': const Color(0xFFFECACA), 'emoji': '!'},
  };

  List<Map<String, dynamic>> get filtered {
    return scans.where((s) {
      final matchFilter = filter == 'all' || s['risk'] == filter;
      final matchSearch = search.isEmpty ||
          (s['location'] as String).toLowerCase().contains(search.toLowerCase()) ||
          (s['date'] as String).toLowerCase().contains(search.toLowerCase());
      return matchFilter && matchSearch;
    }).toList();
  }

  Map<String, int> get counts {
    final c = {'all': scans.length, 'low': 0, 'moderate': 0, 'high': 0};
    for (final s in scans) {
      c[s['risk'] as String] = (c[s['risk'] as String] ?? 0) + 1;
    }
    return c;
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final filteredList = filtered;

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
            child: Column(
              children: [
                Row(
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Riwayat Skrining',
                            style: TextStyle(color: Color(0xFF1F2937), fontSize: 17, fontWeight: FontWeight.w700)),
                          Text('${scans.length} total skrining',
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                        ],
                      ),
                    ),
                    Container(
                      width: 38, height: 38,
                      decoration: const BoxDecoration(color: Color(0xFFF0FAFA), shape: BoxShape.circle),
                      child: const Icon(Icons.tune_rounded, color: Color(0xFF0A858C), size: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Search
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FAFA),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 15),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          onChanged: (v) => setState(() => search = v),
                          decoration: const InputDecoration(
                            hintText: 'Cari berdasarkan lokasi atau tanggal...',
                            hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
                        ),
                      ),
                    ],
                  ),
                ),
                // Filter pills
                Row(
                  children: [
                    for (final f in [
                      {'id': 'all', 'label': 'Semua'},
                      {'id': 'low', 'label': 'Rendah'},
                      {'id': 'moderate', 'label': 'Sedang'},
                      {'id': 'high', 'label': 'Tinggi'},
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: GestureDetector(
                          onTap: () => setState(() => filter = f['id']!),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: filter == f['id'] ? const Color(0xFF0A858C) : const Color(0xFFF0FAFA),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              f['id'] == 'all'
                                  ? 'Semua'
                                  : '${f['label']} (${counts[f['id']] ?? 0})',
                              style: TextStyle(
                                color: filter == f['id'] ? Colors.white : const Color(0xFF6B7280),
                                fontSize: 12,
                                fontWeight: filter == f['id'] ? FontWeight.w700 : FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // List
          Expanded(
            child: filteredList.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 60, height: 60,
                          decoration: const BoxDecoration(color: Color(0xFFF3F4F6), shape: BoxShape.circle),
                          child: const Icon(Icons.search_rounded, color: Color(0xFF9CA3AF), size: 24),
                        ),
                        const SizedBox(height: 14),
                        const Text('Tidak ada skrining ditemukan',
                          style: TextStyle(color: Color(0xFF6B7280), fontSize: 14)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                    itemCount: filteredList.length,
                    itemBuilder: (_, i) {
                      final scan = filteredList[i];
                      final rc = riskConfig[scan['risk']]!;
                      return _ScanCard(
                        scan: scan,
                        rc: rc,
                        onTap: () => widget.navigate('result'),
                        index: i,
                      );
                    },
                  ),
          ),
          BottomNav(current: 'history', navigate: widget.navigate),
        ],
      ),
    );
  }
}

class _ScanCard extends StatefulWidget {
  final Map<String, dynamic> scan;
  final Map<String, dynamic> rc;
  final VoidCallback onTap;
  final int index;

  const _ScanCard({required this.scan, required this.rc, required this.onTap, required this.index});

  @override
  State<_ScanCard> createState() => _ScanCardState();
}

class _ScanCardState extends State<_ScanCard> with SingleTickerProviderStateMixin {
  late AnimationController _barController;
  late Animation<double> _barAnim;

  @override
  void initState() {
    super.initState();
    _barController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _barAnim = Tween<double>(begin: 0, end: (widget.scan['confidence'] as double) / 100)
        .animate(CurvedAnimation(parent: _barController, curve: Curves.easeOut));
    Future.delayed(Duration(milliseconds: widget.index * 45), () {
      if (mounted) _barController.forward();
    });
  }

  @override
  void dispose() {
    _barController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scan = widget.scan;
    final rc = widget.rc;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: rc['bg'] as Color,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: rc['border'] as Color, width: 1.5),
              ),
              child: Center(
                child: Text(
                  rc['emoji'] as String,
                  style: TextStyle(
                    color: rc['text'] as Color,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        scan['location'] as String,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: rc['bg'] as Color,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(color: rc['border'] as Color),
                        ),
                        child: Text(
                          rc['label'] as String,
                          style: TextStyle(
                            color: rc['text'] as Color,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${scan['date']} · ${scan['time']}',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: AnimatedBuilder(
                            animation: _barAnim,
                            builder: (_, __) {
                              return LinearProgressIndicator(
                                value: _barAnim.value,
                                backgroundColor: const Color(0xFFF3F4F6),
                                valueColor: AlwaysStoppedAnimation(rc['text'] as Color),
                                minHeight: 4,
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${scan['confidence']}%',
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFCBD5E1), size: 15),
          ],
        ),
      ),
    );
  }
}

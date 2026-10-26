import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/screening_model.dart';
import '../providers/screening_provider.dart';
import '../widgets/bottom_nav.dart';

class ScanHistoryScreen extends ConsumerStatefulWidget {
  final Function(String) navigate;
  const ScanHistoryScreen({super.key, required this.navigate});

  @override
  ConsumerState<ScanHistoryScreen> createState() => _ScanHistoryScreenState();
}

class _ScanHistoryScreenState extends ConsumerState<ScanHistoryScreen>
    with SingleTickerProviderStateMixin {
  String filter = 'all';
  String search = '';

  static final _dateFmt = DateFormat('dd MMM yyyy', 'id_ID');
  static final _timeFmt = DateFormat('HH:mm', 'id_ID');

  // Diisi di build() dari Firestore (users/{uid}/screenings).
  List<Map<String, dynamic>> scans = [];

  Map<String, dynamic> _toCardData(ScreeningModel s) {
    return {
      'model': s,
      'date': _dateFmt.format(s.screeningDate),
      'time': '${_timeFmt.format(s.screeningDate)} WIB',
      'location': s.lesionLocation,
      'risk': riskConfig.containsKey(s.riskLevel) ? s.riskLevel : 'moderate',
      'confidence': double.parse(s.confidence.toStringAsFixed(1)),
      'simulated': s.isSimulated,
    };
  }

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

  void _showDetail(ScreeningModel s, Map<String, dynamic> rc) {
    final imageUrl = s.fluorescenceImageUrl ?? s.imageUrl;
    final when =
        '${_dateFmt.format(s.screeningDate)} · ${_timeFmt.format(s.screeningDate)} WIB';

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 90,
                child: Text(label,
                    style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12.5)),
              ),
              Expanded(
                child: Text(value,
                    style: const TextStyle(
                        color: Color(0xFF1F2937),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.prediction,
                  style: TextStyle(
                      color: rc['text'] as Color,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('${s.lesionLocation} · $when',
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
              if (s.isSimulated) ...[
                const SizedBox(height: 10),
                const Text('HASIL SIMULASI — bukan diagnosis.',
                    style: TextStyle(
                        color: Color(0xFFB45309),
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ],
              if (s.rawImageBytes != null) ...[
                // Foto tersimpan di dokumen Firestore (base64).
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(
                    s.rawImageBytes!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),
              ] else if (imageUrl != null) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const SizedBox(
                      height: 60,
                      child: Center(child: Text('Foto tidak dapat dimuat')),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              row('Risiko', rc['label'] as String),
              row('Keyakinan', '${s.confidence.toStringAsFixed(1)}%'),
              row('Mode', (s.mode ?? 'uv').toUpperCase()),
              if (s.lesionNotes != null && s.lesionNotes!.isNotEmpty)
                row('Catatan', s.lesionNotes!),
              const SizedBox(height: 10),
              const Text('Rekomendasi',
                  style: TextStyle(
                      color: Color(0xFF1F2937),
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(s.recommendation,
                  style: const TextStyle(
                      color: Color(0xFF4B5563), fontSize: 12.5, height: 1.5)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final screeningsAsync = ref.watch(screeningsStreamProvider);
    scans = (screeningsAsync.value ?? const <ScreeningModel>[])
        .map(_toCardData)
        .toList();
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
            child: screeningsAsync.isLoading && !screeningsAsync.hasValue
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF0A858C)),
                  )
                : screeningsAsync.hasError && !screeningsAsync.hasValue
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Gagal memuat riwayat: ${screeningsAsync.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
                      ),
                    ),
                  )
                : filteredList.isEmpty
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
                        Text(
                          scans.isEmpty
                              ? 'Belum ada hasil skrining tersimpan'
                              : 'Tidak ada skrining ditemukan',
                          style: const TextStyle(color: Color(0xFF6B7280), fontSize: 14)),
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
                        // Key per dokumen: saat stream Firestore berubah,
                        // animasi kartu tidak memakai data kartu lain.
                        key: ValueKey((scan['model'] as ScreeningModel).id),
                        scan: scan,
                        rc: rc,
                        onTap: () =>
                            _showDetail(scan['model'] as ScreeningModel, rc),
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

  const _ScanCard({super.key, required this.scan, required this.rc, required this.onTap, required this.index});

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
                      Flexible(
                        child: Text(
                          scan['location'] as String,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: Color(0xFF1F2937),
                          ),
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
                  if (scan['simulated'] == true)
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text(
                        'Hasil simulasi — bukan diagnosis',
                        style: TextStyle(
                          color: Color(0xFFD97706),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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

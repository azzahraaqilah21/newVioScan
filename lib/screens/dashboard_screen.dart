import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../widgets/bottom_nav.dart';
import '../providers/auth_provider.dart';
import '../providers/screening_provider.dart';
import '../providers/device_provider.dart';
import '../services/device_service.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  final Function(String) navigate;
  const DashboardScreen({super.key, required this.navigate});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _dotController;

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

  final List<Map<String, dynamic>> quickCards = [
    {
      'id': 'history',
      'icon': Icons.access_time_rounded,
      'label': 'Riwayat Skrining',
      'desc': 'Lihat histori',
      'color': const Color(0xFF0A858C),
      'bg': const Color(0xFFE6F7F7),
    },
    {
      'id': 'device',
      'icon': Icons.bluetooth_rounded,
      'label': 'VioTech',
      'desc': 'Info perangkat',
      'color': const Color(0xFF36B8B7),
      'bg': const Color(0xFFEBF9F9),
    },
    {
      'id': 'about_bcc',
      'icon': Icons.info_outline_rounded,
      'label': 'About BCC',
      'desc': 'Pelajari BCC',
      'color': const Color(0xFF0B757B),
      'bg': const Color(0xFFE4F6F6),
    },
    {
      'id': 'profile',
      'icon': Icons.person_rounded,
      'label': 'Profil',
      'desc': 'Akun saya',
      'color': const Color(0xFF7C3AED),
      'bg': const Color(0xFFF5F3FF),
    },
  ];

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Selamat pagi,';
    if (hour < 17) return 'Selamat siang,';
    return 'Selamat malam,';
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '—';
    return DateFormat('dd MMM yyyy · HH:mm').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final userAsync = ref.watch(currentUserProvider);
    final statsAsync = ref.watch(userStatsProvider);

    final displayName = userAsync.when(
      data: (u) => u?.displayName ?? 'VioScan User',
      loading: () => '...',
      error: (_, __) => 'VioScan User',
    );
    final photoURL = userAsync.when(
      data: (u) => u?.photoURL,
      loading: () => null,
      error: (_, __) => null,
    );
    final initials = displayName.isNotEmpty
        ? displayName.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase()
        : 'VS';

    return Container(
      color: const Color(0xFFF0FAFA),
      child: Column(
        children: [
          // Header gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-0.7, -1),
                end: Alignment(0.7, 1),
                colors: [Color(0xFF0B757B), Color(0xFF0A858C), Color(0xFF36B8B7)],
                stops: [0.0, 0.55, 1.0],
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
            ),
            padding: EdgeInsets.only(
              top: topPad + 14,
              left: 20,
              right: 20,
              bottom: 24,
            ),
            child: Column(
              children: [
                // Top row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getGreeting(),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.65),
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '$displayName 👋',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Avatar — tappable → profile
                    GestureDetector(
                      onTap: () => widget.navigate('profile'),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.22),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.35),
                            width: 2,
                          ),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: photoURL != null
                            ? CachedNetworkImage(
                                imageUrl: photoURL,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Center(
                                  child: Text(
                                    initials,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                errorWidget: (_, __, ___) => Center(
                                  child: Text(
                                    initials,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              )
                            : Center(
                                child: Text(
                                  initials,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                // Device connection status — baca dari koneksi Bluetooth hardware
                Consumer(
                  builder: (context, ref, _) {
                    final deviceState = ref.watch(deviceStatusProvider);
                    final connectedDevice = ref.watch(
                      deviceServiceProvider.select((s) => s.connectedDevice),
                    );

                    final isConnected =
                        deviceState == DeviceConnectionState.connected ||
                        deviceState == DeviceConnectionState.capturing ||
                        deviceState == DeviceConnectionState.transferring ||
                        deviceState == DeviceConnectionState.done;

                    final isConnecting =
                        deviceState == DeviceConnectionState.connecting ||
                        deviceState == DeviceConnectionState.scanning;

                    final statusLabel = isConnected
                        ? 'Connected'
                        : isConnecting
                            ? 'Menghubungkan...'
                            : 'Disconnected';

                    // Ditampilkan di atas "pil" putih agar jelas terbaca
                    // di header teal.
                    final statusColor = isConnected
                        ? const Color(0xFF047857)
                        : isConnecting
                            ? const Color(0xFFB45309)
                            : const Color(0xFFB91C1C);

                    final deviceName = connectedDevice?.name ?? 'BC-Care UV-Scan Pro';

                    // Hanya status — koneksi alat dibuka lewat Skrining Baru
                    // (Skin Risk Assessment → Info Lesi → Koneksi).
                    return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                isConnected
                                    ? Icons.bluetooth_connected_rounded
                                    : Icons.bluetooth_disabled_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'VioTech Device',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.85),
                                      fontSize: 11.5,
                                    ),
                                  ),
                                  Text(
                                    isConnected ? deviceName : 'Belum terhubung',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13.5,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Row(
                              children: [
                                if (isConnecting)
                                  SizedBox(
                                    width: 8,
                                    height: 8,
                                    child: CircularProgressIndicator(
                                      color: statusColor,
                                      strokeWidth: 1.5,
                                    ),
                                  )
                                else
                                  AnimatedBuilder(
                                    animation: _dotController,
                                    builder: (_, __) => Opacity(
                                      opacity: isConnected
                                          ? Tween<double>(begin: 0.4, end: 1.0)
                                              .evaluate(_dotController)
                                          : 1.0,
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: statusColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                const SizedBox(width: 6),
                                Text(
                                  statusLabel,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                              ),
                            ),
                          ],
                        ),
                    );
                  },
                ),
              ],
            ),
          ),
          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Start Screening CTA
                  GestureDetector(
                    onTap: () => widget.navigate('assessment'),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF0A858C), Color(0xFF36B8B7)],
                        ),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0A858C).withOpacity(0.35),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          )
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.22),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(Icons.qr_code_scanner_rounded,
                                color: Colors.white, size: 28),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'VioTech Ready',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.65),
                                    fontSize: 11,
                                  ),
                                ),
                                const Text(
                                  'Start Screening',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 19,
                                  ),
                                ),
                                Text(
                                  'UV Fluorescence Analysis',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.6),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.2),
                            ),
                            child: const Icon(Icons.chevron_right_rounded,
                                color: Colors.white, size: 18),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Last Scan Summary (from Firestore)
                  statsAsync.when(
                    data: (stats) {
                      final lastDate = stats['lastDate'] as DateTime?;
                      final lastPrediction =
                          stats['lastPrediction'] as String?;
                      final lastLocation = stats['lastLocation'] as String?;
                      final lastConfidence =
                          stats['lastConfidence'] as double?;
                      final count = stats['count'] as int? ?? 0;

                      return Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 16,
                              offset: const Offset(0, 2),
                            )
                          ],
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Skrining Terakhir',
                                  style: TextStyle(
                                    color: Color(0xFF0B757B),
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (lastDate != null)
                                  GestureDetector(
                                    onTap: () =>
                                        widget.navigate('history'),
                                    child: const Text(
                                      'Lihat Histori',
                                      style: TextStyle(
                                        color: Color(0xFF36B8B7),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (lastDate == null)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF3F4F6),
                                        borderRadius:
                                            BorderRadius.circular(16),
                                      ),
                                      child: const Icon(
                                          Icons.history_rounded,
                                          color: Color(0xFF9CA3AF),
                                          size: 22),
                                    ),
                                    const SizedBox(width: 12),
                                    const Text(
                                      'Belum ada skrining.\nMulai skrining pertama Anda.',
                                      style: TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 12.5,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Row(
                                children: [
                                  Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFA5E6E2),
                                          Color(0xFF77DAD7)
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius:
                                          BorderRadius.circular(18),
                                    ),
                                    child: const Icon(
                                        Icons.show_chart_rounded,
                                        color: Color(0xFF0A858C),
                                        size: 26),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          lastLocation ?? '—',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: Color(0xFF1F2937),
                                          ),
                                        ),
                                        Text(
                                          _formatDate(lastDate),
                                          style: const TextStyle(
                                            color: Color(0xFF94A3B8),
                                            fontSize: 11.5,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Row(
                                          children: [
                                            Container(
                                              width: 7,
                                              height: 7,
                                              decoration: const BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Color(0xFF0A858C),
                                              ),
                                            ),
                                            const SizedBox(width: 5),
                                            Expanded(
                                              child: Text(
                                                lastPrediction ?? '—',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF374151),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (lastConfidence != null) ...[
                                              const SizedBox(width: 8),
                                              Text(
                                                'CNN: ${lastConfidence.toStringAsFixed(1)}%',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF6B7280),
                                                ),
                                              ),
                                            ]
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            if (count > 0) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 7),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE6F7F7),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Total skrining dilakukan',
                                      style: TextStyle(
                                        color: const Color(0xFF0A858C)
                                            .withOpacity(0.75),
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      '$count skrining',
                                      style: const TextStyle(
                                        color: Color(0xFF0A858C),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                    loading: () => Container(
                      padding: const EdgeInsets.all(20),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF0A858C),
                          ),
                        ),
                      ),
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  // Quick Access
                  const Text(
                    'Akses Cepat',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.45,
                    children: quickCards.map((card) {
                      return GestureDetector(
                        onTap: () => widget.navigate(card['id'] as String),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: card['bg'] as Color,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  card['icon'] as IconData,
                                  color: card['color'] as Color,
                                  size: 20,
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    card['label'] as String,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: Color(0xFF1F2937),
                                    ),
                                  ),
                                  Text(
                                    card['desc'] as String,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  // Health tip
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE6F7F7), Color(0xFFD1F2F0)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0xFF77DAD7).withOpacity(0.5),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '💡 Info Klinis',
                          style: TextStyle(
                            color: Color(0xFF0B757B),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Skrining UV rutin setiap bulan membantu deteksi dini BCC. Edukasi pasien tentang ABCDE self-check kulit dan pentingnya proteksi UV setiap hari.',
                          style: TextStyle(
                            color: const Color(0xFF0B757B).withOpacity(0.75),
                            fontSize: 11.5,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          BottomNav(current: 'dashboard', navigate: widget.navigate),
        ],
      ),
    );
  }
}

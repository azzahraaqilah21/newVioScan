import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/screening_provider.dart';
import '../services/auth_service.dart';
import '../widgets/bottom_nav.dart';

class ProfileScreen extends ConsumerWidget {
  final Function(String) navigate;
  const ProfileScreen({super.key, required this.navigate});

  String _formatDate(DateTime? date) {
    if (date == null) return 'No screenings yet';
    return DateFormat('dd MMM yyyy').format(date);
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Sign Out',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Are you sure you want to sign out of BC-Care?',
          style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final authService = ref.read(authServiceProvider);
      await authService.signOut();
      if (context.mounted) navigate('login');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topPad = MediaQuery.of(context).padding.top;
    final userAsync = ref.watch(currentUserProvider);
    final statsAsync = ref.watch(userStatsProvider);

    final displayName = userAsync.when(
      data: (u) => u?.displayName ?? 'VioScan User',
      loading: () => '...',
      error: (_, __) => 'VioScan User',
    );
    final email = userAsync.when(
      data: (u) => u?.email ?? '',
      loading: () => '...',
      error: (_, __) => '',
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
              bottom: 28,
            ),
            child: Column(
              children: [
                // Top bar
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => navigate('dashboard'),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.18),
                        ),
                        child: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'My Profile',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Avatar
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.22),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.4),
                      width: 3,
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
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Center(
                            child: Text(
                              initials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                Text(
                  displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.25)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_hospital_rounded,
                          color: Color(0xFF77DAD7), size: 12),
                      SizedBox(width: 5),
                      Text(
                        'Healthcare Worker',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: Column(
                children: [
                  // Stats card
                  statsAsync.when(
                    data: (stats) {
                      final count = stats['count'] as int? ?? 0;
                      final lastDate = stats['lastDate'] as DateTime?;
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Screening Stats',
                              style: TextStyle(
                                color: Color(0xFF0B757B),
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: _StatItem(
                                    icon: Icons.medical_services_rounded,
                                    label: 'Total Screenings',
                                    value: '$count',
                                    color: const Color(0xFF0A858C),
                                    bg: const Color(0xFFE6F7F7),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _StatItem(
                                    icon: Icons.calendar_today_rounded,
                                    label: 'Last Screening',
                                    value: _formatDate(lastDate),
                                    color: const Color(0xFF7C3AED),
                                    bg: const Color(0xFFF5F3FF),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                    loading: () => Container(
                      height: 100,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF0A858C)),
                      ),
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  // Account card
                  Container(
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
                    clipBehavior: Clip.hardEdge,
                    child: Column(
                      children: [
                        _ProfileRow(
                          icon: Icons.person_outline_rounded,
                          label: 'Name',
                          value: displayName,
                          iconColor: const Color(0xFF0A858C),
                          iconBg: const Color(0xFFE6F7F7),
                        ),
                        const Divider(height: 1, color: Color(0xFFF9FAFB)),
                        _ProfileRow(
                          icon: Icons.email_outlined,
                          label: 'Email',
                          value: email,
                          iconColor: const Color(0xFF36B8B7),
                          iconBg: const Color(0xFFEBF9F9),
                        ),
                        const Divider(height: 1, color: Color(0xFFF9FAFB)),
                        _ProfileRow(
                          icon: Icons.shield_outlined,
                          label: 'Auth Provider',
                          value: 'Google Account',
                          iconColor: const Color(0xFF4285F4),
                          iconBg: const Color(0xFFEFF6FF),
                        ),
                      ],
                    ),
                  ),
                  // Logout button
                  GestureDetector(
                    onTap: () => _confirmLogout(context, ref),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: const Color(0xFFFECACA),
                          width: 1.5,
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.logout_rounded,
                              color: Color(0xFFDC2626), size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Sign Out',
                            style: TextStyle(
                              color: Color(0xFFDC2626),
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Version note
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Text(
                      'VioScan BC-Care v1.0.0 · PKM-KC 2026',
                      style: TextStyle(
                        color: const Color(0xFF94A3B8).withOpacity(0.7),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          BottomNav(current: 'profile', navigate: navigate),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color bg;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;
  final Color iconBg;

  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
    required this.iconBg,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF1F2937),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

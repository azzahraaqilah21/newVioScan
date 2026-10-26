import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
class AboutBccScreen extends StatelessWidget {
  final Function(String) navigate;
  const AboutBccScreen({super.key, required this.navigate});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text(
          'Tentang BCC',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => navigate('dashboard'),
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero banner
            _HeroBanner(),
            const SizedBox(height: 20),
            // Apa itu BCC
            _SectionCard(
              icon: Icons.info_outline_rounded,
              iconColor: AppColors.primary,
              title: 'Apa itu Basal Cell Carcinoma (BCC)?',
              child: const Text(
                'Basal Cell Carcinoma (BCC) merupakan salah satu jenis kanker kulit yang paling umum ditemukan di dunia. '
                'BCC berkembang dari sel basal di lapisan terdalam epidermis dan umumnya tumbuh perlahan, '
                'namun tetap memerlukan penanganan medis segera.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textDark,
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Ciri-ciri
            _SectionCard(
              icon: Icons.search_rounded,
              iconColor: AppColors.warning,
              title: 'Ciri-Ciri BCC yang Perlu Diwaspadai',
              child: Column(
                children: const [
                  _SymptomItem(
                    emoji: '🫧',
                    text:
                        'Benjolan licin/mengkilap berwarna merah muda, putih, atau seperti mutiara.',
                  ),
                  _SymptomItem(
                    emoji: '🩸',
                    text:
                        'Tahi lalat atau benjolan yang mudah berdarah, mengelupas, lalu kambuh lagi.',
                  ),
                  _SymptomItem(
                    emoji: '🔴',
                    text:
                        'Bercak kemerahan yang agak bersisik atau datar.',
                  ),
                  _SymptomItem(
                    emoji: '🩹',
                    text:
                        'Luka terbuka yang tidak kunjung sembuh setelah 3–4 minggu.',
                    isLast: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Pencegahan - judul seksi
            _SectionHeader(
              icon: Icons.shield_outlined,
              label: 'Langkah Mitigasi & Pencegahan',
              color: AppColors.success,
            ),
            const SizedBox(height: 12),
            // 1. Proteksi UV
            _PreventionCard(
              number: '1',
              title: 'Proteksi Utama dari Paparan Sinar Matahari (Sinar UV)',
              color: const Color(0xFF0A858C),
              items: const [
                _PreventionDetail(
                  icon: Icons.wb_sunny_outlined,
                  title: 'Gunakan Tabir Surya (Sunscreen) Secara Rutin',
                  desc:
                      'Gunakan sunscreen ber-SPF minimal 30 dengan spektrum luas (broad-spectrum) yang melindungi dari UVA dan UVB.',
                ),
                _PreventionDetail(
                  icon: Icons.access_time_rounded,
                  title: 'Hindari Matahari pada Jam Puncak',
                  desc:
                      'Batasi aktivitas di luar ruangan antara pukul 10.00 hingga 16.00, di mana radiasi sinar UV berada pada puncaknya.',
                ),
                _PreventionDetail(
                  icon: Icons.checkroom_rounded,
                  title: 'Gunakan Pakaian & Pelindung Fisik',
                  desc:
                      'Kenakan pakaian berlengan panjang berbahan rapat atau UPF. Gunakan topi bertepi lebar dan kacamata hitam yang memblokir sinar UVA & UVB.',
                ),
                _PreventionDetail(
                  icon: Icons.park_outlined,
                  title: 'Cari Tempat Teduh',
                  desc:
                      'Selalu usahakan berteduh di bawah pohon, payung, atau atap saat berada di luar ruangan.',
                ),
                _PreventionDetail(
                  icon: Icons.block_rounded,
                  title: 'Hindari Indoor Tanning / Tanning Bed',
                  desc:
                      'Alat pencokelat kulit buatan memancarkan sinar UV tinggi yang sangat meningkatkan risiko kanker kulit.',
                  isLast: true,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 2. Deteksi dini
            _PreventionCard(
              number: '2',
              title: 'Mitigasi Deteksi Dini',
              color: const Color(0xFF7C3AED),
              items: const [
                _PreventionDetail(
                  icon: Icons.manage_search_rounded,
                  title: 'Pemeriksaan Kulit Mandiri (Metode ABCDE)',
                  desc:
                      'Periksa seluruh tubuh secara rutin sebulan sekali di depan cermin. Perhatikan tahi lalat, benjolan, atau bercak baru yang tidak hilang.',
                ),
                _PreventionDetail(
                  icon: Icons.local_hospital_outlined,
                  title: 'Pemeriksaan Rutin ke Dokter Spesialis Kulit',
                  desc:
                      'Lakukan skin check tahunan dengan dermatolog, terutama jika Anda memiliki kulit putih/cerah, riwayat sering terpapar matahari, atau riwayat keluarga dengan kanker kulit.',
                  isLast: true,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 3. Pola hidup
            _PreventionCard(
              number: '3',
              title: 'Pola Hidup Sehat & Dukungan Kekebalan Tubuh',
              color: const Color(0xFF059669),
              items: const [
                _PreventionDetail(
                  icon: Icons.favorite_outline_rounded,
                  title: 'Jaga Sistem Imun Tubuh',
                  desc:
                      'Konsumsi makanan kaya antioksidan (buah-buahan, sayuran hijau), istirahat yang cukup, dan hindari merokok.',
                  isLast: true,
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Disclaimer
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFED7AA)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('⚠️', style: TextStyle(fontSize: 18)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Informasi ini bersifat edukatif. Segera konsultasikan ke dokter spesialis kulit (dermatolog) jika menemukan gejala yang mencurigakan.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF92400E),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
// ─── Hero Banner ─────────────────────────────────────────────────────────────
class _HeroBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A858C), Color(0xFF36B8B7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.medical_information_outlined,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Basal Cell\nCarcinoma (BCC)',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '🔬 Kanker Kulit Paling Umum di Dunia',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
// ─── Section Header ───────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
// ─── Section Card ─────────────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;
  const _SectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
// ─── Symptom Item ─────────────────────────────────────────────────────────────
class _SymptomItem extends StatelessWidget {
  final String emoji;
  final String text;
  final bool isLast;
  const _SymptomItem({
    required this.emoji,
    required this.text,
    this.isLast = false,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textDark,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
        if (!isLast)
          const Divider(height: 16, color: Color(0xFFE5E7EB)),
      ],
    );
  }
}
// ─── Prevention Card ──────────────────────────────────────────────────────────
class _PreventionCard extends StatelessWidget {
  final String number;
  final String title;
  final Color color;
  final List<_PreventionDetail> items;
  const _PreventionCard({
    required this.number,
    required this.title,
    required this.color,
    required this.items,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: color,
                  child: Text(
                    number,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Items
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: items),
          ),
        ],
      ),
    );
  }
}
// ─── Prevention Detail Item ───────────────────────────────────────────────────
class _PreventionDetail extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final bool isLast;
  const _PreventionDetail({
    required this.icon,
    required this.title,
    required this.desc,
    this.isLast = false,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    desc,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (!isLast)
          const Divider(height: 20, color: Color(0xFFE5E7EB)),
      ],
    );
  }
}
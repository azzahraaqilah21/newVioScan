import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/screening_provider.dart';
import '../models/clinical_risk_assessment_model.dart';

class SkinRiskAssessmentScreen extends ConsumerStatefulWidget {
  final Function(String) navigate;
  const SkinRiskAssessmentScreen({super.key, required this.navigate});

  @override
  ConsumerState<SkinRiskAssessmentScreen> createState() =>
      _SkinRiskAssessmentScreenState();
}

class _SkinRiskAssessmentScreenState
    extends ConsumerState<SkinRiskAssessmentScreen>
    with SingleTickerProviderStateMixin {
  int step = 0;
  List<String> answers = List.filled(6, '');
  int direction = 1;
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;

  final List<Map<String, dynamic>> questions = [
    {
      'id': 1,
      'emoji': '🎨',
      'question': 'Apa tipe kulit Anda?',
      'subtitle': 'Klasifikasi Skala Fitzpatrick',
      'options': [
        {'id': 'a', 'label': 'Type I–II', 'desc': 'Sangat cerah, sering terbakar, tidak pernah menggelap'},
        {'id': 'b', 'label': 'Type III–IV', 'desc': 'Tone sedang, kadang terbakar, menggelap bertahap'},
        {'id': 'c', 'label': 'Type V–VI', 'desc': 'Tone gelap, jarang terbakar, cepat menggelap'},
      ],
    },
    {
      'id': 2,
      'emoji': '☀️',
      'question': 'Berapa kali Anda mengalami luka bakar matahari parah?',
      'subtitle': 'Kondisi kulit terbakar hingga melepuh atau mengelupas',
      'options': [
        {'id': 'a', 'label': 'Tidak pernah', 'desc': 'Tidak ada riwayat luka bakar matahari parah', 'image': 'assets/images/q2a.jpg'},
        {'id': 'b', 'label': '1–2 kali', 'desc': 'Pernah mengalami luka bakar parah sesekali', 'image': 'assets/images/q2b.jpg'},
        {'id': 'c', 'label': '3 kali atau lebih', 'desc': 'Sering mengalami luka bakar matahari parah', 'image': 'assets/images/q2c.jpg'},
      ],
    },
    {
      'id': 3,
      'emoji': '🧬',
      'question': 'Apakah ada riwayat kanker kulit di keluarga?',
      'subtitle': 'Termasuk orang tua kandung dan saudara kandung',
      'options': [
        {'id': 'a', 'label': 'Tidak ada riwayat', 'desc': 'Tidak ada riwayat kanker kulit di keluarga'},
        {'id': 'b', 'label': 'Tidak yakin', 'desc': 'Kurang mengetahui riwayat medis keluarga'},
        {'id': 'c', 'label': 'Ya, ada', 'desc': 'Terdapat riwayat kanker kulit dalam keluarga'},
      ],
    },
    {
      'id': 4,
      'emoji': '⏱️',
      'question': 'Berapa rata-rata paparan sinar matahari harian Anda?',
      'subtitle': 'Durasi aktivitas di luar ruangan tanpa pelindung/pohon',
      'options': [
        {'id': 'a', 'label': '< 1 jam', 'desc': 'Minimal terpapar sinar matahari harian'},
        {'id': 'b', 'label': '1–3 jam', 'desc': 'Cukup sering terpapar sinar matahari harian'},
        {'id': 'c', 'label': '> 3 jam', 'desc': 'Sangat tinggi terpapar sinar matahari harian'},
      ],
    },
    {
      'id': 5,
      'emoji': '🧴',
      'question': 'Apakah Anda rutin menggunakan pelindung matahari?',
      'subtitle': 'Tabir surya (sunscreen) SPF 30+ atau pakaian pelindung UV',
      'options': [
        {'id': 'a', 'label': 'Selalu', 'desc': 'Konsisten menggunakan SPF 30+ setiap hari'},
        {'id': 'b', 'label': 'Kadang-kadang', 'desc': 'Hanya sesekali menggunakan pelindung matahari'},
        {'id': 'c', 'label': 'Jarang/Tidak pernah', 'desc': 'Hampir tidak pernah melindungi kulit dari UV'},
      ],
    },
    {
      'id': 6,
      'emoji': '🔍',
      'question': 'Apakah Anda menyadari adanya perubahan pada kulit?',
      'subtitle': 'Munculnya bintik aneh, tahi lalat baru, atau lesi luka',
      'options': [
        {'id': 'a', 'label': 'Tidak ada perubahan', 'desc': 'Kondisi kulit tampak normal dan bersih', 'image': 'assets/images/q6a.jpg'},
        {'id': 'b', 'label': 'Perubahan minor', 'desc': 'Ada bintik atau perubahan kecil akhir-akhir ini', 'image': 'assets/images/q6b.png'},
        {'id': 'c', 'label': 'Perubahan signifikan', 'desc': 'Ada perubahan mencurigakan yang butuh perhatian', 'image': 'assets/images/q6c.png'},
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      value: 1 / questions.length,
    );
    _progressAnimation = _progressController;
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  void goNext() {
    if (step == questions.length - 1) {
      _finishQuestionnaire();
    } else {
      setState(() {
        direction = 1;
        step++;
        _progressController.animateTo(
          (step + 1) / questions.length,
          curve: Curves.easeOut,
        );
      });
    }
  }

  void goBack() {
    if (step == 0) {
      widget.navigate('dashboard');
    } else {
      setState(() {
        direction = -1;
        step--;
        _progressController.animateTo(
          (step + 1) / questions.length,
          curve: Curves.easeOut,
        );
      });
    }
  }

  void select(String optId) {
    setState(() {
      answers[step] = optId;
    });
  }

  /// Kuisioner selesai → simpan jawaban ke provider (ikut tersimpan bersama
  /// hasil skrining di scan_result_screen._saveResult), lalu lanjut ke form
  /// informasi lesi → koneksi alat. TIDAK langsung ke 'processing' — animasi
  /// persen di sana fake; progres nyata hanya ada setelah Raspi memindai
  /// (tombol fisik) dan mengirim progress + hasil via Bluetooth.
  void _finishQuestionnaire() {
    const skinTypes = {'a': 'I-II', 'b': 'III-IV', 'c': 'V-VI'};
    const sunburn = {'a': 'never', 'b': '1-2', 'c': '3+'};
    const family = {'a': 'no', 'b': 'unsure', 'c': 'yes'};
    const uv = {'a': '<1h', 'b': '1-3h', 'c': '>3h'};
    const sunscreen = {'a': 'always', 'b': 'sometimes', 'c': 'rarely'};
    const changes = {'a': 'none', 'b': 'minor', 'c': 'significant'};

    ref.read(clinicalAssessmentProvider.notifier).saveAssessment(
          ClinicalRiskAssessmentModel(
            skinType: skinTypes[answers[0]] ?? '',
            historyOfSunburn: sunburn[answers[1]] ?? '',
            familyHistorySkinCancer: family[answers[2]] ?? '',
            dailyUvExposure: uv[answers[3]] ?? '',
            sunscreenUse: sunscreen[answers[4]],
            noticedSkinChanges: changes[answers[5]],
          ),
        );

    widget.navigate('lesion_info');
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final current = questions[step];
    final isLast = step == questions.length - 1;
    final progress = (step + 1) / questions.length;
    final hasAnswer = answers[step].isNotEmpty;

    // Tombol back HP = tombol kembali di layar: mundur satu pertanyaan,
    // atau ke Beranda dari pertanyaan pertama.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) goBack();
      },
      child: Container(
      color: const Color(0xFFF0FAFA),
      child: Column(
        children: [
          // Header
          Container(
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
            padding: EdgeInsets.only(
              top: topPad + 8,
              left: 18,
              right: 18,
              bottom: 16,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: goBack,
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Skin Risk Assessment',
                            style: TextStyle(
                              color: Color(0xFF1F2937),
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Question ${step + 1} of ${questions.length}',
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6F7F7),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        '${(progress * 100).round()}%',
                        style: const TextStyle(
                          color: Color(0xFF0A858C),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: AnimatedBuilder(
                    animation: _progressAnimation,
                    builder: (_, __) {
                      return LinearProgressIndicator(
                        value: _progressAnimation.value,
                        backgroundColor: const Color(0xFFE5E7EB),
                        valueColor: const AlwaysStoppedAnimation(Color(0xFF0A858C)),
                        minHeight: 6,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // Question content
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, anim) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(direction * 0.15, 0),
                    end: Offset.zero,
                  ).animate(anim),
                  child: FadeTransition(opacity: anim, child: child),
                );
              },
              child: KeyedSubtree(
                key: ValueKey(step),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
                  child: Column(
                    children: [
                      // Question card
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
                        margin: const EdgeInsets.only(bottom: 16),
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
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFE6F7F7), Color(0xFFA5E6E2)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Center(
                                child: Text(
                                  current['emoji'] as String,
                                  style: const TextStyle(fontSize: 22),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    current['question'] as String,
                                    style: const TextStyle(
                                      color: Color(0xFF0B757B),
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.w700,
                                      height: 1.3,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    current['subtitle'] as String,
                                    style: const TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Show Fitzpatrick image for Q1
                      if (current['id'] == 1) ...[
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 12,
                                offset: const Offset(0, 2),
                              )
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              'assets/images/fitzpatrickscale.jpg',
                              fit: BoxFit.fitWidth,
                            ),
                          ),
                        ),
                      ],
                      // Options
                      ...((current['options'] as List).map((opt) {
                        final isSelected = answers[step] == opt['id'];
                        final hasImage = opt.containsKey('image') && current['id'] != 1;
                        return GestureDetector(
                          onTap: () => select(opt['id'] as String),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF0A858C).withOpacity(0.05)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF0A858C)
                                    : const Color(0xFFE5E7EB),
                                width: 2,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFF0A858C).withOpacity(0.08),
                                        blurRadius: 8,
                                        spreadRadius: 2,
                                      )
                                    ]
                                  : null,
                            ),
                            child: Row(
                              children: [
                                // Radio
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFF0A858C)
                                          : const Color(0xFFD1D5DB),
                                      width: 2.5,
                                    ),
                                  ),
                                  child: isSelected
                                      ? Center(
                                          child: Container(
                                            width: 10,
                                            height: 10,
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Color(0xFF0A858C),
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                                // Image if present
                                if (hasImage) ...[
                                  const SizedBox(width: 14),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.asset(
                                      opt['image'] as String,
                                      width: 52,
                                      height: 52,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        opt['label'] as String,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: isSelected
                                              ? const Color(0xFF0A858C)
                                              : const Color(0xFF1F2937),
                                        ),
                                      ),
                                      Text(
                                        opt['desc'] as String,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF94A3B8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      })),
                      // Step dots
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(questions.length, (i) {
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              margin: const EdgeInsets.symmetric(horizontal: 2.5),
                              width: i == step ? 20 : 6,
                              height: 4,
                              decoration: BoxDecoration(
                                color: i <= step
                                    ? const Color(0xFF0A858C)
                                    : const Color(0xFFE5E7EB),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Action button
          Container(
            padding: EdgeInsets.fromLTRB(
              18,
              14,
              18,
              14 + MediaQuery.of(context).padding.bottom,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Color(0x0D000000),
                  blurRadius: 20,
                  offset: Offset(0, -4),
                )
              ],
            ),
            child: GestureDetector(
              onTap: hasAnswer ? goNext : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: hasAnswer
                      ? const LinearGradient(
                          colors: [Color(0xFF0A858C), Color(0xFF36B8B7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: hasAnswer ? null : const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: hasAnswer
                      ? [
                          BoxShadow(
                            color: const Color(0xFF0A858C).withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          )
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      isLast ? 'Start UV Screening' : 'Next Question',
                      style: TextStyle(
                        color: hasAnswer ? Colors.white : const Color(0xFF9CA3AF),
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: hasAnswer ? Colors.white : const Color(0xFF9CA3AF),
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}

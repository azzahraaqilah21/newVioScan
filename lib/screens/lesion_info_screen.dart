import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/screening_provider.dart';

class LesionInfoScreen extends ConsumerStatefulWidget {
  final Function(String) navigate;
  const LesionInfoScreen({super.key, required this.navigate});

  @override
  ConsumerState<LesionInfoScreen> createState() => _LesionInfoScreenState();
}

class _LesionInfoScreenState extends ConsumerState<LesionInfoScreen> {
  String? _selectedLocation;
  final TextEditingController _notesCtrl = TextEditingController();

  final List<String> locations = [
    'Wajah (Hidung, Pipi, Dahi)',
    'Leher',
    'Telinga',
    'Kulit Kepala',
    'Dada / Punggung',
    'Lengan / Tangan',
    'Kaki',
    'Lainnya'
  ];

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih lokasi lesi terlebih dahulu.')),
      );
      return;
    }

    ref
        .read(lesionInfoProvider.notifier)
        .saveInfo(_selectedLocation!, _notesCtrl.text);

    // Navigate to hardware connection
    widget.navigate('hardware');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Informasi Lesi',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => widget.navigate('assessment'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Lokasi Lesi',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Di bagian tubuh mana lesi kulit atau tahi lalat yang ingin Anda periksa berada?',
              style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: locations.map((loc) {
                final isSelected = _selectedLocation == loc;
                return GestureDetector(
                  onTap: () => setState(() => _selectedLocation = loc),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF0A858C)
                          : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF0A858C)
                            : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      loc,
                      style: TextStyle(
                        color: isSelected ? Colors.white : const Color(0xFF4B5563),
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
            const Text(
              'Catatan Tambahan (Opsional)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Misal: Tahi lalat sering gatal dan berdarah...',
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide:
                      const BorderSide(color: Color(0xFF0A858C), width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0A858C),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Lanjutkan ke Pemindaian',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

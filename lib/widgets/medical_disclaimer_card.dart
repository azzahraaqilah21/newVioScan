import 'package:flutter/material.dart';

class MedicalDisclaimerCard extends StatelessWidget {
  final String text;

  const MedicalDisclaimerCard({
    super.key,
    this.text =
        '⚠️ Catatan: VioScan BC-Care adalah alat bantu skrining dan tidak menggantikan penilaian klinis dokter. Untuk kondisi darurat medis, selalu hubungi 119 segera.',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Text(
        text,
        style: const TextStyle(
            color: Color(0xFF92400E), fontSize: 11, height: 1.5),
      ),
    );
  }
}

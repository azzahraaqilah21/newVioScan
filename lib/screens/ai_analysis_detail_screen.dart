import 'package:flutter/material.dart';

class AiAnalysisDetailScreen extends StatelessWidget {
  final Function(String) navigate;
  const AiAnalysisDetailScreen({super.key, required this.navigate});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Analisis AI'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => navigate('dashboard'),
        ),
      ),
      body: const Center(
        child: Text('Detail Analisis AI akan tampil di sini.'),
      ),
    );
  }
}

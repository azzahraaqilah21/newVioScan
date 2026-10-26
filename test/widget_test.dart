import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vioscan_flutter/models/clinical_risk_assessment_model.dart';
import 'package:vioscan_flutter/models/screening_model.dart';
import 'package:vioscan_flutter/services/device_service.dart';
import 'package:vioscan_flutter/services/report_service.dart';

void main() {
  group('BC-Care Raspberry Pi & WiFi Data Tests', () {
    test('Parse BCC classification result from Raspberry Pi JSON', () {
      final jsonPacket = {
        "type": "classification_result",
        "timestamp": 1725801234.5,
        "mode": "uv",
        "disease": "BCC",
        "disease_index": 1,
        "confidence": 0.895,
        "probabilities": {
          "NORMAL": 0.105,
          "BCC": 0.895
        },
        "risk_level": "high",
        "ultrasonic": {
          "jarak_referensi": 35.2,
          "jarak_lesi": 32.1,
          "selisih": 3.1,
          "status": "KENYAL (jaringan lunak/cekung)"
        },
        "image_base64": base64Encode([1, 2, 3, 4, 5])
      };

      final model = ScreeningModel.fromDeviceJson(
        jsonPacket,
        userId: 'test_user',
        lesionLocation: 'Dahi Kanan',
      );

      expect(model.prediction, contains('Basal Cell Carcinoma'));
      expect(model.riskLevel, equals('high'));
      expect(model.confidence, closeTo(89.5, 0.1));
      expect(model.probabilities['BCC'], closeTo(89.5, 0.1));
      expect(model.probabilities['NORMAL'], closeTo(10.5, 0.1));
      expect(model.ultrasonicData, isNotNull);
      expect(model.ultrasonicData!['selisih'], equals(3.1));
      expect(model.rawImageBytes, isNotNull);
      expect(model.rawImageBytes!.length, equals(5));
    });

    test('Parse NORMAL classification result from Raspberry Pi JSON', () {
      final jsonPacket = {
        "type": "classification_result",
        "timestamp": 1725801234.5,
        "mode": "white",
        "disease": "NORMAL",
        "disease_index": 0,
        "confidence": 0.942,
        "probabilities": {
          "NORMAL": 0.942,
          "BCC": 0.058
        },
        "risk_level": "low",
        "ultrasonic": {
          "jarak_referensi": 30.0,
          "jarak_lesi": 29.8,
          "selisih": 0.2,
          "status": "SETARA REFERENSI"
        }
      };

      final model = ScreeningModel.fromDeviceJson(
        jsonPacket,
        userId: 'test_user',
        lesionLocation: 'Lengan Kiri',
      );

      expect(model.prediction, contains('Normal'));
      expect(model.riskLevel, equals('low'));
      expect(model.confidence, closeTo(94.2, 0.1));
      expect(model.probabilities['NORMAL'], closeTo(94.2, 0.1));
      expect(model.probabilities['BCC'], closeTo(5.8, 0.1));
      expect(model.ultrasonicData!['status'], equals('SETARA REFERENSI'));
    });

    test('Foto lesi ikut tersimpan & terbaca lewat map Firestore', () {
      // JPEG palsu kecil (isi byte bebas; yang diuji round-trip base64).
      final foto = base64Decode(base64Encode(List<int>.generate(2048, (i) => i % 256)));
      final model = ScreeningModel.fromDeviceJson(
        {'disease': 'BCC', 'confidence': 0.9, 'image_base64': base64Encode(foto)},
        userId: 'u1',
      );

      final map = model.toMap();
      expect(map['imageBase64'], isA<String>());

      final dibaca = ScreeningModel.fromMap('doc1', map);
      expect(dibaca.rawImageBytes, equals(foto));
      expect(dibaca.isSimulated, isFalse);
    });

    test('Data Analisis BC-Care dari Pi ikut tersimpan & terbaca', () {
      final model = ScreeningModel.fromDeviceJson(
        {
          'disease': 'NORMAL',
          'confidence': 0.8,
          'analysis': {
            'brightness': 49.2,
            'sharpness': 117.6,
            'inference_ms': 1100,
            'model_type': 'tflite',
          },
        },
        userId: 'u1',
      );
      expect(model.analysisData!['sharpness'], equals(117.6));

      final dibaca = ScreeningModel.fromMap('doc1', model.toMap());
      expect(dibaca.analysisData!['inference_ms'], equals(1100));
      expect(dibaca.analysisData!['brightness'], equals(49.2));

      // Hasil lama (sebelum ada analisis) tetap terbaca tanpa error.
      final lama = ScreeningModel.fromMap('doc2', {'riskLevel': 'low'});
      expect(lama.analysisData, isNull);
    });

    test('Laporan PDF berisi foto, assessment, analisis & rekomendasi', () async {
      await initializeDateFormatting('id_ID');
      // VIOSCAN_FOTO / VIOSCAN_PDF_OUT: opsional, untuk memeriksa PDF secara visual.
      final contoh = File(Platform.environment['VIOSCAN_FOTO'] ?? '');
      final model = ScreeningModel.fromDeviceJson(
        {
          'disease': 'BCC',
          'confidence': 0.876,
          'mode': 'uv',
          if (contoh.existsSync())
            'image_base64': base64Encode(contoh.readAsBytesSync()),
        },
        userId: 'u1',
        lesionLocation: 'Lengan kanan',
      ).copyWith(
        clinicalRiskAssessment: const ClinicalRiskAssessmentModel(
          skinType: 'III-IV',
          historyOfSunburn: '1-2',
          familyHistorySkinCancer: 'no',
          dailyUvExposure: '>3h',
          sunscreenUse: 'rarely',
          noticedSkinChanges: 'minor',
        ),
      );

      final pdf = await ReportService.buatPdf(
        model,
        analisis: [
          {'label': 'Ketajaman Foto', 'value': 'Tajam'},
        ],
        rekomendasi: {
          'urgency': 'SEGERA – Tindak dalam 1–2 Minggu',
          'sections': [
            {
              'title': 'Tindakan Klinis Segera',
              'source': 'NCCN BCC Guidelines 2024',
              'items': ['Rujuk ke SpKK — prioritas urgent'],
            },
          ],
        },
      );
      expect(String.fromCharCodes(pdf.take(4)), equals('%PDF'));
      expect(ReportService.namaFile(model), startsWith('VioScan_'));
      final out = Platform.environment['VIOSCAN_PDF_OUT'];
      if (out != null) File(out).writeAsBytesSync(pdf);
    });

    test('DeviceService simulation state machine flow', () async {
      final service = DeviceService();
      service.setSimulationMode(true);

      expect(service.currentState, equals(DeviceConnectionState.disconnected));

      final states = <DeviceConnectionState>[];
      final statusSub = service.statusStream.listen(states.add);

      final nextDevicesFuture = service.scanResults.first;
      await service.startScan();
      // 'scanning' hanya sementara: setelah pencarian selesai status kembali
      // ke disconnected (siap dihubungkan).
      expect(states, contains(DeviceConnectionState.scanning));
      expect(service.currentState, equals(DeviceConnectionState.disconnected));

      final devices = await nextDevicesFuture;
      expect(devices.isNotEmpty, isTrue);

      await service.connect(devices.first);
      expect(service.currentState, equals(DeviceConnectionState.connected));

      await service.disconnect();
      expect(service.currentState, equals(DeviceConnectionState.disconnected));

      await statusSub.cancel();
      service.dispose();
    });
  });
}

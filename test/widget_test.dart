import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vioscan_flutter/models/screening_model.dart';
import 'package:vioscan_flutter/services/device_service.dart';

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

    test('DeviceService simulation state machine flow', () async {
      final service = DeviceService();
      service.setSimulationMode(true);

      expect(service.currentState, equals(DeviceConnectionState.disconnected));

      final nextDevicesFuture = service.scanResults.first;
      await service.startScan();
      expect(service.currentState, equals(DeviceConnectionState.scanning));

      final devices = await nextDevicesFuture;
      expect(devices.isNotEmpty, isTrue);

      await service.connect(devices.first);
      expect(service.currentState, equals(DeviceConnectionState.connected));

      await service.disconnect();
      expect(service.currentState, equals(DeviceConnectionState.disconnected));

      service.dispose();
    });
  });
}

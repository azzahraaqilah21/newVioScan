import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'clinical_risk_assessment_model.dart';

/// Represents one completed BC-Care UV fluorescence screening session.
class ScreeningModel {
  final String id;
  final DateTime screeningDate;
  final String lesionLocation;
  final String? lesionNotes;
  final ClinicalRiskAssessmentModel? clinicalRiskAssessment;

  // AI Prediction results
  final String prediction; // e.g. 'Basal Cell Carcinoma' | 'Nevus' | 'Normal'
  final String riskLevel; // 'low' | 'moderate' | 'high'
  final Map<String, double> probabilities; // e.g. {'BCC': 0.87, 'NORMAL': 0.13}
  final double confidence; // 0.0 – 100.0
  final String recommendation;

  // Media
  final String? imageUrl;
  final String? fluorescenceImageUrl;
  final Uint8List? rawImageBytes; // Offline camera image from Raspberry Pi

  // Hardware Ultrasonic Data
  final Map<String, dynamic>? ultrasonicData;
  final String? mode; // 'uv' or 'white'

  // Metadata
  final String cnnModelVersion;
  final DateTime createdAt;
  final String userId;

  // True jika hasil BUKAN dari inferensi model nyata (flag dari Raspberry Pi)
  final bool isSimulated;

  const ScreeningModel({
    required this.id,
    required this.screeningDate,
    required this.lesionLocation,
    this.lesionNotes,
    this.clinicalRiskAssessment,
    required this.prediction,
    required this.riskLevel,
    required this.probabilities,
    required this.confidence,
    required this.recommendation,
    this.imageUrl,
    this.fluorescenceImageUrl,
    this.rawImageBytes,
    this.ultrasonicData,
    this.mode,
    required this.cnnModelVersion,
    required this.createdAt,
    required this.userId,
    this.isSimulated = false,
  });

  /// Batas ukuran foto yang ikut disimpan di dokumen Firestore (maks dokumen
  /// 1 MB; base64 menambah ~33%). Foto dari Pi (lebar 600 px) jauh di bawah ini.
  static const maxStoredImageBytes = 600 * 1024;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'screeningDate': Timestamp.fromDate(screeningDate),
      'lesionLocation': lesionLocation,
      'lesionNotes': lesionNotes,
      'clinicalRiskAssessment': clinicalRiskAssessment?.toMap(),
      'prediction': prediction,
      'riskLevel': riskLevel,
      'probabilities': probabilities,
      'confidence': confidence,
      'recommendation': recommendation,
      'imageUrl': imageUrl,
      'fluorescenceImageUrl': fluorescenceImageUrl,
      'ultrasonicData': ultrasonicData,
      'mode': mode,
      'cnnModelVersion': cnnModelVersion,
      'createdAt': Timestamp.fromDate(createdAt),
      'userId': userId,
      'isSimulated': isSimulated,
      // Foto lesi (JPEG) disimpan sebagai base64 di dokumen yang sama.
      'imageBase64': rawImageBytes != null &&
              rawImageBytes!.length <= maxStoredImageBytes
          ? base64Encode(rawImageBytes!)
          : null,
    };
  }

  /// Copy dengan penggantian sebagian field (dipakai UI saat menyimpan hasil
  /// hardware agar userId/lesionInfo dari form & auth tidak hilang).
  ScreeningModel copyWith({
    String? id,
    DateTime? screeningDate,
    String? lesionLocation,
    String? lesionNotes,
    ClinicalRiskAssessmentModel? clinicalRiskAssessment,
    String? prediction,
    String? riskLevel,
    Map<String, double>? probabilities,
    double? confidence,
    String? recommendation,
    String? imageUrl,
    String? fluorescenceImageUrl,
    Uint8List? rawImageBytes,
    Map<String, dynamic>? ultrasonicData,
    String? mode,
    String? cnnModelVersion,
    DateTime? createdAt,
    String? userId,
    bool? isSimulated,
  }) {
    return ScreeningModel(
      id: id ?? this.id,
      screeningDate: screeningDate ?? this.screeningDate,
      lesionLocation: lesionLocation ?? this.lesionLocation,
      lesionNotes: lesionNotes ?? this.lesionNotes,
      clinicalRiskAssessment:
          clinicalRiskAssessment ?? this.clinicalRiskAssessment,
      prediction: prediction ?? this.prediction,
      riskLevel: riskLevel ?? this.riskLevel,
      probabilities: probabilities ?? this.probabilities,
      confidence: confidence ?? this.confidence,
      recommendation: recommendation ?? this.recommendation,
      imageUrl: imageUrl ?? this.imageUrl,
      fluorescenceImageUrl:
          fluorescenceImageUrl ?? this.fluorescenceImageUrl,
      rawImageBytes: rawImageBytes ?? this.rawImageBytes,
      ultrasonicData: ultrasonicData ?? this.ultrasonicData,
      mode: mode ?? this.mode,
      cnnModelVersion: cnnModelVersion ?? this.cnnModelVersion,
      createdAt: createdAt ?? this.createdAt,
      userId: userId ?? this.userId,
      isSimulated: isSimulated ?? this.isSimulated,
    );
  }

  factory ScreeningModel.fromMap(String docId, Map<String, dynamic> map) {
    final probMap = <String, double>{};
    if (map['probabilities'] is Map) {
      (map['probabilities'] as Map).forEach((k, v) {
        probMap[k.toString()] = (v as num).toDouble();
      });
    }

    Uint8List? imageBytes;
    final imageB64 = map['imageBase64'];
    if (imageB64 is String && imageB64.isNotEmpty) {
      try {
        imageBytes = base64Decode(imageB64);
      } catch (_) {
        imageBytes = null; // data foto rusak → tampil tanpa foto
      }
    }

    return ScreeningModel(
      id: docId,
      screeningDate:
          (map['screeningDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lesionLocation: map['lesionLocation'] as String? ?? 'Unknown',
      lesionNotes: map['lesionNotes'] as String?,
      clinicalRiskAssessment: map['clinicalRiskAssessment'] != null
          ? ClinicalRiskAssessmentModel.fromMap(
              Map<String, dynamic>.from(
                  map['clinicalRiskAssessment'] as Map))
          : null,
      prediction: map['prediction'] as String? ?? 'Unknown',
      riskLevel: map['riskLevel'] as String? ?? 'low',
      probabilities: probMap,
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
      recommendation: map['recommendation'] as String? ?? '',
      imageUrl: map['imageUrl'] as String?,
      fluorescenceImageUrl: map['fluorescenceImageUrl'] as String?,
      rawImageBytes: imageBytes,
      ultrasonicData: map['ultrasonicData'] != null
          ? Map<String, dynamic>.from(map['ultrasonicData'] as Map)
          : null,
      mode: map['mode'] as String?,
      cnnModelVersion: map['cnnModelVersion'] as String? ?? 'BCC-v3.2',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      userId: map['userId'] as String? ?? '',
      isSimulated: map['isSimulated'] == true,
    );
  }

  /// Factory untuk membuat instance dari JSON yang dikirim Raspberry Pi
  /// via Bluetooth Classic SPP.
  factory ScreeningModel.fromDeviceJson(
    Map<String, dynamic> json, {
    String userId = 'offline_user',
    String lesionLocation = 'Lesi Kulit',
    String? lesionNotes,
    ClinicalRiskAssessmentModel? clinicalRiskAssessment,
  }) {
    final rawDisease = (json['disease'] as String? ?? 'NORMAL').toUpperCase();
    final isBcc = rawDisease.contains('BCC') || rawDisease.contains('CARCINOMA');
    final predictionLabel = isBcc ? 'Basal Cell Carcinoma (BCC)' : 'Nevus / Kulit Normal';
    final riskLevel = isBcc ? 'high' : 'low';

    // Parse confidence
    double rawConf = (json['confidence'] as num?)?.toDouble() ?? 0.85;
    if (rawConf <= 1.0) rawConf *= 100.0; // Jika 0.0 - 1.0, ubah ke persentase

    // Probabilitas
    final probMap = <String, double>{};
    if (json['probabilities'] is Map) {
      (json['probabilities'] as Map).forEach((k, v) {
        double val = (v as num).toDouble();
        if (val <= 1.0) val *= 100.0;
        probMap[k.toString()] = val;
      });
    } else {
      if (isBcc) {
        probMap['BCC'] = rawConf;
        probMap['NORMAL'] = 100.0 - rawConf;
      } else {
        probMap['NORMAL'] = rawConf;
        probMap['BCC'] = 100.0 - rawConf;
      }
    }

    // Decode Base64 Image jika ada
    Uint8List? imageBytes;
    final dynamic imageField = json['image_base64'];
    final String? b64 = imageField is String ? imageField : null;

    print('[IMAGE-DEBUG] image_base64 ada: ${b64 != null && b64.isNotEmpty}');
    print('[IMAGE-DEBUG] panjang Base64: ${b64?.length ?? 0}');

    if (b64 != null && b64.isNotEmpty) {
      try {
        imageBytes = base64Decode(b64);
        print('[IMAGE-DEBUG] ukuran foto decode: ${imageBytes.length} byte');
      } catch (e) {
        print('[IMAGE-DEBUG] Gagal decode foto: $e');
      }
    } else {
      print('[IMAGE-DEBUG] Raspberry Pi tidak mengirim image_base64.');
    }

    // Ultrasonic Data
    Map<String, dynamic>? uData;
    if (json['ultrasonic'] is Map) {
      uData = Map<String, dynamic>.from(json['ultrasonic'] as Map);
    }

    final recommendation = isBcc
        ? 'Rujuk segera ke dokter Spesialis Kulit & Kelamin (SpKK) dalam 1–2 minggu. Hindari paparan sinar UV langsung dan gunakan proteksi broad spectrum.'
        : 'Lesi jinak (Risiko Rendah). Jadwalkan skrining kontrol rutin dalam 3 bulan. Lakukan swaperiksa kulit metode ABCDE.';

    return ScreeningModel(
      id: 'rpi_${DateTime.now().millisecondsSinceEpoch}',
      screeningDate: DateTime.now(),
      lesionLocation: lesionLocation,
      lesionNotes: lesionNotes,
      clinicalRiskAssessment: clinicalRiskAssessment,
      prediction: predictionLabel,
      riskLevel: riskLevel,
      probabilities: probMap,
      confidence: rawConf,
      recommendation: recommendation,
      rawImageBytes: imageBytes,
      ultrasonicData: uData,
      mode: json['mode'] as String? ?? 'uv',
      cnnModelVersion: 'BC-Care Edge-AI (EfficientNetB3)',
      createdAt: DateTime.now(),
      userId: userId,
      isSimulated: json['simulated'] == true,
    );
  }

  /// Creates a demo screening result for testing without a real device.
  factory ScreeningModel.demo({
    required String userId,
    required String lesionLocation,
    String? lesionNotes,
    ClinicalRiskAssessmentModel? clinicalRiskAssessment,
    String riskLevel = 'moderate',
  }) {
    final Map<String, Map<String, dynamic>> riskData = {
      'low': {
        'prediction': 'Nevus (Normal)',
        'confidence': 94.1,
        'probabilities': {'Nevus': 94.1, 'BCC': 4.0, 'SH': 1.9},
        'recommendation':
            'No immediate action required. Schedule routine screening in 3 months. Educate patient on ABCDE self-check.',
      },
      'moderate': {
        'prediction': 'Sebaceous Hyperplasia',
        'confidence': 78.1,
        'probabilities': {
          'Sebaceous Hyperplasia': 78.1,
          'BCC': 16.8,
          'Nevus': 5.1
        },
        'recommendation':
            'Schedule follow-up in 4–6 weeks. Use dermoscopy if available. Document serial photos.',
      },
      'high': {
        'prediction': 'Basal Cell Carcinoma',
        'confidence': 85.3,
        'probabilities': {'BCC': 85.3, 'Nevus': 9.0, 'SH': 5.7},
        'recommendation':
            'Urgent referral to dermatologist (SpKK) within 1–2 weeks. Use BPJS referral form to FKRTL.',
      },
    };

    final data = riskData[riskLevel]!;
    return ScreeningModel(
      id: 'demo_${DateTime.now().millisecondsSinceEpoch}',
      screeningDate: DateTime.now(),
      lesionLocation: lesionLocation,
      lesionNotes: lesionNotes,
      clinicalRiskAssessment: clinicalRiskAssessment,
      prediction: data['prediction'] as String,
      riskLevel: riskLevel,
      probabilities: Map<String, double>.from(
          (data['probabilities'] as Map).map((k, v) =>
              MapEntry(k.toString(), (v as num).toDouble()))),
      confidence: (data['confidence'] as num).toDouble(),
      recommendation: data['recommendation'] as String,
      cnnModelVersion: 'BCC-v3.2',
      createdAt: DateTime.now(),
      userId: userId,
      // Data contoh (Mode Simulator) — bukan hasil alat.
      isSimulated: true,
    );
  }
}


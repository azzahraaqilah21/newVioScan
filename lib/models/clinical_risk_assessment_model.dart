/// Stores answers from the clinical risk assessment questionnaire.
/// These answers are metadata only — no risk score is computed here.
/// They are combined with UV image analysis for AI prediction, dan ikut
/// tersimpan ke Firestore bersama hasil skrining.
///
/// Field diisi dari kuisioner UI (skin_risk_assessment_screen):
///   Q1 → skinType, Q2 → historyOfSunburn, Q3 → familyHistorySkinCancer,
///   Q4 → dailyUvExposure, Q5 → sunscreenUse, Q6 → noticedSkinChanges.
/// Field lain (age, gender, dst.) opsional — tidak ditanyakan kuisioner UI
/// saat ini, tetap tersedia untuk form lain / versi berikutnya.
class ClinicalRiskAssessmentModel {
  final int age;
  final String gender; // 'male' | 'female' | 'other'
  final String skinType; // 'I-II' | 'III-IV' | 'V-VI'
  final String dailyUvExposure; // '<1h' | '1-3h' | '>3h'
  final String historyOfSunburn; // 'never' | '1-2' | '3+'
  final String familyHistorySkinCancer; // 'no' | 'unsure' | 'yes'
  final String previousSkinCancer; // 'no' | 'yes'
  final String outdoorOccupation; // 'no' | 'yes'
  final String? immunosuppressiveCondition; // 'no' | 'yes' | null (skipped)
  final String? sunscreenUse; // 'always' | 'sometimes' | 'rarely'
  final String? noticedSkinChanges; // 'none' | 'minor' | 'significant'

  const ClinicalRiskAssessmentModel({
    this.age = 0,
    this.gender = '',
    this.skinType = '',
    this.dailyUvExposure = '',
    this.historyOfSunburn = '',
    this.familyHistorySkinCancer = '',
    this.previousSkinCancer = '',
    this.outdoorOccupation = '',
    this.immunosuppressiveCondition,
    this.sunscreenUse,
    this.noticedSkinChanges,
  });

  Map<String, dynamic> toMap() {
    return {
      'age': age,
      'gender': gender,
      'skinType': skinType,
      'dailyUvExposure': dailyUvExposure,
      'historyOfSunburn': historyOfSunburn,
      'familyHistorySkinCancer': familyHistorySkinCancer,
      'previousSkinCancer': previousSkinCancer,
      'outdoorOccupation': outdoorOccupation,
      'immunosuppressiveCondition': immunosuppressiveCondition,
      'sunscreenUse': sunscreenUse,
      'noticedSkinChanges': noticedSkinChanges,
    };
  }

  factory ClinicalRiskAssessmentModel.fromMap(Map<String, dynamic> map) {
    return ClinicalRiskAssessmentModel(
      age: (map['age'] as num?)?.toInt() ?? 0,
      gender: map['gender'] as String? ?? '',
      skinType: map['skinType'] as String? ?? '',
      dailyUvExposure: map['dailyUvExposure'] as String? ?? '',
      historyOfSunburn: map['historyOfSunburn'] as String? ?? '',
      familyHistorySkinCancer: map['familyHistorySkinCancer'] as String? ?? '',
      previousSkinCancer: map['previousSkinCancer'] as String? ?? '',
      outdoorOccupation: map['outdoorOccupation'] as String? ?? '',
      immunosuppressiveCondition:
          map['immunosuppressiveCondition'] as String?,
      sunscreenUse: map['sunscreenUse'] as String?,
      noticedSkinChanges: map['noticedSkinChanges'] as String?,
    );
  }
}

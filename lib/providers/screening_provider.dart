import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/screening_model.dart';
import '../models/clinical_risk_assessment_model.dart';
import '../services/firestore_service.dart';
import 'auth_provider.dart';

// ─── 1. Firestore Data Providers ──────────────────────────────────────────

/// Stream of all screenings for the current user
final screeningsStreamProvider = StreamProvider<List<ScreeningModel>>((ref) {
  final authState = ref.watch(authStateProvider).value;
  if (authState == null) return const Stream.empty();

  final firestoreService = ref.watch(firestoreServiceProvider);
  return firestoreService.getScreenings(authState.uid);
});

/// Future provider for the user's screening stats
final userStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final authState = await ref.watch(authStateProvider.future);
  if (authState == null) return {'count': 0};

  final firestoreService = ref.watch(firestoreServiceProvider);
  final count = await firestoreService.getUserScreeningCount(authState.uid);
  final last = await firestoreService.getLastScreening(authState.uid);

  return {
    'count': count,
    'lastDate': last?.screeningDate,
    'lastPrediction': last?.prediction,
    'lastLocation': last?.lesionLocation,
    'lastConfidence': last?.confidence,
  };
});

// ─── 2. In-Progress Screening State (Form Data) ───────────────────────────

/// Stores the user's answers to the 9 clinical assessment questions
class ClinicalAssessmentNotifier
    extends StateNotifier<ClinicalRiskAssessmentModel?> {
  ClinicalAssessmentNotifier() : super(null);

  void saveAssessment(ClinicalRiskAssessmentModel model) {
    state = model;
  }

  void clear() {
    state = null;
  }
}

final clinicalAssessmentProvider = StateNotifierProvider<
    ClinicalAssessmentNotifier, ClinicalRiskAssessmentModel?>((ref) {
  return ClinicalAssessmentNotifier();
});

/// Stores lesion location and notes
class LesionInfoState {
  final String location;
  final String notes;
  LesionInfoState({required this.location, required this.notes});
}

class LesionInfoNotifier extends StateNotifier<LesionInfoState?> {
  LesionInfoNotifier() : super(null);

  void saveInfo(String location, String notes) {
    state = LesionInfoState(location: location, notes: notes);
  }

  void clear() {
    state = null;
  }
}

final lesionInfoProvider =
    StateNotifierProvider<LesionInfoNotifier, LesionInfoState?>((ref) {
  return LesionInfoNotifier();
});

/// Stores the final full screening result before saving to Firestore
class ActiveScreeningNotifier extends StateNotifier<ScreeningModel?> {
  ActiveScreeningNotifier() : super(null);

  void setScreeningResult(ScreeningModel model) {
    state = model;
  }

  void clear() {
    state = null;
  }
}

final activeScreeningProvider =
    StateNotifierProvider<ActiveScreeningNotifier, ScreeningModel?>((ref) {
  return ActiveScreeningNotifier();
});

import '../data/cantera_data.dart';
import '../services/offline_mutation_service.dart';

class TrainingSessionRepository {
  const TrainingSessionRepository();

  Future<OfflineWriteResult> persistGeneratedSession({
    required CanteraClub club,
    required TrainingSession session,
    int? relatedLudTeamId,
  }) {
    return OfflineMutationService.instance.saveTacticalDataOfflineFirst(
      type: 'session',
      title: session.title,
      content: session.toJson(),
      relatedLudTeamId: relatedLudTeamId,
      categoryId: session.categoryId,
    );
  }

  Future<OfflineWriteResult> persistGeneratedTactic({
    required String title,
    required String categoryId,
    required Map<String, dynamic> content,
    int? relatedLudTeamId,
  }) {
    return OfflineMutationService.instance.saveTacticalDataOfflineFirst(
      type: 'match_tactic',
      title: title,
      content: content,
      relatedLudTeamId: relatedLudTeamId,
      categoryId: categoryId,
    );
  }
}

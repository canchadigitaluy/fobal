import 'dart:async';

import '../data/cantera_data.dart';
import '../repositories/training_session_repository.dart';
import '../services/offline_mutation_service.dart';

sealed class TrainingSessionEvent {
  const TrainingSessionEvent();
}

class PersistGeneratedTrainingSession extends TrainingSessionEvent {
  final CanteraClub club;
  final TrainingSession session;
  final int? relatedLudTeamId;

  const PersistGeneratedTrainingSession({
    required this.club,
    required this.session,
    this.relatedLudTeamId,
  });
}

sealed class TrainingSessionState {
  const TrainingSessionState();
}

class TrainingSessionIdle extends TrainingSessionState {
  const TrainingSessionIdle();
}

class TrainingSessionSaving extends TrainingSessionState {
  const TrainingSessionSaving();
}

class TrainingSessionSaved extends TrainingSessionState {
  final OfflineWriteResult result;

  const TrainingSessionSaved(this.result);
}

class TrainingSessionSaveFailed extends TrainingSessionState {
  final String message;

  const TrainingSessionSaveFailed(this.message);
}

class TrainingSessionBloc {
  final TrainingSessionRepository _repository;
  final _stateController =
      StreamController<TrainingSessionState>.broadcast();

  TrainingSessionState _state = const TrainingSessionIdle();

  TrainingSessionBloc({
    this._repository =
        const TrainingSessionRepository(),
  });

  TrainingSessionState get state => _state;

  Stream<TrainingSessionState> get stream => _stateController.stream;

  Future<void> dispatch(TrainingSessionEvent event) async {
    switch (event) {
      case PersistGeneratedTrainingSession():
        await _persistGeneratedSession(event);
    }
  }

  Future<void> _persistGeneratedSession(
    PersistGeneratedTrainingSession event,
  ) async {
    _emit(const TrainingSessionSaving());
    try {
      final result = await _repository.persistGeneratedSession(
        club: event.club,
        session: event.session,
        relatedLudTeamId: event.relatedLudTeamId,
      );
      _emit(TrainingSessionSaved(result));
    } catch (error) {
      _emit(TrainingSessionSaveFailed('$error'));
    }
  }

  void _emit(TrainingSessionState next) {
    _state = next;
    _stateController.add(next);
  }

  void dispose() {
    _stateController.close();
  }
}

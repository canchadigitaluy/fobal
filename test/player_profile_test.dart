import 'package:flutter_test/flutter_test.dart';

import 'package:cantera_os/data/cantera_data.dart';
import 'package:cantera_os/services/player_profile_service.dart';

Player _player({
  String id = 'p1',
  bool hasStats = false,
  String status = '',
  List<PlayerGoal> goals = const [],
}) {
  return Player(
    id: id,
    categoryId: 'cat-1',
    firstName: 'Juan',
    lastName: 'Pérez',
    age: 20,
    position: 'DEL',
    secondaryPositions: '',
    dominantFoot: '',
    status: status,
    attendanceRate: 0,
    trend: '',
    matchesPlayed: hasStats ? 10 : 0,
    minutesPlayed: hasStats ? 800 : 0,
    note: '',
    developmentGoals: goals,
  );
}

void main() {
  group('PlayerGoal serialization / retrocompatibilidad', () {
    test('round-trips every field through json', () {
      final goal = PlayerGoal(
        id: 'g1',
        title: 'Mejorar el remate',
        area: PlayerGoalArea.tecnica,
        detail: 'Trabajar la pierna izquierda',
        priority: PlayerGoalPriority.alta,
        status: PlayerGoalStatus.enProgreso,
        reviewDate: '30/09',
        createdAt: '2026-01-01T00:00:00Z',
      );
      final restored = PlayerGoal.fromJson(goal.toJson());
      expect(restored.id, goal.id);
      expect(restored.title, goal.title);
      expect(restored.area, goal.area);
      expect(restored.detail, goal.detail);
      expect(restored.priority, goal.priority);
      expect(restored.status, goal.status);
      expect(restored.reviewDate, goal.reviewDate);
      expect(restored.createdAt, goal.createdAt);
    });

    test('missing/unknown enum values fall back to safe defaults, never crash', () {
      final restored = PlayerGoal.fromJson({
        'id': 'g2',
        'title': 'Objetivo viejo',
        'area': 'algo-que-ya-no-existe',
        'priority': null,
        'status': 'unknown-status',
      });
      expect(restored.title, 'Objetivo viejo');
      expect(restored.area, PlayerGoalArea.otra);
      expect(restored.priority, PlayerGoalPriority.media);
      expect(restored.status, PlayerGoalStatus.pendiente);
    });

    test('a completely empty json still produces a usable goal (retrocompat)', () {
      final restored = PlayerGoal.fromJson(const {});
      expect(restored.id, isNotEmpty);
      expect(restored.title, '');
      expect(restored.area, PlayerGoalArea.otra);
    });
  });

  group('Player.developmentGoals retrocompatibilidad', () {
    test('a player json with no developmentGoals key loads with an empty list', () {
      final player = Player.fromJson({
        'id': 'p1',
        'firstName': 'Juan',
        'lastName': 'Pérez',
      });
      expect(player.developmentGoals, isEmpty);
    });

    test('developmentGoals round-trips through Player json', () {
      final player = _player(goals: [
        const PlayerGoal(id: 'g1', title: 'Objetivo 1'),
      ]);
      final restored = Player.fromJson(player.toJson());
      expect(restored.developmentGoals.length, 1);
      expect(restored.developmentGoals.first.title, 'Objetivo 1');
    });
  });

  group('hasReliableLeagueStats — relación segura jugador LUD/manual', () {
    test('true only when the category is LUD AND the player carries numbers', () {
      expect(
        hasReliableLeagueStats(categoryIsLud: true, player: _player(hasStats: true)),
        isTrue,
      );
    });

    test('false for a LUD category if the player has no numbers yet', () {
      expect(
        hasReliableLeagueStats(categoryIsLud: true, player: _player(hasStats: false)),
        isFalse,
      );
    });

    test('false for a manual/No-LUD category even if the player somehow has '
        'numbers — never shown as league stats outside LUD', () {
      expect(
        hasReliableLeagueStats(categoryIsLud: false, player: _player(hasStats: true)),
        isFalse,
      );
    });
  });

  group('hasManualMatchStats — partidos/goles cargados a mano en No-LUD', () {
    test('true for a No-LUD player with real matches or goals', () {
      expect(
        hasManualMatchStats(categoryIsLud: false, player: _player(hasStats: true)),
        isTrue,
      );
    });

    test('false for a No-LUD player with nothing loaded yet', () {
      expect(
        hasManualMatchStats(categoryIsLud: false, player: _player(hasStats: false)),
        isFalse,
      );
    });

    test('false for a LUD category even with numbers — that path is '
        'hasReliableLeagueStats instead, never this one', () {
      expect(
        hasManualMatchStats(categoryIsLud: true, player: _player(hasStats: true)),
        isFalse,
      );
    });
  });

  group('formatPlayerGoalLine(s)', () {
    test('formats title, area and status into one line', () {
      const goal = PlayerGoal(
        id: 'g1',
        title: 'Mejorar el remate',
        area: PlayerGoalArea.tecnica,
        status: PlayerGoalStatus.enProgreso,
      );
      expect(formatPlayerGoalLine(goal), 'Mejorar el remate (Técnica) — En progreso');
    });
  });

  group('activePlayerGoals', () {
    test('keeps pendiente/en progreso, drops logrado/pausado', () {
      final goals = [
        const PlayerGoal(id: 'g1', title: 'A', status: PlayerGoalStatus.pendiente),
        const PlayerGoal(id: 'g2', title: 'B', status: PlayerGoalStatus.enProgreso),
        const PlayerGoal(id: 'g3', title: 'C', status: PlayerGoalStatus.logrado),
        const PlayerGoal(id: 'g4', title: 'D', status: PlayerGoalStatus.pausado),
      ];
      final active = activePlayerGoals(goals);
      expect(active.map((g) => g.id).toSet(), {'g1', 'g2'});
    });
  });

  group('goalReviewStatus', () {
    final now = DateTime(2026, 9, 5);
    test('ISO date in the past -> overdue', () {
      expect(goalReviewStatus('2026-09-01', now: now), GoalReviewStatus.overdue);
    });
    test('ISO date within 7 days -> upcoming', () {
      expect(goalReviewStatus('2026-09-10', now: now), GoalReviewStatus.upcoming);
    });
    test('ISO date further out -> none', () {
      expect(goalReviewStatus('2026-10-30', now: now), GoalReviewStatus.none);
    });
    test('legacy free text -> none, never a guessed date', () {
      expect(goalReviewStatus('30/09', now: now), GoalReviewStatus.none);
      expect(goalReviewStatus('en un mes', now: now), GoalReviewStatus.none);
      expect(goalReviewStatus('', now: now), GoalReviewStatus.none);
    });
  });

  group('squadGoalTracker review-date bump', () {
    final now = DateTime(2026, 9, 5);
    test('an overdue-review goal outranks a higher-priority goal with no review', () {
      final overdueLowPri = _player(
        id: 'p-a',
        goals: [
          const PlayerGoal(id: 'g1', title: 'A', priority: PlayerGoalPriority.baja, reviewDate: '2026-09-01'),
        ],
      );
      final highPriNoReview = _player(
        id: 'p-b',
        goals: [
          const PlayerGoal(id: 'g2', title: 'B', priority: PlayerGoalPriority.alta),
        ],
      );
      final result = squadGoalTracker([highPriNoReview, overdueLowPri], now: now);
      expect(result.first.goal.id, 'g1');
    });
  });

  group('newPlayerGoalId', () {
    test('is never empty', () {
      expect(newPlayerGoalId(), isNotEmpty);
    });
  });

  group('squadGoalTracker', () {
    test('flattens active goals across players, ordered by priority (alta first)', () {
      final low = _player(
        id: 'p-low',
        goals: [
          const PlayerGoal(id: 'g1', title: 'Bajo', priority: PlayerGoalPriority.baja),
        ],
      );
      final high = _player(
        id: 'p-high',
        goals: [
          const PlayerGoal(id: 'g2', title: 'Alto', priority: PlayerGoalPriority.alta),
        ],
      );
      final result = squadGoalTracker([low, high]);
      expect(result.length, 2);
      expect(result.first.player.id, 'p-high');
      expect(result.last.player.id, 'p-low');
    });

    test('drops logrado/pausado goals — only active ones are tracked', () {
      final player = _player(
        goals: [
          const PlayerGoal(id: 'g1', title: 'Listo', status: PlayerGoalStatus.logrado),
        ],
      );
      expect(squadGoalTracker([player]), isEmpty);
    });

    test('empty squad yields an empty tracker', () {
      expect(squadGoalTracker(const []), isEmpty);
    });
  });
}

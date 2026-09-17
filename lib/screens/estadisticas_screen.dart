import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import '../services/attendance_stats_service.dart';
import '../services/club_access_service.dart';
import '../services/export_download_service.dart';
import '../services/export_text_service.dart';
import '../services/player_match_stats_service.dart';
import '../services/squad_report_service.dart';
import '../state/section_handoff.dart';
import '../ui/export_preview_dialog.dart';
import '../ui/ui_kit.dart';
import 'match_result_dialog.dart';
import 'player_profile_screen.dart';

class EstadisticasScreen extends StatefulWidget {
  const EstadisticasScreen({super.key});

  @override
  State<EstadisticasScreen> createState() => _EstadisticasScreenState();
}

class _EstadisticasScreenState extends State<EstadisticasScreen> {
  Future<_StatsData>? _future;
  String? _key;
  bool _forceNextLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppScope.of(context);
    final categories = scope.fullClub.categories;
    if (categories.isEmpty) return;
    final selectedCategoryId = scope.selectedCategoryId;
    final category = categories.firstWhere(
      (item) => item.id == selectedCategoryId,
      orElse: () => categories.first,
    );
    final key = '${scope.fullClub.id}|${category.id}';
    if (_key == key && _future != null) return;
    _key = key;
    final players = scope.fullClub.players
        .where((player) => player.categoryId == category.id)
        .toList();
    _future = _load(scope.fullClub, category, players);
  }

  Future<_StatsData> _load(
    CanteraClub club,
    CategorySquad category,
    List<Player> players,
  ) async {
    final force = _forceNextLoad;
    _forceNextLoad = false;
    final activeMembership = await ClubAccessService.activeMembership();
    final membership =
        activeMembership != null && activeMembership.clubId == club.id
        ? activeMembership
        : _previewMembership(club, category);
    if (membership == null) {
      return _StatsData(players: _playerStats(players));
    }
    final values = await Future.wait<dynamic>([
      ClubAccessService.loadStandings(
        membership: membership,
        category: category,
        forceRefresh: force,
      ).catchError((_) => null),
      ClubAccessService.loadResults(
        membership: membership,
        category: category,
        forceRefresh: force,
      ).catchError((_) => <LudFixtureMatch>[]),
      _loadLudPlayers(membership, category, players).catchError(
        (_) => players,
      ),
    ]);
    return _StatsData(
      standings: values[0] as LudStandingsTable?,
      results: values[1] as List<LudFixtureMatch>,
      players: _playerStats(values[2] as List<Player>),
    );
  }

  Future<List<Player>> _loadLudPlayers(
    ClubMembership membership,
    CategorySquad category,
    List<Player> currentPlayers,
  ) async {
    if (LudCategoryRef.teamIdOf(category.id) == null) return currentPlayers;
    final context = await ClubAccessService.loadClubContext(membership);
    if (context == null) return currentPlayers;
    final incoming = context.players
        .where((player) => player.categoryId == category.id)
        .toList();
    if (incoming.isEmpty) return currentPlayers;
    return preservePlayerProfiles(
      incoming: incoming,
      existing: currentPlayers,
    );
  }

  ClubMembership? _previewMembership(CanteraClub club, CategorySquad category) {
    final teamId = LudCategoryRef.teamIdOf(category.id);
    if (teamId == null) return null;
    return ClubMembership(
      clubId: club.id,
      clubName: club.name,
      ludTeamId: '$teamId',
      role: 'coach',
      status: 'active',
    );
  }

  List<_PlayerStat> _playerStats(List<Player> players) {
    return players
        .map(
          (player) => _PlayerStat(
            id: player.id,
            name: player.fullName.trim(),
            position: player.position.trim(),
            matches: player.matchesPlayed,
            minutes: player.minutesPlayed,
            goals: player.goals,
            assists: player.assists,
            yellowCards: player.yellowCards,
            attendanceRate: player.attendanceRate,
          ),
        )
        .where((player) => player.name.isNotEmpty)
        .toList();
  }

  /// Persists a No-LUD category's match results and, in the same update,
  /// recomputes matchesPlayed/goals for every player in that category from
  /// the full result history — the only source of truth for manual clubs,
  /// which have no league sync to derive those numbers from. Recomputing
  /// from scratch (instead of incrementing) means an edit or delete never
  /// double-counts.
  void _saveResults(List<MatchResult> next, String categoryId) {
    final scope = AppScope.of(context);
    final club = scope.fullClub;
    final categoryPlayerIds = club.players
        .where((player) => player.categoryId == categoryId)
        .map((player) => player.id)
        .toList();
    final categoryResults = next
        .where((result) => result.categoryId == categoryId)
        .toList();
    final stats = computePlayerMatchStats(
      lineups: [for (final result in categoryResults) result.lineupIds],
      scorers: [for (final result in categoryResults) result.scorerIds],
      minutesByMatch: [
        for (final result in categoryResults) result.minutesByPlayer,
      ],
      playerIds: categoryPlayerIds,
    );
    final players = [
      for (final player in club.players)
        if (stats.containsKey(player.id))
          player.copyWith(
            matchesPlayed: stats[player.id]!.matchesPlayed,
            goals: stats[player.id]!.goals,
            minutesPlayed: stats[player.id]!.minutesPlayed,
          )
        else
          player,
    ];
    scope.updateClub(club.copyWith(matchResults: next, players: players));
  }

  void _refresh() {
    _key = null;
    _forceNextLoad = true;
    didChangeDependencies();
    setState(() {});
  }

  void _generateSquadReport({
    required CanteraClub club,
    required List<Player> players,
    required String categoryId,
    required String categoryName,
  }) {
    final content = buildSquadReportContent(
      club: club,
      players: players,
      categoryId: categoryId,
      categoryName: categoryName,
    );
    final fileName = buildExportFileName(
      club: club.name,
      category: categoryName,
      type: 'reporte-plantel',
      extension: 'txt',
    );
    showExportPreviewDialog(
      context,
      title: 'Reporte del plantel',
      content: content,
      fileName: fileName,
      onDownload: (name, text) {
        ExportDownloadService.downloadText(name, text);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Reporte descargado: $name')));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final club = AppScope.of(context).club;
    final scope = AppScope.of(context);
    var category = '';
    for (final item in scope.fullClub.categories) {
      if (item.id == scope.selectedCategoryId) {
        category = item.name;
        break;
      }
    }
    if (category.isEmpty && scope.fullClub.categories.isNotEmpty) {
      category = scope.fullClub.categories.first.name;
    }
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Estadísticas'),
            Text(
              'Rendimiento y lectura deportiva',
              style: TextStyle(
                color: CX.faint,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<_StatsData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data ?? const _StatsData();
          final selectedCategoryId =
              scope.selectedCategoryId ??
              (scope.fullClub.categories.isEmpty
                  ? ''
                  : scope.fullClub.categories.first.id);
          final isLud = LudCategoryRef.teamIdOf(selectedCategoryId) != null;

          if (!isLud) {
            final categoryPlayers = club.players
                .where((player) => player.categoryId == selectedCategoryId)
                .toList();
            return _NoLudStatsBody(
              clubName: club.name,
              category: category,
              categoryId: selectedCategoryId,
              allResults: scope.fullClub.matchResults,
              players: categoryPlayers,
              attendanceRecords: scope.fullClub.attendanceRecords
                  .where((record) => record.categoryId == selectedCategoryId)
                  .toList(),
              onChanged: (next) => _saveResults(next, selectedCategoryId),
              onGenerateReport: () => _generateSquadReport(
                club: scope.fullClub,
                players: categoryPlayers,
                categoryId: selectedCategoryId,
                categoryName: category,
              ),
            );
          }

          final narrow = MediaQuery.sizeOf(context).width < 700;
          return ListView(
            padding: EdgeInsets.fromLTRB(
              narrow ? 14 : 20,
              narrow ? 8 : 12,
              narrow ? 14 : 20,
              narrow ? 24 : 36,
            ),
            children: [
              _WeekReading(
                clubName: club.name,
                category: category,
                data: data,
                isLud: isLud,
              ),
              SizedBox(height: narrow ? 10 : 14),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _generateSquadReport(
                    club: scope.fullClub,
                    players: scope.fullClub.players
                        .where((p) => p.categoryId == selectedCategoryId)
                        .toList(),
                    categoryId: selectedCategoryId,
                    categoryName: category,
                  ),
                  icon: const Icon(Icons.summarize_outlined, size: 17),
                  label: const Text('Generar reporte del plantel'),
                ),
              ),
              SizedBox(height: narrow ? 14 : 20),
              PremiumSectionHeader(
                compact: narrow,
                eyebrow: 'Panorama',
                title: 'Números de la categoría',
              ),
              _MetricGrid(
                data: data,
                attendanceRecords: scope.fullClub.attendanceRecords
                    .where((record) => record.categoryId == selectedCategoryId)
                    .toList(),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => ShellActions.of(
                    context,
                  ).openSection(ShellSection.attendance),
                  icon: const Icon(Icons.history, size: 17),
                  label: const Text('Ver historial de asistencia'),
                ),
              ),
              SizedBox(height: narrow ? 14 : 20),
              PremiumSectionHeader(
                compact: narrow,
                eyebrow: 'Rendimiento',
                title: 'Forma y goles',
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final form = _FormPanel(
                    results: data.results,
                    clubName: club.name,
                  );
                  final goals = _GoalsPanel(row: data.ownRow);
                  if (constraints.maxWidth < 760) {
                    return Column(
                      children: [form, const SizedBox(height: 12), goals],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: form),
                      const SizedBox(width: 12),
                      Expanded(child: goals),
                    ],
                  );
                },
              ),
              SizedBox(height: narrow ? 14 : 20),
              PremiumSectionHeader(
                compact: narrow,
                eyebrow: 'Detalle',
                title: 'Lectura, plantel y tabla',
              ),
              _AutomaticReading(data: data),
              SizedBox(height: narrow ? 10 : 14),
              _PlayerLeaders(
                players: data.players,
                onTapPlayer: (id) {
                  for (final player in scope.fullClub.players) {
                    if (player.id == id) {
                      openPlayerProfile(context, player);
                      return;
                    }
                  }
                },
              ),
              SizedBox(height: narrow ? 10 : 14),
              _TablePanel(table: data.standings),
            ],
          );
        },
      ),
    );
  }
}

class _StatsData {
  final LudStandingsTable? standings;
  final List<LudFixtureMatch> results;
  final List<_PlayerStat> players;

  const _StatsData({
    this.standings,
    this.results = const [],
    this.players = const [],
  });

  LudStandingRow? get ownRow => standings?.ownRow;
}

class _PlayerStat {
  final String id;
  final String name;
  final String position;
  final int matches;
  final int minutes;
  final int goals;
  final int assists;
  final int yellowCards;
  final double attendanceRate;

  const _PlayerStat({
    this.id = '',
    required this.name,
    required this.position,
    required this.matches,
    required this.minutes,
    required this.goals,
    this.assists = 0,
    this.yellowCards = 0,
    this.attendanceRate = 0,
  });

  int get goalContributions => goals + assists;
  bool get hasData => matches > 0 || minutes > 0 || goalContributions > 0;
}

/// League averages for the selected category, derived from the standings table.
/// Null when the table is too thin to average.
class _CategoryAverages {
  final int teamCount;
  final double pointsPerGame;
  final double goalsForPerGame;
  final double goalsAgainstPerGame;
  final int? attackRank; // own rank by goals for (1 = best)
  final int? defenseRank; // own rank by goals against (1 = best)

  const _CategoryAverages({
    required this.teamCount,
    required this.pointsPerGame,
    required this.goalsForPerGame,
    required this.goalsAgainstPerGame,
    this.attackRank,
    this.defenseRank,
  });

  static _CategoryAverages? from(LudStandingsTable? table) {
    final rows = (table?.rows ?? const <LudStandingRow>[])
        .where((r) => r.played > 0)
        .toList();
    if (rows.length < 3) return null;
    final games = rows.fold<int>(0, (s, r) => s + r.played);
    if (games == 0) return null;
    int? attackRank;
    int? defenseRank;
    final own = table?.ownRow;
    if (own != null && own.played > 0) {
      final byAttack = [...rows]
        ..sort((a, b) => b.goalsFor.compareTo(a.goalsFor));
      final byDefense = [...rows]
        ..sort((a, b) => a.goalsAgainst.compareTo(b.goalsAgainst));
      final a = byAttack.indexWhere((r) => r.isOwnTeam);
      final d = byDefense.indexWhere((r) => r.isOwnTeam);
      attackRank = a < 0 ? null : a + 1;
      defenseRank = d < 0 ? null : d + 1;
    }
    return _CategoryAverages(
      teamCount: rows.length,
      pointsPerGame: rows.fold<int>(0, (s, r) => s + r.points) / games,
      goalsForPerGame: rows.fold<int>(0, (s, r) => s + r.goalsFor) / games,
      goalsAgainstPerGame:
          rows.fold<int>(0, (s, r) => s + r.goalsAgainst) / games,
      attackRank: attackRank,
      defenseRank: defenseRank,
    );
  }
}

enum _Confidence { alta, media, baja }

/// The headline read: 3-5 deterministic sentences built only from real rows,
/// with a confidence badge and an explicit note when the sample is short.
class _WeekReading extends StatelessWidget {
  final String clubName;
  final String category;
  final _StatsData data;
  final bool isLud;

  const _WeekReading({
    required this.clubName,
    required this.category,
    required this.data,
    required this.isLud,
  });

  bool _sameClub(String value) {
    String clean(String t) =>
        t.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final l = clean(value);
    final r = clean(clubName);
    return l.isNotEmpty &&
        r.isNotEmpty &&
        (l == r || l.contains(r) || r.contains(l));
  }

  bool _isHome(LudFixtureMatch m) {
    final opp = m.opponentName.trim();
    if (opp.isNotEmpty) return m.awayTeamName.trim() == opp;
    return _sameClub(m.homeTeamName);
  }

  ({int w, int d, int l, int pts}) _record(List<LudFixtureMatch> matches) {
    var w = 0, d = 0, l = 0;
    for (final m in matches) {
      final home = _isHome(m);
      final gf = home ? m.homeScore! : m.awayScore!;
      final ga = home ? m.awayScore! : m.homeScore!;
      if (gf > ga) {
        w++;
      } else if (gf == ga) {
        d++;
      } else {
        l++;
      }
    }
    return (w: w, d: d, l: l, pts: w * 3 + d);
  }

  @override
  Widget build(BuildContext context) {
    final row = data.ownRow;
    final title = '$clubName · $category';

    if (row == null || row.played == 0) {
      return _shell(
        title: title,
        confidence: null,
        lines: const [],
        empty: isLud
            ? 'La liga todavía no publicó partidos jugados para esta categoría.'
            : 'Todavía no hay datos de liga para esta categoría.',
      );
    }

    final avg = _CategoryAverages.from(data.standings);
    final played = data.results.where((m) => m.isPlayedResult).toList();
    final scoring = row.goalsFor / row.played;
    final conceding = row.goalsAgainst / row.played;
    final pointsRate = row.points / (row.played * 3);

    final lines = <String>[];

    // 1. Posición y ritmo de puntos.
    final rateText = '${(pointsRate * 100).round()}% de los puntos en juego';
    lines.add(
      avg == null
          ? '${row.rank}° con ${row.points} pts en ${row.played} partidos — $rateText.'
          : '${row.rank}° con ${row.points} pts — $rateText, '
                '${_cmp(pointsRate, avg.pointsPerGame / 3, tol: 0.05)} la media de la categoría '
                '(${(avg.pointsPerGame / 3 * 100).round()}%).',
    );

    // 2. Ataque.
    if (scoring >= 1.4) {
      lines.add(
        'Ataque productivo: ${scoring.toStringAsFixed(1)} goles por partido'
        '${avg?.attackRank != null && avg!.attackRank! <= 3 ? ' — 3° o mejor de la categoría' : ''}.',
      );
    } else {
      lines.add(
        'Producción ofensiva baja: ${scoring.toStringAsFixed(1)} goles por partido'
        '${avg != null ? ', ${_cmp(scoring, avg.goalsForPerGame)} la media (${avg.goalsForPerGame.toStringAsFixed(1)})' : ''}.',
      );
    }

    // 3. Defensa.
    if (conceding <= 1.1) {
      lines.add(
        'Defensa sólida: ${conceding.toStringAsFixed(1)} recibidos por partido'
        '${avg?.defenseRank != null && avg!.defenseRank! <= 3 ? ' — 3° o mejor de la categoría' : ''}.',
      );
    } else {
      lines.add(
        'Cuidar la defensa: ${conceding.toStringAsFixed(1)} recibidos por partido'
        '${avg != null ? ', ${_cmp(conceding, avg.goalsAgainstPerGame)} la media (${avg.goalsAgainstPerGame.toStringAsFixed(1)})' : ''}.',
      );
    }

    // 4. Forma reciente (últimos 5 resultados reales).
    if (played.length >= 3) {
      final last5 = played.take(5).toList();
      final rec = _record(last5);
      final prev5 = played.skip(5).take(5).toList();
      var trend = '';
      if (prev5.length >= 3) {
        final prev = _record(prev5);
        trend = rec.pts > prev.pts
            ? ' — en alza (venía de ${prev.pts})'
            : rec.pts < prev.pts
            ? ' — en baja (venía de ${prev.pts})'
            : '';
      }
      lines.add(
        'Últimos ${last5.length}: ${rec.w}G ${rec.d}E ${rec.l}P, ${rec.pts} pts$trend.',
      );
    }

    // 5. Local vs visitante.
    if (played.length >= 4) {
      final home = _record(played.where(_isHome).toList());
      final away = _record(played.where((m) => !_isHome(m)).toList());
      final homeGames = home.w + home.d + home.l;
      final awayGames = away.w + away.d + away.l;
      if (homeGames >= 2 && awayGames >= 2) {
        final homeRate = home.pts / (homeGames * 3);
        final awayRate = away.pts / (awayGames * 3);
        if ((homeRate - awayRate).abs() >= 0.25) {
          lines.add(
            homeRate > awayRate
                ? 'Rendís mejor de local: ${home.pts} pts en $homeGames vs ${away.pts} en $awayGames de visitante.'
                : 'Rendís mejor de visitante: ${away.pts} pts en $awayGames vs ${home.pts} en $homeGames de local.',
          );
        }
      }
    }

    final confidence = row.played >= 8 && played.length >= 4
        ? _Confidence.alta
        : row.played >= 4
        ? _Confidence.media
        : _Confidence.baja;

    final limits = <String>[
      if (row.played < 4)
        'Datos de ${row.played} partido${row.played == 1 ? '' : 's'}: tomalo como tendencia preliminar.',
      if (played.length < 3)
        'Pocos resultados recientes disponibles para leer la forma.',
      if (avg == null) 'Sin tabla completa de la categoría para comparar.',
    ];

    final recent5 = played.take(5).toList();
    final rec = _record(recent5);
    final focus = deriveSessionFocus(
      scoring: scoring,
      conceding: conceding,
      leagueScoring: avg?.goalsForPerGame,
      leagueConceding: avg?.goalsAgainstPerGame,
      played: row.played,
      formSummary: recent5.isEmpty
          ? '${row.rank}° en la tabla'
          : '${row.rank}° · últimos ${recent5.length}: ${rec.w}G ${rec.d}E ${rec.l}P',
    );
    final atRisk = data.players.where((p) => p.yellowCards >= 4).toList();

    return _shell(
      title: title,
      confidence: confidence,
      lines: lines,
      limits: limits,
      actions: _readingActions(
        focus: focus,
        offerMatchPrep: isLud,
        suspensionRisk: atRisk,
      ),
    );
  }

  List<_ReadingAction> _readingActions({
    required SessionFocusHandoff? focus,
    required bool offerMatchPrep,
    required List<_PlayerStat> suspensionRisk,
  }) {
    final actions = <_ReadingAction>[];
    if (focus != null) {
      actions.add(
        _ReadingAction(
          label: 'Preparar entrenamiento con este foco',
          icon: Icons.auto_awesome,
          primary: true,
          run: (context) =>
              ShellActions.of(context).openPlannerWithFocus(focus),
        ),
      );
    }
    // One secondary at most. Suspension risk is the more time-sensitive nudge.
    if (suspensionRisk.isNotEmpty) {
      actions.add(
        _ReadingAction(
          label: 'Revisar citación',
          icon: Icons.how_to_reg_outlined,
          primary: false,
          run: (context) => ShellActions.of(context).openLineup(
            LineupHint(
              reason: suspensionRisk.length == 1
                  ? '${suspensionRisk.first.name} en riesgo de suspensión'
                  : '${suspensionRisk.length} jugadores con 4+ amarillas',
              players: suspensionRisk.map((p) => p.name).toList(),
            ),
          ),
        ),
      );
    } else if (offerMatchPrep) {
      actions.add(
        _ReadingAction(
          label: 'Preparar el próximo partido',
          icon: Icons.sports_soccer_outlined,
          primary: false,
          run: (context) => ShellActions.of(context).openMatchPrep(
            const MatchPrepHandoff(origin: 'Lectura de la semana'),
          ),
        ),
      );
    }
    return actions;
  }

  /// "sobre" / "bajo" / "en" [reference], comparing [value].
  String _cmp(double value, double reference, {double tol = 0.1}) {
    if ((value - reference).abs() <= tol) return 'en';
    return value > reference ? 'sobre' : 'bajo';
  }

  Widget _shell({
    required String title,
    required _Confidence? confidence,
    required List<String> lines,
    List<String> limits = const [],
    List<_ReadingAction> actions = const [],
    String? empty,
  }) {
    return InsightCard(
      icon: Icons.auto_graph,
      title: 'Lectura de la semana',
      subtitle: title,
      badge: confidence == null
          ? null
          : ConfidenceBadge(_kitConfidence(confidence)),
      notes: limits,
      actions: actions.isEmpty
          ? null
          : ActionStrip(
              onDark: true,
              actions: [
                for (final a in actions)
                  ActionSpec(
                    label: a.label,
                    icon: a.icon,
                    primary: a.primary,
                    onTap: a.run,
                  ),
              ],
            ),
      child: empty != null
          ? Text(
              empty,
              style: const TextStyle(
                color: Color(0xFFE8F1ED),
                fontSize: 13,
                height: 1.45,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final line in lines) InsightLine(line)],
            ),
    );
  }
}

/// One contextual action offered under a reading.
class _ReadingAction {
  final String label;
  final IconData icon;
  final bool primary;
  final void Function(BuildContext context) run;

  const _ReadingAction({
    required this.label,
    required this.icon,
    required this.primary,
    required this.run,
  });
}

Confidence _kitConfidence(_Confidence c) => switch (c) {
  _Confidence.alta => Confidence.alta,
  _Confidence.media => Confidence.media,
  _Confidence.baja => Confidence.baja,
};

class _Metric {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String context; // one short line: comparison / verdict / "sin datos"
  const _Metric(this.label, this.value, this.icon, this.color, this.context);
}

class _MetricGrid extends StatelessWidget {
  final _StatsData data;
  final List<AttendanceRecord> attendanceRecords;
  const _MetricGrid({required this.data, required this.attendanceRecords});

  @override
  Widget build(BuildContext context) {
    final row = data.ownRow;
    final avg = _CategoryAverages.from(data.standings);

    List<_Metric> items;
    if (row == null || row.played == 0) {
      items = const [
        _Metric('Posición', '—', Icons.emoji_events, CX.amber, 'Sin tabla'),
        _Metric('Puntos', '—', Icons.stars, CX.blue, 'Sin datos'),
        _Metric(
          'Puntos obtenidos',
          '—',
          Icons.trending_up,
          CX.green,
          'Sin datos',
        ),
        _Metric('Goles a favor', '—', Icons.sports_soccer, CX.red, 'Sin datos'),
      ];
    } else {
      final pointsRate = row.points / (row.played * 3);
      final scoring = row.goalsFor / row.played;
      final conceding = row.goalsAgainst / row.played;
      final leagueRate = avg == null ? null : avg.pointsPerGame / 3;

      items = [
        _Metric(
          'Posición',
          '${row.rank}°',
          Icons.emoji_events,
          CX.amber,
          avg == null ? '${row.played} PJ' : 'de ${avg.teamCount} equipos',
        ),
        _Metric(
          'Puntos',
          '${row.points}',
          Icons.stars,
          CX.blue,
          '${row.won}G ${row.drawn}E ${row.lost}P',
        ),
        _Metric(
          'Puntos obtenidos',
          '${(pointsRate * 100).round()}%',
          Icons.trending_up,
          CX.green,
          leagueRate == null
              ? 'de los disputados'
              : _verdict(
                  pointsRate,
                  leagueRate,
                  0.05,
                  '(media ${(leagueRate * 100).round()}%)',
                ),
        ),
        _Metric(
          'Goles / partido',
          scoring.toStringAsFixed(1),
          Icons.sports_soccer,
          CX.red,
          avg == null
              ? '${row.goalsFor} a favor'
              : '${_verdict(scoring, avg.goalsForPerGame, 0.15, '')}'
                    '${avg.attackRank != null ? ' · ${avg.attackRank}° ataque' : ''}',
        ),
        _Metric(
          'Recibidos / partido',
          conceding.toStringAsFixed(1),
          Icons.shield_outlined,
          conceding <= 1.1 ? CX.green : CX.amber,
          avg == null
              ? '${row.goalsAgainst} en contra'
              : '${_verdict(conceding, avg.goalsAgainstPerGame, 0.15, '')}'
                    '${avg.defenseRank != null ? ' · ${avg.defenseRank}° defensa' : ''}',
        ),
      ];
    }

    final attendance = summarizeAttendance(attendanceRecords).average;
    items = [
      ...items,
      _Metric(
        'Asistencia',
        attendance == null ? '—' : '${(attendance * 100).round()}%',
        Icons.fact_check_outlined,
        attendance == null
            ? CX.faint
            : attendance >= .8
            ? CX.green
            : CX.amber,
        attendance == null ? 'Sin registros' : 'promedio del plantel',
      ),
    ];

    return MetricGrid(
      tiles: [
        for (final item in items)
          MetricTile(
            icon: item.icon,
            value: item.value,
            label: item.label,
            context: item.context,
            accent: item.color,
          ),
      ],
    );
  }

  /// Literal position of [value] against [reference] ("sobre / bajo / en la
  /// media"). The reader interprets whether that is good or bad from the label
  /// ("Goles / partido" vs "Recibidos / partido").
  String _verdict(double value, double reference, double tol, String suffix) {
    final within = (value - reference).abs() <= tol;
    final word = within
        ? 'en la media'
        : value > reference
        ? 'sobre la media'
        : 'bajo la media';
    return suffix.isEmpty ? word : '$word $suffix';
  }
}

class _FormPanel extends StatelessWidget {
  final List<LudFixtureMatch> results;
  final String clubName;
  const _FormPanel({required this.results, required this.clubName});

  bool _sameClub(String value) {
    String clean(String text) =>
        text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final left = clean(value);
    final right = clean(clubName);
    return left.isNotEmpty &&
        right.isNotEmpty &&
        (left == right || left.contains(right) || right.contains(left));
  }

  bool _isHome(LudFixtureMatch match) {
    final opponent = match.opponentName.trim();
    if (opponent.isNotEmpty) return match.awayTeamName.trim() == opponent;
    return _sameClub(match.homeTeamName);
  }

  @override
  Widget build(BuildContext context) {
    // loadResults already returns the last five real results, newest first.
    final recent = results
        .where((match) => match.isPlayedResult)
        .take(5)
        .toList()
        .reversed
        .toList();
    if (recent.isEmpty) {
      return const _Panel(
        title: 'Forma reciente',
        icon: Icons.timeline,
        child: _NoData(),
      );
    }
    var points = 0;
    var wins = 0;
    var draws = 0;
    for (final match in recent) {
      final home = _isHome(match);
      final gf = home ? match.homeScore! : match.awayScore!;
      final ga = home ? match.awayScore! : match.homeScore!;
      if (gf > ga) {
        points += 3;
        wins++;
      } else if (gf == ga) {
        points += 1;
        draws++;
      }
    }
    final losses = recent.length - wins - draws;
    return _Panel(
      title: 'Forma reciente',
      icon: Icons.timeline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final match in recent)
                Builder(
                  builder: (_) {
                    final home = _isHome(match);
                    final gf = home ? match.homeScore! : match.awayScore!;
                    final ga = home ? match.awayScore! : match.homeScore!;
                    final rival = match.opponentName.trim().isNotEmpty
                        ? match.opponentName.trim()
                        : (home ? match.awayTeamName : match.homeTeamName)
                              .trim();
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: FormPill(
                          outcome: gf == ga ? 'E' : (gf > ga ? 'G' : 'P'),
                          score: '$gf-$ga',
                          rival: rival,
                          home: home,
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$wins G · $draws E · $losses P — $points de ${recent.length * 3} pts',
            style: const TextStyle(
              color: CX.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalsPanel extends StatelessWidget {
  final LudStandingRow? row;
  const _GoalsPanel({required this.row});

  @override
  Widget build(BuildContext context) {
    final total = row == null ? 0 : row!.goalsFor + row!.goalsAgainst;
    final share = total == 0 ? 0.0 : row!.goalsFor / total;
    return _Panel(
      title: 'Balance de goles',
      icon: Icons.balance,
      child: row == null
          ? const _NoData()
          : Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${row!.goalsFor} a favor',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${row!.goalsAgainst} recibidos',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 18,
                    value: share,
                    color: CX.green,
                    backgroundColor: CX.red.withValues(alpha: .55),
                  ),
                ),
                const SizedBox(height: 13),
                Text(
                  row!.played == 0
                      ? 'Sin partidos computados.'
                      : '${(row!.goalsFor / row!.played).toStringAsFixed(1)} goles convertidos por partido.',
                  style: const TextStyle(color: CX.muted, fontSize: 12),
                ),
              ],
            ),
    );
  }
}

class _AutomaticReading extends StatelessWidget {
  final _StatsData data;
  const _AutomaticReading({required this.data});

  @override
  Widget build(BuildContext context) {
    final row = data.ownRow;
    final messages = <String>[];

    // Table context: distance to positions above.
    final rows = data.standings?.rows ?? const <LudStandingRow>[];
    if (row != null && rows.isNotEmpty && row.rank > 1) {
      final above = rows.firstWhere(
        (r) => r.rank == row.rank - 1,
        orElse: () => row,
      );
      if (above.rank == row.rank - 1) {
        final gap = above.points - row.points;
        messages.add(
          gap <= 0
              ? 'Igualás en puntos al ${above.rank}° (${above.teamName}); te separa la diferencia de gol.'
              : 'Estás a $gap ${gap == 1 ? 'punto' : 'puntos'} del ${above.rank}° (${above.teamName}).',
        );
      }
    }

    // Streak from the last 3 results, own perspective. Needs the opponent side
    // to be resolvable; skip the rule otherwise.
    final recent = data.results.where((m) => m.isPlayedResult).take(3).toList();
    if (recent.length == 3) {
      int? ownDiff(LudFixtureMatch m) {
        final opp = m.opponentName.trim();
        if (opp.isEmpty || m.homeScore == null || m.awayScore == null) {
          return null;
        }
        final clubHome = m.awayTeamName.trim() == opp;
        final gf = clubHome ? m.homeScore! : m.awayScore!;
        final ga = clubHome ? m.awayScore! : m.homeScore!;
        return gf - ga;
      }

      final diffs = recent.map(ownDiff).toList();
      if (!diffs.contains(null)) {
        if (diffs.every((d) => d! > 0)) {
          messages.add(
            '3 victorias al hilo: el equipo está fino, sostener la idea.',
          );
        } else if (diffs.every((d) => d! <= 0)) {
          messages.add(
            '3 partidos seguidos sin ganar: revisar por qué se corta el rendimiento.',
          );
        }
      }
    }

    // Goal concentration + top scorer, from typed player stats.
    final scorers = [...data.players.where((p) => p.goalContributions > 0)]
      ..sort((a, b) => b.goalContributions.compareTo(a.goalContributions));
    if (scorers.isNotEmpty) {
      final totalGoals = data.players.fold<int>(0, (s, p) => s + p.goals);
      final top = scorers.first;
      messages.add(
        top.assists > 0
            ? '${top.name} es el más determinante: ${top.goals} goles y ${top.assists} asistencias.'
            : '${top.name} lidera el goleo del plantel con ${top.goals}.',
      );
      if (totalGoals >= 6 && scorers.length >= 2) {
        final topTwo = scorers.take(2).fold<int>(0, (s, p) => s + p.goals);
        final share = (topTwo / totalGoals * 100).round();
        if (share >= 55) {
          messages.add(
            'El gol depende de pocos: 2 jugadores concentran el $share% de los goles del plantel.',
          );
        }
      }
    }

    // Suspension risk from yellow cards.
    final atRisk = data.players.where((p) => p.yellowCards >= 4).toList();
    if (atRisk.isNotEmpty) {
      messages.add(
        atRisk.length == 1
            ? '${atRisk.first.name} acumula ${atRisk.first.yellowCards} amarillas: cuidar la suspensión.'
            : '${atRisk.length} jugadores con 4+ amarillas: riesgo de suspensión.',
      );
    }

    return _Panel(
      title: 'Otras señales',
      icon: Icons.insights,
      accent: CX.green,
      child: messages.isEmpty
          ? const _NoData()
          : Column(
              children: messages
                  .map(
                    (message) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.arrow_right, color: CX.green),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              message,
                              style: const TextStyle(height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _PlayerLeaders extends StatelessWidget {
  final List<_PlayerStat> players;

  /// False for No-LUD categories: minutos/asistencias/amarillas nunca se
  /// cargan a mano ahí, así que mostrarlas sería un 0 que parece un dato
  /// real cuando en verdad nunca se registró. Solo Goles/PJ, que desde esta
  /// ronda sí son reales para categorías manuales.
  final bool showFullColumns;
  final void Function(String playerId)? onTapPlayer;
  const _PlayerLeaders({
    required this.players,
    this.showFullColumns = true,
    this.onTapPlayer,
  });

  @override
  Widget build(BuildContext context) {
    final withData = players
        .where(
          (p) => showFullColumns ? p.hasData : (p.goals > 0 || p.matches > 0),
        )
        .toList();
    if (withData.isEmpty) {
      return const _Panel(
        title: 'Jugadores',
        icon: Icons.groups_2_outlined,
        child: _NoData(),
      );
    }
    // Goal contributions first, then minutes as the tiebreaker / participation
    // proxy.
    final ranked = [...withData]
      ..sort((a, b) {
        final byContribution = b.goalContributions.compareTo(
          a.goalContributions,
        );
        return byContribution != 0
            ? byContribution
            : b.minutes.compareTo(a.minutes);
      });
    return _Panel(
      title: 'Jugadores',
      icon: Icons.groups_2_outlined,
      child: Column(
        children: [
          Row(
            children: [
              const Spacer(),
              const _ColHead('G', 34),
              if (showFullColumns) ...const [_ColHead('A', 34)],
              const _ColHead('PJ', 40),
              if (showFullColumns) ...const [_ColHead('min', 56)],
            ],
          ),
          const SizedBox(height: 4),
          ...ranked.map((player) {
            final risk = player.yellowCards >= 4;
            final canTap = onTapPlayer != null && player.id.isNotEmpty;
            return InkWell(
              onTap: canTap ? () => onTapPlayer!(player.id) : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 14,
                      backgroundColor: CX.greenDark,
                      child: Icon(
                        Icons.person_outline,
                        size: 16,
                        color: CX.green,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  player.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (risk) ...[
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  size: 13,
                                  color: CX.amber,
                                ),
                              ],
                            ],
                          ),
                          Text(
                            player.position.isEmpty
                                ? 'Sin posición cargada'
                                : player.position,
                            style: const TextStyle(
                              color: CX.faint,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _Cell('${player.goals}', 34, bold: player.goals > 0),
                    if (showFullColumns) ...[_Cell('${player.assists}', 34)],
                    _Cell('${player.matches}', 40),
                    if (showFullColumns) ...[_Cell('${player.minutes}', 56)],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ColHead extends StatelessWidget {
  final String text;
  final double width;
  const _ColHead(this.text, this.width);
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Text(
      text,
      textAlign: TextAlign.right,
      style: const TextStyle(
        color: CX.faint,
        fontSize: 10,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _Cell extends StatelessWidget {
  final String text;
  final double width;
  final bool bold;
  const _Cell(this.text, this.width, {this.bold = false});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Text(
      text,
      textAlign: TextAlign.right,
      style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w600),
    ),
  );
}

class _TablePanel extends StatelessWidget {
  final LudStandingsTable? table;
  const _TablePanel({required this.table});

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Tabla de la categoría',
      icon: Icons.leaderboard_outlined,
      child: table == null || table!.rows.isEmpty
          ? const _NoData()
          : Column(
              children: table!.rows.map((row) {
                return Container(
                  color: row.isOwnTeam ? CX.greenDark : Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      SizedBox(width: 28, child: Text('${row.rank}')),
                      Expanded(
                        child: Text(
                          row.teamName,
                          style: TextStyle(
                            fontWeight: row.isOwnTeam
                                ? FontWeight.w900
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 34,
                        child: Text(
                          '${row.played}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      SizedBox(
                        width: 42,
                        child: Text(
                          '${row.goalDifference >= 0 ? '+' : ''}${row.goalDifference}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      SizedBox(
                        width: 38,
                        child: Text(
                          '${row.points}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Color accent;

  const _Panel({
    required this.title,
    required this.icon,
    required this.child,
    this.accent = CX.blue,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 700;
    return Container(
      padding: EdgeInsets.all(narrow ? 12 : 18),
      decoration: CX.panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 9),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _NoData extends StatelessWidget {
  const _NoData();

  @override
  Widget build(BuildContext context) => const Text(
    'La liga todavía no publicó datos suficientes para esta lectura.',
    style: TextStyle(color: CX.muted, fontSize: 12),
  );
}

// ===========================================================================
// No-LUD: statistics built entirely from match results the coach logs by hand.
// ===========================================================================

class _NoLudStatsBody extends StatelessWidget {
  final String clubName;
  final String category;
  final String categoryId;
  final List<MatchResult> allResults;
  final List<Player> players;
  final List<AttendanceRecord> attendanceRecords;
  final ValueChanged<List<MatchResult>> onChanged;
  final VoidCallback onGenerateReport;

  const _NoLudStatsBody({
    required this.clubName,
    required this.category,
    required this.categoryId,
    required this.allResults,
    required this.players,
    required this.attendanceRecords,
    required this.onChanged,
    required this.onGenerateReport,
  });

  Future<void> _add(BuildContext context) async {
    final result = await showMatchResultDialog(
      context,
      categoryId: categoryId,
      players: players,
    );
    if (result != null) onChanged([...allResults, result]);
  }

  Future<void> _edit(BuildContext context, MatchResult existing) async {
    final result = await showMatchResultDialog(
      context,
      categoryId: categoryId,
      existing: existing,
      players: players,
    );
    if (result != null) {
      onChanged([
        for (final r in allResults)
          if (r.id == existing.id) result else r,
      ]);
    }
  }

  Future<void> _delete(BuildContext context, MatchResult target) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar resultado'),
        content: Text(
          'Vas a borrar ${target.opponent} ${target.goalsFor}-${target.goalsAgainst}. '
          'No se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      onChanged([
        for (final r in allResults)
          if (r.id != target.id) r,
      ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = MatchStats.forCategory(allResults, categoryId);
    final narrow = MediaQuery.sizeOf(context).width < 700;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        narrow ? 14 : 20,
        narrow ? 8 : 12,
        narrow ? 14 : 20,
        narrow ? 24 : 36,
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$clubName · $category',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: CX.muted,
                ),
              ),
            ),
            if (summary.all.isNotEmpty)
              TextButton.icon(
                onPressed: () => _add(context),
                icon: const Icon(Icons.add, size: 17),
                label: const Text('Cargar resultado'),
              ),
          ],
        ),
        if (players.isNotEmpty) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onGenerateReport,
              icon: const Icon(Icons.summarize_outlined, size: 17),
              label: const Text('Generar reporte del plantel'),
            ),
          ),
        ],
        const SizedBox(height: 6),
        if (summary.all.isEmpty)
          _NoLudEmpty(onAdd: () => _add(context))
        else ...[
          _NoLudReading(summary: summary),
          SizedBox(height: narrow ? 14 : 20),
          PremiumSectionHeader(
            compact: narrow,
            eyebrow: 'Panorama',
            title: 'Números del equipo',
          ),
          _NoLudMetrics(
            summary: summary,
            attendanceAverage: summarizeAttendance(attendanceRecords).average,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  ShellActions.of(context).openSection(ShellSection.attendance),
              icon: const Icon(Icons.history, size: 17),
              label: const Text('Ver historial de asistencia'),
            ),
          ),
          SizedBox(height: narrow ? 14 : 20),
          PremiumSectionHeader(
            compact: narrow,
            eyebrow: 'Rendimiento',
            title: 'Forma reciente',
          ),
          _NoLudForm(summary: summary),
          SizedBox(height: narrow ? 14 : 20),
          PremiumSectionHeader(
            compact: narrow,
            eyebrow: 'Plantel',
            title: 'Goleadores',
          ),
          _PlayerLeaders(
            showFullColumns: false,
            players: [
              for (final player in players)
                _PlayerStat(
                  id: player.id,
                  name: player.fullName.trim(),
                  position: player.position.trim(),
                  matches: player.matchesPlayed,
                  minutes: player.minutesPlayed,
                  goals: player.goals,
                  assists: player.assists,
                  yellowCards: player.yellowCards,
                ),
            ],
            onTapPlayer: (id) {
              for (final player in players) {
                if (player.id == id) {
                  openPlayerProfile(context, player);
                  return;
                }
              }
            },
          ),
          SizedBox(height: narrow ? 14 : 20),
          PremiumSectionHeader(
            compact: narrow,
            eyebrow: 'Historial',
            title: 'Resultados cargados',
          ),
          _NoLudResultsList(
            results: summary.all,
            playerNames: {for (final p in players) p.id: p.fullName.trim()},
            onEdit: (r) => _edit(context, r),
            onDelete: (r) => _delete(context, r),
          ),
        ],
      ],
    );
  }
}

class _NoLudEmpty extends StatelessWidget {
  final VoidCallback onAdd;
  const _NoLudEmpty({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return EmptyStatePanel(
      icon: Icons.scoreboard_outlined,
      title: 'Todavía no cargaste resultados',
      message:
          'Cargá los partidos de tu equipo y fobal arma la tabla, la '
          'forma reciente y una lectura de cómo viene el rendimiento.',
      primaryLabel: 'Cargar el primer resultado',
      onPrimary: onAdd,
    );
  }
}

class _NoLudReading extends StatelessWidget {
  final MatchStats summary;
  const _NoLudReading({required this.summary});

  @override
  Widget build(BuildContext context) {
    final lines = <String>[];
    final limits = <String>[];
    _Confidence? confidence;

    if (summary.played == 0) {
      lines.add(
        summary.all.isEmpty
            ? 'Sin partidos cargados.'
            : 'Cargaste ${summary.all.length} amistoso(s) o práctica(s). '
                  'Sumá partidos oficiales para ver la lectura de rendimiento.',
      );
    } else {
      final s = summary;
      confidence = s.played >= 6
          ? _Confidence.alta
          : s.played >= 3
          ? _Confidence.media
          : _Confidence.baja;

      lines.add(
        '${s.wins}G ${s.draws}E ${s.losses}P en ${s.played} '
        'partido${s.played == 1 ? '' : 's'} — '
        '${(s.pointsRate * 100).round()}% de los puntos en juego.',
      );

      if (s.played >= 3) {
        lines.add(
          s.scoring >= 2
              ? 'Ataque prolífico: ${s.scoring.toStringAsFixed(1)} goles por partido.'
              : s.scoring < 1
              ? 'Cuesta convertir: ${s.scoring.toStringAsFixed(1)} goles por partido.'
              : 'Convertís ${s.scoring.toStringAsFixed(1)} goles por partido.',
        );
        lines.add(
          s.conceding <= 1
              ? 'Defensa firme: ${s.conceding.toStringAsFixed(1)} recibidos por partido.'
              : s.conceding > 1.6
              ? 'La defensa es lo primero a mejorar: ${s.conceding.toStringAsFixed(1)} recibidos por partido.'
              : 'Recibís ${s.conceding.toStringAsFixed(1)} por partido.',
        );
        final last = s.last5;
        final w = last.where((o) => o == 'G').length;
        final d = last.where((o) => o == 'E').length;
        final l = last.where((o) => o == 'P').length;
        lines.add('Últimos ${last.length}: ${w}G ${d}E ${l}P.');
        final st = s.streak;
        if (st.count >= 3) {
          lines.add('Venís de ${st.count} ${st.label}.');
        }
      }

      if (s.played < 4) {
        limits.add(
          'Pocos partidos (${s.played}): tomá las conclusiones como una '
          'tendencia preliminar.',
        );
      }
      if (s.friendlies > 0) {
        limits.add(
          '${s.friendlies} amistoso(s)/práctica(s) no cuentan para los puntos.',
        );
      }
    }

    final focus = summary.played >= 2
        ? deriveSessionFocus(
            scoring: summary.scoring,
            conceding: summary.conceding,
            played: summary.played,
            formSummary:
                'Últimos ${summary.last5.length}: '
                '${summary.last5.where((o) => o == 'G').length}G '
                '${summary.last5.where((o) => o == 'E').length}E '
                '${summary.last5.where((o) => o == 'P').length}P',
          )
        : null;

    return InsightCard(
      icon: Icons.auto_graph,
      title: 'Lectura de la semana',
      badge: confidence == null
          ? null
          : ConfidenceBadge(_kitConfidence(confidence)),
      notes: limits,
      actions: focus == null
          ? null
          : ActionStrip(
              onDark: true,
              actions: [
                ActionSpec(
                  label: 'Preparar entrenamiento con este foco',
                  icon: Icons.auto_awesome,
                  primary: true,
                  onTap: (context) =>
                      ShellActions.of(context).openPlannerWithFocus(focus),
                ),
              ],
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final line in lines) InsightLine(line)],
      ),
    );
  }
}

class _NoLudMetrics extends StatelessWidget {
  final MatchStats summary;
  final double? attendanceAverage;
  const _NoLudMetrics({required this.summary, this.attendanceAverage});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final hasCompetitive = s.played > 0;
    final items = <_Metric>[
      _Metric(
        'Partidos',
        '${s.played}',
        Icons.event_available,
        CX.blue,
        s.friendlies > 0 ? '+ ${s.friendlies} amistosos' : 'oficiales',
      ),
      _Metric(
        'Puntos',
        hasCompetitive ? '${s.points}' : '—',
        Icons.stars,
        CX.green,
        hasCompetitive
            ? '${s.wins}G ${s.draws}E ${s.losses}P'
            : 'sin oficiales',
      ),
      _Metric(
        'Puntos obtenidos',
        hasCompetitive ? '${(s.pointsRate * 100).round()}%' : '—',
        Icons.trending_up,
        CX.amber,
        'de los disputados',
      ),
      _Metric(
        'Diferencia de gol',
        hasCompetitive ? '${s.goalDiff >= 0 ? '+' : ''}${s.goalDiff}' : '—',
        Icons.swap_vert,
        s.goalDiff >= 0 ? CX.green : CX.red,
        hasCompetitive
            ? '${s.goalsFor} a favor / ${s.goalsAgainst} en contra'
            : '',
      ),
      _Metric(
        'Goles / partido',
        hasCompetitive ? s.scoring.toStringAsFixed(1) : '—',
        Icons.sports_soccer,
        CX.red,
        'convertidos',
      ),
      _Metric(
        'Recibidos / partido',
        hasCompetitive ? s.conceding.toStringAsFixed(1) : '—',
        Icons.shield_outlined,
        s.conceding <= 1 ? CX.green : CX.amber,
        'en contra',
      ),
    ];
    items.add(
      _Metric(
        'Asistencia',
        attendanceAverage == null
            ? '—'
            : '${(attendanceAverage! * 100).round()}%',
        Icons.fact_check_outlined,
        attendanceAverage == null
            ? CX.faint
            : attendanceAverage! >= .8
            ? CX.green
            : CX.amber,
        attendanceAverage == null ? 'Sin registros' : 'promedio del plantel',
      ),
    );

    return MetricGrid(
      tiles: [
        for (final item in items)
          MetricTile(
            icon: item.icon,
            value: item.value,
            label: item.label,
            context: item.context,
            accent: item.color,
          ),
      ],
    );
  }
}

class _NoLudForm extends StatelessWidget {
  final MatchStats summary;
  const _NoLudForm({required this.summary});

  @override
  Widget build(BuildContext context) {
    final recent = summary.competitive.take(5).toList().reversed.toList();
    if (recent.isEmpty) {
      return const _Panel(
        title: 'Detalle de los oficiales',
        icon: Icons.timeline,
        child: Text(
          'Cargá partidos oficiales para ver la forma reciente.',
          style: TextStyle(color: CX.muted, fontSize: 12),
        ),
      );
    }
    final points = recent.fold(0, (s, r) => s + r.points);
    final w = recent.where((r) => r.outcome == 'G').length;
    final d = recent.where((r) => r.outcome == 'E').length;
    final l = recent.length - w - d;
    return _Panel(
      title: 'Detalle de los oficiales',
      icon: Icons.timeline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final r in recent)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: FormPill(
                      outcome: r.outcome,
                      score: '${r.goalsFor}-${r.goalsAgainst}',
                      rival: r.opponent,
                      home: r.venue != 'away',
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$w G · $d E · $l P — $points de ${recent.length * 3} pts',
            style: const TextStyle(
              color: CX.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoLudResultsList extends StatelessWidget {
  final List<MatchResult> results;
  final Map<String, String> playerNames;
  final ValueChanged<MatchResult> onEdit;
  final ValueChanged<MatchResult> onDelete;

  const _NoLudResultsList({
    required this.results,
    this.playerNames = const {},
    required this.onEdit,
    required this.onDelete,
  });

  String _scorers(MatchResult r) {
    if (r.scorerIds.isEmpty) return '';
    final counts = <String, int>{};
    for (final id in r.scorerIds) {
      final name = playerNames[id];
      if (name == null || name.isEmpty) continue;
      counts[name] = (counts[name] ?? 0) + 1;
    }
    if (counts.isEmpty) return '';
    return counts.entries
        .map((e) => e.value > 1 ? '${e.key} (${e.value})' : e.key)
        .join(', ');
  }

  String _fmt(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Resultados cargados',
      icon: Icons.list_alt,
      child: Column(
        children: results.map((r) {
          final color = r.outcome == 'E'
              ? CX.amber
              : r.outcome == 'G'
              ? CX.green
              : CX.red;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    r.outcome,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${r.opponent}  ${r.goalsFor}-${r.goalsAgainst}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${_fmt(r.date)} · ${r.venueLabel}'
                        '${r.isCompetitive ? '' : ' · ${r.kindLabel}'}',
                        style: const TextStyle(color: CX.faint, fontSize: 10),
                      ),
                      if (_scorers(r).isNotEmpty)
                        Text(
                          'Goles: ${_scorers(r)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: CX.muted,
                            fontSize: 10.5,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Editar',
                  onPressed: () => onEdit(r),
                  icon: const Icon(Icons.edit_outlined, size: 17),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Borrar',
                  onPressed: () => onDelete(r),
                  icon: const Icon(Icons.delete_outline, size: 17),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

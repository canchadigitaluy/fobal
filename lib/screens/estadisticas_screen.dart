import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import '../services/club_access_service.dart';
import 'match_result_dialog.dart';

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
    ]);
    return _StatsData(
      standings: values[0] as LudStandingsTable?,
      results: values[1] as List<LudFixtureMatch>,
      players: _playerStats(players),
    );
  }

  ClubMembership? _previewMembership(
    CanteraClub club,
    CategorySquad category,
  ) {
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
            name: player.fullName.trim(),
            position: player.position.trim(),
            matches: player.matchesPlayed,
            minutes: player.minutesPlayed,
            goals: player.goals,
            assists: player.assists,
            yellowCards: player.yellowCards,
          ),
        )
        .where((player) => player.name.isNotEmpty)
        .toList();
  }

  void _refresh() {
    _key = null;
    _forceNextLoad = true;
    didChangeDependencies();
    setState(() {});
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
          final selectedCategoryId = scope.selectedCategoryId ??
              (scope.fullClub.categories.isEmpty
                  ? ''
                  : scope.fullClub.categories.first.id);
          final isLud = LudCategoryRef.teamIdOf(selectedCategoryId) != null;

          if (!isLud) {
            return _NoLudStatsBody(
              clubName: club.name,
              category: category,
              categoryId: selectedCategoryId,
              allResults: scope.fullClub.matchResults,
              onChanged: (next) => scope.updateClub(
                scope.fullClub.copyWith(matchResults: next),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            children: [
              _WeekReading(
                clubName: club.name,
                category: category,
                data: data,
                isLud: isLud,
              ),
              const SizedBox(height: 14),
              _MetricGrid(data: data),
              const SizedBox(height: 14),
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
              const SizedBox(height: 14),
              _AutomaticReading(data: data),
              const SizedBox(height: 14),
              _PlayerLeaders(players: data.players),
              const SizedBox(height: 14),
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
  final String name;
  final String position;
  final int matches;
  final int minutes;
  final int goals;
  final int assists;
  final int yellowCards;

  const _PlayerStat({
    required this.name,
    required this.position,
    required this.matches,
    required this.minutes,
    required this.goals,
    this.assists = 0,
    this.yellowCards = 0,
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
    String clean(String t) => t.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final l = clean(value);
    final r = clean(clubName);
    return l.isNotEmpty && r.isNotEmpty && (l == r || l.contains(r) || r.contains(l));
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

    return _shell(
      title: title,
      confidence: confidence,
      lines: lines,
      limits: limits,
    );
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
    String? empty,
  }) {
    const fg = Color(0xFFE8F1ED);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF102019),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_graph, color: Color(0xFF6EF2C7), size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Lectura de la semana',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .2,
                  ),
                ),
              ),
              if (confidence != null) _ConfidencePill(confidence),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFB8C5BF),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          if (empty != null)
            Text(empty, style: const TextStyle(color: fg, fontSize: 13, height: 1.4))
          else
            ...lines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6, right: 8),
                      child: _Dot(),
                    ),
                    Expanded(
                      child: Text(
                        line,
                        style: const TextStyle(
                          color: fg,
                          fontSize: 13.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (limits.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...limits.map(
              (l) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline,
                        size: 13, color: Color(0xFF8CA39B)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l,
                        style: const TextStyle(
                          color: Color(0xFF8CA39B),
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) => Container(
    width: 4,
    height: 4,
    decoration: const BoxDecoration(
      color: Color(0xFF6EF2C7),
      shape: BoxShape.circle,
    ),
  );
}

class _ConfidencePill extends StatelessWidget {
  final _Confidence level;
  const _ConfidencePill(this.level);

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (level) {
      _Confidence.alta => ('Confianza alta', const Color(0xFF6EF2C7)),
      _Confidence.media => ('Confianza media', CX.amber),
      _Confidence.baja => ('Confianza baja', const Color(0xFFFF9B9B)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

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
  const _MetricGrid({required this.data});

  @override
  Widget build(BuildContext context) {
    final row = data.ownRow;
    final avg = _CategoryAverages.from(data.standings);

    List<_Metric> items;
    if (row == null || row.played == 0) {
      items = const [
        _Metric('Posición', '—', Icons.emoji_events, CX.amber, 'Sin tabla'),
        _Metric('Puntos', '—', Icons.stars, CX.blue, 'Sin datos'),
        _Metric('Puntos obtenidos', '—', Icons.trending_up, CX.green, 'Sin datos'),
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
              : _verdict(pointsRate, leagueRate, 0.05,
                  '(media ${(leagueRate * 100).round()}%)'),
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

    return LayoutBuilder(
      builder: (context, constraints) => GridView.count(
        crossAxisCount: constraints.maxWidth < 650
            ? 2
            : (constraints.maxWidth < 980 ? 3 : items.length),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: constraints.maxWidth < 650 ? 1.35 : 1.5,
        children: items
            .map(
              (item) => Container(
                padding: const EdgeInsets.all(14),
                decoration: CX.panelDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(item.icon, color: item.color, size: 19),
                    Text(
                      item.value,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      item.label,
                      style: const TextStyle(color: CX.white, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      item.context,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: CX.faint, fontSize: 10, height: 1.25),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
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
            children: recent.map((match) {
              final home = _isHome(match);
              final gf = home ? match.homeScore! : match.awayScore!;
              final ga = home ? match.awayScore! : match.homeScore!;
              final draw = gf == ga;
              final won = gf > ga;
              final rival = match.opponentName.trim().isNotEmpty
                  ? match.opponentName.trim()
                  : (home ? match.awayTeamName : match.homeTeamName).trim();
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    children: [
                      Container(
                        height: 58,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: draw
                              ? CX.amber.withValues(alpha: .75)
                              : won
                              ? CX.green.withValues(alpha: .8)
                              : CX.red.withValues(alpha: .7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          draw ? 'E' : (won ? 'G' : 'P'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            home ? Icons.home : Icons.flight_takeoff,
                            size: 10,
                            color: CX.faint,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '$gf-$ga',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        rival,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: CX.faint, fontSize: 8.5),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
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
                    Text('${row!.goalsFor} a favor', style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text('${row!.goalsAgainst} recibidos', style: const TextStyle(fontWeight: FontWeight.w800)),
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
                          Expanded(child: Text(message, style: const TextStyle(height: 1.4))),
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
  const _PlayerLeaders({required this.players});

  @override
  Widget build(BuildContext context) {
    final withData = players.where((p) => p.hasData).toList();
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
        final byContribution = b.goalContributions.compareTo(a.goalContributions);
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
            children: const [
              Spacer(),
              _ColHead('G', 34),
              _ColHead('A', 34),
              _ColHead('PJ', 40),
              _ColHead('min', 56),
            ],
          ),
          const SizedBox(height: 4),
          ...ranked.take(10).map((player) {
            final risk = player.yellowCards >= 4;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 14,
                    backgroundColor: CX.greenDark,
                    child: Icon(Icons.person_outline, size: 16, color: CX.green),
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
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            if (risk) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.warning_amber_rounded,
                                  size: 13, color: CX.amber),
                            ],
                          ],
                        ),
                        Text(
                          player.position.isEmpty
                              ? 'Sin posición cargada'
                              : player.position,
                          style: const TextStyle(color: CX.faint, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  _Cell('${player.goals}', 34, bold: player.goals > 0),
                  _Cell('${player.assists}', 34),
                  _Cell('${player.matches}', 40),
                  _Cell('${player.minutes}', 56),
                ],
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
      style: const TextStyle(color: CX.faint, fontSize: 10, fontWeight: FontWeight.w800),
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  child: Row(
                    children: [
                      SizedBox(width: 28, child: Text('${row.rank}')),
                      Expanded(child: Text(row.teamName, style: TextStyle(fontWeight: row.isOwnTeam ? FontWeight.w900 : FontWeight.w600))),
                      SizedBox(width: 34, child: Text('${row.played}', textAlign: TextAlign.center)),
                      SizedBox(width: 42, child: Text('${row.goalDifference >= 0 ? '+' : ''}${row.goalDifference}', textAlign: TextAlign.center)),
                      SizedBox(width: 38, child: Text('${row.points}', textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w900))),
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: CX.panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 9),
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
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
  final ValueChanged<List<MatchResult>> onChanged;

  const _NoLudStatsBody({
    required this.clubName,
    required this.category,
    required this.categoryId,
    required this.allResults,
    required this.onChanged,
  });

  Future<void> _add(BuildContext context) async {
    final result = await showMatchResultDialog(context, categoryId: categoryId);
    if (result != null) onChanged([...allResults, result]);
  }

  Future<void> _edit(BuildContext context, MatchResult existing) async {
    final result = await showMatchResultDialog(
      context,
      categoryId: categoryId,
      existing: existing,
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
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
        const SizedBox(height: 6),
        if (summary.all.isEmpty)
          _NoLudEmpty(onAdd: () => _add(context))
        else ...[
          _NoLudReading(summary: summary),
          const SizedBox(height: 14),
          _NoLudMetrics(summary: summary),
          const SizedBox(height: 14),
          _NoLudForm(summary: summary),
          const SizedBox(height: 14),
          _NoLudResultsList(
            results: summary.all,
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
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: CX.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.line),
      ),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 30,
            backgroundColor: CX.greenDark,
            child: Icon(Icons.scoreboard_outlined, color: CX.green, size: 30),
          ),
          const SizedBox(height: 14),
          const Text(
            'Todavía no cargaste resultados',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'Cargá los partidos de tu equipo y fobal arma la tabla, la forma '
            'reciente y una lectura de cómo viene el rendimiento.',
            textAlign: TextAlign.center,
            style: TextStyle(color: CX.muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Cargar el primer resultado'),
          ),
        ],
      ),
    );
  }
}

class _NoLudReading extends StatelessWidget {
  final MatchStats summary;
  const _NoLudReading({required this.summary});

  @override
  Widget build(BuildContext context) {
    const fg = Color(0xFFE8F1ED);
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

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF102019),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_graph, color: Color(0xFF6EF2C7), size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Lectura de la semana',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (confidence != null) _ConfidencePill(confidence),
            ],
          ),
          const SizedBox(height: 14),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: 8),
                    child: _Dot(),
                  ),
                  Expanded(
                    child: Text(
                      line,
                      style: const TextStyle(color: fg, fontSize: 13.5, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (limits.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...limits.map(
              (l) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 13, color: Color(0xFF8CA39B)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l,
                        style: const TextStyle(
                          color: Color(0xFF8CA39B),
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoLudMetrics extends StatelessWidget {
  final MatchStats summary;
  const _NoLudMetrics({required this.summary});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final hasCompetitive = s.played > 0;
    final items = <_Metric>[
      _Metric('Partidos', '${s.played}', Icons.event_available, CX.blue,
          s.friendlies > 0 ? '+ ${s.friendlies} amistosos' : 'oficiales'),
      _Metric('Puntos', hasCompetitive ? '${s.points}' : '—', Icons.stars, CX.green,
          hasCompetitive ? '${s.wins}G ${s.draws}E ${s.losses}P' : 'sin oficiales'),
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
        hasCompetitive ? '${s.goalsFor} a favor / ${s.goalsAgainst} en contra' : '',
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

    return LayoutBuilder(
      builder: (context, constraints) => GridView.count(
        crossAxisCount: constraints.maxWidth < 650
            ? 2
            : (constraints.maxWidth < 980 ? 3 : items.length),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: constraints.maxWidth < 650 ? 1.35 : 1.5,
        children: items
            .map(
              (item) => Container(
                padding: const EdgeInsets.all(14),
                decoration: CX.panelDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(item.icon, color: item.color, size: 19),
                    Text(
                      item.value,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      item.label,
                      style: const TextStyle(
                        color: CX.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      item.context,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: CX.faint, fontSize: 10, height: 1.25),
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

class _NoLudForm extends StatelessWidget {
  final MatchStats summary;
  const _NoLudForm({required this.summary});

  @override
  Widget build(BuildContext context) {
    final recent = summary.competitive.take(5).toList().reversed.toList();
    if (recent.isEmpty) {
      return const _Panel(
        title: 'Forma reciente',
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
      title: 'Forma reciente',
      icon: Icons.timeline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: recent.map((r) {
              final color = r.outcome == 'E'
                  ? CX.amber.withValues(alpha: .75)
                  : r.outcome == 'G'
                  ? CX.green.withValues(alpha: .8)
                  : CX.red.withValues(alpha: .7);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    children: [
                      Container(
                        height: 58,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          r.outcome,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            r.venue == 'away'
                                ? Icons.flight_takeoff
                                : r.venue == 'neutral'
                                ? Icons.place_outlined
                                : Icons.home,
                            size: 10,
                            color: CX.faint,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${r.goalsFor}-${r.goalsAgainst}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        r.opponent,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: CX.faint, fontSize: 8.5),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
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
  final ValueChanged<MatchResult> onEdit;
  final ValueChanged<MatchResult> onDelete;

  const _NoLudResultsList({
    required this.results,
    required this.onEdit,
    required this.onDelete,
  });

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
                    style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12),
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

import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import '../services/club_access_service.dart';

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
    int value(String text, String suffix) {
      final match = RegExp('(\\d+)\\s+$suffix', caseSensitive: false)
          .firstMatch(text);
      return int.tryParse(match?.group(1) ?? '') ?? 0;
    }

    return players
        .map(
          (player) => _PlayerStat(
            name: player.fullName.trim(),
            position: player.position.trim(),
            matches: value(player.trend, 'PJ'),
            minutes: value(player.trend, 'min'),
            goals: value(player.trend, 'goles?'),
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
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            children: [
              _StatsHero(clubName: club.name, category: category, data: data),
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

  const _PlayerStat({
    required this.name,
    required this.position,
    required this.matches,
    required this.minutes,
    required this.goals,
  });
}

class _StatsHero extends StatelessWidget {
  final String clubName;
  final String category;
  final _StatsData data;

  const _StatsHero({
    required this.clubName,
    required this.category,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final row = data.ownRow;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF102019),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.query_stats, color: Color(0xFF6EF2C7), size: 34),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$clubName · $category',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  row == null
                      ? 'Esperando estadísticas oficiales de esta categoría.'
                      : '${row.rank}° en la tabla · ${row.points} puntos · ${row.goalDifference >= 0 ? '+' : ''}${row.goalDifference} de diferencia',
                  style: const TextStyle(color: Color(0xFFB8C5BF), fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  final _StatsData data;
  const _MetricGrid({required this.data});

  @override
  Widget build(BuildContext context) {
    final row = data.ownRow;
    final pointsRate = row == null || row.played == 0
        ? 0
        : (row.points / (row.played * 3) * 100).round();
    final items = [
      ('Posición', row == null ? '—' : '${row.rank}°', Icons.emoji_events, CX.amber),
      ('Puntos', row == null ? '—' : '${row.points}', Icons.stars, CX.blue),
      (
        'Puntos obtenidos',
        row == null ? '—' : '$pointsRate%',
        Icons.trending_up,
        CX.green,
      ),
      ('Goles', row == null ? '—' : '${row.goalsFor}', Icons.sports_soccer, CX.red),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => GridView.count(
        crossAxisCount: constraints.maxWidth < 650 ? 2 : 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: constraints.maxWidth < 650 ? 1.55 : 1.75,
        children: items
            .map(
              (item) => Container(
                padding: const EdgeInsets.all(16),
                decoration: CX.panelDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(item.$3, color: item.$4, size: 20),
                    Text(
                      item.$2,
                      style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
                    ),
                    Text(item.$1, style: const TextStyle(color: CX.muted, fontSize: 11)),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
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
    return _Panel(
      title: 'Forma reciente',
      icon: Icons.timeline,
      child: recent.isEmpty
          ? const _NoData()
          : Row(
              children: recent.map((match) {
                final isHome = _isHome(match);
                final goalsFor = isHome ? match.homeScore! : match.awayScore!;
                final goalsAgainst = isHome
                    ? match.awayScore!
                    : match.homeScore!;
                final draw = goalsFor == goalsAgainst;
                final won = goalsFor > goalsAgainst;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      children: [
                        Container(
                          height: 72,
                          decoration: BoxDecoration(
                            color: draw
                                ? CX.amber.withValues(alpha: .75)
                                : won
                                ? CX.green.withValues(alpha: .8)
                                : CX.red.withValues(alpha: .7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$goalsFor-$goalsAgainst',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
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
    if (row != null && row.played > 0) {
      final scoring = row.goalsFor / row.played;
      final conceding = row.goalsAgainst / row.played;
      messages.add(
        scoring >= 1.5
            ? 'El equipo sostiene una producción alta: ${scoring.toStringAsFixed(1)} goles por partido.'
            : 'La producción ofensiva es un área de mejora: ${scoring.toStringAsFixed(1)} goles por partido.',
      );
      messages.add(
        conceding <= 1
            ? 'La solidez defensiva es una fortaleza: ${conceding.toStringAsFixed(1)} goles recibidos por partido.'
            : 'Conviene priorizar el control defensivo: ${conceding.toStringAsFixed(1)} goles recibidos por partido.',
      );
      final pointsRate = row.points / (row.played * 3) * 100;
      messages.add('Se obtuvo el ${pointsRate.toStringAsFixed(0)}% de los puntos disputados.');
    }
    if (data.players.isNotEmpty) {
      final scorer = [...data.players]..sort((a, b) => b.goals.compareTo(a.goals));
      if (scorer.first.goals > 0) {
        messages.add('${scorer.first.name} lidera el goleo del plantel con ${scorer.first.goals}.');
      }
    }
    return _Panel(
      title: 'Lectura automática',
      icon: Icons.auto_graph,
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
    final ranked = [...players]
      ..sort((a, b) => b.minutes.compareTo(a.minutes));
    return _Panel(
      title: 'Jugadores con mayor participación',
      icon: Icons.groups_2_outlined,
      child: ranked.isEmpty
          ? const _NoData()
          : Column(
              children: ranked.take(8).map((player) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 15,
                        backgroundColor: CX.greenDark,
                        child: Icon(Icons.person_outline, size: 17, color: CX.green),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(player.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text(player.position.isEmpty ? 'Sin posición cargada' : player.position, style: const TextStyle(color: CX.faint, fontSize: 10)),
                          ],
                        ),
                      ),
                      Text('${player.matches} PJ', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 18),
                      SizedBox(width: 68, child: Text('${player.minutes} min', textAlign: TextAlign.right)),
                      const SizedBox(width: 18),
                      SizedBox(width: 52, child: Text('${player.goals} gol', textAlign: TextAlign.right)),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
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

import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import '../services/supabase_auth_service.dart';
import '../services/club_access_service.dart';

class HomeScreen extends StatefulWidget {
  final ValueChanged<int> onNavigate;

  const HomeScreen({super.key, required this.onNavigate});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _hydratedContextKey;
  bool _planningSyncing = false;
  bool _planningSyncFailed = false;
  DateTime? _planningSyncedAt;
  List<TrainingSession> _matchPlans = const [];
  Future<LudStandingsTable?>? _standingsFuture;
  Future<List<LudFixtureMatch>>? _fixtureFuture;
  Future<List<LudFixtureMatch>>? _resultsFuture;
  String? _standingsKey;
  String? _fixtureKey;
  String? _resultsKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppScope.of(context);
    final contextKey = '${scope.fullClub.id}|${scope.selectedCategoryId ?? ''}';
    if (_hydratedContextKey == contextKey) return;
    _hydratedContextKey = contextKey;
    Future<void>.microtask(_syncSharedPlanning);
    _ensureLeagueFutures();
  }

  void _ensureLeagueFutures({bool force = false}) {
    final scope = AppScope.of(context);
    if (scope.club.categories.isEmpty) return;
    final category = scope.club.categories.first;
    final key = '${scope.fullClub.id}|${category.id}';
    if (force || _standingsKey != key || _standingsFuture == null) {
      _standingsKey = key;
      _standingsFuture = _loadStandings(category, force: force);
    }
    if (force || _fixtureKey != key || _fixtureFuture == null) {
      _fixtureKey = key;
      _fixtureFuture = _loadFixture(category, force: force);
    }
    if (force || _resultsKey != key || _resultsFuture == null) {
      _resultsKey = key;
      _resultsFuture = _loadResults(category, force: force);
    }
  }

  void _reloadLeague() {
    _ensureLeagueFutures(force: true);
    setState(() {});
  }

  Future<LudStandingsTable?> _loadStandings(
    CategorySquad category, {
    bool force = false,
  }) async {
    final membership = await _membershipForVisibleClub(category);
    if (membership == null) return null;
    return ClubAccessService.loadStandings(
      membership: membership,
      category: category,
      forceRefresh: force,
    );
  }

  Future<List<LudFixtureMatch>> _loadFixture(
    CategorySquad category, {
    bool force = false,
  }) async {
    final membership = await _membershipForVisibleClub(category);
    if (membership == null) return const [];
    return ClubAccessService.loadFixture(
      membership: membership,
      category: category,
      forceRefresh: force,
    );
  }

  Future<List<LudFixtureMatch>> _loadResults(
    CategorySquad category, {
    bool force = false,
  }) async {
    final membership = await _membershipForVisibleClub(category);
    if (membership == null) return const [];
    return ClubAccessService.loadResults(
      membership: membership,
      category: category,
      forceRefresh: force,
    );
  }

  Future<ClubMembership?> _membershipForVisibleClub(
    CategorySquad category,
  ) async {
    final club = AppScope.of(context).fullClub;
    final active = await ClubAccessService.activeMembership();
    if (active != null && active.clubId == club.id) return active;
    return _previewMembershipFromCategory(category);
  }

  ClubMembership? _previewMembershipFromCategory(CategorySquad category) {
    final teamId = LudCategoryRef.teamIdOf(category.id);
    if (teamId == null) return null;
    final club = AppScope.of(context).fullClub;
    return ClubMembership(
      clubId: club.id,
      clubName: club.name,
      ludTeamId: '$teamId',
      role: 'coach',
      status: 'active',
    );
  }

  Future<void> _syncSharedPlanning() async {
    if (_planningSyncing) return;
    setState(() {
      _planningSyncing = true;
      _planningSyncFailed = false;
    });

    try {
      final records = await ClubAccessService.loadTacticalData(limit: 80);
      if (!mounted) return;
      final scope = AppScope.of(context);
      final club = scope.club;
      final visibleCategoryIds = club.categories.map((item) => item.id).toSet();
      final remoteSessions = <TrainingSession>[];
      final remoteReports = <TrainingReport>[];
      final remoteMatchPlans = <TrainingSession>[];
      for (final record in records) {
        try {
          if (record.type == 'session') {
            final session = TrainingSession.fromJson(record.content);
            if (session.id.isNotEmpty && session.categoryId.isNotEmpty) {
              remoteSessions.add(session);
            }
          } else if (record.type == 'match_plan') {
            final plan = TrainingSession.fromJson(record.content);
            if (plan.id.isNotEmpty && plan.categoryId.isNotEmpty) {
              remoteMatchPlans.add(plan);
            }
          } else if (record.type == 'staff_note') {
            final report = TrainingReport.fromJson(record.content);
            if (report.categoryId.isNotEmpty && report.date.isNotEmpty) {
              remoteReports.add(report);
            }
          }
        } catch (_) {
          // Ignore one malformed shared record without hiding the dashboard.
        }
      }
      final sessionIds = remoteSessions.map((item) => item.id).toSet();
      final reportKeys = remoteReports
          .map((item) => '${item.categoryId}|${item.date}')
          .toSet();
      scope.updateClub(
        club.copyWith(
          players: applyRemotePlayerProfiles(
            players: club.players,
            records: records,
          ),
          sessions: [
            ...remoteSessions,
            ...club.sessions.where((item) => !sessionIds.contains(item.id)),
          ],
          trainingReports: [
            ...remoteReports,
            ...club.trainingReports.where(
              (item) => !reportKeys.contains('${item.categoryId}|${item.date}'),
            ),
          ],
        ),
      );
      setState(() {
        _matchPlans = remoteMatchPlans
            .where(
              (plan) =>
                  visibleCategoryIds.contains(plan.categoryId) &&
                  !_isWrongCategorySeminarioPlan(plan),
            )
            .toList();
        _planningSyncedAt = DateTime.now();
        _planningSyncing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _planningSyncFailed = true;
        _planningSyncing = false;
      });
    }
  }

  bool _isWrongCategorySeminarioPlan(TrainingSession plan) {
    final text = [
      plan.title,
      plan.objective,
      ...plan.blocks.map((block) => block.description),
    ].join(' ').toLowerCase();
    return text.contains('seminario');
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final club = scope.club;
    _ensureLeagueFutures();
    final setupItems = <bool>[
      club.name.trim().isNotEmpty &&
          club.name != 'Club Demo' &&
          club.league.trim().isNotEmpty,
      club.categories.isNotEmpty,
      club.players.isNotEmpty,
      club.methodology.playingStyle.trim().isNotEmpty,
      SupabaseAuthService.currentSession != null,
    ];
    final completed = setupItems.where((value) => value).length;
    final readiness = (completed / setupItems.length * 100).round();
    final attendance = club.categories.isEmpty
        ? 0
        : (club.categories.fold<double>(0, (sum, c) => sum + c.attendanceRate) /
                  club.categories.length *
                  100)
              .round();
    final planned = club.sessions
        .where((session) => session.status == 'planned')
        .length;
    final completePlayerProfiles = club.players
        .where(_hasAiReadyPlayerProfile)
        .length;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1260),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
                  sliver: SliverToBoxAdapter(
                    child: _TopBar(club: club, role: scope.role),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                  sliver: SliverList.list(
                    children: CanteraMotion.stagger([
                      _MatchCenterPanel(
                        club: club,
                        standingsFuture: _standingsFuture,
                        fixtureFuture: _fixtureFuture,
                        onRefresh: _reloadLeague,
                        onOpenField: () => widget.onNavigate(1),
                        onOpenAssistant: () => widget.onNavigate(2),
                        onOpenLineup: () => widget.onNavigate(
                          scope.role == UserRole.coordinator ? 5 : 4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _CommandHero(
                        club: club,
                        readiness: readiness,
                        onPrimaryAction: () => widget.onNavigate(
                          scope.role == UserRole.viewer
                              ? 1
                              : readiness < 100 &&
                                    scope.role == UserRole.coordinator
                              ? 4
                              : 2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 720;
                          final metrics = [
                            _Metric(
                              'Categorias',
                              '${club.categories.length}',
                              'Estructura activa',
                              Icons.groups_2_outlined,
                              CX.blue,
                            ),
                            _Metric(
                              'Jugadores',
                              '${club.players.length}',
                              completePlayerProfiles == 0
                                  ? 'Plantel registrado'
                                  : '$completePlayerProfiles perfiles completos',
                              Icons.badge_outlined,
                              CX.green,
                            ),
                            _Metric(
                              'Asistencia',
                              '$attendance%',
                              club.categories.isEmpty
                                  ? 'Sin registros'
                                  : 'Promedio del club',
                              Icons.monitor_heart_outlined,
                              CX.amber,
                            ),
                            _Metric(
                              'Sesiones',
                              '$planned',
                              'Próximas planificadas',
                              Icons.calendar_today_outlined,
                              const Color(0xFFC09BFF),
                            ),
                          ];
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: metrics.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: compact ? 2 : 4,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                  childAspectRatio: compact ? 1.35 : 1.6,
                                ),
                            itemBuilder: (context, index) =>
                                _MetricTile(metric: metrics[index]),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      _StandingsPanel(
                        future: _standingsFuture,
                        categoryName: club.categories.isEmpty
                            ? ''
                            : club.categories.first.name,
                      ),
                      const SizedBox(height: 12),
                      _RecentResultsPanel(
                        future: _resultsFuture,
                        clubName: club.name,
                        onRefresh: _reloadLeague,
                      ),
                      const SizedBox(height: 26),
                      const _SectionHeader(
                        eyebrow: 'TU SEMANA',
                        title: 'Lo importante, en un solo lugar',
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final desktop = constraints.maxWidth >= 820;
                          final primary = _TodayPanel(
                            club: club,
                            matchPlans: _matchPlans,
                            syncing: _planningSyncing,
                            syncFailed: _planningSyncFailed,
                            syncedAt: _planningSyncedAt,
                            onRefresh: _syncSharedPlanning,
                            onOpenField: () => widget.onNavigate(1),
                            onOpenAssistant: () => widget.onNavigate(2),
                          );
                          final secondary = _SetupPanel(
                            club: club,
                            completed: completed,
                            total: setupItems.length,
                            role: scope.role,
                            onNavigate: widget.onNavigate,
                          );
                          if (!desktop) {
                            return Column(
                              children: [
                                primary,
                                const SizedBox(height: 12),
                                secondary,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 7, child: primary),
                              const SizedBox(width: 12),
                              Expanded(flex: 4, child: secondary),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 26),
                      const _SectionHeader(
                        eyebrow: 'LECTURA DEL CUERPO TECNICO',
                        title: 'Que mirar esta semana',
                      ),
                      const SizedBox(height: 12),
                      _IntelligenceStrip(
                        club: club,
                        onOpen: () => widget.onNavigate(3),
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _hasAiReadyPlayerProfile(Player player) =>
      player.position.trim().isNotEmpty &&
      player.secondaryPositions.trim().isNotEmpty &&
      player.dominantFoot.trim().isNotEmpty &&
      player.status.trim().isNotEmpty &&
      player.note.trim().length >= 12;
}

class _TopBar extends StatelessWidget {
  final CanteraClub club;
  final UserRole role;
  const _TopBar({required this.club, required this.role});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    const months = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    return Row(
      children: [
        ClubCrest(logoUrl: club.logoUrl, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                club.name == 'Club Demo' ? 'Centro de mando' : club.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${now.day} de ${months[now.month - 1]}  -  ${switch (role) {
                  UserRole.coordinator => 'Vista coordinador',
                  UserRole.coach => 'Vista entrenador',
                  UserRole.viewer => 'Solo lectura',
                }}',
                style: const TextStyle(color: CX.faint, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Notificaciones',
          onPressed: () {},
          icon: const Icon(Icons.notifications_none, size: 20),
          style: IconButton.styleFrom(
            backgroundColor: CX.panel,
            foregroundColor: CX.muted,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
            ),
          ),
        ),
      ],
    );
  }
}

class _CommandHero extends StatelessWidget {
  final CanteraClub club;
  final int readiness;
  final VoidCallback onPrimaryAction;

  const _CommandHero({
    required this.club,
    required this.readiness,
    required this.onPrimaryAction,
  });

  @override
  Widget build(BuildContext context) {
    final configured = readiness == 100;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: CX.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.line),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 650;
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClubCrest(logoUrl: club.logoUrl, size: 52),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: configured ? CX.greenDark : CX.panel2,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      configured
                          ? 'CLUB OPERATIVO'
                          : 'PUESTA EN MARCHA · $readiness%',
                      style: TextStyle(
                        color: configured ? CX.green : CX.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                configured
                    ? 'Todo el club, bajo una misma idea.'
                    : 'Armá la base deportiva de tu club.',
                style: TextStyle(
                  fontSize: narrow ? 25 : 34,
                  height: 1.08,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Text(
                  configured
                      ? 'Planificá, observá y decidí con el contexto completo de cada categoría.'
                      : 'Cargá identidad, categorías, planteles y forma de jugar. fobal usa esos datos para conectar cada decisión.',
                  style: const TextStyle(
                    color: CX.muted,
                    height: 1.45,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: narrow ? double.infinity : 220,
                child: ElevatedButton.icon(
                  onPressed: onPrimaryAction,
                  icon: Icon(
                    configured ? Icons.auto_awesome : Icons.arrow_forward,
                    size: 18,
                  ),
                  label: Text(
                    configured ? 'Abrir asistente' : 'Continuar configuración',
                  ),
                ),
              ),
            ],
          );
          if (narrow) return content;
          return Stack(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 230),
                child: content,
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: _ReadinessDial(value: readiness),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReadinessDial extends StatelessWidget {
  final int value;
  const _ReadinessDial({required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: CircularProgressIndicator(
                value: value / 100,
                strokeWidth: 8,
                strokeCap: StrokeCap.round,
                backgroundColor: CX.panel3,
                color: CX.green,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$value%',
                  style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Text(
                  'preparacion',
                  style: TextStyle(color: CX.faint, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final _Metric metric;
  const _MetricTile({required this.metric});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: CX.panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(metric.icon, color: metric.color, size: 18),
              const Spacer(),
              const Icon(Icons.north_east, color: CX.faint, size: 14),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                metric.value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                metric.label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                metric.detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: CX.faint, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentResultsPanel extends StatelessWidget {
  final Future<List<LudFixtureMatch>>? future;
  final String clubName;
  final VoidCallback onRefresh;

  const _RecentResultsPanel({
    required this.future,
    required this.clubName,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: CX.panelDecoration(
        borderColor: CX.blue.withValues(alpha: .2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sports_score_outlined, color: CX.blue, size: 19),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Ultimos resultados',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
              IconButton(
                tooltip: 'Actualizar resultados',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<LudFixtureMatch>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator(minHeight: 2);
              }
              // loadResults already returns only real played matches (<=5,
              // newest first). isPlayedResult is the belt-and-braces guard so
              // an unplayed 0-0 can never slip into "recent form".
              final results =
                  (snapshot.data ?? const <LudFixtureMatch>[])
                      .where((match) => match.isPlayedResult)
                      .toList()
                    ..sort((a, b) => b.date.compareTo(a.date));
              final trimmed = results.take(5).toList();
              if (trimmed.isEmpty) {
                return const Text(
                  'Todavia no hay resultados publicados para esta categoria.',
                  style: TextStyle(color: CX.muted, fontSize: 12),
                );
              }
              return Column(
                children: trimmed
                    .map(
                      (match) =>
                          _RecentResultRow(match: match, clubName: clubName),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RecentResultRow extends StatelessWidget {
  final LudFixtureMatch match;
  final String clubName;

  const _RecentResultRow({required this.match, required this.clubName});

  @override
  Widget build(BuildContext context) {
    // opponentName is set server-side to the "other" team, so it is a more
    // reliable home/away signal than fuzzy-matching the club name.
    final opponent = match.opponentName.trim();
    final home = opponent.isNotEmpty
        ? match.awayTeamName.trim() == opponent
        : _matchesClub(match.homeTeamName, clubName);
    final goalsFor = home ? match.homeScore! : match.awayScore!;
    final goalsAgainst = home ? match.awayScore! : match.homeScore!;
    final color = goalsFor > goalsAgainst
        ? CX.green
        : goalsFor == goalsAgainst
        ? CX.amber
        : CX.red;
    final label = goalsFor > goalsAgainst
        ? 'Ganado'
        : goalsFor == goalsAgainst
        ? 'Empatado'
        : 'Perdido';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: CX.panel2,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: CX.line),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(
              match.dateLabel,
              style: const TextStyle(color: CX.faint, fontSize: 10),
            ),
          ),
          Expanded(
            child: Text(
              match.opponentName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
          Text(
            '$goalsFor - $goalsAgainst',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 62,
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

}

bool _matchesClub(String value, String target) {
  String clean(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final left = clean(value);
  final right = clean(target);
  if (left.isEmpty || right.isEmpty) return false;
  return left == right || left.contains(right) || right.contains(left);
}

class _DecisionCard extends StatefulWidget {
  final _DecisionItem item;
  final VoidCallback onTap;

  const _DecisionCard({required this.item, required this.onTap});

  @override
  State<_DecisionCard> createState() => _DecisionCardState();
}

class _DecisionCardState extends State<_DecisionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: CX.motionFast,
          curve: CX.curve,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _hovered ? CX.panel3 : CX.panel2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.item.color.withValues(alpha: _hovered ? .34 : .18),
            ),
          ),
          child: Row(
            children: [
              AnimatedScale(
                scale: _hovered ? 1.06 : 1,
                duration: CX.motionFast,
                curve: CX.curve,
                child: Icon(
                  widget.item.icon,
                  color: widget.item.color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.item.detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CX.faint,
                        fontSize: 10,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                widget.item.actionLabel,
                style: TextStyle(
                  color: widget.item.color,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DecisionItem {
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final String actionLabel;
  final int targetIndex;

  const _DecisionItem(
    this.icon,
    this.color,
    this.title,
    this.detail,
    this.actionLabel,
    this.targetIndex,
  );
}

class _HealthPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _HealthPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _MatchCenterPanel extends StatelessWidget {
  final CanteraClub club;
  final Future<LudStandingsTable?>? standingsFuture;
  final Future<List<LudFixtureMatch>>? fixtureFuture;
  final VoidCallback onRefresh;
  final VoidCallback onOpenField;
  final VoidCallback onOpenAssistant;
  final VoidCallback onOpenLineup;

  const _MatchCenterPanel({
    required this.club,
    required this.standingsFuture,
    required this.fixtureFuture,
    required this.onRefresh,
    required this.onOpenField,
    required this.onOpenAssistant,
    required this.onOpenLineup,
  });

  @override
  Widget build(BuildContext context) {
    final category = club.categories.isEmpty ? null : club.categories.first;
    if (category == null) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: CX.panelDecoration(
          borderColor: CX.amber.withValues(alpha: .25),
        ),
        child: const Text(
          'Elegí una categoría para ver partido, tabla y plantel en un solo lugar.',
          style: TextStyle(color: CX.muted, fontWeight: FontWeight.w800),
        ),
      );
    }

    final players = club.players
        .where((player) => player.categoryId == category.id)
        .toList();
    final available = players
        .where((player) => player.status.toLowerCase() != 'lesionado')
        .length;
    final profiled = players.where(_hasCompleteProfile).length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: CX.panelDecoration(
        borderColor: CX.green.withValues(alpha: .26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sports_soccer, color: CX.green, size: 20),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Centro de partido',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${category.name} / datos listos para planificar',
                      style: const TextStyle(color: CX.faint, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Actualizar datos de la liga',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 850;
              final content = [
                Expanded(
                  flex: 5,
                  child: _NextFixtureCard(
                    future: fixtureFuture,
                    onOpenAssistant: onOpenAssistant,
                  ),
                ),
                SizedBox(width: compact ? 0 : 10, height: compact ? 10 : 0),
                Expanded(
                  flex: 4,
                  child: _LeagueSnapshotCard(
                    future: standingsFuture,
                    categoryName: category.name,
                  ),
                ),
                SizedBox(width: compact ? 0 : 10, height: compact ? 10 : 0),
                Expanded(
                  flex: 4,
                  child: _SquadSnapshotCard(
                    players: players.length,
                    available: available,
                    profiled: profiled,
                    onOpenField: onOpenField,
                  ),
                ),
              ];
              if (compact) {
                return Column(
                  children: content
                      .map((child) => child is Expanded ? child.child : child)
                      .toList(),
                );
              }
              return Row(children: content);
            },
          ),
          const SizedBox(height: 14),
          _PracticeWeekCard(category: category),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: onOpenAssistant,
                icon: const Icon(Icons.auto_awesome, size: 17),
                label: const Text('Preparar partido'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenLineup,
                icon: const Icon(Icons.view_module_outlined, size: 17),
                label: const Text('Armar alineación'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenField,
                icon: const Icon(Icons.groups_2_outlined, size: 17),
                label: const Text('Ver plantel'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static bool _hasCompleteProfile(Player player) =>
      player.position.trim().isNotEmpty &&
      player.dominantFoot.trim().isNotEmpty &&
      player.note.trim().length >= 12;
}

class _NextFixtureCard extends StatelessWidget {
  final Future<List<LudFixtureMatch>>? future;
  final VoidCallback onOpenAssistant;

  const _NextFixtureCard({required this.future, required this.onOpenAssistant});

  @override
  Widget build(BuildContext context) {
    return _MiniInfoCard(
      icon: Icons.event_available_outlined,
      title: 'Próximo rival',
      child: FutureBuilder<List<LudFixtureMatch>>(
        future: future,
        builder: (context, snapshot) {
          final loading = snapshot.connectionState == ConnectionState.waiting;
          final matches = snapshot.data ?? const <LudFixtureMatch>[];
          final upcoming = matches.where((match) => match.isUpcoming).toList();
          final next = upcoming.isEmpty
              ? (matches.isEmpty ? null : matches.first)
              : upcoming.first;
          if (loading) {
            return const _InlineLoading(label: 'Cargando fixture');
          }
          if (snapshot.hasError || next == null) {
            return const _MutedBlock(
              'Fixture no disponible todavía. Podés preparar el partido escribiendo el rival manualmente.',
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                upcoming.isEmpty
                    ? 'Ultimo rival: ${next.opponentName}'
                    : next.opponentName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                [
                  next.dateLabel,
                  if (next.venue.trim().isNotEmpty) next.venue.trim(),
                ].join(' / '),
                style: const TextStyle(color: CX.muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: onOpenAssistant,
                child: const Text('Preparar este partido'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LeagueSnapshotCard extends StatelessWidget {
  final Future<LudStandingsTable?>? future;
  final String categoryName;

  const _LeagueSnapshotCard({required this.future, required this.categoryName});

  @override
  Widget build(BuildContext context) {
    return _MiniInfoCard(
      icon: Icons.leaderboard_outlined,
      title: 'Tabla',
      child: FutureBuilder<LudStandingsTable?>(
        future: future,
        builder: (context, snapshot) {
          final loading = snapshot.connectionState == ConnectionState.waiting;
          final table = snapshot.data;
          final own = table?.ownRow;
          if (loading) return const _InlineLoading(label: 'Cargando tabla');
          if (snapshot.hasError || table == null || own == null) {
            return const _MutedBlock('Tabla pendiente para esta categoría.');
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${own.rank}° puesto',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '$categoryName / ${own.points} pts / ${own.played} PJ',
                style: const TextStyle(color: CX.muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              _MiniTable(rows: table.rows.take(4).toList()),
            ],
          );
        },
      ),
    );
  }
}

class _SquadSnapshotCard extends StatelessWidget {
  final int players;
  final int available;
  final int profiled;
  final VoidCallback onOpenField;

  const _SquadSnapshotCard({
    required this.players,
    required this.available,
    required this.profiled,
    required this.onOpenField,
  });

  @override
  Widget build(BuildContext context) {
    return _MiniInfoCard(
      icon: Icons.groups_2_outlined,
      title: 'Plantel',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$available/$players disponibles',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            '$profiled perfiles individuales completos',
            style: const TextStyle(color: CX.muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onOpenField,
            child: const Text('Revisar plantel'),
          ),
        ],
      ),
    );
  }
}

class _PracticeWeekCard extends StatelessWidget {
  final CategorySquad category;

  const _PracticeWeekCard({required this.category});

  @override
  Widget build(BuildContext context) {
    final schedule = category.practiceSchedule.trim();
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _editSchedule(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: CX.panel2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: CX.line),
        ),
        child: Row(
          children: [
            const Icon(Icons.schedule, color: CX.green, size: 18),
            const SizedBox(width: 9),
            const Text(
              'Prácticas de la semana',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                schedule.isEmpty
                    ? 'Click para cargar días y horarios.'
                    : schedule,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CX.muted,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ),
            const Icon(Icons.edit_outlined, color: CX.faint, size: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _editSchedule(BuildContext context) async {
    final value = await promptForText(
      context,
      title: 'Prácticas de la semana',
      initialValue: category.practiceSchedule,
      hintText: 'Ej: martes y jueves 20:30, sábado 10:00',
      minLines: 2,
      maxLines: 4,
    );
    if (value == null) return;
    final scope = AppScope.of(context);
    scope.updateClub(
      scope.club.copyWith(
        categories: scope.club.categories
            .map(
              (item) => item.id == category.id
                  ? item.copyWith(practiceSchedule: value)
                  : item,
            )
            .toList(),
      ),
    );
  }
}

class _MiniInfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _MiniInfoCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CX.panel2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: CX.green, size: 17),
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _InlineLoading extends StatelessWidget {
  final String label;

  const _InlineLoading({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 15,
          height: 15,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: CX.muted, fontSize: 12)),
      ],
    );
  }
}

class _MutedBlock extends StatelessWidget {
  final String text;

  const _MutedBlock(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(color: CX.muted, fontSize: 12, height: 1.35),
    );
  }
}

class _MiniTable extends StatelessWidget {
  final List<LudStandingRow> rows;

  const _MiniTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: rows
          .map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${row.rank}',
                      style: TextStyle(
                        color: row.isOwnTeam ? CX.green : CX.faint,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.teamName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: row.isOwnTeam ? CX.white : CX.muted,
                        fontSize: 11,
                        fontWeight: row.isOwnTeam
                            ? FontWeight.w900
                            : FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${row.points}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _StandingsPanel extends StatelessWidget {
  final Future<LudStandingsTable?>? future;
  final String categoryName;

  const _StandingsPanel({required this.future, required this.categoryName});

  @override
  Widget build(BuildContext context) {
    if (categoryName.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: CX.panelDecoration(
        borderColor: CX.green.withValues(alpha: .22),
      ),
      child: FutureBuilder<LudStandingsTable?>(
        future: future,
        builder: (context, snapshot) {
          final table = snapshot.data;
          final loading = snapshot.connectionState == ConnectionState.waiting;
          final own = table?.ownRow;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.leaderboard_outlined,
                    color: CX.green,
                    size: 19,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Tabla de $categoryName',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (loading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (own != null)
                    _HealthPill(
                      icon: Icons.shield_outlined,
                      label: '${own.rank}° / ${own.points} pts',
                      color: CX.green,
                    ),
                ],
              ),
              if (table?.phaseName.trim().isNotEmpty == true) ...[
                const SizedBox(height: 5),
                Text(
                  table!.phaseName,
                  style: const TextStyle(color: CX.faint, fontSize: 11),
                ),
              ],
              const SizedBox(height: 12),
              if (snapshot.hasError)
                const Text(
                  'No se pudo cargar la tabla de la liga ahora.',
                  style: TextStyle(color: CX.muted, fontSize: 12),
                )
              else if (loading)
                const LinearProgressIndicator(minHeight: 2)
              else if (table == null || table.rows.isEmpty)
                const Text(
                  'La liga todavia no publico tabla para esta categoria.',
                  style: TextStyle(color: CX.muted, fontSize: 12),
                )
              else
                Column(
                  children: table.rows
                      .take(8)
                      .map(_StandingRowTile.new)
                      .toList(),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StandingRowTile extends StatelessWidget {
  final LudStandingRow row;

  const _StandingRowTile(this.row);

  @override
  Widget build(BuildContext context) {
    final color = row.isOwnTeam ? CX.green : CX.line;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: row.isOwnTeam ? CX.greenDark.withValues(alpha: .34) : CX.panel2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: row.isOwnTeam ? .35 : 1),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${row.rank}',
              style: TextStyle(
                color: row.isOwnTeam ? CX.green : CX.muted,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Text(
              row.teamName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: row.isOwnTeam ? FontWeight.w900 : FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          _StandingCell('${row.played}', 'PJ'),
          _StandingCell('${row.goalDifference}', 'DG'),
          _StandingCell('${row.points}', 'PTS', strong: true),
        ],
      ),
    );
  }
}

class _StandingCell extends StatelessWidget {
  final String value;
  final String label;
  final bool strong;

  const _StandingCell(this.value, this.label, {this.strong = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: strong ? FontWeight.w900 : FontWeight.w800,
              color: strong ? CX.white : CX.muted,
              fontSize: 12,
            ),
          ),
          Text(label, style: const TextStyle(color: CX.faint, fontSize: 8)),
        ],
      ),
    );
  }
}

class _TodayPanel extends StatelessWidget {
  final CanteraClub club;
  final List<TrainingSession> matchPlans;
  final bool syncing;
  final bool syncFailed;
  final DateTime? syncedAt;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenField;
  final VoidCallback onOpenAssistant;

  const _TodayPanel({
    required this.club,
    required this.matchPlans,
    required this.syncing,
    required this.syncFailed,
    required this.syncedAt,
    required this.onRefresh,
    required this.onOpenField,
    required this.onOpenAssistant,
  });

  @override
  Widget build(BuildContext context) {
    final planned =
        club.sessions.where((session) => session.status != 'completed').toList()
          ..sort((a, b) {
            final aDate = DateTime.tryParse(a.scheduledDate);
            final bDate = DateTime.tryParse(b.scheduledDate);
            if (aDate == null && bDate == null) return 0;
            if (aDate == null) return 1;
            if (bDate == null) return -1;
            return aDate.compareTo(bDate);
          });
    final next = planned.isEmpty ? null : planned.first;
    final upcomingMatchPlans =
        matchPlans.where((plan) {
          final date = DateTime.tryParse(plan.scheduledDate);
          if (date == null) return true;
          final today = DateTime.now();
          return !date.isBefore(DateTime(today.year, today.month, today.day));
        }).toList()..sort((a, b) {
          final aDate = DateTime.tryParse(a.scheduledDate);
          final bDate = DateTime.tryParse(b.scheduledDate);
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return aDate.compareTo(bDate);
        });
    final nextMatchPlan = upcomingMatchPlans.isEmpty
        ? null
        : upcomingMatchPlans.first;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: CX.panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.today_outlined, color: CX.green, size: 19),
              SizedBox(width: 9),
              Text(
                'Agenda de campo',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _SharedPlanningStatus(
            syncing: syncing,
            failed: syncFailed,
            syncedAt: syncedAt,
            onRefresh: onRefresh,
          ),
          const SizedBox(height: 18),
          if (nextMatchPlan != null) ...[
            _NextMatchPlanCard(
              plan: nextMatchPlan,
              categoryName: _categoryName(nextMatchPlan.categoryId),
              onOpenAssistant: onOpenAssistant,
            ),
            const SizedBox(height: 14),
          ],
          if (next == null) ...[
            const Text(
              'No hay una sesion planificada',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            const Text(
              'Define el objetivo y deja que el asistente construya una sesion aplicable al plantel.',
              style: TextStyle(color: CX.muted, height: 1.4, fontSize: 13),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onOpenField,
                    icon: const Icon(Icons.visibility_outlined, size: 17),
                    label: const Text('Ver campo'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onOpenAssistant,
                    icon: const Icon(Icons.auto_awesome, size: 17),
                    label: const Text('Crear sesión'),
                  ),
                ),
              ],
            ),
          ] else
            _HomeAgendaSession(
              session: next,
              overdue: _isOverdue(next),
              formattedDate: _formatDate(next.scheduledDate),
            ),
        ],
      ),
    );
  }

  String _formatDate(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  bool _isOverdue(TrainingSession session) {
    final date = DateTime.tryParse(session.scheduledDate);
    if (date == null) return false;
    final now = DateTime.now();
    return date.isBefore(DateTime(now.year, now.month, now.day));
  }

  String _categoryName(String categoryId) {
    for (final category in club.categories) {
      if (category.id == categoryId) return category.name;
    }
    return '';
  }
}

class _HomeAgendaSession extends StatelessWidget {
  final TrainingSession session;
  final bool overdue;
  final String formattedDate;

  const _HomeAgendaSession({
    required this.session,
    required this.overdue,
    required this.formattedDate,
  });

  @override
  Widget build(BuildContext context) {
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          session.objective,
          style: const TextStyle(color: CX.muted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        _HomeSessionActionHint(session: session),
        const SizedBox(height: 10),
        _HomePostTrainingCue(session: session),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Tag('${session.duration} min'),
            _Tag(session.space),
            _Tag('${session.playerCount} jugadores'),
            if (session.scheduledDate.isNotEmpty) _Tag(formattedDate),
            if (overdue) _Tag('Finalizada'),
          ],
        ),
      ],
    );
    if (!overdue) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            session.title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          details,
        ],
      );
    }
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 8),
        initiallyExpanded: false,
        leading: const Icon(Icons.history, color: CX.faint, size: 18),
        title: Text(
          session.title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        subtitle: formattedDate.isEmpty
            ? null
            : Text(
                formattedDate,
                style: const TextStyle(color: CX.faint, fontSize: 10),
              ),
        children: [details],
      ),
    );
  }
}

class _SharedPlanningStatus extends StatelessWidget {
  final bool syncing;
  final bool failed;
  final DateTime? syncedAt;
  final Future<void> Function() onRefresh;

  const _SharedPlanningStatus({
    required this.syncing,
    required this.failed,
    required this.syncedAt,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final label = syncing
        ? 'Actualizando agenda'
        : failed
        ? 'Agenda guardada en este dispositivo'
        : syncedAt == null
        ? 'Agenda lista'
        : 'Agenda actualizada ${syncedAt!.hour.toString().padLeft(2, '0')}:${syncedAt!.minute.toString().padLeft(2, '0')}';
    return Row(
      children: [
        Icon(
          failed ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
          color: failed ? CX.amber : CX.green,
          size: 16,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: CX.faint, fontSize: 11),
          ),
        ),
        IconButton(
          tooltip: 'Actualizar agenda compartida',
          onPressed: syncing ? null : onRefresh,
          icon: syncing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, size: 18),
        ),
      ],
    );
  }
}

class _HomePostTrainingCue extends StatelessWidget {
  final TrainingSession session;

  const _HomePostTrainingCue({required this.session});

  @override
  Widget build(BuildContext context) {
    final prompt = session.postTrainingReviewPrompts.isEmpty
        ? 'Cerrar con una devolucion breve despues de entrenar.'
        : session.postTrainingReviewPrompts.first;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: CX.blue.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.blue.withValues(alpha: .2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.assignment_turned_in_outlined,
            color: CX.blue,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Post-entreno: $prompt',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: CX.muted,
                fontSize: 10,
                height: 1.3,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeSessionActionHint extends StatelessWidget {
  final TrainingSession session;

  const _HomeSessionActionHint({required this.session});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(session.scheduledDate);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = date == null
        ? null
        : DateTime(date.year, date.month, date.day);
    final overdue = dateOnly != null && dateOnly.isBefore(today);
    final todaySession = dateOnly != null && dateOnly.isAtSameMomentAs(today);
    final missingDate = session.scheduledDate.trim().isEmpty || date == null;
    final color = overdue || missingDate
        ? CX.amber
        : todaySession
        ? CX.green
        : CX.blue;
    final text = overdue
        ? 'Sesion vencida: reprogramar o cerrar desde Campo.'
        : missingDate
        ? 'Sesion sin fecha clara: asignar dia desde Campo.'
        : todaySession
        ? 'Sesion de hoy: revisar consignas antes de cancha.'
        : 'Proxima sesion ordenada.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .2)),
      ),
      child: Row(
        children: [
          Icon(
            overdue || missingDate
                ? Icons.priority_high_outlined
                : Icons.event_available_outlined,
            color: color,
            size: 17,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: CX.muted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NextMatchPlanCard extends StatelessWidget {
  final TrainingSession plan;
  final String categoryName;
  final VoidCallback onOpenAssistant;

  const _NextMatchPlanCard({
    required this.plan,
    required this.categoryName,
    required this.onOpenAssistant,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: CX.greenDark.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.green.withValues(alpha: .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sports_soccer, color: CX.green, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Proximo plan de partido',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              TextButton(
                onPressed: onOpenAssistant,
                child: const Text('Abrir'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            plan.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            [
              if (categoryName.isNotEmpty) categoryName,
              if (plan.scheduledDate.isNotEmpty)
                _formatDate(plan.scheduledDate),
              '${plan.playerCount} jugadores',
            ].join(' / '),
            style: const TextStyle(color: CX.muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              if (plan.confidence.isNotEmpty)
                _Tag(_confidenceLabel(plan.confidence)),
              _Tag(
                plan.contextSources.isEmpty
                    ? 'Sin fuentes declaradas'
                    : '${plan.contextSources.length} fuentes',
              ),
              if (plan.limitations.isNotEmpty)
                _Tag('${plan.limitations.length} alertas'),
            ],
          ),
          const SizedBox(height: 10),
          _HomeMatchPlanSignal(plan: plan),
        ],
      ),
    );
  }

  String _formatDate(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _confidenceLabel(String value) => switch (value) {
    'high' => 'Confianza alta',
    'medium' => 'Confianza media',
    _ => 'Confianza baja',
  };
}

class _HomeMatchPlanSignal extends StatelessWidget {
  final TrainingSession plan;

  const _HomeMatchPlanSignal({required this.plan});

  @override
  Widget build(BuildContext context) {
    final hasLimitations = plan.limitations.isNotEmpty;
    final hasSources = plan.contextSources.isNotEmpty;
    final color = hasLimitations
        ? CX.amber
        : hasSources
        ? CX.green
        : CX.blue;
    final title = hasLimitations
        ? 'Revisar dato sensible'
        : hasSources
        ? 'Plan trazable'
        : 'Completar contexto';
    final detail = hasLimitations
        ? plan.limitations.first
        : hasSources
        ? plan.contextSources.first
        : 'Abrir asistente y vincular rival, fecha o contexto antes de compartir.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hasLimitations
                ? Icons.warning_amber_outlined
                : Icons.fact_check_outlined,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CX.muted,
                    fontSize: 10,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupPanel extends StatelessWidget {
  final CanteraClub club;
  final int completed;
  final int total;
  final UserRole role;
  final ValueChanged<int> onNavigate;
  const _SetupPanel({
    required this.club,
    required this.completed,
    required this.total,
    required this.role,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final configTarget = role == UserRole.coordinator ? 4 : 3;
    final items = [
      (
        'Identidad y liga',
        club.name != 'Club Demo' && club.league.isNotEmpty,
        configTarget,
      ),
      (
        'Categorias',
        club.categories.isNotEmpty,
        role == UserRole.coordinator ? 4 : 1,
      ),
      ('Planteles', club.players.isNotEmpty, 1),
      ('Metodologia', club.methodology.playingStyle.isNotEmpty, 3),
      ('Equipo de trabajo', club.users.isNotEmpty, configTarget),
    ];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: CX.panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Base del club',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              Text(
                '$completed/$total',
                style: const TextStyle(
                  color: CX.green,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: completed / total,
              minHeight: 5,
              backgroundColor: CX.panel3,
              color: CX.green,
            ),
          ),
          const SizedBox(height: 14),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: InkWell(
                borderRadius: BorderRadius.circular(7),
                onTap: () => onNavigate(item.$3),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 7,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        item.$2
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: item.$2 ? CX.green : CX.faint,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.$1,
                          style: TextStyle(
                            color: item.$2 ? CX.white : CX.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: CX.faint,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntelligenceStrip extends StatelessWidget {
  final CanteraClub club;
  final VoidCallback onOpen;
  const _IntelligenceStrip({required this.club, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final hasContext =
        club.players.isNotEmpty && club.methodology.playingStyle.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CX.greenDark.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.green.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: CX.green.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(Icons.auto_graph, color: CX.green, size: 20),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasContext
                      ? 'Contexto listo para analizar'
                      : 'La inteligencia necesita contexto',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  hasContext
                      ? 'fobal ya puede cruzar metodologia, categorias y perfiles del plantel para orientar decisiones.'
                      : 'Completa metodologia y planteles para obtener lecturas que respondan a la realidad del club.',
                  style: const TextStyle(
                    color: CX.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Abrir inteligencia',
            onPressed: onOpen,
            icon: const Icon(Icons.arrow_forward, color: CX.green),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  const _SectionHeader({required this.eyebrow, required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: CX.green,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag(this.text);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: CX.panel2,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: CX.muted,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _Metric {
  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;
  const _Metric(this.label, this.value, this.detail, this.icon, this.color);
}

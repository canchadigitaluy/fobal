// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;

import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import '../services/club_access_service.dart';
import '../services/preview_access_service.dart';
import '../services/supabase_auth_service.dart';

class AccessGateScreen extends StatefulWidget {
  final bool forcePreview;

  const AccessGateScreen({super.key, this.forcePreview = false});

  @override
  State<AccessGateScreen> createState() => _AccessGateScreenState();
}

class _AccessGateScreenState extends State<AccessGateScreen> {
  late Future<_AccessState> _state;
  String? _selectedClubId;
  String? _selectedActiveClubId;
  String? _selectedCategoryId;
  final String _selectedRole = 'coach';
  final _inviteController = TextEditingController();
  final bool _submitting = false;
  bool _loadingClubContext = false;
  String? _message;
  ClubMembership? _categoryMembership;
  String? _categoryRoute;
  List<CategorySquad> _categoryOptions = const [];

  @override
  void initState() {
    super.initState();
    _state = _load();
  }

  @override
  void dispose() {
    _inviteController.dispose();
    super.dispose();
  }

  Future<_AccessState> _load() async {
    final postAuthMode = html.window.localStorage['cantera_post_auth_mode'];
    if (postAuthMode == 'local') {
      html.window.localStorage.remove('cantera_post_auth_mode');
      return const _AccessState(localMode: true);
    }
    final clubs = await _previewClubs();
    if (widget.forcePreview ||
        !SupabaseAuthService.isConfigured ||
        SupabaseAuthService.currentSession == null) {
      return _AccessState(clubs: clubs, previewMode: true);
    }
    return _AccessState(clubs: clubs, previewMode: true);
  }

  Future<List<CanteraAccessClub>> _previewClubs() async {
    final ligaClubs = await ClubAccessService.listLigaClubs();
    if (ligaClubs.isNotEmpty) return ligaClubs;
    return ClubAccessService.listClubs();
  }

  Future<void> _enter(ClubMembership membership) async {
    if (_loadingClubContext) return;
    setState(() => _loadingClubContext = true);
    ClubAccessService.selectActiveMembership(membership);

    final scope = AppScope.of(context);
    CanteraClubContext? contextData;
    String? syncError;
    try {
      contextData = await ClubAccessService.loadClubContext(membership);
    } on ClubContextLoadException catch (_) {
      syncError = 'No pudimos cargar los datos del club ahora.';
      contextData = null;
    } catch (_) {
      syncError = 'No pudimos cargar los datos del club ahora.';
      contextData = null;
    }
    if (!mounted) return;

    final localClub = scope.loadClub(membership.clubId);
    List<ClubTacticalRecord> sharedRecords = const [];
    try {
      sharedRecords = await ClubAccessService.loadTacticalData(limit: 100);
    } catch (_) {
      sharedRecords = const [];
    }
    if (!mounted) return;

    final basePlayers = contextData == null
        ? localClub.players
        : preservePlayerProfiles(
            incoming: contextData.players,
            existing: localClub.players,
          );
    final profiledPlayers = applyRemotePlayerProfiles(
      players: basePlayers,
      records: sharedRecords,
    );

    scope.updateClub(
      localClub.copyWith(
        id: membership.clubId,
        name: contextData?.teamName.isNotEmpty == true
            ? contextData!.teamName
            : membership.clubName,
        league: membership.ludTeamId == null
            ? localClub.league
            : 'Liga Universitaria',
        dataSource: contextData?.source ?? localClub.dataSource,
        seasonYear: contextData?.seasonYear ?? localClub.seasonYear,
        logoUrl: contextData?.logoUrl.isNotEmpty == true
            ? contextData!.logoUrl
            : localClub.logoUrl,
        syncedAt:
            contextData?.syncedAt?.toUtc().toIso8601String() ??
            localClub.syncedAt,
        categories: contextData?.categories ?? localClub.categories,
        players: profiledPlayers,
      ),
    );
    final allCategories = contextData?.categories ?? localClub.categories;
    final categories = membership.accessibleCategories(allCategories);
    final nextRole =
      membership.role == 'viewer'
          ? UserRole.viewer
          : membership.role == 'club_admin'
          ? UserRole.coordinator
          : membership.role == 'platform_admin'
          ? UserRole.coordinator
          : UserRole.coach;
    scope.selectRole(nextRole);
    if (contextData == null && membership.ludTeamId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${syncError ?? 'No pudimos cargar los datos del club ahora.'} Estás viendo los datos guardados.',
          ),
        ),
      );
    } else if (contextData?.source == 'supabase_cache') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Estás viendo los datos guardados del club.'),
        ),
      );
    }
    if (nextRole != UserRole.coordinator && categories.length > 1) {
      setState(() {
        _loadingClubContext = false;
        _categoryMembership = membership;
        _categoryRoute = widget.forcePreview ? '/preview-home' : '/home';
        _categoryOptions = categories;
        _selectedCategoryId = null;
      });
      return;
    }
    scope.selectCategory(categories.isEmpty ? null : categories.first.id);
    await ClubAccessService.prewarmPrimaryLeagueData(
      membership: membership,
      categories: categories,
    );
    unawaited(
      ClubAccessService.prewarmAllLeagueData(
        membership: membership,
        categories: categories,
      ),
    );
    Navigator.pushReplacementNamed(
      context,
      widget.forcePreview ? '/preview-home' : '/home',
    );
  }

  Future<void> _enterPreview(CanteraAccessClub club) async {
    if (_loadingClubContext) return;
    setState(() => _loadingClubContext = true);
    final membership = ClubMembership(
      clubId: club.id,
      clubName: club.name,
      ludTeamId: club.ludTeamId,
      role: 'coach',
      status: 'active',
    );
    ClubAccessService.selectPreviewMembership(membership);
    final scope = AppScope.of(context);
    CanteraClubContext? contextData;
    try {
      contextData = await ClubAccessService.loadClubContext(
        membership,
      ).timeout(const Duration(seconds: 18));
    } catch (_) {
      contextData = null;
    }
    if (!mounted) return;

    final localClub = scope.loadClub(club.id);
    final players = contextData == null
        ? localClub.players
        : preservePlayerProfiles(
            incoming: contextData.players,
            existing: localClub.players,
          );
    scope.updateClub(
      localClub.copyWith(
        id: club.id,
        name: contextData?.teamName.isNotEmpty == true
            ? contextData!.teamName
            : club.name,
        league: club.ludTeamId == null
            ? localClub.league
            : 'Liga Universitaria',
        dataSource: contextData?.source ?? localClub.dataSource,
        seasonYear: contextData?.seasonYear ?? localClub.seasonYear,
        logoUrl: contextData?.logoUrl.isNotEmpty == true
            ? contextData!.logoUrl
            : localClub.logoUrl,
        syncedAt:
            contextData?.syncedAt?.toUtc().toIso8601String() ??
            localClub.syncedAt,
        categories: contextData?.categories ?? localClub.categories,
        players: players,
      ),
    );
    final categories = contextData?.categories ?? localClub.categories;
    scope.selectRole(UserRole.coach);
    if (categories.length > 1) {
      setState(() {
        _loadingClubContext = false;
        _categoryMembership = membership;
        _categoryRoute = widget.forcePreview ? '/preview-home' : '/home';
        _categoryOptions = categories;
        _selectedCategoryId = null;
      });
      return;
    }
    scope.selectCategory(categories.isEmpty ? null : categories.first.id);
    await ClubAccessService.prewarmPrimaryLeagueData(
      membership: membership,
      categories: categories,
    );
    unawaited(
      ClubAccessService.prewarmAllLeagueData(
        membership: membership,
        categories: categories,
      ),
    );
    Navigator.pushReplacementNamed(
      context,
      widget.forcePreview ? '/preview-home' : '/home',
    );
  }

  Future<void> _enterSelectedCategory() async {
    final membership = _categoryMembership;
    final route = _categoryRoute;
    final category = _categoryOptions
        .cast<CategorySquad?>()
        .firstWhere(
          (item) => item?.id == _selectedCategoryId,
          orElse: () => null,
        );
    if (membership == null || route == null || category == null) {
      setState(() => _message = 'Elegí la categoría que vas a dirigir.');
      return;
    }
    setState(() => _loadingClubContext = true);
    AppScope.of(context).selectCategory(category.id);
    await ClubAccessService.prewarmPrimaryLeagueData(
      membership: membership,
      categories: [category],
    );
    unawaited(
      ClubAccessService.prewarmAllLeagueData(
        membership: membership,
        categories: _categoryOptions,
      ),
    );
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, route);
  }

  Future<void> _requestAccess() async {
    setState(() => _message = 'Elegí un club de la lista para continuar.');
  }

  Future<void> _leave() async {
    if (widget.forcePreview) {
      PreviewAccessService.clear();
      ClubAccessService.clearPreviewMembership();
    }
    if (SupabaseAuthService.currentSession != null) {
      await SupabaseAuthService.signOut();
    }
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CX.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: FutureBuilder<_AccessState>(
                future: _state,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: CX.green),
                    );
                  }

                  final state = snapshot.data!;
                  if (state.localMode) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      Navigator.pushReplacementNamed(context, '/local-setup');
                    });
                    return const Center(
                      child: CircularProgressIndicator(color: CX.green),
                    );
                  }
                  if (_categoryMembership != null) {
                    return _CategoryPicker(
                      clubName: _categoryMembership!.clubName,
                      categories: _categoryOptions,
                      selectedCategoryId: _selectedCategoryId,
                      loading: _loadingClubContext,
                      onChanged: (value) =>
                          setState(() => _selectedCategoryId = value),
                      onEnter: _enterSelectedCategory,
                      onBack: () => setState(() {
                        _categoryMembership = null;
                        _categoryRoute = null;
                        _categoryOptions = const [];
                        _selectedCategoryId = null;
                      }),
                    );
                  }
                  CanteraAccessClub? selectedClub;
                  for (final club in state.clubs) {
                    if (club.id == _selectedClubId) {
                      selectedClub = club;
                      break;
                    }
                  }
                  return _PreviewClubPicker(
                    clubs: state.clubs,
                    selectedClubId: _selectedClubId,
                    loading: _loadingClubContext,
                    onChanged: (value) =>
                        setState(() => _selectedClubId = value),
                    onEnterClub: _enterPreview,
                    onLeave: _leave,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewClubPicker extends StatefulWidget {
  final List<CanteraAccessClub> clubs;
  final String? selectedClubId;
  final bool loading;
  final ValueChanged<String?> onChanged;
  final ValueChanged<CanteraAccessClub> onEnterClub;
  final Future<void> Function() onLeave;

  const _PreviewClubPicker({
    required this.clubs,
    required this.selectedClubId,
    required this.loading,
    required this.onChanged,
    required this.onEnterClub,
    required this.onLeave,
  });

  @override
  State<_PreviewClubPicker> createState() => _PreviewClubPickerState();
}

class _PreviewClubPickerState extends State<_PreviewClubPicker> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = widget.clubs
        .where((club) => club.name.toLowerCase().contains(query))
        .toList();
    final selectedId =
        widget.clubs.any((club) => club.id == widget.selectedClubId)
        ? widget.selectedClubId
        : null;
    CanteraAccessClub? selectedClub;
    if (selectedId != null) {
      selectedClub = widget.clubs.firstWhere((club) => club.id == selectedId);
    } else if (filtered.isNotEmpty) {
      selectedClub = filtered.first;
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: CX.panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AccessBrand(),
          const SizedBox(height: 26),
          const Text(
            'Elegir club',
            style: TextStyle(
              fontSize: 25,
              height: 1.1,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Selecciona tu club. Luego elegis la categoria que vas a dirigir.',
            style: TextStyle(color: CX.muted, height: 1.45, fontSize: 13),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _searchController,
            enabled: !widget.loading,
            decoration: const InputDecoration(
              labelText: 'Buscar club',
              prefixIcon: Icon(Icons.search, size: 19),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CX.panel2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: CX.line),
              ),
              child: const Text(
                'No hay clubes con ese nombre.',
                style: TextStyle(color: CX.muted, fontSize: 13),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final club = filtered[index];
                  final active = club.id == selectedClub?.id;
                  return InkWell(
                    onTap: widget.loading
                        ? null
                        : () => widget.onChanged(club.id),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: active ? CX.greenDark : CX.panel2,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: active ? CX.green : CX.line,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 19,
                            color: active ? CX.green : CX.faint,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              club.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (active)
                            const Icon(
                              Icons.check_circle,
                              color: CX.green,
                              size: 18,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: widget.loading || selectedClub == null
                ? null
                : () => widget.onEnterClub(selectedClub!),
            icon: widget.loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login, size: 18),
            label: Text(widget.loading ? 'Cargando club' : 'Continuar'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: widget.loading ? null : widget.onLeave,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Volver'),
          ),
        ],
      ),
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  final String clubName;
  final List<CategorySquad> categories;
  final String? selectedCategoryId;
  final bool loading;
  final ValueChanged<String?> onChanged;
  final Future<void> Function() onEnter;
  final VoidCallback onBack;

  const _CategoryPicker({
    required this.clubName,
    required this.categories,
    required this.selectedCategoryId,
    required this.loading,
    required this.onChanged,
    required this.onEnter,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final selected = categories
        .cast<CategorySquad?>()
        .firstWhere(
          (category) => category?.id == selectedCategoryId,
          orElse: () => null,
        );
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: CX.panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AccessBrand(),
          const SizedBox(height: 26),
          Text(
            clubName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: CX.green,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Elegir categoría',
            style: TextStyle(
              fontSize: 25,
              height: 1.1,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Seleccioná la categoría que vas a dirigir. La app va a mostrar plantel, tabla, fixture y planificación solo de esa categoría.',
            style: TextStyle(color: CX.muted, height: 1.45, fontSize: 13),
          ),
          const SizedBox(height: 18),
          if (categories.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF6DD),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0x66F0BE57)),
              ),
              child: const Text(
                'No se encontraron categorías para este club.',
                style: TextStyle(color: CX.amber, fontSize: 12, height: 1.35),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 330),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: categories.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final category = categories[index];
                  final active = category.id == selected?.id;
                  return InkWell(
                    onTap: loading ? null : () => onChanged(category.id),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: active ? CX.greenDark : CX.panel2,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: active ? CX.green : CX.line,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.groups_2_outlined,
                            color: active ? CX.green : CX.faint,
                            size: 19,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  category.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  category.playerCount > 0
                                      ? '${category.playerCount} jugadores'
                                      : 'Plantel por cargar',
                                  style: const TextStyle(
                                    color: CX.faint,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (active)
                            const Icon(
                              Icons.check_circle,
                              color: CX.green,
                              size: 18,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: loading || selected == null ? null : onEnter,
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login, size: 18),
            label: Text(loading ? 'Cargando categoría' : 'Entrar'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: loading ? null : onBack,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Cambiar club'),
          ),
        ],
      ),
    );
  }
}

class _AccessBrand extends StatelessWidget {
  const _AccessBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: CX.green,
            borderRadius: BorderRadius.circular(7),
          ),
          child: const Icon(
            Icons.stadium_outlined,
            color: Color(0xFF07100B),
            size: 20,
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'fobal',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _AccessState {
  final List<ClubMembership> activeMemberships;
  final ClubMembership? pending;
  final List<CanteraAccessClub> clubs;
  final bool previewMode;
  final bool localMode;

  const _AccessState({
    this.clubs = const [],
    this.previewMode = false,
    this.localMode = false,
  }) : pending = null, activeMemberships = const [];
}

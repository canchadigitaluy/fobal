// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;

import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import '../services/account_identity_service.dart';
import '../services/club_access_service.dart';
import '../services/club_collaborators_service.dart';
import '../services/club_sync_service.dart';
import '../services/preview_access_service.dart';
import '../services/supabase_auth_service.dart';
import '../ui/branded_loading_screen.dart';

class AccessGateScreen extends StatefulWidget {
  final bool forcePreview;

  const AccessGateScreen({super.key, this.forcePreview = false});

  @override
  State<AccessGateScreen> createState() => _AccessGateScreenState();
}

class _AccessGateScreenState extends State<AccessGateScreen> {
  late Future<_AccessState> _state;
  String? _selectedClubId;
  String? _selectedCategoryId;
  final _inviteController = TextEditingController();
  bool _loadingClubContext = false;
  ClubMembership? _categoryMembership;
  String? _categoryRoute;
  String _categoryClubLogoUrl = '';
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
    List<ClubCollaboration> collaborations = const [];
    try {
      collaborations = await ClubCollaboratorsService.myCollaborations();
    } catch (_) {
      collaborations = const [];
    }
    ClubMembership? pending;
    try {
      pending = await ClubAccessService.pendingMembership();
    } catch (_) {
      pending = null;
    }
    return _AccessState(
      clubs: clubs,
      collaborations: collaborations,
      previewMode: true,
      pending: pending,
    );
  }

  Future<List<CanteraAccessClub>> _previewClubs() async {
    final ligaClubs = await ClubAccessService.listLigaClubs();
    if (ligaClubs.isNotEmpty) return ligaClubs;
    return ClubAccessService.listClubs();
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Un club lo dirige una sola cuenta: la primera que lo reclama. Las demas
  /// tienen que pedir acceso y esperar la aprobacion del director. Devuelve
  /// true solo si ya se puede entrar.
  Future<bool> _passClaimGate(CanteraAccessClub club) async {
    final status = await ClubAccessService.clubClaimStatus(club.id);
    if (!mounted) return false;
    switch (status) {
      case 'free':
        final ok = await _confirm(
          title: 'Dirigir ${club.name}',
          body:
              'Al continuar quedás como director de este club. Los demás '
              'entrenadores van a tener que pedirte acceso para entrar.',
          action: 'Continuar',
        );
        if (!ok || !mounted) return false;
        return _requestClubAccess(club);
      case 'claimed':
        final ok = await _confirm(
          title: '${club.name} ya tiene director',
          body:
              'Solo el director puede darte acceso a este club. ¿Querés '
              'enviarle una solicitud?',
          action: 'Pedir acceso',
        );
        if (ok && mounted) await _requestClubAccess(club);
        return false;
      case 'pending':
        _snack('Tu solicitud a ${club.name} sigue esperando aprobación.');
        return false;
      case 'other':
        _snack(_oneClubMessage);
        return false;
      default:
        return true;
    }
  }

  Future<bool> _requestClubAccess(CanteraAccessClub club) async {
    try {
      final result = await ClubAccessService.requestAccess(
        clubId: club.id,
        role: 'coach',
        inviteCode: '',
      );
      if (!mounted) return false;
      if (result == 'active') return true;
      _snack('Solicitud enviada. El director del club tiene que aprobarla.');
      setState(() => _state = _load());
    } catch (error) {
      if (mounted) {
        _snack(
          error.toString().contains('already_in_another_club')
              ? _oneClubMessage
              : 'No pudimos enviar la solicitud. Probá de nuevo.',
        );
      }
    }
    return false;
  }

  static const _oneClubMessage =
      'Tu cuenta ya pertenece a otro club. Cada cuenta gestiona un solo club.';

  Future<void> _enterPreview(CanteraAccessClub club) async {
    if (_loadingClubContext) return;
    if (!widget.forcePreview && SupabaseAuthService.currentSession != null) {
      if (!await _passClaimGate(club)) return;
    }
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
        _categoryClubLogoUrl = club.logoUrl;
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

  Future<void> _enterCollaboration(ClubCollaboration collaboration) async {
    if (_loadingClubContext) return;
    setState(() => _loadingClubContext = true);
    final membership = ClubMembership(
      clubId: collaboration.clubId,
      clubName: collaboration.clubName,
      ludTeamId: null,
      role: collaboration.role,
      status: 'active',
    );
    ClubAccessService.selectActiveMembership(membership);
    AccountIdentityService.writeActiveClubId(collaboration.clubId);
    final scope = AppScope.of(context);
    final document = await ClubSyncService.pull(collaboration.clubId);
    if (!mounted) return;
    if (document == null || document.club.id != collaboration.clubId) {
      setState(() => _loadingClubContext = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos abrir ese club compartido.')),
      );
      return;
    }
    ClubSyncService.rememberVersion(document.club.id, document.version);
    scope.adoptClub(document.club);
    final categories = document.club.categories;
    scope.selectRole(
      collaboration.role == 'viewer' ? UserRole.viewer : UserRole.coach,
    );
    if (categories.length > 1) {
      setState(() {
        _loadingClubContext = false;
        _categoryMembership = membership;
        _categoryRoute = '/collaboration-home';
        _categoryOptions = categories;
        _selectedCategoryId = null;
        _categoryClubLogoUrl = document.club.logoUrl;
      });
      return;
    }
    scope.selectCategory(categories.isEmpty ? null : categories.first.id);
    Navigator.pushReplacementNamed(context, '/collaboration-home');
  }

  Future<void> _enterSelectedCategory() async {
    final membership = _categoryMembership;
    final route = _categoryRoute;
    final category = _categoryOptions.cast<CategorySquad?>().firstWhere(
      (item) => item?.id == _selectedCategoryId,
      orElse: () => null,
    );
    if (membership == null || route == null || category == null) {
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
    return FutureBuilder<_AccessState>(
      future: _state,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const BrandedLoadingScreen();
        }

        final state = snapshot.data!;
        if (state.localMode) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.pushReplacementNamed(context, '/local-setup');
          });
          return const BrandedLoadingScreen();
        }

        return Scaffold(
          backgroundColor: CX.bg,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, viewport) {
                return SizedBox(
                  width: viewport.maxWidth,
                  height: viewport.maxHeight,
                  child: _categoryMembership != null
                            ? _CategoryPicker(
                                clubName: _categoryMembership!.clubName,
                                clubLogoUrl: _categoryClubLogoUrl,
                                categories: _categoryOptions,
                                selectedCategoryId: _selectedCategoryId,
                                loading: _loadingClubContext,
                                onChanged: (value) => setState(
                                  () => _selectedCategoryId = value,
                                ),
                                onEnter: _enterSelectedCategory,
                                onBack: () => setState(() {
                                  _categoryMembership = null;
                                  _categoryRoute = null;
                                  _categoryOptions = const [];
                                  _selectedCategoryId = null;
                                }),
                              )
                            : _PreviewClubPicker(
                                clubs: state.clubs,
                                collaborations: state.collaborations,
                                pending: state.pending,
                                selectedClubId: _selectedClubId,
                                loading: _loadingClubContext,
                                onChanged: (value) =>
                                    setState(() => _selectedClubId = value),
                                onEnterClub: _enterPreview,
                                onEnterCollaboration: _enterCollaboration,
                                onLeave: _leave,
                              ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _PreviewClubPicker extends StatefulWidget {
  final List<CanteraAccessClub> clubs;
  final List<ClubCollaboration> collaborations;
  final ClubMembership? pending;
  final String? selectedClubId;
  final bool loading;
  final ValueChanged<String?> onChanged;
  final ValueChanged<CanteraAccessClub> onEnterClub;
  final ValueChanged<ClubCollaboration> onEnterCollaboration;
  final Future<void> Function() onLeave;

  const _PreviewClubPicker({
    required this.clubs,
    required this.collaborations,
    required this.pending,
    required this.selectedClubId,
    required this.loading,
    required this.onChanged,
    required this.onEnterClub,
    required this.onEnterCollaboration,
    required this.onLeave,
  });

  @override
  State<_PreviewClubPicker> createState() => _PreviewClubPickerState();
}

const int _clubPickerVisibleCap = 60;

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
    final visible = filtered.take(_clubPickerVisibleCap).toList();

    return Container(
      color: CX.panel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 700;
          final brand = _ClubPickerBrandPanel(
            clubChosen: selectedClub != null,
            compact: narrow,
          );
          final picker = _ClubPickerListPanel(
            clubs: widget.clubs,
            collaborations: widget.collaborations,
            pending: widget.pending,
            visible: visible,
            totalFiltered: filtered.length,
            query: query,
            selectedClub: selectedClub,
            loading: widget.loading,
            searchController: _searchController,
            onQueryChanged: () => setState(() {}),
            onSelect: widget.onChanged,
            onContinue: selectedClub == null
                ? null
                : () => widget.onEnterClub(selectedClub!),
            onEnterCollaboration: widget.onEnterCollaboration,
            onLeave: widget.onLeave,
          );
          if (narrow) {
            return Column(
              children: [
                brand,
                Expanded(child: picker),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: brand),
              Expanded(flex: 5, child: picker),
            ],
          );
        },
      ),
    );
  }
}

/// Left panel: brand, copy, and the club→category step indicator. A faint
/// pitch-lines overlay and a soft glow give it presence instead of a flat
/// fill — purely decorative, no data.
class _ClubPickerBrandPanel extends StatelessWidget {
  final bool clubChosen;
  final bool compact;
  const _ClubPickerBrandPanel({
    required this.clubChosen,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: compact
          ? const EdgeInsets.fromLTRB(20, 18, 20, 18)
          : const EdgeInsets.fromLTRB(30, 32, 30, 32),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF16332A), Color(0xFF0C201A)],
        ),
      ),
      child: Stack(
        children: [
          if (!compact)
            Positioned.fill(
              child: Opacity(
                opacity: .16,
                child: CustomPaint(painter: PitchLinesPainter()),
              ),
            ),
          Positioned(
            right: -70,
            bottom: -90,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [CX.green.withValues(alpha: .28), Colors.transparent],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: compact ? 32 : 36,
                    height: compact ? 32 : 36,
                    decoration: BoxDecoration(
                      color: CX.green,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x40000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'fobal',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 17 : 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: compact ? 0 : -.3,
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 12 : 26),
              Text(
                'Elegí tu club',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 20 : 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: compact ? 0 : -.3,
                  height: 1.2,
                ),
              ),
              SizedBox(height: compact ? 4 : 10),
              Text(
                'Seleccioná el club que vas a dirigir. Vas a elegir la categoría a continuación.',
                maxLines: compact ? 1 : null,
                overflow: compact ? TextOverflow.ellipsis : null,
                style: TextStyle(
                  color: const Color(0xDDE0F3EB),
                  fontSize: compact ? 13 : 14.5,
                  height: compact ? 1.25 : 1.55,
                ),
              ),
              SizedBox(height: compact ? 10 : 40),
              Container(height: 1, color: Colors.white.withValues(alpha: .18)),
              SizedBox(height: compact ? 8 : 16),
              _ClubPickerStepper(clubChosen: clubChosen),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClubPickerStepper extends StatelessWidget {
  final bool clubChosen;
  const _ClubPickerStepper({required this.clubChosen});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StepDot(label: 'Club', done: clubChosen, active: true),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Stack(
              children: [
                Container(height: 2, color: Colors.white.withValues(alpha: .2)),
                AnimatedContainer(
                  duration: CX.motion,
                  curve: CX.curve,
                  height: 2,
                  width: clubChosen ? double.infinity : 0,
                  color: CX.green,
                ),
              ],
            ),
          ),
        ),
        Opacity(
          opacity: .55,
          child: _StepDot(
            label: 'Categoría',
            done: false,
            active: false,
            number: '2',
          ),
        ),
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  final String label;
  final bool done;
  final bool active;
  final String number;
  // A step can be filled/green without being "done" (checked) — the
  // current step on the Categoría screen is filled but still shows "2".
  final bool? filled;
  const _StepDot({
    required this.label,
    required this.done,
    required this.active,
    this.number = '1',
    this.filled,
  });

  @override
  Widget build(BuildContext context) {
    final isFilled = filled ?? done;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: CX.motionFast,
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled ? CX.green : Colors.transparent,
            border: Border.all(
              color: isFilled
                  ? CX.green
                  : Colors.white.withValues(alpha: active ? .9 : .6),
              width: 1.5,
            ),
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check, size: 13, color: Colors.white)
                : Text(
                    number,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 13.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Right panel: search, results, the club list, and the continue/back
/// actions. Everything here is real data — no invented city/division.
class _ClubPickerListPanel extends StatelessWidget {
  final List<CanteraAccessClub> clubs;
  final List<ClubCollaboration> collaborations;
  final ClubMembership? pending;
  final List<CanteraAccessClub> visible;
  final int totalFiltered;
  final String query;
  final CanteraAccessClub? selectedClub;
  final bool loading;
  final TextEditingController searchController;
  final VoidCallback onQueryChanged;
  final ValueChanged<String?> onSelect;
  final VoidCallback? onContinue;
  final ValueChanged<ClubCollaboration> onEnterCollaboration;
  final Future<void> Function() onLeave;

  const _ClubPickerListPanel({
    required this.clubs,
    required this.collaborations,
    required this.pending,
    required this.visible,
    required this.totalFiltered,
    required this.query,
    required this.selectedClub,
    required this.loading,
    required this.searchController,
    required this.onQueryChanged,
    required this.onSelect,
    required this.onContinue,
    required this.onEnterCollaboration,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 30, 30, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pending != null) ...[
            _PendingRequestBanner(pending: pending!),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  '${clubs.length} club${clubs.length == 1 ? '' : 'es'} disponibles',
                  style: const TextStyle(
                    color: CX.faint,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                decoration: BoxDecoration(
                  color: CX.panel,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: CX.line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: CX.greenDark,
                        shape: BoxShape.circle,
                      ),
                      child: const Text(
                        'DT',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: CX.green,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Mi cuenta',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: CX.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: searchController,
            enabled: !loading,
            decoration: InputDecoration(
              hintText: 'Buscar club',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        searchController.clear();
                        onQueryChanged();
                      },
                    ),
            ),
            onChanged: (_) => onQueryChanged(),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                totalFiltered == 0
                    ? ''
                    : '$totalFiltered club${totalFiltered == 1 ? '' : 'es'}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: CX.muted,
                ),
              ),
              Text(
                selectedClub == null
                    ? 'Ningún club seleccionado'
                    : selectedClub!.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: CX.faint),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (totalFiltered == 0)
            Expanded(
              child: Center(
                child: _ClubPickerEmptyResults(
                  query: query,
                  onClear: () {
                    searchController.clear();
                    onQueryChanged();
                  },
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: visible.length,
                separatorBuilder: (_, _) => const SizedBox(height: 9),
                itemBuilder: (context, index) {
                  final club = visible[index];
                  final active = club.id == selectedClub?.id;
                  return _ClubRow(
                    club: club,
                    active: active,
                    query: query,
                    onTap: loading ? null : () => onSelect(club.id),
                  );
                },
              ),
            ),
          if (totalFiltered > _clubPickerVisibleCap) ...[
            const SizedBox(height: 8),
            Text(
              'Mostrando ${visible.length} de $totalFiltered — seguí escribiendo para refinar la búsqueda.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: CX.faint),
            ),
          ],
          if (collaborations.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Divider(height: 1, color: CX.line),
            const SizedBox(height: 14),
            const Text(
              'También colaborás en estos clubes',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 9),
            ...collaborations.map(
              (collaboration) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CollaborationRow(
                  collaboration: collaboration,
                  loading: loading,
                  onTap: () => onEnterCollaboration(collaboration),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: loading || onContinue == null ? null : onContinue,
              icon: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward, size: 17),
              label: Text(loading ? 'Cargando club' : 'Continuar'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: loading ? null : onLeave,
              icon: const Icon(Icons.arrow_back, size: 17),
              label: const Text('Volver'),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '¿No encontrás tu club? Escribinos a soporte@fobal.com',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: CX.faint),
          ),
        ],
      ),
    );
  }
}

/// A club-membership request from a previous session that's still waiting
/// on a club_admin to review it. Explorá clubes de la liga (below) works
/// without this — it never needed a membership — but a DT who tried the
/// invite-code path for a private club deserves to know why nothing
/// happened after they asked, instead of silence.
class _PendingRequestBanner extends StatelessWidget {
  final ClubMembership pending;
  const _PendingRequestBanner({required this.pending});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CX.amber.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.amber.withValues(alpha: .22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.hourglass_top_outlined, color: CX.amber, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Solicitud pendiente en ${pending.clubName}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Un admin del club todavía no la aprobó. Mientras tanto, '
                  'podés explorar cualquier club de la liga desde la lista '
                  'de abajo.',
                  style: TextStyle(fontSize: 13, color: CX.muted, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CollaborationRow extends StatelessWidget {
  final ClubCollaboration collaboration;
  final bool loading;
  final VoidCallback onTap;

  const _CollaborationRow({
    required this.collaboration,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: loading ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: CX.panel2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: CX.line),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: CX.greenDark,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.handshake_outlined,
                color: CX.green,
                size: 19,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    collaboration.clubName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _collaborationRoleName(collaboration.role),
                    style: const TextStyle(fontSize: 13, color: CX.faint),
                  ),
                ],
              ),
            ),
            const Icon(Icons.login, color: CX.green, size: 18),
          ],
        ),
      ),
    );
  }
}

String _collaborationRoleName(String role) => switch (role) {
  'coach' => 'Director tecnico',
  'assistant' => 'Ayudante tecnico',
  'physical_trainer' => 'Preparador fisico',
  'viewer' => 'Solo lectura',
  _ => role,
};

class _ClubPickerEmptyResults extends StatelessWidget {
  final String query;
  final VoidCallback onClear;
  const _ClubPickerEmptyResults({required this.query, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: CX.panel2,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.search_off, size: 22, color: CX.faint),
          ),
          const SizedBox(height: 12),
          const Text(
            'Sin resultados',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'No encontramos clubes para "$query".',
            style: const TextStyle(fontSize: 13, color: CX.muted),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: onClear,
            child: const Text('Limpiar búsqueda'),
          ),
        ],
      ),
    );
  }
}

class _ClubRow extends StatefulWidget {
  final CanteraAccessClub club;
  final bool active;
  final String query;
  final VoidCallback? onTap;
  const _ClubRow({
    required this.club,
    required this.active,
    required this.query,
    required this.onTap,
  });

  @override
  State<_ClubRow> createState() => _ClubRowState();
}

class _ClubRowState extends State<_ClubRow> {
  bool _hover = false;

  List<InlineSpan> _highlighted(String name, String query) {
    if (query.isEmpty) return [TextSpan(text: name)];
    final lower = name.toLowerCase();
    final idx = lower.indexOf(query);
    if (idx < 0) return [TextSpan(text: name)];
    return [
      if (idx > 0) TextSpan(text: name.substring(0, idx)),
      TextSpan(
        text: name.substring(idx, idx + query.length),
        style: const TextStyle(
          backgroundColor: Color(0x55E0C24A),
          color: Color(0xFF3A2E05),
        ),
      ),
      if (idx + query.length < name.length)
        TextSpan(text: name.substring(idx + query.length)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final club = widget.club;
    final active = widget.active;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: CX.motionFast,
        curve: CX.curve,
        transform: Matrix4.translationValues(0, _hover && !active ? -2 : 0, 0),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: CX.motionFast,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: active ? CX.greenDark : CX.panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active
                    ? CX.green
                    : (_hover ? CX.green.withValues(alpha: .4) : CX.line),
              ),
              boxShadow: _hover && !active
                  ? [
                      BoxShadow(
                        color: CX.green.withValues(alpha: .18),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: active
                          ? [CX.green.withValues(alpha: .7), CX.green]
                          : [CX.line, CX.panel2],
                    ),
                  ),
                  child: ClubCrest(logoUrl: club.logoUrl, size: 39),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RichText(
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: CX.white,
                          ),
                          children: _highlighted(club.name, widget.query),
                        ),
                      ),
                      if (club.ludTeamId != null) ...[
                        const SizedBox(height: 2),
                        const Text(
                          'Liga Universitaria',
                          style: TextStyle(fontSize: 11, color: CX.faint),
                        ),
                      ],
                    ],
                  ),
                ),
                AnimatedScale(
                  duration: CX.motionFast,
                  curve: Curves.elasticOut,
                  scale: active ? 1 : 0,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: CX.green,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  final String clubName;
  final String clubLogoUrl;
  final List<CategorySquad> categories;
  final String? selectedCategoryId;
  final bool loading;
  final ValueChanged<String?> onChanged;
  final Future<void> Function() onEnter;
  final VoidCallback onBack;

  const _CategoryPicker({
    required this.clubName,
    required this.clubLogoUrl,
    required this.categories,
    required this.selectedCategoryId,
    required this.loading,
    required this.onChanged,
    required this.onEnter,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final selected = categories.cast<CategorySquad?>().firstWhere(
      (category) => category?.id == selectedCategoryId,
      orElse: () => null,
    );
    return Container(
      color: CX.panel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 700;
          final brand = _CategoryBrandPanel(
            clubName: clubName,
            clubLogoUrl: clubLogoUrl,
            compact: narrow,
          );
          final picker = _CategoryListPanel(
            categories: categories,
            selected: selected,
            loading: loading,
            onSelect: onChanged,
            onEnter: selected == null ? null : onEnter,
            onBack: onBack,
          );
          if (narrow) {
            return Column(
              children: [
                brand,
                Expanded(child: picker),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: brand),
              Expanded(flex: 5, child: picker),
            ],
          );
        },
      ),
    );
  }
}

/// Left panel: same brand treatment as the club picker, plus a chip
/// reminding which club is already chosen (crest + name) and the stepper
/// now showing step 1 done, step 2 current.
class _CategoryBrandPanel extends StatelessWidget {
  final String clubName;
  final String clubLogoUrl;
  final bool compact;
  const _CategoryBrandPanel({
    required this.clubName,
    required this.clubLogoUrl,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: compact
          ? const EdgeInsets.fromLTRB(20, 12, 20, 12)
          : const EdgeInsets.fromLTRB(30, 32, 30, 32),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF16332A), Color(0xFF0C201A)],
        ),
      ),
      child: Stack(
        children: [
          if (!compact)
            Positioned.fill(
              child: Opacity(
                opacity: .16,
                child: CustomPaint(painter: PitchLinesPainter()),
              ),
            ),
          Positioned(
            right: -70,
            bottom: -90,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [CX.green.withValues(alpha: .28), Colors.transparent],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: compact ? 32 : 36,
                    height: compact ? 32 : 36,
                    decoration: BoxDecoration(
                      color: CX.green,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x40000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'fobal',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 17 : 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: compact ? 0 : -.3,
                    ),
                  ),
                ],
              ),
              SizedBox(height: compact ? 6 : 22),
              Container(
                padding: EdgeInsets.all(compact ? 4 : 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .14),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: compact ? 30 : 42,
                      height: compact ? 30 : 42,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [CX.green.withValues(alpha: .7), CX.green],
                        ),
                      ),
                      child: ClubCrest(
                        logoUrl: clubLogoUrl,
                        size: compact ? 26 : 38,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'CLUB SELECCIONADO',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .65),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: .5,
                            ),
                          ),
                          Text(
                            clubName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: compact ? 8 : 22),
              Text(
                '¿Qué categoría dirigís?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 20 : 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: compact ? 0 : -.3,
                  height: 1.2,
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 10),
                const Text(
                  'Cada categoría tiene su propio plantel, tabla, fixture y planificación de entrenamientos.',
                  style: TextStyle(
                    color: Color(0xDDE0F3EB),
                    fontSize: 14.5,
                    height: 1.55,
                  ),
                ),
              ],
              SizedBox(height: compact ? 8 : 40),
              Container(height: 1, color: Colors.white.withValues(alpha: .18)),
              SizedBox(height: compact ? 6 : 16),
              Row(
                children: [
                  const _StepDot(label: 'Club', done: true, active: false),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: SizedBox(
                        height: 2,
                        child: ColoredBox(color: CX.green),
                      ),
                    ),
                  ),
                  const _StepDot(
                    label: 'Categoría',
                    done: false,
                    active: true,
                    number: '2',
                    filled: true,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CategoryListPanel extends StatelessWidget {
  final List<CategorySquad> categories;
  final CategorySquad? selected;
  final bool loading;
  final ValueChanged<String?> onSelect;
  final Future<void> Function()? onEnter;
  final VoidCallback onBack;

  const _CategoryListPanel({
    required this.categories,
    required this.selected,
    required this.loading,
    required this.onSelect,
    required this.onEnter,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 30, 30, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${categories.length} categoría${categories.length == 1 ? '' : 's'} activas',
                  style: const TextStyle(
                    color: CX.faint,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                decoration: BoxDecoration(
                  color: CX.panel,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: CX.line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: CX.greenDark,
                        shape: BoxShape.circle,
                      ),
                      child: const Text(
                        'DT',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: CX.green,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Mi cuenta',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: CX.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (categories.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF6DD),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x66F0BE57)),
              ),
              child: const Text(
                'No se encontraron categorías para este club.',
                style: TextStyle(color: CX.amber, fontSize: 12.5, height: 1.4),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: categories.length,
                separatorBuilder: (_, _) => const SizedBox(height: 9),
                itemBuilder: (context, index) {
                  final category = categories[index];
                  final active = category.id == selected?.id;
                  return _CategoryRow(
                    category: category,
                    active: active,
                    onTap: loading ? null : () => onSelect(category.id),
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: loading || onEnter == null ? null : onEnter,
              icon: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login, size: 17),
              label: Text(loading ? 'Cargando categoría' : 'Entrar'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: loading ? null : onBack,
              icon: const Icon(Icons.arrow_back, size: 17),
              label: const Text('Cambiar club'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatefulWidget {
  final CategorySquad category;
  final bool active;
  final VoidCallback? onTap;
  const _CategoryRow({
    required this.category,
    required this.active,
    required this.onTap,
  });

  @override
  State<_CategoryRow> createState() => _CategoryRowState();
}

class _CategoryRowState extends State<_CategoryRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    final active = widget.active;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: CX.motionFast,
        curve: CX.curve,
        transform: Matrix4.translationValues(0, _hover && !active ? -2 : 0, 0),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: CX.motionFast,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: active ? CX.greenDark : CX.panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active
                    ? CX.green
                    : (_hover ? CX.green.withValues(alpha: .4) : CX.line),
              ),
              boxShadow: _hover && !active
                  ? [
                      BoxShadow(
                        color: CX.green.withValues(alpha: .18),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? CX.green : CX.panel2,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.groups_2_outlined,
                    color: active ? Colors.white : CX.faint,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        category.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: CX.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        category.playerCount > 0
                            ? '${category.playerCount} jugadores'
                            : 'Plantel por cargar',
                        style: const TextStyle(fontSize: 12, color: CX.faint),
                      ),
                    ],
                  ),
                ),
                AnimatedScale(
                  duration: CX.motionFast,
                  curve: Curves.elasticOut,
                  scale: active ? 1 : 0,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: CX.green,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccessState {
  final ClubMembership? pending;
  final List<CanteraAccessClub> clubs;
  final List<ClubCollaboration> collaborations;
  final bool previewMode;
  final bool localMode;

  const _AccessState({
    this.clubs = const [],
    this.collaborations = const [],
    this.previewMode = false,
    this.localMode = false,
    this.pending,
  });
}

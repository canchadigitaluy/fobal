import 'dart:async';

import 'package:flutter/material.dart';
import '../data/cantera_data.dart';
import '../main.dart';
import '../services/account_identity_service.dart';
import '../services/club_access_service.dart';
import '../services/club_backup_service.dart';
import '../services/club_collaborators_service.dart';
import '../services/offline_mutation_service.dart';
import '../services/plantel_service.dart';
import '../services/supabase_auth_service.dart';
import '../ui/ui_kit.dart';
import 'add_player_dialog.dart';

class ConfiguracionClubScreen extends StatefulWidget {
  const ConfiguracionClubScreen({super.key});

  @override
  State<ConfiguracionClubScreen> createState() =>
      _ConfiguracionClubScreenState();
}

class _ConfiguracionClubScreenState extends State<ConfiguracionClubScreen> {
  final _nameController = TextEditingController();
  final _leagueController = TextEditingController();
  final _headCoachController = TextEditingController();
  final _assistantCoachController = TextEditingController();
  final _categoryNameController = TextEditingController();
  final _categoryAgeController = TextEditingController();
  final _categoryCoachController = TextEditingController();
  final _categoryPlayersController = TextEditingController();
  final _categoryFocusController = TextEditingController();
  final _categoryScheduleController = TextEditingController();
  final _playerFirstNameController = TextEditingController();
  final _playerLastNameController = TextEditingController();
  final _playerAgeController = TextEditingController();
  final _playerPositionController = TextEditingController();
  final _playerFootController = TextEditingController();
  final _playerStatusController = TextEditingController(text: 'Disponible');
  final _playerStatusDetailController = TextEditingController();
  final _playerSuspensionController = TextEditingController();
  final _playerNoteController = TextEditingController();
  final _playingStyleController = TextEditingController();
  final _offensiveController = TextEditingController();
  final _defensiveController = TextEditingController();
  final _ageObjectivesController = TextEditingController();
  final _evaluationController = TextEditingController();
  Color _primaryColor = CX.green;
  String? _selectedPlayerCategoryId;
  int _sectionIndex = 0;
  late Future<List<ClubMemberAccess>> _membersFuture;
  Future<List<ClubCollaborator>>? _collaboratorsFuture;
  String? _collaboratorsClubId;

  @override
  void initState() {
    super.initState();
    _membersFuture = ClubAccessService.loadClubMembers();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final club = AppScope.of(context).club;
    if (_nameController.text.isEmpty && club.name != 'Club Demo') {
      _nameController.text = club.name;
    }
    if (_leagueController.text.isEmpty) _leagueController.text = club.league;
    if (_headCoachController.text.isEmpty) {
      _headCoachController.text = club.headCoachName;
    }
    if (_assistantCoachController.text.isEmpty) {
      _assistantCoachController.text = club.assistantCoachName;
    }
    if (_playingStyleController.text.isEmpty) {
      _playingStyleController.text = club.methodology.playingStyle;
      _offensiveController.text = club.methodology.offensivePrinciples.join(
        '\n',
      );
      _defensiveController.text = club.methodology.defensivePrinciples.join(
        '\n',
      );
      _ageObjectivesController.text = club.methodology.ageObjectives.join('\n');
      _evaluationController.text = club.methodology.evaluationCriteria.join(
        '\n',
      );
    }
    if (_selectedPlayerCategoryId == null && club.categories.isNotEmpty) {
      _selectedPlayerCategoryId = club.categories.first.id;
    }
    _primaryColor = club.primaryColor;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _leagueController.dispose();
    _headCoachController.dispose();
    _assistantCoachController.dispose();
    _categoryNameController.dispose();
    _categoryAgeController.dispose();
    _categoryCoachController.dispose();
    _categoryPlayersController.dispose();
    _categoryFocusController.dispose();
    _categoryScheduleController.dispose();
    _playerFirstNameController.dispose();
    _playerLastNameController.dispose();
    _playerAgeController.dispose();
    _playerPositionController.dispose();
    _playerFootController.dispose();
    _playerStatusController.dispose();
    _playerStatusDetailController.dispose();
    _playerSuspensionController.dispose();
    _playerNoteController.dispose();
    _playingStyleController.dispose();
    _offensiveController.dispose();
    _defensiveController.dispose();
    _ageObjectivesController.dispose();
    _evaluationController.dispose();
    super.dispose();
  }

  void _saveBasicData() {
    final scope = AppScope.of(context);
    scope.updateClub(
      scope.club.copyWith(
        name: _nameController.text.trim().isEmpty
            ? 'Club Demo'
            : _nameController.text.trim(),
        league: _leagueController.text.trim(),
        headCoachName: _headCoachController.text.trim(),
        assistantCoachName: _assistantCoachController.text.trim(),
        sportFocus: 'Futbol',
        primaryColor: _primaryColor,
      ),
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Datos basicos guardados.')));
  }

  void _resetDemo() {
    AppScope.of(context).updateClub(canteraDemoClub);
    _nameController.clear();
    _leagueController.clear();
    _headCoachController.clear();
    _assistantCoachController.clear();
    _categoryNameController.clear();
    _categoryAgeController.clear();
    _categoryCoachController.clear();
    _categoryPlayersController.clear();
    _categoryFocusController.clear();
    _categoryScheduleController.clear();
    _playerFirstNameController.clear();
    _playerLastNameController.clear();
    _playerAgeController.clear();
    _playerPositionController.clear();
    _playerFootController.clear();
    _playerNoteController.clear();
    _selectedPlayerCategoryId = null;
    _playingStyleController.clear();
    _offensiveController.clear();
    _defensiveController.clear();
    _ageObjectivesController.clear();
    _evaluationController.clear();
  }

  void _addCategory() {
    final name = _categoryNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa el nombre de la categoria.')),
      );
      return;
    }

    final scope = AppScope.of(context);
    final category = CategorySquad(
      id: 'cat-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      sport: 'Futbol',
      ageGroup: _categoryAgeController.text.trim(),
      coachName: _categoryCoachController.text.trim(),
      playerCount: int.tryParse(_categoryPlayersController.text.trim()) ?? 0,
      attendanceRate: 0,
      objectives: const [],
      currentFocus: _categoryFocusController.text.trim(),
      lastRegistered: '',
      practiceSchedule: _categoryScheduleController.text.trim(),
    );

    scope.updateClub(
      scope.club.copyWith(categories: [...scope.club.categories, category]),
    );
    setState(() => _selectedPlayerCategoryId ??= category.id);

    _categoryNameController.clear();
    _categoryAgeController.clear();
    _categoryCoachController.clear();
    _categoryPlayersController.clear();
    _categoryFocusController.clear();
    _categoryScheduleController.clear();
  }

  Future<void> _addPlayer() async {
    final categoryId = _selectedPlayerCategoryId;
    final firstName = _playerFirstNameController.text.trim();
    final lastName = _playerLastNameController.text.trim();
    if (categoryId == null || firstName.isEmpty) return;

    final scope = AppScope.of(context);
    final nameKey = '${firstName.toLowerCase()} ${lastName.toLowerCase()}'
        .trim();
    final existing = normalizedPlayerNames(
      scope.club.players.where((p) => p.categoryId == categoryId),
    );
    if (existing.contains(nameKey)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Nombre repetido'),
          content: Text(
            'Ya hay un jugador llamado "$firstName $lastName" en esta '
            'categoría. ¿Agregarlo igual?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Agregar igual'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final player = Player(
      id: 'player-${DateTime.now().millisecondsSinceEpoch}',
      categoryId: categoryId,
      firstName: firstName,
      lastName: lastName,
      age: int.tryParse(_playerAgeController.text.trim()) ?? 0,
      position: _playerPositionController.text.trim(),
      secondaryPositions: '',
      dominantFoot: _playerFootController.text.trim(),
      status: _playerStatusController.text.trim().isEmpty
          ? 'Disponible'
          : _playerStatusController.text.trim(),
      statusDetail: _playerStatusDetailController.text.trim(),
      suspensionDates:
          int.tryParse(_playerSuspensionController.text.trim()) ?? 0,
      attendanceRate: 0,
      trend: '',
      note: _playerNoteController.text.trim(),
    );
    final nextPlayers = [...scope.club.players, player];
    final categories = scope.club.categories
        .map(
          (category) => category.id == categoryId
              ? category.copyWith(
                  playerCount: nextPlayers
                      .where((candidate) => candidate.categoryId == categoryId)
                      .length,
                )
              : category,
        )
        .toList();
    scope.updateClub(
      scope.club.copyWith(players: nextPlayers, categories: categories),
    );
    _playerFirstNameController.clear();
    _playerLastNameController.clear();
    _playerAgeController.clear();
    _playerPositionController.clear();
    _playerFootController.clear();
    _playerStatusController.text = 'Disponible';
    _playerStatusDetailController.clear();
    _playerSuspensionController.clear();
    _playerNoteController.clear();
  }

  void _deletePlayer(String id) {
    if (id.startsWith('lud-player-')) return;
    final scope = AppScope.of(context);
    Player? removed;
    for (final player in scope.club.players) {
      if (player.id == id) {
        removed = player;
        break;
      }
    }
    final nextPlayers = scope.club.players.where((p) => p.id != id).toList();
    final categories = removed == null
        ? scope.club.categories
        : scope.club.categories
              .map(
                (category) => category.id == removed!.categoryId
                    ? category.copyWith(
                        playerCount: nextPlayers
                            .where(
                              (candidate) =>
                                  candidate.categoryId == removed!.categoryId,
                            )
                            .length,
                      )
                    : category,
              )
              .toList();
    scope.updateClub(
      scope.club.copyWith(players: nextPlayers, categories: categories),
    );
  }

  void _deleteCategory(String id) {
    if (id.startsWith('lud-cat-')) return;
    final scope = AppScope.of(context);
    scope.updateClub(
      scope.club.copyWith(
        categories: scope.club.categories.where((c) => c.id != id).toList(),
        planteles: scope.club.planteles
            .where((plantel) => plantel.categoryId != id)
            .toList(),
        players: scope.club.players.where((p) => p.categoryId != id).toList(),
      ),
    );
  }

  Future<void> _addPlantel(CategorySquad category) async {
    if (isLudCategoryId(category.id)) return;
    final name = await promptForText(
      context,
      title: 'Nuevo plantel',
      labelText: 'Nombre',
      hintText: 'Ej. A, B o Arqueros',
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    final scope = AppScope.of(context);
    scope.updateClub(
      scope.club.copyWith(
        planteles: [
          ...scope.club.planteles,
          Plantel(
            id: 'plantel-${DateTime.now().microsecondsSinceEpoch}',
            categoryId: category.id,
            name: name.trim(),
          ),
        ],
      ),
    );
  }

  Future<void> _renamePlantel(Plantel plantel) async {
    final name = await promptForText(
      context,
      title: 'Renombrar plantel',
      labelText: 'Nombre',
      initialValue: plantel.name,
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    final scope = AppScope.of(context);
    scope.updateClub(
      scope.club.copyWith(
        planteles: [
          for (final item in scope.club.planteles)
            if (item.id == plantel.id)
              item.copyWith(name: name.trim())
            else
              item,
        ],
      ),
    );
  }

  void _deletePlantel(String id) {
    final scope = AppScope.of(context);
    scope.updateClub(removePlantel(scope.club, id));
  }

  List<String> _lines(String value) {
    return value
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  void _saveMethodology() {
    final scope = AppScope.of(context);
    final methodology = scope.club.methodology.copyWith(
      playingStyle: _playingStyleController.text.trim(),
      offensivePrinciples: _lines(_offensiveController.text),
      defensivePrinciples: _lines(_defensiveController.text),
      ageObjectives: _lines(_ageObjectivesController.text),
      evaluationCriteria: _lines(_evaluationController.text),
    );
    scope.updateClub(
      scope.club.copyWith(
        methodology: methodology,
      ),
    );
    unawaited(
      OfflineMutationService.instance.saveTacticalDataOfflineFirst(
        type: 'methodology',
        title: 'Forma de jugar',
        categoryId: scope.selectedCategoryId,
        content: {'methodology': methodology.toJson()},
      ),
    );
  }

  void _refreshMembers() {
    setState(() {
      _membersFuture = ClubAccessService.loadClubMembers();
    });
  }

  Future<List<ClubCollaborator>> _collaboratorsFor(String clubId) {
    if (_collaboratorsClubId != clubId || _collaboratorsFuture == null) {
      _collaboratorsClubId = clubId;
      _collaboratorsFuture = ClubCollaboratorsService.list(clubId);
    }
    return _collaboratorsFuture!;
  }

  void _refreshCollaborators() {
    final clubId = AppScope.of(context).fullClub.id;
    setState(() {
      _collaboratorsClubId = clubId;
      _collaboratorsFuture = ClubCollaboratorsService.list(clubId);
    });
  }

  Future<void> _inviteCollaborator() async {
    final club = AppScope.of(context).fullClub;
    final emailController = TextEditingController();
    var role = clubCollaboratorRoles.first;
    final result = await showDialog<({String email, String role})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Invitar colaborador'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  items: clubCollaboratorRoles
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_collaboratorRoleName(value)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => role = value);
                  },
                  decoration: const InputDecoration(labelText: 'Rol'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final email = emailController.text.trim();
                if (email.isEmpty) return;
                Navigator.pop(context, (email: email, role: role));
              },
              child: const Text('Invitar'),
            ),
          ],
        ),
      ),
    );
    emailController.dispose();
    if (result == null || !mounted) return;
    try {
      await ClubCollaboratorsService.invite(
        clubId: club.id,
        email: result.email,
        role: result.role,
      );
      if (!mounted) return;
      _refreshCollaborators();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Colaborador invitado.')));
    } on ClubCollaboratorsException catch (error) {
      if (!mounted) return;
      final message =
          error.code == 'no_account' ||
              error.message.toLowerCase().contains('no tiene una cuenta')
          ? 'Esa persona todavía no tiene cuenta en fobal, pedile que se registre primero.'
          : error.message;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _revokeCollaborator(ClubCollaborator collaborator) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revocar acceso'),
        content: Text(
          'Se quitará el acceso de ${collaborator.email.isEmpty ? collaborator.fullName : collaborator.email}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revocar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ClubCollaboratorsService.revoke(
        clubId: AppScope.of(context).fullClub.id,
        userId: collaborator.userId,
      );
      if (!mounted) return;
      _refreshCollaborators();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Acceso revocado.')));
    } on ClubCollaboratorsException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _reviewMember(ClubMemberAccess member, bool approve) async {
    final categories = AppScope.of(context).fullClub.categories;
    final selected = member.categoryIds.toSet();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(approve ? 'Aprobar y asignar' : 'Rechazar solicitud'),
          content: SizedBox(
            width: 480,
            child: approve
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Elegí hasta dos categorías. El DT solo verá y editará esas categorías.',
                        style: TextStyle(color: CX.muted, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      ...categories.map(
                        (category) => CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(category.name),
                          value: selected.contains(category.id),
                          onChanged: (checked) {
                            setDialogState(() {
                              if (checked == true && selected.length < 2) {
                                selected.add(category.id);
                              } else if (checked != true) {
                                selected.remove(category.id);
                              }
                            });
                          },
                        ),
                      ),
                      if (selected.length == 2)
                        const Text(
                          'Máximo de dos categorías alcanzado.',
                          style: TextStyle(color: CX.amber, fontSize: 11),
                        ),
                    ],
                  )
                : const Text(
                    'La solicitud dejará de estar pendiente para este club.',
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: approve && selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, selected.toList()),
              child: Text(approve ? 'Aprobar acceso' : 'Rechazar'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    try {
      await ClubAccessService.reviewMembership(
        userId: member.userId,
        approve: approve,
        categoryIds: result,
      );
      if (!mounted) return;
      _refreshMembers();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve ? 'Acceso aprobado para el club.' : 'Solicitud rechazada.',
          ),
        ),
      );
    } on ClubAccessException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo revisar la solicitud.')),
      );
    }
  }

  Future<void> _manageMemberCategories(ClubMemberAccess member) async {
    final categories = AppScope.of(context).fullClub.categories;
    final selected = member.categoryIds.toSet();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Categorías habilitadas'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'El acceso del DT queda limitado a un máximo de dos categorías.',
                  style: TextStyle(color: CX.muted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                ...categories.map(
                  (category) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(category.name),
                    value: selected.contains(category.id),
                    onChanged: (checked) {
                      setDialogState(() {
                        if (checked == true && selected.length < 2) {
                          selected.add(category.id);
                        } else if (checked != true) {
                          selected.remove(category.id);
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, selected.toList()),
              child: const Text('Guardar acceso'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    try {
      await ClubAccessService.updateMembershipCategories(
        userId: member.userId,
        categoryIds: result,
      );
      if (!mounted) return;
      _refreshMembers();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Categorías del DT actualizadas.')),
      );
    } on ClubAccessException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final club = AppScope.of(context).club;
    final fullClub = AppScope.of(context).fullClub;
    final isManualOwner =
        fullClub.isManualClub &&
        AccountIdentityService.readLocalClubId() == fullClub.id;
    final categoryNames = {
      for (final category in club.categories) category.id: category.name,
    };
    final steps = [
      _SetupStep(
        title: 'Datos basicos',
        icon: Icons.shield_outlined,
        completed: club.name.trim().isNotEmpty && club.league.trim().isNotEmpty,
        fields: const ['Nombre del club', 'Liga', 'Escudo', 'Colores'],
      ),
      _SetupStep(
        title: 'Estructura deportiva',
        icon: Icons.account_tree_outlined,
        completed: club.categories.isNotEmpty && club.players.isNotEmpty,
        fields: const [
          'Categorias',
          'Entrenadores',
          'Coordinador',
          'Planteles',
        ],
      ),
      _SetupStep(
        title: 'Metodologia',
        icon: Icons.sports_soccer_outlined,
        completed:
            club.methodology.playingStyle.trim().isNotEmpty &&
            club.methodology.offensivePrinciples.isNotEmpty &&
            club.methodology.defensivePrinciples.isNotEmpty,
        fields: const [
          'Idea de juego',
          'Principios ofensivos',
          'Principios defensivos',
          'Objetivos por edad',
          'Criterios de evaluacion',
        ],
      ),
      if (club.isLudClub || isManualOwner)
        _SetupStep(
          title: 'Usuarios y permisos',
          icon: Icons.admin_panel_settings_outlined,
          completed: SupabaseAuthService.currentSession != null,
          fields: const [
            'Miembros del club',
            'Roles operativos',
            'Estados de acceso',
            'Separacion por club',
          ],
        ),
    ];

    final completed = steps.where((s) => s.completed).length;
    final narrow = MediaQuery.sizeOf(context).width < 700;

    final sections = <Widget>[
      _BasicDataForm(
        nameController: _nameController,
        leagueController: _leagueController,
        headCoachController: _headCoachController,
        assistantCoachController: _assistantCoachController,
        selectedColor: _primaryColor,
        onColor: (color) => setState(() => _primaryColor = color),
        onSave: _saveBasicData,
      ),
      Column(
        children: [
          _CategoryForm(
            nameController: _categoryNameController,
            ageController: _categoryAgeController,
            coachController: _categoryCoachController,
            playersController: _categoryPlayersController,
            focusController: _categoryFocusController,
            scheduleController: _categoryScheduleController,
            onAdd: _addCategory,
          ),
          const SizedBox(height: 12),
          if (club.categories.isEmpty)
            const _EmptyCard('Todavia no hay categorias creadas.')
          else
            ...club.categories.map(
              (category) => _CategorySetupCard(
                category: category,
                onDelete: category.id.startsWith('lud-cat-')
                    ? null
                    : () => _deleteCategory(category.id),
              ),
            ),
          if (club.isManualClub && club.categories.isNotEmpty) ...[
            SizedBox(height: narrow ? 12 : 18),
            PremiumSectionHeader(
              compact: narrow,
              eyebrow: 'SUBGRUPOS',
              title: 'Planteles por categoría',
            ),
            ...club.categories.where((c) => !isLudCategoryId(c.id)).map((
              category,
            ) {
              final planteles = plantelesForCategory(club, category.id);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              category.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Crear plantel',
                            onPressed: () => _addPlantel(category),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                      if (planteles.isEmpty)
                        const Text(
                          'Sin planteles. La categoría trabaja como un único grupo.',
                          style: TextStyle(color: CX.muted),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final plantel in planteles)
                              InputChip(
                                label: Text(plantel.name),
                                onPressed: () => _renamePlantel(plantel),
                                onDeleted: () => _deletePlantel(plantel.id),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            }),
          ],
          SizedBox(height: narrow ? 12 : 18),
          _PlayerForm(
            categories: club.categories,
            selectedCategoryId: _selectedPlayerCategoryId,
            firstNameController: _playerFirstNameController,
            lastNameController: _playerLastNameController,
            ageController: _playerAgeController,
            positionController: _playerPositionController,
            footController: _playerFootController,
            statusController: _playerStatusController,
            statusDetailController: _playerStatusDetailController,
            suspensionController: _playerSuspensionController,
            noteController: _playerNoteController,
            onCategory: (id) => setState(() => _selectedPlayerCategoryId = id),
            onAdd: _addPlayer,
          ),
          const SizedBox(height: 12),
          if (club.players.isEmpty)
            const _EmptyCard('Todavia no hay jugadores cargados.')
          else
            ...club.players.map(
              (player) => _PlayerSetupCard(
                player: player,
                categoryName: categoryNames[player.categoryId] ?? '',
                onDelete: player.id.startsWith('lud-player-')
                    ? null
                    : () => _deletePlayer(player.id),
              ),
            ),
        ],
      ),
      _MethodologyForm(
        playingStyleController: _playingStyleController,
        offensiveController: _offensiveController,
        defensiveController: _defensiveController,
        ageObjectivesController: _ageObjectivesController,
        evaluationController: _evaluationController,
        onSave: _saveMethodology,
      ),
      if (club.isLudClub)
        _RealClubAccessPanel(
          future: _membersFuture,
          onRefresh: _refreshMembers,
          onReview: _reviewMember,
          onManage: _manageMemberCategories,
        ),
      if (isManualOwner)
        _ManualCollaboratorsPanel(
          future: _collaboratorsFor(fullClub.id),
          onRefresh: _refreshCollaborators,
          onInvite: _inviteCollaborator,
          onRevoke: _revokeCollaborator,
        ),
    ];

    if (_sectionIndex >= sections.length) _sectionIndex = sections.length - 1;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Configuracion del club'),
            Text(
              'Base operativa de fobal',
              style: TextStyle(
                color: CX.faint,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                narrow ? 12 : 18,
                narrow ? 6 : 8,
                narrow ? 12 : 18,
                narrow ? 20 : 28,
              ),
              children: [
                _Header(
                  clubName: club.name,
                  completed: completed,
                  total: steps.length,
                  onReset: SupabaseAuthService.currentSession == null
                      ? _resetDemo
                      : null,
                ),
                SizedBox(height: narrow ? 10 : 14),
                _SetupNavigation(
                  steps: steps,
                  selectedIndex: _sectionIndex,
                  onSelected: (index) => setState(() => _sectionIndex = index),
                ),
                SizedBox(height: narrow ? 11 : 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: KeyedSubtree(
                    key: ValueKey(_sectionIndex),
                    child: sections[_sectionIndex],
                  ),
                ),
                SizedBox(height: narrow ? 11 : 16),
                _ClubDataCard(
                  onExport: () => ClubBackupService.downloadJson(
                    AppScope.of(context).fullClub,
                  ),
                  onImport: () => importClubFromFile(context),
                ),
                if (SupabaseAuthService.currentSession != null &&
                    !AppScope.of(context).fullClub.isManualClub) ...[
                  SizedBox(height: narrow ? 11 : 16),
                  _LeaveClubCard(clubName: club.name, onLeave: _leaveClub),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _leaveClub() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dejar este club'),
        content: Text(
          'Tu cuenta deja de pertenecer a ${AppScope.of(context).fullClub.name}. '
          'Si sos el único director, el club queda libre para que otra cuenta '
          'lo reclame. Después vas a poder elegir otro club.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: CX.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Dejar club'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final membership = await ClubAccessService.activeMembership();
      final clubId = membership?.clubId ?? AppScope.of(context).fullClub.id;
      await ClubAccessService.leaveClub(clubId);
      navigator.pushReplacementNamed('/access');
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error.toString().contains('last_admin_has_members')
                ? 'Sos el único director y el club tiene otros miembros. '
                      'Designá a otro director o quitá a los miembros antes '
                      'de dejarlo.'
                : 'No pudimos dejar el club. Probá de nuevo.',
          ),
        ),
      );
    }
  }
}

class _LeaveClubCard extends StatelessWidget {
  final String clubName;
  final VoidCallback onLeave;

  const _LeaveClubCard({required this.clubName, required this.onLeave});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: CX.auxiliaryDecoration(),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tu cuenta en este club',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  'Si te cambiás de equipo, dejá $clubName para poder unirte a otro.',
                  style: const TextStyle(
                    color: CX.muted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(onPressed: onLeave, child: const Text('Dejar club')),
        ],
      ),
    );
  }
}

class _BasicDataForm extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController leagueController;
  final TextEditingController headCoachController;
  final TextEditingController assistantCoachController;
  final Color selectedColor;
  final ValueChanged<Color> onColor;
  final VoidCallback onSave;

  const _BasicDataForm({
    required this.nameController,
    required this.leagueController,
    required this.headCoachController,
    required this.assistantCoachController,
    required this.selectedColor,
    required this.onColor,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    const colors = [
      CX.green,
      CX.blue,
      CX.amber,
      CX.red,
      Color(0xFFFF8A65),
      Color(0xFFE879F9),
      Color(0xFFFFFFFF),
      Color(0xFF111827),
      Color(0xFF22C55E),
      Color(0xFF2563EB),
      Color(0xFFFACC15),
    ];

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: CX.auxiliaryDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Datos basicos',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Nombre del club'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: leagueController,
            decoration: const InputDecoration(labelText: 'Liga'),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;
              final fields = [
                TextFormField(
                  controller: headCoachController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del entrenador',
                  ),
                ),
                TextFormField(
                  controller: assistantCoachController,
                  decoration: const InputDecoration(
                    labelText: 'Ayudante tecnico (opcional)',
                  ),
                ),
              ];
              if (compact) {
                return Column(
                  children: [fields[0], const SizedBox(height: 10), fields[1]],
                );
              }
              return Row(
                children: [
                  Expanded(child: fields[0]),
                  const SizedBox(width: 10),
                  Expanded(child: fields[1]),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Text(
            'Color principal',
            style: TextStyle(color: CX.muted, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Row(
            children: colors
                .map(
                  (color) => Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: InkWell(
                      onTap: () => onColor(color),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selectedColor == color
                                ? CX.white
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Guardar datos basicos'),
          ),
        ],
      ),
    );
  }
}

class _CategoryForm extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController ageController;
  final TextEditingController coachController;
  final TextEditingController playersController;
  final TextEditingController focusController;
  final TextEditingController scheduleController;
  final VoidCallback onAdd;

  const _CategoryForm({
    required this.nameController,
    required this.ageController,
    required this.coachController,
    required this.playersController,
    required this.focusController,
    required this.scheduleController,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: CX.auxiliaryDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Categoría complementaria',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            'Para estructuras que todavia no existen en la liga. Se guarda solo en fobal.',
            style: TextStyle(color: CX.muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          TextFormField(
            controller: ageController,
            decoration: const InputDecoration(labelText: 'Edad o generacion'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: coachController,
            decoration: const InputDecoration(labelText: 'Entrenador'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: playersController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Cantidad de jugadores',
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: focusController,
            decoration: const InputDecoration(labelText: 'Foco actual'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: scheduleController,
            decoration: const InputDecoration(
              labelText: 'Dias y horarios de practica',
              hintText: 'Ej: martes y jueves 20:30, sabado 10:00',
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Agregar registro interno'),
          ),
        ],
      ),
    );
  }
}

class _CategorySetupCard extends StatelessWidget {
  final CategorySquad category;
  final VoidCallback? onDelete;

  const _CategorySetupCard({required this.category, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final fromLud = category.id.startsWith('lud-cat-');
    final details = [
      category.sport,
      category.ageGroup,
      category.coachName,
      '${category.playerCount} jugadores',
    ].where((v) => v.trim().isNotEmpty).join(' - ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: CX.panelDecoration(
        borderColor: CX.green.withValues(alpha: 0.28),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.groups_outlined, color: CX.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                _SourceLabel(fromLud: fromLud),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    details,
                    style: TextStyle(color: CX.muted, fontSize: 12),
                  ),
                ],
                if (category.currentFocus.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    category.currentFocus,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
                if (category.practiceSchedule.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.schedule, color: CX.green, size: 15),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          category.practiceSchedule,
                          style: const TextStyle(
                            color: CX.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              tooltip: 'Eliminar registro interno',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              color: CX.faint,
            )
          else
            const Tooltip(
              message: 'Dato oficial protegido; se actualiza desde la liga',
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.lock_outline, size: 19, color: CX.faint),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlayerForm extends StatelessWidget {
  final List<CategorySquad> categories;
  final String? selectedCategoryId;
  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final TextEditingController ageController;
  final TextEditingController positionController;
  final TextEditingController footController;
  final TextEditingController statusController;
  final TextEditingController statusDetailController;
  final TextEditingController suspensionController;
  final TextEditingController noteController;
  final ValueChanged<String?> onCategory;
  final VoidCallback onAdd;

  const _PlayerForm({
    required this.categories,
    required this.selectedCategoryId,
    required this.firstNameController,
    required this.lastNameController,
    required this.ageController,
    required this.positionController,
    required this.footController,
    required this.statusController,
    required this.statusDetailController,
    required this.suspensionController,
    required this.noteController,
    required this.onCategory,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: CX.auxiliaryDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Jugador complementario',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            'Usa esta alta solo cuando el jugador aun no figure en la liga.',
            style: TextStyle(color: CX.muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: categories.any((c) => c.id == selectedCategoryId)
                ? selectedCategoryId
                : null,
            items: categories
                .map(
                  (category) => DropdownMenuItem(
                    value: category.id,
                    child: Text(category.name),
                  ),
                )
                .toList(),
            onChanged: categories.isEmpty ? null : onCategory,
            decoration: const InputDecoration(labelText: 'Categoria'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: firstNameController,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: lastNameController,
            decoration: const InputDecoration(labelText: 'Apellido'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: ageController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Edad'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: positionController,
            decoration: const InputDecoration(labelText: 'Posicion'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: footController,
            decoration: const InputDecoration(labelText: 'Pie habil'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: statusController,
            decoration: const InputDecoration(labelText: 'Estado'),
          ),
          const SizedBox(height: 8),
          QuickValueRow(
            values: const [
              'Disponible',
              'Tocado',
              'Lesionado',
              'Sancionado',
              'Ausente avisado',
            ],
            onSelected: (value) => statusController.text = value,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: suspensionController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Fechas de suspension',
              hintText: 'Solo si corresponde',
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: statusDetailController,
            decoration: const InputDecoration(
              labelText: 'Detalle de disponibilidad',
              hintText: 'Ej: esguince leve, viaje, examen, vuelve el martes',
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: noteController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notas',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: categories.isEmpty ? null : onAdd,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('Agregar registro interno'),
          ),
        ],
      ),
    );
  }
}

class _PlayerSetupCard extends StatelessWidget {
  final Player player;
  final String categoryName;
  final VoidCallback? onDelete;

  const _PlayerSetupCard({
    required this.player,
    required this.categoryName,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      categoryName,
      player.position,
      player.age == 0 ? '' : '${player.age} anos',
      player.availabilityLabel,
    ].where((v) => v.trim().isNotEmpty).join(' - ');

    return _RemovableCard(
      icon: Icons.person_outline,
      title: player.fullName.trim(),
      subtitle: subtitle,
      onDelete: onDelete,
      fromLud: player.id.startsWith('lud-player-'),
    );
  }
}

class _MethodologyForm extends StatelessWidget {
  final TextEditingController playingStyleController;
  final TextEditingController offensiveController;
  final TextEditingController defensiveController;
  final TextEditingController ageObjectivesController;
  final TextEditingController evaluationController;
  final VoidCallback onSave;

  const _MethodologyForm({
    required this.playingStyleController,
    required this.offensiveController,
    required this.defensiveController,
    required this.ageObjectivesController,
    required this.evaluationController,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: CX.auxiliaryDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Metodologia deportiva',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: playingStyleController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Idea de juego',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          _MultiLineField(
            controller: offensiveController,
            label: 'Principios ofensivos',
          ),
          const SizedBox(height: 10),
          _MultiLineField(
            controller: defensiveController,
            label: 'Principios defensivos',
          ),
          const SizedBox(height: 10),
          _MultiLineField(
            controller: ageObjectivesController,
            label: 'Objetivos por edad',
          ),
          const SizedBox(height: 10),
          _MultiLineField(
            controller: evaluationController,
            label: 'Criterios de evaluacion',
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Guardar metodologia'),
          ),
        ],
      ),
    );
  }
}

class _ManualCollaboratorsPanel extends StatelessWidget {
  final Future<List<ClubCollaborator>> future;
  final VoidCallback onRefresh;
  final VoidCallback onInvite;
  final ValueChanged<ClubCollaborator> onRevoke;

  const _ManualCollaboratorsPanel({
    required this.future,
    required this.onRefresh,
    required this.onInvite,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ClubCollaborator>>(
      future: future,
      builder: (context, snapshot) {
        final collaborators = snapshot.data ?? const <ClubCollaborator>[];
        return Container(
          padding: const EdgeInsets.all(15),
          decoration: CX.auxiliaryDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.group_add_outlined, color: CX.green),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Text(
                      'Colaboradores',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Actualizar colaboradores',
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    onPressed: onInvite,
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Invitar'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Sumá usuarios registrados para trabajar sobre este club manual sin mezclarlo con clubes de Liga Universitaria.',
                style: TextStyle(color: CX.muted, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 14),
              if (snapshot.connectionState == ConnectionState.waiting)
                const LinearProgressIndicator(minHeight: 2)
              else if (snapshot.hasError)
                const _EmptyCard(
                  'No pudimos cargar colaboradores. Probá de nuevo.',
                )
              else if (collaborators.isEmpty)
                const _EmptyCard('Todavía no invitaste colaboradores.')
              else
                ...collaborators.map(
                  (collaborator) => _CollaboratorTile(
                    collaborator: collaborator,
                    onRevoke: () => onRevoke(collaborator),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CollaboratorTile extends StatelessWidget {
  final ClubCollaborator collaborator;
  final VoidCallback onRevoke;

  const _CollaboratorTile({required this.collaborator, required this.onRevoke});

  @override
  Widget build(BuildContext context) {
    final title = collaborator.fullName.trim().isNotEmpty
        ? collaborator.fullName.trim()
        : collaborator.email;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.person_outline, color: CX.green),
      title: Text(
        title.isEmpty ? 'Colaborador' : title,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        [
          if (collaborator.email.trim().isNotEmpty) collaborator.email.trim(),
          _collaboratorRoleName(collaborator.role),
        ].join(' / '),
        style: const TextStyle(color: CX.muted, fontSize: 12),
      ),
      trailing: IconButton(
        tooltip: 'Revocar acceso',
        onPressed: onRevoke,
        icon: const Icon(Icons.person_remove_outlined, color: CX.red),
      ),
    );
  }
}

class _RealClubAccessPanel extends StatelessWidget {
  final Future<List<ClubMemberAccess>> future;
  final VoidCallback onRefresh;
  final void Function(ClubMemberAccess member, bool approve) onReview;
  final ValueChanged<ClubMemberAccess> onManage;

  const _RealClubAccessPanel({
    required this.future,
    required this.onRefresh,
    required this.onReview,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ClubMemberAccess>>(
      future: future,
      builder: (context, snapshot) {
        final members = snapshot.data ?? const <ClubMemberAccess>[];
        return Container(
          padding: const EdgeInsets.all(15),
          decoration: CX.auxiliaryDecoration(),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.admin_panel_settings_outlined,
                      color: CX.green,
                    ),
                    const SizedBox(width: 9),
                    const Expanded(
                      child: Text(
                        'Accesos reales del club',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Actualizar accesos',
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Estos son los accesos reales al club. Crear una tarjeta local no concede acceso.',
                  style: TextStyle(color: CX.muted, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 14),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const LinearProgressIndicator(minHeight: 2)
                else if (snapshot.hasError)
                  const _EmptyCard(
                    'No pudimos cargar los accesos. Probá de nuevo.',
                  )
                else if (members.isEmpty)
                  const _EmptyCard('No hay miembros con acceso a este club.')
                else ...[
                  _AccessHealthStrip(members: members),
                  const SizedBox(height: 10),
                  ...members.map(
                    (member) => _RealMemberTile(
                      member,
                      onReview: (approve) => onReview(member, approve),
                      onManage: () => onManage(member),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

String _collaboratorRoleName(String role) => switch (role) {
  'coach' => 'Director tecnico',
  'assistant' => 'Ayudante tecnico',
  'physical_trainer' => 'Preparador fisico',
  'viewer' => 'Solo lectura',
  _ => role,
};

class _AccessHealthStrip extends StatelessWidget {
  final List<ClubMemberAccess> members;

  const _AccessHealthStrip({required this.members});

  @override
  Widget build(BuildContext context) {
    final active = members.where((member) => member.status == 'active').length;
    final pending = members
        .where((member) => member.status == 'pending')
        .length;
    final editors = members
        .where(
          (member) =>
              member.status == 'active' &&
              const {
                'platform_admin',
                'club_admin',
                'coach',
                'assistant',
                'physical_trainer',
              }.contains(member.role),
        )
        .length;
    final viewers = members
        .where((member) => member.status == 'active' && member.role == 'viewer')
        .length;
    final color = pending > 0 ? CX.amber : CX.green;
    final message = pending > 0
        ? '$pending solicitudes pendientes para revisar antes de habilitar datos del club.'
        : 'Acceso separado por club con $active membresias activas.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.security_outlined, color: color, size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _AccessPill('$active activos', CX.green),
              _AccessPill('$editors editan', CX.blue),
              _AccessPill('$viewers lectura', CX.faint),
              if (pending > 0) _AccessPill('$pending pendientes', CX.amber),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccessPill extends StatelessWidget {
  final String label;
  final Color color;

  const _AccessPill(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _RealMemberTile extends StatelessWidget {
  final ClubMemberAccess member;
  final ValueChanged<bool> onReview;
  final VoidCallback onManage;

  const _RealMemberTile(
    this.member, {
    required this.onReview,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    final color = member.status == 'active' ? CX.green : CX.amber;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.person_outline, color: color),
      title: Text(
        member.isCurrentUser ? 'Tu cuenta' : 'Miembro del club',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${_roleName(member.role)} / ${_statusName(member.status)} / ${member.categoryIds.isEmpty ? 'Sin categoría asignada' : '${member.categoryIds.length} categoría(s)'}',
        style: const TextStyle(color: CX.muted, fontSize: 12),
      ),
      trailing: member.status == 'pending'
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Rechazar solicitud',
                  onPressed: () => onReview(false),
                  icon: const Icon(Icons.close, color: CX.red),
                ),
                IconButton(
                  tooltip: 'Aprobar solicitud',
                  onPressed: () => onReview(true),
                  icon: const Icon(Icons.check, color: CX.green),
                ),
              ],
            )
          : member.status == 'active' &&
                !member.isCurrentUser &&
                !const {'platform_admin', 'club_admin'}.contains(member.role)
          ? IconButton(
              tooltip: 'Gestionar categorías',
              onPressed: onManage,
              icon: const Icon(Icons.tune, color: CX.green),
            )
          : Icon(
              member.status == 'active'
                  ? Icons.verified_user_outlined
                  : Icons.block_outlined,
              color: color,
            ),
    );
  }

  String _roleName(String role) => switch (role) {
    'platform_admin' => 'Admin plataforma',
    'club_admin' => 'Admin club',
    'coach' => 'Director tecnico',
    'assistant' => 'Ayudante tecnico',
    'physical_trainer' => 'Preparador fisico',
    'viewer' => 'Solo lectura',
    _ => role,
  };

  String _statusName(String status) => switch (status) {
    'active' => 'Activo',
    'pending' => 'Pendiente',
    'rejected' => 'Rechazado',
    'disabled' => 'Deshabilitado',
    _ => status,
  };
}

class _RemovableCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onDelete;
  final bool fromLud;

  const _RemovableCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onDelete,
    this.fromLud = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: CX.panelDecoration(
        borderColor: CX.green.withValues(alpha: 0.28),
      ),
      child: Row(
        children: [
          Icon(icon, color: CX.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                _SourceLabel(fromLud: fromLud),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: CX.muted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              tooltip: 'Eliminar registro interno',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              color: CX.faint,
            )
          else
            const Tooltip(
              message: 'Dato oficial protegido; se actualiza desde la liga',
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.lock_outline, size: 19, color: CX.faint),
              ),
            ),
        ],
      ),
    );
  }
}

class _SourceLabel extends StatelessWidget {
  final bool fromLud;

  const _SourceLabel({required this.fromLud});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          fromLud ? Icons.verified_outlined : Icons.edit_note_outlined,
          size: 14,
          color: fromLud ? CX.green : CX.muted,
        ),
        const SizedBox(width: 5),
        Text(
          fromLud ? 'Liga · protegido' : 'Registro interno',
          style: TextStyle(
            color: fromLud ? CX.green : CX.muted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _MultiLineField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _MultiLineField({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: 4,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'Uno por linea',
        alignLabelWithHint: true,
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String text;

  const _EmptyCard(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: CX.auxiliaryDecoration(),
      child: Text(
        text,
        style: const TextStyle(color: CX.muted, fontSize: 12.5, height: 1.4),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String clubName;
  final int completed;
  final int total;
  final VoidCallback? onReset;

  const _Header({
    required this.clubName,
    required this.completed,
    required this.total,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 700;
    return Container(
      padding: EdgeInsets.all(narrow ? 12 : 18),
      decoration: CX.auxiliaryDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            clubName == 'Club Demo'
                ? 'Club pendiente de configuracion'
                : clubName,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: narrow ? 6 : 8),
          Text(
            'Completa estos bloques para operar fobal con datos reales del club.',
            style: TextStyle(color: CX.muted, height: 1.35),
          ),
          SizedBox(height: narrow ? 11 : 16),
          LinearProgressIndicator(
            value: total == 0 ? 0 : completed / total,
            minHeight: 8,
            borderRadius: BorderRadius.circular(999),
            backgroundColor: CX.panel2,
            color: CX.green,
          ),
          SizedBox(height: narrow ? 6 : 8),
          Text(
            '$completed de $total bloques completos',
            style: TextStyle(color: CX.faint, fontSize: 12),
          ),
          if (onReset != null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.refresh),
              label: const Text('Restaurar datos locales'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SetupNavigation extends StatelessWidget {
  final List<_SetupStep> steps;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _SetupNavigation({
    required this.steps,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: steps.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final step = steps[index];
          final selected = index == selectedIndex;
          return InkWell(
            onTap: () => onSelected(index),
            borderRadius: BorderRadius.circular(7),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? CX.greenDark : CX.panel,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: selected ? CX.green.withValues(alpha: .45) : CX.line,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    step.completed ? Icons.check_circle : step.icon,
                    color: step.completed || selected ? CX.green : CX.faint,
                    size: 17,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    step.title,
                    style: TextStyle(
                      color: selected ? CX.white : CX.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SetupStep {
  final String title;
  final IconData icon;
  final bool completed;
  final List<String> fields;

  const _SetupStep({
    required this.title,
    required this.icon,
    required this.completed,
    required this.fields,
  });
}

class _ClubDataCard extends StatelessWidget {
  final VoidCallback onExport;
  final VoidCallback onImport;

  const _ClubDataCard({required this.onExport, required this.onImport});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: CX.auxiliaryDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Datos del club',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'Guardá una copia de todo tu espacio (plantel, categorías, sesiones, '
            'metodología, calendario y asistencia) o restaurala desde un archivo. '
            'fobal también conserva respaldos automáticos de tus últimos cambios.',
            style: TextStyle(color: CX.muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 460;
              final export = OutlinedButton.icon(
                onPressed: onExport,
                icon: const Icon(Icons.download_outlined, size: 17),
                label: const Text('Exportar datos'),
              );
              final import = OutlinedButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.upload_outlined, size: 17),
                label: const Text('Importar datos'),
              );
              if (compact) {
                return Column(
                  children: [export, const SizedBox(height: 8), import],
                );
              }
              return Row(
                children: [
                  Expanded(child: export),
                  const SizedBox(width: 10),
                  Expanded(child: import),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import '../services/export_download_service.dart';
import '../services/export_text_service.dart';
import '../services/exercise_library_service.dart';
import '../services/offline_mutation_service.dart';
import '../ui/export_preview_dialog.dart';
import '../ui/ui_kit.dart';
import 'exercise_library_screen.dart';

/// Manual session builder: pick blocks from the exercise library or create
/// them on the fly, reorder, see the total duration add up live, then save
/// the same way a generated session already does.
class SessionBuilderScreen extends StatefulWidget {
  /// Stable id of the calendar event this session prepares for, if any —
  /// same linking pattern the AI planner already uses, so a match prep's
  /// "Entrenamiento vinculado" shows up regardless of which planner built
  /// the session.
  final String calendarEventId;

  const SessionBuilderScreen({super.key, this.calendarEventId = ''});

  @override
  State<SessionBuilderScreen> createState() => _SessionBuilderScreenState();
}

class _SessionBuilderScreenState extends State<SessionBuilderScreen> {
  final _title = TextEditingController();
  final _objective = TextEditingController();
  final _space = TextEditingController();
  int _playerCount = 18;
  String? _categoryId;
  bool _prefilledFromMatchPrep = false;
  DateTime _sessionDate = DateTime.now().add(const Duration(days: 1));
  final List<Exercise> _blocks = [];

  @override
  void dispose() {
    _title.dispose();
    _objective.dispose();
    _space.dispose();
    super.dispose();
  }

  Future<void> _addFromLibrary(CategorySquad category) async {
    final picked = await Navigator.push<Exercise>(
      context,
      MaterialPageRoute(
        builder: (context) => ExerciseLibraryScreen(
          pickMode: true,
          initialCategoryId: category.id,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _blocks.add(
        Exercise.fromBlock(
          picked.toBlock(),
          id: newBuilderBlockId(),
          minutes: picked.duration,
          objective: picked.objective,
          players: picked.players,
          space: picked.space,
          categoryId: picked.categoryId,
          source: picked.source,
        ),
      );
    });
  }

  Future<void> _addNew(CanteraClub club, CategorySquad category) async {
    final result = await showDialog<Exercise>(
      context: context,
      builder: (context) => ExerciseEditDialog(
        categories: club.categories,
        defaultCategoryId: category.id,
        prefill: _matchPrepBlockPrefill(club, category),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _blocks.add(result));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Bloque agregado: ${result.name}'),
        action: SnackBarAction(
          label: 'Guardar en biblioteca',
          onPressed: () {
            final scope = AppScope.of(context);
            final club = scope.club;
            scope.updateClub(
              club.copyWith(
                savedExercises: [
                  result,
                  ...club.savedExercises.where((item) => item.id != result.id),
                ],
              ),
            );
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${result.name} guardado en la biblioteca.'),
              ),
            );
          },
        ),
      ),
    );
  }

  String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Exercise? _matchPrepBlockPrefill(CanteraClub club, CategorySquad category) {
    if (widget.calendarEventId.isEmpty) return null;
    MatchPreparation? prep;
    for (final item in club.matchPreparations) {
      if (item.calendarEventId == widget.calendarEventId &&
          item.categoryId == category.id) {
        prep = item;
        break;
      }
    }
    if (prep == null) return null;
    TrainingSession? linkedSession;
    if (prep.linkedSessionId.isNotEmpty) {
      for (final session in club.sessions) {
        if (session.id == prep.linkedSessionId) {
          linkedSession = session;
          break;
        }
      }
    }
    final objective = [
      if (prep.planObjective.trim().isNotEmpty) prep.planObjective.trim(),
      if (prep.offensiveKeys.trim().isNotEmpty)
        'Claves ofensivas: ${prep.offensiveKeys.trim()}',
      if (prep.defensiveKeys.trim().isNotEmpty)
        'Claves defensivas: ${prep.defensiveKeys.trim()}',
    ].join(' ');
    final players = linkedSession?.playerCount ??
        club.players.where((player) => player.categoryId == category.id).length;
    return Exercise(
      id: '',
      name: '',
      objective: objective,
      space: linkedSession?.space ?? _space.text.trim(),
      players: players,
      categoryId: category.id,
      source: 'manual',
    );
  }

  void _prefillSessionFromMatchPrep(CanteraClub club, CategorySquad category) {
    if (_prefilledFromMatchPrep || widget.calendarEventId.isEmpty) return;
    final prefill = _matchPrepBlockPrefill(club, category);
    if (prefill == null) return;
    _prefilledFromMatchPrep = true;
    if (_objective.text.trim().isEmpty && prefill.objective.trim().isNotEmpty) {
      _objective.text = prefill.objective.trim();
    }
    if (_space.text.trim().isEmpty && prefill.space.trim().isNotEmpty) {
      _space.text = prefill.space.trim();
    }
    if (prefill.players > 0) {
      _playerCount = prefill.players;
    }
  }

  void _removeBlock(int index) {
    final removed = _blocks[index];
    setState(() => _blocks.removeAt(index));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Bloque quitado: ${removed.name}')));
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _blocks.removeAt(oldIndex);
      _blocks.insert(newIndex, item);
    });
  }

  Future<void> _save(CanteraClub club, CategorySquad category) async {
    if (_blocks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agregá al menos un bloque antes de guardar.'),
        ),
      );
      return;
    }
    final scope = AppScope.of(context);
    final title = _title.text.trim().isEmpty
        ? '${category.name} · Sesión manual'
        : _title.text.trim();
    final session = TrainingSession(
      id: 'session-${DateTime.now().millisecondsSinceEpoch}',
      categoryId: category.id,
      title: title,
      objective: _objective.text.trim(),
      duration: totalMinutes(_blocks.map((block) => block.duration)),
      space: _space.text.trim(),
      playerCount: _playerCount,
      generatedByAi: false,
      status: 'planned',
      scheduledDate: _isoDate(_sessionDate),
      blocks: [for (final block in _blocks) block.toBlock()],
      coachCues: const [],
      successIndicators: const [],
    );
    final matchPreparations = widget.calendarEventId.isEmpty
        ? club.matchPreparations
        : [
            for (final prep in club.matchPreparations)
              if (prep.calendarEventId == widget.calendarEventId)
                prep.copyWith(linkedSessionId: session.id)
              else
                prep,
          ];
    scope.updateClub(
      club.copyWith(
        sessions: [
          session,
          ...club.sessions.where((item) => item.id != session.id),
        ],
        matchPreparations: matchPreparations,
      ),
    );
    final writeResult = await OfflineMutationService.instance
        .saveTacticalDataOfflineFirst(
          type: 'session',
          title: session.title,
          content: session.toJson(),
          categoryId: category.id,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          writeResult.synced
              ? 'Sesión guardada para el club: $title'
              : 'Sesión guardada en este dispositivo: $title',
        ),
      ),
    );
    Navigator.pop(context);
  }

  void _shareText(CanteraClub club, CategorySquad category) {
    if (_blocks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agregá al menos un bloque para compartir.'),
        ),
      );
      return;
    }
    final title = _title.text.trim().isEmpty
        ? '${category.name} · Sesión manual'
        : _title.text.trim();
    final content = formatSessionText(
      title: title,
      categoryName: category.name,
      duration: totalMinutes(_blocks.map((block) => block.duration)),
      playerCount: _playerCount,
      space: _space.text.trim(),
      objective: _objective.text.trim(),
      blocks: [
        for (final block in _blocks)
          (
            name: block.name,
            duration: '${block.duration} min',
            description: block.description,
          ),
      ],
    );
    final fileName = buildExportFileName(
      club: club.name,
      category: category.name,
      type: 'sesion-manual',
      extension: 'txt',
    );
    showExportPreviewDialog(
      context,
      title: 'Sesión manual',
      content: content,
      fileName: fileName,
      onDownload: (name, text) {
        ExportDownloadService.downloadText(name, text);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sesión descargada: $name')));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 700;
    final scope = AppScope.of(context);
    final club = scope.club;
    if (club.categories.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Constructor de sesión')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: EmptyStatePanel(
              icon: Icons.account_tree_outlined,
              title: 'Primero cargá una categoría',
              message:
                  'Creá una categoría con jugadores para poder armar '
                  'una sesión manual.',
            ),
          ),
        ),
      );
    }
    final scopedCategoryId = club.categories.any(
      (item) => item.id == scope.selectedCategoryId,
    )
        ? scope.selectedCategoryId
        : null;
    final selectedId = club.categories.any((item) => item.id == _categoryId)
        ? _categoryId
        : scopedCategoryId ?? club.categories.first.id;
    if (_categoryId != selectedId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _categoryId = selectedId);
      });
    }
    final category = club.categories.firstWhere(
      (item) => item.id == selectedId,
    );
    _prefillSessionFromMatchPrep(club, category);
    final totalDuration = totalMinutes(_blocks.map((block) => block.duration));

    return Scaffold(
      appBar: AppBar(title: const Text('Constructor de sesión')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(18, narrow ? 9 : 12, 18, narrow ? 22 : 30),
          children: [
            Container(
              padding: EdgeInsets.all(narrow ? 11 : 14),
              decoration: CX.panelDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedId,
                    decoration: const InputDecoration(labelText: 'Categoría'),
                    items: [
                      for (final item in club.categories)
                        DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                    ],
                    onChanged: (value) => setState(() => _categoryId = value),
                  ),
                  SizedBox(height: narrow ? 8 : 10),
                  TextField(
                    controller: _title,
                    decoration: const InputDecoration(
                      labelText: 'Título de la sesión',
                    ),
                  ),
                  SizedBox(height: narrow ? 8 : 10),
                  TextField(
                    controller: _objective,
                    decoration: const InputDecoration(labelText: 'Objetivo'),
                  ),
                  SizedBox(height: narrow ? 8 : 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () async {
                      final selected = await showDatePicker(
                        context: context,
                        initialDate: _sessionDate,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 1),
                        ),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (selected != null) {
                        setState(() => _sessionDate = selected);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Fecha',
                        prefixIcon: Icon(Icons.calendar_month_outlined),
                        suffixIcon: Icon(
                          Icons.edit_calendar_outlined,
                          size: 19,
                        ),
                      ),
                      child: Text(
                        '${_sessionDate.day.toString().padLeft(2, '0')}/'
                        '${_sessionDate.month.toString().padLeft(2, '0')}/'
                        '${_sessionDate.year}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  SizedBox(height: narrow ? 8 : 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _space,
                          decoration: const InputDecoration(
                            labelText: 'Espacio',
                          ),
                        ),
                      ),
                      SizedBox(width: narrow ? 8 : 10),
                      Expanded(
                        child: TextFormField(
                          initialValue: '$_playerCount',
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Jugadores',
                          ),
                          onChanged: (value) => _playerCount =
                              int.tryParse(value) ?? _playerCount,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: narrow ? 11 : 16),
            Row(
              children: [
                Expanded(
                  child: PremiumSectionHeader(
                    eyebrow: 'Bloques',
                    title: _blocks.isEmpty
                        ? 'Sin bloques todavía'
                        : '${_blocks.length} bloque${_blocks.length == 1 ? '' : 's'} · $totalDuration min en total',
                    compact: narrow,
                  ),
                ),
              ],
            ),
            if (_blocks.isEmpty)
              const EmptyStatePanel(
                icon: Icons.view_agenda_outlined,
                title: 'Armá la sesión bloque por bloque',
                message:
                    'Sumá ejercicios guardados de tu biblioteca o creá '
                    'uno nuevo. La duración total se calcula sola.',
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _blocks.length,
                onReorder: _reorder,
                itemBuilder: (context, index) {
                  final block = _blocks[index];
                  return _BuilderBlockTile(
                    key: ValueKey(block.id),
                    index: index,
                    exercise: block,
                    onRemove: () => _removeBlock(index),
                    compact: narrow,
                  );
                },
              ),
            SizedBox(height: narrow ? 7 : 10),
            ActionStrip(
              actions: [
                ActionSpec(
                  label: 'Desde la biblioteca',
                  icon: Icons.library_add_outlined,
                  onTap: (_) => _addFromLibrary(category),
                ),
                ActionSpec(
                  label: 'Bloque nuevo',
                  icon: Icons.add_circle_outline,
                  onTap: (_) => _addNew(club, category),
                ),
              ],
            ),
            SizedBox(height: narrow ? 12 : 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 190,
                  child: ElevatedButton.icon(
                    onPressed: () => _save(club, category),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Guardar sesión'),
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: OutlinedButton.icon(
                    onPressed: () => _shareText(club, category),
                    icon: const Icon(Icons.notes_outlined),
                    label: const Text('Compartir texto'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BuilderBlockTile extends StatelessWidget {
  final int index;
  final Exercise exercise;
  final VoidCallback onRemove;
  final bool compact;

  const _BuilderBlockTile({
    super.key,
    required this.index,
    required this.exercise,
    required this.onRemove,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    const accent = CX.green;
    final details = [
      if (exercise.duration > 0) '${exercise.duration} min',
      if (exercise.players > 0) '${exercise.players} jugadores',
      if (exercise.space.trim().isNotEmpty) exercise.space.trim(),
      if (exercise.objective.trim().isNotEmpty) exercise.objective.trim(),
    ].join(' · ');
    final description = exercise.description.trim();
    return Container(
      margin: EdgeInsets.only(bottom: compact ? 7 : 10),
      decoration: CX.panelDecoration(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16,
            vertical: compact ? 10 : 13,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: compact ? 32 : 38,
                height: compact ? 32 : 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(compact ? 9 : 11),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.fitness_center,
                      size: compact ? 16 : 19,
                      color: accent,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: compact ? 10 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        details,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: CX.muted, fontSize: 12.5),
                      ),
                    ],
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CX.faint,
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: compact ? 6 : 8),
              IconButton(
                tooltip: 'Quitar',
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 18, color: CX.faint),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 9),
                child: Icon(Icons.drag_handle, color: CX.faint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

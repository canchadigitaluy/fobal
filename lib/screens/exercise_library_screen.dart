import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import '../services/exercise_library_service.dart';
import '../ui/exercise_animation_preview.dart';
import '../ui/ui_kit.dart';

/// Club-wide exercise library: browse/filter, create/edit by hand, capture
/// one from a generated session block, or — in [pickMode] — pick one to
/// drop into the manual session builder.
class ExerciseLibraryScreen extends StatefulWidget {
  final bool pickMode;
  final String? initialCategoryId;

  const ExerciseLibraryScreen({
    super.key,
    this.pickMode = false,
    this.initialCategoryId,
  });

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  final _search = TextEditingController();
  String _categoryId = '';
  String _space = '';
  String _intensity = '';
  ({int? min, int? max}) _playersRange = (min: null, max: null);

  @override
  void initState() {
    super.initState();
    _categoryId = widget.initialCategoryId ?? '';
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _createOrEdit(
    CanteraClub club, {
    Exercise? existing,
  }) async {
    final result = await showDialog<Exercise>(
      context: context,
      builder: (context) => ExerciseEditDialog(
        existing: existing,
        categories: club.categories,
        defaultCategoryId: _categoryId,
      ),
    );
    if (result == null || !mounted) return;
    final scope = AppScope.of(context);
    final libraryWithoutSelf =
        club.savedExercises.where((item) => item.id != result.id).toList();
    final dedup = findExerciseDuplicate(
      library: libraryWithoutSelf,
      name: result.name,
      duration: result.duration,
      description: result.description,
    );
    if (dedup == ExerciseDedupResult.exactMatch) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ya existe un ejercicio igual en la biblioteca.'),
        ),
      );
      return;
    }
    if (dedup == ExerciseDedupResult.nameMatch) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ejercicio parecido'),
          content: Text(
            'Ya tenés un ejercicio guardado con el nombre "${result.name}" '
            'pero con otros datos. ¿Guardar este de todos modos?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Guardar de todos modos'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    scope.updateClub(
      club.copyWith(savedExercises: [result, ...libraryWithoutSelf]),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          existing == null
              ? 'Ejercicio guardado en la biblioteca.'
              : 'Ejercicio actualizado.',
        ),
      ),
    );
  }

  Future<void> _delete(CanteraClub club, Exercise exercise) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar ejercicio'),
        content: Text(
          'Vas a borrar "${exercise.name}" de la biblioteca. Las sesiones '
          'que ya lo usan no se modifican. No se puede deshacer.',
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
    if (confirmed != true || !mounted) return;
    final scope = AppScope.of(context);
    scope.updateClub(
      club.copyWith(
        savedExercises:
            club.savedExercises.where((item) => item.id != exercise.id).toList(),
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Borrado: ${exercise.name}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final club = scope.club;
    final canEdit = scope.role != UserRole.viewer;
    final spaces = {
      for (final exercise in club.savedExercises)
        if (exercise.space.trim().isNotEmpty) exercise.space.trim(),
    }.toList()
      ..sort();

    final filtered = filterExercises(
      club.savedExercises,
      categoryId: _categoryId,
      query: _search.text,
      space: _space,
      intensity: _intensity,
      minPlayers: _playersRange.min,
      maxPlayers: _playersRange.max,
    )..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pickMode ? 'Elegir ejercicio' : 'Biblioteca de ejercicios'),
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _createOrEdit(club),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo ejercicio'),
            )
          : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 90),
          children: [
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Buscar',
                hintText: 'Nombre, objetivo o descripción',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FilterDropdown(
                  label: 'Categoría',
                  value: _categoryId,
                  items: [
                    const ('', 'Todas'),
                    for (final category in club.categories)
                      (category.id, category.name),
                  ],
                  onChanged: (value) => setState(() => _categoryId = value),
                ),
                _FilterDropdown(
                  label: 'Espacio',
                  value: _space,
                  items: [
                    const ('', 'Cualquiera'),
                    for (final space in spaces) (space, space),
                  ],
                  onChanged: (value) => setState(() => _space = value),
                ),
                _FilterDropdown(
                  label: 'Intensidad',
                  value: _intensity,
                  items: const [
                    ('', 'Cualquiera'),
                    ('baja', 'Baja'),
                    ('media', 'Media'),
                    ('alta', 'Alta'),
                  ],
                  onChanged: (value) => setState(() => _intensity = value),
                ),
                _FilterDropdown(
                  label: 'Jugadores',
                  value: switch (_playersRange) {
                    (min: null, max: null) => '',
                    (min: 0, max: 8) => 'hasta8',
                    (min: 9, max: 14) => '9a14',
                    (min: 15, max: null) => '15mas',
                    _ => '',
                  },
                  items: const [
                    ('', 'Cualquiera'),
                    ('hasta8', 'Hasta 8'),
                    ('9a14', '9 a 14'),
                    ('15mas', '15 o más'),
                  ],
                  onChanged: (value) => setState(() {
                    _playersRange = switch (value) {
                      'hasta8' => (min: 0, max: 8),
                      '9a14' => (min: 9, max: 14),
                      '15mas' => (min: 15, max: null),
                      _ => (min: null, max: null),
                    };
                  }),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (club.savedExercises.isEmpty)
              EmptyStatePanel(
                icon: Icons.auto_awesome_motion_outlined,
                title: 'Todavía no hay ejercicios guardados',
                message: 'Guardá los bloques de una sesión generada o creá '
                    'uno a mano: la próxima vez lo armás en segundos.',
                primaryLabel: canEdit ? 'Crear el primero' : null,
                onPrimary: canEdit ? () => _createOrEdit(club) : null,
              )
            else if (filtered.isEmpty)
              const EmptyStatePanel(
                icon: Icons.filter_alt_off_outlined,
                title: 'Ningún ejercicio coincide con estos filtros',
                message: 'Probá una búsqueda más amplia o limpiá algún filtro.',
              )
            else
              for (final exercise in filtered)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ExerciseCard(
                    exercise: exercise,
                    pickMode: widget.pickMode,
                    canEdit: canEdit,
                    onTap: widget.pickMode
                        ? () => Navigator.pop(context, exercise)
                        : (canEdit ? () => _createOrEdit(club, existing: exercise) : null),
                    onEdit: canEdit ? () => _createOrEdit(club, existing: exercise) : null,
                    onDelete: canEdit ? () => _delete(club, exercise) : null,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<(String, String)> items;
  final ValueChanged<String> onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final safeValue = items.any((item) => item.$1 == value) ? value : '';
    return SizedBox(
      width: 168,
      child: DropdownButtonFormField<String>(
        initialValue: safeValue,
        isDense: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final item in items)
            DropdownMenuItem(value: item.$1, child: Text(item.$2)),
        ],
        onChanged: (next) => onChanged(next ?? ''),
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  final Exercise exercise;
  final bool pickMode;
  final bool canEdit;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _ExerciseCard({
    required this.exercise,
    required this.pickMode,
    required this.canEdit,
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: CX.panelDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercise.name.trim().isEmpty ? 'Sin nombre' : exercise.name,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      if (exercise.objective.trim().isNotEmpty)
                        Text(
                          exercise.objective,
                          style: const TextStyle(color: CX.muted, fontSize: 11.5),
                        ),
                    ],
                  ),
                ),
                if (pickMode)
                  const Icon(Icons.add_circle_outline, color: CX.green)
                else ...[
                  if (onEdit != null)
                    IconButton(
                      tooltip: 'Editar',
                      visualDensity: VisualDensity.compact,
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18, color: CX.muted),
                    ),
                  if (onDelete != null)
                    IconButton(
                      tooltip: 'Borrar',
                      visualDensity: VisualDensity.compact,
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 18, color: CX.red),
                    ),
                ],
              ],
            ),
            if (exercise.description.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                exercise.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: CX.muted, fontSize: 12, height: 1.35),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (exercise.duration > 0)
                  _tag(Icons.schedule, '${exercise.duration} min'),
                if (exercise.players > 0)
                  _tag(Icons.groups_2_outlined, '${exercise.players} jug'),
                if (exercise.space.trim().isNotEmpty)
                  _tag(Icons.crop_free, exercise.space),
                if (exercise.intensity.trim().isNotEmpty)
                  _tag(Icons.bolt_outlined, exercise.intensity),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: CX.panel2,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: CX.muted),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

/// Reused by the session builder too, so a block created on the fly can be
/// captured with the exact same fields/validation as a library exercise.
class ExerciseEditDialog extends StatefulWidget {
  final Exercise? existing;
  final List<CategorySquad> categories;
  final String defaultCategoryId;

  const ExerciseEditDialog({
    super.key,
    this.existing,
    required this.categories,
    required this.defaultCategoryId,
  });

  @override
  State<ExerciseEditDialog> createState() => _ExerciseEditDialogState();
}

class _ExerciseEditDialogState extends State<ExerciseEditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _objective;
  late final TextEditingController _space;
  late final TextEditingController _players;
  late final TextEditingController _duration;
  late final TextEditingController _intensity;
  late final TextEditingController _coachingPoints;
  late final TextEditingController _constraints;
  late final TextEditingController _successMetric;
  late String _categoryId;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _objective = TextEditingController(text: e?.objective ?? '');
    _space = TextEditingController(text: e?.space ?? '');
    _players = TextEditingController(text: e != null && e.players > 0 ? '${e.players}' : '');
    _duration = TextEditingController(text: e != null && e.duration > 0 ? '${e.duration}' : '');
    _intensity = TextEditingController(text: e?.intensity ?? '');
    _coachingPoints = TextEditingController(text: (e?.coachingPoints ?? const []).join('\n'));
    _constraints = TextEditingController(text: (e?.constraints ?? const []).join('\n'));
    _successMetric = TextEditingController(text: e?.successMetric ?? '');
    _categoryId = e?.categoryId ?? widget.defaultCategoryId;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _objective.dispose();
    _space.dispose();
    _players.dispose();
    _duration.dispose();
    _intensity.dispose();
    _coachingPoints.dispose();
    _constraints.dispose();
    _successMetric.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Ponele un nombre al ejercicio.');
      return;
    }
    final existing = widget.existing;
    final result = Exercise(
      id: existing?.id ?? newExerciseId(),
      name: name,
      description: _description.text.trim(),
      objective: _objective.text.trim(),
      space: _space.text.trim(),
      players: int.tryParse(_players.text.trim()) ?? 0,
      duration: int.tryParse(_duration.text.trim()) ?? 0,
      intensity: _intensity.text.trim(),
      coachingPoints: _lines(_coachingPoints.text),
      constraints: _lines(_constraints.text),
      successMetric: _successMetric.text.trim(),
      categoryId: _categoryId,
      source: existing?.source ?? 'manual',
      createdAt: existing?.createdAt ?? DateTime.now().toUtc().toIso8601String(),
      animationScene: existing?.animationScene,
    );
    Navigator.pop(context, result);
  }

  List<String> _lines(String text) => text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    final scene = widget.existing?.animationScene;
    return AlertDialog(
      title: Text(widget.existing == null ? 'Nuevo ejercicio' : 'Editar ejercicio'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _description,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Descripción'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _objective,
                      decoration: const InputDecoration(labelText: 'Objetivo'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _intensity,
                      decoration: const InputDecoration(
                        labelText: 'Intensidad',
                        hintText: 'Baja / Media / Alta',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              QuickValueRow(
                values: const ['Baja', 'Media', 'Alta'],
                onSelected: (value) => setState(() => _intensity.text = value),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _space,
                      decoration: const InputDecoration(labelText: 'Espacio'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _players,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Jugadores'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _duration,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Duración (min)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: widget.categories.any((c) => c.id == _categoryId)
                    ? _categoryId
                    : '',
                decoration: const InputDecoration(labelText: 'Categoría'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Todas (compartido)')),
                  for (final category in widget.categories)
                    DropdownMenuItem(value: category.id, child: Text(category.name)),
                ],
                onChanged: (value) => setState(() => _categoryId = value ?? ''),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _coachingPoints,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Consignas (una por línea)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _constraints,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reglas / condiciones (una por línea)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _successMetric,
                decoration: const InputDecoration(labelText: 'Indicador de éxito'),
              ),
              if (scene != null && scene.hasContent) ...[
                const SizedBox(height: 14),
                ExerciseAnimationPreview(scene: scene, title: _name.text),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: CX.red, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

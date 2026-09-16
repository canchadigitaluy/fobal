import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import 'asistencia_screen.dart';
import 'cuota_screen.dart';
import 'perfil_screen.dart';
import 'reservas_screen.dart';

class TacticaScreen extends StatefulWidget {
  const TacticaScreen({super.key});

  @override
  State<TacticaScreen> createState() => TacticaScreenState();
}

class TacticaScreenState extends State<TacticaScreen> {
  int _section = 0;
  String? _plannerCategoryId;

  void selectSection(int index) {
    final external = _isExternal(context);
    final max = external ? 2 : 3;
    final next = index.clamp(0, max);
    if (next == _section) return;
    setState(() => _section = next);
  }

  bool _isExternal(BuildContext context) =>
      AppScope.of(context).fullClub.isManualClub;

  bool _isPlannerSection(int selectedSection, bool external) =>
      selectedSection == (external ? 1 : 2);

  String? _effectivePlannerCategoryId(
    List<CategorySquad> categories,
    String? scopeSelectedId,
  ) {
    if (categories.any((item) => item.id == _plannerCategoryId)) {
      return _plannerCategoryId;
    }
    if (categories.any((item) => item.id == scopeSelectedId)) {
      return scopeSelectedId;
    }
    return categories.isEmpty ? null : categories.first.id;
  }

  void _selectPlannerCategory(String? categoryId) {
    final scope = AppScope.of(context);
    if (categoryId != null &&
        !scope.fullClub.categories.any((item) => item.id == categoryId)) {
      return;
    }
    if (categoryId != scope.selectedCategoryId) {
      scope.selectCategory(categoryId);
    }
    if (categoryId == _plannerCategoryId) return;
    setState(() => _plannerCategoryId = categoryId);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final external = _isExternal(context);
    final selectedSection = _section.clamp(0, external ? 2 : 3);
    final categories = scope.fullClub.categories;
    final planning = _isPlannerSection(selectedSection, external);
    final plannerCategoryId = _effectivePlannerCategoryId(
      categories,
      scope.selectedCategoryId,
    );
    if (selectedSection != _section) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _section = selectedSection);
      });
    }
    return Column(
      children: [
        Material(
          color: CX.panel,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    SegmentedButton<int>(
                  segments: [
                    ButtonSegment(
                      value: 0,
                      icon: Icon(Icons.groups_2_outlined),
                      label: Text('Plantel'),
                    ),
                    if (!external)
                      ButtonSegment(
                        value: 1,
                        icon: Icon(Icons.fact_check_outlined),
                        label: Text('Asistencia'),
                      ),
                    ButtonSegment(
                      value: external ? 1 : 2,
                      icon: Icon(Icons.sports_soccer_outlined),
                      label: Text('Planificar'),
                    ),
                    ButtonSegment(
                      value: external ? 2 : 3,
                      icon: Icon(Icons.account_tree_outlined),
                      label: Text('Impronta futbolística'),
                    ),
                  ],
                  selected: {selectedSection},
                  showSelectedIcon: false,
                      onSelectionChanged: (value) => selectSection(value.first),
                    ),
                    if (planning &&
                        categories.isNotEmpty &&
                        plannerCategoryId != null) ...[
                      const SizedBox(width: 10),
                      _PlannerCategorySelector(
                        categories: categories,
                        selectedCategoryId: plannerCategoryId,
                        onChanged: _selectPlannerCategory,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        // Section -> screen map. The screen classes keep historical names:
        // CuotaScreen  = "Plantel" (squad + tracking)
        // AsistenciaScreen = "Asistencia" (LUD profiles only)
        // ReservasScreen = "Planificar" (match / session planner)
        // PerfilScreen = "Impronta futbolística" (playing identity)
        // They each render their own Scaffold and a real empty state, so a
        // missing plantel or category never leaves this area blank.
        Expanded(
          child: AnimatedSwitcher(
            duration: (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
                ? Duration.zero
                : CX.motion,
            switchInCurve: CX.curve,
            switchOutCurve: CX.curve,
            layoutBuilder: (currentChild, previousChildren) => Stack(
              fit: StackFit.expand,
              children: [
                ...previousChildren,
                ?currentChild,
              ],
            ),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, .02),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: KeyedSubtree(
              key: ValueKey('tactica-section-$selectedSection-$external'),
              child: switch (selectedSection) {
                0 => const CuotaScreen(),
                1 => external
                    ? ReservasScreen(
                        initialCategoryOverride: plannerCategoryId,
                        onCategoryChanged: _selectPlannerCategory,
                      )
                    : const AsistenciaScreen(),
                2 => external
                    ? const PerfilScreen()
                    : ReservasScreen(
                        initialCategoryOverride: plannerCategoryId,
                        onCategoryChanged: _selectPlannerCategory,
                      ),
                _ => const PerfilScreen(),
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _PlannerCategorySelector extends StatelessWidget {
  final List<CategorySquad> categories;
  final String selectedCategoryId;
  final ValueChanged<String?> onChanged;

  const _PlannerCategorySelector({
    required this.categories,
    required this.selectedCategoryId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      constraints: const BoxConstraints(minWidth: 190, maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: CX.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedCategoryId,
          isExpanded: true,
          icon: const Icon(Icons.expand_more, size: 18),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: CX.white,
                fontWeight: FontWeight.w700,
              ),
          selectedItemBuilder: (context) => categories
              .map(
                (item) => Row(
                  children: [
                    const Icon(Icons.groups_2_outlined, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )
              .toList(),
          items: categories
              .map(
                (item) => DropdownMenuItem(
                  value: item.id,
                  child: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

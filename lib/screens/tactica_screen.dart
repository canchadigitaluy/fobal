import 'package:flutter/material.dart';

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

  void selectSection(int index) {
    final external = _isExternal(context);
    final max = external ? 2 : 3;
    final next = index.clamp(0, max);
    if (next == _section) return;
    setState(() => _section = next);
  }

  bool _isExternal(BuildContext context) {
    final club = AppScope.of(context).fullClub;
    return club.dataSource == 'manual' || club.league == 'Trabajo independiente';
  }

  @override
  Widget build(BuildContext context) {
    final external = _isExternal(context);
    final selectedSection = _section.clamp(0, external ? 2 : 3);
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
                child: SegmentedButton<int>(
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
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey('tactica-section-$_section'),
            child: switch (selectedSection) {
              0 => const CuotaScreen(),
              1 => external ? const ReservasScreen() : const AsistenciaScreen(),
              2 => external ? const PerfilScreen() : const ReservasScreen(),
              _ => const PerfilScreen(),
            },
          ),
        ),
      ],
    );
  }
}

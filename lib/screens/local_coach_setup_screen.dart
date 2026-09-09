// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import '../services/account_identity_service.dart';

class LocalCoachSetupScreen extends StatefulWidget {
  const LocalCoachSetupScreen({super.key});

  @override
  State<LocalCoachSetupScreen> createState() => _LocalCoachSetupScreenState();
}

class _LocalCoachSetupScreenState extends State<LocalCoachSetupScreen> {
  final _clubController = TextEditingController();
  final _coachController = TextEditingController();
  final _nameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _timeController = TextEditingController();
  final List<Player> _players = [];
  final Set<String> _days = {};
  final Set<String> _panelSections = {
    'Mi equipo',
    'Táctica',
    'Calendario',
    'Asistencia',
    'Alineación & citaciones',
  };
  int _step = 0;
  String _memberType = 'Jugador';
  String? _message;

  @override
  void dispose() {
    _clubController.dispose();
    _coachController.dispose();
    _nameController.dispose();
    _lastNameController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  void _addMember() {
    final name = _nameController.text.trim();
    final last = _lastNameController.text.trim();
    if (name.length < 2 || last.length < 2) return;
    if (_memberType == 'Jugador') {
      _players.add(
        Player(
          id: 'manual-${DateTime.now().millisecondsSinceEpoch}',
          categoryId: '',
          firstName: name,
          lastName: last,
          age: 0,
          position: '',
          secondaryPositions: '',
          dominantFoot: '',
          status: 'Activo',
          attendanceRate: 0,
          trend: '',
          note: '',
        ),
      );
    }
    _nameController.clear();
    _lastNameController.clear();
    setState(() {});
  }

  void _next() {
    if (_step == 0) {
      final clubName = _clubController.text.trim();
      final coachName = _coachController.text.trim();
      if (clubName.length < 3 || coachName.length < 3) {
        setState(() => _message = 'Completa equipo y nombre del profe.');
        return;
      }
    }
    if (_step < 3) {
      setState(() {
        _message = null;
        _step++;
      });
      return;
    }
    _enter();
  }

  void _enter() {
    final clubName = _clubController.text.trim();
    final coachName = _coachController.text.trim();
    if (clubName.length < 3 || coachName.length < 3) {
      setState(() => _message = 'Completa equipo y nombre del profe.');
      return;
    }

    final userId = AccountIdentityService.currentUserId;
    if (userId == null) {
      setState(() {
        _message =
            'Tu sesión venció. Volvé a iniciar sesión para crear tu espacio.';
      });
      return;
    }
    final id = AccountIdentityService.manualClubIdFor(userId, _slug(clubName));
    final categoryId = '$id-plantel';
    final schedule = [
      if (_days.isNotEmpty) _days.join(', '),
      if (_timeController.text.trim().isNotEmpty) _timeController.text.trim(),
    ].join(' - ');
    final club = CanteraClub(
      id: id,
      name: clubName,
      league: 'Trabajo independiente',
      sportFocus: 'Futbol',
      dataSource: 'manual',
      headCoachName: coachName,
      primaryColor: const Color(0xFF159463),
      secondaryColor: const Color(0xFF102019),
      methodology: const Methodology(
        playingStyle: '',
        offensivePrinciples: [],
        defensivePrinciples: [],
        ageObjectives: [],
        values: [],
        evaluationCriteria: [],
      ),
      categories: [
        CategorySquad(
          id: categoryId,
          name: 'Plantel',
          sport: 'Futbol',
          ageGroup: '',
          coachName: coachName,
          playerCount: _players.length,
          attendanceRate: 0,
          objectives: const [],
          currentFocus: '',
          lastRegistered: '',
          practiceSchedule: schedule,
        ),
      ],
      players: _players
          .map((player) => player.copyWith(categoryId: categoryId))
          .toList(),
      sessions: const [],
      trainingReports: const [],
      alerts: const [],
      aiReports: const [],
      users: [
        ClubUserAccess(
          id: 'profe-local',
          name: coachName,
          role: 'Entrenador',
          email: '',
          phone: '',
        ),
      ],
    );

    final scope = AppScope.of(context);
    scope.updateClub(club);
    AccountIdentityService.writeLocalClubId(club.id);
    AccountIdentityService.writeActiveClubId(club.id);
    html.window.localStorage['fobal_panel_sections_${club.id}'] = jsonEncode(
      _panelSections.toList(),
    );
    scope.selectRole(UserRole.coach);
    scope.selectCategory(categoryId);
    Navigator.pushReplacementNamed(context, '/local-home');
  }

  String _slug(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CX.canvas,
      appBar: AppBar(
        backgroundColor: CX.green,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => _step == 0
              ? Navigator.pushReplacementNamed(context, '/login')
              : setState(() => _step--),
        ),
        title: const Text(
          '¡Bienvenido!',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 34),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 660),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Stepper(current: _step),
                  const SizedBox(height: 18),
                  AnimatedSwitcher(
                    duration: CX.motion,
                    child: switch (_step) {
                      0 => _teamStep(),
                      1 => _trainingStep(),
                      2 => _simpleStep(
                        icon: Icons.sports_soccer_outlined,
                        title: 'Partido',
                        text:
                            'Luego vas a poder preparar partidos y citaciones manualmente.',
                      ),
                      _ => _simpleStep(
                        icon: Icons.emoji_events_outlined,
                        title: 'Panel',
                        text:
                            'Elegí qué herramientas querés ver para que el panel arranque simple.',
                        child: _panelStep(),
                      ),
                    },
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _message!,
                      style: const TextStyle(
                        color: CX.amber,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  TextButton.icon(
                    onPressed: _step < 3 ? _next : _enter,
                    icon: Icon(_step < 3 ? Icons.arrow_forward : Icons.check),
                    label: Text(_step < 3 ? 'Continuar' : 'Entrar a fobal'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _teamStep() {
    return Column(
      key: const ValueKey('team'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _clubController,
          decoration: const InputDecoration(
            labelText: 'Nombre del club o colegio',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _coachController,
          decoration: const InputDecoration(labelText: 'Tu nombre'),
        ),
        const SizedBox(height: 18),
        _SetupPanel(
          title: 'Añade miembros al equipo',
          subtitle: 'Crea contactos uno por uno con nombre y apellido',
          child: Column(
            children: [
              Row(
                children: ['Jugador', 'Entrenador', 'Padre/madre']
                    .map(
                      (item) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            selected: _memberType == item,
                            onSelected: (_) =>
                                setState(() => _memberType = item),
                            label: SizedBox(
                              width: double.infinity,
                              child: Center(child: Text(item)),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(hintText: 'Nombre'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _lastNameController,
                decoration: const InputDecoration(hintText: 'Apellido'),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _addMember,
                icon: const Icon(Icons.person_add_alt_1),
                label: Text('Añadir $_memberType'),
              ),
              if (_players.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _players.length == 1
                        ? '1 jugador cargado'
                        : '${_players.length} jugadores cargados',
                    style: const TextStyle(
                      color: CX.green,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _trainingStep() {
    const days = ['Lu', 'Ma', 'Mi', 'Ju', 'Vi', 'Sá', 'Do'];
    return Column(
      key: const ValueKey('training'),
      children: [
        const Text(
          '¿Cuándo entrenas durante la semana?',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 22),
        const Icon(Icons.sports_soccer, color: CX.green, size: 26),
        const SizedBox(height: 18),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: days
              .map(
                (day) => ChoiceChip(
                  selected: _days.contains(day),
                  onSelected: (_) => setState(() {
                    _days.contains(day) ? _days.remove(day) : _days.add(day);
                  }),
                  label: SizedBox(width: 54, child: Center(child: Text(day))),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _timeController,
          decoration: const InputDecoration(
            labelText: 'Horarios de práctica',
            hintText: 'Ej: 19:30 a 21:00',
          ),
        ),
      ],
    );
  }

  Widget _panelStep() {
    final options = [
      ('Mi equipo', Icons.shield_outlined),
      ('Táctica', Icons.sports_soccer_outlined),
      ('Calendario', Icons.calendar_month_outlined),
      ('Asistencia', Icons.fact_check_outlined),
      ('Alineación & citaciones', Icons.view_module_outlined),
    ];
    return Material(
      type: MaterialType.transparency,
      child: Column(
        children: options
            .map(
              (option) => CheckboxListTile(
                value: _panelSections.contains(option.$1),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    _panelSections.add(option.$1);
                  } else if (_panelSections.length > 1) {
                    _panelSections.remove(option.$1);
                  }
                }),
                secondary: Icon(option.$2, color: CX.green),
                title: Text(option.$1),
                controlAffinity: ListTileControlAffinity.trailing,
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _simpleStep({
    required IconData icon,
    required String title,
    required String text,
    Widget? child,
  }) {
    return Container(
      key: ValueKey(title),
      padding: const EdgeInsets.all(26),
      decoration: CX.panelDecoration(),
      child: Column(
        children: [
          Icon(icon, color: CX.green, size: 42),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: CX.muted),
          ),
          if (child != null) ...[const SizedBox(height: 18), child],
        ],
      ),
    );
  }
}

class _SetupPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SetupPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CX.greenDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CX.green.withValues(alpha: .45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: CX.green,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          Text(subtitle, style: const TextStyle(color: CX.muted, fontSize: 12)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final int current;

  const _Stepper({required this.current});

  @override
  Widget build(BuildContext context) {
    final labels = ['Equipo', 'Entreno', 'Partido', 'Panel'];
    return Row(
      children: List.generate(labels.length, (index) {
        final done = index < current;
        final active = index == current;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    CircleAvatar(
                      backgroundColor: done || active ? CX.green : CX.greenDark,
                      foregroundColor: done || active ? Colors.white : CX.green,
                      child: done
                          ? const Icon(Icons.check, size: 18)
                          : Text(
                              '${index + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      labels[index],
                      style: TextStyle(
                        fontSize: 11,
                        color: active ? CX.green : CX.muted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (index != labels.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    color: index < current ? CX.green : CX.lineStrong,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}

// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'data/cantera_data.dart';
import 'screens/access_gate_screen.dart';
import 'screens/alineacion_screen.dart';
import 'screens/asistencia_screen.dart';
import 'screens/configuracion_club_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/local_coach_setup_screen.dart';
import 'screens/calendario_screen.dart';
import 'screens/mi_equipo_screen.dart';
import 'screens/tactica_screen.dart';
import 'screens/estadisticas_screen.dart';
import 'services/club_access_service.dart';
import 'services/club_backup_service.dart';
import 'services/club_sync_service.dart';
import 'services/offline_mutation_service.dart';
import 'state/section_handoff.dart';
import 'services/preview_access_service.dart';
import 'services/supabase_auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseAuthService.initialize();
  OfflineMutationService.instance.start();
  // Single source of truth for the active club: restore it before the first
  // frame so membership resolution and category storage stay in lockstep.
  final restoredClubId = html.window.localStorage['fobal_active_club_id'];
  if (restoredClubId != null && restoredClubId.isNotEmpty) {
    ClubAccessService.selectActiveClub(restoredClubId);
  }
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  // Any widget that throws while building renders this instead of a blank/grey
  // rectangle, so a broken section always shows something the user can act on.
  ErrorWidget.builder = (_) => const _SectionErrorView();
  runApp(const CanteraApp());
}

class _SectionErrorView extends StatelessWidget {
  const _SectionErrorView();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CX.canvas,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: CX.amber, size: 34),
                const SizedBox(height: 12),
                const Text(
                  'Esta sección no se pudo mostrar',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Probá cambiar de sección y volver, o recargá la página. '
                  'Tus datos quedan guardados.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: CX.muted, fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AppScope extends InheritedWidget {
  final CanteraClub club;
  final CanteraClub fullClub;
  final UserRole role;
  final String? selectedCategoryId;
  final ValueChanged<UserRole> selectRole;
  final ValueChanged<String?> selectCategory;
  final ValueChanged<CanteraClub> updateClub;

  /// Wholesale replace of the active space by a user action (import). Marks the
  /// club dirty so it syncs to the cloud.
  final ValueChanged<CanteraClub> replaceClub;

  /// Wholesale replace by an incoming cloud document. Does NOT mark dirty (the
  /// data just came from the server).
  final ValueChanged<CanteraClub> adoptClub;
  final CanteraClub Function(String clubId) loadClub;

  const AppScope({
    super.key,
    required this.club,
    required this.fullClub,
    required this.role,
    required this.selectedCategoryId,
    required this.selectRole,
    required this.selectCategory,
    required this.updateClub,
    required this.replaceClub,
    required this.adoptClub,
    required this.loadClub,
    required super.child,
  });

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      club != oldWidget.club ||
      fullClub != oldWidget.fullClub ||
      role != oldWidget.role ||
      selectedCategoryId != oldWidget.selectedCategoryId;
}

/// Imperative bridge for "a read turned into an action": a section calls
/// `openPlannerWithFocus` / `openMatchPrep` / `openLineup`, the shell navigates
/// and stashes the payload, and the destination section reads it once with the
/// matching `take*`. Callbacks are stable, so this never triggers rebuilds.
class ShellActions extends InheritedWidget {
  final void Function(SessionFocusHandoff) openPlannerWithFocus;
  final void Function(MatchPrepHandoff) openMatchPrep;
  final void Function([LineupHint?]) openLineup;
  final void Function(ShellSection) openSection;
  final SessionFocusHandoff? Function() takeSessionFocus;
  final MatchPrepHandoff? Function() takeMatchPrep;
  final LineupHint? Function() takeLineupHint;

  const ShellActions({
    super.key,
    required this.openPlannerWithFocus,
    required this.openMatchPrep,
    required this.openLineup,
    required this.openSection,
    required this.takeSessionFocus,
    required this.takeMatchPrep,
    required this.takeLineupHint,
    required super.child,
  });

  static ShellActions? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellActions>();

  static ShellActions of(BuildContext context) {
    final actions = maybeOf(context);
    assert(actions != null, 'ShellActions not found');
    return actions!;
  }

  @override
  bool updateShouldNotify(ShellActions oldWidget) => false;
}

/// One typographic calibration for the whole app: tighter tracking on
/// display/title sizes, roomier line-height on body copy, firmer label
/// weights. Sizes are left untouched (only tracking / height / weight) so no
/// bare `Text` shifts its footprint — an explicit `style:` still overrides.
TextTheme _tuneText(TextTheme t) => t.copyWith(
  displayLarge: t.displayLarge?.copyWith(
    letterSpacing: -.5,
    height: 1.12,
    fontWeight: FontWeight.w800,
  ),
  displayMedium: t.displayMedium?.copyWith(
    letterSpacing: -.5,
    height: 1.12,
    fontWeight: FontWeight.w800,
  ),
  displaySmall: t.displaySmall?.copyWith(
    letterSpacing: -.4,
    height: 1.14,
    fontWeight: FontWeight.w800,
  ),
  headlineLarge: t.headlineLarge?.copyWith(
    letterSpacing: -.4,
    height: 1.15,
    fontWeight: FontWeight.w800,
  ),
  headlineMedium: t.headlineMedium?.copyWith(
    letterSpacing: -.3,
    height: 1.16,
    fontWeight: FontWeight.w800,
  ),
  headlineSmall: t.headlineSmall?.copyWith(
    letterSpacing: -.2,
    height: 1.2,
    fontWeight: FontWeight.w700,
  ),
  titleLarge: t.titleLarge?.copyWith(
    letterSpacing: -.15,
    height: 1.2,
    fontWeight: FontWeight.w700,
  ),
  titleMedium: t.titleMedium?.copyWith(
    letterSpacing: -.1,
    height: 1.25,
    fontWeight: FontWeight.w600,
  ),
  titleSmall: t.titleSmall?.copyWith(height: 1.3, fontWeight: FontWeight.w600),
  bodyLarge: t.bodyLarge?.copyWith(height: 1.45),
  bodyMedium: t.bodyMedium?.copyWith(height: 1.45),
  bodySmall: t.bodySmall?.copyWith(height: 1.4),
  labelLarge: t.labelLarge?.copyWith(
    letterSpacing: .1,
    fontWeight: FontWeight.w700,
  ),
  labelMedium: t.labelMedium?.copyWith(
    letterSpacing: .2,
    fontWeight: FontWeight.w600,
  ),
  labelSmall: t.labelSmall?.copyWith(
    letterSpacing: .3,
    fontWeight: FontWeight.w600,
  ),
);

class CX {
  static const bg = Color(0xFFF3F6F4);
  static const canvas = Color(0xFFFAFCFB);
  static const panel = Color(0xFFFFFFFF);
  static const panel2 = Color(0xFFF1F5F3);
  static const panel3 = Color(0xFFE7EFEB);
  static const line = Color(0x260D1A14);
  static const lineStrong = Color(0x420D1A14);
  static const white = Color(0xFF102019);
  static const muted = Color(0xA60D1A14);
  static const faint = Color(0x850D1A14);
  static const green = Color(0xFF159463);
  static const greenDark = Color(0xFFDDF6EA);
  static const blue = Color(0xFF2E67A8);
  static const amber = Color(0xFFE0A11A);
  static const red = Color(0xFFDC3D3D);
  static const motionFast = Duration(milliseconds: 160);
  static const motion = Duration(milliseconds: 260);
  static const motionSlow = Duration(milliseconds: 420);
  static const curve = Curves.easeOutCubic;

  static BoxDecoration panelDecoration({Color? borderColor}) => BoxDecoration(
    color: panel,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: borderColor ?? line),
    boxShadow: const [
      BoxShadow(color: Color(0x0E0D1A14), blurRadius: 22, offset: Offset(0, 6)),
    ],
  );
}

class CanteraApp extends StatefulWidget {
  const CanteraApp({super.key});

  @override
  State<CanteraApp> createState() => _CanteraAppState();
}

class _CanteraAppState extends State<CanteraApp> {
  static const _storagePrefix = 'cantera_os_club_';
  static const _localClubKey = 'fobal_local_profile_club_id';
  static const _categoryPrefix = 'fobal_selected_category_';
  static const _activeClubKey = 'fobal_active_club_id';
  UserRole _role = UserRole.coach;
  String? _selectedCategoryId;
  late CanteraClub _club;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  bool _recoveredFromBackup = false;
  final Map<String, Timer> _pushDebounce = {};
  StreamSubscription<ClubSyncEvent>? _syncEventsSub;

  @override
  void initState() {
    super.initState();
    _club = _loadClub();
    _selectedCategoryId = _storedCategoryId(_club);
    _syncEventsSub = ClubSyncService.events.listen(_onSyncEvent);
  }

  @override
  void dispose() {
    for (final timer in _pushDebounce.values) {
      timer.cancel();
    }
    _syncEventsSub?.cancel();
    super.dispose();
  }

  /// A conflict was resolved by the sync layer adopting the server version into
  /// the local blob. Reload it into memory and tell the user their copy was
  /// kept as a backup. Full conflict UX is Phase 2c.
  void _onSyncEvent(ClubSyncEvent event) {
    if (!mounted) return;
    if (event.type == ClubSyncEventType.conflict &&
        event.clubId == _club.id) {
      setState(() => _club = _loadClubById(event.clubId));
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 6),
          content: Text(
            'Se cargó una versión más nueva desde otro dispositivo. '
            'Tu copia anterior quedó respaldada.',
          ),
        ),
      );
    }
  }

  /// Marks [clubId] dirty and (debounced) queues a cloud push. No-op without a
  /// session — edits stay local, exactly as before Phase 2b.
  void _schedulePush(String clubId) {
    if (!SupabaseAuthService.isConfigured ||
        SupabaseAuthService.currentSession == null) {
      return;
    }
    ClubSyncService.markDirty(clubId);
    _pushDebounce[clubId]?.cancel();
    _pushDebounce[clubId] = Timer(const Duration(seconds: 3), () {
      _pushDebounce.remove(clubId);
      OfflineMutationService.instance.enqueueClubDocumentPush(clubId);
    });
  }

  CanteraClub _loadClub() {
    // Priority: last active club (LUD or manual) -> manual profile -> demo.
    final activeClubId = html.window.localStorage[_activeClubKey];
    if (activeClubId != null && activeClubId.isNotEmpty) {
      return _loadClubById(activeClubId);
    }
    final localClubId = html.window.localStorage[_localClubKey];
    if (localClubId != null && localClubId.isNotEmpty) {
      return _loadClubById(localClubId);
    }
    return _loadClubById(canteraDemoClub.id);
  }

  CanteraClub _loadClubById(String clubId) {
    final raw = html.window.localStorage['$_storagePrefix$clubId'];
    if (raw == null || raw.isEmpty) {
      return canteraDemoClub.copyWith(id: clubId);
    }
    try {
      return CanteraClub.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // The main blob is unreadable: recover the newest valid snapshot instead
      // of silently dropping to the demo club, and flag it so the shell can
      // tell the user what happened.
      final recovered = ClubBackupService.recoverCorruptMain(clubId);
      if (recovered != null) {
        _recoveredFromBackup = true;
        return recovered;
      }
      return canteraDemoClub.copyWith(id: clubId);
    }
  }

  String? _storedCategoryId(CanteraClub club) {
    final key = '$_categoryPrefix${club.id}';
    final raw = html.window.localStorage[key];
    final resolved = resolveStoredCategoryId(club: club, storedCategoryId: raw);
    if (raw != null && resolved == null) {
      // Surgical correction: only this club's stored-category key, never a
      // global localStorage wipe. Covers a category that no longer exists
      // and — for a manual club — a leaked lud-cat-* id.
      html.window.localStorage.remove(key);
    }
    return resolved;
  }

  String? _effectiveCategoryId(CanteraClub club) {
    if (_role == UserRole.coordinator || club.categories.isEmpty) return null;
    if (club.categories.any((category) => category.id == _selectedCategoryId)) {
      return _selectedCategoryId;
    }
    final stored = _storedCategoryId(club);
    if (stored != null) return stored;
    return club.categories.first.id;
  }

  CanteraClub _visibleClub() {
    final categoryId = _effectiveCategoryId(_club);
    if (categoryId == null) return _club;
    final category = _club.categories.firstWhere(
      (item) => item.id == categoryId,
    );
    return _club.copyWith(
      categories: [category],
      players: _club.players
          .where((player) => player.categoryId == categoryId)
          .toList(),
      sessions: _club.sessions
          .where((session) => session.categoryId == categoryId)
          .toList(),
      trainingReports: _club.trainingReports
          .where((report) => report.categoryId == categoryId)
          .toList(),
      matchResults: _club.matchResults
          .where((result) => result.categoryId == categoryId)
          .toList(),
      matchPreparations: _club.matchPreparations
          .where((prep) => prep.categoryId == categoryId)
          .toList(),
      alerts: _club.alerts
          .where(
            (alert) =>
                alert.categoryId == null || alert.categoryId == categoryId,
          )
          .toList(),
      aiReports: _club.aiReports
          .where((report) => report.categoryId == categoryId)
          .toList(),
    );
  }

  CanteraClub _mergeScopedClub(CanteraClub scopedClub) {
    final categoryId = _effectiveCategoryId(_club);
    if (categoryId == null) return scopedClub;
    CategorySquad? scopedCategory;
    for (final category in scopedClub.categories) {
      if (category.id == categoryId) {
        scopedCategory = category;
        break;
      }
    }
    return _club.copyWith(
      name: scopedClub.name,
      league: scopedClub.league,
      sportFocus: scopedClub.sportFocus,
      logoUrl: scopedClub.logoUrl,
      seasonYear: scopedClub.seasonYear,
      headCoachName: scopedClub.headCoachName,
      assistantCoachName: scopedClub.assistantCoachName,
      dataSource: scopedClub.dataSource,
      syncedAt: scopedClub.syncedAt,
      methodology: scopedClub.methodology,
      categories: _club.categories
          .map(
            (category) => category.id == categoryId
                ? scopedCategory ?? category
                : category,
          )
          .toList(),
      players: [
        ..._club.players.where((player) => player.categoryId != categoryId),
        ...scopedClub.players.where(
          (player) => player.categoryId == categoryId,
        ),
      ],
      sessions: [
        ..._club.sessions.where((session) => session.categoryId != categoryId),
        ...scopedClub.sessions.where(
          (session) => session.categoryId == categoryId,
        ),
      ],
      trainingReports: [
        ..._club.trainingReports.where(
          (report) => report.categoryId != categoryId,
        ),
        ...scopedClub.trainingReports.where(
          (report) => report.categoryId == categoryId,
        ),
      ],
      // Manual match results follow the same per-category merge pattern as
      // trainingReports so an edit in the scoped club is not dropped.
      matchResults: [
        ..._club.matchResults.where(
          (result) => result.categoryId != categoryId,
        ),
        ...scopedClub.matchResults.where(
          (result) => result.categoryId == categoryId,
        ),
      ],
      // Club-wide, not category-scoped — same treatment as name/league/etc.
      savedExercises: scopedClub.savedExercises,
      matchPreparations: [
        ..._club.matchPreparations.where(
          (prep) => prep.categoryId != categoryId,
        ),
        ...scopedClub.matchPreparations.where(
          (prep) => prep.categoryId == categoryId,
        ),
      ],
      alerts: [
        ..._club.alerts.where((alert) => alert.categoryId != categoryId),
        ...scopedClub.alerts.where((alert) => alert.categoryId == categoryId),
      ],
      aiReports: [
        ..._club.aiReports.where((report) => report.categoryId != categoryId),
        ...scopedClub.aiReports.where(
          (report) => report.categoryId == categoryId,
        ),
      ],
    );
  }

  void _updateClub(CanteraClub club) {
    final changingClub = club.id != _club.id;
    final nextClub = changingClub ? club : _mergeScopedClub(club);
    ClubBackupService.rotateSnapshot(nextClub.id);
    html.window.localStorage['$_storagePrefix${nextClub.id}'] = jsonEncode(
      nextClub.toJson(),
    );
    if (changingClub) {
      // Keep the active-club pointer and the per-club category key aligned.
      html.window.localStorage[_activeClubKey] = nextClub.id;
      ClubAccessService.selectActiveClub(nextClub.id);
    }
    setState(() {
      _club = nextClub;
      if (changingClub) _selectedCategoryId = _storedCategoryId(nextClub);
    });
    _schedulePush(nextClub.id);
  }

  /// Durable write of a whole-club replacement (import or cloud adoption).
  /// Mirrors the club-switch branch of [_updateClub] without the per-category
  /// merge. When [sync] is true the club is marked dirty and queued for cloud
  /// push; cloud adoption passes false (the data already came from the server).
  void _writeWholeClub(CanteraClub club, {required bool sync}) {
    ClubBackupService.rotateSnapshot(club.id);
    html.window.localStorage['$_storagePrefix${club.id}'] = jsonEncode(
      club.toJson(),
    );
    html.window.localStorage[_activeClubKey] = club.id;
    ClubAccessService.selectActiveClub(club.id);
    setState(() {
      _club = club;
      _selectedCategoryId = _storedCategoryId(club);
    });
    if (sync) _schedulePush(club.id);
  }

  void _replaceClub(CanteraClub club) => _writeWholeClub(club, sync: true);

  void _adoptCloudClub(CanteraClub club) => _writeWholeClub(club, sync: false);

  void _selectRole(UserRole role) {
    setState(() {
      _role = role;
      if (_role == UserRole.coordinator) _selectedCategoryId = null;
    });
  }

  void _selectCategory(String? categoryId) {
    // A manual club must never adopt a LUD category id, even if some future
    // caller passes one in by mistake.
    if (categoryId != null &&
        _club.isManualClub &&
        isLudCategoryId(categoryId)) {
      return;
    }
    // The category preference is always written for the currently active club,
    // and the active-club pointer is refreshed so the two never drift apart.
    html.window.localStorage[_activeClubKey] = _club.id;
    if (categoryId == null || categoryId.isEmpty) {
      html.window.localStorage.remove('$_categoryPrefix${_club.id}');
    } else {
      html.window.localStorage['$_categoryPrefix${_club.id}'] = categoryId;
    }
    setState(() => _selectedCategoryId = categoryId);
  }

  @override
  Widget build(BuildContext context) {
    final baseText = _tuneText(
      GoogleFonts.interTextTheme(ThemeData.light().textTheme),
    );
    final visibleClub = _visibleClub();
    if (_recoveredFromBackup) {
      _recoveredFromBackup = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 6),
            content: Text(
              'Tus datos estaban dañados. Los recuperamos desde un respaldo '
              'automático reciente.',
            ),
          ),
        );
      });
    }
    return AppScope(
      club: visibleClub,
      fullClub: _club,
      role: _role,
      selectedCategoryId: _effectiveCategoryId(_club),
      selectRole: _selectRole,
      selectCategory: _selectCategory,
      updateClub: _updateClub,
      replaceClub: _replaceClub,
      adoptClub: _adoptCloudClub,
      loadClub: _loadClubById,
      child: MaterialApp(
        title: 'fobal',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: _messengerKey,
        scrollBehavior: const CanteraScrollBehavior(),
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          scaffoldBackgroundColor: CX.canvas,
          canvasColor: CX.panel,
          // Quiet, brand-tinted tap/hover/focus feedback everywhere an Ink
          // surface reacts — the default grey ripple reads generic on web.
          splashFactory: InkRipple.splashFactory,
          splashColor: CX.green.withValues(alpha: .07),
          highlightColor: CX.green.withValues(alpha: .04),
          hoverColor: CX.green.withValues(alpha: .04),
          focusColor: CX.green.withValues(alpha: .10),
          colorScheme: const ColorScheme.light(
            primary: CX.green,
            secondary: CX.blue,
            surface: CX.panel,
            error: CX.red,
          ),
          textTheme: baseText.apply(
            bodyColor: CX.white,
            displayColor: CX.white,
          ),
          dividerColor: CX.line,
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: _CanteraPageTransitionsBuilder(),
              TargetPlatform.iOS: _CanteraPageTransitionsBuilder(),
              TargetPlatform.linux: _CanteraPageTransitionsBuilder(),
              TargetPlatform.macOS: _CanteraPageTransitionsBuilder(),
              TargetPlatform.windows: _CanteraPageTransitionsBuilder(),
            },
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: CX.canvas,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: false,
            iconTheme: IconThemeData(color: CX.white, size: 22),
            shape: Border(bottom: BorderSide(color: CX.line)),
            titleTextStyle: TextStyle(
              color: CX.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -.3,
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: CX.panel2,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 15,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: CX.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: CX.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: CX.green, width: 1.4),
            ),
            labelStyle: const TextStyle(color: CX.muted),
            hintStyle: const TextStyle(color: CX.faint),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: CX.green,
              foregroundColor: const Color(0xFF07100B),
              minimumSize: const Size(double.infinity, 50),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
              animationDuration: CX.motionFast,
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              foregroundColor: CX.white,
              side: const BorderSide(color: CX.lineStrong),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              minimumSize: const Size(0, 46),
              animationDuration: CX.motionFast,
            ),
          ),
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            backgroundColor: CX.white,
            elevation: 8,
            contentTextStyle: const TextStyle(
              color: Color(0xFFEEF3F0),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
            actionTextColor: const Color(0xFF6EF2C7),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 20,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: CX.panel,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: CX.canvas,
            surfaceTintColor: Colors.transparent,
            indicatorColor: CX.green.withValues(alpha: .16),
            indicatorShape: const StadiumBorder(),
            height: 68,
            iconTheme: WidgetStateProperty.resolveWith(
              (states) => IconThemeData(
                size: 22,
                color: states.contains(WidgetState.selected)
                    ? CX.green
                    : CX.faint,
              ),
            ),
            labelTextStyle: WidgetStateProperty.resolveWith(
              (states) => TextStyle(
                fontSize: 10.5,
                letterSpacing: .1,
                fontWeight: states.contains(WidgetState.selected)
                    ? FontWeight.w800
                    : FontWeight.w600,
                color: states.contains(WidgetState.selected)
                    ? CX.green
                    : CX.muted,
              ),
            ),
          ),
          // Bare Card / Chip / TextButton pick up fobal's flat language:
          // no M3 tinted elevation, hairline edge, pill chips, green links.
          cardTheme: CardThemeData(
            elevation: 0,
            color: CX.panel,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: CX.line),
            ),
          ),
          chipTheme: ChipThemeData(
            backgroundColor: CX.panel2,
            surfaceTintColor: Colors.transparent,
            side: const BorderSide(color: CX.line),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            labelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: CX.white,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: CX.green,
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 40),
            ),
          ),
          // Form toggles: green when on, sober neutral track/outline when off.
          checkboxTheme: CheckboxThemeData(
            fillColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected)
                  ? CX.green
                  : Colors.transparent,
            ),
            checkColor: const WidgetStatePropertyAll(Color(0xFF07100B)),
            side: const BorderSide(color: CX.lineStrong, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            visualDensity: VisualDensity.compact,
          ),
          radioTheme: RadioThemeData(
            fillColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected)
                  ? CX.green
                  : CX.lineStrong,
            ),
            visualDensity: VisualDensity.compact,
          ),
          switchTheme: SwitchThemeData(
            thumbColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected)
                  ? Colors.white
                  : CX.faint,
            ),
            trackColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected)
                  ? CX.green
                  : CX.panel2,
            ),
            trackOutlineColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected)
                  ? Colors.transparent
                  : CX.lineStrong,
            ),
            trackOutlineWidth: const WidgetStatePropertyAll(1.5),
          ),
          // Transient popover surfaces all adopt the panel language:
          // white fill, hairline edge, radius 12, no M3 tint.
          menuTheme: MenuThemeData(
            style: MenuStyle(
              backgroundColor: const WidgetStatePropertyAll(CX.panel),
              surfaceTintColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
              elevation: const WidgetStatePropertyAll(8),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(vertical: 6),
              ),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: CX.line),
                ),
              ),
            ),
          ),
          dropdownMenuTheme: DropdownMenuThemeData(
            menuStyle: MenuStyle(
              backgroundColor: const WidgetStatePropertyAll(CX.panel),
              surfaceTintColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
              elevation: const WidgetStatePropertyAll(8),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: CX.line),
                ),
              ),
            ),
          ),
          popupMenuTheme: PopupMenuThemeData(
            color: CX.panel,
            surfaceTintColor: Colors.transparent,
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: CX.line),
            ),
            textStyle: const TextStyle(
              fontSize: 13,
              color: CX.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          bottomSheetTheme: const BottomSheetThemeData(
            backgroundColor: CX.panel,
            surfaceTintColor: Colors.transparent,
            elevation: 12,
            showDragHandle: true,
            dragHandleColor: CX.lineStrong,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
          ),
          datePickerTheme: DatePickerThemeData(
            backgroundColor: CX.panel,
            surfaceTintColor: Colors.transparent,
            elevation: 12,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          listTileTheme: ListTileThemeData(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            minVerticalPadding: 10,
            iconColor: CX.muted,
            textColor: CX.white,
            titleTextStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: CX.white,
            ),
            subtitleTextStyle: const TextStyle(
              fontSize: 12,
              color: CX.muted,
              height: 1.3,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          tooltipTheme: TooltipThemeData(
            decoration: BoxDecoration(
              color: CX.white,
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(
              color: Color(0xFFEEF3F0),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            waitDuration: const Duration(milliseconds: 400),
          ),
          progressIndicatorTheme: const ProgressIndicatorThemeData(
            color: CX.green,
            linearTrackColor: CX.panel2,
            circularTrackColor: CX.panel2,
          ),
          // Thin, rounded, hover-reveal scrollbar — the default web
          // scrollbar reads heavy and unbranded.
          scrollbarTheme: ScrollbarThemeData(
            thumbVisibility: const WidgetStatePropertyAll(false),
            thumbColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.hovered)
                  ? CX.lineStrong
                  : CX.line,
            ),
            thickness: const WidgetStatePropertyAll(6),
            radius: const Radius.circular(999),
            crossAxisMargin: 2,
            mainAxisMargin: 4,
          ),
        ),
        initialRoute: '/login',
        routes: {
          '/login': (context) => const LoginScreen(),
          '/login?mode=lud': (context) => const LoginScreen(),
          '/login?mode=local': (context) => const LoginScreen(),
          '/auth-lud': (context) => const _PostAuthRedirect(localMode: false),
          '/auth-local': (context) => const _PostAuthRedirect(localMode: true),
          '/access': (context) => const AccessGateScreen(),
          '/local-setup': (context) => const LocalCoachSetupScreen(),
          '/local-home': (context) => const _LocalHomeRoute(),
          '/local-team': (context) => const _LocalHomeRoute(initialIndex: 0),
          '/local-tactica': (context) => const _LocalHomeRoute(initialIndex: 1),
          '/local-calendar': (context) => const _LocalHomeRoute(initialIndex: 2),
          '/local-attendance': (context) => const _LocalHomeRoute(initialIndex: 3),
          '/local-lineups': (context) => const _LocalHomeRoute(initialIndex: 4),
          '/home': (context) => const _ProtectedHome(),
          '/preview-access': (context) => const _PreviewAccessRoute(),
          '/preview-home': (context) => const _PreviewHomeRoute(),
        },
      ),
    );
  }
}

class _PostAuthRedirect extends StatefulWidget {
  final bool localMode;

  const _PostAuthRedirect({required this.localMode});

  @override
  State<_PostAuthRedirect> createState() => _PostAuthRedirectState();
}

class _PostAuthRedirectState extends State<_PostAuthRedirect> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_finishAuthRedirect);
  }

  Future<void> _finishAuthRedirect() async {
    for (var attempt = 0; attempt < 20; attempt++) {
      if (!SupabaseAuthService.isConfigured ||
          SupabaseAuthService.currentSession != null) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (!mounted) return;
    if (SupabaseAuthService.isConfigured &&
        SupabaseAuthService.currentSession == null) {
      Navigator.pushReplacementNamed(context, '/login');
      return;
    }
    if (widget.localMode) {
      final localClubId =
          html.window.localStorage[_CanteraAppState._localClubKey];
      Navigator.pushReplacementNamed(
        context,
        localClubId == null || localClubId.isEmpty
            ? '/local-setup'
            : '/local-home',
      );
      return;
    }
    Navigator.pushReplacementNamed(context, '/access');
  }

  @override
  Widget build(BuildContext context) {
    return const _CalmLoadingScaffold();
  }
}

class _LocalHomeRoute extends StatelessWidget {
  final int initialIndex;

  const _LocalHomeRoute({this.initialIndex = 0});

  @override
  Widget build(BuildContext context) {
    if (SupabaseAuthService.isConfigured &&
        SupabaseAuthService.currentSession == null) {
      return const _AccessRedirect(route: '/login');
    }
    final localClubId =
        html.window.localStorage[_CanteraAppState._localClubKey];
    if (localClubId == null || localClubId.isEmpty) {
      return const _AccessRedirect(route: '/local-setup');
    }
    return _LocalHomeGuard(
      localClubId: localClubId,
      child: _CloudDocGate(
        clubId: localClubId,
        child: MainShell(initialIndex: initialIndex),
      ),
    );
  }
}

/// Ensures the club actually loaded into app state is the user's own manual
/// club before rendering the No-LUD shell. Self-heals a stale
/// `fobal_active_club_id` left over from a LUD session on the same browser
/// (root cause of LUD data — e.g. a "Sub 20" category — leaking into the
/// No-LUD flow); mirrors what [_MembershipHydrator] already does for LUD.
class _LocalHomeGuard extends StatefulWidget {
  final String localClubId;
  final Widget child;

  const _LocalHomeGuard({required this.localClubId, required this.child});

  @override
  State<_LocalHomeGuard> createState() => _LocalHomeGuardState();
}

class _LocalHomeGuardState extends State<_LocalHomeGuard> {
  bool _switching = false;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final needsSwitch = clubNeedsManualSwitch(
      loadedClub: scope.fullClub,
      requiredManualClubId: widget.localClubId,
    );
    if (needsSwitch) {
      if (!_switching) {
        _switching = true;
        final corrected = scope.loadClub(widget.localClubId);
        // Deferred: updateClub triggers setState on the ancestor
        // _CanteraAppState, which must not happen synchronously mid-build.
        Future<void>.microtask(() {
          if (mounted) scope.updateClub(corrected);
        });
      }
      return const _CalmLoadingScaffold();
    }
    _switching = false;
    return widget.child;
  }
}

/// Phase 2a (read-only) cloud pull for the No-LUD flow, which has no
/// [_MembershipHydrator]. Renders the shell immediately and adopts the stored
/// document in the background if one exists and there is no unsynced local
/// work. Does nothing when there is no cloud document — the common case today —
/// so the app behaves exactly as before.
class _CloudDocGate extends StatefulWidget {
  final String clubId;
  final Widget child;

  const _CloudDocGate({required this.clubId, required this.child});

  @override
  State<_CloudDocGate> createState() => _CloudDocGateState();
}

class _CloudDocGateState extends State<_CloudDocGate> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_sync);
  }

  Future<void> _sync() async {
    if (ClubSyncService.isDirty(widget.clubId)) return;
    try {
      final doc = await ClubSyncService.pull(widget.clubId);
      if (!mounted || doc == null) return;
      if (doc.club.id != widget.clubId) return;
      if (doc.version <= ClubSyncService.knownServerVersion(widget.clubId)) {
        return;
      }
      AppScope.of(context).adoptClub(doc.club);
      ClubSyncService.rememberVersion(widget.clubId, doc.version);
    } catch (_) {
      // Offline / transient: keep the local copy.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _PreviewAccessRoute extends StatelessWidget {
  const _PreviewAccessRoute();

  @override
  Widget build(BuildContext context) {
    if (!PreviewAccessService.isGranted) {
      return const _AccessRedirect(route: '/login');
    }
    return const AccessGateScreen(forcePreview: true);
  }
}

class _PreviewHomeRoute extends StatelessWidget {
  const _PreviewHomeRoute();

  @override
  Widget build(BuildContext context) {
    if (!PreviewAccessService.isGranted) {
      return const _AccessRedirect(route: '/login');
    }
    return const MainShell();
  }
}

class _ProtectedHome extends StatefulWidget {
  const _ProtectedHome();

  @override
  State<_ProtectedHome> createState() => _ProtectedHomeState();
}

class _ProtectedHomeState extends State<_ProtectedHome> {
  late final Future<ClubMembership?> _membership =
      ClubAccessService.activeMembership();

  @override
  Widget build(BuildContext context) {
    if (!SupabaseAuthService.isConfigured) return const MainShell();
    if (SupabaseAuthService.currentSession == null) {
      return const _AccessRedirect(route: '/login');
    }
    return FutureBuilder<ClubMembership?>(
      future: _membership,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _CalmLoadingScaffold();
        }
        if (snapshot.data == null) {
          return const _AccessRedirect(route: '/access');
        }
        return _MembershipHydrator(
          membership: snapshot.data!,
          child: const MainShell(),
        );
      },
    );
  }
}

class _MembershipHydrator extends StatefulWidget {
  final ClubMembership membership;
  final Widget child;

  const _MembershipHydrator({required this.membership, required this.child});

  @override
  State<_MembershipHydrator> createState() => _MembershipHydratorState();
}

class _MembershipHydratorState extends State<_MembershipHydrator> {
  String? _hydratedClubId;
  bool _hydrating = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hydratedClubId == widget.membership.clubId || _hydrating) return;
    _hydrating = true;
    Future<void>.microtask(_hydrate);
  }

  Future<void> _hydrate() async {
    final scope = AppScope.of(context);
    ClubAccessService.selectActiveMembership(widget.membership);

    // Phase 2a (read-only): adopt the stored cloud document before the LUD /
    // shared-record overlay runs on top of it. Never pushes, never backfills,
    // never overwrites unsynced local work.
    final clubId = widget.membership.clubId;
    if (!ClubSyncService.isDirty(clubId)) {
      try {
        final doc = await ClubSyncService.pull(clubId);
        if (mounted &&
            doc != null &&
            doc.club.id == clubId &&
            doc.version > ClubSyncService.knownServerVersion(clubId)) {
          scope.adoptClub(doc.club);
          ClubSyncService.rememberVersion(clubId, doc.version);
        }
      } catch (_) {
        // Offline / transient: fall through and hydrate from local as before.
      }
    }

    final localClub = scope.loadClub(widget.membership.clubId);

    CanteraClubContext? contextData;
    try {
      contextData = await ClubAccessService.loadClubContext(widget.membership);
    } catch (_) {
      contextData = null;
    }
    if (!mounted) return;

    List<ClubTacticalRecord> sharedRecords = const [];
    try {
      sharedRecords = await ClubAccessService.loadTacticalData(limit: 100);
    } catch (_) {
      sharedRecords = const [];
    }
    if (!mounted) return;

    Methodology? sharedMethodology;
    for (final record in sharedRecords) {
      if (record.type != 'methodology') continue;
      final raw = record.content['methodology'];
      if (raw is Map) {
        sharedMethodology = Methodology.fromJson(
          Map<String, dynamic>.from(raw),
        );
        break;
      }
    }

    final basePlayers = contextData == null
        ? localClub.players
        : preservePlayerProfiles(
            incoming: contextData.players,
            existing: localClub.players,
          );

    scope.updateClub(
      localClub.copyWith(
        id: widget.membership.clubId,
        name: contextData?.teamName.isNotEmpty == true
            ? contextData!.teamName
            : widget.membership.clubName,
        league: widget.membership.ludTeamId == null
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
        methodology: localClub.methodology.playingStyle.trim().isNotEmpty
            ? localClub.methodology
            : sharedMethodology ?? localClub.methodology,
        players: applyRemotePlayerProfiles(
          players: basePlayers,
          records: sharedRecords,
        ),
      ),
    );
    final allCategories = contextData?.categories ?? localClub.categories;
    final categories = widget.membership.accessibleCategories(allCategories);
    await ClubAccessService.prewarmPrimaryLeagueData(
      membership: widget.membership,
      categories: categories,
    );
    unawaited(
      ClubAccessService.prewarmAllLeagueData(
        membership: widget.membership,
        categories: categories,
      ),
    );
    scope.selectRole(
      widget.membership.isClubAdmin
          ? UserRole.coordinator
          : widget.membership.role == 'viewer'
          ? UserRole.viewer
          : UserRole.coach,
    );
    if (!widget.membership.isClubAdmin && categories.isNotEmpty) {
      final stored = html.window
          .localStorage['fobal_selected_category_${widget.membership.clubId}'];
      final storedValid =
          stored != null && categories.any((category) => category.id == stored);
      if (storedValid) {
        // Honour the coach's explicit pick for this club.
        scope.selectCategory(stored);
      } else if (stored == null || stored.isEmpty) {
        // No pick yet: seed with the first accessible category.
        scope.selectCategory(categories.first.id);
      }
      // A stored pick that is not in the current (possibly partial) list is
      // left untouched: never silently downgrade it to "the first category".
    }
    if (!mounted) return;
    setState(() {
      _hydratedClubId = widget.membership.clubId;
      _hydrating = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hydratedClubId != widget.membership.clubId) {
      return const _CalmLoadingScaffold();
    }
    return widget.child;
  }
}

class _AccessRedirect extends StatelessWidget {
  final String route;
  const _AccessRedirect({required this.route});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) Navigator.pushReplacementNamed(context, route);
    });
    return const _CalmLoadingScaffold();
  }
}

class _CalmLoadingScaffold extends StatelessWidget {
  const _CalmLoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CX.bg,
      body: const Center(child: _MinimalAppLoader()),
    );
  }
}

class _MinimalAppLoader extends StatelessWidget {
  const _MinimalAppLoader();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: .96, end: 1),
      duration: CX.motionSlow,
      curve: CX.curve,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(.0, 1.0),
          child: Transform.scale(scale: value, child: child),
        );
      },
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: CX.panel.withValues(alpha: .74),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: CX.line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x120D1A14),
              blurRadius: 28,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: CX.green.withValues(alpha: .35)),
              ),
              child: const CustomPaint(painter: FobalMarkPainter()),
            ),
            const SizedBox(height: 14),
            const Text(
              'fobal',
              style: TextStyle(
                color: CX.white,
                fontSize: 22,
                fontWeight: FontWeight.w300,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Cargando',
              style: TextStyle(
                color: CX.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: .08, end: 1),
              duration: Duration(milliseconds: 1800),
              curve: Curves.easeInOutCubic,
              builder: (context, value, _) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 2,
                    color: CX.green,
                    backgroundColor: CX.line,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows a single-field text dialog and returns the trimmed value (or null if
/// cancelled). The dialog owns its [TextEditingController] for its whole
/// lifetime, so the controller is never disposed while the close animation is
/// still running (which was crashing the calling section).
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String? hintText,
  String? labelText,
  int minLines = 1,
  int maxLines = 4,
  String confirmLabel = 'Guardar',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextPromptDialog(
      title: title,
      initialValue: initialValue,
      hintText: hintText,
      labelText: labelText,
      minLines: minLines,
      maxLines: maxLines,
      confirmLabel: confirmLabel,
    ),
  );
}

class _TextPromptDialog extends StatefulWidget {
  final String title;
  final String initialValue;
  final String? hintText;
  final String? labelText;
  final int minLines;
  final int maxLines;
  final String confirmLabel;

  const _TextPromptDialog({
    required this.title,
    required this.initialValue,
    required this.hintText,
    required this.labelText,
    required this.minLines,
    required this.maxLines,
    required this.confirmLabel,
  });

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          decoration: InputDecoration(
            hintText: widget.hintText,
            labelText: widget.labelText,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Shared "Importar datos" flow: pick a file, confirm the replacement, then
/// swap the active space. Used from the club menu (both LUD and No-LUD) and
/// from Configurar.
Future<void> importClubFromFile(BuildContext context) async {
  final scope = AppScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  CanteraClub incoming;
  try {
    incoming = await ClubBackupService.pickAndParse();
  } on ClubBackupException catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error.message)));
    return;
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('No pudimos leer el archivo. Probá de nuevo.')),
    );
    return;
  }
  if (!context.mounted) return;
  final name = incoming.name.trim().isEmpty ? 'sin nombre' : incoming.name.trim();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Importar datos'),
      content: Text(
        'Vas a reemplazar los datos actuales de este espacio con los del '
        'archivo ($name: ${incoming.categories.length} categorías, '
        '${incoming.players.length} jugadores). Esta acción no se puede deshacer.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Importar'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  scope.replaceClub(incoming);
  messenger.showSnackBar(
    const SnackBar(content: Text('Datos importados.')),
  );
}

class CanteraScrollBehavior extends MaterialScrollBehavior {
  const CanteraScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const _CanteraScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }
}

class _CanteraScrollPhysics extends ClampingScrollPhysics {
  const _CanteraScrollPhysics({super.parent});

  @override
  _CanteraScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _CanteraScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    return super.applyPhysicsToUserOffset(position, offset * .62);
  }

  @override
  double carriedMomentum(double existingVelocity) => 0;
}

class _CanteraPageTransitionsBuilder extends PageTransitionsBuilder {
  const _CanteraPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: CX.curve);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, .025),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

class CanteraMotion {
  const CanteraMotion._();

  /// Wraps each visible child in a short staggered fade + rise. Call sites are
  /// unchanged; small spacer [SizedBox]es pass through untouched so the stagger
  /// index tracks real rows and the final layout is identical.
  static List<Widget> stagger(
    List<Widget> children, {
    int intervalMs = 34,
    double distance = 10,
  }) {
    final out = <Widget>[];
    var revealIndex = 0;
    for (final child in children) {
      final isSpacer = child is SizedBox &&
          child.child == null &&
          (child.height ?? 0) <= 40 &&
          (child.width ?? 0) <= 40;
      if (isSpacer) {
        out.add(child);
        continue;
      }
      // Only the first rows stagger; anything that mounts later (lazy list rows
      // scrolled into view) appears at once so it never flashes blank.
      final delayMs = revealIndex < 8 ? intervalMs * revealIndex : 0;
      out.add(
        _StaggeredReveal(
          delay: Duration(milliseconds: delayMs),
          distance: distance,
          child: child,
        ),
      );
      revealIndex++;
    }
    return out;
  }
}

class _StaggeredReveal extends StatefulWidget {
  final Duration delay;
  final double distance;
  final Widget child;

  const _StaggeredReveal({
    required this.delay,
    required this.distance,
    required this.child,
  });

  @override
  State<_StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<_StaggeredReveal> {
  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _visible = true;
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) setState(() => _visible = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Honour the OS "reduce motion" setting: show the row as-is, no delay.
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return widget.child;
    }
    final offset = _visible ? Offset.zero : Offset(0, widget.distance / 100);
    return AnimatedSlide(
      offset: offset,
      duration: CX.motion,
      curve: CX.curve,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: CX.motion,
        curve: CX.curve,
        child: widget.child,
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  final int initialIndex;

  const MainShell({super.key, this.initialIndex = 0});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _currentIndex = widget.initialIndex;
  final PageStorageBucket _pageStorageBucket = PageStorageBucket();
  final GlobalKey<TacticaScreenState> _tacticaKey = GlobalKey();

  // Consume-once payloads for section-to-section actions (datos -> lectura ->
  // decisión -> sección). Held in memory only.
  SessionFocusHandoff? _pendingSessionFocus;
  MatchPrepHandoff? _pendingMatchPrep;
  LineupHint? _pendingLineupHint;

  int _indexOfScreen<T>() {
    final scope = AppScope.of(context);
    final external = _isExternalClub(scope.fullClub);
    final screens = external
        ? _enabledExternalLabels(scope.fullClub).map(_screenForLabel).toList()
        : _screens(scope.role, external);
    final index = screens.indexWhere((widget) => widget is T);
    return index < 0 ? 0 : index;
  }

  /// Planificar sub-tab index inside TacticaScreen (Asistencia is hidden for
  /// external clubs, shifting the planner one slot left).
  int _plannerSubSection() =>
      _isExternalClub(AppScope.of(context).fullClub) ? 1 : 2;

  void _openTacticaSub(int sub) {
    _setIndex(_indexOfScreen<TacticaScreen>());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tacticaKey.currentState?.selectSection(sub);
    });
  }

  void _openPlannerWithFocus(SessionFocusHandoff focus) {
    _pendingSessionFocus = focus;
    _openTacticaSub(_plannerSubSection());
  }

  void _openMatchPrep(MatchPrepHandoff prep) {
    _pendingMatchPrep = prep;
    _openTacticaSub(_plannerSubSection());
  }

  void _openLineup([LineupHint? hint]) {
    _pendingLineupHint = hint;
    _setIndex(_indexOfScreen<AlineacionScreen>());
  }

  void _openSection(ShellSection section) {
    final external = _isExternalClub(AppScope.of(context).fullClub);
    switch (section) {
      case ShellSection.myTeam:
        if (external) {
          _setIndex(_indexOfScreen<MiEquipoScreen>());
        } else {
          _openTacticaSub(0); // Plantel sub-tab
        }
      case ShellSection.planner:
        _openTacticaSub(_plannerSubSection());
      case ShellSection.calendar:
        _setIndex(_indexOfScreen<CalendarioScreen>());
      case ShellSection.attendance:
        if (external) {
          _setIndex(_indexOfScreen<AsistenciaScreen>());
        } else {
          _openTacticaSub(1); // Asistencia sub-tab
        }
      case ShellSection.stats:
        _setIndex(_indexOfScreen<EstadisticasScreen>());
      case ShellSection.lineup:
        _setIndex(_indexOfScreen<AlineacionScreen>());
    }
  }

  SessionFocusHandoff? _takeSessionFocus() {
    final value = _pendingSessionFocus;
    _pendingSessionFocus = null;
    return value;
  }

  MatchPrepHandoff? _takeMatchPrep() {
    final value = _pendingMatchPrep;
    _pendingMatchPrep = null;
    return value;
  }

  LineupHint? _takeLineupHint() {
    final value = _pendingLineupHint;
    _pendingLineupHint = null;
    return value;
  }

  static const _allItems = <_ShellItem>[
    _ShellItem(Icons.space_dashboard_outlined, Icons.space_dashboard, 'Inicio'),
    _ShellItem(Icons.shield_outlined, Icons.shield, 'Mi equipo'),
    _ShellItem(
      Icons.sports_soccer_outlined,
      Icons.sports_soccer,
      'Táctica',
    ),
    _ShellItem(Icons.calendar_month_outlined, Icons.calendar_month, 'Calendario'),
    _ShellItem(Icons.fact_check_outlined, Icons.fact_check, 'Asistencia'),
    _ShellItem(Icons.bar_chart_outlined, Icons.bar_chart, 'Estadísticas'),
    _ShellItem(Icons.settings_outlined, Icons.settings, 'Configurar'),
    _ShellItem(
      Icons.view_module_outlined,
      Icons.view_module,
      'Alineación & citaciones',
    ),
  ];

  void _goTo(int index) {
    final role = AppScope.of(context).role;
    if (index >= 1 && index <= 3) {
      _tacticaKey.currentState?.selectSection(index - 1);
    }
    if (role == UserRole.coordinator) {
      final target = switch (index) {
        0 => 0,
        >= 1 && <= 3 => 1,
        4 => 3,
        5 => 4,
        _ => null,
      };
      if (target != null) _setIndex(target);
      return;
    }
    final target = role == UserRole.viewer
        ? switch (index) {
            0 => 0,
            1 => 1,
            2 => 1,
            3 => 1,
            _ => null,
          }
        : switch (index) {
            0 => 0,
            1 => 1,
            2 => 1,
            3 => 1,
            4 => 3,
            5 => 3,
            _ => null,
          };
    if (target != null) _setIndex(target);
  }

  void _selectNavigation(int index) {
    _setIndex(index);
  }

  void _installPwa() {
    html.window.dispatchEvent(html.CustomEvent('cantera-install-pwa'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Si el navegador lo permite, se abre la instalación.'),
      ),
    );
  }

  void _setIndex(int index) {
    final scope = AppScope.of(context);
    final external = _isExternalClub(scope.fullClub);
    final maxIndex = external
        ? (_enabledExternalLabels(scope.fullClub).length - 1).clamp(0, 999)
        : (_screens(scope.role, false).length - 1).clamp(0, 999);
    final next = index.clamp(0, maxIndex).toInt();
    if (next == _currentIndex) return;
    setState(() {
      _currentIndex = next;
    });
  }

  void _switchClub() {
    final scope = AppScope.of(context);
    Navigator.pushReplacementNamed(
      context,
      _isExternalClub(scope.fullClub) ? '/login?mode=local' : '/access',
    );
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text(
          'Se cierra tu acceso actual. Los datos del club quedan guardados y separados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await SupabaseAuthService.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  bool _isExternalClub(CanteraClub club) => club.isManualClub;

  List<String> _enabledExternalLabels(CanteraClub club) {
    const fallback = [
      'Inicio',
      'Mi equipo',
      'Táctica',
      'Calendario',
      'Asistencia',
      'Estadísticas',
      'Alineación & citaciones',
    ];
    return fallback;
  }

  Widget _screenForLabel(String label) => switch (label) {
    'Inicio' => HomeScreen(onNavigate: _goTo),
    'Mi equipo' => const MiEquipoScreen(),
    'Táctica' => TacticaScreen(key: _tacticaKey),
    'Calendario' => const CalendarioScreen(),
    'Asistencia' => const AsistenciaScreen(),
    'Estadísticas' => const EstadisticasScreen(),
    'Alineación & citaciones' => AlineacionScreen(onBack: () => _goTo(0)),
    _ => const MiEquipoScreen(),
  };

  List<Widget> _screens(UserRole role, bool external) => [
      if (external) const MiEquipoScreen() else HomeScreen(onNavigate: _goTo),
      TacticaScreen(key: _tacticaKey),
      if (external) const CalendarioScreen(),
      if (!external) const EstadisticasScreen(),
      if (!external && role == UserRole.coordinator)
        const ConfiguracionClubScreen(),
      if (role != UserRole.viewer) AlineacionScreen(onBack: () => _goTo(0)),
    ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 980;
    final scope = AppScope.of(context);
    final role = scope.role;
    final external = _isExternalClub(scope.fullClub);
    final externalLabels = external ? _enabledExternalLabels(scope.fullClub) : const <String>[];
    final items = external
        ? [
            _allItems[0],
            _allItems[1],
            _allItems[2],
            _allItems[3],
            _allItems[4],
            _allItems[5],
            _allItems[7],
          ].where((item) => externalLabels.contains(item.label)).toList()
        : switch (role) {
            UserRole.viewer => [_allItems[0], _allItems[2], _allItems[5]],
      UserRole.coach => [
        _allItems[0],
        _allItems[2],
        _allItems[5],
        _allItems[7],
            ],
            UserRole.coordinator => [
              _allItems[0],
              _allItems[2],
              _allItems[5],
              _allItems[6],
              _allItems[7],
            ],
          };
    final screens = external
        ? externalLabels.map(_screenForLabel).toList()
        : _screens(role, external);
    final selectedIndex = _currentIndex.clamp(0, items.length - 1).toInt();
    if (_currentIndex != selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _currentIndex = selectedIndex);
      });
    }

    final Widget shell = desktop
        ? Scaffold(
            backgroundColor: CX.bg,
            body: Row(
              children: [
                _DesktopSidebar(
                  selectedIndex: selectedIndex,
                  items: items,
                  onSelected: _selectNavigation,
                  onSwitchClub: _switchClub,
                  onSignOut: _signOut,
                  onInstallPwa: _installPwa,
                ),
                Expanded(
                  child: Container(
                    color: CX.canvas,
                    child: PageStorage(
                      bucket: _pageStorageBucket,
                      child: _AnimatedShellStack(
                        selectedIndex: selectedIndex,
                        children: screens,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        : _mobileShell(context, screens, selectedIndex, items, role);

    return ShellActions(
      openPlannerWithFocus: _openPlannerWithFocus,
      openMatchPrep: _openMatchPrep,
      openLineup: _openLineup,
      openSection: _openSection,
      takeSessionFocus: _takeSessionFocus,
      takeMatchPrep: _takeMatchPrep,
      takeLineupHint: _takeLineupHint,
      child: shell,
    );
  }

  Widget _mobileShell(
    BuildContext context,
    List<Widget> screens,
    int selectedIndex,
    List<_ShellItem> items,
    UserRole role,
  ) {
    return Scaffold(
      body: PageStorage(
        bucket: _pageStorageBucket,
        child: _AnimatedShellStack(
          selectedIndex: selectedIndex,
          children: screens,
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (role != UserRole.coordinator &&
              ClubAccessService.accessibleCategories(
                AppScope.of(context).fullClub.categories,
              ).isNotEmpty)
            _MobileCategoryScopeBar(),
          if (SupabaseAuthService.currentEmail != null)
            _MobileClubContextBar(
              onSwitchClub: _switchClub,
              onSignOut: _signOut,
              onInstallPwa: _installPwa,
            ),
          DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: CX.line)),
            ),
            child: NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: _selectNavigation,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: items
                  .map(
                    (item) => NavigationDestination(
                      icon: Icon(item.icon, color: CX.faint, size: 21),
                      selectedIcon: Icon(
                        item.activeIcon,
                        color: CX.green,
                        size: 21,
                      ),
                      label: item.shortLabel,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  final int selectedIndex;
  final List<_ShellItem> items;
  final ValueChanged<int> onSelected;
  final VoidCallback onSwitchClub;
  final Future<void> Function() onSignOut;
  final VoidCallback onInstallPwa;

  const _DesktopSidebar({
    required this.selectedIndex,
    required this.items,
    required this.onSelected,
    required this.onSwitchClub,
    required this.onSignOut,
    required this.onInstallPwa,
  });

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final clubName = scope.club.name == 'Club Demo'
        ? 'Espacio de trabajo'
        : scope.club.name;
    return Container(
      width: 248,
      decoration: const BoxDecoration(
        color: CX.bg,
        border: Border(right: BorderSide(color: CX.line)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 22, 14, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: _BrandMark(compact: false),
              ),
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    ClubCrest(logoUrl: scope.club.logoUrl, size: 30),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        clubName.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: CX.faint,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    if (scope.role == UserRole.viewer)
                      const Tooltip(
                        message: 'Acceso de solo lectura',
                        child: Icon(
                          Icons.visibility_outlined,
                          color: CX.blue,
                          size: 16,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: _DataStatusChip(),
              ),
              if (scope.role != UserRole.coordinator &&
                  ClubAccessService.accessibleCategories(
                    scope.fullClub.categories,
                  ).isNotEmpty) ...[
                const SizedBox(height: 12),
                _CategoryScopeSelector(
                  categories: ClubAccessService.accessibleCategories(
                    scope.fullClub.categories,
                  ),
                  selectedCategoryId: scope.selectedCategoryId,
                  onChanged: scope.selectCategory,
                ),
              ],
              const SizedBox(height: 8),
              ...List.generate(items.length, (index) {
                final item = items[index];
                final selected = index == selectedIndex;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _DesktopNavTile(
                    item: item,
                    selected: selected,
                    onTap: () => onSelected(index),
                  ),
                );
              }),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: onInstallPwa,
                icon: const Icon(Icons.install_mobile, size: 17),
                label: const Text('Instalar app'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => ClubBackupService.downloadJson(
                        AppScope.of(context).fullClub,
                      ),
                      icon: const Icon(Icons.download_outlined, size: 15),
                      label: const Text(
                        'Exportar',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => importClubFromFile(context),
                      icon: const Icon(Icons.upload_outlined, size: 15),
                      label: const Text(
                        'Importar',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: CX.panelDecoration(),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: CX.greenDark,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.person_outline,
                            color: CX.green,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _roleLabel(scope.role),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                SupabaseAuthService.currentEmail ?? 'Cuenta local',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: CX.faint,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (SupabaseAuthService.currentEmail == null) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 36,
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              Navigator.pushReplacementNamed(context, '/login'),
                          icon: const Icon(Icons.login, size: 16),
                          label: const Text('Iniciar sesión'),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: IconButton.outlined(
                              tooltip: 'Cambiar club',
                              onPressed: onSwitchClub,
                              icon: const Icon(Icons.swap_horiz, size: 18),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: IconButton.outlined(
                              tooltip: 'Cerrar sesión',
                              onPressed: onSignOut,
                              icon: const Icon(Icons.logout, size: 18),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopNavTile extends StatefulWidget {
  final _ShellItem item;
  final bool selected;
  final VoidCallback onTap;

  const _DesktopNavTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_DesktopNavTile> createState() => _DesktopNavTileState();
}

class _DesktopNavTileState extends State<_DesktopNavTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _hovered;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: CX.motionFast,
          curve: CX.curve,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: widget.selected
                ? CX.greenDark
                : _hovered
                ? CX.panel
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: widget.selected
                  ? CX.green.withValues(alpha: .26)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              AnimatedScale(
                duration: CX.motionFast,
                curve: CX.curve,
                scale: widget.selected ? 1.08 : 1,
                child: Icon(
                  widget.selected ? widget.item.activeIcon : widget.item.icon,
                  color: widget.selected
                      ? CX.green
                      : active
                      ? CX.white
                      : CX.faint,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedDefaultTextStyle(
                  duration: CX.motionFast,
                  curve: CX.curve,
                  style: TextStyle(
                    color: widget.selected
                        ? CX.white
                        : active
                        ? CX.white
                        : CX.muted,
                    fontWeight: widget.selected
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                  child: Text(widget.item.label),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryScopeSelector extends StatelessWidget {
  final List<CategorySquad> categories;
  final String? selectedCategoryId;
  final ValueChanged<String?> onChanged;

  const _CategoryScopeSelector({
    required this.categories,
    required this.selectedCategoryId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = categories.any((item) => item.id == selectedCategoryId)
        ? selectedCategoryId
        : categories.first.id;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: CX.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CX.green.withValues(alpha: .24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MI CATEGORÍA',
            style: TextStyle(
              color: CX.green,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: selected,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
            ),
            items: categories
                .map(
                  (category) => DropdownMenuItem(
                    value: category.id,
                    child: Text(category.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: onChanged,
          ),
          const SizedBox(height: 7),
          const Text(
            'La app muestra solo esta categoría.',
            style: TextStyle(color: CX.faint, fontSize: 10, height: 1.25),
          ),
        ],
      ),
    );
  }
}

class _AnimatedShellStack extends StatelessWidget {
  final int selectedIndex;
  final List<Widget> children;

  const _AnimatedShellStack({
    required this.selectedIndex,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey('shell-screen-$selectedIndex'),
      child: children[selectedIndex],
    );
  }
}

class _MobileClubContextBar extends StatelessWidget {
  final VoidCallback onSwitchClub;
  final Future<void> Function() onSignOut;
  final VoidCallback onInstallPwa;

  const _MobileClubContextBar({
    required this.onSwitchClub,
    required this.onSignOut,
    required this.onInstallPwa,
  });

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Material(
      color: CX.bg,
      child: SafeArea(
        top: false,
        bottom: false,
        child: SizedBox(
          height: 42,
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 6),
            child: Row(
              children: [
                ClubCrest(logoUrl: scope.club.logoUrl, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    scope.club.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CX.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const _DataStatusChip(compact: true),
                PopupMenuButton<String>(
                  tooltip: 'Opciones del club',
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (value) {
                    if (value == 'club') onSwitchClub();
                    if (value == 'install') onInstallPwa();
                    if (value == 'logout') onSignOut();
                    if (value == 'export') {
                      ClubBackupService.downloadJson(
                        AppScope.of(context).fullClub,
                      );
                    }
                    if (value == 'import') importClubFromFile(context);
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'install',
                      child: ListTile(
                        leading: Icon(Icons.install_mobile),
                        title: Text('Instalar app'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'export',
                      child: ListTile(
                        leading: Icon(Icons.download_outlined),
                        title: Text('Exportar datos'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'import',
                      child: ListTile(
                        leading: Icon(Icons.upload_outlined),
                        title: Text('Importar datos'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'club',
                      child: ListTile(
                        leading: Icon(Icons.swap_horiz),
                        title: Text('Cambiar club'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'logout',
                      child: ListTile(
                        leading: Icon(Icons.logout),
                        title: Text('Cerrar sesión'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _roleLabel(UserRole role) => switch (role) {
  UserRole.coordinator => 'Coordinador',
  UserRole.coach => 'Entrenador',
  UserRole.viewer => 'Solo lectura',
};

String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.isNegative || diff.inMinutes < 1) return 'recién';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  return 'hace ${diff.inDays} d';
}

/// Single, consistent read on where the coach's data stands: offline, saving,
/// or synced (with how long ago). Backed by the real offline queue and the
/// browser's connectivity, so it never claims "synced" while writes are stuck.
class _DataStatusChip extends StatefulWidget {
  final bool compact;
  const _DataStatusChip({this.compact = false});

  @override
  State<_DataStatusChip> createState() => _DataStatusChipState();
}

class _DataStatusChipState extends State<_DataStatusChip> {
  final _subs = <StreamSubscription<dynamic>>[];
  bool _online = true;
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    _online = html.window.navigator.onLine ?? true;
    _pending = OfflineMutationService.instance.queue.length;
    _subs.add(
      html.window.onOnline.listen((_) {
        if (mounted) setState(() => _online = true);
      }),
    );
    _subs.add(
      html.window.onOffline.listen((_) {
        if (mounted) setState(() => _online = false);
      }),
    );
    _subs.add(
      OfflineMutationService.instance.queueStream.listen((queue) {
        if (mounted) setState(() => _pending = queue.length);
      }),
    );
    _subs.add(
      ClubSyncService.events.listen((_) {
        if (mounted) setState(() {});
      }),
    );
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clubId = AppScope.of(context).fullClub.id;
    final dirty = ClubSyncService.isDirty(clubId);
    final syncedAt = ClubSyncService.lastPushedAt(clubId) ??
        DateTime.tryParse(AppScope.of(context).club.syncedAt);
    final (IconData icon, Color color, String text) = !_online
        ? (Icons.cloud_off_outlined, CX.amber, 'Trabajando sin conexión')
        : (_pending > 0 || dirty)
        ? (Icons.sync, CX.blue, 'Guardando cambios…')
        : (
            Icons.cloud_done_outlined,
            CX.green,
            syncedAt == null
                ? 'Sincronizado'
                : 'Sincronizado · ${_relativeTime(syncedAt)}',
          );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: widget.compact ? 10 : 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _BrandMark extends StatelessWidget {
  final bool compact;
  const _BrandMark({required this.compact});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 34 : 38,
          height: compact ? 34 : 38,
          decoration: BoxDecoration(
            color: const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: CX.green.withValues(alpha: .45)),
            boxShadow: [
              BoxShadow(color: CX.green.withValues(alpha: .18), blurRadius: 14),
            ],
          ),
          child: const CustomPaint(painter: FobalMarkPainter()),
        ),
        const SizedBox(width: 10),
        Text(
          'fobal',
          style: TextStyle(
            color: CX.white,
            fontSize: compact ? 21 : 23,
            fontWeight: FontWeight.w300,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

/// The fobal mark: a goal frame with two players at its base. One drawing
/// routine shared by the login screen, the loading splash and the shell
/// brand badge so the mark stays identical everywhere instead of drifting
/// between hand-copied CustomPainters.
void paintFobalMark(Canvas canvas, Size size, {Color color = CX.green}) {
  final w = size.width;
  final h = size.height;
  final line = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = w * .09
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final dot = Paint()..color = color;

  final frame = Path()
    ..moveTo(w * .27, h * .64)
    ..lineTo(w * .27, h * .22)
    ..lineTo(w * .73, h * .22)
    ..lineTo(w * .73, h * .64);
  canvas.drawPath(frame, line);

  canvas.drawCircle(Offset(w * .38, h * .76), w * .075, dot);
  canvas.drawCircle(Offset(w * .62, h * .76), w * .075, dot);
}

class FobalMarkPainter extends CustomPainter {
  final Color color;
  const FobalMarkPainter({this.color = CX.green});

  @override
  void paint(Canvas canvas, Size size) => paintFobalMark(canvas, size, color: color);

  @override
  bool shouldRepaint(covariant FobalMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}

class ClubCrest extends StatelessWidget {
  final String logoUrl;
  final double size;

  const ClubCrest({super.key, required this.logoUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    final imageUrl = _proxiedLogoUrl(logoUrl);
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: CX.panel2,
        shape: BoxShape.circle,
        border: Border.all(color: CX.green.withValues(alpha: .28)),
      ),
      child: imageUrl.isEmpty
          ? Icon(Icons.shield_outlined, size: size * .58, color: CX.green)
          : Image.network(
              imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Icon(
                Icons.shield_outlined,
                size: size * .58,
                color: CX.green,
              ),
            ),
    );
  }

  String _proxiedLogoUrl(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return '';
    if (clean.contains('PLAYA_HONDA_UNIVERSITARIO.png')) {
      return '/club-crests/playa_honda_universitario.png';
    }
    if (clean.startsWith('https://lud-escudos.s3.us-east-1.amazonaws.com/')) {
      return '/api/club-crest?url=${Uri.encodeComponent(clean)}';
    }
    return clean;
  }
}

class _MobileCategoryScopeBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final categories = ClubAccessService.accessibleCategories(
      scope.fullClub.categories,
    );
    final selected =
        categories.any((item) => item.id == scope.selectedCategoryId)
        ? scope.selectedCategoryId
        : categories.first.id;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        color: CX.bg,
        border: Border(top: BorderSide(color: CX.line)),
      ),
      child: DropdownButtonFormField<String>(
        value: selected,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Mi categoría',
          isDense: true,
          prefixIcon: Icon(Icons.groups_2_outlined),
        ),
        items: categories
            .map(
              (category) => DropdownMenuItem(
                value: category.id,
                child: Text(category.name, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: scope.selectCategory,
      ),
    );
  }
}

class _ShellItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _ShellItem(this.icon, this.activeIcon, this.label);

  String get shortLabel => switch (label) {
    'Inteligencia' => 'Intel.',
    'Configurar' => 'Config.',
    'Alineación & citaciones' => 'Alineación',
    _ => label,
  };
}

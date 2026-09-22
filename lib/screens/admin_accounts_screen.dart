import 'package:flutter/material.dart';

import '../main.dart';
import '../services/admin_accounts_service.dart';
import '../services/supabase_auth_service.dart';
import '../ui/ui_kit.dart';

/// Platform-admin panel: every registered account, LUD or manual, with a
/// single action — ban / unban. Reachable only via the PIN doorway; every
/// read and write here is re-verified server-side against platform_admins.
class AdminAccountsScreen extends StatefulWidget {
  const AdminAccountsScreen({super.key});

  @override
  State<AdminAccountsScreen> createState() => _AdminAccountsScreenState();
}

class _AdminAccountsScreenState extends State<AdminAccountsScreen> {
  Future<List<AdminAccount>>? _future;
  Future<PlatformMetrics>? _metricsFuture;
  String _search = '';
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    if (SupabaseAuthService.currentSession != null) {
      _future = AdminAccountsService.listAccounts();
      _metricsFuture = AdminAccountsService.platformMetrics();
    }
  }

  void _onSignedIn() {
    // Straight into the panel — no detour through the app's normal
    // post-login routing (club selection, category picker, etc).
    setState(() {
      _future = AdminAccountsService.listAccounts();
      _metricsFuture = AdminAccountsService.platformMetrics();
    });
  }

  void _reload() {
    setState(() {
      _future = AdminAccountsService.listAccounts();
      _metricsFuture = AdminAccountsService.platformMetrics();
    });
  }

  Future<void> _toggleBan(AdminAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(account.banned ? 'Reactivar cuenta' : 'Desactivar cuenta'),
        content: Text(
          account.banned
              ? '${account.email} vuelve a poder iniciar sesión.'
              : '${account.email} no va a poder iniciar sesión hasta que la reactives.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(account.banned ? 'Reactivar' : 'Desactivar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy.add(account.userId));
    try {
      await AdminAccountsService.setBanned(account.userId, !account.banned);
      _reload();
    } on AdminAccountsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy.remove(account.userId));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (SupabaseAuthService.currentSession == null) {
      return Scaffold(
        backgroundColor: CX.bg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _AdminLoginForm(onSignedIn: _onSignedIn),
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: CX.bg,
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Administración'),
            Text(
              'Cuentas registradas',
              style: TextStyle(color: CX.faint, fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<AdminAccount>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is AdminAccountsException
                ? (snapshot.error as AdminAccountsException).message
                : 'No se pudo cargar el panel.';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: EmptyStatePanel(
                  icon: Icons.lock_outline,
                  title: 'No autorizado',
                  message: message,
                ),
              ),
            );
          }
          final accounts = snapshot.data ?? const <AdminAccount>[];
          final query = _search.trim().toLowerCase();
          final visible = query.isEmpty
              ? accounts
              : accounts
                    .where(
                      (a) =>
                          a.email.toLowerCase().contains(query) ||
                          a.fullName.toLowerCase().contains(query) ||
                          a.manualClubs.any(
                            (c) => c.name.toLowerCase().contains(query),
                          ) ||
                          a.ludMemberships.any(
                            (m) => m.name.toLowerCase().contains(query),
                          ),
                    )
                    .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
            children: [
              _MetricsSection(future: _metricsFuture),
              const SizedBox(height: 16),
              MetricGrid(
                tiles: [
                  MetricTile(
                    icon: Icons.people_outline,
                    value: '${accounts.length}',
                    label: 'Cuentas',
                    context: 'registradas',
                    accent: CX.blue,
                  ),
                  MetricTile(
                    icon: Icons.block_outlined,
                    value: '${accounts.where((a) => a.banned).length}',
                    label: 'Desactivadas',
                    context: 'sin acceso',
                    accent: CX.red,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: const InputDecoration(
                  hintText: 'Buscar por email, nombre o club',
                  prefixIcon: Icon(Icons.search, size: 18),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
              if (visible.isEmpty)
                const EmptyStatePanel(
                  icon: Icons.people_outline,
                  title: 'Sin resultados',
                  message: 'No hay cuentas que coincidan con la búsqueda.',
                )
              else
                Container(
                  decoration: CX.panelDecoration(),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (final account in visible)
                        _AccountTile(
                          account: account,
                          busy: _busy.contains(account.userId),
                          onToggle: () => _toggleBan(account),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MetricsSection extends StatelessWidget {
  final Future<PlatformMetrics>? future;

  const _MetricsSection({required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PlatformMetrics>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(18),
            decoration: CX.panelDecoration(),
            child: const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Cargando métricas...'),
              ],
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return EmptyStatePanel(
            icon: Icons.insights_outlined,
            title: 'Métricas no disponibles',
            message: snapshot.error is AdminAccountsException
                ? (snapshot.error as AdminAccountsException).message
                : 'No se pudieron cargar las métricas.',
          );
        }
        final metrics = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PremiumSectionHeader(title: 'Métricas'),
            MetricGrid(
              tiles: [
                MetricTile(
                  icon: Icons.person_search_outlined,
                  value: '${metrics.activeUsers}',
                  label: 'DTs / usuarios',
                  context: 'perfiles activos',
                  accent: CX.green,
                ),
                MetricTile(
                  icon: Icons.apartment_outlined,
                  value: '${metrics.manualClubs}',
                  label: 'Clubes manuales',
                  context: 'club_documents',
                  accent: CX.blue,
                ),
                MetricTile(
                  icon: Icons.verified_outlined,
                  value: '${metrics.activeLudClubs}',
                  label: 'Clubes LUD',
                  context: 'con membresía activa',
                  accent: CX.amber,
                ),
                MetricTile(
                  icon: Icons.group_add_outlined,
                  value: '${metrics.activeCollaborators}',
                  label: 'Colaboradores',
                  context: 'activos',
                  accent: const Color(0xFFC09BFF),
                ),
                MetricTile(
                  icon: Icons.trending_up,
                  value: '${metrics.recentTotal}',
                  label: 'Altas 7 días',
                  context:
                      '${metrics.recentUsers} usuarios · ${metrics.recentManualClubs} manuales · ${metrics.recentLudMemberships} LUD',
                  accent: CX.white,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _AccountTile extends StatelessWidget {
  final AdminAccount account;
  final bool busy;
  final VoidCallback onToggle;
  const _AccountTile({
    required this.account,
    required this.busy,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final clubLabels = <String>[
      for (final c in account.manualClubs)
        c.categories.isEmpty ? c.name : '${c.name} — ${c.categories.join(', ')}',
      for (final m in account.ludMemberships) '${m.name} · ${m.role}',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CX.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        account.fullName.isEmpty
                            ? account.email
                            : account.fullName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (account.banned)
                      const StatusPill('Desactivada', CX.red, compact: true),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  account.email,
                  style: const TextStyle(color: CX.faint, fontSize: 13),
                ),
                if (clubLabels.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final label in clubLabels) MetaTag(label)],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  tooltip: account.banned ? 'Reactivar' : 'Desactivar',
                  onPressed: onToggle,
                  icon: Icon(
                    account.banned
                        ? Icons.lock_open_outlined
                        : Icons.block_outlined,
                    color: account.banned ? CX.green : CX.red,
                  ),
                ),
        ],
      ),
    );
  }
}

/// Self-contained email/password login for the admin doorway — deliberately
/// separate from LoginScreen so a successful sign-in lands straight back on
/// this panel instead of the app's normal post-login routing.
class _AdminLoginForm extends StatefulWidget {
  final VoidCallback onSignedIn;
  const _AdminLoginForm({required this.onSignedIn});

  @override
  State<_AdminLoginForm> createState() => _AdminLoginFormState();
}

class _AdminLoginFormState extends State<_AdminLoginForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submitGoogle() async {
    setState(() {
      _googleLoading = true;
      _error = null;
    });
    try {
      // Redirects back to /#/admin — the PIN doorway shows once more (it's
      // a full page reload), but from there the session is already live and
      // this form never appears again.
      await SupabaseAuthService.signInWithGoogle(
        redirectTo: '${Uri.base.origin}/#/admin',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo iniciar con Google. Volvé a intentar.';
        _googleLoading = false;
      });
    }
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SupabaseAuthService.signInWithPassword(
        _email.text,
        _password.text,
      );
      if (!mounted) return;
      widget.onSignedIn();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo iniciar sesión. Revisá los datos.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: CX.panelDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.admin_panel_settings_outlined, color: CX.green, size: 26),
          const SizedBox(height: 12),
          const Text(
            'Administración',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text(
            'Iniciá sesión con tu cuenta para entrar directo al panel.',
            style: TextStyle(color: CX.muted, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Contraseña'),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: CX.red, fontSize: 12)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Entrar al panel'),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: const [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('o', style: TextStyle(color: CX.faint, fontSize: 11)),
              ),
              Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _googleLoading ? null : _submitGoogle,
              icon: _googleLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.g_mobiledata, size: 22),
              label: const Text('Continuar con Google'),
            ),
          ),
        ],
      ),
    );
  }
}

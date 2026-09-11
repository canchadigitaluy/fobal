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
  String _search = '';
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    if (SupabaseAuthService.currentSession != null) {
      _future = AdminAccountsService.listAccounts();
    }
  }

  void _reload() {
    setState(() => _future = AdminAccountsService.listAccounts());
  }

  Future<void> _toggleBan(AdminAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(account.banned ? 'Reactivar cuenta' : 'Desactivar cuenta'),
        content: Text(
          account.banned
              ? '${account.email} vuelve a poder iniciar sesion.'
              : '${account.email} no va a poder iniciar sesion hasta que la reactives.',
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
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: EmptyStatePanel(
                icon: Icons.admin_panel_settings_outlined,
                title: 'Iniciá sesión con tu cuenta',
                message: 'El panel de administración necesita tu sesión de fobal.',
                primaryLabel: 'Ir a iniciar sesión',
                onPrimary: () =>
                    Navigator.pushReplacementNamed(context, '/login'),
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
              style: TextStyle(color: CX.faint, fontSize: 10),
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
      for (final c in account.manualClubs) c.name,
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
                  style: const TextStyle(color: CX.faint, fontSize: 11.5),
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

import 'package:flutter/material.dart';

import '../main.dart';
import 'admin_accounts_screen.dart';

/// The only door into the platform-admin area: a numeric PIN, reached from
/// a deliberately unlabeled button on the login screen. This is a UI
/// shortcut, not the real security boundary — every privileged action still
/// goes through /api/admin-accounts, which re-checks the caller's own
/// Supabase session against the platform_admins table server-side.
class AdminPinScreen extends StatelessWidget {
  const AdminPinScreen({super.key});

  static const _pin = '200717';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CX.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _PinPad(
                expected: _pin,
                onSuccess: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => const AdminAccountsScreen(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PinPad extends StatefulWidget {
  final String expected;
  final VoidCallback onSuccess;
  const _PinPad({required this.expected, required this.onSuccess});

  @override
  State<_PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<_PinPad> {
  String _entered = '';
  bool _error = false;

  void _press(String digit) {
    if (_entered.length >= widget.expected.length) return;
    setState(() {
      _error = false;
      _entered += digit;
    });
    if (_entered.length == widget.expected.length) {
      if (_entered == widget.expected) {
        widget.onSuccess();
      } else {
        setState(() => _error = true);
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted) setState(() => _entered = '');
        });
      }
    }
  }

  void _backspace() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock_outline, color: CX.faint, size: 28),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.expected.length; i++)
              AnimatedContainer(
                duration: CX.motionFast,
                margin: const EdgeInsets.symmetric(horizontal: 5),
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _error
                      ? CX.red
                      : i < _entered.length
                      ? CX.green
                      : CX.line,
                ),
              ),
          ],
        ),
        const SizedBox(height: 28),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [for (final d in row) _PinKey(d, onTap: () => _press(d))],
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 64, height: 64),
            _PinKey('0', onTap: () => _press('0')),
            SizedBox(
              width: 64,
              height: 64,
              child: IconButton(
                onPressed: _backspace,
                icon: const Icon(Icons.backspace_outlined, size: 18),
                color: CX.faint,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PinKey extends StatelessWidget {
  final String digit;
  final VoidCallback onTap;
  const _PinKey(this.digit, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: CX.panel,
            border: Border.all(color: CX.line),
          ),
          child: Text(
            digit,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

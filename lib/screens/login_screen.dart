// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import '../services/account_identity_service.dart';
import '../services/supabase_auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _postAuthModeKey = 'cantera_post_auth_mode';
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _signupEmailController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _signupPasswordController = TextEditingController();
  final _signupPassword2Controller = TextEditingController();
  bool _googleLoading = false;
  bool _emailLoading = false;
  bool _ludMode = true;
  bool _creatingAccount = false;
  int _signupStep = 0;
  bool _passwordVisible = false;
  String? _authMessage;

  @override
  void initState() {
    super.initState();
    final initialFragment = Uri.base.fragment;
    if (initialFragment.contains('mode=local') ||
        initialFragment.startsWith('/login?mode=local')) {
      _ludMode = false;
    } else if (initialFragment.contains('mode=lud') ||
        initialFragment.startsWith('/login?mode=lud')) {
      _ludMode = true;
    }
    if (SupabaseAuthService.currentSession != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final fragment = Uri.base.fragment;
        final fragmentPath = fragment.split('?').first;
        final uriMode =
            fragmentPath == '/auth-local' || fragment.contains('mode=local')
            ? 'local'
            : fragmentPath == '/auth-lud' || fragment.contains('mode=lud')
            ? 'lud'
            : null;
        final mode = uriMode ?? html.window.localStorage[_postAuthModeKey];
        html.window.localStorage.remove(_postAuthModeKey);
        Navigator.pushReplacementNamed(
          context,
          mode == 'local' ? '/local-entry' : '/access',
        );
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _signupEmailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _signupPasswordController.dispose();
    _signupPassword2Controller.dispose();
    super.dispose();
  }

  String _localRoute() {
    return AccountIdentityService.currentUserId == null
        ? '/login?mode=local'
        : '/local-entry';
  }

  Future<void> _enterWithGoogle() async {
    setState(() {
      _googleLoading = true;
      _authMessage = null;
    });

    try {
      AppScope.of(context).selectRole(UserRole.coach);
      html.window.localStorage[_postAuthModeKey] = _ludMode ? 'lud' : 'local';
      await SupabaseAuthService.signInWithGoogle(localMode: !_ludMode);
    } on AuthConfigException {
      if (!mounted) return;
      setState(() => _authMessage = 'No se pudo conectar el inicio de sesión.');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _authMessage = 'No se pudo iniciar con Google. Vuelve a intentar.';
      });
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _signInWithPassword() async {
    if (_emailLoading) return;
    setState(() {
      _emailLoading = true;
      _authMessage = null;
    });
    try {
      AppScope.of(context).selectRole(UserRole.coach);
      await SupabaseAuthService.signInWithPassword(
        _emailController.text,
        _passwordController.text,
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        _ludMode ? '/access' : _localRoute(),
      );
    } on AuthConfigException {
      if (!mounted) return;
      setState(() => _authMessage = 'No se pudo conectar el inicio de sesión.');
    } on AuthInputException catch (error) {
      if (mounted) setState(() => _authMessage = error.message);
    } catch (_) {
      if (mounted) setState(() => _authMessage = 'No se pudo iniciar sesión.');
    } finally {
      if (mounted) setState(() => _emailLoading = false);
    }
  }

  Future<void> _createAccount() async {
    if (_signupStep == 0) {
      final email = _signupEmailController.text.trim();
      if (!email.contains('@')) {
        setState(() => _authMessage = 'Ingresa un correo válido.');
        return;
      }
      setState(() {
        _authMessage = null;
        _signupStep = 1;
      });
      return;
    }
    final first = _firstNameController.text.trim();
    final last = _lastNameController.text.trim();
    final pass = _signupPasswordController.text;
    if (first.length < 2 || last.length < 2) {
      setState(() => _authMessage = 'Completa nombre y apellido.');
      return;
    }
    if (pass != _signupPassword2Controller.text) {
      setState(() => _authMessage = 'Las contraseñas no coinciden.');
      return;
    }
    setState(() {
      _emailLoading = true;
      _authMessage = null;
    });
    try {
      final hasSession = await SupabaseAuthService.signUpWithPassword(
        email: _signupEmailController.text,
        password: pass,
        firstName: first,
        lastName: last,
      );
      if (!hasSession) {
        try {
          await SupabaseAuthService.signInWithPassword(
            _signupEmailController.text,
            pass,
          );
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _creatingAccount = false;
            _signupStep = 0;
            _authMessage =
                'Cuenta creada. Revisá tu correo para confirmarla y volvé a iniciar sesión.';
            _emailController.text = _signupEmailController.text;
            _passwordController.text = pass;
          });
          return;
        }
      }
      if (!mounted) return;
      AppScope.of(context).selectRole(UserRole.coach);
      Navigator.pushReplacementNamed(
        context,
        _ludMode ? '/access' : _localRoute(),
      );
    } on AuthConfigException {
      if (!mounted) return;
      setState(() => _authMessage = 'No se pudo conectar el registro.');
    } on AuthInputException catch (error) {
      if (mounted) setState(() => _authMessage = error.message);
    } catch (_) {
      if (mounted) setState(() => _authMessage = 'No se pudo crear la cuenta.');
    } finally {
      if (mounted) setState(() => _emailLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_creatingAccount) {
      return _CreateAccountView(
        step: _signupStep,
        emailController: _signupEmailController,
        firstNameController: _firstNameController,
        lastNameController: _lastNameController,
        passwordController: _signupPasswordController,
        confirmPasswordController: _signupPassword2Controller,
        loading: _emailLoading,
        message: _authMessage,
        passwordVisible: _passwordVisible,
        onClose: () => setState(() {
          _creatingAccount = false;
          _signupStep = 0;
          _authMessage = null;
        }),
        onBack: _signupStep == 0
            ? null
            : () => setState(() {
                _signupStep = 0;
                _authMessage = null;
              }),
        onTogglePassword: () =>
            setState(() => _passwordVisible = !_passwordVisible),
        onContinue: _emailLoading ? null : _createAccount,
        onGoogle: _googleLoading ? null : _enterWithGoogle,
        onLogin: () => setState(() {
          _creatingAccount = false;
          _signupStep = 0;
          _authMessage = null;
        }),
      );
    }
    return _ModernLoginView(
      ludMode: _ludMode,
      emailController: _emailController,
      passwordController: _passwordController,
      loading: _emailLoading,
      googleLoading: _googleLoading,
      message: _authMessage,
      passwordVisible: _passwordVisible,
      onModeChanged: (value) => setState(() {
        _ludMode = value;
        _authMessage = null;
      }),
      onTogglePassword: () =>
          setState(() => _passwordVisible = !_passwordVisible),
      onSubmit: _emailLoading ? null : _signInWithPassword,
      onGoogle: _googleLoading ? null : _enterWithGoogle,
      onCreateAccount: () => setState(() {
        _creatingAccount = true;
        _authMessage = null;
      }),
    );
  }
}

/// Practical, honest guidance — never a fake "reset password" flow that
/// doesn't exist, just what actually solves the two real causes of a failed
/// login: a mismatched credential or the wrong access path (LUD vs club
/// independiente).
void _showLoginHelp(BuildContext context, {required bool ludMode}) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('¿No podés entrar?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ludMode
                ? 'Revisá que el correo y la contraseña sean los mismos con '
                      'los que te diste de alta en la liga universitaria.'
                : 'Revisá que el correo y la contraseña sean los mismos con '
                      'los que creaste tu club en fobal.',
          ),
          const SizedBox(height: 10),
          Text(
            ludMode
                ? 'Si tu club no juega en la liga universitaria, elegí '
                      '"No soy DT de Liga" arriba.'
                : 'Si tu categoría juega en la liga universitaria, elegí '
                      '"Soy DT de Liga" arriba e ingresá con esas credenciales.',
          ),
          const SizedBox(height: 10),
          const Text(
            'También podés ingresar con Google o crear una cuenta nueva.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Entendido'),
        ),
      ],
    ),
  );
}

class _ModernLoginView extends StatelessWidget {
  final bool ludMode;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool loading;
  final bool googleLoading;
  final bool passwordVisible;
  final String? message;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onTogglePassword;
  final VoidCallback? onSubmit;
  final VoidCallback? onGoogle;
  final VoidCallback onCreateAccount;

  const _ModernLoginView({
    required this.ludMode,
    required this.emailController,
    required this.passwordController,
    required this.loading,
    required this.googleLoading,
    required this.passwordVisible,
    required this.message,
    required this.onModeChanged,
    required this.onTogglePassword,
    required this.onSubmit,
    required this.onGoogle,
    required this.onCreateAccount,
  });

  Widget _card(BuildContext context) {
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6EF2C7),
          surface: Color(0x33212925),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: .05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: .16)),
          ),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Inicia sesión en fobal',
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tu club. Tu metodología. En un solo lugar.',
              style: TextStyle(color: Colors.white.withValues(alpha: .55)),
            ),
            const SizedBox(height: 18),
            _AccessPathSelector(ludMode: ludMode, onChanged: onModeChanged),
            const SizedBox(height: 18),
            Text(
              'Correo electrónico',
              style: TextStyle(
                color: Colors.white.withValues(alpha: .85),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'tu@email.com',
                prefixIcon: Icon(Icons.mail_outline, size: 19),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Contraseña',
              style: TextStyle(
                color: Colors.white.withValues(alpha: .85),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: passwordController,
              obscureText: !passwordVisible,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => onSubmit?.call(),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.lock_outline, size: 19),
                suffixIcon: IconButton(
                  onPressed: onTogglePassword,
                  icon: Icon(
                    passwordVisible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: CX.green,
                foregroundColor: const Color(0xFF07110D),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    loading
                        ? 'Ingresando...'
                        : ludMode
                        ? 'Iniciar sesión'
                        : 'Continuar',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (!loading) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward, size: 18),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: () => _showLoginHelp(context, ludMode: ludMode),
                child: const Text('¿Problemas para iniciar sesión?'),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Divider(color: Colors.white.withValues(alpha: .14)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    ludMode ? 'O inicia sesión con' : 'O continúa con',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .45),
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  child: Divider(color: Colors.white.withValues(alpha: .14)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: googleLoading ? null : onGoogle,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: .16)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: googleLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const SizedBox(
                      width: 18,
                      height: 18,
                      child: CustomPaint(painter: _GoogleGPainter()),
                    ),
              label: const Text('Continuar con Google'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onCreateAccount,
              style: OutlinedButton.styleFrom(
                foregroundColor: CX.green,
                side: BorderSide(color: CX.green.withValues(alpha: .55)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Crear cuenta nueva'),
            ),
            if (message != null) ...[
              const SizedBox(height: 14),
              _AuthMessage(message: message!),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 860;
    final body = desktop
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(child: _ProductStory(compact: false)),
              Container(
                width: 460,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .16),
                  border: Border(
                    left: BorderSide(color: Colors.white.withValues(alpha: .08)),
                  ),
                ),
                child: Center(
                  child: SingleChildScrollView(
                    child: Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .03),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .12),
                        ),
                      ),
                      child: _card(context),
                    ),
                  ),
                ),
              ),
            ],
          )
        : SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _ProductStory(compact: true),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .03),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .12),
                      ),
                    ),
                    child: _card(context),
                  ),
                ),
                const SizedBox(height: 10),
                const _FooterTag(),
                const SizedBox(height: 28),
              ],
            ),
          );
    return Scaffold(
      backgroundColor: const Color(0xFF07110D),
      body: Stack(
        children: [
          body,
          // Deliberately unlabeled — the real door is /api/admin-accounts,
          // which re-checks platform_admins server-side either way.
          Positioned(
            right: 10,
            bottom: 10,
            child: InkWell(
              onTap: () => Navigator.pushNamed(context, '/admin'),
              customBorder: const CircleBorder(),
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: .05),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateAccountView extends StatelessWidget {
  final int step;
  final TextEditingController emailController;
  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final bool loading;
  final bool passwordVisible;
  final String? message;
  final VoidCallback onClose;
  final VoidCallback? onBack;
  final VoidCallback onTogglePassword;
  final VoidCallback? onContinue;
  final VoidCallback? onGoogle;
  final VoidCallback onLogin;

  const _CreateAccountView({
    required this.step,
    required this.emailController,
    required this.firstNameController,
    required this.lastNameController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.loading,
    required this.passwordVisible,
    required this.message,
    required this.onClose,
    required this.onBack,
    required this.onTogglePassword,
    required this.onContinue,
    required this.onGoogle,
    required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CX.canvas,
      body: Column(
        children: [
          LinearProgressIndicator(
            value: step == 0 ? .45 : .9,
            minHeight: 4,
            color: CX.green,
            backgroundColor: CX.line,
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IconButton.outlined(
                            onPressed: onClose,
                            icon: const Icon(Icons.close),
                          ),
                          const Spacer(),
                          if (onBack != null)
                            IconButton.outlined(
                              onPressed: onBack,
                              icon: const Icon(Icons.arrow_back),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (step == 0) ...[
                        const Text(
                          '¿Cuál es tu correo?',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Correo electrónico',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: emailController,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 18),
                        const _LegalConsentText(),
                        const SizedBox(height: 22),
                        ElevatedButton(
                          onPressed: onContinue,
                          child: const Text('Continuar'),
                        ),
                        const SizedBox(height: 24),
                        Center(
                          child: _SocialCircle(loading: false, onTap: onGoogle),
                        ),
                        const SizedBox(height: 20),
                        TextButton(
                          onPressed: onLogin,
                          child: const Text('Ya tengo una cuenta'),
                        ),
                      ] else ...[
                        const Text(
                          'Sobre ti',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 22),
                        const Text(
                          'Nombre',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        TextField(controller: firstNameController),
                        const SizedBox(height: 14),
                        const Text(
                          'Apellido',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        TextField(controller: lastNameController),
                        const SizedBox(height: 14),
                        const Text(
                          'Contraseña',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: passwordController,
                          obscureText: !passwordVisible,
                          decoration: InputDecoration(
                            suffixIcon: IconButton(
                              onPressed: onTogglePassword,
                              icon: Icon(
                                passwordVisible
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 7),
                        const Text(
                          "Los caracteres '/' y ' no están permitidos en la contraseña",
                          style: TextStyle(color: CX.muted, fontSize: 11),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Confirmar contraseña',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: confirmPasswordController,
                          obscureText: !passwordVisible,
                          decoration: InputDecoration(
                            suffixIcon: IconButton(
                              onPressed: onTogglePassword,
                              icon: Icon(
                                passwordVisible
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        ElevatedButton(
                          onPressed: onContinue,
                          child: Text(loading ? 'Creando...' : 'Crear cuenta'),
                        ),
                      ],
                      if (message != null) ...[
                        const SizedBox(height: 14),
                        _AuthMessage(message: message!),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Continuar con Google" affordance. Renders the real four-color "G" mark
/// instead of a generic Material icon, so it reads as an actual Google
/// sign-in button rather than a placeholder.
class _LegalConsentText extends StatelessWidget {
  const _LegalConsentText();

  @override
  Widget build(BuildContext context) {
    final linkStyle = TextButton.styleFrom(
      foregroundColor: CX.green,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        height: 1.45,
      ),
    );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          'Al registrarte aceptas nuestros ',
          style: TextStyle(color: CX.muted, height: 1.45),
        ),
        TextButton(
          style: linkStyle,
          onPressed: () => Navigator.pushNamed(context, '/legal/terminos'),
          child: const Text('Términos y condiciones'),
        ),
        const Text(
          ' y la ',
          style: TextStyle(color: CX.muted, height: 1.45),
        ),
        TextButton(
          style: linkStyle,
          onPressed: () => Navigator.pushNamed(context, '/legal/privacidad'),
          child: const Text('política de privacidad'),
        ),
        const Text('.', style: TextStyle(color: CX.muted, height: 1.45)),
      ],
    );
  }
}

class _SocialCircle extends StatelessWidget {
  final bool loading;
  final VoidCallback? onTap;

  const _SocialCircle({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: loading ? null : onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: loading
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Padding(
                padding: EdgeInsets.all(15),
                child: CustomPaint(painter: _GoogleGPainter()),
              ),
      ),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  const _GoogleGPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final stroke = size.width * .34;
    Paint arc(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final rect = Rect.fromCircle(center: center, radius: radius - stroke / 2);
    const twoPi = 6.28318530718;
    const quarter = twoPi / 4;
    // Four quarter-arcs, one per Google brand color, matching the familiar
    // ring-with-a-notch "G" composition.
    canvas.drawArc(
      rect,
      -quarter * .18,
      quarter,
      false,
      arc(const Color(0xFF4285F4)),
    );
    canvas.drawArc(
      rect,
      quarter * .82,
      quarter,
      false,
      arc(const Color(0xFF34A853)),
    );
    canvas.drawArc(
      rect,
      quarter * 1.82,
      quarter,
      false,
      arc(const Color(0xFFFBBC05)),
    );
    canvas.drawArc(
      rect,
      quarter * 2.82,
      quarter * 1.18,
      false,
      arc(const Color(0xFFEA4335)),
    );
    // The bar that closes the ring into a "G": a blue square filling the
    // notch on the right, matching the arc's own thickness.
    canvas.drawRect(
      Rect.fromLTWH(center.dx, center.dy - stroke / 2, radius, stroke),
      Paint()..color = const Color(0xFF4285F4),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AuthMessage extends StatelessWidget {
  final String message;

  const _AuthMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6DD),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x66F0BE57)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: CX.amber, fontSize: 12, height: 1.35),
      ),
    );
  }
}

/// The hero panel: logo/nav, headline and feature chips over a dark
/// tactics-board watermark. [compact] switches the desktop split-screen
/// layout (with its own footer tag) for a stacked mobile section — the
/// footer then renders separately, once, after the login card below it.
class _ProductStory extends StatelessWidget {
  final bool compact;
  const _ProductStory({required this.compact});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF07110D),
      child: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _LoginTacticPainter()),
          ),
          Padding(
            padding: EdgeInsets.all(compact ? 22 : 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
              children: [
                Row(
                  children: [
                    const _MobileBrand(),
                    const Spacer(),
                    if (compact)
                      IconButton(
                        onPressed: () {},
                        tooltip: 'Menú',
                        icon: const Icon(Icons.menu, color: Colors.white),
                      )
                    else
                      const _TopNavLinks(),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'FÚTBOL · DATOS · PERSONAS · PROGRESO',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .4),
                    fontSize: 10.5,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: compact ? 22 : 34),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x1A6EF2C7),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0x666EF2C7)),
                  ),
                  child: const Text(
                    'INTELIGENCIA DEPORTIVA',
                    style: TextStyle(
                      color: Color(0xFF9CF8DB),
                      fontSize: 11,
                      letterSpacing: .6,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: compact ? 340 : 570),
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontSize: compact ? 30 : 45,
                        height: 1.08,
                        fontWeight: FontWeight.w800,
                      ),
                      children: const [
                        TextSpan(
                          text: 'Una idea de juego.\n',
                          style: TextStyle(color: Colors.white),
                        ),
                        TextSpan(
                          text: 'Todo el club conectado.',
                          style: TextStyle(color: Color(0xFF6EF2C7)),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: compact ? 10 : 15),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: compact ? 340 : 520),
                  child: Text(
                    'Metodología, planteles, sesiones y análisis contextual '
                    'para hacer crecer cada categoría.',
                    style: TextStyle(
                      color: const Color(0xDDECF8F2),
                      fontSize: compact ? 13.5 : 15,
                      height: 1.5,
                    ),
                  ),
                ),
                SizedBox(height: compact ? 22 : 38),
                Wrap(
                  spacing: compact ? 26 : 30,
                  runSpacing: 18,
                  children: const [
                    _FeatureChip(
                      icon: Icons.account_tree_outlined,
                      title: 'Estructura',
                      caption: 'De la idea al plan',
                    ),
                    _FeatureChip(
                      icon: Icons.sports_soccer_outlined,
                      title: 'Campo',
                      caption: 'Del entrenamiento al rendimiento',
                    ),
                    _FeatureChip(
                      icon: Icons.auto_awesome_outlined,
                      title: 'Inteligencia',
                      caption: 'Datos que potencian',
                    ),
                  ],
                ),
                if (!compact) ...[const Spacer(), const _FooterTag()],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Desktop-only nav, purely decorative (no sections exist to link to yet on
/// this screen) — mirrors the design's word list without pretending each
/// entry is a working link.
class _TopNavLinks extends StatelessWidget {
  const _TopNavLinks();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: Color(0x8CFFFFFF),
      fontSize: 11,
      letterSpacing: .8,
      fontWeight: FontWeight.w700,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: const [
        Text('ANALIZA', style: style),
        SizedBox(height: 3),
        Text('PLANIFICA', style: style),
        SizedBox(height: 3),
        Text('ENTRENA', style: style),
        SizedBox(height: 3),
        Text('EVOLUCIONA', style: style),
      ],
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String caption;

  const _FeatureChip({
    required this.icon,
    required this.title,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF6EF2C7), size: 19),
          const SizedBox(height: 7),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .5),
              fontSize: 11.5,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterTag extends StatelessWidget {
  const _FooterTag();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: 2, color: const Color(0xFF6EF2C7)),
        const SizedBox(width: 10),
        Text(
          'MEJORES ENTRENADORES. CLUBES MÁS FUERTES.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: .4),
            fontSize: 10.5,
            letterSpacing: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _AccessPathSelector extends StatelessWidget {
  final bool ludMode;
  final ValueChanged<bool> onChanged;

  const _AccessPathSelector({required this.ludMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: CX.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CX.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: _AccessPathOption(
              label: 'Soy DT de Liga',
              icon: Icons.verified_outlined,
              selected: ludMode,
              onTap: () => onChanged(true),
            ),
          ),
          Expanded(
            child: _AccessPathOption(
              label: 'No soy DT de Liga',
              icon: Icons.edit_note_outlined,
              selected: !ludMode,
              onTap: () => onChanged(false),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccessPathOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _AccessPathOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: CX.motionFast,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? CX.greenDark : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: selected ? CX.green : CX.faint),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: selected ? CX.white : CX.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileBrand extends StatelessWidget {
  const _MobileBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: CX.green.withValues(alpha: .45)),
            boxShadow: [
              BoxShadow(color: CX.green.withValues(alpha: .18), blurRadius: 14),
            ],
          ),
          child: Center(
            child: Image.asset(
              'assets/branding/isotipo_white.png',
              width: 22,
              height: 22,
              color: CX.green,
              colorBlendMode: BlendMode.srcIn,
            ),
          ),
        ),
        const SizedBox(width: 10),
        RichText(
          text: const TextSpan(
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
            children: [
              TextSpan(
                text: 'fobal',
                style: TextStyle(color: CX.white),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Restrained tactics-board watermark: a pitch outline, halfway line and
/// center circle, with a couple of dashed movement arrows — vector, so it
/// stays crisp at any size and costs nothing on a slow connection (no
/// photographic hero asset).
class _LoginTacticPainter extends CustomPainter {
  const _LoginTacticPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final field = Rect.fromLTWH(
      size.width * .06,
      size.height * .14,
      size.width * .58,
      size.height * .58,
    );
    final linePaint = Paint()
      ..color = const Color(0x26FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(
      RRect.fromRectAndRadius(field, const Radius.circular(12)),
      linePaint,
    );
    canvas.drawLine(
      Offset(field.center.dx, field.top),
      Offset(field.center.dx, field.bottom),
      linePaint,
    );
    canvas.drawCircle(field.center, size.shortestSide * .11, linePaint);

    final nodes = [
      Offset(field.left + field.width * .30, field.top + field.height * .68),
      Offset(field.left + field.width * .46, field.top + field.height * .48),
      Offset(field.left + field.width * .70, field.top + field.height * .74),
      Offset(field.left + field.width * .60, field.top + field.height * .26),
      Offset(field.left + field.width * .82, field.top + field.height * .40),
    ];
    final dashed = Paint()
      ..color = const Color(0xFF6EF2C7)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    void dashedLine(Offset a, Offset b) {
      const dash = 5.0, gap = 5.0;
      final total = (b - a).distance;
      final dir = (b - a) / total;
      var walked = 0.0;
      while (walked < total) {
        final start = a + dir * walked;
        final end = a + dir * (walked + dash).clamp(0, total);
        canvas.drawLine(start, end, dashed);
        walked += dash + gap;
      }
    }

    dashedLine(nodes[0], nodes[1]);
    dashedLine(nodes[1], nodes[2]);
    dashedLine(nodes[3], nodes[4]);
    final nodePaint = Paint()..color = const Color(0xFF6EF2C7);
    for (final node in nodes) {
      canvas.drawCircle(node, 4.5, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

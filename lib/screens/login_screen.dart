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
  bool _remember = true;
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
      remember: _remember,
      loading: _emailLoading,
      googleLoading: _googleLoading,
      message: _authMessage,
      passwordVisible: _passwordVisible,
      onModeChanged: (value) => setState(() {
        _ludMode = value;
        _authMessage = null;
      }),
      onRememberChanged: (value) => setState(() => _remember = value ?? true),
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
  final bool remember;
  final bool loading;
  final bool googleLoading;
  final bool passwordVisible;
  final String? message;
  final ValueChanged<bool> onModeChanged;
  final ValueChanged<bool?> onRememberChanged;
  final VoidCallback onTogglePassword;
  final VoidCallback? onSubmit;
  final VoidCallback? onGoogle;
  final VoidCallback onCreateAccount;

  const _ModernLoginView({
    required this.ludMode,
    required this.emailController,
    required this.passwordController,
    required this.remember,
    required this.loading,
    required this.googleLoading,
    required this.passwordVisible,
    required this.message,
    required this.onModeChanged,
    required this.onRememberChanged,
    required this.onTogglePassword,
    required this.onSubmit,
    required this.onGoogle,
    required this.onCreateAccount,
  });

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 860;
    final form = Material(
      type: MaterialType.transparency,
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: desktop ? 54 : 28,
          vertical: 28,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!desktop) ...[
                const _MobileBrand(),
                const SizedBox(height: 34),
              ],
              const Text(
                'Inicia sesión en fobal',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 18),
              _AccessPathSelector(ludMode: ludMode, onChanged: onModeChanged),
              const SizedBox(height: 20),
              const Text(
                'Correo electrónico',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(hintText: 'tu@email.com'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Contraseña',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passwordController,
                obscureText: !passwordVisible,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => onSubmit?.call(),
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
              const SizedBox(height: 10),
              CheckboxListTile(
                value: remember,
                onChanged: onRememberChanged,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Recordarme',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              ElevatedButton(
                onPressed: onSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: CX.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  loading
                      ? 'Ingresando...'
                      : ludMode
                      ? 'Iniciar sesión'
                      : 'Continuar',
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => _showLoginHelp(context, ludMode: ludMode),
                child: const Text('¿Problemas para iniciar sesión?'),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  ludMode ? 'O inicia sesión con' : 'O continúa con',
                  style: const TextStyle(color: CX.muted),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: _SocialCircle(loading: googleLoading, onTap: onGoogle),
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 18),
              OutlinedButton(
                onPressed: onCreateAccount,
                child: const Text('Crear cuenta nueva'),
              ),
              if (message != null) ...[
                const SizedBox(height: 14),
                _AuthMessage(message: message!),
              ],
            ],
          ),
        ),
      ),
    );
    return Scaffold(
      backgroundColor: const Color(0xFF07110D),
      body: desktop
          ? Stack(
              children: [
                const Positioned.fill(child: _ProductStory()),
                Positioned(
                  top: 72,
                  right: 42,
                  bottom: 36,
                  width: 430,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .35),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x55000000),
                          blurRadius: 38,
                          offset: Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Theme(
                      data: ThemeData.dark(useMaterial3: true).copyWith(
                        colorScheme: const ColorScheme.dark(
                          primary: Color(0xFF6EF2C7),
                          surface: Color(0x33212925),
                        ),
                        inputDecorationTheme: InputDecorationTheme(
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: .16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: .22),
                            ),
                          ),
                        ),
                      ),
                      child: form,
                    ),
                  ),
                ),
              ],
            )
          : Center(child: form),
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
                        const Text(
                          'Al registrarte aceptas nuestros Términos y condiciones y la política de privacidad.',
                          style: TextStyle(color: CX.muted, height: 1.45),
                        ),
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

class _ProductStory extends StatelessWidget {
  const _ProductStory();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEFF6F2), Color(0xFF0A2017), Color(0xFF07110D)],
          stops: [0, .45, 1],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _LoginTacticPainter()),
          ),
          Positioned(
            left: 382,
            top: 98,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .72),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0x662C3A34)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: const Text(
                'INTELIGENCIA DEPORTIVA',
                style: TextStyle(
                  color: Color(0xFF102019),
                  fontSize: 13,
                  letterSpacing: .6,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _MobileBrand(),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xCC0D2B20),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: const Color(0x6676F0C7)),
                  ),
                  child: const Text(
                    'INTELIGENCIA DEPORTIVA',
                    style: TextStyle(
                      color: Color(0xFF9CF8DB),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 570),
                  child: const Text(
                    'Una idea de juego.\nTodo el club conectado.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 45,
                      height: 1.04,
                      fontWeight: FontWeight.w800,
                      shadows: [
                        Shadow(
                          color: Color(0xAA000000),
                          blurRadius: 10,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: const Text(
                    'Metodologia, planteles, sesiones y analisis contextual para hacer crecer cada categoria.',
                    style: TextStyle(
                      color: Color(0xDDECF8F2),
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 38),
                const Row(
                  children: [
                    _ProofPoint(Icons.account_tree_outlined, 'Estructura'),
                    SizedBox(width: 22),
                    _ProofPoint(Icons.sports_soccer_outlined, 'Campo'),
                    SizedBox(width: 22),
                    _ProofPoint(Icons.auto_awesome_outlined, 'Inteligencia'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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
          child: const CustomPaint(painter: FobalMarkPainter()),
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

class _ProofPoint extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ProofPoint(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: CX.green, size: 18),
      const SizedBox(width: 7),
      Text(
        label,
        style: const TextStyle(
          color: CX.muted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _LoginTacticPainter extends CustomPainter {
  const _LoginTacticPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final field = Rect.fromLTWH(
      size.width * .10,
      size.height * .16,
      size.width * .64,
      size.height * .48,
    );
    final fieldPaint = Paint()
      ..color = const Color(0x402A6B4B)
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = const Color(0x66FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.save();
    canvas.translate(size.width * .03, size.height * .02);
    canvas.rotate(-0.22);
    canvas.drawRRect(
      RRect.fromRectAndRadius(field, const Radius.circular(10)),
      fieldPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(field, const Radius.circular(10)),
      linePaint,
    );
    canvas.drawLine(
      Offset(field.center.dx, field.top),
      Offset(field.center.dx, field.bottom),
      linePaint,
    );
    canvas.drawCircle(field.center, size.shortestSide * .07, linePaint);
    canvas.drawRect(
      Rect.fromLTWH(
        field.left,
        field.top + field.height * .28,
        field.width * .18,
        field.height * .44,
      ),
      linePaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        field.right - field.width * .18,
        field.top + field.height * .28,
        field.width * .18,
        field.height * .44,
      ),
      linePaint,
    );

    final nodes = [
      Offset(field.left + field.width * .34, field.top + field.height * .32),
      Offset(field.left + field.width * .48, field.top + field.height * .44),
      Offset(field.left + field.width * .62, field.top + field.height * .32),
      Offset(field.left + field.width * .52, field.top + field.height * .61),
      Offset(field.left + field.width * .72, field.top + field.height * .50),
      Offset(field.left + field.width * .40, field.top + field.height * .68),
    ];
    final pathPaint = Paint()
      ..color = const Color(0xBBF6C35B)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < nodes.length - 1; i++) {
      canvas.drawLine(nodes[i], nodes[i + 1], pathPaint);
    }
    final glow = Paint()
      ..color = const Color(0x664AA8FF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    final nodePaint = Paint()..color = const Color(0xFF6EF2C7);
    final yellow = Paint()..color = const Color(0xFFF6C35B);
    for (var i = 0; i < nodes.length; i++) {
      canvas.drawCircle(nodes[i], 16, glow);
      canvas.drawCircle(nodes[i], 6.5, i == 4 ? yellow : nodePaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/cantera_data.dart';
import '../main.dart';
import '../services/preview_access_service.dart';
import '../services/supabase_auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _postAuthModeKey = 'cantera_post_auth_mode';
  UserRole _role = UserRole.coach;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _signupEmailController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _signupPasswordController = TextEditingController();
  final _signupPassword2Controller = TextEditingController();
  final _codeController = TextEditingController();
  bool _googleLoading = false;
  bool _emailLoading = false;
  bool _previewLoading = false;
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
        final uriMode = fragmentPath == '/auth-local' ||
                fragment.contains('mode=local')
            ? 'local'
            : fragmentPath == '/auth-lud' || fragment.contains('mode=lud')
            ? 'lud'
            : null;
        final mode = uriMode ?? html.window.localStorage[_postAuthModeKey];
        html.window.localStorage.remove(_postAuthModeKey);
        final localClubId =
            html.window.localStorage['fobal_local_profile_club_id'];
        Navigator.pushReplacementNamed(
          context,
          mode == 'local'
              ? (localClubId == null || localClubId.isEmpty
                    ? '/local-setup'
                    : '/local-home')
              : '/access',
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
    _codeController.dispose();
    super.dispose();
  }

  void _enter() {
    AppScope.of(context).selectRole(_role);
    Navigator.pushReplacementNamed(context, '/home');
  }

  String _localRoute() {
    final localClubId = html.window.localStorage['fobal_local_profile_club_id'];
    return localClubId == null || localClubId.isEmpty
        ? '/local-setup'
        : '/local-home';
  }

  Future<void> _enterWithCode() async {
    if (_previewLoading) return;
    final code = _codeController.text.trim().replaceAll(' ', '');
    if (code.length != 4) {
      setState(() => _authMessage = 'Ingresa los cuatro numeros.');
      return;
    }
    setState(() {
      _previewLoading = true;
      _authMessage = null;
    });
    try {
      await PreviewAccessService.grant(code);
      if (!mounted) return;
      AppScope.of(context).selectRole(UserRole.coach);
      Navigator.pushReplacementNamed(
        context,
        _ludMode ? '/preview-access' : _localRoute(),
      );
    } on PreviewAccessException catch (error) {
      if (mounted) setState(() => _authMessage = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _authMessage = 'No se pudo validar el acceso.');
      }
    } finally {
      if (mounted) setState(() => _previewLoading = false);
    }
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
      if (!_ludMode) {
        Navigator.pushReplacementNamed(context, _localRoute());
        return;
      }
      setState(() => _authMessage = 'No se pudo conectar el inicio de sesión.');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _authMessage =
            'No se pudo iniciar con Google. Vuelve a intentar.';
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
      if (!_ludMode) {
        Navigator.pushReplacementNamed(context, _localRoute());
        return;
      }
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
      if (!_ludMode) {
        Navigator.pushReplacementNamed(context, _localRoute());
        return;
      }
      setState(() => _authMessage = 'No se pudo conectar el registro.');
    } on AuthInputException catch (error) {
      if (mounted) setState(() => _authMessage = error.message);
    } catch (_) {
      if (mounted) setState(() => _authMessage = 'No se pudo crear la cuenta.');
    } finally {
      if (mounted) setState(() => _emailLoading = false);
    }
  }

  Future<void> _sendMagicLink() async {
    setState(() {
      _emailLoading = true;
      _authMessage = null;
    });

    try {
      AppScope.of(context).selectRole(_role);
      await SupabaseAuthService.sendMagicLink(_emailController.text);
      if (!mounted) return;
      setState(() {
        _authMessage =
            'Te enviamos un enlace de acceso. Al abrirlo, fobal validara tu club.';
      });
    } on AuthConfigException {
      if (!mounted) return;
      setState(() => _authMessage = 'No se pudo conectar el acceso.');
    } on AuthInputException catch (error) {
      if (!mounted) return;
      setState(() => _authMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _authMessage =
            'No se pudo enviar el enlace. Vuelve a intentar.';
      });
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
    return Scaffold(
      backgroundColor: CX.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 860;
            return Row(
              children: [
                if (desktop) const Expanded(flex: 6, child: _ProductStory()),
                Expanded(
                  flex: desktop ? 4 : 1,
                  child: Container(
                    color: CX.canvas,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                          horizontal: desktop ? 54 : 22,
                          vertical: 28,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 430),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!desktop) ...[
                                const _MobileBrand(),
                                const SizedBox(height: 40),
                              ],
                              const Text(
                                'Bienvenido a tu cantera',
                                style: TextStyle(
                                  fontSize: 28,
                                  height: 1.1,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Organiza el trabajo deportivo y convierte informacion de campo en decisiones.',
                                style: TextStyle(
                                  color: CX.muted,
                                  height: 1.45,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 26),
                              _AccessPathSelector(
                                ludMode: _ludMode,
                                onChanged: (value) =>
                                    setState(() => _ludMode = value),
                              ),
                              const SizedBox(height: 22),
                              const Text(
                                'ACCESO DE PRUEBA',
                                style: TextStyle(
                                  color: CX.faint,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _codeController,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 14,
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(4),
                                ],
                                onChanged: (value) {
                                  if (value.length == 4) _enterWithCode();
                                },
                                onSubmitted: (_) => _enterWithCode(),
                                decoration: const InputDecoration(
                                  labelText: 'Codigo de acceso',
                                  prefixIcon: Icon(Icons.lock_outline, size: 19),
                                  counterText: '',
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: _previewLoading ? null : _enterWithCode,
                                icon: _previewLoading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.arrow_forward, size: 18),
                                label: Text(
                                  _previewLoading
                                      ? 'Validando...'
                                      : _ludMode
                                      ? 'Elegir club de Liga'
                                      : 'Crear espacio del profe',
                                ),
                              ),
                              const SizedBox(height: 18),
                              ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                childrenPadding: EdgeInsets.zero,
                                title: const Text(
                                  'Acceso interno',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                children: [
                                  const Text(
                                    'Para cuentas reales del club.',
                                    style: TextStyle(
                                      color: CX.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  _RoleSelector(
                                    value: _role,
                                    onChanged: (value) =>
                                        setState(() => _role = value),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    autofillHints: const [AutofillHints.email],
                                    onSubmitted: (_) => _sendMagicLink(),
                                    decoration: const InputDecoration(
                                      labelText: 'Email del cuerpo tecnico',
                                      prefixIcon: Icon(
                                        Icons.mail_outline,
                                        size: 19,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: _emailLoading
                                    ? null
                                    : _sendMagicLink,
                                icon: _emailLoading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: CX.green,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.forward_to_inbox_outlined,
                                        size: 18,
                                      ),
                                label: Text(
                                  _emailLoading
                                      ? 'Enviando enlace'
                                      : 'Enviar enlace de acceso',
                                ),
                              ),
                              const SizedBox(height: 10),
                              ElevatedButton.icon(
                                onPressed: _googleLoading
                                    ? null
                                    : _enterWithGoogle,
                                icon: _googleLoading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: CX.green,
                                        ),
                                      )
                                    : const Icon(Icons.g_mobiledata, size: 24),
                                label: Text(
                                  _googleLoading
                                      ? 'Conectando con Google'
                                      : 'Continuar con Google',
                                ),
                              ),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: _enter,
                                    icon: const Icon(
                                      Icons.visibility_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('Entrar solo a demo'),
                                  ),
                                ],
                              ),
                              if (_authMessage != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF6DD),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0x66F0BE57),
                                    ),
                                  ),
                                  child: Text(
                                    _authMessage!,
                                    style: const TextStyle(
                                      color: CX.amber,
                                      fontSize: 12,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.shield_outlined,
                                    color: CX.faint,
                                    size: 14,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Google habilita acceso por club real',
                                    style: TextStyle(
                                      color: CX.faint,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
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
      padding: EdgeInsets.symmetric(horizontal: desktop ? 54 : 28, vertical: 28),
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
            const Text('Correo electrónico', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(hintText: 'tu@email.com'),
            ),
            const SizedBox(height: 12),
            const Text('Contraseña', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            TextField(
              controller: passwordController,
              obscureText: !passwordVisible,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => onSubmit?.call(),
              decoration: InputDecoration(
                suffixIcon: IconButton(
                  onPressed: onTogglePassword,
                  icon: Icon(passwordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
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
              title: const Text('Recordarme', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            OutlinedButton(
              onPressed: onSubmit,
              child: Text(loading ? 'Ingresando...' : ludMode ? 'Iniciar sesión' : 'Continuar'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: null,
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
              child: _SocialCircle(
                icon: Icons.g_mobiledata,
                loading: googleLoading,
                onTap: onGoogle,
              ),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: onCreateAccount,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF183D49), foregroundColor: Colors.white),
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
          LinearProgressIndicator(value: step == 0 ? .45 : .9, minHeight: 4, color: CX.green, backgroundColor: CX.line),
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
                          IconButton.outlined(onPressed: onClose, icon: const Icon(Icons.close)),
                          const Spacer(),
                          if (onBack != null)
                            IconButton.outlined(onPressed: onBack, icon: const Icon(Icons.arrow_back)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (step == 0) ...[
                        const Text('¿Cuál es tu correo?', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 24),
                        const Text('Correo electrónico', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        TextField(controller: emailController, keyboardType: TextInputType.emailAddress),
                        const SizedBox(height: 18),
                        const Text(
                          'Al registrarte aceptas nuestros Términos y condiciones y la política de privacidad.',
                          style: TextStyle(color: CX.muted, height: 1.45),
                        ),
                        const SizedBox(height: 22),
                        ElevatedButton(onPressed: onContinue, child: const Text('Continuar')),
                        const SizedBox(height: 24),
                        Center(
                          child: _SocialCircle(
                            icon: Icons.g_mobiledata,
                            loading: false,
                            onTap: onGoogle,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextButton(onPressed: onLogin, child: const Text('Ya tengo una cuenta')),
                      ] else ...[
                        const Text('Sobre ti', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 22),
                        const Text('Nombre', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        TextField(controller: firstNameController),
                        const SizedBox(height: 14),
                        const Text('Apellido', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        TextField(controller: lastNameController),
                        const SizedBox(height: 14),
                        const Text('Contraseña', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: passwordController,
                          obscureText: !passwordVisible,
                          decoration: InputDecoration(
                            suffixIcon: IconButton(
                              onPressed: onTogglePassword,
                              icon: Icon(passwordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(height: 7),
                        const Text("Los caracteres '/' y ' no están permitidos en la contraseña", style: TextStyle(color: CX.muted, fontSize: 11)),
                        const SizedBox(height: 14),
                        const Text('Confirmar contraseña', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: confirmPasswordController,
                          obscureText: !passwordVisible,
                          decoration: InputDecoration(
                            suffixIcon: IconButton(
                              onPressed: onTogglePassword,
                              icon: Icon(passwordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        ElevatedButton(onPressed: onContinue, child: Text(loading ? 'Creando...' : 'Crear cuenta')),
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

class _SocialCircle extends StatelessWidget {
  final IconData icon;
  final bool loading;
  final VoidCallback? onTap;

  const _SocialCircle({required this.icon, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: loading ? null : onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: CX.lineStrong),
          color: CX.panel,
        ),
        child: loading
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, color: CX.green, size: 34),
      ),
    );
  }
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
      child: Text(message, style: const TextStyle(color: CX.amber, fontSize: 12, height: 1.35)),
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
          const Positioned.fill(child: CustomPaint(painter: _LoginTacticPainter())),
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

class _RoleSelector extends StatelessWidget {
  final UserRole value;
  final ValueChanged<UserRole> onChanged;
  const _RoleSelector({required this.value, required this.onChanged});

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
            child: _RoleOption(
              label: 'Coordinador',
              icon: Icons.hub_outlined,
              selected: value == UserRole.coordinator,
              onTap: () => onChanged(UserRole.coordinator),
            ),
          ),
          Expanded(
            child: _RoleOption(
              label: 'Entrenador',
              icon: Icons.sports_outlined,
              selected: value == UserRole.coach,
              onTap: () => onChanged(UserRole.coach),
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

  const _AccessPathSelector({
    required this.ludMode,
    required this.onChanged,
  });

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

class _RoleOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _RoleOption({
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
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? CX.panel3 : Colors.transparent,
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
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
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
              BoxShadow(
                color: CX.green.withValues(alpha: .18),
                blurRadius: 14,
              ),
            ],
          ),
          child: const CustomPaint(painter: _CanteraLoginIsoPainter()),
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
              TextSpan(text: 'fobal', style: TextStyle(color: CX.white)),
            ],
          ),
        ),
      ],
    );
  }
}

class _CanteraLoginIsoPainter extends CustomPainter {
  const _CanteraLoginIsoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final line = Paint()
      ..color = CX.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * .075
      ..strokeCap = StrokeCap.round;
    final yellow = Paint()
      ..color = CX.amber
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * .06
      ..strokeCap = StrokeCap.round;
    final blue = Paint()
      ..color = CX.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * .055
      ..strokeCap = StrokeCap.round;
    final greenDot = Paint()..color = CX.green;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .17, h * .18, w * .66, h * .64),
        Radius.circular(w * .16),
      ),
      line,
    );
    canvas.drawCircle(Offset(w * .50, h * .50), w * .16, line);
    canvas.drawLine(Offset(w * .50, h * .20), Offset(w * .50, h * .80), line);
    canvas.drawLine(Offset(w * .30, h * .57), Offset(w * .50, h * .25), line);
    canvas.drawLine(Offset(w * .50, h * .50), Offset(w * .67, h * .42), yellow);
    canvas.drawLine(Offset(w * .57, h * .80), Offset(w * .80, h * .65), blue);
    for (final dot in [
      Offset(w * .50, h * .23),
      Offset(w * .30, h * .57),
      Offset(w * .50, h * .50),
      Offset(w * .57, h * .80),
    ]) {
      canvas.drawCircle(dot, w * .065, greenDot);
    }
    canvas.drawCircle(Offset(w * .67, h * .42), w * .06, Paint()..color = CX.amber);
    canvas.drawCircle(Offset(w * .80, h * .65), w * .06, Paint()..color = CX.blue);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
      Rect.fromLTWH(field.left, field.top + field.height * .28, field.width * .18, field.height * .44),
      linePaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(field.right - field.width * .18, field.top + field.height * .28, field.width * .18, field.height * .44),
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

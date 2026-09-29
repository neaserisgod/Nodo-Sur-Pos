// Primera pantalla de la companion (fase 1, "POS aparte"): sin sesión válida
// con la cuenta autorizada no se pasa de acá. No navega manualmente al
// loguearse — `companion_app.dart` escucha `authStateChanges()` y decide solo
// cuándo mostrar el resto de la app (ver `_PuertaDeEntrada`).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/tema/tokens.dart';
import 'autenticacion.dart';
import 'tema/tema_companion.dart';
import '../ui/tema/iconos.dart';

class PantallaLogin extends StatefulWidget {
  const PantallaLogin({
    super.key,
    @visibleForTesting Future<AuthResponse?> Function()? iniciarSesionConGoogleDePrueba,
    @visibleForTesting Future<AuthResponse> Function(String, String)? registrarseConEmailDePrueba,
    @visibleForTesting Future<AuthResponse> Function(String, String)? iniciarSesionConEmailDePrueba,
    @visibleForTesting Future<void> Function()? cerrarSesionDePrueba,
    this.onEntrarSinCuenta,
  }) : _iniciarSesionConGoogle = iniciarSesionConGoogleDePrueba ?? iniciarSesionConGoogle,
       _registrarseConEmail = registrarseConEmailDePrueba ?? registrarseConEmail,
       _iniciarSesionConEmail = iniciarSesionConEmailDePrueba ?? iniciarSesionConEmail,
       _cerrarSesion = cerrarSesionDePrueba ?? cerrarSesionCompanion;

  final Future<AuthResponse?> Function() _iniciarSesionConGoogle;
  final Future<AuthResponse> Function(String, String) _registrarseConEmail;
  final Future<AuthResponse> Function(String, String) _iniciarSesionConEmail;
  final Future<void> Function() _cerrarSesion;

  /// "Entrar sin cuenta" (2026-09-28): para cuando Supabase no deja iniciar
  /// sesión — el celular trabaja contra la PC por el wifi del local. Null
  /// (tests viejos) = sin el botón.
  final VoidCallback? onEntrarSinCuenta;

  @override
  State<PantallaLogin> createState() => _PantallaLoginState();
}

class _PantallaLoginState extends State<PantallaLogin> {
  bool _registrando = false;
  bool _procesando = false;
  String? _error;

  final _emailCtrl = TextEditingController();
  final _contrasenaCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _contrasenaCtrl.dispose();
    super.dispose();
  }

  Future<void> _tras(Future<AuthResponse?> Function() accion) async {
    if (_procesando) return;
    setState(() {
      _procesando = true;
      _error = null;
    });
    try {
      final credencial = await accion();
      // null: el usuario canceló el selector de Google — no es un error.
      if (credencial == null) {
        setState(() => _procesando = false);
        return;
      }
      if (!esCuentaAutorizada(credencial.user)) {
        await widget._cerrarSesion();
        if (!mounted) return;
        setState(() {
          _procesando = false;
          _error = 'Esa cuenta no está autorizada para usar la companion.';
        });
        return;
      }
      // Autorizada: no hace falta navegar ni tocar `_procesando` — el
      // `StreamBuilder` de `companion_app.dart` va a mostrar el resto de la
      // app solo apenas `authStateChanges()` emita este user.
    } on AutenticacionCompanionException catch (e) {
      if (!mounted) return;
      setState(() {
        _procesando = false;
        _error = e.mensaje;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _procesando = false;
        _error = 'Algo salió mal ($e).';
      });
    }
  }

  void _continuarConGoogle() => _tras(widget._iniciarSesionConGoogle);

  void _confirmarEmail() {
    final email = _emailCtrl.text.trim();
    final contrasena = _contrasenaCtrl.text;
    if (email.isEmpty || contrasena.isEmpty) {
      setState(() => _error = 'Completá el email y la contraseña.');
      return;
    }
    _tras(
      () => _registrando
          ? widget._registrarseConEmail(email, contrasena)
          : widget._iniciarSesionConEmail(email, contrasena),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(EspacioCompanion.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(IconosPlazoleta.storefrontRounded, size: 56, color: colores.acento),
                  const SizedBox(height: EspacioCompanion.md),
                  Text(
                    'La Plazoleta',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: EspacioCompanion.xs),
                  Text(
                    'Iniciá sesión para entrar a la companion.',
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: colores.textoSecundario),
                  ),
                  const SizedBox(height: EspacioCompanion.xxl),
                  FilledButton.icon(
                    onPressed: _procesando ? null : _continuarConGoogle,
                    icon: const Icon(IconosPlazoleta.gMobiledataRounded, size: 28),
                    label: const Text('Continuar con Google'),
                  ),
                  const SizedBox(height: EspacioCompanion.xl),
                  Row(
                    children: [
                      Expanded(child: Divider(color: colores.borde)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: EspacioCompanion.md),
                        child: Text('o', style: TextStyle(color: colores.textoTenue)),
                      ),
                      Expanded(child: Divider(color: colores.borde)),
                    ],
                  ),
                  const SizedBox(height: EspacioCompanion.xl),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: EspacioCompanion.md),
                  TextField(
                    controller: _contrasenaCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Contraseña'),
                    onSubmitted: (_) => _confirmarEmail(),
                  ),
                  const SizedBox(height: EspacioCompanion.lg),
                  OutlinedButton(
                    onPressed: _procesando ? null : _confirmarEmail,
                    child: _procesando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_registrando ? 'Registrarme' : 'Iniciar sesión'),
                  ),
                  const SizedBox(height: EspacioCompanion.sm),
                  TextButton(
                    onPressed: _procesando
                        ? null
                        : () => setState(() {
                            _registrando = !_registrando;
                            _error = null;
                          }),
                    child: Text(
                      _registrando ? '¿Ya tenés cuenta? Iniciar sesión' : '¿No tenés cuenta? Registrarme',
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: EspacioCompanion.md),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colores.error),
                    ),
                  ],
                  if (widget.onEntrarSinCuenta != null) ...[
                    const SizedBox(height: EspacioCompanion.xl),
                    Divider(color: colores.borde),
                    const SizedBox(height: EspacioCompanion.md),
                    TextButton.icon(
                      onPressed: _procesando ? null : widget.onEntrarSinCuenta,
                      icon: const Icon(IconosPlazoleta.storefrontOutlined),
                      label: const Text('Entrar sin cuenta (por el wifi del local)'),
                    ),
                    Text(
                      'Para cuando no se puede iniciar sesión. El celular trabaja contra la PC '
                      'estando en el local; lo que no llegue a la PC se sincroniza cuando vuelvas '
                      'a iniciar sesión.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colores.textoSecundario),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

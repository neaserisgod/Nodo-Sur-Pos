// Raíz de la companion app Android — sin base de datos propia, sin
// servidor: arranca leyendo si ya hay un usuario elegido
// (`emparejamiento.dart`) y entra directo al menú. Emparejar con una PC por
// LAN ya no es parte de este arranque (ver comentario en `_decidir`).

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/identidad_sync.dart';
import '../data/sincronizacion_supabase.dart';
import 'autenticacion.dart';
import 'cambios_companion.dart';
import 'base_local.dart';
import 'emparejamiento.dart';
import 'identidad_dispositivo.dart';
import 'pantalla_elegir_usuario.dart';
import 'pantalla_login.dart';
import 'pantalla_menu_companion.dart';
import 'tema/tema_companion.dart';
import '../servicios/marca_actual.dart';

class CompanionApp extends StatelessWidget {
  const CompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (_) => '${marcaActual.value.nombre} — Companion',
      debugShowCheckedModeBanner: false,
      theme: TemaCompanion.claro,
      darkTheme: TemaCompanion.oscuro,
      home: const PuertaDeEntradaCompanion(),
    );
  }
}

/// Delante de todo lo demás (emparejamiento con la PC, elegir usuario de
/// turno): sin sesión de la cuenta autorizada, no se pasa de acá (Bruno,
/// 2026-09-18: "login con Google o register", fase 1 de volver la companion
/// un POS aparte). Escucha `authStateChanges()` en vez de navegar a mano —
/// un login exitoso en `PantallaLogin` no hace nada más que dejar que este
/// stream emita el nuevo user, y acá se decide solo. Pública (no privada como
/// el resto de este archivo) para poder testear la decisión con un stream
/// falso, sin tocar el plugin real de Firebase.
class PuertaDeEntradaCompanion extends StatefulWidget {
  const PuertaDeEntradaCompanion({
    super.key,
    @visibleForTesting Stream<User?>? authStateDePrueba,
    @visibleForTesting bool iniciarSyncSupabaseDePrueba = true,
  }) : _authState = authStateDePrueba,
       _iniciarSyncSupabase = iniciarSyncSupabaseDePrueba;

  final Stream<User?>? _authState;

  /// Solo para tests: en `flutter test` (no `integration_test`) no hay
  /// cliente real de Supabase ni tiene sentido abrir la base local de
  /// verdad — sin esto, cada test que llega a `_PantallaInicial` abriría un
  /// archivo SQLite real y dejaría un `Timer.periodic` colgado.
  final bool _iniciarSyncSupabase;

  /// `Stream.value(null)` si Supabase no llegó a inicializarse al arrancar
  /// (sin red, timeout — ver el comentario de `main.dart`) — cae a
  /// `PantallaLogin` en vez de crashear toda la companion.
  Stream<User?> _streamDeAuth() {
    try {
      return Supabase.instance.client.auth.onAuthStateChange.map((estado) => estado.session?.user);
    } catch (_) {
      return Stream.value(null);
    }
  }

  @override
  State<PuertaDeEntradaCompanion> createState() => _PuertaDeEntradaCompanionState();
}

class _PuertaDeEntradaCompanionState extends State<PuertaDeEntradaCompanion> {
  /// "Entrar sin cuenta" (2026-09-28): Supabase cortó el servicio por cuota
  /// y el login no anda — el celular sigue trabajando contra la PC por el
  /// wifi del local, sin sincronizar por internet. Null mientras se lee.
  bool? _sinCuenta;

  @override
  void initState() {
    super.initState();
    leerModoSinCuenta().then((v) {
      if (mounted) setState(() => _sinCuenta = v);
    });
  }

  Future<void> _entrarSinCuenta() async {
    await guardarModoSinCuenta(true);
    if (mounted) setState(() => _sinCuenta = true);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: widget._authState ?? widget._streamDeAuth(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting || _sinCuenta == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (esCuentaAutorizada(snapshot.data)) {
          // Volvió el login: se sale del modo sin cuenta solo.
          if (_sinCuenta!) {
            _sinCuenta = false;
            guardarModoSinCuenta(false);
          }
          return _PantallaInicial(iniciarSyncSupabase: widget._iniciarSyncSupabase);
        }
        if (_sinCuenta!) {
          // Sin sesión no hay sync por internet que arrancar.
          return const _PantallaInicial(iniciarSyncSupabase: false);
        }
        return PantallaLogin(onEntrarSinCuenta: _entrarSinCuenta);
      },
    );
  }
}

class _PantallaInicial extends StatefulWidget {
  const _PantallaInicial({required this.iniciarSyncSupabase});

  final bool iniciarSyncSupabase;

  @override
  State<_PantallaInicial> createState() => _PantallaInicialState();
}

class _PantallaInicialState extends State<_PantallaInicial> {
  @override
  void initState() {
    super.initState();
    // Sync por Supabase (fase 2, "cómo hacemos con las sync") contra la
    // base LOCAL del celular (`base_local.dart`) — a diferencia del sync
    // HTTP viejo, esto nunca toca la base de la PC en vivo, así que no
    // aplica la razón por la que `_decidir` de abajo evita sincronizar solo
    // al arrancar (no compite por el mismo acceso serializado a SQLite de
    // la PC). Se llega acá recién con la cuenta autorizada ya logueada
    // (`PuertaDeEntradaCompanion`), así que siempre hay sesión.
    if (widget.iniciarSyncSupabase) _asegurarSyncSupabaseCompanion();
    _decidir();
  }

  Future<void> _decidir() async {
    // Se fija una sola vez por arranque, antes de cualquier pantalla — hoy
    // no hay ninguna escritura local todavía (fase 1 del rediseño de
    // sincronización, sin `PuertoLocal` en producción), pero cuando la haya
    // (fase 3) tiene que estar listo desde el primer frame.
    establecerIdDispositivo(await idDispositivoEstable());
    // Emparejar con una PC por LAN ya NO es un paso obligatorio de arranque
    // (Bruno, 2026-09-18: "no debería tener que escanear ya, es
    // innecesario" — justo el objetivo de esta fase era que la companion
    // funcione como un POS aparte, sin depender de la PC). Con login de
    // Google + sync por Supabase, la identidad y los datos ya no dependen
    // de emparejar nada: se entra directo a elegir usuario / al menú, y
    // `PantallaMenuCompanion` ya tolera sin problema no tener `conexion`
    // (`_iniciarConexion` se queda con `_cliente`/`_servicio` en null).
    // Emparejar sigue disponible a pedido desde Gestión → "Desconectar de
    // esta PC" (mismo botón sirve para conectar si todavía no hay nada que
    // desconectar).
    final usuario = await leerUsuario();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => usuario == null
            ? const PantallaElegirUsuario()
            : const PantallaMenuCompanion(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

/// Vive mientras dure el proceso (mismo criterio que `identidad_sync.dart`),
/// no atada al ciclo de vida de `_PantallaInicial` — esa pantalla se
/// reemplaza (`pushReplacement`) apenas decide a dónde ir, así que guardar
/// esto en su `State` la cortaría enseguida.
///
/// Pública (Bruno, 2026-09-18: "no hay nada que actualice la app cuando se
/// sincronizó, tengo que entrar y volver a salir") — las pantallas de
/// `lib/companion/pantalla_*.dart` se suscriben a
/// `syncSupabaseCompanion?.cambiosAplicados` para refrescarse solas apenas
/// algo nuevo se aplicó a la base local, en vez de necesitar salir y volver
/// a entrar.
SincronizacionSupabase? syncSupabaseCompanion;

void _asegurarSyncSupabaseCompanion() {
  if (syncSupabaseCompanion != null) return;
  final sync = SincronizacionSupabase(baseLocalCompanion())..iniciar();
  // Lo que baja por Supabase también avisa por el canal único de la
  // companion (`cambios_companion.dart`), igual que la sync por wifi.
  sync.cambiosAplicados.listen((_) => avisarCambiosCompanion());
  syncSupabaseCompanion = sync;
}

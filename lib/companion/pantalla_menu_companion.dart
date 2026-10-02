// Menú de la companion app, una vez emparejada y con usuario elegido.
//
// Navbar estilo Mercado Pago (El dueño, 2026-09-13): cuatro pestañas fijas
// más un botón circular elevado en el medio, igual que el botón de QR de esa
// app. Ese botón era el carrito (vender); pasó a ser un escáner de código
// (El dueño, 2026-09-17: "en lugar de que sea un carrito el botón del medio,
// que sea un escáner") que abre directo a editar el producto si ya existe, o
// a darlo de alta completo si no — "vender" se mudó a un CTA propio en la
// pestaña Inicio (El dueño, 2026-09-18: "reacomodación de absolutamente todos
// los elementos" — dejó de competir en igualdad de condiciones con
// "Movimiento de caja", la fusión de lo que antes eran Gasto e Ingreso
// rápido por separado). Esta clase sigue siendo la raíz que sostiene el
// estado compartido entre pestañas (carrito, cliente HTTP, sesión de caja,
// usuario, catálogo de proveedores/categorías para el escáner) y arma cada
// pestaña como un widget aparte (`pantalla_inicio_companion.dart`,
// `pantalla_precios.dart`, `pantalla_historial_ventas.dart`,
// `pantalla_gestion_companion.dart`). Ya no hay una pestaña "Buscar": El dueño
// (2026-09-13) pidió juntarla con el carrito ("buscar está estrictamente
// ligado al carrito... para que al entrar en el carrito directamente se
// pueda agregar y cobrar desde ahí mismo") — el buscador vive dentro de
// `PantallaCarritoVenta`.
//
// Las cuatro pestañas hoy: Inicio, Productos (`pantalla_precios.dart`,
// El dueño 2026-09-19: "productos pasa a ser la segunda pantalla más
// importante después de vender" — promovida desde adentro de Gestión, con
// su búsqueda y sus filtros de catálogo), Historial y Gestión (ocupa el
// lugar que tenía "Más" — esa pestaña se eliminó, fusionada en Gestión:
// "gestión poniéndolo donde va más").
//
// Las pestañas viven en un `PageView` (El dueño, 2026-09-13: "quiero la
// posibilidad de poder deslizar entre pantallas"), no un `IndexedStack` —
// mismos widgets, pero ahora también se llega a ellos arrastrando el dedo,
// no solo tocando la navbar. Cada uno se envuelve en `_PaginaSiempreViva`
// para no perder su estado (ej. los filtros de "Productos") al deslizar a
// otra pestaña y volver — mismo objetivo que ya cumplía el `IndexedStack`,
// que por default no lo garantiza un `PageView`.

import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/caja.dart' show necesitaArqueoIntermedio;
import '../domain/venta.dart';
import '../ui/tema/tokens.dart';
import 'cambios_companion.dart';
import 'escucha_pc.dart';
import 'flujo_modo_uso.dart';
import 'modo_uso.dart';
import 'pantalla_elegir_modo.dart';
import 'sync_nube_companion.dart';
import 'actualizacion.dart';
import 'base_local.dart';
import 'cliente_companion.dart';
import 'dialogo_arqueo_intermedio_companion.dart';
import 'dialogo_cierre_companion.dart';
import 'emparejamiento.dart';
import 'mensaje_error.dart';
import 'navbar_companion.dart';
import 'navegacion.dart';
import 'pantalla_arqueo.dart';
import 'pantalla_carrito_venta.dart';
import 'pantalla_encargues_companion.dart';
import 'pantalla_movimiento_caja.dart';
import 'pantalla_gestion_companion.dart';
import 'pantalla_historial_ventas.dart';
import 'pantalla_inicio_companion.dart';
import 'pantalla_precios.dart';
import 'puerto_local.dart';
import 'seleccion_servicio.dart';
import 'servicio_companion.dart';
import 'servicio_companion_offline.dart';
import 'servicio_sincronizacion.dart';

class PantallaMenuCompanion extends StatefulWidget {
  const PantallaMenuCompanion({super.key});

  @override
  State<PantallaMenuCompanion> createState() => _PantallaMenuCompanionState();
}

class _PantallaMenuCompanionState extends State<PantallaMenuCompanion>
    with WidgetsBindingObserver {
  /// 0 Inicio, 1 Gestión, 2 Historial, 3 Más.
  int _indice = 0;
  final _paginaController = PageController();

  String? _nombreUsuario;

  /// Evita que un doble toque en un acceso (fácil de disparar con el dedo
  /// en un celular grande) pushee la misma pantalla dos veces mientras la
  /// primera navegación todavía no completó.
  bool _navegando = false;

  /// Estado de caja abierta/cerrada, para el indicador de "Inicio" y el
  /// acceso a "Arqueo" desde ahí y desde "Más".
  SesionCompanion? _sesion;

  /// Total y desglose efectivo/Mercado Pago de hoy, para el resumen de
  /// "Inicio" (El dueño, 2026-09-14). Se pide junto con `_sesion` en
  /// `_revisarSesion` — mismo endpoint que ya usaba "Arqueo"
  /// (`/caja/estado`), null con la caja cerrada porque el servidor no
  /// tiene sesión sobre la que resumir.
  EstadoCajaCompanion? _estadoCaja;

  /// Exclusivo de imprimir ticket (todo lo demás que antes necesitaba esto
  /// — Arqueo, cierres, historial, Point — ya pasó a `_servicio`, el dueño
  /// 2026-09-18). Null sin PC emparejada.
  ClienteCompanion? _cliente;

  /// Con fallback automático a la base local si la PC no responde o no hay
  /// ninguna emparejada (fase 3/4, "companion sin depender del escritorio")
  /// — nunca queda en null.
  ServicioCompanion? _servicio;

  /// true si `leerConexion()` devolvió una PC configurada — para
  /// `AvisoModoLocal`: sin esto, ese aviso aparecería siempre que no hay PC,
  /// aunque nunca se haya emparejado ninguna (su modo normal hoy).
  bool _pcEmparejada = false;
  ModoUso? _modoUso;
  int? _usuarioId;
  final List<LineaVenta> _carrito = [];


  /// true si pasaron 2hs desde el último arqueo — muestra el aviso (no
  /// bloqueante, el dueño 2026-09-15) en "Inicio", nunca abre nada solo.
  bool _arqueoIntermedioVencido = false;
  late final Timer _tickArqueoIntermedio;

  /// El dueño, 2026-09-18: "no hay nada que actualice la app cuando se
  /// sincronizó, tengo que entrar y volver a salir" — se suscribe a
  /// `avisosCambiosCompanion` (la sync por wifi o la de Supabase) para
  /// refrescar Inicio y el catálogo del escáner solo, apenas la sync trae
  /// algo nuevo a la base local, en vez de esperar al chequeo de 1 minuto.
  StreamSubscription<void>? _subCambiosSync;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    leerUsuario().then((u) {
      if (mounted) {
        setState(() {
          _nombreUsuario = u?.nombre;
          _usuarioId = u?.id;
        });
      }
    });
    _iniciarConexion();
    _revisarActualizacion();
    _revisarSesion();
    _subCambiosSync = avisosCambiosCompanion.listen((_) {
      _revisarSesion();
    });
    // Aviso de arqueo cada 2hs (El dueño, 2026-09-13: "sincronizado con la app
    // desktop"; 2026-09-15: "que se cambie a una sugerencia únicamente" —
    // ya no abre nada solo) — mismo patrón que `VentaControlador` en el
    // escritorio (`_tickArqueoIntermedio`, 1 minuto alcanza para una
    // ventana de 2 horas): el aviso tiene que aparecer solo, sin que nadie
    // tenga que volver a entrar a la app para notarlo.
    _tickArqueoIntermedio = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _revisarSesion(),
    );
  }

  /// El dueño, 2026-09-07: "la apk no detecta la actualización si no la
  /// cierro y abro de vuelta" — antes solo chequeaba una vez, en
  /// `initState()`. Volver del segundo plano (sin cerrar del todo la app)
  /// vuelve a chequear, para agarrar una versión publicada mientras tanto
  /// sin forzar un reinicio completo del celular tampoco.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _revisarActualizacion();
      _revisarSesion();
      escuchaPcCompanion?.reconectarSiHaceFalta();
    }
  }

  /// Resuelve `_cliente`/`_servicio` una sola vez por apertura del menú —
  /// `resolverServicioCompanion` hace un único ping y decide (El dueño,
  /// 2026-09-17: "la conexión solo detecta 1 vez"), nada de reintentar la
  /// PC en cada acción después.
  ///
  /// Sin PC emparejada (El dueño, 2026-09-18: "no debería tener que escanear
  /// ya, es innecesario"), `_servicio` NO se queda en null — se resuelve
  /// directo contra la base local sincronizada por Supabase
  /// (`ServicioCompanionOffline(PuertoLocal(...))`), el mismo camino que ya
  /// usa `resolverServicioCompanion` cuando la PC no contesta. Sin esto,
  /// "Vender"/Arqueo/Movimiento de caja quedaban silenciosamente sin hacer
  /// nada en cualquier celular que nunca emparejó — no era solo "elegir
  /// usuario" el trabado, era toda la companion. `_cliente` sí se queda en
  /// null sin PC: es exclusivo de imprimir ticket, que sigue necesitando la
  /// PC de verdad.
  Future<void> _iniciarConexion() async {
    final conexion = await leerConexion();
    final modo = resolverModoUso(guardado: await leerModoUso(), tieneConexion: conexion != null, tieneUsuario: true);
    if (!mounted) return;
    final servicio = conexion == null
        ? ServicioCompanionOffline(PuertoLocal(baseLocalCompanion()))
        : await resolverServicioCompanion(conexion);
    if (!mounted) return;
    setState(() {
      _cliente = conexion == null ? null : ClienteCompanion(conexion);
      _servicio = servicio;
      _pcEmparejada = conexion != null;
      _modoUso = modo;
    });
    // Sync instantánea por wifi (2026-09-28): con la PC emparejada, queda
    // escuchando sus avisos — cualquier cambio en la PC (abrir la caja, una
    // venta, un precio) llega en el momento, sin reiniciar la app.
    final sync = await syncNubeDelCelular();
    sync.conmutador.definirPc(emparejada: conexion != null);
    if (conexion != null) {
      var escucha = escuchaPcCompanion;
      if (escucha == null || escucha.conexion.ip != conexion.ip || escucha.conexion.token != conexion.token) {
        escucha?.detener();
        escucha = escuchaPcCompanion = EscuchaPc(conexion, baseLocalCompanion());
        escucha.alCambiarConexion = _alCambiarConexionPc;
        escucha.iniciar();
      } else {
        // Una escucha ya andando de una apertura anterior del menú: el aviso pasa a este.
        escucha.alCambiarConexion = _alCambiarConexionPc;
        _alCambiarConexionPc(escucha.conectada);
      }
    } else {
      escuchaPcCompanion?.detener();
      escuchaPcCompanion = null;
    }
  }

  /// La PC dejó de contestar o volvió (2026-10-01: "si se apaga la PC el sistema tiene que seguir funcionando").
  /// Las pantallas pasan al instante a trabajar con la base local — que la sync por wifi mantiene al día — y de
  /// vuelta a la PC cuando contesta. Si la PC sigue sin contestar, el conmutador pasa a la nube pasados unos
  /// segundos (`conmutador_sync.dart`).
  void _alCambiarConexionPc(bool conectada) {
    syncNubeCompanion?.conmutador.pcConectada(conectada);
    if (!mounted) return;
    unawaited(_cambiarServicioPorConexion(conectada));
  }

  Future<void> _cambiarServicioPorConexion(bool conectada) async {
    final conexion = await leerConexion();
    if (conexion == null || !mounted) return;
    final ServicioCompanion servicio =
        conectada ? ClienteCompanion(conexion) : ServicioCompanionOffline(PuertoLocal(baseLocalCompanion()));
    setState(() => _servicio = servicio);
    _revisarSesion();
  }

  /// Resuelve su propio [ServicioCompanion], igual que `_iniciarConexion`
  /// — así no depende de que `_servicio` ya esté armado (initState dispara
  /// las dos cosas en paralelo), y sin PC emparejada cae igual a la base
  /// local en vez de quedarse sin nada que mostrar (El dueño, 2026-09-18: "no
  /// debería tener que escanear ya, es innecesario"). Silencioso si falla:
  /// sin caja abierta ni PC ni datos locales todavía no hay nada que
  /// mostrar, no es un error.
  Future<void> _revisarSesion() async {
    final conexion = await leerConexion();
    if (!mounted) return;
    final servicio = conexion == null
        ? ServicioCompanionOffline(PuertoLocal(baseLocalCompanion()))
        : await resolverServicioCompanion(conexion);
    try {
      final sesion = await servicio.sesion();
      if (mounted) {
        setState(() {
          _sesion = sesion;
          _arqueoIntermedioVencido = _calcularArqueoIntermedioVencido(sesion);
        });
      }
      if (!sesion.abierta) {
        if (mounted) setState(() => _estadoCaja = null);
        return;
      }
      final estado = await servicio.estadoCaja();
      if (mounted) setState(() => _estadoCaja = estado);
    } catch (_) {
      // Sin diagnóstico visible, mismo criterio que `_revisarActualizacion`.
    }
  }

  /// Mismo cálculo que `VentaControlador.arqueoIntermedioVencido` en el
  /// escritorio (`domain/caja.dart`, Regla 3): "desde" es el último arqueo
  /// intermedio de esta sesión, o la apertura si todavía no hubo ninguno.
  bool _calcularArqueoIntermedioVencido(SesionCompanion sesion) {
    if (!sesion.abierta) return false;
    final desde = sesion.fechaUltimoArqueoIntermedio ?? sesion.fechaApertura;
    if (desde == null) return false;
    return necesitaArqueoIntermedio(desde: desde, ahora: DateTime.now());
  }

  /// Abre el diálogo a pedido, desde el aviso de "Inicio" — antes se abría
  /// solo al vencer las 2hs (El dueño, 2026-09-15: "que se cambie a una
  /// sugerencia únicamente"). Al confirmar, vuelve a pedir `/sesion` — ahí
  /// es donde la sincronización se nota de verdad: si el arqueo se hizo en
  /// el escritorio mientras tanto, esta misma lectura ya trae la fecha
  /// nueva y el aviso desaparece sin hacer nada más acá.
  Future<void> _hacerArqueoIntermedio() async {
    if (_servicio == null || _usuarioId == null) return;
    await mostrarDialogoArqueoIntermedioCompanion(
      context,
      servicio: _servicio!,
      usuarioId: _usuarioId!,
    );
    await _revisarSesion();
  }

  Future<void> _abrirArqueo() async {
    if (_servicio == null) return;
    await _irA((_) => PantallaArqueo(servicio: _servicio!));
  }

  /// Cerrar caja de verdad desde el celular (El dueño, 2026-09-19: "que deje
  /// cerrar caja desde el celular") — mismo criterio que
  /// `_hacerArqueoIntermedio`: el diálogo hace todo, acá solo se vuelve a
  /// pedir `/sesion` al volver para que "Inicio"/"Gestión" dejen de mostrar
  /// la caja como abierta sin tener que salir y volver a entrar.
  Future<void> _cerrarCaja() async {
    if (_servicio == null || _usuarioId == null) return;
    await mostrarDialogoCierreCompanion(
      context,
      servicio: _servicio!,
      usuarioId: _usuarioId!,
      precargaEfectivoCentavos: _sesion?.ultimoArqueoEfectivoCentavos,
      precargaMpCentavos: _sesion?.ultimoArqueoMpCentavos,
      horaPrecarga: _sesion?.fechaUltimoArqueoIntermedio,
    );
    await _revisarSesion();
  }

  /// Empuja [builder] con `pushSinTeclado`, ignorando el toque si ya hay
  /// una navegación en vuelo — sin esto, dos toques rápidos en un acceso
  /// (fácil con el dedo en un celular grande) pusheaban la misma pantalla
  /// dos veces.
  Future<void> _irA(WidgetBuilder builder) async {
    if (_navegando) return;
    setState(() => _navegando = true);
    try {
      await pushSinTeclado(context, builder);
    } finally {
      if (mounted) setState(() => _navegando = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickArqueoIntermedio.cancel();
    _subCambiosSync?.cancel();
    _paginaController.dispose();
    super.dispose();
  }

  /// Cambia de pestaña deslizando el `PageView` (Alt+tab de la navbar o
  /// vuelta a "Inicio" con el back del sistema) — el propio arrastre del
  /// usuario no pasa por acá, dispara `onPageChanged` directamente.
  void _irAPagina(int i) {
    setState(() => _indice = i);
    _paginaController.animateToPage(
      i,
      duration: Animaciones.media,
      curve: Animaciones.curva,
    );
  }

  /// "Vender" en Inicio (El dueño, 2026-09-17: el carrito dejó de ser el botón
  /// central, ahora vive acá) — el carrito es la misma lista (referencia
  /// compartida) que le pasamos a `PantallaCarritoVenta`; al volver, revisa
  /// la sesión por si se abrió la caja de emergencia ahí adentro, mismo
  /// criterio que gasto/ingreso rápido.
  /// `_cliente` (PC) NO es obligatorio acá (El dueño, 2026-09-18: "no debería
  /// tener que escanear ya, es innecesario") — solo hace falta para
  /// imprimir, y `PantallaCarritoVenta` ya lo tolera en null (avisa en vez
  /// de tirar). Vender de verdad corre entero contra `_servicio`.
  Future<void> _abrirCarritoDesdeInicio() async {
    if (_servicio == null || _usuarioId == null) return;
    await _irA(
      (_) => PantallaCarritoVenta(
        cliente: _cliente,
        servicio: _servicio!,
        usuarioId: _usuarioId!,
        carrito: _carrito,
        encargueId: _encargueId,
      ),
    );
    // Cobrada o vaciada: ya no entrega ese encargue (si quedó con líneas, sigue siendo la misma venta).
    if (_carrito.isEmpty) _encargueId = null;
    _revisarSesion();
  }

  /// El encargue por apartado que el carrito está entregando (null en una venta común).
  int? _encargueId;

  /// Encargues (El dueño, 2026-10-02). "Entregar" vuelve acá con el encargue elegido: se arma el carrito con lo
  /// apartado a los precios de hoy y se abre; al cobrar, la venta libera lo apartado.
  Future<void> _abrirEncargues() async {
    if (_servicio == null || _usuarioId == null || _navegando) return;
    setState(() => _navegando = true);
    EntregaEncargue? entrega;
    try {
      entrega = await pushSinTeclado<EntregaEncargue>(
        context,
        (_) => PantallaEncarguesCompanion(servicio: _servicio!, usuarioId: _usuarioId!, hayVentaArmada: _carrito.isNotEmpty),
      );
    } finally {
      if (mounted) setState(() => _navegando = false);
    }
    if (entrega == null || !mounted) return;
    try {
      final lineas = await _servicio!.lineasDeEncargue(entrega.id);
      _carrito
        ..clear()
        ..addAll(lineas);
      _encargueId = entrega.id;
    } catch (_) {
      return; // sin lineas no se abre un carrito vacío: el encargue sigue pendiente y se puede reintentar
    }
    await _abrirCarritoDesdeInicio();
  }

  Future<void> _abrirMovimientoCaja(TipoMovimientoCaja tipo) async {
    await _irA((_) => PantallaMovimientoCaja(tipoInicial: tipo));
    _revisarSesion(); // pudo haberse abierto la caja de emergencia ahí adentro
  }

  /// Pull-to-refresh de "Inicio" (El dueño: "haciendo pull para abajo en la app
  /// Android") — el único disparador de sync que queda (2026-09-17: se sacó
  /// el automático de `companion_app.dart`/`pantalla_emparejamiento.dart`,
  /// volvía lenta a toda la companion cada vez que se abría). También es el
  /// momento en que se vuelve a detectar si la PC está o no (mismo criterio
  /// de "una sola vez" que `_iniciarConexion` — nada de reintentar sola en
  /// medio de otra acción): si `_servicio` había quedado en modo local
  /// porque la PC no contestó al abrir la companion, y ahora sí contesta,
  /// acá es donde se entera y vuelve a usarla en vivo. Silencioso si falla,
  /// mismo criterio que `_revisarActualizacion`/`_revisarSesion`.
  Future<void> _sincronizar() async {
    if (_cliente == null) return;
    await sincronizarConPc(_cliente!);
    final conexion = await leerConexion();
    if (conexion == null || !mounted) return;
    final servicio = await resolverServicioCompanion(conexion);
    if (mounted) {
      setState(() => _servicio = servicio);
      }
  }

  // El dueño, 2026-09-07: "necesito que saques la versión de abajo" — el
  // diagnóstico visible (Celular X · PC Y, o el error) que antes vivía al
  // pie de esta pantalla se sacó. El chequeo en sí sigue: sin él, la
  // banda de "Hay una versión distinta" tampoco podría aparecer.
  //
  // El dueño, 2026-09-18: "que directamente descargue en automático" — el
  // banner con botón "Actualizar" se sacó (era el ejemplo #1 de "esto
  // parece pegote"). Ahora, detectar una versión distinta dispara la
  // descarga sola; Android igual pide confirmación para instalar (nunca
  // deja hacerlo en silencio, `actualizacion.dart`), así que no se pierde
  // el control, solo se salta el paso intermedio de nuestro propio botón.
  // `_actualizacionYaOfrecida` evita volver a abrir el instalador solo
  // porque el chequeo periódico (cada vez que la app vuelve de segundo
  // plano) sigue viendo la misma versión distinta mientras la persona
  // todavía no completó la instalación anterior.
  bool _actualizacionYaOfrecida = false;

  /// El dueño, 2026-09-19: "no me salió la actualización" — causa real: la
  /// IP/token guardados en el celular habían quedado viejos (cambio de
  /// máquina de fase 13), y este chequeo específico es el único que NO
  /// cae al fallback offline del resto de la companion (fase 4) — habla
  /// SIEMPRE directo con `ClienteCompanion(conexion)`, así que fallaba en
  /// silencio sin ninguna pista de por qué. Este flag no reabre el
  /// diagnóstico general que el dueño pidió sacar (2026-09-07/18) — es un
  /// aviso puntual, solo para ESTE chequeo, solo cuando SÍ hay una PC
  /// emparejada y no se la pudo alcanzar para buscar una actualización.
  bool _actualizacionSinConexion = false;

  Future<void> _revisarActualizacion() async {
    // Sin PC emparejada igual se mira el sitio: ahí vive el APK publicado.
    final conexion = await leerConexion();
    try {
      final estado = await revisarActualizacion(
        conexion == null ? null : ClienteCompanion(conexion),
      );
      if (mounted) setState(() => _actualizacionSinConexion = false);
      if (estado.hayActualizacion && !_actualizacionYaOfrecida) {
        _actualizacionYaOfrecida = true;
        await _actualizar(estado.oferta);
      }
    } catch (_) {
      // Sin PC emparejada y sin sitio no hay a quién culpar: no se avisa.
      if (mounted) setState(() => _actualizacionSinConexion = conexion != null);
    }
  }

  Future<void> _actualizar([OfertaSitio? oferta]) async {
    final conexion = await leerConexion();
    if (conexion == null && oferta == null) return;
    try {
      await descargarEInstalarActualizacion(
        conexion == null ? null : ClienteCompanion(conexion),
        oferta: oferta,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo actualizar: ${mensajeDeError(e)}'),
          ),
        );
      }
    }
  }

  Future<void> _cambiarUsuario() async {
    await olvidarUsuario();
    if (mounted) Navigator.of(context).pop();
  }

  /// Cambiar entre "PC y celular" y "solo celular" (antes "Desconectar de esta PC", que solo servía para volver
  /// a emparejar). Ver `flujo_modo_uso.dart`.
  void _cambiarModo() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PantallaElegirModo(
          actual: _modoUso,
          alElegir: (contexto, modo) => elegirModo(contexto, modo, actual: _modoUso),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Con el back del sistema (o el gesto) en una pestaña que no es
      // "Inicio", volvemos a "Inicio" en vez de salir de la app de una —
      // mismo criterio que cualquier app con navbar de pestañas.
      canPop: _indice == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _irAPagina(0);
      },
      child: Scaffold(
        // El `PageView` pasa por debajo de la navbar de verdad (El dueño,
        // 2026-09-18) — sin esto, `Scaffold` reserva su propio espacio para
        // `bottomNavigationBar` con el fondo de pantalla detrás, y la barra
        // "flotante" en realidad flota sobre una franja vacía del mismo
        // color, no sobre contenido — se ve como un recuadro sólido, no
        // como algo suspendido en el aire (y el vidrio de la barra no tiene
        // nada real que desenfocar). Cada pestaña agrega
        // `NavbarCompanion.espacioReservado` de padding inferior para que
        // su último elemento no quede oculto detrás de la barra.
        extendBody: true,
        body: PageView(
          controller: _paginaController,
          onPageChanged: (i) => setState(() => _indice = i),
          children: [
            _PaginaSiempreViva(
              child: PantallaInicioCompanion(
                nombreUsuario: _nombreUsuario,
                usuarioId: _usuarioId,
                sesion: _sesion,
                estadoCaja: _estadoCaja,
                arqueoIntermedioVencido: _arqueoIntermedioVencido,
                onHacerArqueoIntermedio: _hacerArqueoIntermedio,
                navegando: _navegando,
                irA: _irA,
                onAbrirMovimientoCaja: _abrirMovimientoCaja,
                onSincronizar: _sincronizar,
                carrito: _carrito,
                onVender: _abrirCarritoDesdeInicio,
                servicio: _servicio,
                pcEmparejada: _pcEmparejada,
                actualizacionSinConexion: _actualizacionSinConexion,
              ),
            ),
            const _PaginaSiempreViva(child: PantallaPrecios()),
            const _PaginaSiempreViva(child: PantallaHistorialVentas()),
            _PaginaSiempreViva(
              child: PantallaGestionCompanion(
                navegando: _navegando,
                irA: _irA,
                sesion: _sesion,
                onAbrirArqueo: _abrirArqueo,
                onCerrarCaja: _cerrarCaja,
                onCambiarUsuario: _cambiarUsuario,
                onCambiarModo: _cambiarModo,
                modoUso: _modoUso,
                usuarioId: _usuarioId,
                onAbrirEncargues: _abrirEncargues,
              ),
            ),
          ],
        ),
        bottomNavigationBar: NavbarCompanion(indice: _indice, onSeleccionar: _irAPagina),
      ),
    );
  }
}

/// Mantiene viva una pestaña del `PageView` aunque quede lejos de la
/// visible — sin esto, deslizar de "Inicio" a "Más" (dos pestañas) podía
/// reconstruir "Gestión" al pasar por el medio y perder su estado, algo
/// que el `IndexedStack` anterior no dejaba pasar nunca.
class _PaginaSiempreViva extends StatefulWidget {
  const _PaginaSiempreViva({required this.child});

  final Widget child;

  @override
  State<_PaginaSiempreViva> createState() => _PaginaSiempreVivaState();
}

class _PaginaSiempreVivaState extends State<_PaginaSiempreViva>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

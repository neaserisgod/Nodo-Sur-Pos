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
import 'package:flutter/scheduler.dart';

import '../data/repositorio_tablero.dart' show tableroDelDia;
import '../domain/caja.dart' show necesitaArqueoIntermedio;
import '../domain/venta.dart';
import 'cambios_companion.dart';
import 'escucha_pc.dart';
import 'flujo_modo_uso.dart';
import 'modo_uso.dart';
import 'pantalla_elegir_modo.dart';
import 'sync_nube_companion.dart';
import 'actualizacion.dart';
import 'pantallas/hoja_actualizar_ns.dart';
import 'app_ns.dart';
import 'funciones_ns.dart';
import 'kit/kit_ns.dart';
import 'pantallas/hoja_abrir_caja_ns.dart';
import 'pantallas/hoja_contar_caja_ns.dart';
import 'pantallas/pantalla_cierre_ns.dart';
import 'pantallas/pantalla_caja_ns.dart';
import 'pantallas/pantalla_inicio_ns.dart';
import 'pantallas/pantalla_mas_ns.dart';
import 'pantallas/pantalla_productos_ns.dart';
import 'base_local.dart';
import 'cliente_companion.dart';
import 'emparejamiento.dart';
import 'navegacion.dart';
import 'pantalla_carrito_venta.dart';
import 'pantalla_encargues_companion.dart';
import 'pantalla_movimiento_caja.dart';
import 'pantalla_carga_historica.dart';
import 'pantalla_cargar_factura.dart';
import 'pantalla_promos.dart';
import 'pantalla_proveedores.dart';
import 'pantalla_cierres.dart';
import 'pantalla_configuracion_companion.dart';
import 'pantalla_consultar_precio.dart';
import 'pantalla_conteo_stock.dart';
import 'pantalla_entrar_con_cuenta.dart';
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
    with WidgetsBindingObserver
    implements ControladorAppNs {
  PestaniaNs _pestania = PestaniaNs.inicio;
  int _version = 0;

  @override
  final ValueNotifier<PendientesNs> pendientes = ValueNotifier(const PendientesNs());
  @override
  final ValueNotifier<DatosDiaNs> datosDia = ValueNotifier(const DatosDiaNs());
  @override
  final ValueNotifier<int> segmentoCaja = ValueNotifier(0);
  @override
  final ValueNotifier<bool> productosEnConteo = ValueNotifier(false);
  @override
  final ValueNotifier<bool> ocultarBarra = ValueNotifier(false);

  /// Hay una versión nueva publicada (con su oferta del sitio, si vino de ahí).
  bool _hayActualizacion = false;
  OfertaSitio? _ofertaActualizacion;

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
  int _minutosDesdeArqueo = 0;
  late final Timer _tickArqueoIntermedio;

  /// El dueño, 2026-09-18: "no hay nada que actualice la app cuando se
  /// sincronizó, tengo que entrar y volver a salir" — se suscribe a
  /// `avisosCambiosCompanion` (la sync por wifi o la de Supabase) para
  /// refrescar Inicio y el catálogo del escáner solo, apenas la sync trae
  /// algo nuevo a la base local, en vez de esperar al chequeo de 1 minuto.
  StreamSubscription<void>? _subCambiosSync;

  /// Cada cambio del menú (el servicio que se resuelve recién después de abrir, el usuario, la caja…) avisa a las
  /// pestañas que lo leen por `AppNs`: sin esto, Productos y Vender se quedaban esperando un servicio que ya estaba.
  @override
  void setState(VoidCallback fn) {
    super.setState(() {
      fn();
      _version++;
    });
    _publicar();
  }

  /// Lo mismo para las pantallas que cuelgan del navegador (ver `puenteAppNs`); si se está dibujando, al cuadro siguiente.
  void _publicar() {
    void poner() {
      if (mounted) puenteAppNs.value = (controlador: this, version: _version);
    }

    final fase = SchedulerBinding.instance.schedulerPhase;
    if (fase == SchedulerPhase.idle || fase == SchedulerPhase.postFrameCallbacks) {
      poner();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) => poner());
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _publicar();
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
    sinConexionGlobalNs.value = sinConexion;
    unawaited(_iniciarAvisosMp(modo));
    // Sync instantánea por wifi (2026-09-28): con la PC emparejada, queda
    // escuchando sus avisos — cualquier cambio en la PC (abrir la caja, una
    // venta, un precio) llega en el momento, sin reiniciar la app.
    try {
      final sync = await syncNubeDelCelular();
      sync.conmutador.definirPc(emparejada: conexion != null);
    } catch (_) {
      // Sin la sync por internet igual se escucha a la PC y se trabaja con la base del celular.
    }
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

  /// Avisos de Mercado Pago en el celular (El dueño, 2026-10-09: independizar el celular). El mismo servicio de la PC sobre la
  /// base del celular, solo en "Solo celular": con una PC, la campanita de la PC ya los muestra (y "Visto" no viaja entre
  /// equipos, así que se verían dos veces).
  int _avisosMp = 0;

  Future<void> _iniciarAvisosMp(ModoUso? modo) async {
    try {
      if (modo != ModoUso.soloCelular) {
        avisosMpCompanion?.detener();
        _alCambiarAvisosMp(0);
        return;
      }
      final avisos = await avisosMpDelCelular();
      avisos.pendientes.removeListener(_escucharAvisosMp);
      avisos.pendientes.addListener(_escucharAvisosMp);
      avisos.iniciar();
    } catch (_) {
      // Sin cuenta o sin internet no hay avisos: no es un error para mostrar.
    }
  }

  void _escucharAvisosMp() => _alCambiarAvisosMp(avisosMpCompanion?.pendientes.value.length ?? 0);

  void _alCambiarAvisosMp(int n) {
    if (!mounted || n == _avisosMp) return;
    _avisosMp = n;
    final p = pendientes.value;
    pendientes.value = PendientesNs(
      faltaSepararCentavos: p.faltaSepararCentavos,
      proveedoresPendientes: p.proveedoresPendientes,
      proveedoresTotal: p.proveedoresTotal,
      sinStock: p.sinStock,
      hayActualizacion: p.hayActualizacion,
      arqueoVencido: p.arqueoVencido,
      minutosDesdeConteo: p.minutosDesdeConteo,
      avisosMp: n,
    );
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
    sinConexionGlobalNs.value = sinConexion;
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
        await _cargarDia();
        return;
      }
      final estado = await servicio.estadoCaja();
      if (mounted) setState(() => _estadoCaja = estado);
    } catch (_) {
      // Sin diagnóstico visible, mismo criterio que `_revisarActualizacion`.
    }
    await _cargarDia();
  }

  /// Mismo cálculo que `VentaControlador.arqueoIntermedioVencido` en el
  /// escritorio (`domain/caja.dart`, Regla 3): "desde" es el último arqueo
  /// intermedio de esta sesión, o la apertura si todavía no hubo ninguno.
  bool _calcularArqueoIntermedioVencido(SesionCompanion sesion) {
    if (!sesion.abierta) return false;
    final desde = sesion.fechaUltimoArqueoIntermedio ?? sesion.fechaApertura;
    if (desde == null) return false;
    _minutosDesdeArqueo = DateTime.now().difference(desde).inMinutes;
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
    await mostrarHojaContarCaja(context, servicio: _servicio!, usuarioId: _usuarioId!);
    await _revisarSesion();
  }

  /// Cerrar caja de verdad desde el celular (El dueño, 2026-09-19: "que deje
  /// cerrar caja desde el celular") — mismo criterio que
  /// `_hacerArqueoIntermedio`: el diálogo hace todo, acá solo se vuelve a
  /// pedir `/sesion` al volver para que "Inicio"/"Gestión" dejen de mostrar
  /// la caja como abierta sin tener que salir y volver a entrar.
  Future<void> _cerrarCaja() async {
    if (_servicio == null || _usuarioId == null) return;
    await irA<bool>(
      (_) => PantallaCierreNs(
        servicio: _servicio!,
        usuarioId: _usuarioId!,
        precargaEfectivoCentavos: _sesion?.ultimoArqueoEfectivoCentavos,
        precargaMpCentavos: _sesion?.ultimoArqueoMpCentavos,
        horaPrecarga: _sesion?.fechaUltimoArqueoIntermedio,
      ),
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
    avisosMpCompanion?.pendientes.removeListener(_escucharAvisosMp);
    sinConexionGlobalNs.value = false;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (puenteAppNs.value?.controlador == this) puenteAppNs.value = null;
    });
    pendientes.dispose();
    datosDia.dispose();
    segmentoCaja.dispose();
    productosEnConteo.dispose();
    ocultarBarra.dispose();
    super.dispose();
  }

  // ───────────── ControladorAppNs: lo que leen las pantallas del mock ─────────────

  @override
  ServicioCompanion? get servicio => _servicio;
  @override
  ClienteCompanion? get cliente => _cliente;
  @override
  int? get usuarioId => _usuarioId;
  @override
  String? get nombreUsuario => _nombreUsuario;
  @override
  SesionCompanion? get sesion => _sesion;
  @override
  EstadoCajaCompanion? get estadoCaja => _estadoCaja;
  @override
  List<LineaVenta> get carrito => _carrito;
  @override
  ModoUso? get modoUso => _modoUso;
  @override
  bool get pcEmparejada => _pcEmparejada;
  @override
  bool get sinConexion => _pcEmparejada && _servicio is ServicioCompanionOffline;
  @override
  bool get cajaAbierta => _sesion?.abierta ?? false;
  @override
  PestaniaNs get pestania => _pestania;

  @override
  void irAPestania(PestaniaNs p) {
    if (!mounted) return;
    setState(() {
      _pestania = p;
      if (p != PestaniaNs.vender) ocultarBarra.value = false;
    });
  }

  @override
  Future<T?> irA<T>(WidgetBuilder builder) async {
    if (_navegando) return null;
    setState(() => _navegando = true);
    try {
      return await pushSinTeclado<T>(context, builder);
    } finally {
      if (mounted) setState(() => _navegando = false);
    }
  }

  @override
  Future<void> refrescar() => _revisarSesion();

  @override
  Future<void> sincronizar() async {
    await _sincronizar();
    await _revisarSesion();
  }

  @override
  Future<void> abrirCaja() async {
    final servicio = _servicio;
    final usuario = _usuarioId;
    if (servicio == null || usuario == null) return;
    await mostrarHojaAbrirCaja(context, servicio: servicio, usuarioId: usuario);
    await _revisarSesion();
  }

  @override
  Future<void> abrirActualizacion() async {
    final conexion = await leerConexion();
    final oferta = _ofertaActualizacion;
    if (!mounted) return;
    await mostrarHojaActualizar(
      context,
      descargar: () => descargarActualizacion(conexion == null ? null : ClienteCompanion(conexion), oferta: oferta),
      instalar: instalarActualizacion,
    );
  }

  @override
  Future<void> cambiarUsuario() async {
    // El perfil sale de la cuenta con que se entró (El dueño, 2026-10-02): cambiar
    // de persona es entrar con otra cuenta.
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PantallaEntrarConCuenta()));
  }

  @override
  Future<void> cambiarModo() async => _cambiarModo();

  @override
  Future<void> abrirConteo({bool soloSinStock = false}) async {
    await irA((_) => const PantallaConteoStock());
  }

  @override
  Future<void> ejecutarFuncion(AccionFuncion accion) async {
    switch (accion) {
      case AccionFuncion.irAVender:
        irAPestania(PestaniaNs.vender);
      case AccionFuncion.consultarPrecio:
        await irA((_) => const PantallaConsultarPrecio());
      case AccionFuncion.productosCatalogo:
        productosEnConteo.value = false;
        irAPestania(PestaniaNs.productos);
      case AccionFuncion.productoNuevo:
      case AccionFuncion.productosEnLote:
        productosEnConteo.value = false;
        irAPestania(PestaniaNs.productos);
      case AccionFuncion.controlarStock:
        productosEnConteo.value = true;
        irAPestania(PestaniaNs.productos);
      case AccionFuncion.productosSinStock:
        await abrirConteo(soloSinStock: true);
      case AccionFuncion.cerrarCaja:
        if (cajaAbierta) {
          await _cerrarCaja();
        } else {
          irAPestania(PestaniaNs.caja);
        }
      case AccionFuncion.abrirCaja:
        irAPestania(PestaniaNs.caja);
        if (!cajaAbierta) await abrirCaja();
      case AccionFuncion.contarCaja:
        irAPestania(PestaniaNs.caja);
        await _hacerArqueoIntermedio();
      case AccionFuncion.gastoIngreso:
        await _abrirMovimientoCaja(TipoMovimientoCaja.gasto);
      case AccionFuncion.cajaSeparar:
        segmentoCaja.value = 1;
        irAPestania(PestaniaNs.caja);
      case AccionFuncion.cajaVentas:
        segmentoCaja.value = 2;
        irAPestania(PestaniaNs.caja);
      case AccionFuncion.cierresAnteriores:
        await irA((_) => const PaginaCierresAnteriores());
      case AccionFuncion.configuracion:
        await irA((_) => const PantallaConfiguracionCompanion());
      case AccionFuncion.diasAnteriores:
        await irA((_) => const PantallaCargaHistorica());
      case AccionFuncion.cargarFactura:
        await irA((_) => const PantallaCargarFactura());
      case AccionFuncion.promos:
        await irA((_) => const PantallaPromos());
      case AccionFuncion.proveedores:
        await irA((_) => const PantallaProveedores());
      case AccionFuncion.cambiarUsuario:
        await cambiarUsuario();
      case AccionFuncion.irAMas:
        irAPestania(PestaniaNs.mas);
      case AccionFuncion.actualizar:
        irAPestania(PestaniaNs.mas);
        if (_hayActualizacion) await abrirActualizacion();
      case AccionFuncion.desconectar:
        _cambiarModo();
    }
  }

  /// Cifras del día y pendientes, calculados de la base local (que la sync
  /// mantiene al día). Se vuelve a pedir con cada aviso de cambios.
  Future<void> _cargarDia() async {
    try {
      final t = await tableroDelDia(baseLocalCompanion());
      var sinStock = 0;
      try {
        sinStock = (await _servicio?.productosSinStock())?.length ?? 0;
      } catch (_) {
        // Sin lista de productos todavía: no se marca nada.
      }
      if (!mounted) return;
      datosDia.value = DatosDiaNs(
        vendidoCentavos: t.vendidoCentavos,
        gananciaCentavos: t.gananciaCentavos,
        efectivoCentavos: t.efectivoCentavos,
        mpCentavos: t.mpCentavos,
        ventas: t.tickets,
      );
      pendientes.value = PendientesNs(
        faltaSepararCentavos: t.faltaSepararCentavos,
        proveedoresPendientes: t.proveedoresPendientes,
        proveedoresTotal: t.proveedoresConAlgoQueSeparar,
        sinStock: sinStock,
        hayActualizacion: _hayActualizacion,
        arqueoVencido: _arqueoIntermedioVencido,
        minutosDesdeConteo: _minutosDesdeArqueo,
        avisosMp: _avisosMp,
      );
      setState(() => _version++);
    } catch (_) {
      // Sin diagnóstico visible: si la base todavía no tiene nada, no hay qué mostrar.
    }
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
    irAPestania(PestaniaNs.vender);
  }

  /// El encargue por apartado que el carrito está entregando (null en una venta común).
  final ValueNotifier<int?> _encargueEnVenta = ValueNotifier<int?>(null);

  /// Encargues (El dueño, 2026-10-02). "Entregar" vuelve acá con el encargue elegido: se arma el carrito con lo
  /// apartado a los precios de hoy y se abre; al cobrar, la venta libera lo apartado.
  Future<void> _abrirEncargues() async {
    if (_servicio == null || _usuarioId == null || _navegando) return;
    setState(() => _navegando = true);
    EntregaEncargue? entrega;
    try {
      entrega = await pushSinTeclado<EntregaEncargue>(
        context,
        (_) => PantallaEncarguesCompanion(
          servicio: _servicio!,
          usuarioId: _usuarioId!,
          hayVentaArmada: _carrito.isNotEmpty,
          sesionCajaId: _sesion?.id,
        ),
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
      _encargueEnVenta.value = entrega.id;
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
      sinConexionGlobalNs.value = sinConexion;
    }
  }

  // El dueño, 2026-09-07: "necesito que saques la versión de abajo" — el
  // diagnóstico visible (Celular X · PC Y, o el error) se sacó. El chequeo en
  // sí sigue: sin él, la campana tampoco podría avisar "Hay una versión nueva".
  // Con el mock (2026-10-04) la persona elige cuándo descargar: detectar una
  // versión nueva solo prende el aviso y el punto de "Más".

  Future<void> _revisarActualizacion() async {
    // Sin PC emparejada igual se mira el sitio: ahí vive el APK publicado.
    final conexion = await leerConexion();
    try {
      final estado = await revisarActualizacion(
        conexion == null ? null : ClienteCompanion(conexion),
      );
      if (mounted) {
        setState(() {
          _hayActualizacion = estado.hayActualizacion;
          _ofertaActualizacion = estado.oferta;
        });
        // Aparece en la campana y en el punto de "Más": la persona elige cuándo instalar.
        final p = pendientes.value;
        pendientes.value = PendientesNs(
          faltaSepararCentavos: p.faltaSepararCentavos,
          proveedoresPendientes: p.proveedoresPendientes,
          proveedoresTotal: p.proveedoresTotal,
          sinStock: p.sinStock,
          hayActualizacion: _hayActualizacion,
          arqueoVencido: p.arqueoVencido,
          minutosDesdeConteo: p.minutosDesdeConteo,
          avisosMp: p.avisosMp,
        );
      }
    } catch (_) {
      // Sin PC emparejada y sin sitio no hay a quién culpar: no se avisa.
    }
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
    final ns = context.ns;
    return AppNs(
      controlador: this,
      version: _version,
      child: PopScope(
        // Con el back del sistema en una pestaña que no es "Inicio" se vuelve a
        // "Inicio" en vez de salir de la app de una.
        canPop: _pestania == PestaniaNs.inicio,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          // En el cobro de Vender el "volver" es de esa pantalla, no de la barra.
          if (ocultarBarra.value) return;
          irAPestania(PestaniaNs.inicio);
        },
        child: Scaffold(
          backgroundColor: ns.paper,
          // El contenido pasa por debajo de la barra flotante: cada pestaña suma
          // `BarraInferiorNs.espacioReservado` de aire abajo.
          extendBody: true,
          body: CambioDePestanaNs(
            indice: _pestania.index,
            child: IndexedStack(
            index: _pestania.index,
            children: [
              const PantallaInicioNs(),
              const PantallaProductosNs(),
              _servicio == null || _usuarioId == null
                  ? const SizedBox.shrink()
                  : PantallaCarritoVenta(
                      cliente: _cliente,
                      servicio: _servicio!,
                      usuarioId: _usuarioId!,
                      carrito: _carrito,
                      encargue: _encargueEnVenta,
                    ),
              const PantallaCajaNs(),
              PantallaMasNs(alAbrirEncargues: _abrirEncargues),
            ],
          ),
          ),
          bottomNavigationBar: ValueListenableBuilder<bool>(
            valueListenable: ocultarBarra,
            // Con el teclado abierto la barra no sirve y, como sube pegada al teclado, tapaba la lista (El dueño,
            // 2026-10-09: "arriba del teclado hay una franja muy grande que tapa la lista de los productos").
            builder: (context, oculta, _) => ConTecladoNs(
              builder: (context, teclado) => oculta || teclado
                  ? const SizedBox.shrink()
                  : BarraInferiorNs(activa: _pestania, onSeleccionar: irAPestania, hayActualizacion: _hayActualizacion),
            ),
          ),
        ),
      ),
    );
  }
}

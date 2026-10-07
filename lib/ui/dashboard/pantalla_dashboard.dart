// Inicio — pantalla de arranque de la app. Nació como "Dashboard" (El dueño,
// 2026-09-14) y el 2026-09-26 absorbió Equilibrio (menú de 6 secciones).
//
// Distribución del "Lenguaje de diseño" (El dueño, 2026-09-26, mock
// `Dashboard.dc.html`, "medio inspiración" pero "la distribución es la
// idea"), en dos vistas que se eligen arriba a la derecha:
//
// - HOY: fila de cuatro indicadores (vendido, ganancia, tickets y "falta
//   separar" en la tarjeta oscura que lleva a Separaciones); ventas por
//   hora al lado de cómo te pagaron; y abajo más vendidos, stock que avisa
//   y fiados/encargues pendientes — este último en el lugar donde el mock
//   tenía "Reparaciones", que no es de este negocio (El dueño lo sacó).
// - ESTE MES: el contenido de lo que era Equilibrio (`ContenidoEquilibrio`).
//
// Es la raíz de la app (`main.dart`): nadie le pasa `usuarioId`/
// `sesionCajaId`, se resuelven solos, y se recarga al volver de cualquier
// pantalla (`RouteAware`, ver `route_observer.dart`).

import 'package:flutter/material.dart';

import '../navegacion/refresco_por_celular.dart';
import '../../data/database.dart';
import '../../data/repositorio_tablero.dart';
import '../../data/repositorio_ventas.dart' show sesionAbierta;
import '../comun/armazon_gestion.dart';
import '../comun/fechas.dart';
import '../equilibrio/pantalla_equilibrio.dart';
import '../kit/piezas.dart';
import 'vista_inicio.dart';
import '../navegacion/navegacion_gestion.dart';
import '../navegacion/route_observer.dart';
import '../../domain/modulos.dart';
import '../../servicios/marca_actual.dart';
import '../../servicios/modulos_activos.dart';
import '../comun/dialogo_datos_comercio.dart';

enum _Vista { hoy, mes }

class PantallaDashboard extends StatefulWidget {
  const PantallaDashboard({super.key, required this.db, this.ahora});

  final AppDatabase db;

  /// Solo para tests y capturas: fija "hoy".
  final DateTime? ahora;

  @override
  State<PantallaDashboard> createState() => _PantallaDashboardState();
}

class _PantallaDashboardState extends State<PantallaDashboard> with RouteAware , RefrescoPorCelular{
  @override
  void alCambiarDesdeElCelular() => _cargarTodo();

  bool _cargando = true;
  SesionCaja? _sesion;

  /// Nombre de quien abrió la caja, para el saludo "Hola, Ana" (mock Nodo Sur). Null sin caja abierta: el título es "Inicio".
  String? _nombreUsuario;
  TableroDelDia? _tablero;
  _Vista _vista = _Vista.hoy;

  /// Cambia en cada recarga para rearmar el contenido del mes (su propio
  /// controlador lee la base una vez al montarse).
  int _version = 0;

  /// El aviso de "Datos de tu comercio" se ofrece una vez por apertura de la app.
  bool _preguntoComercio = false;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pedirDatosDelComercio());
  }

  Future<void> _pedirDatosDelComercio() async {
    if (_preguntoComercio) return;
    _preguntoComercio = true;
    final marca = await marcaDeBase(widget.db);
    if (marca.configurada || !mounted) return;
    await mostrarDialogoDatosComercio(context, widget.db);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute<dynamic>);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  /// Cualquier pantalla de la que se vuelve (Venta, Separaciones...) pudo
  /// cambiar ventas, stock o fijos — se recarga sola.
  @override
  void didPopNext() => _cargarTodo();

  Future<void> _cargarTodo() async {
    final sesion = await sesionAbierta(widget.db);
    final tablero = await tableroDelDia(widget.db, ahora: widget.ahora);
    final usuarioId = sesion?.usuarioAbrioId;
    final usuario = usuarioId == null
        ? null
        : await (widget.db.select(widget.db.usuarios)..where((u) => u.id.equals(usuarioId))).getSingleOrNull();
    if (!mounted) return;
    setState(() {
      _nombreUsuario = usuario?.nombre.trim().isEmpty ?? true ? null : usuario!.nombre.trim();
      _sesion = sesion;
      _tablero = tablero;
      _version++;
      _cargando = false;
    });
  }

  void _ir(String clave) {
    final sesion = _sesion;
    navegarASeccionDeGestion(
      context,
      clave,
      db: widget.db,
      usuarioId: sesion?.usuarioAbrioId ?? 0,
      sesionCajaId: sesion?.id,
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ModulosNegocio>(
    valueListenable: modulosActuales,
    builder: (context, modulos, _) => _construir(context, modulos),
  );

  Widget _construir(BuildContext context, ModulosNegocio modulos) {
    // Cargando, igual va la pantalla con su barra (vacía abajo): sin barra en el primer cuadro, el `Hero` de la barra no
    // tiene a dónde volar y al venir de Venta toda la barra entraba en el fundido (El dueño, 2026-10-07).
    if (_cargando) {
      return PantallaGestion(db: widget.db, claveActiva: 'dashboard', usuarioId: 0, titulo: 'Inicio', child: const SizedBox.shrink());
    }
    final sesion = _sesion;
    final hoy = widget.ahora ?? DateTime.now();
    // Sin el módulo de equilibrio no hay vista mensual: queda solo "Hoy".
    final verMes = modulos.estaActivo(Modulo.equilibrio) && _vista == _Vista.mes;

    return PantallaGestion(
      db: widget.db,
      claveActiva: 'dashboard',
      usuarioId: sesion?.usuarioAbrioId ?? 0,
      sesionCajaId: sesion?.id,
      titulo: _nombreUsuario == null ? 'Inicio' : 'Hola, $_nombreUsuario',
      subtitulo: !verMes
          ? 'Hoy · ${fechaLarga(hoy)}${sesion == null ? ' · caja cerrada' : ''}'
          : 'Este mes · ${mesLargo(hoy)}',
      accion: !modulos.estaActivo(Modulo.equilibrio)
          ? null
          : Seg<_Vista>(
              opciones: const [(_Vista.hoy, 'Hoy'), (_Vista.mes, 'Este mes')],
              valor: _vista,
              onCambio: (v) => setState(() => _vista = v),
            ),
      child: !verMes
          ? VistaInicioHoy(
              tablero: _tablero!,
              hoy: hoy,
              onSeparar: () => _ir('separaciones'),
              onVerPendientes: () => _ir('encargues'),
              conPendientes: modulos.estaActivo(Modulo.fiado),
            )
          : ContenidoEquilibrio(
              key: ValueKey(_version),
              db: widget.db,
              usuarioId: sesion?.usuarioAbrioId ?? 0,
              sesionCajaId: sesion?.id,
            ),
    );
  }
}


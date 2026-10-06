// La pantalla de venta. Franja superior (navbar + búsqueda de ancho fijo,
// centrada) y debajo dos zonas (grilla de productos navegable, carrito +
// cobro) — rediseño de composición 2026-09-25, ver el comentario de
// `build()`. Ya no hay una tira de accesos directos por Alt+tecla (El dueño,
// cuarta pasada: "ahora no hacen falta los accesos rapidos... sacar la
// tira Y el sistema de accesos directos entero" — la grilla, táctil, la
// reemplaza). Pantalla completa, sin scroll de página salvo el propio del
// carrito. Fase 13 (hardware) devolvió las
// animaciones de transición entre pantallas (`tema.dart`) — acá adentro
// siguen sin usarse: nada de esto (agregar al carrito, cambiar de medio,
// cobrar) pasa por un `Navigator`, y la densidad/velocidad de tecleo siguen
// ganando por sobre cualquier adorno mientras hay un cliente esperando.
//
// Todos los atajos de acá son Alt+algo (incluidos los directos y el gasto
// rápido, no solo los medios de pago): el campo único tiene el foco todo el
// tiempo, así que cualquier tecla sin Alt se interpretaría como texto.
//
// Se manejan con un handler global (`HardwareKeyboard.instance.addHandler`)
// en vez de `Shortcuts`/`Actions` o un `Focus.onKeyEvent`: un FocusNode solo
// puede pertenecer a un widget de foco a la vez, y el campo único ya usa el
// suyo. Un handler global no compite por ese nodo y funciona sin importar
// qué widget tenga el foco en un instante dado — que en la práctica siempre
// va a ser el campo único.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../navegacion/refresco_por_celular.dart';
import '../../domain/modulos.dart';
import '../../servicios/modulos_activos.dart';
import '../../data/database.dart';
import 'venta_en_curso.dart';
import '../../data/repositorio_secciones_menu.dart';
import '../../domain/medio_pago.dart';
import '../cierre/pantalla_cierre.dart';
import 'cancelar_venta_con_deshacer.dart';
import '../comun/botones.dart';
import '../comun/modal.dart';
import '../impresion/dialogo_imprimir_ticket.dart';
import '../navegacion/acciones_caja.dart';
import '../navegacion/asistente.dart';
import '../navegacion/boton_caja.dart';
import '../navegacion/boton_notificaciones.dart';
import '../navegacion/navbar_superior.dart';
import '../navegacion/navegacion_gestion.dart';
import '../navegacion/route_observer.dart';
import 'acciones_venta.dart';
import 'cuerpo_venta.dart';
import 'dialogo_apertura_caja.dart';
import 'dialogo_arqueo_intermedio.dart';
import 'dialogo_movimiento_rapido.dart';
import 'dialogo_pagar_proveedor_rapido.dart';
import 'venta_controlador.dart';
import 'elegir_tarjeta.dart';

class PantallaVenta extends StatefulWidget {
  const PantallaVenta({
    super.key,
    required this.db,
    this.textoBusquedaPendiente,
    this.encarguePendienteId,
  });

  final AppDatabase db;

  /// Texto a precargar en el campo único al llegar — lo manda
  /// `BarraBusquedaGlobal` (`navegacion/barra_busqueda_global.dart`) cuando
  /// se busca un producto desde OTRA pantalla de gestión (El dueño, tercera
  /// pasada: "quiero que la barra de busqueda este en todos lados"). Nunca
  /// agrega nada por su cuenta — solo deja el campo listo para que el
  /// usuario termine el mismo camino de siempre.
  final String? textoBusquedaPendiente;

  /// Encargue por apartado a entregar: al llegar abre una venta con lo apartado (lo manda la pantalla de Encargues).
  final int? encarguePendienteId;

  @override
  State<PantallaVenta> createState() => _PantallaVentaState();
}

class _PantallaVentaState extends State<PantallaVenta>
    with RouteAware, RefrescoPorCelular {
  @override
  void alCambiarDesdeElCelular() => _controlador.cargarTodo();

  late final VentaControlador _controlador;

  /// Qué pantallas de gestión aparecen en el menú y en qué orden (fase 8) —
  /// "Cerrar caja" y "Configuración" quedan fijos, no pasan por acá.
  List<SeccionMenu> _seccionesVisibles = [];

  @override
  void initState() {
    super.initState();
    _controlador = VentaControlador(widget.db);
    _controlador.addListener(_publicarVentaEnCurso);
    HardwareKeyboard.instance.addHandler(_manejarTeclaGlobal);
    _controlador.cargarTodo().then((_) {
      if (mounted) {
        // El arranque tiene que ser inmediato (CLAUDE.md): el foco se pide
        // recién cuando ya hay algo cargado para mostrar, no antes.
        final encargue = widget.encarguePendienteId;
        if (encargue != null) unawaited(_controlador.cargarEncargue(encargue));
        final pendiente = widget.textoBusquedaPendiente;
        if (pendiente != null && pendiente.isNotEmpty) {
          // Dispara `_alCambiarTexto` solo (el controlador ya escucha a
          // `campoTexto`) — no hace falta llamar a nada más a mano.
          _controlador.campoTexto.text = pendiente;
        }
        _controlador.focoCampoPrincipal.requestFocus();
      }
    });
    _cargarSecciones();
  }

  Future<void> _cargarSecciones() async {
    final secciones = await listarSeccionesVisibles(widget.db);
    if (mounted) setState(() => _seccionesVisibles = secciones);
  }

  bool _soyRaiz = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ruta = ModalRoute.of(context)!;
    routeObserver.subscribe(this, ruta as PageRoute<dynamic>);
    if (ruta.isFirst && !_soyRaiz) {
      _soyRaiz = true;
      ventaEsRaiz.value = true;
    }
  }

  /// Lo que otra pantalla mandó a cargar al volver a Venta (texto de la búsqueda global o un encargue a entregar).
  void _tomarPedido() {
    final pedido = pedidoParaVenta.value;
    if (pedido == null) return;
    pedidoParaVenta.value = null;
    if (pedido.encargueId != null) unawaited(_controlador.cargarEncargue(pedido.encargueId!));
    final texto = pedido.texto;
    if (texto != null && texto.isNotEmpty) _controlador.campoTexto.text = texto;
  }

  void _publicarVentaEnCurso() =>
      hayVentaEnCurso.value = _controlador.hayVentaAbierta;

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    HardwareKeyboard.instance.removeHandler(_manejarTeclaGlobal);
    if (_soyRaiz) ventaEsRaiz.value = false;
    _controlador.removeListener(_publicarVentaEnCurso);
    _controlador.dispose();
    super.dispose();
  }

  /// Se llama cuando esta pantalla vuelve a quedar arriba de todo porque la
  /// ruta que la tapaba se sacó — sin importar cuál era esa ruta ni por
  /// dónde se volvió (`Navigator.pop`, la flecha de atrás, o `popUntil`
  /// saltando de una sección de gestión a otra sin pasar por acá, ver
  /// `route_observer.dart`). Cualquiera de esas pantallas pudo haber
  /// cambiado productos, proveedores, stock o configuración.
  @override
  void didPopNext() {
    _controlador.cargarTodo().then((_) {
      if (mounted) _tomarPedido();
    });
    _controlador.focoCampoPrincipal.requestFocus();
  }

  bool _manejarTeclaGlobal(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    // `HardwareKeyboard.instance.addHandler` es un registro global: no sabe
    // nada del `Navigator`, así que sigue llamando a este handler aunque
    // haya un diálogo (o cualquier otra pantalla pusheada) tapando la venta.
    // Bug real, encontrado antes de la fase 12 — ver TRAMPAS.md: Alt+Q con
    // el diálogo de mixto abierto cambiaba el medio elegido por detrás, y
    // una tecla de accesorio directo con "alta rápida" abierta agregaba el
    // producto al carrito sin que el diálogo se enterara.
    //
    // `ModalRoute.of(context)` engancha una dependencia de `InheritedWidget`
    // — esta pantalla se reconstruye cada vez que una ruta se pone o se
    // saca de encima. Es aceptable (ya se reconstruye por `provider` en
    // cada cambio del carrito) y está evaluado a propósito, no pasado por
    // alto: en una app que cuida cada repintado por el hardware, un
    // rebuild ocasional al navegar es un costo real pero raro, contra un
    // bug de plata que pasa todos los días.
    //
    // `== false` explícito, no `!isCurrent`: si `ModalRoute.of()` da `null`
    // (sin ruta contenedora — no debería pasar en esta pantalla, pero el
    // default tiene que ser seguro), el handler sigue activo en vez de
    // apagarse por accidente.
    if (ModalRoute.of(context)?.isCurrent == false) return false;

    final c = _controlador;

    // Ctrl+K: el Asistente funciona siempre (con la caja cerrada ofrece "Abrir caja"), por eso va antes del bloqueo de abajo.
    if (event.logicalKey == LogicalKeyboardKey.keyK &&
        HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isAltPressed) {
      unawaited(_abrirAsistente());
      return true;
    }

    // Bug real (reportado por el dueño): con la caja cerrada, `ColumnaBusqueda`/
    // `ColumnaCarrito`/`ColumnaCobro` desaparecen de la pantalla ("Caja
    // cerrada.", ver `build()`), pero este handler es global — no sabe nada
    // del árbol de widgets ni de qué hay pintado — y seguía reaccionando a
    // Alt+directo/Alt+V/Alt+X/Alt+E/Alt+Q, agregando al carrito o cambiando
    // el medio elegido a espaldas de la pantalla. El resultado: se podía
    // "vender" (armar un carrito entero) mientras se mostraba el aviso de
    // caja cerrada, y aparecía recién al volver a abrir caja, ya cargado.
    // Mismo bloqueo si la sesión abierta es de un día anterior (Regla 5): no
    // se puede vender bajo ella aunque siga técnicamente "abierta".
    if (c.sesion == null || c.sesionVencida) return false;

    // Ctrl+F: el atajo de buscar de toda la app (El dueño, 2026-10-03). En Venta el campo ya está a la vista: lo enfoca.
    if (event.logicalKey == LogicalKeyboardKey.keyF &&
        HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isAltPressed) {
      c.focoCampoPrincipal.requestFocus();
      return true;
    }

    // `!isControlPressed`: en Windows, AltGr (tecla de la derecha en un
    // teclado latinoamericano/español — necesaria para escribir '@', '#',
    // etc.) se reporta como Ctrl+Alt sintético, así que `isAltPressed` solo
    // da `true` también con AltGr. Sin este chequeo, escribir un carácter
    // compuesto con AltGr en el campo de búsqueda podía disparar un atajo
    // reservado (ej. Alt+Q cambia el medio de pago a QR) en vez de escribir
    // el carácter, si la letra de esa combinación coincidía con una de
    // `teclasReservadas`.
    if (HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isControlPressed) {
      final etiqueta = event.logicalKey.keyLabel.toLowerCase();

      // Gobernado por `teclasReservadas` (acciones_venta.dart) — las únicas
      // combinaciones Alt+tecla que quedan desde que se sacó el sistema de
      // accesos directos configurables (El dueño, cuarta pasada).
      if (teclasReservadas.containsKey(etiqueta)) {
        switch (etiqueta) {
          case 'e':
            c.elegirMedio(ComposicionPago.efectivo);
          // QR y Débito eligen el canal nada más (El dueño, 2026-09-08: volvió
          // a ser de dos pasos — "necesito cobro manual... no hay más modal
          // para seleccionarlo"). "Cobrar" (Enter con el campo vacío, o el
          // botón) recién ahí abre el diálogo que manda la orden a la
          // terminal; Alt+M cobra directo sin pasar por ella.
          case 'q':
            c.elegirCanalDirecto('qr');
          case 'd':
            elegirTarjeta(context, c);
          case 'm':
            cobrarAMano(context, c);
          case 'x':
            abrirMixto(context, c);
          case 'v':
            agregarVarios(context, c);
          case 'c':
            final vuelto = c.productoVuelto;
            if (vuelto != null) {
              c.agregarProducto(vuelto);
              c.focoCampoPrincipal.requestFocus();
            }
          case '-':
            _abrirGastoRapido();
          case 'i':
            _abrirIngresoRapido();
          case 'p':
            _pagarProveedor();
          case 'n':
            c.nuevaVenta();
          case 's':
            if (c.cantidadPestanas > 1) {
              c.cambiarAPestana((c.pestanaActiva + 1) % c.cantidadPestanas);
            }
        }
        return true;
      }
      return false;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      c.moverSeleccion(1);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      c.moverSeleccion(-1);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      cancelarVentaConDeshacer(context, c);
      return true;
    }
    return false;
  }

  /// Turno entrante: un turno es una sesión completa (El dueño, sesión del
  /// 31/08/2026), así que después de un cierre voluntario mid-día tiene que
  /// poder abrirse una hoja nueva ahí mismo — reiniciar la app entera para
  /// seguir vendiendo era el callejón sin salida que esto reemplaza.
  Future<void> _abrirCaja() async {
    await mostrarDialogoAperturaCaja(context, db: widget.db);
    await _controlador.cargarTodo();
    if (mounted) _controlador.focoCampoPrincipal.requestFocus();
  }

  // Diálogos secundarios (gasto/ingreso rápido) — el foco ya no vuelve solo
  // al cerrarse (El dueño, 2026-09-16: "dejar de robar el foco al hacer otra
  // cosa"), a diferencia de agregar un producto o cobrar.
  Future<void> _abrirGastoRapido() async {
    final sesion = _controlador.sesion;
    if (sesion == null) return;
    await mostrarDialogoGastoRapido(
      context,
      db: widget.db,
      sesionCajaId: sesion.id,
      usuarioId: sesion.usuarioAbrioId,
    );
  }

  /// "Pagar proveedor" (Alt+P, rediseño v4): el pago más común del día en un par de teclas. Al terminar avisa arriba y,
  /// si se puede, ofrece Deshacer (anula el movimiento: la plata vuelve a su caja y la deuda a lo que era).
  Future<void> _pagarProveedor() async {
    final sesion = _controlador.sesion;
    if (sesion == null) return;
    await pagarProveedorYAvisar(context, db: widget.db, usuarioId: sesion.usuarioAbrioId, sesionCajaId: sesion.id);
  }

  /// Asistente (Ctrl+K): buscador de acciones, pantallas y productos. Elegir un producto lo deja escrito en el campo único.
  Future<void> _abrirAsistente() async {
    await abrirAsistente(
      context,
      db: widget.db,
      sesion: _controlador.sesion,
      irA: _onSeleccionarSeccion,
      alElegirProducto: (texto) {
        _controlador.campoTexto.text = texto;
        _controlador.focoCampoPrincipal.requestFocus();
      },
      alTerminarAccion: _controlador.cargarTodo,
    );
  }

  Future<void> _abrirIngresoRapido() async {
    final sesion = _controlador.sesion;
    if (sesion == null) return;
    await mostrarDialogoIngresoRapido(
      context,
      db: widget.db,
      sesionCajaId: sesion.id,
      usuarioId: sesion.usuarioAbrioId,
    );
  }

  /// Cierre desde la pantalla de venta — tanto el voluntario (botón "Cerrar
  /// caja" del pie) como el de una sesión de un día anterior (Regla 5,
  /// `_EstadoBloqueado` en `build()`) pasan por acá: los dos vuelven a esta
  /// misma pantalla al terminar, nunca hay nada más a donde ir.
  ///
  /// No recarga acá al volver — `didPopNext()` (`RouteAware`, ver
  /// `route_observer.dart`) lo hace solo apenas esta pantalla vuelve a
  /// quedar arriba, sin importar por dónde se volvió.
  Future<void> _irACierre() async {
    final sesion = _controlador.sesion;
    if (sesion == null) return;
    await mostrarModal<void>(
      context,
      builder: (context) => PantallaCierre(
        db: widget.db,
        sesionId: sesion.id,
        usuarioId: sesion.usuarioAbrioId,
      ),
    );
  }

  /// "Cambiar de turno" (2026-09-12, el dueño: viene ayuda de fin de semana a
  /// mitad de sesión) — mismo arqueo obligatorio que "Cerrar caja", nada
  /// queda sin contar antes de soltar la caja, pero encadena directo a
  /// abrir la hoja de quien entra en vez de dejar la pantalla en "Caja
  /// cerrada" esperando un segundo clic.
  Future<void> _cambiarTurno() async {
    final sesion = _controlador.sesion;
    if (sesion == null) return;
    // `cerrado` distingue "llegó a cerrar" de "canceló a mitad de camino"
    // (Esc en conteo/revisado) — `_controlador.sesion` todavía no se puede
    // usar acá para eso: recién se actualiza cuando `didPopNext()` termine
    // su propio `cargarTodo()`, después de este `await`.
    var cerrado = false;
    await mostrarModal<void>(
      context,
      builder: (context) => PantallaCierre(
        db: widget.db,
        sesionId: sesion.id,
        usuarioId: sesion.usuarioAbrioId,
        textoBotonFinal: 'Abrir para el que entra',
        onFinalizado: () {
          cerrado = true;
          Navigator.of(context).pop();
        },
      ),
    );
    if (cerrado) await _abrirCaja();
  }

  /// Arqueo sugerido cada 2hs (turnos por usuario, 2026-09-12; el dueño,
  /// 2026-09-15: "que se cambie a una sugerencia únicamente" — ya no
  /// bloquea la venta, solo muestra `_AvisoArqueoIntermedio` en `build()`
  /// mientras no se haga). A diferencia de "Cerrar caja"/"Cambiar de
  /// turno", no corta la sesión: solo recarga el controlador para que
  /// `arqueoIntermedioVencido` vea el arqueo recién registrado y deje de
  /// mostrar el aviso.
  Future<void> _hacerArqueoIntermedio() async {
    final sesion = _controlador.sesion;
    if (sesion == null) return;
    await mostrarDialogoArqueoIntermedio(
      context,
      db: widget.db,
      sesionId: sesion.id,
      usuarioId: sesion.usuarioAbrioId,
    );
    await _controlador.cargarTodo();
  }

  Future<void> _imprimirUltimoTicket() async {
    final ventaId = _controlador.ultimaVentaId;
    if (ventaId == null) return;
    await mostrarDialogoImprimirTicket(
      context,
      db: widget.db,
      ventaId: ventaId,
    );
  }


  /// "Dashboard" (la raíz, un clic para volver) + "Venta" (la pantalla en
  /// la que ya se está) + las secciones configurables visibles +
  /// "Configuración" (fija, no pasa por `secciones_menu`) — mismo orden que
  /// `itemsNavGestion` en el resto de las pantallas.
  List<ItemNavbarSuperior> get _itemsNav => [
    const ItemNavbarSuperior(clave: 'dashboard', etiqueta: 'Inicio'),
    const ItemNavbarSuperior(clave: 'venta', etiqueta: 'Venta'),
    for (final seccion in _seccionesVisibles)
      ItemNavbarSuperior(clave: seccion.clave, etiqueta: seccion.etiqueta),
    const ItemNavbarSuperior(clave: 'configuracion', etiqueta: 'Configuración'),
  ];

  /// "Caja ▾" (rediseño v4): el estado de la caja a la vista y, en el menú, todo lo que se hace con ella. Reemplaza a los
  /// íconos sueltos "Cambiar de turno" y "Cerrar caja" del extremo derecho. Con la caja cerrada, el menú tiene solo "Abrir
  /// caja"; con la de un día anterior sin cerrar, solo cerrarla.
  Widget _construirBotonCaja(VentaControlador c) {
    final sesion = c.sesion;
    final EstadoCajaNavbar estado = sesion == null
        ? EstadoCajaNavbar.cerrada
        : (c.sesionVencida ? EstadoCajaNavbar.deAyerSinCerrar : EstadoCajaNavbar.abierta);
    return ValueListenableBuilder<ModulosNegocio>(
      valueListenable: modulosActuales,
      builder: (context, modulos, _) {
        final hayTurnos = modulos.estaActivo(Modulo.turnos);
        final acciones = armarAccionesMenuCaja(
          estado: estado,
          hayTurnos: hayTurnos,
          arqueoVencido: c.arqueoIntermedioVencido,
          onAbrir: _abrirCaja,
          onArqueo: _hacerArqueoIntermedio,
          onTurno: _cambiarTurno,
          onGasto: _abrirGastoRapido,
          onIngreso: _abrirIngresoRapido,
          onCerrar: _irACierre,
        );
        return BotonCaja(estado: estado, acciones: acciones);
      },
    );
  }

  /// Venta es la raíz de la app (El dueño, 2026-10-03): cada sección se abre encima con la misma navegación que el
  /// resto de las pantallas, y al volver se recargan las secciones (pudieron cambiar en Configuración).
  Future<void> _onSeleccionarSeccion(String clave) async {
    if (clave == 'venta') return; // ya estamos acá
    final sesion = _controlador.sesion;
    await navegarASeccionDeGestion(
      context,
      clave,
      db: widget.db,
      usuarioId: sesion?.usuarioAbrioId ?? 0,
      sesionCajaId: sesion?.id,
    );
    await _cargarSecciones();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<VentaControlador>.value(
      value: _controlador,
      child: Scaffold(
        body: SafeArea(
          child: Consumer<VentaControlador>(
            builder: (context, c, _) {
              // Primer frame, antes de que `cargarTodo()` resuelva: todavía
              // no hay sesión (ni se sabe si hay una) para decidir entre el
              // layout de venta o "Caja cerrada". Nada que mostrar todavía,
              // mismo criterio que el arranque de `main.dart`.
              if (c.cargando) return const SizedBox.shrink();

              // La campanita va a la derecha, antes de la tuerca. El arqueo sugerido cada 2 horas es parte de los turnos; los
              // avisos de Mercado Pago (etapa D) no, así que la campanita está siempre y cada parte decide si se muestra.
              final campanita = BotonNotificaciones(
                hayArqueoVencido: c.arqueoIntermedioVencido,
                onHacerArqueo: _hacerArqueoIntermedio,
              );
              final hayVenta = c.sesion != null && !c.sesionVencida;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // "Estética Google" (El dueño, rediseño 2026-09-25): navbar
                  // a la izquierda, búsqueda al centro con ANCHO FIJO (no
                  // `Expanded` — El dueño: "la barra de busqueda debe ocpar un
                  // espacio fijo al centro, no extenderse en todos lados"),
                  // acciones de caja al extremo derecho — mismo patrón que
                  // la franja superior de Gmail/Drive. Sin sesión activa no
                  // hay nada que buscar (el handler global de teclado ya
                  // bloquea toda entrada en ese caso, ver más abajo) — la
                  // navbar sola vuelve a quedar sin acompañantes.
                  // Rediseño "antigravity": la barra de arriba lleva la marca,
                  // las secciones en pastillas y las acciones de caja; la
                  // búsqueda baja a la columna de productos, debajo del
                  // título "Vender" (igual que el mock).
                  // La búsqueda de Venta no se esconde detrás de la lupa: es el campo único (y el lector de códigos escribe
                  // ahí), siempre visible en la columna de productos (CLAUDE.md, "Pantalla de venta"). Ctrl+F lo enfoca.
                  NavbarSuperior(
                    claveActiva: 'venta',
                    items: _itemsNav,
                    onSeleccionar: _onSeleccionarSeccion,
                    izquierda: _construirBotonCaja(c),
                    onAbrirAsistente: () => unawaited(_abrirAsistente()),
                    acciones: hayVenta ? campanita : null,
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: c.sesion == null
                        ? _EstadoBloqueado(
                            mensaje: 'Caja cerrada.',
                            etiquetaBoton: 'Abrir caja',
                            onPressed: _abrirCaja,
                          )
                        : c.sesionVencida
                        ? _EstadoBloqueado(
                            mensaje:
                                'Queda una sesión de un día anterior sin cerrar.',
                            etiquetaBoton: 'Cerrar caja',
                            onPressed: _irACierre,
                          )
                        : CuerpoVenta(
                            onPagarProveedor: _pagarProveedor,
                            onImprimir: _imprimirUltimoTicket,
                            ventaConfirmada: c.ultimaVentaId,
                            totalConfirmadoCentavos: c.ultimoTotalCobradoCentavos,
                            usuarioId: c.sesion?.usuarioAbrioId ?? 0,
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Reemplaza el carrito cuando no se puede vender — sin sesión abierta, o
/// con una sesión abierta pero de un día anterior (Regla 5). El resto de la
/// pantalla (barra lateral, navegación) sigue disponible igual: El dueño,
/// 2026-09-06, "que no salga obligatoriamente al abrir la app" — el bloqueo
/// es solo para vender, nunca para el resto de la app.
class _EstadoBloqueado extends StatelessWidget {
  const _EstadoBloqueado({
    required this.mensaje,
    required this.etiquetaBoton,
    required this.onPressed,
  });

  final String mensaje;
  final String etiquetaBoton;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(mensaje),
          const SizedBox(height: 12),
          BotonPrimario(texto: etiquetaBoton, onPressed: onPressed),
        ],
      ),
    );
  }
}

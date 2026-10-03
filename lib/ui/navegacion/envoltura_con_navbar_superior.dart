// Envuelve el contenido de una pantalla de gestión con la navbar superior
// — reemplazo directo de `EnvolturaConBarraLateral`
// (`envoltura_con_barra_lateral.dart`, sigue en el árbol mientras dura el
// rollout, se borra en la Fase 6). Carga las secciones visibles y resuelve
// la navegación — cada pantalla nueva solo pasa su propia clave activa y su
// contenido. Ya no guarda preferencia de compactado (El dueño, rediseño
// 2026-09-25: la navbar pasó a ser un dropdown de un solo tamaño, ver
// `navbar_superior.dart` — no hay "compacta" que recordar).
//
// Suma `BarraBusquedaGlobal` junto a la navbar (El dueño, tercera pasada de
// venta: "quiero que la barra de busqueda este en todos lados" — confirmado
// que es para TODA la app, no solo Venta) — mismo patrón de fila que
// `pantalla_venta.dart` ya usa para la suya: navbar a la izquierda, campo
// de ancho fijo centrado con `LayoutBuilder`+`clamp` para no desbordar en
// ventanas angostas. Elegir un resultado ahí NAVEGA a Venta con el texto
// precargado (`navegarASeccionDeGestion(..., textoBusquedaPendiente: ...)`)
// — la pantalla de Venta sigue siendo la única que agrega productos de
// verdad, esto solo te lleva hasta ahí con el trabajo de escribir ya hecho.
//
// La pantalla de Venta NO usa este envoltorio: arma su propia
// `NavbarSuperior`+`BarraBusquedaVenta` a mano (mismo motivo que antes con
// `BarraLateral` — foco del campo único, atajos de teclado, "Cerrar caja"
// en el slot de acción; `BarraBusquedaVenta`, a diferencia de
// `BarraBusquedaGlobal`, agrega directo al carrito).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/database.dart';
import '../tema/tokens.dart';
import 'barra_busqueda_global.dart';
import 'busqueda_contextual.dart';
import 'navbar_superior.dart';
import 'navegacion_gestion.dart';

class EnvolturaConNavbarSuperior extends StatefulWidget {
  const EnvolturaConNavbarSuperior({
    super.key,
    required this.db,
    required this.claveActiva,
    required this.usuarioId,
    this.sesionCajaId,
    this.busqueda,
    required this.child,
  });

  final AppDatabase db;
  final String claveActiva;
  final int usuarioId;
  final int? sesionCajaId;

  /// Null: el buscador de productos de siempre (elegir uno lleva a Venta).
  /// Con valor: el campo de arriba filtra lo de esta pantalla.
  final BusquedaContextual? busqueda;
  final Widget child;

  @override
  State<EnvolturaConNavbarSuperior> createState() => _EnvolturaConNavbarSuperiorState();
}

class _EnvolturaConNavbarSuperiorState extends State<EnvolturaConNavbarSuperior> {
  List<ItemNavbarSuperior> _items = const [ItemNavbarSuperior(clave: 'venta', etiqueta: 'Venta')];

  /// Búsqueda de la navbar: cerrada es una lupa; abierta, el campo ocupa la barra.
  bool _buscando = false;
  final _focoBusqueda = FocusNode();

  /// Cambia al cerrar: el campo vuelve a nacer vacío (y sin resultados colgando) la próxima vez.
  int _vueltaBusqueda = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
    HardwareKeyboard.instance.addHandler(_tecla);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_tecla);
    _focoBusqueda.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final items = await itemsNavGestion(widget.db);
    if (mounted) setState(() => _items = items);
  }

  /// Ctrl+F abre la búsqueda; la tecla Inicio lleva a Venta (El dueño, 2026-10-03), salvo escribiendo en un campo, donde
  /// sigue moviendo el cursor al principio.
  bool _tecla(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    final teclado = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.keyF && teclado.isControlPressed && !teclado.isAltPressed) {
      _abrirBusqueda();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.home && !teclado.isControlPressed && !teclado.isAltPressed && !teclado.isShiftPressed) {
      final enCampo = FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<EditableTextState>() != null;
      if (enCampo) return false;
      unawaited(_seleccionar('venta'));
      return true;
    }
    return false;
  }

  void _abrirBusqueda() {
    setState(() => _buscando = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focoBusqueda.requestFocus();
    });
  }

  void _cerrarBusqueda() {
    if (!_buscando) return;
    _focoBusqueda.unfocus();
    widget.busqueda?.alCambiar('');
    setState(() {
      _buscando = false;
      _vueltaBusqueda++;
    });
  }

  Future<void> _seleccionar(String clave) async {
    if (clave == widget.claveActiva) return;
    await navegarASeccionDeGestion(
      context,
      clave,
      db: widget.db,
      usuarioId: widget.usuarioId,
      sesionCajaId: widget.sesionCajaId,
    );
  }

  Future<void> _irAVentaConTexto(String texto) {
    _cerrarBusqueda();
    return navegarASeccionDeGestion(
      context,
      'venta',
      db: widget.db,
      usuarioId: widget.usuarioId,
      sesionCajaId: widget.sesionCajaId,
      textoBusquedaPendiente: texto,
    );
  }

  @override
  Widget build(BuildContext context) {
    final anchoAbierta = MediaQuery.sizeOf(context).width * NavbarSuperior.fraccionBusquedaAbierta;
    final campo = widget.busqueda == null
        ? BarraBusquedaGlobal(
            key: ValueKey('busqueda_global_$_vueltaBusqueda'),
            db: widget.db,
            anchoDropdown: anchoAbierta,
            onElegir: _irAVentaConTexto,
            foco: _focoBusqueda,
            alSalir: _cerrarBusqueda,
          )
        : CampoBusquedaContextual(
            key: ValueKey('busqueda_contextual_$_vueltaBusqueda'),
            busqueda: widget.busqueda!,
            foco: _focoBusqueda,
            alSalir: _cerrarBusqueda,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg),
          child: NavbarSuperior(
            claveActiva: widget.claveActiva,
            items: _items,
            onSeleccionar: _seleccionar,
            busqueda: campo,
            buscando: _buscando,
            onAbrirBusqueda: _abrirBusqueda,
            onCerrarBusqueda: _cerrarBusqueda,
          ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}

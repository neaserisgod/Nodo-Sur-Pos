// Envuelve el contenido de una pantalla de gestión con la barra de navegación del mock v4 (`NavbarSuperior` con
// `child`: la barra arriba, el mega-menú y el velo en el medio, el contenido abajo). Carga las secciones visibles y
// resuelve a dónde ir; cada pantalla solo pasa su clave activa y su contenido.
//
// Teclado de toda la app (El dueño, 2026-10-03, y el mock v4): Ctrl+K abre el Asistente; Ctrl+F abre la búsqueda
// propia de la pantalla adentro de la barra, o el Asistente si la pantalla no tiene una (el mock no tiene lupa a la
// vista: el Asistente busca productos y elegir uno vuelve a Venta con el texto cargado); la tecla Inicio vuelve a Venta,
// salvo escribiendo en un campo.
//
// La pantalla de Venta NO usa este envoltorio: arma su propia barra (foco del campo único, atajos de cobro, el menú de
// caja con lo que sabe del controlador).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/database.dart';
import '../../data/repositorio_ventas.dart' show sesionAbierta;
import 'acciones_caja.dart';
import 'asistente.dart';
import 'boton_notificaciones.dart';
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
    if (event.logicalKey == LogicalKeyboardKey.keyK && teclado.isControlPressed && !teclado.isAltPressed) {
      unawaited(_abrirAsistente());
      return true;
    }
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

  /// Ctrl+K o el botón "Asistente": buscador de acciones, pantallas y productos.
  Future<void> _abrirAsistente() async {
    final sesion = await sesionAbierta(widget.db);
    if (!mounted) return;
    await abrirAsistente(
      context,
      db: widget.db,
      sesion: sesion,
      irA: _seleccionar,
      alElegirProducto: (texto) => unawaited(_irAVentaConTexto(texto)),
    );
  }

  /// Ctrl+F: con búsqueda propia de la pantalla, el campo se abre adentro de la barra (`.sbar` del mock); si no, el
  /// Asistente, que también busca productos (igual que el mock).
  void _abrirBusqueda() {
    if (widget.busqueda == null) {
      unawaited(_abrirAsistente());
      return;
    }
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
    final campo = widget.busqueda == null
        ? null
        : CampoBusquedaContextual(
            key: ValueKey('busqueda_contextual_$_vueltaBusqueda'),
            busqueda: widget.busqueda!,
            foco: _focoBusqueda,
            alSalir: _cerrarBusqueda,
          );

    return NavbarSuperior(
      claveActiva: widget.claveActiva,
      items: _items,
      onSeleccionar: _seleccionar,
      izquierda: BotonCajaDeGestion(db: widget.db),
      onAbrirAsistente: () => unawaited(_abrirAsistente()),
      acciones: const BotonNotificaciones(),
      busqueda: campo,
      buscando: _buscando,
      onAbrirBusqueda: _abrirBusqueda,
      onCerrarBusqueda: _cerrarBusqueda,
      child: widget.child,
    );
  }
}

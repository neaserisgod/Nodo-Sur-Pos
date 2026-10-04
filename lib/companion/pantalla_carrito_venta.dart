// Vender, tal cual el mock (docs/03 B2): la pestaña central de la barra, con tres
// pasos — armar el carrito, elegir cómo paga y la venta cobrada — y el estado
// "La caja está cerrada". La lógica de la venta es la de siempre (El dueño,
// 2026-09-07: "que la parte de vender use la misma lógica que la app de
// desktop"): buscar, calcular el total real (recargo de cigarrillos, redondeo,
// descuento), cobrar en efectivo o por la terminal y asentar la venta.
//
// Lo que el mock no tiene y la app sí se conserva con el mismo aspecto:
// el crédito en 1 pago, "Cobrar a mano (sin terminal)", el caramelo cuando el
// vuelto es de $100, entregar un encargue, gramos exactos con doble toque y
// "Deshacer" al quitar una línea. Mixto (efectivo + QR/débito) todavía no se
// cobra desde el celular: queda pendiente de decidir (ver el documento
// `docs/COMPARACION-MOCK-CELULAR.md`).

import 'package:flutter/material.dart';

import '../data/identidad_sync.dart' show generarGlobalId;
import '../data/repositorio_tablero.dart' show tableroDelDia;
import '../domain/cobro_posnet.dart' show canalCredito, canalDebito, canalQr;
import '../domain/descuento.dart';
import '../domain/dinero.dart';
import '../domain/venta.dart';
import '../domain/vuelto.dart';
import 'app_ns.dart';
import 'base_local.dart';
import 'carrito_venta.dart';
import 'cliente_companion.dart';
import 'debounce.dart';
import 'dialogo_cobro_posnet_companion.dart';
import 'escanear_codigo.dart';
import 'kit/kit_ns.dart';
import 'mensaje_error.dart';
import 'pantallas/hoja_abrir_caja_ns.dart';
import 'servicio_companion.dart';

enum _MedioVenta { efectivo, qr, debito, credito }

/// Canal de la Point de cada medio virtual (crédito siempre en 1 pago).
String _canalDe(_MedioVenta m) => switch (m) {
  _MedioVenta.debito => canalDebito,
  _MedioVenta.credito => canalCredito,
  _ => canalQr,
};

/// Los tres momentos de una venta en esta pantalla.
enum _Paso { carrito, cobro, cobrado }

/// Descuento fijo del mock: 10 % sobre el total (1000 puntos básicos).
const int _descuentoFijoBp = 1000;

/// Lo que muestra "Venta cobrada" una vez asentada la venta.
typedef _ResumenCobro = ({int ventaId, int totalCentavos, _MedioVenta medio, int productos, int vueltoCentavos});

class PantallaCarritoVenta extends StatefulWidget {
  const PantallaCarritoVenta({
    super.key,
    required this.cliente,
    required this.servicio,
    required this.usuarioId,
    required this.carrito,
    this.encargueId,
  });

  /// Imprimir ticket — exclusivo de la PC. Null sin PC emparejada.
  final ClienteCompanion? cliente;

  /// Buscar, calcular, sesión y cobrar, con fallback a la base local.
  final ServicioCompanion servicio;

  final int usuarioId;

  /// El carrito del menú principal (lista mutable compartida).
  final List<LineaVenta> carrito;

  /// El encargue por apartado que esta venta entrega: al cobrar libera lo apartado.
  final int? encargueId;

  @override
  State<PantallaCarritoVenta> createState() => _PantallaCarritoVentaState();
}

class _PantallaCarritoVentaState extends State<PantallaCarritoVenta> {
  _MedioVenta _medio = _MedioVenta.efectivo;
  ResultadoTotalVenta? _resultado;
  bool _calculando = false;
  bool _cobrando = false;
  String? _error;

  _Paso _paso = _Paso.carrito;
  _ResumenCobro? _cobrado;

  /// Con cuánto paga en efectivo: un billete elegido, "Justo" o lo escrito en "Otro monto".
  int? _pagaCentavos;
  bool _pagaJusto = true;
  final _otroCtrl = TextEditingController();
  bool _escaneando = false;

  /// Descuento fijo del 10 % (el del mock). El valor se guarda como porcentaje.
  bool _descuento = false;
  TipoDescuento _tipoDescuento = TipoDescuento.porcentaje;
  int _valorDescuento = 0;

  final _busquedaCtrl = TextEditingController();
  final _busquedaFocus = FocusNode();
  final _debouncerBusqueda = Debouncer();
  List<ProductoCompanion> _resultadosBusqueda = [];
  int? _gramosBusqueda;
  bool _buscando = false;

  /// "Más vendidos": cuatro productos para tocar con el carrito vacío.
  List<ProductoCompanion> _masVendidos = [];

  // Identifica este intento de cobro ante el servidor (ver `/ventas/cobrar`): se renueva cuando cambia lo que se cobra y al
  // cobrar, así un reintento por mala señal no duplica la venta pero una venta igual a la anterior sí se graba.
  String? _claveCobroActual;
  String get _claveCobro => _claveCobroActual ??= generarGlobalId();

  @override
  void initState() {
    super.initState();
    _cargarMasVendidos();
  }

  @override
  void dispose() {
    _otroCtrl.dispose();
    _busquedaCtrl.dispose();
    _busquedaFocus.dispose();
    _debouncerBusqueda.dispose();
    super.dispose();
  }

  void _ocultarBarra(bool oculta) {
    // La barra inferior se esconde en los pasos de cobro y de "hecho" (docs/02 §1.2).
    AppNs.of(context).ocultarBarra.value = oculta;
  }

  Future<void> _cargarMasVendidos() async {
    try {
      final todos = await widget.servicio.productos();
      final activos = todos.where((p) => p.activo && !p.esPesable && p.precioCentavos != null).toList();
      final nombres = <String>[];
      try {
        final t = await tableroDelDia(baseLocalCompanion());
        nombres.addAll(t.masVendidos.map((m) => m.nombre));
      } catch (_) {
        // Sin ventas de hoy se completa con el catálogo.
      }
      final elegidos = <ProductoCompanion>[
        for (final nombre in nombres) ...activos.where((p) => p.nombre == nombre).take(1),
      ];
      for (final p in activos) {
        if (elegidos.length >= 4) break;
        if (!elegidos.contains(p)) elegidos.add(p);
      }
      if (mounted) setState(() => _masVendidos = elegidos.take(4).toList());
    } catch (_) {
      // Sin catálogo todavía: la grilla queda vacía.
    }
  }

  // ───────────────────────── Carrito ─────────────────────────

  Future<void> _buscar(String texto) async {
    if (texto.trim().isEmpty) {
      setState(() {
        _resultadosBusqueda = [];
        _gramosBusqueda = null;
      });
      return;
    }
    setState(() => _buscando = true);
    try {
      final resultado = await widget.servicio.buscarVenta(texto);
      // Una respuesta vieja que llega tarde no debe pisar el resultado del texto actual.
      if (mounted && _busquedaCtrl.text == texto) {
        setState(() {
          _resultadosBusqueda = resultado.resultados;
          _gramosBusqueda = resultado.gramos;
        });
      }
    } finally {
      if (mounted && _busquedaCtrl.text == texto) setState(() => _buscando = false);
    }
  }

  /// Agrega [producto] al carrito con la misma lógica que `VentaControlador.agregarProducto`
  /// (Regla 3, `lineaDesdeResultadoBusqueda`): un producto repetido suma en la misma línea.
  /// Un pesable entra con 250 g si no se escribieron gramos (paso del mock).
  void _agregar(ProductoCompanion producto, {bool limpiar = true}) {
    final resultado = lineaDesdeResultadoBusqueda(producto, gramos: producto.esPesable ? (_gramosBusqueda ?? 250) : null);
    if (resultado.error != null) {
      mostrarAvisoNs(context, resultado.error!, largo: true);
      return;
    }
    final nueva = resultado.linea!;
    _claveCobroActual = null;
    setState(() {
      final i = widget.carrito.indexWhere((l) => l.productoId == nueva.productoId);
      if (i != -1) {
        widget.carrito[i] = sumarLineasVenta(widget.carrito[i], nueva);
      } else {
        widget.carrito.add(nueva);
      }
      _resultado = null;
      if (limpiar) {
        _busquedaCtrl.clear();
        _resultadosBusqueda = [];
        _gramosBusqueda = null;
      }
    });
  }

  void _quitarLinea(int index) {
    final quitada = widget.carrito[index];
    _actualizarLinea(index, null);
    // Un toque saca la línea, así que se puede deshacer (sigue en la app aunque el mock no lo tenga).
    final mensajero = ScaffoldMessenger.of(context);
    mensajero.clearSnackBars();
    mensajero.showSnackBar(
      SnackBar(
        content: Text('Quitaste ${quitada.nombreProducto}'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () {
            if (!mounted) return;
            _claveCobroActual = null;
            setState(() {
              widget.carrito.insert(index.clamp(0, widget.carrito.length), quitada);
              _resultado = null;
            });
          },
        ),
      ),
    );
  }

  /// `nueva` null = eliminar la línea (restar por debajo de 1 saca la línea entera).
  void _actualizarLinea(int index, LineaVenta? nueva) {
    _claveCobroActual = null;
    setState(() {
      if (nueva == null) {
        widget.carrito.removeAt(index);
      } else {
        widget.carrito[index] = nueva;
      }
      _resultado = null;
    });
  }

  LineaVenta _conValor(LineaVenta l, int valor) {
    if (l is LineaVentaPesable) {
      return LineaVentaPesable(
        productoId: l.productoId,
        nombreProducto: l.nombreProducto,
        proveedorId: l.proveedorId,
        gramos: valor,
        precioPorKiloCentavos: l.precioPorKiloCentavos,
        costoPorKiloCentavos: l.costoPorKiloCentavos,
      );
    }
    final u = l as LineaVentaPorUnidad;
    return LineaVentaPorUnidad(
      productoId: u.productoId,
      nombreProducto: u.nombreProducto,
      proveedorId: u.proveedorId,
      cantidad: valor,
      esVarios: u.esVarios,
      tipoCigarrillo: u.tipoCigarrillo,
      precioUnitarioCentavos: u.precioUnitarioCentavos,
      costoUnitarioCentavos: u.costoUnitarioCentavos,
    );
  }

  /// − / + de una línea: 1 unidad, o 50 g si es por peso (docs/02 §3.2).
  void _ajustarLinea(int index, int signo) {
    final l = widget.carrito[index];
    final actual = l is LineaVentaPesable ? l.gramos : (l as LineaVentaPorUnidad).cantidad;
    final nuevo = actual + (l is LineaVentaPesable ? 50 : 1) * signo;
    if (nuevo <= 0) return _quitarLinea(index);
    _actualizarLinea(index, _conValor(l, nuevo));
  }

  /// Doble toque sobre la cantidad: escribir el valor exacto (gramos o unidades).
  Future<void> _editarExacto(int index) async {
    final l = widget.carrito[index];
    final esPesable = l is LineaVentaPesable;
    final actual = esPesable ? l.gramos : (l as LineaVentaPorUnidad).cantidad;
    final ctrl = TextEditingController(text: '$actual');
    final valor = await mostrarHojaNs<int>(
      context,
      builder: (ctx) => HojaNs(
        titulo: esPesable ? 'Gramos' : 'Cantidad',
        bloques: [
          CampoNs(etiqueta: esPesable ? 'Gramos' : 'Cantidad', controller: ctrl, grande: true, teclado: TextInputType.number, formatos: soloDigitosNs, autofoco: true, onSubmit: (t) => Navigator.of(ctx).pop(int.tryParse(t))),
        ],
        botones: [
          BotonNs.primario(ctx, 'Listo', () => Navigator.of(ctx).pop(int.tryParse(ctrl.text))),
          BotonNs.secundario(ctx, 'Cancelar', () => Navigator.of(ctx).pop()),
        ],
      ),
    );
    ctrl.dispose();
    if (valor == null || !mounted) return;
    if (valor <= 0) return _quitarLinea(index);
    _actualizarLinea(index, _conValor(widget.carrito[index], valor));
  }

  /// Escanea un código y suma el producto: el mismo camino que tocar un resultado.
  Future<void> _escanearYAgregar() async {
    if (_escaneando) return;
    final codigo = await escanearCodigo(context);
    if (codigo == null || !mounted) return;
    setState(() => _escaneando = true);
    try {
      final producto = await widget.servicio.porCodigoBarras(codigo);
      if (!mounted) return;
      if (producto == null) {
        mostrarAvisoNs(context, 'No hay un producto con ese código.');
      } else {
        _agregar(producto);
      }
    } catch (e) {
      if (mounted) mostrarAvisoNs(context, mensajeDeError(e), largo: true);
    } finally {
      if (mounted) setState(() => _escaneando = false);
    }
  }

  int get _subtotalCentavos => Venta(lineas: widget.carrito).subtotalCentavos;

  /// Descuento del chip: 10 % del subtotal, redondeado al peso (docs/02 §4.1).
  int get _descuentoCentavos => _descuento ? ((_subtotalCentavos * _descuentoFijoBp / 10000) / centavosPorPeso).round() * centavosPorPeso : 0;

  void _alternarDescuento() {
    _claveCobroActual = null;
    setState(() {
      _descuento = !_descuento;
      _tipoDescuento = TipoDescuento.porcentaje;
      _valorDescuento = _descuento ? _descuentoFijoBp : 0;
      _resultado = null;
    });
  }

  // ───────────────────────── Cobro ─────────────────────────

  Future<void> _irACobro() async {
    if (widget.carrito.isEmpty) {
      mostrarAvisoNs(context, 'Agregá al menos un producto para cobrar');
      return;
    }
    _otroCtrl.clear();
    setState(() {
      _paso = _Paso.cobro;
      _pagaCentavos = null;
      _pagaJusto = true;
      _medio = _MedioVenta.efectivo;
    });
    _ocultarBarra(true);
    await _elegirMedio(_MedioVenta.efectivo);
  }

  void _volverAlCarrito() {
    setState(() {
      _paso = _Paso.carrito;
      _error = null;
    });
    _ocultarBarra(false);
  }

  Future<void> _elegirMedio(_MedioVenta medio) async {
    _claveCobroActual = null;
    setState(() {
      _medio = medio;
      _calculando = true;
      _error = null;
    });
    try {
      final resultado = await widget.servicio.calcularVenta(
        lineas: widget.carrito,
        medio: medio == _MedioVenta.efectivo ? 'efectivo' : 'virtual',
        tipoDescuento: _valorDescuento == 0 ? null : _tipoDescuento,
        valorDescuento: _valorDescuento,
      );
      if (mounted) setState(() => _resultado = resultado);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _calculando = false);
    }
  }

  int get _otroMontoCentavos {
    final digitos = _otroCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitos.isEmpty) return 0;
    return (int.tryParse(digitos) ?? 0) * centavosPorPeso;
  }

  /// Con cuánto paga: lo escrito en "Otro monto" (si es mayor a cero), si no el
  /// billete elegido o, con "Justo", el total.
  int _pagaEfectivoCentavos(int total) {
    final otro = _otroMontoCentavos;
    if (otro > 0) return otro;
    if (_pagaJusto) return total;
    return _pagaCentavos ?? total;
  }

  Future<void> _confirmar() async {
    final total = _resultado?.totalCentavos;
    if (total == null || _calculando || _cobrando) return;
    if (_medio == _MedioVenta.efectivo) {
      final falta = total - _pagaEfectivoCentavos(total);
      if (falta > 0) {
        mostrarAvisoNs(context, 'Falta ${plataNs(falta)}: el cliente tiene que pagar con más');
        return;
      }
      await _cobrarEfectivo();
    } else {
      await _cobrarPosnet(_canalDe(_medio));
    }
  }

  Future<void> _cobrarEfectivo() async {
    final sesionId = AppNs.of(context).sesion?.id;
    if (sesionId == null) return;
    setState(() {
      _cobrando = true;
      _error = null;
    });
    try {
      final r = await widget.servicio.cobrarEfectivo(
        lineas: widget.carrito,
        sesionCajaId: sesionId,
        usuarioId: widget.usuarioId,
        tipoDescuento: _valorDescuento == 0 ? null : _tipoDescuento,
        valorDescuento: _valorDescuento,
        encargueId: widget.encargueId,
        claveCobro: _claveCobro,
      );
      await _ventaCobrada(r.ventaId, r.totalCentavos);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cobrando = false);
    }
  }

  Future<void> _cobrarPosnet(String canal) async {
    final sesionId = AppNs.of(context).sesion?.id;
    if (sesionId == null) return;
    // Sin este try/finally, una excepción antes de que se abra la terminal dejaba `_cobrando` en `true` para siempre.
    setState(() {
      _cobrando = true;
      _error = null;
    });
    try {
      final total = _resultado?.totalCentavos;
      if (total == null) {
        setState(() => _error = 'Elegí el medio de pago de nuevo antes de cobrar.');
        return;
      }
      final resultado = await mostrarDialogoCobroPosnetCompanion(
        context,
        cliente: widget.servicio,
        usuarioId: widget.usuarioId,
        sesionCajaId: sesionId,
        lineas: widget.carrito,
        canal: canal,
        montoCentavos: total,
        tipoDescuento: _valorDescuento == 0 ? null : _tipoDescuento,
        valorDescuento: _valorDescuento,
        encargueId: widget.encargueId,
      );
      if (resultado != null) await _ventaCobrada(resultado.ventaId, resultado.totalCentavos);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cobrando = false);
    }
  }

  /// Asienta la venta sin tocar la terminal (ventas ya cobradas por otro medio:
  /// link de pago, MP de otro celular). Mismo endpoint que el fallback de la terminal.
  Future<void> _cobrarAMano() async {
    final sesionId = AppNs.of(context).sesion?.id;
    if (_medio == _MedioVenta.efectivo || sesionId == null) return;
    setState(() {
      _cobrando = true;
      _error = null;
    });
    try {
      final r = await widget.servicio.cobrarVirtualAMano(
        lineas: widget.carrito,
        sesionCajaId: sesionId,
        usuarioId: widget.usuarioId,
        canal: _canalDe(_medio),
        tipoDescuento: _valorDescuento == 0 ? null : _tipoDescuento,
        valorDescuento: _valorDescuento,
        encargueId: widget.encargueId,
        claveCobro: _claveCobro,
      );
      await _ventaCobrada(r.ventaId, r.totalCentavos);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cobrando = false);
    }
  }

  Future<void> _ventaCobrada(int ventaId, int totalCentavos) async {
    _claveCobroActual = null;
    // El resumen se arma ANTES de vaciar el carrito: cuántos productos fueron
    // y cuánto se devuelve dependen de lo que había.
    final medio = _medio;
    final productos = widget.carrito.length;
    final vuelto = medio == _MedioVenta.efectivo ? vueltoCentavos(pagaCentavos: _pagaEfectivoCentavos(totalCentavos), totalCentavos: totalCentavos) : 0;
    widget.carrito.clear();
    _descuento = false;
    _valorDescuento = 0;
    if (!mounted) return;
    setState(() {
      _cobrado = (ventaId: ventaId, totalCentavos: totalCentavos, medio: medio, productos: productos, vueltoCentavos: vuelto < 0 ? 0 : vuelto);
      _paso = _Paso.cobrado;
    });
    // El resumen del día (Inicio, Caja) cambió.
    AppNs.of(context).refrescar();
  }

  Future<void> _imprimirTicket(int ventaId) async {
    final cliente = widget.cliente;
    if (cliente == null || AppNs.of(context).sinConexion) {
      mostrarAvisoNs(context, 'Para imprimir hace falta estar conectado a la PC');
      return;
    }
    try {
      await cliente.imprimirTicket(ventaId);
      if (mounted) mostrarAvisoNs(context, 'Ticket enviado a la impresora');
    } catch (e) {
      if (mounted) mostrarAvisoNs(context, 'No se pudo imprimir: ${mensajeDeError(e)}', largo: true);
    }
  }

  void _nuevaVenta() {
    setState(() {
      _paso = _Paso.carrito;
      _cobrado = null;
      _resultado = null;
      _error = null;
    });
    _ocultarBarra(false);
  }

  void _volverAlInicio() {
    _nuevaVenta();
    AppNs.of(context).irAPestania(PestaniaNs.inicio);
  }

  /// REGLAS-NEGOCIO §3: con $100 de vuelto exactos se agrega el producto de vuelto en vez de dar el cambio.
  Future<void> _agregarCaramelo() async {
    try {
      final config = await widget.servicio.configuracionNegocio();
      final id = config.productoVueltoId;
      if (id == null) {
        if (mounted) mostrarAvisoNs(context, 'No hay un producto de vuelto configurado (Más → Configuración).', largo: true);
        return;
      }
      final todos = await widget.servicio.productos();
      final producto = todos.where((x) => x.id == id).firstOrNull;
      if (!mounted) return;
      if (producto == null) {
        mostrarAvisoNs(context, 'No se encontró el producto de vuelto.');
        return;
      }
      _agregar(producto, limpiar: false);
      setState(() {
        _pagaCentavos = null;
        _pagaJusto = true;
        _otroCtrl.clear();
      });
      await _elegirMedio(_MedioVenta.efectivo);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  // ───────────────────────── Pantalla ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final app = AppNs.of(context);
    final ns = context.ns;
    final abierta = app.cajaAbierta;
    return PopScope(
      // En "cobrar" y en "hecho" volver es volver al carrito, no salir de la venta.
      canPop: _paso == _Paso.carrito,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_paso == _Paso.cobro) _volverAlCarrito();
        if (_paso == _Paso.cobrado) _nuevaVenta();
      },
      child: ColoredBox(
        color: ns.paper,
        child: SafeArea(
          bottom: false,
          child: PantallaEntradaNs(
            child: !abierta && _paso == _Paso.carrito
                ? _CajaCerrada(onAbrir: () => mostrarHojaAbrirCaja(context, servicio: widget.servicio, usuarioId: widget.usuarioId).then((_) => app.refrescar()))
                : switch (_paso) {
                    _Paso.carrito => _vistaCarrito(context),
                    _Paso.cobro => _vistaCobro(context),
                    _Paso.cobrado => _vistaCobrado(context),
                  },
          ),
        ),
      ),
    );
  }

  Widget _vistaCarrito(BuildContext context) {
    final ns = context.ns;
    final n = widget.carrito.length;
    final buscando = _busquedaCtrl.text.trim().isNotEmpty;
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(child: Text('Venta', style: tituloNs(40, color: ns.ink))),
                  if (n > 0) Text(n == 1 ? '1 producto' : '$n productos', style: estiloNs(15, peso: FontWeight.w600, color: ns.mute)),
                ],
              ),
              const SizedBox(height: 14),
              _FilaBuscador(
                controller: _busquedaCtrl,
                foco: _busquedaFocus,
                escaneando: _escaneando,
                onEscanear: _escanearYAgregar,
                onChanged: (t) {
                  setState(() {});
                  if (t.trim().isEmpty) {
                    _debouncerBusqueda.cancelar();
                    _buscar(t);
                  } else {
                    _debouncerBusqueda.ejecutar(() => _buscar(t));
                  }
                },
              ),
              const SizedBox(height: 14),
              Expanded(child: n == 0 ? _vacio(context) : _lineas(context)),
              if (n > 0) ...[
                _filaDescuento(context),
                const SizedBox(height: 14),
                _barraTotal(context),
                const SizedBox(height: BarraInferiorNs.espacioReservado - 40),
              ] else
                const SizedBox(height: BarraInferiorNs.espacioReservado),
            ],
          ),
        ),
        if (buscando)
          Positioned(
            left: margenNs,
            right: margenNs,
            // 28 de margen + 40 del título + 14 + 64 hasta debajo del campo.
            top: 28 + 40 + 14 + 64,
            child: _MenuBusqueda(resultados: _resultadosBusqueda.take(4).toList(), buscando: _buscando, onElegir: _agregar),
          ),
      ],
    );
  }

  Widget _vacio(BuildContext context) {
    final ns = context.ns;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Text('Buscá, escaneá o tocá un producto para empezar.', style: estiloNs(15, color: ns.mute)),
        const SizedBox(height: 14),
        const SeccionNs('Más vendidos'),
        const SizedBox(height: 10),
        if (_masVendidos.isNotEmpty)
          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 165 / 84,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final p in _masVendidos)
                PresionNs(
                  onTap: () => _agregar(p),
                  etiqueta: p.nombre,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 84),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(24)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(p.nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: estiloNs(15, peso: FontWeight.w500, track: -0.01, altura: 1.2, color: ns.ink)),
                        Text(plataNs(p.precioCentavos ?? 0), style: estiloNs(15, peso: FontWeight.w500, color: ns.mute, tabular: true)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _lineas(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: widget.carrito.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) => EntradaNs(
        child: _LineaCarrito(
          linea: widget.carrito[i],
          onMenos: () => _ajustarLinea(i, -1),
          onMas: () => _ajustarLinea(i, 1),
          onQuitar: () => _quitarLinea(i),
          onEditar: () => _editarExacto(i),
        ),
      ),
    );
  }

  Widget _filaDescuento(BuildContext context) {
    final ns = context.ns;
    return Row(
      children: [
        PresionNs(
          onTap: _alternarDescuento,
          etiqueta: _descuento ? 'Quitar descuento 10 %' : 'Aplicar descuento 10 %',
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(color: _descuento ? ns.prim : ns.s, borderRadius: BorderRadius.circular(999)),
            child: Center(
              widthFactor: 1,
              child: Text(_descuento ? 'Descuento 10 % aplicado' : 'Aplicar descuento 10 %', style: estiloNs(14, peso: FontWeight.w600, color: _descuento ? TokensNs.blanco : ns.ink)),
            ),
          ),
        ),
        const Spacer(),
        if (_descuento) Text('− ${plataNs(_descuentoCentavos)}', style: estiloNs(14, color: ns.mute, tabular: true)),
      ],
    );
  }

  Widget _barraTotal(BuildContext context) {
    final ns = context.ns;
    final total = _subtotalCentavos - _descuentoCentavos;
    return HeroNs(
      radio: 34,
      padding: const EdgeInsets.fromLTRB(26, 16, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Total', style: estiloNs(13, peso: FontWeight.w600, color: const Color(0xB8FFFFFF))),
                FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(plataNs(total), style: tituloNs(38, color: TokensNs.blanco))),
              ],
            ),
          ),
          const SizedBox(width: 12),
          BotonNs(texto: 'Cobrar', onTap: _irACobro, alto: 56, tamanio: 17, fondo: ns.paper, color: ns.ink, rellenar: false, paddingH: 30),
        ],
      ),
    );
  }

  // ───────────────────────── Cobrar ─────────────────────────

  static const _nombres = {
    _MedioVenta.efectivo: 'Efectivo',
    _MedioVenta.qr: 'Mercado Pago',
    _MedioVenta.debito: 'Tarjeta de débito',
    _MedioVenta.credito: 'Tarjeta de crédito',
  };

  static const _colores = {
    _MedioVenta.efectivo: TokensNs.medioEfectivo,
    _MedioVenta.qr: TokensNs.medioMercadoPago,
    _MedioVenta.debito: TokensNs.medioDebito,
    _MedioVenta.credito: TokensNs.medioMixto,
  };

  static const _iconos = {
    _MedioVenta.efectivo: IconoNs.billetes,
    _MedioVenta.qr: IconoNs.escanear,
    _MedioVenta.debito: IconoNs.tarjeta,
    _MedioVenta.credito: IconoNs.tarjeta,
  };

  Widget _vistaCobro(BuildContext context) {
    final ns = context.ns;
    final total = _resultado?.totalCentavos;
    final efectivo = _medio == _MedioVenta.efectivo;
    final falta = (efectivo && total != null) ? total - _pagaEfectivoCentavos(total) : 0;
    final puede = total != null && !_calculando && !_cobrando;
    final textoBoton = _cobrando ? 'Cobrando…' : (falta > 0 ? 'Falta ${plataNs(falta)} para cobrar' : 'Confirmar cobro de ${plataNs(total ?? 0)}');
    final activo = puede && falta <= 0;
    final r = _resultado;
    return Padding(
      padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              BotonCircularNs(icono: IconoNs.volver, onTap: _cobrando ? null : _volverAlCarrito, etiqueta: 'Volver', tamanioIcono: 18, grosor: 2.4),
              const SizedBox(width: 12),
              Text('Cobrar', style: tituloNs(30, track: -0.05, color: ns.ink)),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                Text('Total a cobrar', style: estiloNs(14, peso: FontWeight.w600, color: ns.mute)),
                Text(total == null ? '…' : plataNs(total), style: tituloNs(62, track: -0.06, color: ns.ink)),
                if (r != null && (r.recargoCigarrillosCentavos > 0 || r.descuentoCentavos > 0 || r.redondeoCentavos > 0))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      [
                        if (r.recargoCigarrillosCentavos > 0) 'Recargo ${plataNs(r.recargoCigarrillosCentavos)}',
                        if (r.descuentoCentavos > 0) 'Desc. -${plataNs(r.descuentoCentavos)}',
                        if (r.redondeoCentavos > 0) 'Redondeo ${plataNs(r.redondeoCentavos)}',
                      ].join(' · '),
                      style: estiloNs(14, color: ns.mute, tabular: true),
                    ),
                  ),
                const SizedBox(height: 14),
                Text('¿Cómo paga?', style: estiloNs(17, peso: FontWeight.w600, color: ns.ink)),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 170 / 68,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final m in _MedioVenta.values)
                      _TarjetaMedio(nombre: _nombres[m]!, icono: _iconos[m]!, color: _colores[m]!, activo: _medio == m, onTap: _cobrando ? null : () => _elegirMedio(m)),
                  ],
                ),
                const SizedBox(height: 14),
                if (efectivo && total != null) _panelEfectivo(context, total),
                if (!efectivo) ...[
                  InfoNs(
                    _medio == _MedioVenta.qr
                        ? 'Se cobra con el QR de Mercado Pago en la terminal. Vas a ver acá si el pago se aprobó.'
                        : 'Se cobra con la tarjeta en la terminal. Vas a ver acá si el pago se aprobó.',
                    tono: TonoNs.info,
                    radio: 24,
                    tamanio: 15,
                    peso: FontWeight.w500,
                  ),
                  const SizedBox(height: 4),
                  BotonNs.texto(context, 'Cobrar a mano (sin terminal)', _cobrando ? null : _cobrarAMano),
                ],
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: InfoNs(_error!, tono: TonoNs.bad)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Con plata de menos el botón se ve apagado pero responde con el aviso del mock.
          BotonNs(
            texto: textoBoton,
            onTap: _confirmar,
            alto: 64,
            tamanio: 18,
            fondo: activo ? ns.prim : ns.s,
            color: activo ? TokensNs.blanco : ns.mute,
            habilitado: puede,
          ),
        ],
      ),
    );
  }

  Widget _panelEfectivo(BuildContext context, int total) {
    final ns = context.ns;
    final paga = _pagaEfectivoCentavos(total);
    final vuelto = vueltoCentavos(pagaCentavos: paga, totalCentavos: total);
    final billetes = atajosDeEfectivo(total, cuantos: 3).where((b) => b != total).take(3).toList();
    final otroActivo = _otroMontoCentavos > 0;
    return EntradaNs(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Con cuánto paga?', style: estiloNs(14, peso: FontWeight.w600, color: ns.mute)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ChipPago(
                  texto: 'Justo',
                  activo: !otroActivo && _pagaJusto,
                  onTap: () => setState(() {
                    _pagaJusto = true;
                    _otroCtrl.clear();
                  }),
                ),
                for (final b in billetes)
                  _ChipPago(
                    texto: plataNs(b),
                    activo: !otroActivo && !_pagaJusto && _pagaCentavos == b,
                    onTap: () => setState(() {
                      _pagaJusto = false;
                      _pagaCentavos = b;
                      _otroCtrl.clear();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(color: ns.paper, borderRadius: BorderRadius.circular(999)),
              child: Row(
                children: [
                  Text('Otro monto', style: estiloNs(14, peso: FontWeight.w600, color: ns.mute)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _otroCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: soloDigitosNs,
                      textAlign: TextAlign.right,
                      onChanged: (_) => setState(() {}),
                      cursorColor: ns.ink,
                      style: estiloNs(17, peso: FontWeight.w600, color: ns.ink, tabular: true),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintText: '\$ 0',
                        hintStyle: estiloNs(17, peso: FontWeight.w600, color: ns.mute),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              vuelto < 0 ? 'Falta ${plataNs(-vuelto)}' : 'Vuelto ${plataNs(vuelto)}',
              style: estiloNs(32, peso: FontWeight.w600, track: -0.04, color: vuelto < 0 ? ns.b : ns.g, tabular: true),
            ),
            if (vueltoEsCaramelo(vuelto)) BotonNs.texto(context, 'Agregar caramelo en vez del vuelto', _agregarCaramelo),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── Venta cobrada ─────────────────────────

  Widget _vistaCobrado(BuildContext context) {
    final ns = context.ns;
    final c = _cobrado!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CirculoTildeNs(tamanio: 76, fondo: ns.prim, color: TokensNs.blanco, tamanioTilde: 36),
                const SizedBox(height: 14),
                Text('Venta cobrada', style: tituloNs(50, track: -0.058, color: ns.ink)),
                const SizedBox(height: 14),
                Text(plataNs(c.totalCentavos), style: tituloNs(56, track: -0.06, color: ns.ink)),
                const SizedBox(height: 14),
                Text('${_nombres[c.medio]} · ${c.productos == 1 ? '1 producto' : '${c.productos} productos'}', style: estiloNs(16, color: ns.mute)),
                const SizedBox(height: 14),
                if (c.medio == _MedioVenta.efectivo)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                    decoration: BoxDecoration(color: ns.gbg, borderRadius: BorderRadius.circular(28)),
                    child: Text('Dar de vuelto ${plataNs(c.vueltoCentavos)}', style: estiloNs(30, peso: FontWeight.w600, color: ns.g, tabular: true)),
                  )
                else
                  Text('Cobro registrado en la caja', style: estiloNs(16, color: ns.mute)),
              ],
            ),
          ),
          BotonNs.secundario(context, 'Imprimir ticket', () => _imprimirTicket(c.ventaId), alto: 56),
          const SizedBox(height: 8),
          BotonNs.primario(context, 'Nueva venta', _nuevaVenta, alto: 64, tamanio: 18),
          const SizedBox(height: 8),
          BotonNs.texto(context, 'Volver al inicio', _volverAlInicio),
        ],
      ),
    );
  }
}

// ───────────────────────── Piezas de Vender ─────────────────────────

class _CajaCerrada extends StatelessWidget {
  const _CajaCerrada({required this.onAbrir});
  final VoidCallback onAbrir;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Padding(
      padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, BarraInferiorNs.espacioReservado),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Venta', style: tituloNs(40, color: ns.ink)),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 72, height: 72, decoration: BoxDecoration(color: ns.s, shape: BoxShape.circle), alignment: Alignment.center, child: IconoNsWidget(IconoNs.candado, tamanio: 32, color: ns.ink)),
                const SizedBox(height: 14),
                Text('La caja está cerrada', style: tituloNs(34, track: -0.05, color: ns.ink)),
                const SizedBox(height: 14),
                Text('Para cobrar primero abrí la caja con el fondo inicial.', style: estiloNs(16, color: ns.mute)),
                const SizedBox(height: 14),
                BotonNs(texto: 'Abrir caja', onTap: onAbrir, alto: 60, tamanio: 17, fondo: ns.prim, color: TokensNs.blanco, rellenar: false, paddingH: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilaBuscador extends StatelessWidget {
  const _FilaBuscador({required this.controller, required this.foco, required this.escaneando, required this.onEscanear, required this.onChanged});
  final TextEditingController controller;
  final FocusNode foco;
  final bool escaneando;
  final VoidCallback onEscanear;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Row(
      children: [
        Expanded(child: BuscadorNs(controller: controller, foco: foco, placeholder: 'Buscar producto', onChanged: onChanged)),
        const SizedBox(width: 8),
        PresionNs(
          onTap: escaneando ? null : onEscanear,
          etiqueta: 'Escanear código de barras',
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: ns.prim, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: escaneando
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: TokensNs.blanco))
                : const IconoNsWidget(IconoNs.escanear, tamanio: 24, color: TokensNs.blanco),
          ),
        ),
      ],
    );
  }
}

/// Menú flotante de resultados (docs/03 B2.1): hasta 4 filas de 52, radio 26.
class _MenuBusqueda extends StatelessWidget {
  const _MenuBusqueda({required this.resultados, required this.buscando, required this.onElegir});
  final List<ProductoCompanion> resultados;
  final bool buscando;
  final ValueChanged<ProductoCompanion> onElegir;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return EntradaNs(
      duracion: const Duration(milliseconds: 450),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: ns.paper,
          borderRadius: BorderRadius.circular(26),
          boxShadow: const [BoxShadow(color: Color(0x38121317), blurRadius: 60, offset: Offset(0, 24)), BoxShadow(color: Color(0x14121317), spreadRadius: 1)],
        ),
        child: resultados.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Text(buscando ? 'Buscando…' : 'No encontramos ese producto. Probá con otra parte del nombre.', style: estiloNs(15, color: ns.mute)),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final p in resultados)
                    PresionNs(
                      onTap: () => onElegir(p),
                      etiqueta: p.nombre,
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 52),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          children: [
                            Expanded(child: Text(p.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: estiloNs(17, peso: FontWeight.w500, color: ns.ink))),
                            const SizedBox(width: 10),
                            Text(p.esPesable ? '${plataNs(p.precioPorKiloCentavos ?? 0)}/kg' : plataNs(p.precioCentavos ?? 0), style: estiloNs(17, peso: FontWeight.w500, color: ns.ink, tabular: true)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _LineaCarrito extends StatelessWidget {
  const _LineaCarrito({required this.linea, required this.onMenos, required this.onMas, required this.onQuitar, required this.onEditar});

  final LineaVenta linea;
  final VoidCallback onMenos;
  final VoidCallback onMas;
  final VoidCallback onQuitar;
  final VoidCallback onEditar;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final cantidad = switch (linea) {
      LineaVentaPesable l => '${l.gramos} g',
      LineaVentaPorUnidad l => '${l.cantidad}',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(26)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(linea.nombreProducto, maxLines: 2, overflow: TextOverflow.ellipsis, style: estiloNs(17, peso: FontWeight.w500, track: -0.02, altura: 1.2, color: ns.ink))),
              const SizedBox(width: 12),
              Text(plataNs(linea.subtotalCentavos), maxLines: 1, style: estiloNs(19, peso: FontWeight.w500, track: -0.03, color: ns.ink, tabular: true)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              GestureDetector(onDoubleTap: onEditar, child: StepperNs(cantidad: cantidad, onMenos: onMenos, onMas: onMas)),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: BotonNs(texto: 'Quitar del carrito', onTap: onQuitar, alto: 44, tamanio: 14, fondo: Colors.transparent, color: ns.mute, rellenar: false, paddingH: 16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TarjetaMedio extends StatelessWidget {
  const _TarjetaMedio({required this.nombre, required this.icono, required this.color, required this.activo, required this.onTap});
  final String nombre;
  final IconoNs icono;
  final Color color;
  final bool activo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Semantics(
      selected: activo,
      child: PresionNs(
        onTap: onTap,
        etiqueta: nombre,
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: activo ? color : ns.s, borderRadius: BorderRadius.circular(26)),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: activo ? const Color(0x38FFFFFF) : ns.paper, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: IconoNsWidget(icono, tamanio: 20, color: activo ? TokensNs.blanco : color),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(nombre, maxLines: 2, style: estiloNs(16, peso: FontWeight.w600, track: -0.01, altura: 1.15, color: activo ? TokensNs.blanco : ns.ink))),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipPago extends StatelessWidget {
  const _ChipPago({required this.texto, required this.activo, required this.onTap});
  final String texto;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return PresionNs(
      onTap: onTap,
      etiqueta: texto,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(color: activo ? ns.prim : ns.paper, borderRadius: BorderRadius.circular(999)),
        child: Center(widthFactor: 1, child: Text(texto, style: estiloNs(15, peso: FontWeight.w600, color: activo ? TokensNs.blanco : ns.ink, tabular: true))),
      ),
    );
  }
}

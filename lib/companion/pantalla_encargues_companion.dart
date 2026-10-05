// Encargues en el celular (El dueño, 2026-10-02): lo que un cliente pidió y ya está en el local, apartado hasta que lo
// retire. Mismas reglas que la PC (`repositorio_encargues.dart`) a través del servicio, así que anda igual con la PC
// por wifi que sin ella. Apartar saca el stock ya; "Entregar" vuelve al menú con lo apartado para abrir el carrito;
// "Cancelar" lo devuelve al stock. "Entregar y anotar deuda" (2026-10-03, el fiado se unificó acá) deja una deuda que se cobra
// desde la sección "Deudas" de esta misma pantalla.

import 'package:flutter/material.dart';

import '../domain/dinero.dart';
import 'cliente_companion.dart' show ApartadoCompanion, DeudaCompanion, EncargueCompanion, ProductoCompanion;
import 'kit/kit_ns.dart';
import 'mensaje_error.dart';
import 'navegacion.dart';
import 'servicio_companion.dart';

/// Lo que devuelve la pantalla al elegir "Entregar": el menú arma el carrito con esto.
class EntregaEncargue {
  const EntregaEncargue(this.id);
  final int id;
}

class PantallaEncarguesCompanion extends StatefulWidget {
  const PantallaEncarguesCompanion({super.key, required this.servicio, required this.usuarioId, this.hayVentaArmada = false, this.sesionCajaId});

  final ServicioCompanion servicio;
  final int usuarioId;

  /// El celular tiene un solo carrito: con una venta armada no se puede abrir otra para entregar.
  final bool hayVentaArmada;

  /// La caja abierta, para cobrar una deuda como venta del día. Null = sin caja abierta.
  final int? sesionCajaId;

  @override
  State<PantallaEncarguesCompanion> createState() => _PantallaEncarguesCompanionState();
}

class _PantallaEncarguesCompanionState extends State<PantallaEncarguesCompanion> {
  List<EncargueCompanion> _encargues = const [];
  List<DeudaCompanion> _deudas = const [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final lista = await widget.servicio.encargues();
      final deudas = await widget.servicio.deudas();
      if (mounted) {
        setState(() {
          _encargues = lista;
          _deudas = deudas;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _nuevo() async {
    final creado = await pushSinTeclado<bool>(
      context,
      (_) => _PantallaNuevoEncargue(servicio: widget.servicio, usuarioId: widget.usuarioId),
    );
    if (creado == true) await _cargar();
  }

  Future<bool> _confirmar(String titulo, String texto, String confirmar, {bool peligro = true, String volver = 'Cancelar'}) async {
    final ok = await mostrarHojaNs<bool>(
      context,
      builder: (ctx) => HojaNs(
        titulo: titulo,
        texto: texto,
        botones: [
          peligro ? BotonNs.peligroSolido(ctx, confirmar, () => Navigator.of(ctx).pop(true)) : BotonNs.primario(ctx, confirmar, () => Navigator.of(ctx).pop(true)),
          BotonNs.secundario(ctx, volver, () => Navigator.of(ctx).pop(false)),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _cancelar(EncargueCompanion e) async {
    if (!await _confirmar('¿Cancelar el encargue de ${e.nombreCliente}?', 'Lo apartado vuelve al stock.', 'Cancelar encargue', volver: 'Volver')) return;
    try {
      await widget.servicio.cancelarEncargue(e.id, usuarioId: widget.usuarioId);
      await _cargar();
    } catch (err) {
      if (mounted) setState(() => _error = mensajeDeError(err));
    }
  }

  Future<void> _entregarADeuda(EncargueCompanion e) async {
    if (!await _confirmar(
      '¿Entregar a ${e.nombreCliente} y anotar la deuda?',
      'Se lleva lo apartado sin pagar. Queda en Deudas, a los precios de hoy, para cobrarle después. El stock ya está descontado.',
      'Entregar y anotar',
      peligro: false,
    )) {
      return;
    }
    try {
      await widget.servicio.entregarEncargueADeuda(e.id, usuarioId: widget.usuarioId);
      await _cargar();
    } catch (err) {
      if (mounted) setState(() => _error = mensajeDeError(err));
    }
  }

  Future<void> _cobrarDeuda(DeudaCompanion d) async {
    final sesionId = widget.sesionCajaId;
    if (sesionId == null) {
      await mostrarHojaNs<void>(
        context,
        builder: (ctx) => HojaNs(
          titulo: 'Cobrar a ${d.nombreCliente}',
          texto: formatearARS(d.montoCentavos),
          bloques: const [InfoNs('Para cobrar una deuda hay que abrir la caja: el cobro entra como una venta del día.', tono: TonoNs.warn)],
          botones: [BotonNs.secundario(ctx, 'Cerrar', () => Navigator.of(ctx).pop())],
        ),
      );
      return;
    }
    final efectivo = await mostrarHojaNs<bool>(
      context,
      builder: (ctx) => HojaNs(
        titulo: 'Cobrar a ${d.nombreCliente}',
        texto: formatearARS(d.montoCentavos),
        botones: [
          BotonNs.primario(ctx, 'Efectivo', () => Navigator.of(ctx).pop(true)),
          BotonNs.secundario(ctx, 'Mercado Pago', () => Navigator.of(ctx).pop(false)),
          BotonNs.secundario(ctx, 'Cancelar', () => Navigator.of(ctx).pop()),
        ],
      ),
    );
    if (efectivo == null) return;
    try {
      await widget.servicio.cobrarDeuda(d.id, usuarioId: widget.usuarioId, sesionCajaId: sesionId, efectivo: efectivo);
      await _cargar();
    } catch (err) {
      if (mounted) setState(() => _error = mensajeDeError(err));
    }
  }

  void _entregar(EncargueCompanion e) {
    if (widget.hayVentaArmada) {
      setState(() => _error = 'Hay una venta armada: cobrala o vaciala antes de entregar un encargue.');
      return;
    }
    Navigator.of(context).pop(EntregaEncargue(e.id));
  }

  Widget _fechaYNombre(BuildContext context, String desde, String nombre) {
    final ns = context.ns;
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SeccionNs('Desde el $desde'),
          const SizedBox(height: 4),
          Text(nombre, style: tituloNs(30, track: -0.045, altura: 1.1, color: ns.ink)),
        ],
      ),
    );
  }

  Widget _lineaDeTexto(BuildContext context, String texto) {
    final ns = context.ns;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: ns.s2))),
      child: Text(texto, style: estiloNs(15, color: ns.ink)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vacio = _encargues.isEmpty && _deudas.isEmpty;
    return PaginaNs(
      titulo: 'Encargues',
      cuerpo: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                KeyedSubtree(key: const Key('encargue_nuevo'), child: BotonNs.primario(context, 'Nuevo encargue', _nuevo, alto: 52, tamanio: 16)),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: InfoNs(_error!, key: const Key('encargues_error'), tono: TonoNs.bad),
                  ),
                if (vacio) const Padding(padding: EdgeInsets.only(top: 12), child: InfoNs('No hay encargues pendientes.')),
                for (final e in _encargues)
                  Column(
                    key: Key('encargue_${e.id}'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _fechaYNombre(context, '${e.desde.day}/${e.desde.month}', e.nombreCliente),
                      for (final l in e.lineas) _lineaDeTexto(context, l),
                      const SizedBox(height: 12),
                      BotonNs.primario(context, 'Entregar', () => _entregar(e), alto: 52, tamanio: 16),
                      const SizedBox(height: 8),
                      KeyedSubtree(key: Key('encargue_deuda_${e.id}'), child: BotonNs.secundario(context, 'Entregar y anotar deuda', () => _entregarADeuda(e), alto: 52)),
                      const SizedBox(height: 8),
                      BotonNs.peligroSuave(context, 'Cancelar encargue', () => _cancelar(e)),
                    ],
                  ),
                if (_deudas.isNotEmpty) ...[
                  const Padding(padding: EdgeInsets.only(top: 22, bottom: 4), child: SeccionNs('Deudas')),
                  for (final d in _deudas)
                    Column(
                      key: Key('deuda_${d.id}'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _fechaYNombre(context, '${d.desde.day}/${d.desde.month}', d.nombreCliente.isEmpty ? 'Deuda' : d.nombreCliente),
                        if (d.detalle.isNotEmpty) _lineaDeTexto(context, d.detalle),
                        const SizedBox(height: 12),
                        BotonNs.primario(context, 'Cobrar ${formatearARS(d.montoCentavos)}', () => _cobrarDeuda(d), alto: 52, tamanio: 16),
                      ],
                    ),
                ],
                const SizedBox(height: 12),
              ],
            ),
    );
  }
}

/// Alta: nombre del cliente y los productos a apartar (solo con stock; unidades, o gramos si es pesable).
class _PantallaNuevoEncargue extends StatefulWidget {
  const _PantallaNuevoEncargue({required this.servicio, required this.usuarioId});

  final ServicioCompanion servicio;
  final int usuarioId;

  @override
  State<_PantallaNuevoEncargue> createState() => _PantallaNuevoEncargueState();
}

class _PantallaNuevoEncargueState extends State<_PantallaNuevoEncargue> {
  final _nombre = TextEditingController();
  final _buscador = TextEditingController();
  List<ProductoCompanion> _resultados = const [];
  final List<({ProductoCompanion producto, int cantidad})> _elegidos = [];
  String? _error;
  bool _guardando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _buscador.dispose();
    super.dispose();
  }

  Future<void> _buscar(String texto) async {
    if (texto.trim().isEmpty) {
      setState(() => _resultados = const []);
      return;
    }
    try {
      final r = await widget.servicio.buscarVenta(texto);
      final yaElegidos = {for (final e in _elegidos) e.producto.id};
      if (mounted) setState(() => _resultados = r.resultados.where((p) => !yaElegidos.contains(p.id)).toList());
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  /// Un toque en el resultado lo suma con 1 (o 100 g si se pesa); después se ajusta con el stepper.
  void _elegir(ProductoCompanion p) {
    setState(() {
      _elegidos.add((producto: p, cantidad: p.esPesable ? 100 : 1));
      _buscador.clear();
      _resultados = const [];
      _error = null;
    });
  }

  void _cambiar(int i, int delta) {
    final e = _elegidos[i];
    final paso = e.producto.esPesable ? 100 : 1;
    final nueva = e.cantidad + delta * paso;
    setState(() {
      _error = null;
      if (nueva < paso) {
        _elegidos.removeAt(i);
      } else {
        _elegidos[i] = (producto: e.producto, cantidad: nueva);
      }
    });
  }

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.servicio.crearEncargue(
        nombreCliente: _nombre.text,
        lineas: [
          for (final e in _elegidos)
            ApartadoCompanion(
              productoId: e.producto.id,
              cantidad: e.producto.esPesable ? null : e.cantidad,
              gramos: e.producto.esPesable ? e.cantidad : null,
            ),
        ],
        usuarioId: widget.usuarioId,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return PaginaNs(
      titulo: 'Nuevo encargue',
      cuerpo: ListView(
        padding: EdgeInsets.zero,
        children: [
          KeyedSubtree(
            key: const Key('encargue_nombre'),
            child: CampoNs(etiqueta: 'Cliente', controller: _nombre, placeholder: 'Nombre del cliente'),
          ),
          const SizedBox(height: 10),
          KeyedSubtree(
            key: const Key('encargue_buscador'),
            child: CampoNs(etiqueta: 'Buscar producto para apartar', controller: _buscador, placeholder: 'Buscar producto', onChanged: _buscar),
          ),
          for (final p in _resultados)
            KeyedSubtree(
              key: Key('encargue_opcion_${p.id}'),
              child: FilaProductoNs(
                nombre: p.nombre,
                detalle: p.esPesable ? '${p.stockGramos ?? 0} g en stock' : '${p.stock} en stock',
                onTap: () => _elegir(p),
              ),
            ),
          const SizedBox(height: 10),
          for (var i = 0; i < _elegidos.length; i++)
            Padding(
              key: Key('encargue_elegido_$i'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 6, 8, 6),
                decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)),
                child: Row(
                  children: [
                    Expanded(child: Text(_elegidos[i].producto.nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: estiloNs(15, peso: FontWeight.w500, color: ns.ink))),
                    StepperNs(
                      cantidad: _elegidos[i].producto.esPesable ? '${_elegidos[i].cantidad} g' : '${_elegidos[i].cantidad}',
                      onMenos: () => _cambiar(i, -1),
                      onMas: () => _cambiar(i, 1),
                      fondo: ns.s,
                      anchoCantidad: 54,
                      tamanioCantidad: 14,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      botones: [
        if (_error != null) InfoNs(_error!, key: const Key('encargue_error'), tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
        KeyedSubtree(
          key: const Key('encargue_apartar'),
          child: BotonNs.primario(context, 'Apartar', _guardando || _elegidos.isEmpty ? null : _guardar, habilitado: !_guardando && _elegidos.isNotEmpty),
        ),
      ],
    );
  }
}

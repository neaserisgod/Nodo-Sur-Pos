// Carga histórica desde el celular (El dueño, 2026-09-07: "quiero que agregues
// la parte de los históricos pero... se le pone la fecha, después es como
// si fuesen ventas que no descuentan stock, simplemente son para saber
// ganancias y todo eso") — mismo concepto que `lib/ui/carga_historica/` del
// escritorio: se elige la fecha una sola vez (solo el día, sin hora —
// El dueño: "necesito que solo sea el día que se cargue"), se cargan las
// ventas de ese día con el mismo buscador de Venta (sin exigir stock — un
// producto vendido en su momento puede estar en 0 hoy por cualquier otro
// motivo), y nada se graba hasta "Guardar" completo (una sola transacción
// del lado del servidor, Regla 3: la misma `cargarDiaHistoricoDesdeVentas`/
// `agregarVentasADiaHistorico` que ya usa el escritorio/servidor).
// Deliberadamente más simple que vender de verdad: sin posnet (los medios
// son etiquetas nada más, igual que en el escritorio), sin ticket, sin
// descuento.
//
// "Ver y editar" (El dueño, 2026-09-07: "dejame verlos y editarlos porque le
// erré y lo cerré sin completarlo") — esta pantalla es ahora un hub: lista
// los días ya cargados (`PantallaCargaHistorica`), entrando a uno se ve el
// detalle con opción de borrar una venta puntual, agregar más, o borrar el
// día entero (`_PantallaDetalleDiaHistorico`).

import 'package:flutter/material.dart';

import '../domain/dinero.dart';
import '../domain/medio_pago.dart';
import '../domain/venta.dart';
import 'base_local.dart';
import 'carrito_venta.dart';
import 'cliente_companion.dart';
import 'kit/kit_ns.dart';
import 'debounce.dart';
import 'emparejamiento.dart';
import 'mensaje_error.dart';
import 'navegacion.dart';
import 'puerto_local.dart';
import 'seleccion_servicio.dart';
import 'servicio_companion.dart';
import 'servicio_companion_offline.dart';

enum _MedioHistorico { efectivo, virtual, mixto }

extension on _MedioHistorico {
  String get texto => switch (this) {
    _MedioHistorico.efectivo => 'efectivo',
    _MedioHistorico.virtual => 'virtual',
    _MedioHistorico.mixto => 'mixto',
  };
  String get etiqueta => switch (this) {
    _MedioHistorico.efectivo => 'Efectivo',
    _MedioHistorico.virtual => 'Mercado Pago',
    _MedioHistorico.mixto => 'Mixto',
  };
}

String _formatearFecha(DateTime f) =>
    '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

String _medioDeTexto(String medio) => switch (medio) {
  'efectivo' => 'Efectivo',
  'virtual' => 'Mercado Pago',
  _ => 'Mixto',
};

/// El hub (mock 39): lista los días ya cargados, "Nuevo día" para arrancar uno.
class PantallaCargaHistorica extends StatefulWidget {
  const PantallaCargaHistorica({super.key});

  @override
  State<PantallaCargaHistorica> createState() => _PantallaCargaHistoricaState();
}

class _PantallaCargaHistoricaState extends State<PantallaCargaHistorica> {
  ServicioCompanion? _cliente;
  int? _usuarioId;
  List<DiaHistoricoCompanion> _dias = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  /// Sin PC emparejada (El dueño, 2026-09-18: "no debería tener que escanear
  /// ya, es innecesario") cae a la base local sincronizada por Supabase —
  /// cargar histórico no necesita la PC para nada.
  Future<void> _iniciar() async {
    final conexion = await leerConexion();
    final usuario = await leerUsuario();
    if (usuario == null || !mounted) return;
    final cliente = conexion == null ? ServicioCompanionOffline(PuertoLocal(baseLocalCompanion())) : await resolverServicioCompanion(conexion);
    if (!mounted) return;
    setState(() {
      _cliente = cliente;
      _usuarioId = usuario.id;
    });
    await _cargarDias();
  }

  Future<void> _cargarDias() async {
    if (_cliente == null) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final dias = await _cliente!.diasHistoricos();
      if (mounted) setState(() => _dias = dias);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _nuevoDia() async {
    await pushSinTeclado(context, (_) => _PantallaNuevoDiaHistorico(cliente: _cliente!, usuarioId: _usuarioId!));
    await _cargarDias();
  }

  Future<void> _abrirDia(DiaHistoricoCompanion dia) async {
    await pushSinTeclado(context, (_) => _PantallaDetalleDiaHistorico(cliente: _cliente!, usuarioId: _usuarioId!, sesionId: dia.sesionId, fecha: dia.fecha));
    await _cargarDias();
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return _PaginaNs(
      titulo: 'Días históricos',
      cuerpo: ListView(
        padding: EdgeInsets.zero,
        children: [
          const InfoNs('Cargá ventas de días que no registraste para tener las ganancias completas. No descuentan stock.'),
          const SizedBox(height: 10),
          if (_cargando)
            const EsqueletoListaNs(filas: 2, alto: 64)
          else if (_error != null)
            InfoNs(_error!, tono: TonoNs.bad)
          else if (_dias.isEmpty)
            Container(width: double.infinity, padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)), child: Text('Todavía no cargaste ningún día. Tocá "Nuevo día".', style: estiloNs(16, color: ns.mute)))
          else
            for (final d in _dias) ...[
              FilaProductoNs(
                nombre: _formatearFecha(d.fecha),
                detalle: '${d.cantidadVentas} ${d.cantidadVentas == 1 ? 'venta' : 'ventas'}',
                valor: plataNs(d.totalCentavos),
                onTap: () => _abrirDia(d),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
      botones: [BotonNs.primario(context, 'Nuevo día', _cliente == null ? null : _nuevoDia, habilitado: _cliente != null, alto: 60)],
    );
  }
}

/// Página con el aspecto del mock: volver, título de 32, el cuerpo que scrollea y los botones fijos abajo.
class _PaginaNs extends StatelessWidget {
  const _PaginaNs({required this.titulo, required this.cuerpo, this.botones = const []});
  final String titulo;
  final Widget cuerpo;
  final List<Widget> botones;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Scaffold(
      backgroundColor: ns.paper,
      body: SafeArea(
        child: PantallaEntradaNs(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CabeceraSubNs(titulo: titulo, onVolver: () => Navigator.of(context).maybePop()),
                const SizedBox(height: 14),
                Expanded(child: cuerpo),
                for (final b in botones) ...[const SizedBox(height: 8), b],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Confirmación de borrar algo del histórico (mock 39g/39h): hoja con el detalle y "Borrar" en rojo.
Future<bool> _confirmarBorrado(BuildContext context, {required String titulo, String? texto}) async {
  final ok = await mostrarHojaNs<bool>(
    context,
    builder: (ctx) => HojaNs(
      titulo: titulo,
      texto: texto,
      botones: [
        BotonNs.peligroSolido(ctx, 'Borrar', () => Navigator.of(ctx).pop(true)),
        BotonNs.secundario(ctx, 'Cancelar', () => Navigator.of(ctx).pop(false)),
      ],
    ),
  );
  return ok ?? false;
}

/// El detalle de un día ya cargado (mock 39e/39f): resumen, ventas con tacho, agregar más o borrar el día.
class _PantallaDetalleDiaHistorico extends StatefulWidget {
  const _PantallaDetalleDiaHistorico({required this.cliente, required this.usuarioId, required this.sesionId, required this.fecha});

  final ServicioCompanion cliente;
  final int usuarioId;
  final int sesionId;
  final DateTime fecha;

  @override
  State<_PantallaDetalleDiaHistorico> createState() => _PantallaDetalleDiaHistoricoState();
}

class _PantallaDetalleDiaHistoricoState extends State<_PantallaDetalleDiaHistorico> {
  List<VentaHistoricaResumenCompanion> _ventas = [];
  ResumenDiaHistoricoCompanion? _resumen;
  bool _cargando = true;
  String? _error;
  bool _verVentas = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final resultados = await Future.wait([widget.cliente.ventasDeDiaHistorico(widget.sesionId), widget.cliente.resumenDiaHistorico(widget.sesionId)]);
      if (mounted) {
        setState(() {
          _ventas = resultados[0] as List<VentaHistoricaResumenCompanion>;
          _resumen = resultados[1] as ResumenDiaHistoricoCompanion;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _eliminarVenta(VentaHistoricaResumenCompanion venta) async {
    // Una fila en una lista larga es fácil de tocar por error: pide confirmación como "Borrar el día".
    if (!await _confirmarBorrado(context, titulo: 'Borrar esta venta', texto: plataNs(venta.totalCentavos))) return;
    try {
      await widget.cliente.eliminarVentaHistorica(sesionId: widget.sesionId, ventaId: venta.ventaId, usuarioId: widget.usuarioId);
      await _cargar();
    } catch (e) {
      if (mounted) mostrarAvisoNs(context, 'No se pudo borrar: ${mensajeDeError(e)}', largo: true);
    }
  }

  Future<void> _agregarMas() async {
    await pushSinTeclado(context, (_) => _PantallaAgregarADiaHistorico(cliente: widget.cliente, usuarioId: widget.usuarioId, sesionId: widget.sesionId, fecha: widget.fecha));
    await _cargar();
  }

  Future<void> _borrarDia() async {
    if (!await _confirmarBorrado(context, titulo: 'Borrar día completo', texto: 'Se borran las ${_ventas.length} ventas de ${_formatearFecha(widget.fecha)}.')) return;
    try {
      await widget.cliente.eliminarDiaHistorico(widget.sesionId);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) mostrarAvisoNs(context, 'No se pudo borrar: ${mensajeDeError(e)}', largo: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PaginaNs(
      titulo: _formatearFecha(widget.fecha),
      cuerpo: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [ChipNs(texto: 'Resumen', activo: !_verVentas, onTap: () => setState(() => _verVentas = false)), const SizedBox(width: 8), ChipNs(texto: 'Ventas', activo: _verVentas, onTap: () => setState(() => _verVentas = true))]),
          const SizedBox(height: 10),
          Expanded(
            child: _cargando
                ? const EsqueletoListaNs(filas: 5, alto: 72)
                : _error != null
                ? SingleChildScrollView(child: EstadoErrorNs(texto: _error!, onReintentar: _cargar))
                : (_verVentas ? _pestanaVentas(context) : _pestanaResumen(context)),
          ),
        ],
      ),
      botones: [
        BotonNs.primario(context, 'Agregar más', _agregarMas, alto: 60),
        BotonNs.peligroSuave(context, 'Borrar el día', _borrarDia),
      ],
    );
  }

  Widget _pestanaResumen(BuildContext context) {
    final ns = context.ns;
    final resumen = _resumen;
    if (resumen == null) return const SizedBox.shrink();
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        HeroHojaNs(rotulo: 'Vendido ese día', cifra: plataNs(resumen.totalCentavos), apoyo: '${_ventas.length} ${_ventas.length == 1 ? 'venta' : 'ventas'}'),
        FilaClaveValorNs(clave: 'Efectivo', valor: plataNs(resumen.efectivoCentavos)),
        FilaClaveValorNs(clave: 'Mercado Pago', valor: plataNs(resumen.mercadoPagoCentavos)),
        if (resumen.cigarrillosListaCentavos > 0) FilaClaveValorNs(clave: 'Cigarrillos a separar (lista)', valor: plataNs(resumen.cigarrillosListaCentavos)),
        if (resumen.productosSinDatos.isNotEmpty) ...[
          const SizedBox(height: 18),
          const SeccionNs('Vendido sin proveedor o costo'),
          const SizedBox(height: 10),
          const InfoNs('Completalo para tener números más claros.', tono: TonoNs.warn, tamanio: 15, peso: FontWeight.w500),
          const SizedBox(height: 10),
          for (final p in resumen.productosSinDatos) ...[
            FilaProductoNs(nombre: p.nombreProducto, detalle: [if (p.sinProveedor) 'sin proveedor', if (p.sinCosto) 'sin costo'].join(' · '), valor: plataNs(p.vendidoCentavos)),
            const SizedBox(height: 10),
          ],
        ],
        const SizedBox(height: 18),
        const SeccionNs('Por proveedor'),
        const SizedBox(height: 10),
        if (resumen.porProveedor.isEmpty)
          Text('Nada con proveedor y costo cargado todavía.', style: estiloNs(15, color: ns.mute))
        else
          for (final p in resumen.porProveedor) ...[
            FilaProductoNs(nombre: p.nombreProveedor, detalle: 'Vendido ${plataNs(p.vendidoCentavos)} · Ganancia ${plataNs(p.gananciaCentavos)}', valor: plataNs(p.costoRealCentavos)),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _pestanaVentas(BuildContext context) {
    final ns = context.ns;
    if (_ventas.isEmpty) {
      return Align(alignment: Alignment.topCenter, child: Container(width: double.infinity, padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)), child: Text('Sin ventas — "Agregar más" para cargar', style: estiloNs(16, color: ns.mute))));
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _ventas.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final v = _ventas[i];
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
          decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.detalle, maxLines: 3, overflow: TextOverflow.ellipsis, style: estiloNs(17, peso: FontWeight.w500, track: -0.02, altura: 1.2, color: ns.ink)),
                    Text(_medioDeTexto(v.medioResumen), style: estiloNs(13, color: ns.mute)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(plataNs(v.totalCentavos), style: estiloNs(18, peso: FontWeight.w500, track: -0.03, color: ns.ink, tabular: true)),
              const SizedBox(width: 6),
              PresionNs(
                onTap: () => _eliminarVenta(v),
                etiqueta: 'Borrar la venta',
                child: Container(width: 44, height: 44, decoration: BoxDecoration(color: ns.bbg, shape: BoxShape.circle), alignment: Alignment.center, child: IconoNsWidget(IconoNs.papelera, tamanio: 20, color: ns.b)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SeccionProductosSinDatos extends StatelessWidget {
  const SeccionProductosSinDatos({super.key, required this.productos});

  final List<ProductoSinDatosCompanion> productos;

  @override
  Widget build(BuildContext context) {
    if (productos.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        const SeccionNs('Vendido sin proveedor o costo — completalo para números más claros'),
        const SizedBox(height: 10),
        for (final p in productos) ...[
          FilaProductoNs(
            nombre: p.nombreProducto,
            detalle: [if (p.sinProveedor) 'sin proveedor', if (p.sinCosto) 'sin costo'].join(' · '),
            valor: plataNs(p.vendidoCentavos),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// Elegir la fecha y armar un día nuevo de cero (mock 40).
class _PantallaNuevoDiaHistorico extends StatefulWidget {
  const _PantallaNuevoDiaHistorico({required this.cliente, required this.usuarioId});

  final ServicioCompanion cliente;
  final int usuarioId;

  @override
  State<_PantallaNuevoDiaHistorico> createState() => _PantallaNuevoDiaHistoricoState();
}

class _PantallaNuevoDiaHistoricoState extends State<_PantallaNuevoDiaHistorico> {
  DateTime? _fecha;

  /// Solo el día (El dueño, 2026-09-07: "necesito que solo sea el día que se cargue") — sin hora: la carga histórica es
  /// para saber ganancias, no para reconstruir a qué hora se vendió cada cosa. Hasta 5 años atrás.
  Future<void> _elegirFecha() async {
    final ahora = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fecha ?? ahora,
      firstDate: DateTime(ahora.year - 5),
      lastDate: ahora,
      helpText: 'Elegí la fecha',
    );
    if (fecha == null || !mounted) return;
    setState(() => _fecha = DateTime(fecha.year, fecha.month, fecha.day, 12));
  }

  @override
  Widget build(BuildContext context) {
    final fecha = _fecha;
    if (fecha == null) {
      return _PaginaNs(
        titulo: 'Nuevo día histórico',
        cuerpo: ListView(padding: EdgeInsets.zero, children: const [InfoNs('Elegí el día que querés cargar. Después armás las ventas una por una, cada una con su medio de pago.')]),
        botones: [BotonNs.primario(context, 'Elegir la fecha de este día', _elegirFecha, alto: 60)],
      );
    }
    return _AcumuladorDeVentas(
      cliente: widget.cliente,
      titulo: _formatearFecha(fecha),
      textoBoton: 'Guardar día',
      onGuardar: (ventas) => widget.cliente.guardarDiaHistorico(fecha: fecha, usuarioId: widget.usuarioId, ventas: ventas),
    );
  }
}

/// Agregar más ventas a un día que ya existe.
class _PantallaAgregarADiaHistorico extends StatelessWidget {
  const _PantallaAgregarADiaHistorico({required this.cliente, required this.usuarioId, required this.sesionId, required this.fecha});

  final ServicioCompanion cliente;
  final int usuarioId;
  final int sesionId;
  final DateTime fecha;

  @override
  Widget build(BuildContext context) {
    return _AcumuladorDeVentas(
      cliente: cliente,
      titulo: _formatearFecha(fecha),
      textoBoton: 'Agregar al día',
      onGuardar: (ventas) => cliente.agregarVentasADiaHistorico(sesionId: sesionId, usuarioId: usuarioId, ventas: ventas),
    );
  }
}

/// Junta ventas en memoria (buscar → carrito → elegir medio → "Agregar venta", las veces que haga falta) y recién las
/// manda todas juntas con [onGuardar] — comparten esto tanto armar un día de cero como agregarle más a uno que ya existe
/// (Regla 3: un solo lugar para "acumular antes de guardar").
class _AcumuladorDeVentas extends StatefulWidget {
  const _AcumuladorDeVentas({required this.cliente, required this.titulo, required this.textoBoton, required this.onGuardar});

  final ServicioCompanion cliente;
  final String titulo;
  final String textoBoton;
  final Future<void> Function(List<VentaHistoricaPendienteCompanion> ventas) onGuardar;

  @override
  State<_AcumuladorDeVentas> createState() => _AcumuladorDeVentasState();
}

class _AcumuladorDeVentasState extends State<_AcumuladorDeVentas> {
  final List<VentaHistoricaPendienteCompanion> _ventasCargadas = [];
  bool _guardando = false;
  String? _error;

  void _agregarVenta(VentaHistoricaPendienteCompanion venta) => setState(() => _ventasCargadas.add(venta));

  void _quitarVenta(int index) => setState(() => _ventasCargadas.removeAt(index));

  Future<void> _guardar() async {
    if (_ventasCargadas.isEmpty) {
      mostrarAvisoNs(context, 'Agregá al menos una venta');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.onGuardar(_ventasCargadas);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final total = _ventasCargadas.fold<int>(0, (acc, v) => acc + v.totalParaMostrar);
    return _PaginaNs(
      titulo: widget.titulo,
      cuerpo: ListView(
        padding: EdgeInsets.zero,
        children: [
          _ArmadorDeVenta(cliente: widget.cliente, onVentaLista: _agregarVenta),
          if (_ventasCargadas.isNotEmpty) ...[
            const SizedBox(height: 18),
            SeccionNs('${_ventasCargadas.length} ${_ventasCargadas.length == 1 ? 'venta cargada' : 'ventas cargadas'} · ${plataNs(total)}'),
            const SizedBox(height: 10),
            for (var i = 0; i < _ventasCargadas.length; i++) ...[
              Container(
                padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
                decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Venta ${i + 1} — ${plataNs(_ventasCargadas[i].totalParaMostrar)}', style: estiloNs(17, peso: FontWeight.w500, track: -0.02, color: ns.ink)),
                          Text(_medioDeTexto(_ventasCargadas[i].medio), style: estiloNs(13, color: ns.mute)),
                        ],
                      ),
                    ),
                    PresionNs(
                      onTap: () => _quitarVenta(i),
                      etiqueta: 'Quitar la venta',
                      child: Container(width: 44, height: 44, decoration: BoxDecoration(color: ns.paper, shape: BoxShape.circle), alignment: Alignment.center, child: IconoNsWidget(IconoNs.papelera, tamanio: 20, color: ns.b)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
          if (_error != null) ...[const SizedBox(height: 10), InfoNs(_error!, tono: TonoNs.bad)],
        ],
      ),
      botones: [
        BotonNs(
          texto: _guardando ? 'Guardando…' : widget.textoBoton,
          onTap: _guardando ? null : _guardar,
          alto: 60,
          tamanio: 17,
          fondo: _ventasCargadas.isEmpty ? ns.s : ns.prim,
          color: _ventasCargadas.isEmpty ? ns.mute : TokensNs.blanco,
          habilitado: !_guardando,
        ),
      ],
    );
  }
}

/// El armado de UNA venta (mock 40c): buscar (sin exigir stock), agregar al carrito, elegir cómo pagaron, "Agregar venta" —
/// devuelve la venta ya armada por [onVentaLista] y se vacía sola para la próxima.
class _ArmadorDeVenta extends StatefulWidget {
  const _ArmadorDeVenta({required this.cliente, required this.onVentaLista});

  final ServicioCompanion cliente;
  final ValueChanged<VentaHistoricaPendienteCompanion> onVentaLista;

  @override
  State<_ArmadorDeVenta> createState() => _ArmadorDeVentaState();
}

class _ArmadorDeVentaState extends State<_ArmadorDeVenta> {
  final _busquedaCtrl = TextEditingController();
  final _debouncer = Debouncer();
  List<ProductoCompanion> _resultados = [];
  int? _gramosBusqueda;
  bool _buscando = false;

  final List<LineaVenta> _carrito = [];
  _MedioHistorico _medio = _MedioHistorico.efectivo;
  final _montoEfectivoCtrl = TextEditingController();
  String? _error;

  /// Total real (con recargo de cigarrillos y redondeo, Regla 6/5) para el medio elegido: sin esto el botón mostraba
  /// siempre el subtotal crudo (El dueño, 2026-09-07: "revisa que la apk no agrega los recargos automáticos").
  ResultadoTotalVenta? _resultado;
  bool _calculando = false;

  Future<void> _recalcular() async {
    if (_carrito.isEmpty) {
      setState(() => _resultado = null);
      return;
    }
    setState(() => _calculando = true);
    try {
      final resultado = await widget.cliente.calcularVenta(lineas: _carrito, medio: _medio.texto);
      if (mounted) setState(() => _resultado = resultado);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _calculando = false);
    }
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    _montoEfectivoCtrl.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  Future<void> _buscar(String texto) async {
    if (texto.trim().isEmpty) {
      setState(() {
        _resultados = [];
        _gramosBusqueda = null;
      });
      return;
    }
    setState(() => _buscando = true);
    try {
      final resultado = await widget.cliente.buscarVenta(texto, exigirStock: false);
      // Descarta una respuesta que ya no corresponde al texto actual: otra, más nueva, pudo llegar antes por el jitter del WiFi.
      if (mounted && _busquedaCtrl.text == texto) {
        setState(() {
          _resultados = resultado.resultados;
          _gramosBusqueda = resultado.gramos;
        });
      }
    } finally {
      if (mounted && _busquedaCtrl.text == texto) setState(() => _buscando = false);
    }
  }

  void _agregarAlCarrito(ProductoCompanion producto) {
    final resultado = lineaDesdeResultadoBusqueda(producto, gramos: _gramosBusqueda);
    if (resultado.error != null) {
      mostrarAvisoNs(context, resultado.error!, largo: true);
      return;
    }
    final nueva = resultado.linea!;
    setState(() {
      final i = _carrito.indexWhere((l) => l.productoId == nueva.productoId);
      if (i != -1) {
        _carrito[i] = sumarLineasVenta(_carrito[i], nueva);
      } else {
        _carrito.add(nueva);
      }
      _busquedaCtrl.clear();
      _resultados = [];
      _gramosBusqueda = null;
    });
    _recalcular();
  }

  LineaVenta _conValor(LineaVenta l, int valor) {
    if (l is LineaVentaPesable) {
      return LineaVentaPesable(productoId: l.productoId, nombreProducto: l.nombreProducto, proveedorId: l.proveedorId, gramos: valor, precioPorKiloCentavos: l.precioPorKiloCentavos, costoPorKiloCentavos: l.costoPorKiloCentavos);
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

  /// − / + de una línea: 1 unidad, o 50 g si es por peso; por debajo de 1 la saca.
  void _ajustar(int i, int signo) {
    final l = _carrito[i];
    final actual = l is LineaVentaPesable ? l.gramos : (l as LineaVentaPorUnidad).cantidad;
    final nuevo = actual + (l is LineaVentaPesable ? 50 : 1) * signo;
    setState(() {
      if (nuevo <= 0) {
        _carrito.removeAt(i);
      } else {
        _carrito[i] = _conValor(l, nuevo);
      }
    });
    _recalcular();
  }

  /// Un "mixto" con el efectivo en $0 es virtual puro (no debería redondear, Regla 2) y con el efectivo igual al total es
  /// efectivo puro (no debería llevar recargo de cigarrillos, Regla 6): se reclasifica con `clasificarComposicion` del
  /// dominio antes de mandar nada, igual que en el escritorio (`VentaControlador.confirmarMixto`).
  Future<void> _confirmarVenta() async {
    if (_carrito.isEmpty) return;
    int? montoEfectivo;
    var medioTexto = _medio.texto;
    var resultado = _resultado;
    if (_medio == _MedioHistorico.mixto) {
      try {
        montoEfectivo = parsearARS(_montoEfectivoCtrl.text);
      } on FormatException {
        setState(() => _error = 'Monto en efectivo inválido');
        return;
      }
      final techo = resultado?.totalCentavos ?? Venta(lineas: _carrito).subtotalCentavos;
      final real = clasificarComposicion(montoEfectivoCentavos: montoEfectivo, totalCentavos: techo);
      medioTexto = real.name; // 'efectivo' | 'virtual' | 'mixto'
      if (real != ComposicionPago.mixto) {
        montoEfectivo = null;
        setState(() => _calculando = true);
        try {
          resultado = await widget.cliente.calcularVenta(lineas: _carrito, medio: medioTexto);
        } catch (e) {
          if (mounted) setState(() => _error = mensajeDeError(e));
          return;
        } finally {
          if (mounted) setState(() => _calculando = false);
        }
      }
    }
    widget.onVentaLista(
      VentaHistoricaPendienteCompanion(lineas: List.of(_carrito), medio: medioTexto, montoEfectivoMixtoCentavos: montoEfectivo, totalCentavos: resultado?.totalCentavos),
    );
    setState(() {
      _carrito.clear();
      _medio = _MedioHistorico.efectivo;
      _montoEfectivoCtrl.clear();
      _error = null;
      _resultado = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final subtotal = Venta(lineas: _carrito).subtotalCentavos;
    final total = _resultado?.totalCentavos ?? subtotal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CampoNs(
          etiqueta: 'Buscar producto vendido ese día',
          controller: _busquedaCtrl,
          placeholder: 'Buscar producto',
          grande: false,
          onChanged: (texto) {
            setState(() {});
            if (texto.trim().isEmpty) {
              _debouncer.cancelar();
              _buscar(texto);
            } else {
              _debouncer.ejecutar(() => _buscar(texto));
            }
          },
        ),
        const SizedBox(height: 10),
        if (_busquedaCtrl.text.trim().isNotEmpty)
          if (_resultados.isEmpty && !_buscando)
            Container(width: double.infinity, padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)), child: Text('Sin resultados', style: estiloNs(16, color: ns.mute)))
          else
            for (final p in _resultados.take(8)) ...[
              FilaProductoNs(nombre: p.nombre, valor: p.esPesable ? '${plataNs(p.precioPorKiloCentavos ?? 0)}/kg' : plataNs(p.precioCentavos ?? 0), onTap: () => _agregarAlCarrito(p)),
              const SizedBox(height: 8),
            ]
        else ...[
          if (_carrito.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8), child: Text('Buscá y tocá los productos de esta venta', style: estiloNs(15, color: ns.mute)))
          else
            for (var i = 0; i < _carrito.length; i++) ...[
              Container(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(26)),
                child: Row(
                  children: [
                    Expanded(child: Text(_carrito[i].nombreProducto, maxLines: 2, overflow: TextOverflow.ellipsis, style: estiloNs(17, peso: FontWeight.w500, track: -0.02, altura: 1.2, color: ns.ink))),
                    const SizedBox(width: 8),
                    StepperNs(cantidad: _carrito[i] is LineaVentaPesable ? '${(_carrito[i] as LineaVentaPesable).gramos} g' : '${(_carrito[i] as LineaVentaPorUnidad).cantidad}', onMenos: () => _ajustar(i, -1), onMas: () => _ajustar(i, 1)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 6),
          Text('Cómo pagaron', style: estiloNs(15, peso: FontWeight.w500, color: ns.mute)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in _MedioHistorico.values)
                ChipNs(
                  texto: m.etiqueta,
                  activo: _medio == m,
                  onTap: () {
                    setState(() => _medio = m);
                    _recalcular();
                  },
                ),
            ],
          ),
          if (_medio == _MedioHistorico.mixto) ...[
            const SizedBox(height: 10),
            CampoNs(etiqueta: 'Monto en efectivo', controller: _montoEfectivoCtrl, placeholder: '\$ 0', teclado: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() => _error = null)),
          ],
          if (_error != null) ...[const SizedBox(height: 10), InfoNs(_error!, tono: TonoNs.bad)],
          const SizedBox(height: 10),
          BotonNs(
            texto: _calculando ? 'Calculando…' : 'Agregar venta — ${plataNs(total)}',
            onTap: _carrito.isEmpty || _calculando ? null : _confirmarVenta,
            alto: 56,
            tamanio: 17,
            fondo: _carrito.isEmpty ? ns.s : ns.prim,
            color: _carrito.isEmpty ? ns.mute : TokensNs.blanco,
            habilitado: _carrito.isNotEmpty && !_calculando,
          ),
        ],
      ],
    );
  }
}

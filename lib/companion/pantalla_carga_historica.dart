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
import '../ui/comun/campo_texto.dart';
import '../ui/tema/tokens.dart';
import 'base_local.dart';
import 'carrito_venta.dart';
import 'cliente_companion.dart';
import 'debounce.dart';
import 'emparejamiento.dart';
import 'fila_linea_carrito.dart';
import 'mensaje_error.dart';
import 'navegacion.dart';
import 'puerto_local.dart';
import 'seleccion_servicio.dart';
import 'servicio_companion.dart';
import 'servicio_companion_offline.dart';
import 'tema/chip_icono.dart';
import '../ui/comun/estado_vacio.dart';
import 'tema/hoja_vidrio.dart';
import 'tema/presionable.dart';
import 'tema/superficie.dart';
import '../ui/tema/iconos.dart';
import 'tema/error_en_linea.dart';

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

/// El hub: lista los días ya cargados, "+ Nuevo día" para arrancar uno.
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
    final cliente = conexion == null
        ? ServicioCompanionOffline(PuertoLocal(baseLocalCompanion()))
        : await resolverServicioCompanion(conexion);
    if (!mounted) return;
    setState(() {
      _cliente = cliente;
      _usuarioId = usuario.id;
    });
    await _cargarDias();
  }

  Future<void> _cargarDias() async {
    if (_cliente == null) return;
    setState(() => _cargando = true);
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
    await pushSinTeclado(
      context,
      (_) => _PantallaNuevoDiaHistorico(
        cliente: _cliente!,
        usuarioId: _usuarioId!,
      ),
    );
    await _cargarDias();
  }

  Future<void> _abrirDia(DiaHistoricoCompanion dia) async {
    await pushSinTeclado(
      context,
      (_) => _PantallaDetalleDiaHistorico(
        cliente: _cliente!,
        usuarioId: _usuarioId!,
        sesionId: dia.sesionId,
        fecha: dia.fecha,
      ),
    );
    await _cargarDias();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Días históricos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _cliente == null ? null : _nuevoDia,
        icon: const Icon(IconosPlazoleta.add),
        label: const Text('Nuevo día'),
      ),
      body: SafeArea(
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: ErrorEnLinea(_error!),
              )
            : _dias.isEmpty
            ? const EstadoVacio(
                mensaje: 'Todavía no cargaste ningún día — tocá "Nuevo día"',
                icono: IconosPlazoleta.history,
              )
            : ListView.builder(
                padding: const EdgeInsets.all(Espaciado.lg),
                itemCount: _dias.length,
                itemBuilder: (context, i) {
                  final d = _dias[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: Espaciado.sm),
                    child: Superficie(
                      padding: EdgeInsets.zero,
                      child: Presionable(
                        onTap: () => _abrirDia(d),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Espaciado.lg,
                            vertical: Espaciado.md,
                          ),
                          child: Row(
                            children: [
                              ChipIcono(icono: IconosPlazoleta.eventOutlined, color: context.colores.acento),
                              const SizedBox(width: Espaciado.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _formatearFecha(d.fecha),
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                    Text(
                                      '${d.cantidadVentas} venta(s)',
                                      style: TextStyle(color: context.colores.textoSecundario),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                formatearARS(d.totalCentavos),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

/// El detalle de un día ya cargado: sus ventas, con eliminar puntual,
/// agregar más, o borrar el día entero.
class _PantallaDetalleDiaHistorico extends StatefulWidget {
  const _PantallaDetalleDiaHistorico({
    required this.cliente,
    required this.usuarioId,
    required this.sesionId,
    required this.fecha,
  });

  final ServicioCompanion cliente;
  final int usuarioId;
  final int sesionId;
  final DateTime fecha;

  @override
  State<_PantallaDetalleDiaHistorico> createState() =>
      _PantallaDetalleDiaHistoricoState();
}

class _PantallaDetalleDiaHistoricoState
    extends State<_PantallaDetalleDiaHistorico> {
  List<VentaHistoricaResumenCompanion> _ventas = [];
  ResumenDiaHistoricoCompanion? _resumen;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final resultados = await Future.wait([
        widget.cliente.ventasDeDiaHistorico(widget.sesionId),
        widget.cliente.resumenDiaHistorico(widget.sesionId),
      ]);
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
    // Antes borraba directo con un solo toque — una fila en una lista larga
    // es más fácil de tocar por error que el botón de "Borrar día completo"
    // (que sí tenía confirmación), así que la acción más chica quedaba con
    // MENOS protección que la más grande.
    final confirmar = await confirmarAccionDestructiva(
      context,
      titulo: 'Borrar esta venta',
      contenido: formatearARS(venta.totalCentavos),
    );
    if (!confirmar) return;
    try {
      await widget.cliente.eliminarVentaHistorica(
        sesionId: widget.sesionId,
        ventaId: venta.ventaId,
        usuarioId: widget.usuarioId,
      );
      await _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo borrar: ${mensajeDeError(e)}')),
        );
      }
    }
  }

  Future<void> _agregarMas() async {
    await pushSinTeclado(
      context,
      (_) => _PantallaAgregarADiaHistorico(
        cliente: widget.cliente,
        usuarioId: widget.usuarioId,
        sesionId: widget.sesionId,
        fecha: widget.fecha,
      ),
    );
    await _cargar();
  }

  Future<void> _borrarDia() async {
    final confirmar = await confirmarAccionDestructiva(
      context,
      titulo: 'Borrar día completo',
      contenido: 'Se borran las ${_ventas.length} venta(s) de ${_formatearFecha(widget.fecha)}.',
    );
    if (!confirmar) return;
    try {
      await widget.cliente.eliminarDiaHistorico(widget.sesionId);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo borrar: ${mensajeDeError(e)}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      // Arranca en "Resumen" (El dueño, 2026-09-07: "hay que scrollear
      // demasiado... sobre todo que ordenemos y resumamos todo") — antes
      // esta pantalla era directo la lista de ventas una por una, y para
      // saber "cuánto vendí" o "cuánto separo de tal proveedor" había que
      // sumarlas a ojo. "Ventas" (para editar/borrar una puntual) queda
      // en la segunda pestaña, no es lo primero que hace falta ver.
      child: Scaffold(
        appBar: AppBar(
          title: Text(_formatearFecha(widget.fecha)),
          actions: [
            IconButton(
              tooltip: 'Borrar el día',
              icon: const Icon(IconosPlazoleta.deleteOutline),
              onPressed: _borrarDia,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Resumen'),
              Tab(text: 'Ventas'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _agregarMas,
          icon: const Icon(IconosPlazoleta.add),
          label: const Text('Agregar más'),
        ),
        body: SafeArea(
          child: _cargando
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: ErrorEnLinea(_error!),
                )
              : TabBarView(
                  children: [_pestanaResumen(context), _pestanaVentas(context)],
                ),
        ),
      ),
    );
  }

  Widget _pestanaResumen(BuildContext context) {
    final resumen = _resumen;
    if (resumen == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Espaciado.lg,
        Espaciado.lg,
        Espaciado.lg,
        80,
      ),
      children: [
        Superficie(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                formatearARS(resumen.totalCentavos),
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              Text(
                '${_ventas.length} venta(s)',
                style: TextStyle(color: context.colores.textoSecundario),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Espaciado.md),
              FilaDatoSimple(
                'Efectivo',
                formatearARS(resumen.efectivoCentavos),
              ),
              FilaDatoSimple(
                'Mercado Pago',
                formatearARS(resumen.mercadoPagoCentavos),
              ),
              if (resumen.cigarrillosListaCentavos > 0)
                FilaDatoSimple(
                  'Cigarrillos a separar (lista)',
                  formatearARS(resumen.cigarrillosListaCentavos),
                ),
            ],
          ),
        ),
        SeccionProductosSinDatos(productos: resumen.productosSinDatos),
        const SizedBox(height: Espaciado.lg),
        Text('Por proveedor', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: Espaciado.sm),
        if (resumen.porProveedor.isEmpty)
          Text(
            'Nada con proveedor y costo cargado todavía.',
            style: TextStyle(color: context.colores.textoSecundario),
          )
        else
          for (final p in resumen.porProveedor)
            Padding(
              padding: const EdgeInsets.only(bottom: Espaciado.sm),
              child: Superficie(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      p.nombreProveedor,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: Espaciado.xs),
                    FilaDatoSimple('Vendido', formatearARS(p.vendidoCentavos)),
                    FilaDatoSimple(
                      'Separar (costo real)',
                      formatearARS(p.costoRealCentavos),
                    ),
                    FilaDatoSimple(
                      'Ganancia',
                      formatearARS(p.gananciaCentavos),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Widget _pestanaVentas(BuildContext context) {
    if (_ventas.isEmpty) {
      return const EstadoVacio(
        mensaje: 'Sin ventas — "Agregar más" para cargar',
        icono: IconosPlazoleta.receiptLongOutlined,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        Espaciado.lg,
        Espaciado.lg,
        Espaciado.lg,
        80,
      ),
      itemCount: _ventas.length,
      itemBuilder: (context, i) {
        final v = _ventas[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: Espaciado.sm),
          child: Superficie(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        v.detalle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        _medioDeTexto(v.medioResumen),
                        style: TextStyle(
                          color: context.colores.textoSecundario,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(formatearARS(v.totalCentavos)),
                IconButton(
                  tooltip: 'Eliminar la venta',
                  icon: const Icon(IconosPlazoleta.deleteOutline),
                  onPressed: () => _eliminarVenta(v),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Etiqueta a la izquierda, valor a la derecha — mismo patrón que
/// `FilaDato` del kit de escritorio (`lib/ui/comun/`), pero sin depender
/// de él para no acoplar la companion al kit de escritorio por una fila
/// tan chica.
class FilaDatoSimple extends StatelessWidget {
  const FilaDatoSimple(this.etiqueta, this.valor, {super.key});
  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            etiqueta,
            style: TextStyle(color: context.colores.textoSecundario),
          ),
          Text(valor, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// "Vendido sin proveedor o costo", producto por producto (El dueño,
/// 2026-09-07: "de lo vendido decime que no tiene costo o proveedor, así
/// le asignamos uno") — compartida por el resumen de un día histórico y
/// el arqueo en vivo (Regla 3, mismo dato: `ResumenDiaHistoricoCompanion.
/// productosSinDatos`).
class SeccionProductosSinDatos extends StatelessWidget {
  const SeccionProductosSinDatos({super.key, required this.productos});

  final List<ProductoSinDatosCompanion> productos;

  @override
  Widget build(BuildContext context) {
    if (productos.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Espaciado.lg),
        Text(
          'Vendido sin proveedor o costo — completalo para números más claros',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: Espaciado.sm),
        for (final p in productos)
          Padding(
            padding: const EdgeInsets.only(bottom: Espaciado.sm),
            child: Superficie(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.nombreProducto,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          [
                            if (p.sinProveedor) 'sin proveedor',
                            if (p.sinCosto) 'sin costo',
                          ].join(' · '),
                          style: TextStyle(
                            color: context.colores.textoSecundario,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(formatearARS(p.vendidoCentavos)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Elegir la fecha y armar un día nuevo de cero.
class _PantallaNuevoDiaHistorico extends StatefulWidget {
  const _PantallaNuevoDiaHistorico({
    required this.cliente,
    required this.usuarioId,
  });

  final ServicioCompanion cliente;
  final int usuarioId;

  @override
  State<_PantallaNuevoDiaHistorico> createState() =>
      _PantallaNuevoDiaHistoricoState();
}

class _PantallaNuevoDiaHistoricoState
    extends State<_PantallaNuevoDiaHistorico> {
  DateTime? _fecha;

  /// Solo el día (El dueño, 2026-09-07: "necesito que solo sea el día que se
  /// cargue") — sin hora: la carga histórica es para saber ganancias, no
  /// para reconstruir a qué hora se vendió cada cosa.
  Future<void> _elegirFecha() async {
    final ahora = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fecha ?? ahora,
      firstDate: DateTime(ahora.year - 5),
      lastDate: ahora,
    );
    if (fecha == null || !mounted) return;
    setState(() => _fecha = DateTime(fecha.year, fecha.month, fecha.day, 12));
  }

  @override
  Widget build(BuildContext context) {
    final fecha = _fecha;
    if (fecha == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nuevo día histórico')),
        body: SafeArea(
          child: Center(
            child: FilledButton(
              onPressed: _elegirFecha,
              child: const Text('Elegir la fecha de este día'),
            ),
          ),
        ),
      );
    }
    return _AcumuladorDeVentas(
      cliente: widget.cliente,
      titulo: _formatearFecha(fecha),
      textoBoton: 'Guardar día',
      onGuardar: (ventas) => widget.cliente.guardarDiaHistorico(
        fecha: fecha,
        usuarioId: widget.usuarioId,
        ventas: ventas,
      ),
    );
  }
}

/// Agregar más ventas a un día que ya existe.
class _PantallaAgregarADiaHistorico extends StatelessWidget {
  const _PantallaAgregarADiaHistorico({
    required this.cliente,
    required this.usuarioId,
    required this.sesionId,
    required this.fecha,
  });

  final ServicioCompanion cliente;
  final int usuarioId;
  final int sesionId;
  final DateTime fecha;

  @override
  Widget build(BuildContext context) {
    return _AcumuladorDeVentas(
      cliente: cliente,
      titulo: 'Agregar a ${_formatearFecha(fecha)}',
      textoBoton: 'Agregar',
      onGuardar: (ventas) => cliente.agregarVentasADiaHistorico(
        sesionId: sesionId,
        usuarioId: usuarioId,
        ventas: ventas,
      ),
    );
  }
}

/// Junta ventas en memoria (buscar → carrito → elegir medio → "Agregar
/// venta", las veces que haga falta) y recién las manda todas juntas con
/// [onGuardar] — comparten esto tanto armar un día de cero como agregarle
/// más a uno que ya existe (Regla 3: un solo lugar para "acumular antes de
/// guardar").
class _AcumuladorDeVentas extends StatefulWidget {
  const _AcumuladorDeVentas({
    required this.cliente,
    required this.titulo,
    required this.textoBoton,
    required this.onGuardar,
  });

  final ServicioCompanion cliente;
  final String titulo;
  final String textoBoton;
  final Future<void> Function(List<VentaHistoricaPendienteCompanion> ventas)
  onGuardar;

  @override
  State<_AcumuladorDeVentas> createState() => _AcumuladorDeVentasState();
}

class _AcumuladorDeVentasState extends State<_AcumuladorDeVentas> {
  final List<VentaHistoricaPendienteCompanion> _ventasCargadas = [];
  bool _guardando = false;
  String? _error;

  void _agregarVenta(VentaHistoricaPendienteCompanion venta) {
    setState(() => _ventasCargadas.add(venta));
  }

  void _quitarVenta(int index) {
    setState(() => _ventasCargadas.removeAt(index));
    Navigator.of(
      context,
    ).pop(); // vuelve del diálogo de detalle a ver la lista actualizada
    _mostrarVentasCargadas(context);
  }

  /// El dueño, 2026-09-07: "en las ventas históricas no me gusta que aparezca
  /// abajo las ventas por agregar" — la tira de tarjetas siempre visible
  /// se reemplazó por esta barra compacta (mismo patrón que la del
  /// carrito del menú principal); el detalle con el tacho para borrar una
  /// puntual queda a un toque, no ocupando la pantalla todo el tiempo.
  Future<void> _mostrarVentasCargadas(BuildContext context) async {
    if (_ventasCargadas.isEmpty) return;
    await mostrarHojaVidrio<void>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Ventas cargadas', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: Espaciado.sm),
          SizedBox(
            height: 320,
            child: ListView.builder(
              itemCount: _ventasCargadas.length,
              itemBuilder: (context, i) {
                final v = _ventasCargadas[i];
                return ListTile(
                  title: Text(
                    'Venta ${i + 1} — ${formatearARS(v.totalParaMostrar)}',
                  ),
                  subtitle: Text(_medioDeTexto(v.medio)),
                  trailing: IconButton(
                    tooltip: 'Quitar la venta',
                    icon: const Icon(IconosPlazoleta.deleteOutline),
                    onPressed: () => _quitarVenta(i),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: Espaciado.md),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _guardar() async {
    if (_ventasCargadas.isEmpty) return;
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo),
        // Separado a propósito de "Agregar venta" (El dueño, 2026-09-07: "el
        // botón de guardar para cerrar el día se confunde muy fácil e
        // invita a apretarlo para guardar las ventas, y termino teniendo
        // que volver a abrirlo") — antes los dos botones quedaban pegados
        // y se parecían; acá arriba queda claro que termina todo el día,
        // no una venta más.
        actions: [
          // Sin color a mano en ninguno de los dos (El dueño, 2026-09-13: "hay
          // algo más sin el lenguaje?") — `Colors.white` acá era invisible
          // en tema claro: este AppBar no tiene fondo propio, hereda el
          // fondo normal de la app (claro en horario de local abierto), no
          // uno oscuro como para justificar texto blanco a mano. Sin
          // `color`, el `TextButton` ya trae el color correcto para los dos
          // temas solo.
          TextButton(
            onPressed: _ventasCargadas.isEmpty || _guardando ? null : _guardar,
            child: _guardando
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.textoBoton),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(Espaciado.md),
                child: ErrorEnLinea(_error!),
              ),
            Expanded(
              child: _ArmadorDeVenta(
                cliente: widget.cliente,
                onVentaLista: _agregarVenta,
              ),
            ),
            if (_ventasCargadas.isNotEmpty) _barraVentasCargadas(context),
          ],
        ),
      ),
    );
  }

  Widget _barraVentasCargadas(BuildContext context) {
    final total = _ventasCargadas.fold<int>(
      0,
      (acc, v) => acc + v.totalParaMostrar,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: context.colores.textoSecundario.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: InkWell(
        onTap: () => _mostrarVentasCargadas(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Espaciado.lg,
            vertical: Espaciado.md,
          ),
          child: Row(
            children: [
              Text(
                '${_ventasCargadas.length} venta(s)',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Spacer(),
              Text(
                formatearARS(total),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(width: Espaciado.sm),
              Icon(
                IconosPlazoleta.receiptLongOutlined,
                color: context.colores.textoSecundario,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El armado de UNA venta: buscar (sin exigir stock), agregar al carrito,
/// elegir medio, "Agregar venta" — devuelve la venta ya armada por
/// [onVentaLista] y se vacía sola para la próxima.
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

  /// Total real (con recargo de cigarrillos y redondeo, Regla 6/5) para el
  /// medio elegido — sin esto el botón mostraba siempre el subtotal crudo,
  /// sin importar el medio, y parecía que el recargo nunca se aplicaba
  /// (El dueño, 2026-09-07: "revisa que la apk no agrega los recargos
  /// automáticos" — el cálculo real ya estaba bien, lo que faltaba era
  /// mostrarlo acá antes de confirmar).
  ResultadoTotalVenta? _resultado;
  bool _calculando = false;

  Future<void> _recalcular() async {
    if (_carrito.isEmpty) {
      setState(() => _resultado = null);
      return;
    }
    setState(() => _calculando = true);
    try {
      final resultado = await widget.cliente.calcularVenta(
        lineas: _carrito,
        medio: _medio.texto,
      );
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
      final resultado = await widget.cliente.buscarVenta(
        texto,
        exigirStock: false,
      );
      // Descarta una respuesta que ya no corresponde al texto actual —
      // otra, más nueva, pudo llegar antes por el jitter normal de WiFi.
      if (mounted && _busquedaCtrl.text == texto) {
        setState(() {
          _resultados = resultado.resultados;
          _gramosBusqueda = resultado.gramos;
        });
      }
    } finally {
      if (mounted && _busquedaCtrl.text == texto) {
        setState(() => _buscando = false);
      }
    }
  }

  void _agregarAlCarrito(ProductoCompanion producto) {
    final resultado = lineaDesdeResultadoBusqueda(
      producto,
      gramos: _gramosBusqueda,
    );
    if (resultado.error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(resultado.error!)));
      return;
    }
    final nueva = resultado.linea!;
    setState(() {
      final indiceExistente = _carrito.indexWhere(
        (l) => l.productoId == nueva.productoId,
      );
      if (indiceExistente != -1) {
        _carrito[indiceExistente] = sumarLineasVenta(
          _carrito[indiceExistente],
          nueva,
        );
      } else {
        _carrito.add(nueva);
      }
      _busquedaCtrl.clear();
      _resultados = [];
      _gramosBusqueda = null;
    });
    _recalcular();
  }

  /// Bug real, encontrado revisando que el recargo se aplique bien en las
  /// dos apps (El dueño, 2026-09-08): esta pantalla mandaba `_medio.texto`
  /// literal ("mixto" si se apretó Mixto) sin importar el monto que se
  /// terminaba tipeando — mismo error que ya se había encontrado y
  /// arreglado en el escritorio (`VentaControlador.confirmarMixto`,
  /// `DECISIONES.md`): un "mixto" con el efectivo en $0 es virtual puro
  /// (no debería redondear, Regla 2) y un "mixto" con el efectivo igual al
  /// total es efectivo puro (no debería llevar recargo de cigarrillos,
  /// Regla 6) — mandar "mixto" tal cual en cualquiera de los dos casos
  /// cobraba de más. Ahora reclasifica con la misma `clasificarComposicion`
  /// del dominio antes de mandar nada, y si dejó de ser mixto de verdad
  /// vuelve a pedir el total con el medio correcto (el recargo/redondeo
  /// cambia según cuál sea).
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
      final techo =
          resultado?.totalCentavos ?? Venta(lineas: _carrito).subtotalCentavos;
      final real = clasificarComposicion(
        montoEfectivoCentavos: montoEfectivo,
        totalCentavos: techo,
      );
      medioTexto = real.name; // 'efectivo' | 'virtual' | 'mixto'
      if (real != ComposicionPago.mixto) {
        montoEfectivo = null;
        setState(() => _calculando = true);
        try {
          resultado = await widget.cliente.calcularVenta(
            lineas: _carrito,
            medio: medioTexto,
          );
        } catch (e) {
          if (mounted) setState(() => _error = mensajeDeError(e));
          return;
        } finally {
          if (mounted) setState(() => _calculando = false);
        }
      }
    }
    widget.onVentaLista(
      VentaHistoricaPendienteCompanion(
        lineas: List.of(_carrito),
        medio: medioTexto,
        montoEfectivoMixtoCentavos: montoEfectivo,
        totalCentavos: resultado?.totalCentavos,
      ),
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
    final subtotal = Venta(lineas: _carrito).subtotalCentavos;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Espaciado.lg,
            Espaciado.lg,
            Espaciado.lg,
            0,
          ),
          child: Superficie(
            child: CampoTexto(
              controller: _busquedaCtrl,
              etiqueta: 'Buscar producto vendido ese día',
              prefixIcon: const Icon(IconosPlazoleta.search),
              suffixIcon: _buscando
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
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
          ),
        ),
        if (_busquedaCtrl.text.trim().isNotEmpty)
          Expanded(child: _listaResultados(context))
        else ...[
          Expanded(child: _listaCarrito(context)),
          _panelVenta(context, subtotal),
        ],
      ],
    );
  }

  Widget _listaResultados(BuildContext context) {
    if (_resultados.isEmpty && !_buscando) {
      return const EstadoVacio(
        mensaje: 'Sin resultados',
        icono: IconosPlazoleta.searchOff,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(Espaciado.lg),
      itemCount: _resultados.length,
      itemBuilder: (context, i) {
        final p = _resultados[i];
        final precioTexto = p.esPesable
            ? '${formatearARS(p.precioPorKiloCentavos ?? 0)}/kg'
            : formatearARS(p.precioCentavos ?? 0);
        return Padding(
          padding: const EdgeInsets.only(bottom: Espaciado.sm),
          child: Superficie(
            padding: EdgeInsets.zero,
            child: Presionable(
              onTap: () => _agregarAlCarrito(p),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Espaciado.lg,
                  vertical: Espaciado.md,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(p.nombre, style: Theme.of(context).textTheme.titleMedium),
                    ),
                    Text(precioTexto, style: TextStyle(color: context.colores.textoSecundario)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _listaCarrito(BuildContext context) {
    if (_carrito.isEmpty) {
      return Center(
        child: Text(
          'Buscá y tocá los productos de esta venta',
          style: TextStyle(color: context.colores.textoSecundario),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        Espaciado.lg,
        Espaciado.sm,
        Espaciado.lg,
        Espaciado.sm,
      ),
      itemCount: _carrito.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: Espaciado.xs),
        child: FilaLineaCarrito(
          linea: _carrito[i],
          onCambiar: (nueva) {
            setState(() => _carrito[i] = nueva);
            _recalcular();
          },
          onEliminar: () {
            setState(() => _carrito.removeAt(i));
            _recalcular();
          },
        ),
      ),
    );
  }

  Widget _panelVenta(BuildContext context, int subtotal) {
    final total = _resultado?.totalCentavos ?? subtotal;
    return Padding(
      padding: const EdgeInsets.all(Espaciado.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            ErrorEnLinea(_error!),
            const SizedBox(height: Espaciado.sm),
          ],
          SegmentedButton<_MedioHistorico>(
            segments: [
              for (final m in _MedioHistorico.values)
                ButtonSegment(value: m, label: Text(m.etiqueta)),
            ],
            selected: {_medio},
            onSelectionChanged: (s) {
              setState(() => _medio = s.first);
              _recalcular();
            },
          ),
          if (_medio == _MedioHistorico.mixto) ...[
            const SizedBox(height: Espaciado.sm),
            Superficie(
              child: CampoPlata(
                controller: _montoEfectivoCtrl,
                etiqueta: 'Monto en efectivo',
              ),
            ),
          ],
          const SizedBox(height: Espaciado.md),
          FilledButton(
            onPressed: _carrito.isEmpty || _calculando ? null : _confirmarVenta,
            child: _calculando
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('Agregar venta — ${formatearARS(total)}'),
          ),
        ],
      ),
    );
  }
}

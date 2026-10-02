// Historial de ventas, filtrable — "tipo Mercado Pago" (El dueño,
// 2026-09-07: "hagamos la sección de reportes para móvil con el
// historial de ventas... que sea filtrable... digamos que quiero que
// también sirva para un control manual en caso de desconfiar de los
// números"). Separar/retener/retirar sigue siendo pantalla exclusiva del
// escritorio ("Reportes").
//
// Eliminar una venta (El dueño, 2026-09-13) se agregó acá: solo mientras la
// sesión de caja de esa venta siga abierta (`v.sesionAbierta`, calculado
// del lado del servidor — anular una venta de un cierre ya arqueado
// descuadraría ese arqueo). Revierte stock y caja (misma lógica que editar
// en escritorio, `anularVenta`), pero nunca borra la venta — queda
// marcada, para no perder el rastro (Regla 6).

import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/dinero.dart';
import '../ui/tema/tokens.dart';
import 'cambios_companion.dart';
import 'base_local.dart';
import 'cliente_companion.dart';
import 'emparejamiento.dart';
import 'mensaje_error.dart';
import 'navbar_companion.dart';
import 'pantalla_cierres.dart';
import 'puerto_local.dart';
import 'seleccion_servicio.dart';
import 'servicio_companion.dart';
import 'servicio_companion_offline.dart';
import 'tema/piezas_companion.dart';
import 'tema/tema_companion.dart';
import 'tema/hoja_vidrio.dart';
import 'tema/esqueleto_companion.dart';
import 'tema/estado_error_companion.dart';
import 'tema/estado_vacio_companion.dart';
import 'tema/presionable.dart';
import 'tema/superficie.dart';
import '../ui/tema/iconos.dart';
import 'tema/error_en_linea.dart';

enum _Periodo { hoy, ayer, ultimaSemana, esteMes }

extension on _Periodo {
  String get etiqueta => switch (this) {
    _Periodo.hoy => 'Hoy',
    _Periodo.ayer => 'Ayer',
    _Periodo.ultimaSemana => 'Últimos 7 días',
    _Periodo.esteMes => 'Este mes',
  };

  ({DateTime desde, DateTime hasta}) rango() {
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    return switch (this) {
      _Periodo.hoy => (desde: hoy, hasta: hoy.add(const Duration(days: 1))),
      _Periodo.ayer => (
        desde: hoy.subtract(const Duration(days: 1)),
        hasta: hoy,
      ),
      _Periodo.ultimaSemana => (
        desde: hoy.subtract(const Duration(days: 6)),
        hasta: hoy.add(const Duration(days: 1)),
      ),
      _Periodo.esteMes => (
        desde: DateTime(ahora.year, ahora.month, 1),
        hasta: hoy.add(const Duration(days: 1)),
      ),
    };
  }
}

extension on MedioVentaHistorialCompanion {
  String get etiqueta => switch (this) {
    MedioVentaHistorialCompanion.efectivo => 'Efectivo',
    MedioVentaHistorialCompanion.qr => 'QR',
    MedioVentaHistorialCompanion.debitCard => 'Débito',
    MedioVentaHistorialCompanion.mixto => 'Mixto',
  };

  IconData get icono => switch (this) {
    MedioVentaHistorialCompanion.efectivo => IconosPlazoleta.paymentsOutlined,
    MedioVentaHistorialCompanion.qr => IconosPlazoleta.qrCode,
    MedioVentaHistorialCompanion.debitCard => IconosPlazoleta.creditCard,
    MedioVentaHistorialCompanion.mixto => IconosPlazoleta.callSplit,
  };
}

class PantallaHistorialVentas extends StatefulWidget {
  const PantallaHistorialVentas({super.key});

  @override
  State<PantallaHistorialVentas> createState() =>
      _PantallaHistorialVentasState();
}

class _PantallaHistorialVentasState extends State<PantallaHistorialVentas> {
  ServicioCompanion? _cliente;
  int? _usuarioId;
  _Periodo _periodo = _Periodo.hoy;
  MedioVentaHistorialCompanion? _filtroMedio;
  List<VentaDelHistorialCompanion> _ventas = [];
  bool _cargando = true;
  String? _error;

  /// El dueño, 2026-09-18: "no hay nada que actualice la app cuando se
  /// sincronizó" — repite la carga sola apenas la sync trae algo nuevo.
  /// El dueño, 2026-09-19: "las pantallas se refrescan en cada sync, cosa que
  /// me gustaría que se disimule más" — con el nudge de baja latencia de
  /// `sincronizacion_supabase.dart` esto pasa mucho más seguido, así que el
  /// refresco automático es [silencioso]: no tapa la lista ya visible con
  /// el spinner ni con una pantalla de error por un hiccup transitorio de
  /// wifi (se reintenta solo en la próxima sync). Un refresco explícito
  /// (pull-to-refresh, cambiar de período o de filtro) sigue mostrando
  /// ambos como siempre.
  StreamSubscription<void>? _subCambiosSync;

  @override
  void initState() {
    super.initState();
    leerUsuario().then((u) {
      if (mounted) setState(() => _usuarioId = u?.id);
    });
    _cargar();
    _subCambiosSync = avisosCambiosCompanion.listen(
      (_) => _cargar(silencioso: true),
    );
  }

  @override
  void dispose() {
    _subCambiosSync?.cancel();
    super.dispose();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }
    try {
      final conexion = await leerConexion();
      final cliente =
          _cliente ??
          (conexion == null
              ? ServicioCompanionOffline(PuertoLocal(baseLocalCompanion()))
              : await resolverServicioCompanion(conexion));
      final rango = _periodo.rango();
      final ventas = await cliente.historialDeVentas(
        desde: rango.desde,
        hasta: rango.hasta,
        filtroMedio: _filtroMedio,
      );
      if (mounted) {
        setState(() {
          _cliente = cliente;
          _ventas = ventas;
        });
      }
    } catch (e) {
      if (mounted && !silencioso) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted && !silencioso) setState(() => _cargando = false);
    }
  }

  void _elegirPeriodo(_Periodo p) {
    if (p == _periodo) return;
    setState(() => _periodo = p);
    _cargar();
  }

  void _elegirMedio(MedioVentaHistorialCompanion? m) {
    if (m == _filtroMedio) return;
    setState(() => _filtroMedio = m);
    _cargar();
  }

  Future<void> _confirmarYAnular(VentaDelHistorialCompanion v) async {
    final motivoCtrl = TextEditingController();
    final motivo = await mostrarHojaVidrio<String>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '¿Eliminar la venta de ${formatearARS(v.totalCentavos)}?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: Espaciado.sm),
          Text(
            'Se repone el stock y se revierte la caja. La venta sigue viéndose acá, marcada como anulada.',
            style: TextStyle(color: context.colores.textoSecundario),
          ),
          const SizedBox(height: Espaciado.md),
          TextField(
            controller: motivoCtrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Motivo'),
          ),
          const SizedBox(height: Espaciado.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: Espaciado.sm),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: context.colores.error),
                  onPressed: () => Navigator.of(context).pop(motivoCtrl.text.trim()),
                  child: const Text('Eliminar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    motivoCtrl.dispose();
    if (motivo == null || motivo.isEmpty || _cliente == null || _usuarioId == null) {
      return;
    }
    try {
      await _cliente!.anularVenta(
        ventaId: v.ventaId,
        usuarioId: _usuarioId!,
        motivo: motivo,
      );
      _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mensajeDeError(e))));
      }
    }
  }

  /// Desglose de una venta (El dueño, 2026-09-13: "poder ver un desglose de
  /// la venta") — mismo `Ticket` que arma la impresión, del lado del
  /// servidor (Regla 3). Una venta anulada abre igual: sigue siendo útil
  /// ver qué tenía, aunque ya esté revertida.
  Future<void> _abrirDesglose(VentaDelHistorialCompanion v) async {
    if (_cliente == null) return;
    final cliente = _cliente!;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _HojaDesglose(cliente: cliente, venta: v),
    );
  }

  /// Antes eran dos filas rotuladas ("Período"/"Medio de pago") de chips
  /// horizontales — El dueño, 2026-09-13: "comen demasiado espacio y es muy
  /// confuso" (no quedaba claro que esas filas se podían deslizar). Un
  /// menú desplegable compacto por filtro dice el valor elegido Y da
  /// acceso a cambiarlo en el mismo lugar, sin ocupar una fila propia ni
  /// esconder opciones fuera de la pantalla.
  Widget _selectorPeriodo(BuildContext context) {
    return PopupMenuButton<_Periodo>(
      initialValue: _periodo,
      onSelected: _elegirPeriodo,
      itemBuilder: (context) => [
        for (final p in _Periodo.values)
          PopupMenuItem(value: p, child: Text(p.etiqueta)),
      ],
      child: _Pildora(icono: IconosPlazoleta.calendarTodayOutlined, texto: _periodo.etiqueta),
    );
  }

  Widget _selectorMedio(BuildContext context) {
    return PopupMenuButton<MedioVentaHistorialCompanion?>(
      initialValue: _filtroMedio,
      onSelected: _elegirMedio,
      itemBuilder: (context) => [
        const PopupMenuItem(value: null, child: Text('Todos los medios')),
        for (final m in MedioVentaHistorialCompanion.values)
          PopupMenuItem(value: m, child: Text(m.etiqueta)),
      ],
      child: _Pildora(
        icono: _filtroMedio?.icono ?? IconosPlazoleta.paymentsOutlined,
        texto: _filtroMedio?.etiqueta ?? 'Todos',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Cierres se mudó acá adentro como segunda pestaña (El dueño, 2026-09-18:
    // "reacomodación de absolutamente todos los elementos" — ventas y
    // cierres son las dos formas de mirar para atrás, no dos ideas
    // separadas que merezcan cada una su propio lugar en Gestión/Historial).
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const EncabezadoCompanion(
                rotulo: 'Registro',
                titulo: 'Historial',
                padding: EdgeInsets.fromLTRB(EspacioCompanion.xl, EspacioCompanion.xl, EspacioCompanion.xl, EspacioCompanion.md),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(Espaciado.xl, 0, Espaciado.xl, Espaciado.sm),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: context.colores.fondoBloque, borderRadius: BorderRadius.circular(999)),
                child: TabBar(
                  tabs: const [Tab(text: 'Ventas'), Tab(text: 'Cierres')],
                  labelColor: context.colores.acentoTexto,
                  unselectedLabelColor: context.colores.textoSecundario,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  splashBorderRadius: BorderRadius.circular(999),
                  indicator: BoxDecoration(color: context.colores.acento, borderRadius: BorderRadius.circular(999)),
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [_pestanaVentas(context), const PantallaCierres()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pestanaVentas(BuildContext context) {
    // Una venta anulada no suma al total del período — su plata ya se
    // revirtió de la caja (`anularVenta`), contarla igual mostraría más de
    // lo que de verdad entró.
    final total = _ventas
        .where((v) => !v.anulada)
        .fold<int>(0, (acc, v) => acc + v.totalCentavos);
    return Column(
      children: [
        const SizedBox(height: Espaciado.sm),
        Padding(
              padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg),
              child: Row(
                children: [
                  _selectorPeriodo(context),
                  const SizedBox(width: Espaciado.sm),
                  _selectorMedio(context),
                ],
              ),
            ),
            const SizedBox(height: Espaciado.sm),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg),
                child: ErrorEnLinea(_error!),
              )
            else if (!_cargando)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_ventas.length} venta(s)',
                      style: TextStyle(color: context.colores.textoSecundario),
                    ),
                    Text(
                      formatearARS(total),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: Espaciado.sm),
            Expanded(
              child: _cargando
                  ? const EsqueletoLista()
                  : _error != null
                  ? EstadoErrorCompanion(mensaje: _error!, onReintentar: _cargar)
                  : _ventas.isEmpty
                  ? RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView(
                        children: const [
                          SizedBox(
                            height: 300,
                            child: EstadoVacioCompanion(
                              mensaje: 'Sin ventas en este período',
                              icono: IconosPlazoleta.receiptLongOutlined,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: _lista(context),
                    ),
            ),
      ],
    );
  }

  Widget _lista(BuildContext context) {
    // Agrupadas por día (El dueño: "tipo mercado pago") — sin `intl`, mismo
    // formateo manual que ya usa el resto de la companion.
    final grupos = <String, List<VentaDelHistorialCompanion>>{};
    for (final v in _ventas) {
      grupos.putIfAbsent(_tituloDia(v.fecha), () => []).add(v);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Espaciado.lg,
        0,
        Espaciado.lg,
        Espaciado.lg + NavbarCompanion.espacioReservado,
      ),
      children: [
        for (final entrada in grupos.entries) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Espaciado.sm),
            child: Text(
              entrada.key,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final v in entrada.value)
            Padding(
              padding: const EdgeInsets.only(bottom: Espaciado.sm),
              child: Superficie(
                padding: EdgeInsets.zero,
                child: Presionable(
                  onTap: () => _abrirDesglose(v),
                  child: Padding(
                    padding: const EdgeInsets.all(Bento.paddingBloque),
                    child: Row(
                        children: [
                          Icon(
                            v.medio.icono,
                            color: v.anulada
                                ? context.colores.textoTenue
                                : context.colores.textoSecundario,
                          ),
                          const SizedBox(width: Espaciado.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  v.detalle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: v.anulada ? context.colores.textoTenue : null,
                                    decoration: v.anulada ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                                Text(
                                  v.anulada
                                      ? 'Anulada · ${_hora(v.fecha)} · ${v.medio.etiqueta}'
                                      : '${_hora(v.fecha)} · ${v.medio.etiqueta}',
                                  style: TextStyle(
                                    color: v.anulada
                                        ? context.colores.error
                                        : context.colores.textoSecundario,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            formatearARS(v.totalCentavos),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: v.anulada ? context.colores.textoTenue : null,
                              decoration: v.anulada ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          if (!v.anulada && v.sesionAbierta) ...[
                            const SizedBox(width: Espaciado.sm),
                            IconButton(
                              icon: Icon(
                                IconosPlazoleta.deleteOutline,
                                color: context.colores.textoSecundario,
                              ),
                              onPressed: () => _confirmarYAnular(v),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ],
    );
  }
}

/// Botón compacto que muestra el filtro elegido y abre el menú para
/// cambiarlo (`PopupMenuButton` es quien maneja el toque; esto es solo su
/// apariencia) — mismo `Bloque`/radio de control que el resto del kit, sin
/// inventar un estilo de chip nuevo.
class _Pildora extends StatelessWidget {
  const _Pildora({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Espaciado.md,
        vertical: Espaciado.sm,
      ),
      decoration: BoxDecoration(
        color: context.colores.fondoBloque,
        borderRadius: BorderRadius.circular(Radios.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 16, color: context.colores.textoSecundario),
          const SizedBox(width: Espaciado.xs),
          Text(texto, style: Theme.of(context).textTheme.bodyMedium),
          const Icon(IconosPlazoleta.arrowDropDown, size: 18),
        ],
      ),
    );
  }
}

/// Hoja del desglose de una venta (El dueño, 2026-09-13: "poder ver un
/// desglose de la venta") — carga el detalle al abrirse (mismo `Ticket`
/// que la impresión, Regla 3) en vez de pedirlo por adelantado para cada
/// fila de la lista, que ya viene sin este detalle (`historialDeVentas`
/// solo trae el resumen para no pagar N consultas por cada venta que se
/// lista y nunca se abre).
class _HojaDesglose extends StatefulWidget {
  const _HojaDesglose({required this.cliente, required this.venta});

  final ServicioCompanion cliente;
  final VentaDelHistorialCompanion venta;

  @override
  State<_HojaDesglose> createState() => _HojaDesgloseState();
}

class _HojaDesgloseState extends State<_HojaDesglose> {
  DetalleVentaCompanion? _detalle;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final detalle = await widget.cliente.detalleVenta(widget.venta.ventaId);
      if (mounted) setState(() => _detalle = detalle);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        final detalle = _detalle;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            Espaciado.lg,
            Espaciado.md,
            Espaciado.lg,
            Espaciado.lg,
          ),
          child: _error != null
              ? Center(child: ErrorEnLinea(_error!))
              : detalle == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  controller: scrollController,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: Espaciado.md),
                        decoration: BoxDecoration(
                          color: colores.borde,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      'Venta #${widget.venta.ventaId}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (widget.venta.anulada)
                      Padding(
                        padding: const EdgeInsets.only(top: Espaciado.xs),
                        child: Text(
                          'Anulada',
                          style: TextStyle(color: colores.error, fontWeight: Pesos.medium),
                        ),
                      ),
                    Text(
                      '${_fechaHora(detalle.fecha)} · ${detalle.vendedor}',
                      style: TextStyle(color: colores.textoSecundario),
                    ),
                    const SizedBox(height: Espaciado.lg),
                    for (final l in detalle.lineas)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Espaciado.sm),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                l.gramos != null
                                    ? '${l.nombreProducto} (${l.gramos}g)'
                                    : '${l.nombreProducto} x${l.cantidad}',
                              ),
                            ),
                            Text(formatearARS(l.subtotalCentavos)),
                          ],
                        ),
                      ),
                    Divider(color: colores.borde),
                    _filaTotal(context, 'Subtotal', detalle.subtotalCentavos),
                    if (detalle.recargoCigarrillosCentavos > 0)
                      _filaTotal(
                        context,
                        'Recargo cigarrillos',
                        detalle.recargoCigarrillosCentavos,
                      ),
                    if (detalle.descuentoCentavos > 0)
                      _filaTotal(context, 'Descuento', -detalle.descuentoCentavos),
                    if (detalle.redondeoCentavos > 0)
                      _filaTotal(context, 'Redondeo', detalle.redondeoCentavos),
                    const SizedBox(height: Espaciado.sm),
                    _filaTotal(context, 'Total', detalle.totalCentavos, destacado: true),
                  ],
                ),
        );
      },
    );
  }

  Widget _filaTotal(
    BuildContext context,
    String etiqueta,
    int centavos, {
    bool destacado = false,
  }) {
    final estilo = destacado
        ? Theme.of(context).textTheme.titleLarge
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Espaciado.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta, style: estilo),
          Text(
            centavos < 0 ? '-${formatearARS(-centavos)}' : formatearARS(centavos),
            style: estilo?.copyWith(color: destacado ? context.colores.acento : null),
          ),
        ],
      ),
    );
  }
}

String _fechaHora(DateTime f) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(f.day)}/${dos(f.month)}/${f.year} ${dos(f.hour)}:${dos(f.minute)}';
}

String _hora(DateTime f) =>
    '${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';

String _tituloDia(DateTime f) {
  final ahora = DateTime.now();
  final hoy = DateTime(ahora.year, ahora.month, ahora.day);
  final dia = DateTime(f.year, f.month, f.day);
  if (dia == hoy) return 'Hoy';
  if (dia == hoy.subtract(const Duration(days: 1))) return 'Ayer';
  return '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';
}

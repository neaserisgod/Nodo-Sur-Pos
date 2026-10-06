// Historial de ventas, filtrable — pestaña de Historial desde 2026-09-26
// (antes vivía en Reportes). Nació en Reportes (El dueño, 2026-09-07: "que sea
// filtrable... tipo mercado pago... que también sirva para un control
// manual en caso de desconfiar de los números"). Mismo repositorio que la
// pantalla equivalente del celular (Regla 3).
//
// Distribución del "Lenguaje de diseño" (El dueño, 2026-09-26, mock
// `HistorialVentas.dc.html`): filtros arriba (período, medio, búsqueda),
// la lista de ventas agrupada por día a la izquierda con lo vendido, los
// tickets y el promedio, y la venta elegida a la derecha con sus líneas, el
// total, la ganancia y las acciones (reimprimir, editar, anular).
//
// Anular (El dueño, 2026-09-13): solo mientras la sesión de esa venta siga
// abierta, revirtiendo stock y caja sin borrar la fila (`anularVenta`) —
// Regla 6, nunca se pierde el rastro.
//
// Rediseño v4 (2026-10-06), desde cero como el mock (`histBody`): a la izquierda el total del período en el bloque
// negro y una fila por venta; a la derecha la venta elegida como un ticket (líneas, subtotal, ajustes, total, ganancia)
// con Reimprimir, Editar y Anular venta.

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/linea_venta_reconstruccion.dart';
import '../../data/repositorio_edicion_venta.dart';
import '../../data/repositorio_historial.dart' show lineasDeVenta;
import '../../data/repositorio_historial_ventas.dart';
import '../../domain/equilibrio.dart';
import '../comun/aviso_superior.dart';
import '../comun/fechas.dart';
import '../impresion/dialogo_imprimir_ticket.dart';
import '../kit/kit.dart';
import '../navegacion/busqueda_contextual.dart' show coincideBusqueda;
import '../navegacion/refresco_por_celular.dart';
import 'devolucion_mp_dialogo.dart';
import 'pantalla_editor_venta.dart';
import 'pantalla_historial.dart' show FilaFiltrosHistorial;
import 'periodo_historial.dart';

extension on MedioVentaHistorial {
  String get etiqueta => switch (this) {
    MedioVentaHistorial.efectivo => 'Efectivo',
    MedioVentaHistorial.qr => 'QR',
    MedioVentaHistorial.debitCard => 'Débito',
    MedioVentaHistorial.creditCard => 'Crédito',
    MedioVentaHistorial.mixto => 'Mixto',
  };

  /// `medioTag` del mock: efectivo verde, mixto amarillo, lo demás azul.
  TonoMock get tono => switch (this) {
    MedioVentaHistorial.efectivo => TonoMock.g,
    MedioVentaHistorial.mixto => TonoMock.w,
    _ => TonoMock.i,
  };

  /// `iconoMedio` del mock.
  Ic get icono => switch (this) {
    MedioVentaHistorial.efectivo => Ic.cash,
    MedioVentaHistorial.debitCard || MedioVentaHistorial.creditCard => Ic.card,
    _ => Ic.scan,
  };
}

class TabHistorialVentas extends StatefulWidget {
  const TabHistorialVentas({super.key, required this.db, required this.usuarioId, this.busqueda = '', required this.buscador});

  final AppDatabase db;
  final int usuarioId;

  /// Lo escrito en el buscador de la fila de filtros: número de venta o producto.
  final String busqueda;
  final Widget buscador;

  @override
  State<TabHistorialVentas> createState() => _TabHistorialVentasState();
}

class _TabHistorialVentasState extends State<TabHistorialVentas> with RefrescoPorCelular {
  @override
  void alCambiarDesdeElCelular() => _cargar();

  PeriodoHistorial _periodo = PeriodoHistorial.hoy;
  MedioVentaHistorial? _filtroMedio;
  List<VentaDelHistorial>? _ventas;
  int? _elegida;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final rango = _periodo.rango();
    final ventas = await historialDeVentas(widget.db, desde: rango.desde, hasta: rango.hasta, filtroMedio: _filtroMedio);
    if (!mounted) return;
    setState(() {
      _ventas = ventas;
      if (_elegida == null || !ventas.any((v) => v.ventaId == _elegida)) {
        _elegida = ventas.isEmpty ? null : ventas.first.ventaId;
      }
    });
  }

  void _elegirPeriodo(PeriodoHistorial p) {
    if (p == _periodo) return;
    setState(() {
      _periodo = p;
      _ventas = null;
    });
    _cargar();
  }

  void _elegirMedio(MedioVentaHistorial? m) {
    if (m == _filtroMedio) return;
    setState(() {
      _filtroMedio = m;
      _ventas = null;
    });
    _cargar();
  }

  /// Número de venta o producto: se filtra sobre lo ya cargado, sin volver
  /// a la base (el período ya acota la lista).
  List<VentaDelHistorial> get _visibles {
    final ventas = _ventas ?? const [];
    final q = widget.busqueda;
    if (q.isEmpty) return ventas;
    return ventas.where((v) => '${v.ventaId}' == q.replaceAll('#', '') || coincideBusqueda(v.detalle, q)).toList();
  }

  Future<void> _confirmarYAnular(VentaDelHistorial v) async {
    final motivo = await mostrarModalMock<String>(context, builder: (_) => _DialogoAnular(venta: v));
    if (motivo == null || motivo.isEmpty) return;
    try {
      await anularVenta(widget.db, ventaId: v.ventaId, usuarioId: widget.usuarioId, motivo: motivo);
      _cargar();
      if (mounted) await ofrecerDevolucionMp(context, widget.db, v.ventaId);
    } on ArgumentError catch (e) {
      // "sesión ya cerrada" / "ya está anulada" — un límite de negocio, no
      // un bug.
      if (mounted) {
        mostrarAviso(context, e.message.toString());
      }
    }
  }

  Future<void> _editar(VentaDelHistorial v) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PantallaEditorVenta(db: widget.db, ventaId: v.ventaId, usuarioId: widget.usuarioId)),
    );
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final ventas = _ventas;
    final visibles = _visibles;
    final elegida = visibles.where((v) => v.ventaId == _elegida).firstOrNull ?? visibles.firstOrNull;
    final ancho = MediaQuery.sizeOf(context).width;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilaFiltrosHistorial(
          periodo: _periodo,
          onPeriodo: _elegirPeriodo,
          chips: [
            for (final (m, t) in [(null, 'Todos'), for (final m in MedioVentaHistorial.values) (m, m.etiqueta)])
              ChipMock(t, chico: true, elegido: m == _filtroMedio, onTap: () => _elegirMedio(m)),
          ],
          buscador: widget.buscador,
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ventas == null
              ? const SizedBox.shrink()
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: ancho >= 1700 ? 540 : 420,
                      child: _ListaVentas(
                        ventas: visibles,
                        periodo: _periodo,
                        elegida: elegida?.ventaId,
                        alElegir: (id) => setState(() => _elegida = id),
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: elegida == null
                          ? const Vacio(texto: 'Elegí una venta para ver su detalle', icono: null, padding: EdgeInsets.symmetric(vertical: 70))
                          : SingleChildScrollView(
                              child: _DetalleVenta(
                                key: ValueKey(elegida.ventaId),
                                db: widget.db,
                                venta: elegida,
                                alAnular: () => _confirmarYAnular(elegida),
                                alEditar: () => _editar(elegida),
                              ),
                            ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// "Anular venta #N" del mock: el motivo es obligatorio, con atajos.
class _DialogoAnular extends StatefulWidget {
  const _DialogoAnular({required this.venta});
  final VentaDelHistorial venta;

  @override
  State<_DialogoAnular> createState() => _DialogoAnularState();
}

class _DialogoAnularState extends State<_DialogoAnular> {
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  void _anular() {
    final m = _motivo.text.trim();
    if (m.isEmpty) return;
    Navigator.of(context).pop(m);
  }

  @override
  Widget build(BuildContext context) {
    return ModalMock(
      titulo: 'Anular venta ${widget.venta.etiqueta}',
      subtitulo: 'Revierte el stock y la caja. Nunca borra la venta: queda anotada como anulada.',
      ancho: AnchoModal.angosto,
      cuerpo: [
        Nota(
          texto: 'Se anula la venta de ${pesos(widget.venta.totalCentavos)}. Solo se puede mientras la sesión de caja siga abierta.',
          tono: TonoMock.w,
        ),
        Campo(etiqueta: 'Motivo (obligatorio)', controller: _motivo, pista: 'Ej: cobré de más', autofocus: true, campoKey: const Key('campo_motivo_anular'), onChanged: (_) => setState(() {}), onSubmitted: (_) => _anular()),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in const ['Error de carga', 'Cliente se arrepintió', 'Cobré de más', 'Producto en mal estado'])
              ChipMock(m, chico: true, elegido: _motivo.text == m, onTap: () => setState(() => _motivo.text = m)),
          ],
        ),
      ],
      pie: [
        Btn('Anular venta', variante: VarBtn.red, tam: TamBtn.lg, ancho: true, onTap: _motivo.text.trim().isEmpty ? null : _anular),
        Btn('Cancelar', variante: VarBtn.out, ancho: true, onTap: () => Navigator.of(context).pop()),
      ],
    );
  }
}

class _ListaVentas extends StatelessWidget {
  const _ListaVentas({required this.ventas, required this.periodo, required this.elegida, required this.alElegir});

  final List<VentaDelHistorial> ventas;
  final PeriodoHistorial periodo;
  final int? elegida;
  final void Function(int) alElegir;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    // Una venta anulada no suma: su plata ya se revirtió de la caja.
    final validas = ventas.where((v) => !v.anulada).toList();
    final total = validas.fold(0, (a, v) => a + v.totalCentavos);
    final variosDias = periodo != PeriodoHistorial.hoy && periodo != PeriodoHistorial.ayer;

    // Filas planas: encabezado de día (si el período tiene varios) + ventas de ese día (de más nueva a más vieja).
    final filas = <Object>[];
    DateTime? diaActual;
    for (final v in ventas) {
      final dia = DateTime(v.fecha.year, v.fecha.month, v.fecha.day);
      if (variosDias && dia != diaActual) {
        diaActual = dia;
        filas.add(dia);
      }
      filas.add(v);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(color: p.hero, borderRadius: BorderRadius.circular(28)),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${validas.length} venta${validas.length == 1 ? '' : 's'} · ${periodo.etiqueta.toLowerCase()}',
                  style: estilo(16, 600, color: p.heroSub),
                ),
              ),
              NumeroQueCuenta(valor: total, formato: pesos, estilo: estilo(30, 550, color: p.sobreHero, em: -.04, num: true)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ventas.isEmpty
              ? const Vacio(texto: 'Sin ventas en este período', icono: null, padding: EdgeInsets.symmetric(vertical: 50))
              : ListView.separated(
                  padding: const EdgeInsets.only(right: 4),
                  itemCount: filas.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final f = filas[i];
                    if (f is DateTime) {
                      final delDia = ventas.where((v) => !v.anulada && DateUtils.isSameDay(v.fecha, f)).fold(0, (a, v) => a + v.totalCentavos);
                      final dia = fechaLarga(f);
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                        child: Row(
                          children: [
                            Expanded(child: Text(dia[0].toUpperCase() + dia.substring(1), style: estilo(14, 600, color: p.mute))),
                            Text(pesos(delDia), style: estilo(14, 600, color: p.mute, num: true)),
                          ],
                        ),
                      );
                    }
                    final v = f as VentaDelHistorial;
                    return Aparecer.tarjeta(
                      orden: i,
                      child: Rowb(
                        titulo: 'Venta ${v.etiqueta}',
                        detalle: '${horaCorta(v.fecha)} · ${v.medio.etiqueta}${v.detalle.isEmpty ? '' : ' · ${v.detalle}'}',
                        izquierda: Ibox(v.medio.icono),
                        elegida: v.ventaId == elegida,
                        onTap: () => alElegir(v.ventaId),
                        derecha: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (v.anulada) ...[const Etiqueta('Anulada', tono: TonoMock.b), const SizedBox(width: 10)],
                            Text(
                              pesos(v.totalCentavos),
                              style: estilo(17, 600, color: v.anulada ? p.mute : p.tinta, num: true).copyWith(
                                decoration: v.anulada ? TextDecoration.lineThrough : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// `hr` del ticket: raya punteada de 2 px.
class _Punteada extends StatelessWidget {
  const _Punteada();

  @override
  Widget build(BuildContext context) {
    final color = context.p.linea;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, caja) {
          final n = (caja.maxWidth / 10).floor();
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [for (var i = 0; i < n; i++) SizedBox(width: 5, height: 2, child: ColoredBox(color: color))],
          );
        },
      ),
    );
  }
}

class _DetalleVenta extends StatefulWidget {
  const _DetalleVenta({super.key, required this.db, required this.venta, required this.alAnular, required this.alEditar});

  final AppDatabase db;
  final VentaDelHistorial venta;
  final VoidCallback alAnular;
  final VoidCallback alEditar;

  @override
  State<_DetalleVenta> createState() => _DetalleVentaState();
}

class _DetalleVentaState extends State<_DetalleVenta> {
  List<FilaLineaVenta>? _lineas;
  FilaVenta? _fila;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final db = widget.db;
    final lineas = await lineasDeVenta(db, widget.venta.ventaId);
    final fila = await (db.select(db.ventas)..where((v) => v.id.equals(widget.venta.ventaId))).getSingle();
    if (mounted) {
      setState(() {
        _lineas = lineas;
        _fila = fila;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lineas = _lineas;
    final fila = _fila;
    final v = widget.venta;
    final p = context.p;
    if (lineas == null || fila == null) return const SizedBox.shrink();

    final ganancia = calcularGananciaBruta(lineas: lineas.map((l) => lineaParaReposicionDesde(l, venta: fila)).toList());
    final articulos = lineas.fold(0, (a, l) => a + (l.esPesable ? 1 : (l.cantidad ?? 1)));
    final fecha = fechaLarga(v.fecha);

    Widget ln(String izquierda, String derecha, {Color? color, Color? colorDerecha, double tamanio = 18, double peso = 400}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(izquierda, style: estilo(tamanio, peso, color: color ?? p.tinta, num: true))),
          const SizedBox(width: 14),
          Text(derecha, style: estilo(tamanio, peso, color: colorDerecha ?? color ?? p.tinta, num: true)),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 26),
      decoration: BoxDecoration(color: p.s, borderRadius: BorderRadius.circular(36)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Venta ${v.etiqueta}', style: estilo(30, 550, color: p.tinta, em: -.03)),
                    const SizedBox(height: 6),
                    Text(
                      '${fecha[0].toUpperCase()}${fecha.substring(1)} · ${horaCorta(v.fecha)} · $articulos artículo${articulos == 1 ? '' : 's'}${fila.editadaEn != null ? ' · editada' : ''}',
                      style: estilo(16, 400, color: p.mute),
                    ),
                  ],
                ),
              ),
              if (v.anulada) ...[const Etiqueta('Venta anulada', tono: TonoMock.b), const SizedBox(width: 8)],
              Etiqueta(v.medio.etiqueta, tono: v.medio.tono),
            ],
          ),
          const _Punteada(),
          for (final l in lineas)
            ln(
              '${l.esPesable ? '${l.gramos} g' : '${l.cantidad ?? 1} ×'} ${l.nombreProductoFoto}',
              pesos(lineaParaReposicionDesde(l).precioLineaCentavos),
            ),
          const _Punteada(),
          ln('Subtotal', pesos(fila.subtotalCentavos), color: p.mute),
          if (fila.recargoCigarrillosCentavos != 0) ln('Recargo de cigarrillos', '+${pesos(fila.recargoCigarrillosCentavos)}', color: p.mute),
          if (fila.descuentoCentavos != 0) ln('Descuento', '−${pesos(fila.descuentoCentavos)}', color: p.mute),
          if (fila.redondeoCentavos != 0) ln('Redondeo', pesosConSigno(fila.redondeoCentavos), color: p.mute),
          const SizedBox(height: 4),
          ln('Total', pesos(v.totalCentavos), tamanio: 28, peso: 450),
          ln(
            ganancia.vendidoSinCostoCentavos > 0 ? 'Ganancia (hay productos sin costo)' : 'Ganancia de la venta',
            pesos(ganancia.gananciaBrutaCentavos),
            color: p.mute,
            colorDerecha: p.g,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Btn(
                'Reimprimir',
                variante: VarBtn.ton,
                sobreGris: true,
                icono: Ic.print,
                onTap: () => mostrarDialogoImprimirTicket(context, db: widget.db, ventaId: v.ventaId),
              ),
              if (!v.anulada) Btn('Editar', variante: VarBtn.ton, sobreGris: true, icono: Ic.edit, onTap: widget.alEditar),
              if (!v.anulada && v.sesionAbierta) Btn('Anular venta', variante: VarBtn.red, onTap: widget.alAnular),
            ],
          ),
        ],
      ),
    );
  }
}

// Historial → Movimientos (El dueño, 2026-09-28: "revisá si hay un apartado
// para ver los movimientos, los movimientos de caja y eso" — no había).
// Gastos, ingresos, pagos a proveedores y retiros, uno por uno: cuándo, de
// qué caja, por qué medio, quién. Las ventas no, ya tienen su pestaña.
// Solo lectura: un movimiento de caja es un registro, no se edita.
//
// Rediseño v4 (2026-10-06), como el mock: una tabla (hora, tipo, motivo, caja, monto) con lo que salió y entró del
// período en la fila de filtros.

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/repositorio_movimientos_caja.dart';
import '../comun/fechas.dart';
import '../kit/kit.dart';
import '../navegacion/busqueda_contextual.dart' show coincideBusqueda;
import '../navegacion/refresco_por_celular.dart';
import 'pantalla_historial.dart' show FilaFiltrosHistorial;
import 'periodo_historial.dart';

String etiquetaTipoMovimiento(String tipo) => switch (tipo) {
  'GASTO' => 'Gasto',
  'INGRESO' => 'Ingreso',
  'PAGO_PROVEEDOR' => 'Pago a proveedor',
  'RETIRO' => 'Retiro',
  'DEVOLUCION_SENA' => 'Devolución de seña',
  _ => tipo,
};

class TabHistorialMovimientos extends StatefulWidget {
  const TabHistorialMovimientos({super.key, required this.db, this.busqueda = '', required this.buscador});

  final AppDatabase db;

  /// Buscador de la fila de filtros: motivo, proveedor o quién lo hizo.
  final String busqueda;
  final Widget buscador;

  @override
  State<TabHistorialMovimientos> createState() => _TabHistorialMovimientosState();
}

class _TabHistorialMovimientosState extends State<TabHistorialMovimientos> with RefrescoPorCelular {
  @override
  void alCambiarDesdeElCelular() => _cargar();

  PeriodoHistorial _periodo = PeriodoHistorial.hoy;
  String? _tipo;
  List<MovimientoDeCaja>? _movimientos;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final rango = _periodo.rango();
    final lista = await movimientosDeCaja(widget.db, desde: rango.desde, hasta: rango.hasta);
    if (mounted) setState(() => _movimientos = lista);
  }

  void _elegirPeriodo(PeriodoHistorial p) {
    if (p == _periodo) return;
    setState(() {
      _periodo = p;
      _movimientos = null;
    });
    _cargar();
  }

  List<MovimientoDeCaja> get _visibles => [
    for (final m in _movimientos ?? const <MovimientoDeCaja>[])
      if ((_tipo == null || m.tipo == _tipo) &&
          (widget.busqueda.isEmpty ||
              coincideBusqueda('${m.nota ?? ''} ${m.proveedor ?? ''} ${m.usuario} ${etiquetaTipoMovimiento(m.tipo)}', widget.busqueda)))
        m,
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final lista = _movimientos;
    final visibles = _visibles;
    final salio = visibles.where((m) => m.esSalida).fold(0, (a, m) => a + m.montoCentavos);
    final entro = visibles.where((m) => !m.esSalida).fold(0, (a, m) => a + m.montoCentavos);
    final variosDias = _periodo != PeriodoHistorial.hoy && _periodo != PeriodoHistorial.ayer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilaFiltrosHistorial(
          periodo: _periodo,
          onPeriodo: _elegirPeriodo,
          chips: [
            for (final (t, e) in [(null, 'Todos'), for (final t in tiposMovimientoVisible) (t, etiquetaTipoMovimiento(t))])
              ChipMock(e, chico: true, elegido: t == _tipo, onTap: () => setState(() => _tipo = t)),
          ],
          buscador: widget.buscador,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text('Salió ', style: estilo(15, 500, color: p.mute)),
            Text(pesos(salio), key: const Key('movimientos_salio'), style: estilo(15, 600, color: p.b, num: true)),
            Text('  ·  Entró ', style: estilo(15, 500, color: p.mute)),
            Text(pesos(entro), style: estilo(15, 600, color: p.g, num: true)),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: lista == null
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                      child: Tabla(
                        radio: 28,
                        columnas: [
                          ColumnaTabla(variosDias ? 'Día y hora' : 'Hora', ancho: variosDias ? 210 : 110),
                          const ColumnaTabla('Tipo', ancho: 230),
                          const ColumnaTabla('Motivo', flex: 5),
                          const ColumnaTabla('Caja', flex: 2),
                          const ColumnaTabla('Monto', flex: 2, derecha: true),
                        ],
                        cantidad: visibles.length,
                        vacio: const Vacio(texto: 'Sin movimientos en este período', icono: null, padding: EdgeInsets.symmetric(vertical: 36)),
                        celdas: (context, i) {
                          final m = visibles[i];
                          final caja = m.esLata ? 'Lata' : (m.esMercadoPago ? 'Mercado Pago' : 'Cajón');
                          final motivo = m.nota ?? m.proveedor ?? etiquetaTipoMovimiento(m.tipo);
                          return [
                            celda(context, variosDias ? '${fechaLarga(m.fecha)} · ${horaCorta(m.fecha)}' : horaCorta(m.fecha), color: p.mute, num: true),
                            Etiqueta(etiquetaTipoMovimiento(m.tipo), tono: m.tipo == 'INGRESO' ? TonoMock.g : TonoMock.neutro),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                celda(context, m.proveedor != null && m.nota != null ? '${m.proveedor} · $motivo' : motivo, peso: 500),
                                Text(m.usuario, style: estilo(13, 400, color: p.mute)),
                              ],
                            ),
                            celda(context, caja, color: p.mute),
                            celda(context, '${m.esSalida ? '−' : '+'}${pesos(m.montoCentavos)}', num: true, peso: 600, color: m.esSalida ? p.b : p.g),
                          ];
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

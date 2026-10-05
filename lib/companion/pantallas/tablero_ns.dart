// Tablero del día al pie de Inicio (mock 03b/03c): ganancia, tickets y ticket promedio, ventas por hora, lo más vendido,
// stock bajo y encargues y deudas. Los mismos datos que el Inicio de la PC (`tableroDelDia`, Regla 3), leídos de la base
// local, que se sincroniza sola. Se relee cuando llega algo nuevo.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/repositorio_tablero.dart';
import '../../domain/dinero.dart';
import '../../domain/tablero.dart' show ProductoMasVendido;
import '../app_ns.dart';
import '../base_local.dart';
import '../cambios_companion.dart';
import '../kit/kit_ns.dart';

class TableroNs extends StatefulWidget {
  const TableroNs({super.key});

  @override
  State<TableroNs> createState() => _TableroNsState();
}

class _TableroNsState extends State<TableroNs> {
  TableroDelDia? _t;
  StreamSubscription<void>? _avisos;
  ControladorAppNs? _app;

  @override
  void initState() {
    super.initState();
    _cargar();
    _avisos = avisosCambiosCompanion.listen((_) => _cargar());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppNs.of(context);
    if (_app != app) {
      _app?.datosDia.removeListener(_cargar);
      _app = app;
      app.datosDia.addListener(_cargar);
    }
  }

  @override
  void dispose() {
    _app?.datosDia.removeListener(_cargar);
    _avisos?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final t = await tableroDelDia(baseLocalCompanion());
      if (mounted) setState(() => _t = t);
    } catch (_) {
      // Sin base todavía no hay tablero que mostrar.
    }
  }

  static const _dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
  static const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

  String get _cabecera {
    final a = DateTime.now();
    String dos(int n) => n.toString().padLeft(2, '0');
    return 'Hoy · ${_dias[a.weekday - 1]} ${a.day} ${_meses[a.month - 1]} · ${dos(a.hour)}:${dos(a.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (t == null) return const SizedBox.shrink();
    final ns = context.ns;
    final ticketProm = t.tickets == 0 ? 0 : ((t.vendidoCentavos / t.tickets) / centavosPorPeso).round() * centavosPorPeso;
    final margen = t.margen;
    return Padding(
      padding: const EdgeInsets.fromLTRB(margenNs, 0, margenNs, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(0, 18, 0, 14), child: Text(mayusculasNs(_cabecera), style: seccionNs(ns.mute))),
          Row(
            children: [
              Expanded(child: _Indicador(etiqueta: 'Ganancia', valor: plataNs(t.gananciaCentavos), color: ns.g, extra: margen == null ? null : '${(margen * 100).round()}%')),
              const SizedBox(width: 10),
              Expanded(child: _Indicador(etiqueta: 'Tickets', valor: '${t.tickets}')),
              const SizedBox(width: 10),
              Expanded(child: _Indicador(etiqueta: 'Ticket prom.', valor: plataNs(ticketProm))),
            ],
          ),
          const SizedBox(height: 14),
          _VentasPorHora(porHora: t.porHora),
          const SizedBox(height: 14),
          if (t.masVendidos.isNotEmpty) ...[_MasVendidos(productos: t.masVendidos), const SizedBox(height: 14)],
          if (t.stockBajo.isNotEmpty) ...[_StockBajo(productos: t.stockBajo), const SizedBox(height: 14)],
          if (t.pendientes.isNotEmpty) _Pendientes(pendientes: t.pendientes),
        ],
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.titulo, required this.hijos, this.derecha});
  final String titulo;
  final List<Widget> hijos;
  final Widget? derecha;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(titulo, style: estiloNs(18, peso: FontWeight.w500, track: -0.02, color: ns.ink))),
              ?derecha,
            ],
          ),
          const SizedBox(height: 14),
          ...hijos,
        ],
      ),
    );
  }
}

class _Indicador extends StatelessWidget {
  const _Indicador({required this.etiqueta, required this.valor, this.color, this.extra});
  final String etiqueta;
  final String valor;
  final Color? color;
  final String? extra;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Container(
      constraints: const BoxConstraints(minHeight: 85),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta, maxLines: 1, overflow: TextOverflow.ellipsis, style: estiloNs(13, color: ns.mute)),
          const SizedBox(height: 2),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(valor, style: estiloNs(19, peso: FontWeight.w600, color: color ?? ns.ink, tabular: true))),
          if (extra != null) Text(extra!, style: estiloNs(12, peso: FontWeight.w600, color: color ?? ns.ink)),
        ],
      ),
    );
  }
}

class _VentasPorHora extends StatelessWidget {
  const _VentasPorHora({required this.porHora});
  final Map<int, int> porHora;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    const horas = [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21];
    final valores = [for (final h in horas) porHora[h] ?? 0];
    final maximo = valores.fold<int>(0, (a, b) => a > b ? a : b);
    final pico = maximo == 0 ? null : horas[valores.indexOf(maximo)];
    return _Tarjeta(
      titulo: 'Ventas por hora',
      derecha: pico == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Pico · $pico a ${pico + 1} h', style: estiloNs(13, color: ns.mute)),
                Text(plataNs(maximo), style: estiloNs(18, peso: FontWeight.w600, color: ns.ink, tabular: true)),
              ],
            ),
      hijos: [
        Semantics(
          label: 'Ventas por hora de las 9 a las 21',
          child: ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < horas.length; i++)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 110,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(width: 20, height: maximo == 0 ? 6 : (8 + 102 * valores[i] / maximo), decoration: BoxDecoration(color: valores[i] == maximo && maximo > 0 ? ns.ink : ns.s2, borderRadius: BorderRadius.circular(6))),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(height: 14, width: 20, child: OverflowBox(maxWidth: 40, child: Text(const {9, 12, 15, 18}.contains(horas[i]) ? '${horas[i]}' : (horas[i] == 21 ? '21 h' : ''), maxLines: 1, style: estiloNs(12, color: ns.mute)))),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MasVendidos extends StatelessWidget {
  const _MasVendidos({required this.productos});
  final List<ProductoMasVendido> productos;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final maximo = productos.fold<int>(1, (a, p) => p.vendidoCentavos > a ? p.vendidoCentavos : a);
    return _Tarjeta(
      titulo: 'Más vendidos hoy',
      hijos: [
        for (final p in productos) ...[
          Row(
            children: [
              Expanded(child: Text(p.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: estiloNs(15, peso: FontWeight.w500, color: ns.ink))),
              const SizedBox(width: 8),
              Text('${p.esPesable ? '${_miles(p.gramos)} g' : '${p.cantidad} u.'} · ${plataNs(p.vendidoCentavos)}', style: estiloNs(15, color: ns.mute, tabular: true)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Stack(
              children: [
                Container(height: 8, color: ns.s2),
                FractionallySizedBox(widthFactor: (p.vendidoCentavos / maximo).clamp(0.02, 1.0), child: Container(height: 8, color: ns.ink)),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  static String _miles(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
}

class _StockBajo extends StatelessWidget {
  const _StockBajo({required this.productos});
  final List<ProductoConStockBajo> productos;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return _Tarjeta(
      titulo: 'Stock bajo',
      derecha: Container(constraints: const BoxConstraints(minWidth: 28), height: 28, padding: const EdgeInsets.symmetric(horizontal: 8), decoration: BoxDecoration(color: ns.wbg, borderRadius: BorderRadius.circular(999)), alignment: Alignment.center, child: Text('${productos.length}', style: estiloNs(14, peso: FontWeight.w700, color: ns.w))),
      hijos: [
        for (final p in productos) ...[
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: estiloNs(15, peso: FontWeight.w500, color: ns.ink)),
                    Text(p.proveedor ?? 'Sin proveedor', style: estiloNs(13, color: ns.mute)),
                  ],
                ),
              ),
              Text(p.stock <= 0 ? 'Sin stock' : 'Quedan ${p.esPesable ? kilosTextoNs(p.stock) : p.stock}', style: estiloNs(14, peso: FontWeight.w600, color: p.stock <= 0 ? ns.b : ns.w)),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _Pendientes extends StatelessWidget {
  const _Pendientes({required this.pendientes});
  final List<PendienteDelTablero> pendientes;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return _Tarjeta(
      titulo: 'Encargues y deudas',
      hijos: [
        for (final p in pendientes) ...[
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.quien, maxLines: 1, overflow: TextOverflow.ellipsis, style: estiloNs(15, peso: FontWeight.w500, color: ns.ink)),
                    Text(p.esFiado ? (p.detalle == null || p.detalle!.isEmpty ? 'Deuda' : 'Deuda · ${p.detalle}') : (p.detalle == null || p.detalle!.isEmpty ? 'Encargue' : 'Encargue · ${p.detalle}'), maxLines: 1, overflow: TextOverflow.ellipsis, style: estiloNs(13, color: ns.mute)),
                  ],
                ),
              ),
              if (p.montoCentavos != null) Text(plataNs(p.montoCentavos!), style: estiloNs(16, peso: FontWeight.w600, color: ns.ink, tabular: true)),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

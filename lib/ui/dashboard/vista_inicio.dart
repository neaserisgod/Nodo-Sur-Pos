// Inicio "Hoy" del mock v4 (`inicioHoy` en `p5_pages.js`), hecho desde cero. Dos filas de tres:
//
//  * Arriba (292 px): el bloque oscuro "Hoy vendiste" (cifra que cuenta, ganancia, comparación con el mismo día de la
//    semana pasada y la barra efectivo / Mercado Pago); cuatro indicadores en 2×2 (tickets, ticket promedio, unidades,
//    "Falta separar" que lleva a Separaciones); y los más vendidos del día.
//  * Abajo: ventas por hora (barras que crecen, las altas en azul), stock bajo con cuántos días alcanza, y encargues y
//    deudas.
//
// Solo dibuja lo que le pasa `TableroDelDia` (`repositorio_tablero.dart`): ninguna cuenta vive acá.

import 'package:flutter/material.dart';

import '../../data/repositorio_tablero.dart';
import '../comun/fechas.dart';
import '../kit/kit.dart';

class VistaInicioHoy extends StatelessWidget {
  const VistaInicioHoy({
    super.key,
    required this.tablero,
    required this.hoy,
    required this.onSeparar,
    required this.onVerPendientes,
    this.conPendientes = true,
  });

  final TableroDelDia tablero;
  final DateTime hoy;
  final VoidCallback onSeparar;
  final VoidCallback onVerPendientes;
  final bool conPendientes;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // A 1366×768 las dos filas no entran con aire: se scrollea la página entera en vez de aplastarlas.
        final entra = c.maxHeight >= 640;
        final arriba = SizedBox(height: entra ? 292 : 280, child: _FilaArriba(t: tablero, hoy: hoy, onSeparar: onSeparar));
        final abajo = _FilaAbajo(t: tablero, onVerPendientes: onVerPendientes, conPendientes: conPendientes);
        final contenido = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [arriba, const SizedBox(height: 14), if (entra) Expanded(child: abajo) else SizedBox(height: 420, child: abajo)],
        );
        return entra ? contenido : SingleChildScrollView(child: contenido);
      },
    );
  }
}

class _FilaArriba extends StatelessWidget {
  const _FilaArriba({required this.t, required this.hoy, required this.onSeparar});
  final TableroDelDia t;
  final DateTime hoy;
  final VoidCallback onSeparar;

  @override
  Widget build(BuildContext context) {
    final promedio = t.tickets == 0 ? 0 : t.vendidoCentavos ~/ t.tickets;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: Aparecer.revelar(child: _HoyVendiste(t: t, hoy: hoy))),
        const SizedBox(width: 14),
        Expanded(
          child: Aparecer.revelar(
            orden: 1,
            child: Column(
              children: [
                Expanded(
                  child: Row(children: [
                    Expanded(child: _Kpi(etiqueta: 'Tickets', valor: t.tickets, formato: (v) => '$v')),
                    const SizedBox(width: 14),
                    Expanded(child: _Kpi(etiqueta: 'Ticket promedio', valor: promedio, formato: pesos)),
                  ]),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: Row(children: [
                    Expanded(child: _Kpi(etiqueta: 'Unidades vendidas', valor: t.unidadesVendidas, formato: (v) => '$v')),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _Kpi(
                        key: const Key('inicio_falta_separar'),
                        etiqueta: 'Falta separar',
                        valor: t.faltaSepararCentavos,
                        formato: pesos,
                        tono: TonoMock.w,
                        onTap: onSeparar,
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(child: Aparecer.revelar(orden: 2, child: _MasVendidos(t: t))),
      ],
    );
  }
}

/// `.hero` "Hoy vendiste".
class _HoyVendiste extends StatelessWidget {
  const _HoyVendiste({required this.t, required this.hoy});
  final TableroDelDia t;
  final DateTime hoy;

  // Los verdes y azules del mock sobre el bloque oscuro (más claros que los de la paleta, para leerse sobre negro).
  static const _verde = Color(0xFF63D9B0);
  static const _barraEfe = Color(0xFF0B8F6F);
  static const _barraMp = Color(0xFF3F6DF0);
  static const _puntoEfe = Color(0xFF2FD0A3);
  static const _puntoMp = Color(0xFF7DA0FF);

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final antes = t.vendidoMismoDiaSemanaPasadaCentavos;
    String? comparacion;
    if (antes > 0 && t.vendidoCentavos > 0) {
      final v = ((t.vendidoCentavos - antes) * 100 / antes).round();
      comparacion = '${v >= 0 ? '+' : '−'}${v.abs()} % vs ${diasSemana[hoy.weekday - 1]} pasado';
    }
    final total = t.efectivoCentavos + t.mpCentavos;
    return BloqueHero(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hoy vendiste', style: estilo(15, 600, color: p.heroSub)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: NumeroQueCuenta(valor: t.vendidoCentavos, formato: pesos, estilo: Tipos.fig(p.sobreHero, tamanio: 60)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Ganancia ${pesos(t.gananciaCentavos)}', style: estilo(18, 600, color: _verde, num: true)),
              if (comparacion != null)
                Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  decoration: BoxDecoration(color: _verde.withValues(alpha: .16), borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [Text(comparacion, style: estilo(13.5, 600, color: _verde))]),
                ),
            ],
          ),
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 14,
              color: const Color(0x24FFFFFF),
              child: total == 0
                  ? null
                  : LayoutBuilder(
                      builder: (context, c) => Row(children: [
                        Crecer(
                          factor: t.efectivoCentavos / total,
                          builder: (context, k) => SizedBox(width: c.maxWidth * k, height: 14, child: const ColoredBox(color: _barraEfe)),
                        ),
                        Crecer(
                          factor: t.mpCentavos / total,
                          builder: (context, k) => SizedBox(width: c.maxWidth * k, height: 14, child: const ColoredBox(color: _barraMp)),
                        ),
                      ]),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _Medio(punto: _puntoEfe, etiqueta: 'Efectivo', monto: t.efectivoCentavos)),
              _Medio(punto: _puntoMp, etiqueta: 'Mercado Pago', monto: t.mpCentavos, derecha: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _Medio extends StatelessWidget {
  const _Medio({required this.punto, required this.etiqueta, required this.monto, this.derecha = false});
  final Color punto;
  final String etiqueta;
  final int monto;
  final bool derecha;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Column(
      crossAxisAlignment: derecha ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 6), decoration: BoxDecoration(color: punto, shape: BoxShape.circle)),
          Text(etiqueta, style: estilo(13, 400, color: p.heroSub)),
        ]),
        const SizedBox(height: 4),
        Text(pesos(monto), style: Tipos.fig(p.sobreHero, tamanio: 24)),
      ],
    );
  }
}

/// Un indicador chico (`kpi()` del mock): etiqueta arriba, cifra abajo.
class _Kpi extends StatelessWidget {
  const _Kpi({super.key, required this.etiqueta, required this.valor, required this.formato, this.tono, this.onTap});
  final String etiqueta;
  final int valor;
  final String Function(int) formato;
  final TonoMock? tono;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final colorCifra = tono == null ? p.tinta : tono!.colores(p).$2;
    final tarjeta = Tarjeta(
      tono: tono,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta, style: estilo(14, 600, color: tono == null ? p.mute : colorCifra)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: NumeroQueCuenta(valor: valor, formato: formato, estilo: Tipos.fig(colorCifra, tamanio: 34)),
          ),
        ],
      ),
    );
    if (onTap == null) return tarjeta;
    return Levantable(builder: (context, _) => Tocable(onTap: onTap, radio: 32, etiqueta: '$etiqueta: ${formato(valor)}', child: tarjeta));
  }
}

/// Cabecera de una tarjeta de lista: `.sec` a la izquierda y algo a la derecha.
class _Cabecera extends StatelessWidget {
  const _Cabecera(this.titulo, {this.derecha});
  final String titulo;
  final Widget? derecha;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [Expanded(child: Sec(titulo)), ?derecha]),
      );
}

/// Fila con línea finísima arriba (menos la primera).
class _Fila extends StatelessWidget {
  const _Fila({required this.primera, required this.child, this.vertical = 10});
  final bool primera;
  final Widget child;
  final double vertical;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(vertical: vertical),
        decoration: BoxDecoration(border: primera ? null : Border(top: BorderSide(color: context.p.pelo))),
        child: child,
      );
}

class _MasVendidos extends StatelessWidget {
  const _MasVendidos({required this.t});
  final TableroDelDia t;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final lista = t.masVendidos;
    return Tarjeta(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Cabecera('Más vendidos hoy', derecha: Etiqueta('hoy')),
          if (lista.isEmpty)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text('Todavía no se vendió nada hoy.', style: estilo(15, 400, color: p.mute)))
          else
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: lista.length,
                itemBuilder: (context, i) {
                  final m = lista[i];
                  return _Fila(
                    primera: i == 0,
                    vertical: 8,
                    child: Row(
                      children: [
                        Avatar('${i + 1}', diametro: 26, tamanioTexto: 12, color: p.mute),
                        const SizedBox(width: 10),
                        Expanded(child: Text(m.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo(15.5, 500, color: p.tinta))),
                        const SizedBox(width: 10),
                        Text(m.esPesable ? '${m.gramos} g' : '${m.cantidad} u.', style: estilo(13, 400, color: p.mute, num: true)),
                        ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 84),
                          child: Text(pesos(m.vendidoCentavos), textAlign: TextAlign.right, style: estilo(15.5, 600, color: p.tinta, num: true)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _FilaAbajo extends StatelessWidget {
  const _FilaAbajo({required this.t, required this.onVerPendientes, required this.conPendientes});
  final TableroDelDia t;
  final VoidCallback onVerPendientes;
  final bool conPendientes;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: Aparecer.revelar(orden: 3, child: _VentasPorHora(porHora: t.porHora))),
        const SizedBox(width: 14),
        Expanded(child: Aparecer.revelar(orden: 4, child: _StockBajo(lista: t.stockBajo))),
        if (conPendientes) ...[
          const SizedBox(width: 14),
          Expanded(child: Aparecer.revelar(orden: 4, child: _Pendientes(lista: t.pendientes, onVerTodos: onVerPendientes))),
        ],
      ],
    );
  }
}

/// `.bars`: una barra por hora, de las 8 a las 20 como mínimo (más si se vendió antes o después); las que llegan al
/// 88 % del pico, en azul. Crecen escalonadas al aparecer.
class _VentasPorHora extends StatelessWidget {
  const _VentasPorHora({required this.porHora});
  final Map<int, int> porHora;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final desde = [8, ...porHora.keys].reduce((a, b) => a < b ? a : b);
    final hasta = [20, ...porHora.keys].reduce((a, b) => a > b ? a : b);
    final maximo = porHora.values.fold(0, (a, b) => a > b ? a : b);
    final pico = maximo == 0 ? null : porHora.entries.firstWhere((e) => e.value == maximo).key;
    return Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Cabecera('Ventas por hora', derecha: pico == null ? null : Etiqueta('pico $pico h', tono: TonoMock.i)),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var h = desde; h <= hasta; h++) ...[
                  if (h > desde) const SizedBox(width: 8),
                  Expanded(
                    child: Tooltip(
                      message: '$h h · ${pesos(porHora[h] ?? 0)}',
                      child: Column(
                        children: [
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, c) {
                                final f = maximo == 0 ? 0.0 : (porHora[h] ?? 0) / maximo;
                                return Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Crecer(
                                    factor: f,
                                    duracion: ms(600),
                                    demora: ms((h - desde) * 25),
                                    builder: (context, k) => Container(
                                      height: c.maxHeight * k,
                                      decoration: BoxDecoration(color: f >= .88 ? p.azul : p.s3, borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text('$h', style: estilo(13, 600, color: p.soft)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StockBajo extends StatelessWidget {
  const _StockBajo({required this.lista});
  final List<ProductoConStockBajo> lista;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Cabecera(
            'Stock bajo',
            derecha: lista.isEmpty ? null : Etiqueta('${lista.length} producto${lista.length == 1 ? '' : 's'}', tono: TonoMock.w),
          ),
          if (lista.isEmpty)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text('Nada por debajo del mínimo.', style: estilo(15, 400, color: p.mute)))
          else
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: lista.length,
                itemBuilder: (context, i) {
                  final s = lista[i];
                  final agotado = s.stock <= 0;
                  final dias = s.diasQueAlcanza;
                  final alcanza = agotado
                      ? 'pedir hoy'
                      : dias == null
                          ? null
                          : (dias < 1 ? 'alcanza ~1 día' : 'alcanza $dias ${dias == 1 ? 'día' : 'días'}');
                  final detalle = [?(s.categoria ?? s.proveedor), ?alcanza].join(' · ');
                  final cantidad = s.esPesable ? '${(s.stock / 1000).toStringAsFixed(1).replaceAll('.', ',')} kg' : '${s.stock} u.';
                  return _Fila(
                    primera: i == 0,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo(16, 500, color: p.tinta)),
                              if (detalle.isNotEmpty) Text(detalle, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo(13, 400, color: p.mute)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Etiqueta(agotado ? 'Sin stock' : cantidad, tono: agotado ? TonoMock.b : TonoMock.w),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _Pendientes extends StatelessWidget {
  const _Pendientes({required this.lista, required this.onVerTodos});
  final List<PendienteDelTablero> lista;
  final VoidCallback onVerTodos;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Cabecera('Encargues y deudas', derecha: Btn('Ver todos', variante: VarBtn.ton, sobreGris: true, tam: TamBtn.xs, onTap: onVerTodos)),
          if (lista.isEmpty)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text('No hay encargues ni deudas pendientes.', style: estilo(15, 400, color: p.mute)))
          else
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: lista.length,
                itemBuilder: (context, i) {
                  final e = lista[i];
                  return _Fila(
                    primera: i == 0,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${e.esFiado ? 'Deuda' : 'Encargue'} de ${e.quien}', maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo(16, 500, color: p.tinta)),
                              Text(e.detalle ?? 'desde el ${e.desde.day}/${e.desde.month}', maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo(13, 400, color: p.mute)),
                            ],
                          ),
                        ),
                        if (e.montoCentavos != null) Text(pesos(e.montoCentavos!), style: estilo(16, 600, color: p.tinta, num: true)),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

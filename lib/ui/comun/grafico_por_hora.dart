// Barras de ventas por hora (Inicio, "Lenguaje de diseño" 2026-09-26). Sin
// librería de gráficos: son barras y texto, alcanza con el layout de
// Flutter. La hora pico va resaltada y su monto arriba; al pasar el mouse
// (o tocar, en pantalla táctil) por otra barra se lee esa.

import 'package:flutter/material.dart';

import '../../domain/dinero.dart';
import '../tema/tokens.dart';

class GraficoPorHora extends StatefulWidget {
  const GraficoPorHora({super.key, required this.porHora, this.altura = 200});

  /// Hora del día (0–23) → centavos vendidos.
  final Map<int, int> porHora;
  final double altura;

  @override
  State<GraficoPorHora> createState() => _GraficoPorHoraState();
}

class _GraficoPorHoraState extends State<GraficoPorHora> {
  int? _elegida;

  /// Siempre un rango que se lee como "el día del local" aunque haya pocas
  /// ventas: de las 9 a las 21 como mínimo, ampliado si se vendió antes o
  /// después.
  List<int> get _horas {
    final conVenta = widget.porHora.keys;
    final desde = [9, ...conVenta].reduce((a, b) => a < b ? a : b);
    final hasta = [21, ...conVenta].reduce((a, b) => a > b ? a : b);
    return [for (var h = desde; h <= hasta; h++) h];
  }

  int? get _pico {
    if (widget.porHora.isEmpty) return null;
    return widget.porHora.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final horas = _horas;
    final maximo = widget.porHora.values.fold(0, (a, b) => b > a ? b : a);
    final pico = _pico;
    final mostrada = _elegida ?? pico;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Ventas por hora', style: textTheme.titleMedium?.copyWith(fontWeight: Pesos.fuerte))),
            if (mostrada != null) ...[
              Text(
                '${_elegida == null ? 'Pico · ' : ''}$mostrada a ${mostrada + 1} h',
                style: textTheme.bodySmall,
              ),
              const SizedBox(width: Espaciado.md),
              Text(
                formatearARS(widget.porHora[mostrada] ?? 0),
                style: textTheme.titleLarge?.tabular,
              ),
            ] else
              Text('Todavía no hay ventas hoy', style: textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: Espaciado.lg),
        SizedBox(
          height: widget.altura,
          child: DecoratedBox(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colores.borde))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final h in horas)
                  Expanded(
                    child: MouseRegion(
                      onEnter: (_) => setState(() => _elegida = h),
                      onExit: (_) => setState(() => _elegida = null),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _elegida = h),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Espaciado.xs),
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: maximo == 0 ? 0 : ((widget.porHora[h] ?? 0) / maximo).clamp(0.0, 1.0),
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 40),
                                decoration: BoxDecoration(
                                  color: h == mostrada ? colores.acento : colores.acento.withValues(alpha: 0.35),
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Espaciado.xs),
        Row(
          children: [
            for (final h in horas)
              Expanded(
                child: Text('$h h', textAlign: TextAlign.center, style: textTheme.labelSmall),
              ),
          ],
        ),
      ],
    );
  }
}

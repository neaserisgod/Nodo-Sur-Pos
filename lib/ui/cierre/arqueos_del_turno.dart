// Los arqueos que se hicieron durante el turno (opcionales desde el
// 2026-09-28), como registro: hora, quién contó, y lo contado con su
// diferencia en cada caja. Lo usan el resumen del cierre y el detalle del
// día en Historial — una sola forma de mostrarlos (Regla 3).

import 'package:flutter/material.dart';

import '../../data/repositorio_arqueo_intermedio.dart' show ArqueoDelTurno;
import '../../domain/dinero.dart';
import '../comun/fechas.dart';
import '../comun/tarjetas.dart';
import '../tema/tokens.dart';

class ArqueosDelTurno extends StatelessWidget {
  const ArqueosDelTurno({super.key, required this.arqueos});

  final List<ArqueoDelTurno> arqueos;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return TarjetaSeccion(
      titulo: 'Arqueos del turno',
      insignia: Insignia(texto: arqueos.length == 1 ? '1 arqueo' : '${arqueos.length} arqueos'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, a) in arqueos.indexed) ...[
            if (i > 0) const Divider(height: Espaciado.lg),
            Text('${horaCorta(a.fecha)} · ${a.usuario}', style: textTheme.titleSmall),
            const SizedBox(height: Espaciado.xs),
            Wrap(
              spacing: Espaciado.lg,
              runSpacing: Espaciado.xs,
              children: [
                _Caja(etiqueta: 'Efectivo', contado: a.efectivoContadoCentavos, diferencia: a.efectivoDiferenciaCentavos),
                _Caja(etiqueta: 'Mercado Pago', contado: a.mpContadoCentavos, diferencia: a.mpDiferenciaCentavos),
                _Caja(etiqueta: 'Lata', contado: a.lataContadoCentavos, diferencia: a.lataDiferenciaCentavos),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Caja extends StatelessWidget {
  const _Caja({required this.etiqueta, required this.contado, required this.diferencia});

  final String etiqueta;
  final int contado;
  final int diferencia;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$etiqueta ${formatearARS(contado)}', style: textTheme.bodyMedium?.tabular),
        const SizedBox(width: Espaciado.xs),
        Insignia(
          texto: diferencia == 0
              ? 'justo'
              : (diferencia > 0 ? 'sobran ${formatearARS(diferencia)}' : 'faltan ${formatearARS(-diferencia)}'),
          tono: diferencia == 0 ? Tono.ganancia : Tono.alerta,
        ),
      ],
    );
  }
}

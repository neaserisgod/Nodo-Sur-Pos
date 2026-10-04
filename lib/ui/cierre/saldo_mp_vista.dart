// Saldo real de Mercado Pago en el cierre (etapa E, El dueño 2026-10-04): el botón que lo trae y llena el "MP contado" (queda
// editable), y las diferencias con lo que la app tiene, que se cargan con un toque como gasto o ingreso por MP.
//
// Nunca frena el cierre: sin cuenta no hay botón, y si el reporte tarda o falla se dice y se sigue contando a mano.

import 'package:flutter/material.dart';

import '../../domain/dinero.dart';
import '../comun/botones.dart';
import '../comun/fechas.dart';
import '../comun/fila_dato.dart';
import '../tema/tokens.dart';
import 'cierre_controlador.dart';

class BotonSaldoMp extends StatelessWidget {
  const BotonSaldoMp({super.key, required this.c});

  final CierreControlador c;

  @override
  Widget build(BuildContext context) {
    if (c.traerSaldoMp == null) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    final saldo = c.saldoMp;
    return Column(
      key: const Key('saldo_mp'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BotonSecundario(
          key: const Key('boton_traer_saldo_mp'),
          texto: saldo == null ? 'Traer saldo de Mercado Pago' : 'Traer de nuevo',
          onPressed: c.pidiendoSaldo ? null : c.traerSaldo,
        ),
        if (c.pidiendoSaldo)
          Padding(
            padding: const EdgeInsets.only(top: Espaciado.xs),
            child: Row(
              children: [
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: Espaciado.sm),
                Expanded(child: Text('Mercado Pago arma el reporte: puede tardar unos minutos.', style: textTheme.bodySmall)),
              ],
            ),
          ),
        if (c.errorSaldo != null)
          Padding(
            padding: const EdgeInsets.only(top: Espaciado.xs),
            child: Text(c.errorSaldo!, key: const Key('error_saldo_mp'), style: textTheme.bodySmall?.copyWith(color: context.colores.error)),
          ),
        if (saldo != null) ...[
          const SizedBox(height: Espaciado.xs),
          FilaDato(
            key: const Key('saldo_mp_total'),
            etiqueta: 'Saldo en Mercado Pago${saldo.hasta == null ? '' : ' a las ${horaCorta(saldo.hasta!)}'}',
            valor: formatearARS(saldo.totalCentavos),
            enfasis: true,
          ),
          Text(
            saldo.aLiberarConocido
                ? 'Disponible ${formatearARS(saldo.disponibleCentavos)} + por liberar ${formatearARS(saldo.aLiberarCentavos!)}. '
                    'Quedó cargado en "MP contado": corregilo si no coincide con lo que ves en la app de Mercado Pago.'
                : 'Es lo disponible: no se pudo calcular lo cobrado que todavía no se libera. Quedó cargado en "MP contado"; corregilo si hace falta.',
            style: textTheme.bodySmall,
          ),
          if (saldo.truncado) Text('Había más movimientos de los que se pudieron leer: puede faltar alguno.', style: textTheme.bodySmall?.copyWith(color: context.colores.error)),
        ],
      ],
    );
  }
}

class DiferenciasSaldoMpVista extends StatelessWidget {
  const DiferenciasSaldoMpVista({super.key, required this.c});

  final CierreControlador c;

  @override
  Widget build(BuildContext context) {
    final d = c.diferenciasSaldo;
    if (d == null || !d.hayDiferencias) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    final error = context.colores.error;
    String cuando(DateTime? f) => f == null ? '' : '${horaCorta(f)} · ';
    return Column(
      key: const Key('diferencias_saldo_mp'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Diferencias con Mercado Pago', style: textTheme.titleMedium?.copyWith(fontWeight: Pesos.fuerte)),
        Text('Cada una se puede cargar con un toque; si no la cargás, el cierre te va a dar esa diferencia.', style: textTheme.bodySmall),
        for (final m in d.egresosSinRegistrar)
          _Fila(
            etiqueta: '${cuando(m.fecha)}Salió de Mercado Pago y no está en la app (${m.descripcion.isEmpty ? m.tipo : m.descripcion})',
            valor: '-${formatearARS(m.debitoCentavos)}',
            boton: 'Cargar como gasto por MP',
            onPressed: () => c.cargarEgresoSinRegistrar(m),
          ),
        for (final m in d.ingresosSinRegistrar)
          _Fila(
            etiqueta: '${cuando(m.fecha)}Entró a Mercado Pago y no está en la app (${m.descripcion.isEmpty ? m.tipo : m.descripcion})',
            valor: '+${formatearARS(m.creditoCentavos)}',
            boton: 'Cargar como ingreso por MP',
            onPressed: () => c.cargarIngresoSinRegistrar(m),
          ),
        for (final v in d.ventasSinCobro)
          _Fila(
            etiqueta: '${cuando(v.fecha)}Venta #${v.ventaId} marcada como Mercado Pago y la plata no entró',
            valor: formatearARS(v.montoCentavos),
            color: error,
            boton: 'Cargar como gasto por MP',
            onPressed: () => c.cargarVentaSinCobroComoGasto(v),
          ),
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.etiqueta, required this.valor, required this.boton, required this.onPressed, this.color});

  final String etiqueta;
  final String valor;
  final String boton;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: Espaciado.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(etiqueta, style: textTheme.bodyMedium)),
              const SizedBox(width: Espaciado.sm),
              Text(valor, style: textTheme.bodyMedium?.copyWith(color: color)),
            ],
          ),
          const SizedBox(height: Espaciado.xs),
          BotonSecundario(texto: boton, onPressed: onPressed),
        ],
      ),
    );
  }
}

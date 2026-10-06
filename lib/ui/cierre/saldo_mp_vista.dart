// Saldo real de Mercado Pago en el cierre (etapa E, El dueño 2026-10-04): el botón que lo trae y llena el "MP contado" (queda
// editable), y las diferencias con lo que la app tiene, que se cargan con un toque como gasto o ingreso por MP.
//
// Nunca frena el cierre: sin cuenta no hay botón, y si el reporte tarda o falla se dice y se sigue contando a mano.
//
// Con el kit del mock v4 (2026-10-06): "Traer saldo" es el `Btn xs ton` que el mock pone adentro del campo de Mercado
// Pago (paso 1), y las diferencias van en la tarjeta "Mercado Pago según Mercado Pago" (paso 2).

import 'package:flutter/material.dart';

import '../comun/fechas.dart';
import '../kit/kit.dart';
import 'cierre_controlador.dart';
import 'seccion_mp_real.dart' show LineaMp;

/// "Traer saldo" (o "Traer de nuevo"). Nada si esta PC no tiene cuenta vinculada.
class BotonSaldoMp extends StatelessWidget {
  const BotonSaldoMp({super.key, required this.c});

  final CierreControlador c;

  @override
  Widget build(BuildContext context) {
    if (c.traerSaldoMp == null) return const SizedBox.shrink();
    return Btn(
      c.saldoMp == null ? 'Traer saldo' : 'Traer de nuevo',
      key: const Key('boton_traer_saldo_mp'),
      variante: VarBtn.ton,
      tam: TamBtn.xs,
      sobreGris: true,
      icono: Ic.reload,
      onTap: c.pidiendoSaldo ? null : c.traerSaldo,
    );
  }
}

/// Debajo de los campos del paso 1: que el reporte se está armando, que falló, o de dónde salió el número que quedó en
/// "Mercado Pago contado".
class EstadoSaldoMp extends StatelessWidget {
  const EstadoSaldoMp({super.key, required this.c});

  final CierreControlador c;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final saldo = c.saldoMp;
    final nota = estilo(14, 400, color: p.mute, alto: 1.45);
    if (c.traerSaldoMp == null || (!c.pidiendoSaldo && c.errorSaldo == null && saldo == null)) return const SizedBox.shrink();
    return Column(
      key: const Key('saldo_mp'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.pidiendoSaldo)
          Row(
            children: [
              Giro(child: Icono(Ic.reload, size: 16, color: p.mute)),
              const SizedBox(width: 10),
              Expanded(child: Text('Mercado Pago arma el reporte: puede tardar unos minutos.', style: nota)),
            ],
          ),
        if (c.errorSaldo != null) Text(c.errorSaldo!, key: const Key('error_saldo_mp'), style: nota.copyWith(color: p.b)),
        if (saldo != null) ...[
          LineaMp(
            'Saldo en Mercado Pago${saldo.hasta == null ? '' : ' a las ${horaCorta(saldo.hasta!)}'}',
            pesos(saldo.totalCentavos),
            key: const Key('saldo_mp_total'),
          ),
          Text(
            saldo.aLiberarConocido
                ? 'Disponible ${pesos(saldo.disponibleCentavos)} + por liberar ${pesos(saldo.aLiberarCentavos!)}. '
                    'Quedó cargado en "Mercado Pago contado": corregilo si no coincide con lo que ves en la app de Mercado Pago.'
                : 'Es lo disponible: no se pudo calcular lo cobrado que todavía no se libera. Quedó cargado en "Mercado Pago contado"; corregilo si hace falta.',
            style: nota,
          ),
          if (saldo.truncado) Text('Había más movimientos de los que se pudieron leer: puede faltar alguno.', style: nota.copyWith(color: p.b)),
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
    final p = context.p;
    String cuando(DateTime? f) => f == null ? '' : '${horaCorta(f)} · ';
    return Column(
      key: const Key('diferencias_saldo_mp'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Diferencias con el saldo', style: estilo(15.5, 600, color: p.tinta)),
        const SizedBox(height: 2),
        Text(
          'Cada una se puede cargar con un toque; si no la cargás, el cierre te va a dar esa diferencia.',
          style: estilo(13.5, 400, color: p.mute, alto: 1.45),
        ),
        for (final m in d.egresosSinRegistrar)
          _Fila(
            etiqueta: '${cuando(m.fecha)}Salió de Mercado Pago y no está en la app (${m.descripcion.isEmpty ? m.tipo : m.descripcion})',
            valor: '−${pesos(m.debitoCentavos)}',
            boton: 'Cargar como gasto por MP',
            onPressed: () => c.cargarEgresoSinRegistrar(m),
          ),
        for (final m in d.ingresosSinRegistrar)
          _Fila(
            etiqueta: '${cuando(m.fecha)}Entró a Mercado Pago y no está en la app (${m.descripcion.isEmpty ? m.tipo : m.descripcion})',
            valor: '+${pesos(m.creditoCentavos)}',
            boton: 'Cargar como ingreso por MP',
            onPressed: () => c.cargarIngresoSinRegistrar(m),
          ),
        for (final v in d.ventasSinCobro)
          _Fila(
            etiqueta: '${cuando(v.fecha)}Venta #${v.ventaId} marcada como Mercado Pago y la plata no entró',
            valor: pesos(v.montoCentavos),
            color: p.b,
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
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LineaMp(etiqueta, valor, color: color),
          const SizedBox(height: 4),
          Btn(boton, variante: VarBtn.ton, tam: TamBtn.xs, sobreGris: true, onTap: onPressed),
        ],
      ),
    );
  }
}

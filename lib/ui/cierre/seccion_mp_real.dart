// "Mercado Pago según Mercado Pago" en el cierre (PC y celular): lo que de verdad
// entró a la cuenta en el turno, contra lo que la app registró. Separa la
// "Diferencia MP" en sus partes: comisiones, devoluciones, cobros sin venta y
// ventas sin cobro (`domain/conciliacion_mp.dart`).
//
// Nunca frena el cierre: se pide a internet aparte, y si no hay red o el equipo
// no está vinculado, lo dice y deja reintentar.
//
// Con el kit del mock v4 (2026-10-06): va adentro de una `Tarjeta` del cierre, con filas `.ln` de 15 px (etiqueta gris a
// la izquierda, cifra en negrita a la derecha).

import 'package:flutter/material.dart';

import '../../domain/conciliacion_mp.dart';
import '../comun/fechas.dart';
import '../kit/kit.dart';

class SeccionMpReal extends StatefulWidget {
  const SeccionMpReal({
    super.key,
    required this.cargar,
    required this.mpEsperadoCentavos,
    this.mpContadoCentavos,
  });

  /// Null = este equipo no puede consultar Mercado Pago (sin cuenta de Nodo Sur).
  final Future<ConciliacionMp> Function()? cargar;

  /// El esperado de Mercado Pago que calculó la app (con lo registrado).
  final int mpEsperadoCentavos;

  /// Lo contado en la app de Mercado Pago, si ya se escribió.
  final int? mpContadoCentavos;

  @override
  State<SeccionMpReal> createState() => _SeccionMpRealState();
}

class _SeccionMpRealState extends State<SeccionMpReal> {
  ConciliacionMp? _c;
  String? _error;
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    _pedir();
  }

  Future<void> _pedir() async {
    final cargar = widget.cargar;
    if (cargar == null) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final c = await cargar();
      if (mounted) setState(() => _c = c);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  String _medio(String? m) => switch (m) {
    'account_money' => 'QR / dinero en cuenta',
    'debit_card' => 'Débito',
    'credit_card' => 'Crédito',
    'prepaid_card' => 'Prepaga',
    'bank_transfer' => 'Transferencia',
    null => 'Otro',
    _ => m,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = _c;
    return Column(
      key: const Key('seccion_mp_real'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Sec('Mercado Pago según Mercado Pago')),
            if (widget.cargar != null)
              BotonCirculo(
                icono: Ic.reload,
                etiqueta: 'Volver a consultar',
                fondo: context.p.papel,
                diametro: 38,
                tamanioIcono: 16,
                onTap: _cargando ? null : _pedir,
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (widget.cargar == null)
          Text(
            'Vinculá este equipo a tu cuenta de Nodo Sur (con Mercado Pago conectado) para ver lo que cobró de verdad.',
            style: estilo(14.5, 400, color: p.mute, alto: 1.45),
          )
        else if (_cargando && c == null)
          const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Center(child: Giro(child: Icono(Ic.reload, size: 20))))
        else if (_error != null && c == null)
          Text('No se pudo consultar Mercado Pago: $_error', style: estilo(14.5, 500, color: p.b, alto: 1.45))
        else if (c != null)
          ..._detalle(context, c),
      ],
    );
  }

  List<Widget> _detalle(BuildContext context, ConciliacionMp c) {
    final p = context.p;
    final esperadoReal = c.esperadoRealCentavos(widget.mpEsperadoCentavos);
    final contado = widget.mpContadoCentavos;
    final difReal = contado == null ? null : contado - esperadoReal;
    final nota = estilo(13.5, 400, color: p.mute, alto: 1.45);
    return [
      LineaMp('Cobrado en Mercado Pago (${c.cantidadCobros} cobros)', pesos(c.brutoCentavos), grande: true),
      if (c.devueltoCentavos != 0) LineaMp('Devoluciones', '−${pesos(c.devueltoCentavos)}'),
      LineaMp('Comisiones de Mercado Pago', '−${pesos(c.comisionCentavos)}'),
      LineaMp('Entró de verdad (neto)', pesos(c.netoCentavos), grande: true),
      LineaMp('Registrado en el sistema como Mercado Pago', pesos(c.registradoCentavos), arriba: true),
      LineaMp(
        'Diferencia de cobros',
        pesosConSigno(c.diferenciaCobrosCentavos),
        key: const Key('mp_real_diferencia_cobros'),
        color: c.diferenciaCobrosCentavos == 0 ? p.g : p.b,
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          c.diferenciaCobrosCentavos == 0
              ? 'Cada cobro de Mercado Pago tiene su venta en el sistema.'
              : c.diferenciaCobrosCentavos > 0
              ? 'Entró más plata a Mercado Pago de la que se registró: hay cobros sin venta (abajo).'
              : 'Se registraron ventas por Mercado Pago que no aparecen cobradas (abajo).',
          style: nota,
        ),
      ),
      LineaMp('Esperado con comisiones y devoluciones', pesos(esperadoReal), key: const Key('mp_real_esperado')),
      if (difReal != null)
        LineaMp(
          'Diferencia real (contado − esperado con comisiones)',
          pesosConSigno(difReal),
          key: const Key('mp_real_diferencia'),
          color: difReal == 0 ? p.g : p.b,
        ),
      LineaMp(
        'Cobros sin venta',
        c.cobrosSinVenta.isEmpty ? '0' : '${c.cobrosSinVenta.length} · ${pesos(c.cobrosSinVenta.fold(0, (a, x) => a + x.cobradoNetoDeDevolucionesCentavos))}',
        arriba: true,
        color: c.cobrosSinVenta.isEmpty ? p.g : p.w,
      ),
      for (final x in c.cobrosSinVenta)
        LineaMp(
          '${x.fecha == null ? '' : '${horaCorta(x.fecha!)} · '}${_medio(x.medio)}${x.estado == 'approved' ? '' : ' (${x.estado})'}',
          pesos(x.cobradoNetoDeDevolucionesCentavos),
          sangria: true,
        ),
      LineaMp('Ventas sin cobro', c.ventasSinCobro.isEmpty ? '0' : '${c.ventasSinCobro.length} · ${pesos(c.ventasSinCobro.fold(0, (a, v) => a + v.montoCentavos))}', color: c.ventasSinCobro.isEmpty ? p.g : p.b),
      for (final v in c.ventasSinCobro) LineaMp('Venta #${v.ventaId} · ${horaCorta(v.fecha)}', pesos(v.montoCentavos), sangria: true),
      if (c.noCobrados > 0) Text('${c.noCobrados} intentos rechazados, cancelados o pendientes (no suman).', style: nota),
      if (c.truncado) Text('Hubo más cobros de los que se pudieron leer: los totales pueden quedar cortos.', style: nota.copyWith(color: p.b)),
      if (_error != null) Text('Última consulta falló: $_error', style: nota.copyWith(color: p.b)),
      const SizedBox(height: 4),
      Text(
        'El neto incluye cobros que Mercado Pago todavía puede tener "a liberar": comparalo con el total de la cuenta, no solo con el disponible.',
        style: nota,
      ),
    ];
  }
}

/// `.ln` del mock: etiqueta gris a la izquierda y la cifra en negrita a la derecha, 15 px (15,5 las que suman). [arriba]
/// le pone la línea finita de separación arriba; [sangria], un renglón de detalle debajo de otro.
class LineaMp extends StatelessWidget {
  const LineaMp(this.etiqueta, this.valor, {super.key, this.color, this.arriba = false, this.grande = false, this.sangria = false, this.valorWidget});

  final String etiqueta;
  final String valor;
  final Color? color;
  final bool arriba;
  final bool grande;
  final bool sangria;
  final Widget? valorWidget;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final t = grande ? 15.5 : 15.0;
    return Container(
      padding: EdgeInsets.fromLTRB(sangria ? 14 : 0, arriba ? 7 : 5, 0, 5),
      margin: EdgeInsets.only(top: arriba ? 4 : 0),
      decoration: BoxDecoration(border: arriba ? Border(top: BorderSide(color: p.pelo)) : null),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(etiqueta, style: estilo(sangria ? 14 : t, 400, color: p.mute, alto: 1.35))),
          const SizedBox(width: 14),
          valorWidget ?? Text(valor, style: estilo(sangria ? 14 : t, 600, color: color ?? p.tinta, num: true, alto: 1.35)),
        ],
      ),
    );
  }
}

// "Mercado Pago según Mercado Pago" en el cierre (PC y celular): lo que de verdad
// entró a la cuenta en el turno, contra lo que la app registró. Separa la
// "Diferencia MP" en sus partes: comisiones, devoluciones, cobros sin venta y
// ventas sin cobro (`domain/conciliacion_mp.dart`).
//
// Nunca frena el cierre: se pide a internet aparte, y si no hay red o el equipo
// no está vinculado, lo dice y deja reintentar.

import 'package:flutter/material.dart';

import '../../domain/conciliacion_mp.dart';
import '../../domain/dinero.dart';
import '../comun/fechas.dart';
import '../comun/fila_dato.dart';
import '../tema/tokens.dart';

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
    final textTheme = Theme.of(context).textTheme;
    final secundario = textTheme.bodySmall?.copyWith(color: context.colores.textoSecundario);
    final c = _c;
    return Column(
      key: const Key('seccion_mp_real'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Mercado Pago según Mercado Pago', style: textTheme.titleMedium?.copyWith(fontWeight: Pesos.fuerte))),
            if (widget.cargar != null)
              IconButton(
                tooltip: 'Volver a consultar',
                onPressed: _cargando ? null : _pedir,
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
        if (widget.cargar == null)
          Text('Vinculá este equipo a tu cuenta de Nodo Sur (con Mercado Pago conectado) para ver lo que cobró de verdad.', style: secundario)
        else if (_cargando && c == null)
          const Padding(
            padding: EdgeInsets.all(Espaciado.md),
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          )
        else if (_error != null && c == null)
          Text('No se pudo consultar Mercado Pago: $_error', style: TextStyle(color: context.colores.error))
        else if (c != null)
          ..._detalle(context, c, secundario),
      ],
    );
  }

  List<Widget> _detalle(BuildContext context, ConciliacionMp c, TextStyle? secundario) {
    final error = context.colores.error;
    final esperadoReal = c.esperadoRealCentavos(widget.mpEsperadoCentavos);
    final contado = widget.mpContadoCentavos;
    final difReal = contado == null ? null : contado - esperadoReal;
    return [
      FilaDato(etiqueta: 'Cobrado en Mercado Pago (${c.cantidadCobros} cobros)', valor: formatearARS(c.brutoCentavos)),
      if (c.devueltoCentavos != 0) FilaDato(etiqueta: 'Devoluciones', valor: '-${formatearARS(c.devueltoCentavos)}'),
      FilaDato(etiqueta: 'Comisiones de Mercado Pago', valor: '-${formatearARS(c.comisionCentavos)}'),
      FilaDato(etiqueta: 'Entró de verdad (neto)', valor: formatearARS(c.netoCentavos), enfasis: true),
      const SizedBox(height: Espaciado.sm),
      FilaDato(etiqueta: 'Registrado en el sistema como Mercado Pago', valor: formatearARS(c.registradoCentavos)),
      FilaDato(
        key: const Key('mp_real_diferencia_cobros'),
        etiqueta: 'Diferencia de cobros',
        valor: formatearARS(c.diferenciaCobrosCentavos),
        enfasis: true,
        color: c.diferenciaCobrosCentavos == 0 ? null : error,
      ),
      Text(
        c.diferenciaCobrosCentavos == 0
            ? 'Cada cobro de Mercado Pago tiene su venta en el sistema.'
            : c.diferenciaCobrosCentavos > 0
            ? 'Entró más plata a Mercado Pago de la que se registró: hay cobros sin venta (abajo).'
            : 'Se registraron ventas por Mercado Pago que no aparecen cobradas (abajo).',
        style: secundario,
      ),
      const SizedBox(height: Espaciado.sm),
      FilaDato(key: const Key('mp_real_esperado'), etiqueta: 'Esperado con comisiones y devoluciones', valor: formatearARS(esperadoReal)),
      if (difReal != null)
        FilaDato(
          key: const Key('mp_real_diferencia'),
          etiqueta: 'Diferencia real (contado − esperado con comisiones)',
          valor: formatearARS(difReal),
          enfasis: true,
          color: difReal == 0 ? null : error,
        ),
      if (c.cobrosSinVenta.isNotEmpty) ...[
        const SizedBox(height: Espaciado.sm),
        Text('Cobros en Mercado Pago sin venta en el sistema', style: Theme.of(context).textTheme.titleSmall),
        for (final x in c.cobrosSinVenta)
          FilaDato(
            etiqueta: '${x.fecha == null ? '' : '${horaCorta(x.fecha!)} · '}${_medio(x.medio)}${x.estado == 'approved' ? '' : ' (${x.estado})'}',
            valor: formatearARS(x.cobradoNetoDeDevolucionesCentavos),
            color: error,
          ),
      ],
      if (c.ventasSinCobro.isNotEmpty) ...[
        const SizedBox(height: Espaciado.sm),
        Text('Ventas por Mercado Pago sin cobro en Mercado Pago', style: Theme.of(context).textTheme.titleSmall),
        for (final v in c.ventasSinCobro)
          FilaDato(etiqueta: 'Venta #${v.ventaId} · ${horaCorta(v.fecha)}', valor: formatearARS(v.montoCentavos), color: error),
      ],
      if (c.noCobrados > 0) Text('${c.noCobrados} intentos rechazados, cancelados o pendientes (no suman).', style: secundario),
      if (c.truncado) Text('Hubo más cobros de los que se pudieron leer: los totales pueden quedar cortos.', style: TextStyle(color: error)),
      if (_error != null) Text('Última consulta falló: $_error', style: TextStyle(color: error)),
      Text(
        'El neto incluye cobros que Mercado Pago todavía puede tener "a liberar": comparalo con el total de la cuenta, no solo con el disponible.',
        style: secundario,
      ),
    ];
  }
}

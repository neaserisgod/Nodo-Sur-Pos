// "Mercado Pago según Mercado Pago" del detalle de un cierre (mock 36b): lo que de verdad entró a la cuenta en el turno,
// contra lo que la app registró. Misma cuenta que `ui/cierre/seccion_mp_real.dart` (PC), dibujada con el kit del celular.
// Nunca frena nada: se pide a internet aparte y, si no hay red o el equipo no está vinculado, lo dice y deja reintentar.

import 'package:flutter/material.dart';

import '../../domain/conciliacion_mp.dart';
import '../../ui/comun/fechas.dart';
import '../kit/kit_ns.dart';

class SeccionMpRealNs extends StatefulWidget {
  const SeccionMpRealNs({super.key, required this.cargar, required this.mpEsperadoCentavos, this.mpContadoCentavos});

  /// Null = este equipo no puede consultar Mercado Pago (sin cuenta de Nodo Sur).
  final Future<ConciliacionMp> Function()? cargar;
  final int mpEsperadoCentavos;
  final int? mpContadoCentavos;

  @override
  State<SeccionMpRealNs> createState() => _SeccionMpRealNsState();
}

class _SeccionMpRealNsState extends State<SeccionMpRealNs> {
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

  /// `+$ 150` / `−$ 150` / `$ 0`, como el mock.
  String _signado(int d) => d == 0 ? plataNs(0) : '${d > 0 ? '+' : '−'}${plataNs(d.abs())}';

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final c = _c;
    return Column(
      key: const Key('seccion_mp_real'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: SeccionNs('Mercado Pago según Mercado Pago')),
            if (widget.cargar != null)
              PresionNs(
                onTap: _cargando ? null : _pedir,
                etiqueta: 'Volver a consultar',
                child: SizedBox(width: 44, height: 44, child: Center(child: IconoNsWidget(IconoNs.intercambio, tamanio: 18, color: ns.mute))),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (widget.cargar == null)
          const InfoNs('Vinculá este equipo a tu cuenta de Nodo Sur (con Mercado Pago conectado) para ver lo que cobró de verdad.')
        else if (_cargando && c == null)
          const Padding(padding: EdgeInsets.all(14), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))))
        else if (_error != null && c == null)
          InfoNs('No se pudo consultar Mercado Pago: $_error', tono: TonoNs.bad)
        else if (c != null)
          ..._detalle(context, c),
      ],
    );
  }

  List<Widget> _detalle(BuildContext context, ConciliacionMp c) {
    final ns = context.ns;
    final esperadoReal = c.esperadoRealCentavos(widget.mpEsperadoCentavos);
    final contado = widget.mpContadoCentavos;
    final difReal = contado == null ? null : contado - esperadoReal;
    final dc = c.diferenciaCobrosCentavos;
    return [
      FilaClaveValorNs(clave: 'Cobrado en Mercado Pago (${c.cantidadCobros} cobros)', valor: plataNs(c.brutoCentavos)),
      if (c.devueltoCentavos != 0) FilaClaveValorNs(clave: 'Devoluciones', valor: '−${plataNs(c.devueltoCentavos)}'),
      FilaClaveValorNs(clave: 'Comisiones de Mercado Pago', valor: '−${plataNs(c.comisionCentavos)}'),
      FilaClaveValorNs(clave: 'Entró de verdad (neto)', valor: plataNs(c.netoCentavos)),
      FilaClaveValorNs(clave: 'Registrado en el sistema como Mercado Pago', valor: plataNs(c.registradoCentavos)),
      FilaClaveValorNs(clave: 'Diferencia de cobros', valor: _signado(dc), colorValor: dc == 0 ? ns.g : ns.b),
      const SizedBox(height: 10),
      InfoNs(
        dc == 0
            ? 'Cada cobro de Mercado Pago tiene su venta en el sistema.'
            : dc > 0
            ? 'Entró más plata a Mercado Pago de la que se registró: hay cobros sin venta (abajo).'
            : 'Se registraron ventas por Mercado Pago que no aparecen cobradas (abajo).',
      ),
      FilaClaveValorNs(clave: 'Esperado con comisiones y devoluciones', valor: plataNs(esperadoReal)),
      if (difReal != null) FilaClaveValorNs(clave: 'Diferencia real (contado − esperado con comisiones)', valor: _signado(difReal), colorValor: difReal == 0 ? ns.g : ns.b),
      if (c.cobrosSinVenta.isNotEmpty) ...[
        const SizedBox(height: 14),
        const SeccionNs('Cobros en Mercado Pago sin venta en el sistema'),
        const SizedBox(height: 10),
        for (final x in c.cobrosSinVenta) ...[
          FilaProductoNs(nombre: '${x.fecha == null ? '' : '${horaCorta(x.fecha!)} · '}${_medio(x.medio)}${x.estado == 'approved' ? '' : ' (${x.estado})'}', valor: plataNs(x.cobradoNetoDeDevolucionesCentavos)),
          const SizedBox(height: 10),
        ],
      ],
      if (c.ventasSinCobro.isNotEmpty) ...[
        const SizedBox(height: 14),
        const SeccionNs('Ventas por Mercado Pago sin cobro en Mercado Pago'),
        const SizedBox(height: 10),
        for (final v in c.ventasSinCobro) ...[
          FilaProductoNs(nombre: 'Venta #${v.ventaId} · ${horaCorta(v.fecha)}', valor: plataNs(v.montoCentavos)),
          const SizedBox(height: 10),
        ],
      ],
      if (c.noCobrados > 0) InfoNs('${c.noCobrados} intentos rechazados, cancelados o pendientes (no suman).'),
      if (c.truncado) const InfoNs('Hubo más cobros de los que se pudieron leer: los totales pueden quedar cortos.', tono: TonoNs.bad),
      if (_error != null) InfoNs('Última consulta falló: $_error', tono: TonoNs.bad),
      const SizedBox(height: 10),
      const InfoNs('El neto incluye cobros que Mercado Pago todavía puede tener "a liberar": comparalo con el total de la cuenta, no solo con el disponible.'),
    ];
  }
}

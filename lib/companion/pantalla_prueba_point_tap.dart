// Pantalla de PRUEBA de Point Tap (El dueño, 2026-10-13): ver si la app de Mercado Pago acepta cobrar con tarjeta acercándola
// al celular cuando se lo pide esta app (`point_tap.dart`). No es parte del cobro: muestra la respuesta cruda de Mercado Pago
// para leerla y decidir si se integra. Cobra de verdad: el monto de prueba se devuelve desde la app de Mercado Pago.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, FilteringTextInputFormatter;

import '../domain/dinero.dart' show parsearARS;
import 'kit/kit_ns.dart';
import 'point_tap.dart';

class PantallaPruebaPointTap extends StatefulWidget {
  const PantallaPruebaPointTap({super.key});

  @override
  State<PantallaPruebaPointTap> createState() => _PantallaPruebaPointTapState();
}

class _PantallaPruebaPointTapState extends State<PantallaPruebaPointTap> {
  final _montoCtrl = TextEditingController(text: '100');
  Map<String, Object?>? _disponible;
  Map<String, Object?>? _respuesta;
  var _cobrando = false;

  @override
  void initState() {
    super.initState();
    disponibilidadPointTap().then((d) {
      if (mounted) setState(() => _disponible = d ?? {'error_canal': 'No es Android'});
    });
  }

  @override
  void dispose() {
    _montoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cobrar(String? tipo) async {
    int centavos;
    try {
      centavos = parsearARS(_montoCtrl.text);
    } on FormatException {
      mostrarAvisoNs(context, 'Escribí un monto');
      return;
    }
    if (centavos <= 0) return;
    setState(() {
      _cobrando = true;
      _respuesta = null;
    });
    final r = await cobrarConPointTap(montoCentavos: centavos, descripcion: 'Prueba Nodo Sur', tipo: tipo);
    if (mounted) {
      setState(() {
        _cobrando = false;
        _respuesta = r;
      });
    }
  }

  String _texto(Map<String, Object?> m) => [for (final e in m.entries) '${e.key}: ${e.value}'].join('\n');

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final d = _disponible;
    final r = _respuesta;
    return PaginaNs(
      titulo: 'Probar Point Tap',
      cuerpo: ListView(
        padding: EdgeInsets.zero,
        children: [
          const InfoNs(
            'Prueba para ver si se puede cobrar con tarjeta acercándola al celular, con la app de Mercado Pago. '
            'Cobra de verdad: usá tu tarjeta y devolvé el pago desde Mercado Pago. Mandale una captura del resultado a Claude.',
          ),
          const SizedBox(height: 14),
          Text('¿Está la app de Mercado Pago?', style: estiloNs(15, peso: FontWeight.w600, color: ns.mute)),
          const SizedBox(height: 6),
          SelectableText(d == null ? 'Revisando…' : _texto(d), style: estiloNs(15, altura: 1.4, color: ns.ink)),
          const SizedBox(height: 18),
          CampoNs(
            etiqueta: 'Monto de prueba',
            controller: _montoCtrl,
            teclado: TextInputType.number,
            formatos: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          ),
          const SizedBox(height: 12),
          BotonNs.primario(context, _cobrando ? 'Esperando a Mercado Pago…' : 'Cobrar con débito', _cobrando ? null : () => _cobrar('debit_card')),
          const SizedBox(height: 8),
          BotonNs.secundario(context, 'Cobrar con crédito', _cobrando ? null : () => _cobrar('credit_card')),
          const SizedBox(height: 8),
          BotonNs.secundario(context, 'Cobrar sin elegir tarjeta', _cobrando ? null : () => _cobrar(null)),
          if (r != null) ...[
            const SizedBox(height: 18),
            Text('Lo que contestó Mercado Pago', style: estiloNs(15, peso: FontWeight.w600, color: ns.mute)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(20)),
              child: SelectableText(r.isEmpty ? '(nada)' : _texto(r), style: estiloNs(15, altura: 1.4, color: ns.ink)),
            ),
            const SizedBox(height: 8),
            BotonNs.texto(context, 'Copiar el resultado', () async {
              await Clipboard.setData(ClipboardData(text: '${_texto(d ?? const {})}\n---\n${_texto(r)}'));
              if (context.mounted) mostrarAvisoNs(context, 'Copiado');
            }),
          ],
        ],
      ),
    );
  }
}

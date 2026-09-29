// Registrar el pago de lo separado a un proveedor (Regla 5 extendida). El
// monto no puede superar lo separado — no tiene sentido pagar más de lo que
// se armó para este proveedor, y "avisar antes que inventar" (no hay una
// regla de negocio que diga qué hacer con un excedente).
//
// Pasado al kit (corrección post-aprobación): `Modal` en vez de
// `AlertDialog`. "Separado: $X" es contexto, no el dato principal — va en
// `textoSecundario` para que el campo sea lo primero que salta.
//
// Lo separado viene dividido entre cajón y Mercado Pago (Bruno,
// 2026-09-26, `lib/domain/separacion_por_medio.dart`): dos campos, cada uno
// prellenado con su parte y editable (mismo criterio que "Retirar
// ganancia" en Reportes). Cada parte se registra por el medio del que sale
// — ver `pagarProveedor`.

import 'package:flutter/material.dart';

import '../../data/repositorio_reposicion.dart';
import '../../domain/dinero.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/modal.dart';
import '../comun/tarjetas.dart';
import '../tema/tokens.dart';

Future<void> mostrarDialogoPagarProveedor(
  BuildContext context, {
  required ResumenReposicionProveedor resumen,
  required AccionPagarProveedor onPagar,
}) {
  return mostrarModal<void>(
    context,
    builder: (context) =>
        _DialogoPagarProveedor(resumen: resumen, onPagar: onPagar),
  );
}

/// Lo que hace "Pagar" — el diálogo se usa desde Proveedores (Avanzado) y
/// desde Separaciones, cada una con su propio controlador.
typedef AccionPagarProveedor =
    Future<void> Function({
      required int montoCentavos,
      required int montoMpCentavos,
    });

class _DialogoPagarProveedor extends StatefulWidget {
  const _DialogoPagarProveedor({required this.resumen, required this.onPagar});

  final ResumenReposicionProveedor resumen;
  final AccionPagarProveedor onPagar;

  @override
  State<_DialogoPagarProveedor> createState() => _DialogoPagarProveedorState();
}

class _DialogoPagarProveedorState extends State<_DialogoPagarProveedor> {
  late final _efectivoCtrl = TextEditingController(
    text: _sinSigno(widget.resumen.separadoEfectivoCentavos),
  );
  late final _mpCtrl = TextEditingController(
    text: _sinSigno(widget.resumen.separadoMpCentavos),
  );
  String? _error;

  static String _sinSigno(int centavos) =>
      formatearARS(centavos).replaceAll('\$', '');

  Future<void> _confirmar() async {
    final int efectivo;
    final int mp;
    try {
      efectivo = _montoOCero(_efectivoCtrl.text);
      mp = _montoOCero(_mpCtrl.text);
    } on FormatException {
      setState(() => _error = 'Monto inválido');
      return;
    }
    if (efectivo < 0 || mp < 0) {
      setState(() => _error = 'Monto inválido');
      return;
    }
    if (efectivo + mp > widget.resumen.separadoCentavos) {
      setState(() => _error = 'No puede ser mayor a lo separado');
      return;
    }

    await widget.onPagar(montoCentavos: efectivo + mp, montoMpCentavos: mp);
    if (mounted) Navigator.of(context).pop();
  }

  /// Un campo vacío es "nada por este medio", no un error.
  int _montoOCero(String texto) => texto.trim().isEmpty ? 0 : parsearARS(texto);

  @override
  void dispose() {
    _efectivoCtrl.dispose();
    _mpCtrl.dispose();
    super.dispose();
  }

  // "Lenguaje de diseño" (mock `DialogosProveedores` → Registrar pago): los
  // dos medios lado a lado y, abajo, qué va a pasar con la plata mientras se
  // escribe. El mock traía fecha y nota/comprobante: el pago se registra en
  // el momento y la caja no guarda comprobantes, así que quedan afuera.
  @override
  Widget build(BuildContext context) {
    final r = widget.resumen;
    final colores = context.colores;
    int? leer(TextEditingController c) {
      try {
        return _montoOCero(c.text);
      } on FormatException {
        return null;
      }
    }

    final efectivo = leer(_efectivoCtrl) ?? 0;
    final mp = leer(_mpCtrl) ?? 0;
    final queda = r.separadoCentavos - efectivo - mp;
    return Modal(
      titulo: 'Registrar pago',
      subtitulo:
          '${r.proveedor.nombre} · separado ${formatearARS(r.separadoCentavos)}',
      ancho: 620,
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: CampoPlata(
                  key: const Key('campo_monto_pagado'),
                  controller: _efectivoCtrl,
                  etiqueta:
                      'Del cajón (separado ${formatearARS(r.separadoEfectivoCentavos)})',
                  autofocus: true,
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _confirmar(),
                ),
              ),
              const SizedBox(width: Espaciado.md),
              Expanded(
                child: CampoPlata(
                  key: const Key('campo_monto_pagado_mp'),
                  controller: _mpCtrl,
                  etiqueta:
                      'De Mercado Pago (separado ${formatearARS(r.separadoMpCentavos)})',
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _confirmar(),
                ),
              ),
            ],
          ),
          const SizedBox(height: Espaciado.md),
          BloqueSuave(
            child: Text(
              queda > 0
                  ? 'Se pagan ${formatearARS(efectivo + mp)}. Los ${formatearARS(queda)} que no pagás vuelven a pendiente sin separar.'
                  : 'Se pagan ${formatearARS(efectivo + mp)} y lo separado para ${r.proveedor.nombre} queda en \$0.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: Espaciado.sm),
            Text(_error!, style: TextStyle(color: colores.error)),
          ],
        ],
      ),
      botones: [
        BotonSecundario(
          texto: 'Cancelar',
          onPressed: () => Navigator.of(context).pop(),
        ),
        BotonPrimario(texto: 'Registrar pago', onPressed: _confirmar),
      ],
    );
  }
}

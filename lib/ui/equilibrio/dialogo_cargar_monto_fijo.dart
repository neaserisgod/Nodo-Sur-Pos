// Carga (o corrige) el monto de un concepto de fijo para el mes actual —
// nunca reescribe meses anteriores (mesAnio vive en el controlador, siempre
// es el mes que se está mostrando).

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../domain/dinero.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/modal.dart';
import '../tema/tokens.dart';
import 'equilibrio_controlador.dart';

Future<void> mostrarDialogoCargarMontoFijo(
  BuildContext context, {
  required GastoFijo concepto,
  required int? montoActualCentavos,
  required EquilibrioControlador controlador,
}) {
  return mostrarModal<void>(
    context,
    builder: (context) => _DialogoCargarMontoFijo(
      concepto: concepto,
      montoActualCentavos: montoActualCentavos,
      controlador: controlador,
    ),
  );
}

class _DialogoCargarMontoFijo extends StatefulWidget {
  const _DialogoCargarMontoFijo({
    required this.concepto,
    required this.montoActualCentavos,
    required this.controlador,
  });

  final GastoFijo concepto;
  final int? montoActualCentavos;
  final EquilibrioControlador controlador;

  @override
  State<_DialogoCargarMontoFijo> createState() => _DialogoCargarMontoFijoState();
}

class _DialogoCargarMontoFijoState extends State<_DialogoCargarMontoFijo> {
  late final _montoCtrl = TextEditingController(
    text: widget.montoActualCentavos == null ? '' : formatearARS(widget.montoActualCentavos!),
  );
  String? _error;

  Future<void> _guardar() async {
    final int monto;
    try {
      monto = parsearARS(_montoCtrl.text);
    } on FormatException {
      setState(() => _error = 'Monto inválido');
      return;
    }
    if (monto <= 0) {
      setState(() => _error = 'El monto tiene que ser mayor a cero');
      return;
    }

    await widget.controlador.cargarMonto(gastoFijoId: widget.concepto.id, montoCentavos: monto);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _montoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Modal(
      titulo: '${widget.concepto.nombre} — ${widget.controlador.mesAnio}',
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CampoPlata(
            key: const Key('campo_monto_fijo'),
            controller: _montoCtrl,
            etiqueta: 'Monto de este mes',
            autofocus: true,
            onSubmitted: (_) => _guardar(),
          ),
          if (_error != null) ...[
            const SizedBox(height: Espaciado.sm),
            Text(_error!, style: TextStyle(color: context.colores.error)),
          ],
        ],
      ),
      botones: [
        BotonSecundario(texto: 'Cancelar', onPressed: () => Navigator.of(context).pop()),
        BotonPrimario(texto: 'Guardar', onPressed: _guardar),
      ],
    );
  }
}

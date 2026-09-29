import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../domain/dinero.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/modal.dart';
import '../tema/tokens.dart';
import 'equilibrio_controlador.dart';

Future<void> mostrarDialogoRegistrarPagoFijo(
  BuildContext context, {
  required GastoFijo concepto,
  required int sugeridoCentavos,
  required EquilibrioControlador controlador,
}) {
  return mostrarModal<void>(
    context,
    builder: (context) => _DialogoRegistrarPagoFijo(
      concepto: concepto,
      sugeridoCentavos: sugeridoCentavos,
      controlador: controlador,
    ),
  );
}

class _DialogoRegistrarPagoFijo extends StatefulWidget {
  const _DialogoRegistrarPagoFijo({
    required this.concepto,
    required this.sugeridoCentavos,
    required this.controlador,
  });

  final GastoFijo concepto;
  final int sugeridoCentavos;
  final EquilibrioControlador controlador;

  @override
  State<_DialogoRegistrarPagoFijo> createState() => _DialogoRegistrarPagoFijoState();
}

class _DialogoRegistrarPagoFijoState extends State<_DialogoRegistrarPagoFijo> {
  late final _montoCtrl = TextEditingController(text: formatearARS(widget.sugeridoCentavos));
  late final _fechaCtrl = TextEditingController(text: _formatearFecha(DateTime.now()));
  bool _pagadoConMp = false;
  String? _error;

  Future<void> _confirmar() async {
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
    final fecha = _parsearFecha(_fechaCtrl.text);
    if (fecha == null) {
      setState(() => _error = 'Fecha inválida');
      return;
    }

    await widget.controlador.registrarPago(
      gastoFijoId: widget.concepto.id,
      montoCentavos: monto,
      pagadoConMp: _pagadoConMp,
      fecha: fecha,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _montoCtrl.dispose();
    _fechaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Modal(
      titulo: 'Registrar pago — ${widget.concepto.nombre}',
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CampoPlata(
            key: const Key('campo_monto_pago_fijo'),
            controller: _montoCtrl,
            etiqueta: 'Monto pagado',
            autofocus: true,
            onSubmitted: (_) => _confirmar(),
          ),
          const SizedBox(height: Espaciado.md),
          CampoTexto(
            key: const Key('campo_fecha_pago_fijo'),
            controller: _fechaCtrl,
            etiqueta: 'Fecha del pago (DD/MM/AAAA)',
            onSubmitted: (_) => _confirmar(),
          ),
          const SizedBox(height: Espaciado.sm),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Pagado con Mercado Pago'),
            value: _pagadoConMp,
            onChanged: (v) => setState(() => _pagadoConMp = v ?? false),
          ),
          if (_error != null) ...[
            const SizedBox(height: Espaciado.sm),
            Text(_error!, style: TextStyle(color: context.colores.error)),
          ],
        ],
      ),
      botones: [
        BotonSecundario(texto: 'Cancelar', onPressed: () => Navigator.of(context).pop()),
        BotonPrimario(texto: 'Registrar', onPressed: _confirmar),
      ],
    );
  }
}

// Mismo parseo/formato que la carga histórica (`pantalla_carga_historica.dart`).
DateTime? _parsearFecha(String texto) {
  final partes = texto.split('/');
  if (partes.length != 3) return null;
  final dia = int.tryParse(partes[0]);
  final mes = int.tryParse(partes[1]);
  final anio = int.tryParse(partes[2]);
  if (dia == null || mes == null || anio == null) return null;
  return DateTime(anio, mes, dia);
}

String _formatearFecha(DateTime f) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(f.day)}/${dos(f.month)}/${f.year}';
}

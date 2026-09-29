import 'package:flutter/material.dart';

import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/modal.dart';
import '../tema/tokens.dart';
import 'equilibrio_controlador.dart';

Future<void> mostrarDialogoNuevoConceptoFijo(BuildContext context, EquilibrioControlador controlador) {
  return mostrarModal<void>(
    context,
    builder: (context) => _DialogoNuevoConceptoFijo(controlador: controlador),
  );
}

class _DialogoNuevoConceptoFijo extends StatefulWidget {
  const _DialogoNuevoConceptoFijo({required this.controlador});

  final EquilibrioControlador controlador;

  @override
  State<_DialogoNuevoConceptoFijo> createState() => _DialogoNuevoConceptoFijoState();
}

class _DialogoNuevoConceptoFijoState extends State<_DialogoNuevoConceptoFijo> {
  final _nombreCtrl = TextEditingController();
  String? _error;

  Future<void> _confirmar() async {
    if (_nombreCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Falta el nombre');
      return;
    }
    await widget.controlador.agregarConcepto(_nombreCtrl.text.trim());
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Modal(
      titulo: 'Nuevo concepto de fijo',
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CampoTexto(
            key: const Key('campo_nombre_concepto'),
            controller: _nombreCtrl,
            etiqueta: 'Nombre',
            autofocus: true,
            onSubmitted: (_) => _confirmar(),
          ),
          if (_error != null) ...[
            const SizedBox(height: Espaciado.sm),
            Text(_error!, style: TextStyle(color: context.colores.error)),
          ],
        ],
      ),
      botones: [
        BotonSecundario(texto: 'Cancelar', onPressed: () => Navigator.of(context).pop()),
        BotonPrimario(texto: 'Agregar', onPressed: _confirmar),
      ],
    );
  }
}

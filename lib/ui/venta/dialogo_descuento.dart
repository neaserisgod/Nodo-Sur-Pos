// "Descuento" del mock v4 (`M.descuento` en `p4_venta.js`): sobre el total de la venta entera, nunca por línea
// (Regla 17). Porcentaje o monto, el número grande, atajos de porcentaje y la cuenta de cómo queda.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/descuento.dart';
import '../kit/kit.dart';
import 'venta_controlador.dart';

Future<void> mostrarDialogoDescuento(BuildContext context, VentaControlador c) async {
  // Lo que había al abrir: cerrar sin aplicar (Esc, la cruz, tocar afuera) lo deja como estaba.
  final texto = c.campoDescuentoCtrl.text;
  final tipo = c.tipoDescuento;
  final aplicado = await mostrarModalMock<bool>(context, builder: (_) => _DialogoDescuento(c: c));
  if (aplicado != true) {
    c.campoDescuentoCtrl.text = texto;
    c.elegirTipoDescuento(tipo);
  }
  c.focoCampoPrincipal.requestFocus();
}

class _DialogoDescuento extends StatefulWidget {
  const _DialogoDescuento({required this.c});
  final VentaControlador c;

  @override
  State<_DialogoDescuento> createState() => _DialogoDescuentoState();
}

class _DialogoDescuentoState extends State<_DialogoDescuento> {
  VentaControlador get c => widget.c;

  @override
  void initState() {
    super.initState();
    c.campoDescuentoCtrl.addListener(_refrescar);
    // Seleccionado entero para escribir encima; después del primer cuadro (cambiar la selección avisa al controlador).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) c.campoDescuentoCtrl.selection = TextSelection(baseOffset: 0, extentOffset: c.campoDescuentoCtrl.text.length);
    });
  }

  void _refrescar() => setState(() {});

  @override
  void dispose() {
    c.campoDescuentoCtrl.removeListener(_refrescar);
    super.dispose();
  }

  void _aplicar() => Navigator.of(context).pop(true);

  void _quitar() {
    c.campoDescuentoCtrl.clear();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final porcentaje = c.tipoDescuento == TipoDescuento.porcentaje;
    final base = c.subtotalCentavos;
    final descuento = c.descuentoSobreSubtotalCentavos;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.enter): _aplicar},
      child: ModalMock(
        titulo: 'Descuento',
        subtitulo: 'Sobre el total de la venta entera, nunca por línea.',
        cuerpo: [
          Seg<TipoDescuento>(
            llenar: true,
            opciones: const [(TipoDescuento.porcentaje, 'Porcentaje %'), (TipoDescuento.monto, r'Monto $')],
            valor: c.tipoDescuento,
            onCambio: (t) => setState(() => c.elegirTipoDescuento(t)),
          ),
          Campo(
            etiqueta: porcentaje ? 'Porcentaje' : 'Monto',
            campoKey: const Key('campo_descuento'),
            controller: c.campoDescuentoCtrl,
            pista: porcentaje ? '0 %' : r'$ 0',
            grande: true,
            autofocus: true,
            teclado: const TextInputType.numberWithOptions(decimal: true),
            onSubmitted: (_) => _aplicar(),
          ),
          if (porcentaje)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in const [5, 10, 15, 20, 30])
                  ChipMock(
                    '$v %',
                    chico: true,
                    elegido: c.campoDescuentoCtrl.text.trim() == '$v',
                    onTap: () => c.campoDescuentoCtrl.text = '$v',
                  ),
              ],
            ),
          Lista(filas: [
            Kv('Subtotal', pesos(base)),
            Kv('Descuento', '−${pesos(descuento)}'),
            Kv('Total con descuento', pesos(base - descuento), tamanioValor: 24, colorValor: p.tinta),
          ]),
        ],
        pie: [
          Btn('Aplicar descuento', variante: VarBtn.blue, tam: TamBtn.lg, ancho: true, onTap: _aplicar),
          Btn('Quitar descuento', variante: VarBtn.out, ancho: true, onTap: _quitar),
        ],
      ),
    );
  }
}

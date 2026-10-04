// "Tarjeta" (etapa C, el dueño 2026-10-04): un solo botón en la pantalla de venta que pregunta Débito o Crédito. Crédito
// siempre en 1 pago y sin recargo: Mercado Pago solo deja limitar las cuotas si la orden es de crédito, así que el cajero elige
// acá en vez de dejar que el cliente elija en la terminal (ahí podría elegir cuotas). Teclas D y C, locales a este diálogo.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/cobro_posnet.dart';
import '../comun/botones.dart';
import '../comun/modal.dart';
import '../tema/tokens.dart';
import 'venta_controlador.dart';

Future<void> elegirTarjeta(BuildContext context, VentaControlador c) async {
  final canal = await mostrarModal<String>(context, builder: (context) => const _ElegirTarjeta());
  if (canal == null) return;
  c.elegirCanalDirecto(canal);
  c.focoCampoPrincipal.requestFocus();
}

class _ElegirTarjeta extends StatelessWidget {
  const _ElegirTarjeta();

  @override
  Widget build(BuildContext context) {
    void elegir(String canal) => Navigator.of(context).pop(canal);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyD): () => elegir(canalDebito),
        const SingleActivator(LogicalKeyboardKey.keyC): () => elegir(canalCredito),
      },
      child: Focus(
        autofocus: true,
        child: Modal(
          titulo: 'Cobrar con tarjeta',
          contenido: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BotonPrimario(key: const Key('tarjeta_debito'), texto: 'Débito (D)', onPressed: () => elegir(canalDebito)),
              const SizedBox(height: Espaciado.sm),
              BotonPrimario(key: const Key('tarjeta_credito'), texto: 'Crédito, 1 pago (C)', onPressed: () => elegir(canalCredito)),
              const SizedBox(height: Espaciado.sm),
              Text('El crédito va siempre en un pago y sin recargo.', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          botones: [BotonSecundario(texto: 'Cancelar', onPressed: () => Navigator.of(context).pop())],
        ),
      ),
    );
  }
}

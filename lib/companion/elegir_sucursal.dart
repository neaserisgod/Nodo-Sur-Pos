// Quien trabaja en más de una sucursal (o negocio) elige en cuál entra este celular, al entrar con Google desde la app. Antes lo
// elegía en la página /vincular/ del sitio; sin navegador, se pregunta acá con las mismas opciones que daba el sitio.

import 'package:flutter/material.dart';

import '../servicios/cuenta_nube.dart' show SucursalParaElegir;
import 'kit/kit_ns.dart';

/// Null si cierra la hoja sin elegir.
Future<SucursalParaElegir?> elegirSucursal(BuildContext context, List<SucursalParaElegir> opciones) {
  // El nombre del negocio solo hace falta si hay más de uno.
  final variosNegocios = opciones.map((o) => o.negocio).toSet().length > 1;
  return mostrarHojaNs<SucursalParaElegir>(
    context,
    builder: (ctx) => HojaNs(
      titulo: '¿En qué sucursal trabajás con este celular?',
      texto: 'Para que el celular y la PC se vean entre sí, tienen que estar en la misma sucursal.',
      // Las sucursales van en los bloques, que se deslizan: un negocio con muchas no empuja "Cancelar" fuera de la pantalla.
      bloques: [
        for (final o in opciones)
          BotonNs.secundario(
            ctx,
            variosNegocios ? '${o.nombreNegocio} · ${o.nombreSucursal}' : o.nombreSucursal,
            () => Navigator.of(ctx).pop(o),
          ),
      ],
      botones: [
        BotonNs.secundario(ctx, 'Cancelar', () => Navigator.of(ctx).pop()),
      ],
    ),
  );
}

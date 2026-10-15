// "Entrar en una compu" desde el celular (El dueño, 2026-10-15: "la vinculación sigue siendo por navegador"): Nodo Sur Servicios
// de Windows muestra un QR al entrar; con el celular ya vinculado se escanea, se ve qué equipo es y se confirma. La compu entra
// sola, en el negocio y la sucursal de este celular (sitio: `functions/api/device/qr.js`).

import 'package:flutter/material.dart';

import '../servicios/cuenta_nube.dart';
import 'escanear_codigo.dart';
import 'kit/kit_ns.dart';
import 'mensaje_error.dart';
import 'sync_nube_companion.dart';

/// El número del pedido que trae el QR de la compu (`https://horsepos.com/vincular/qr/?p=<32 hex>`). Null si el código
/// escaneado es otra cosa: un código de barras, un QR viejo de otra pantalla. El sitio del QR no se visita nunca (se aprueba
/// con el sitio de siempre de la app), así que no importa cuál diga: solo el número.
String? pedidoDeQr(String texto) {
  final url = Uri.tryParse(texto.trim());
  if (url == null || !url.isScheme('https') || url.path != '/vincular/qr/') return null;
  final p = url.queryParameters['p'];
  return p != null && RegExp(r'^[0-9a-f]{32}$').hasMatch(p) ? p : null;
}

/// Abre la cámara, muestra qué compu está por entrar y, si se confirma, la aprueba. Devuelve el aviso para mostrar (o null si se
/// canceló).
Future<String?> entrarEnUnaCompu(BuildContext context, {required SyncNubeCompanion sync}) async {
  final texto = await escanearCodigo(context);
  if (texto == null || !context.mounted) return null;
  final pedido = pedidoDeQr(texto);
  if (pedido == null) return 'Ese no es el código de una compu. Apuntá al QR que muestra Nodo Sur Servicios al entrar.';
  final cuenta = await sync.cuenta();
  if (cuenta == null) return 'Primero entrá con tu cuenta en este celular.';
  try {
    final nombre = await sync.cliente.verQr(cuenta.token, pedido);
    if (!context.mounted) return null;
    final ok = await mostrarHojaNs<bool>(
      context,
      builder: (ctx) => HojaNs(
        titulo: '¿Entrar en la compu?',
        texto: 'Vas a entrar en «$nombre» con tu cuenta, en tu negocio. Lo que se haga desde esa compu queda a tu nombre.\n\n'
            'Hacelo solo si tenés esa compu adelante.',
        botones: [
          BotonNs.primario(ctx, 'Entrar', () => Navigator.of(ctx).pop(true), icono: IconoNs.computadora),
          BotonNs.secundario(ctx, 'Cancelar', () => Navigator.of(ctx).pop(false)),
        ],
      ),
    );
    if (ok != true) return null;
    await sync.cliente.aprobarQr(cuenta.token, pedido);
    return 'Listo: la compu entra sola en unos segundos';
  } on ErrorNube catch (e) {
    return e.mensaje;
  } catch (e) {
    return mensajeDeError(e);
  }
}

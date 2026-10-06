// "Pedir por WhatsApp" (rediseño v4, 2026-10-06): abre el chat del proveedor con lo que está bajo el mínimo ya escrito. No manda
// nada solo: el dueño ve el mensaje en WhatsApp, le pone las cantidades y aprieta enviar.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/repositorio_configuracion.dart';
import '../../domain/pedido_whatsapp.dart';
import '../comun/aviso_superior.dart';
import 'dialogo_avanzado_proveedor.dart';
import 'proveedores_controlador.dart';

/// Los tests lo reemplazan para no abrir nada de verdad. Por defecto abre el link afuera de la app (navegador o WhatsApp de escritorio).
@visibleForTesting
Future<bool> Function(Uri url)? abrirUrlParaTests;

Future<void> pedirPorWhatsApp(BuildContext context, ProveedoresControlador c) async {
  final proveedor = c.seleccionado;
  if (proveedor == null) return;

  final numero = normalizarWhatsapp(proveedor.whatsapp ?? '');
  if (numero == null) {
    mostrarAviso(
      context,
      'Cargale el WhatsApp a ${proveedor.nombre}',
      textoAccion: 'Cargar',
      alAccionar: () => mostrarDialogoAvanzadoProveedor(context, proveedor: proveedor, controlador: c),
    );
    return;
  }

  final lineas = c.lineasParaPedir;
  if (lineas.isEmpty) {
    mostrarAviso(context, 'No hay nada con stock bajo para pedirle a ${proveedor.nombre}');
    return;
  }

  final comercio = (await configuracionNegocioActual(c.db)).nombreComercio;
  if (!context.mounted) return;
  final url = urlWhatsapp(numero, armarMensajePedido(proveedor: proveedor.nombre, comercio: comercio, lineas: lineas));
  final abierto = await (abrirUrlParaTests ?? (u) => launchUrl(u, mode: LaunchMode.externalApplication))(url);
  if (!abierto && context.mounted) mostrarAviso(context, 'No se pudo abrir WhatsApp');
}

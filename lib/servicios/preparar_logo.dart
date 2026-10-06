// Prepara el logo que el dueño elige para el ticket (rediseño v4, 2026-10-06): lo achica, lo pasa a escala de grises y lo
// deja sobre fondo blanco, que es lo que se imprime bien en papel de ticket y lo que pesa poco en la base.

import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Ancho máximo en píxeles: el ticket mide ~58 mm, alcanza de sobra y no hace pesada la base.
const anchoMaximoLogoTicket = 384;

/// Devuelve un PNG listo para guardar, o null si [bytes] no es una imagen que se pueda abrir.
Uint8List? prepararLogoTicket(Uint8List bytes) {
  final img.Image? original;
  try {
    original = img.decodeImage(bytes);
  } catch (_) {
    // Con un archivo que no es una imagen algunos decodificadores tiran en vez de devolver null.
    return null;
  }
  if (original == null) return null;

  var logo = img.bakeOrientation(original);
  if (logo.width > anchoMaximoLogoTicket) {
    logo = img.copyResize(logo, width: anchoMaximoLogoTicket);
  }

  // Lo transparente pasa a blanco: apoyado sobre un lienzo blanco, en vez de quedar negro al sacarle el canal alfa.
  final lienzo = img.Image(width: logo.width, height: logo.height, numChannels: 3);
  img.fill(lienzo, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(lienzo, logo);
  return Uint8List.fromList(img.encodePng(img.grayscale(lienzo)));
}

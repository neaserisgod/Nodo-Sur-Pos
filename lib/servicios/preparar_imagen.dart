// Achica la foto de una factura antes de mandarla a Gemini (El dueño, 2026-10-05: "las fotos que saco a las facturas son demasiado
// pesadas"). Una foto de celular pesa 5 a 10 MB; para leer una factura alcanza con ~2000 px de largo y calidad media (200 a 500 KB).
// Gemini cobra por tamaño en píxeles, no en MB, pero un pedido no puede pasar de 20 MB y subir 10 MB por cada hoja es lento.
//
// Respeta la orientación EXIF (una foto "de costado" del celular suele ser una foto derecha con una marca de giro). Los PDF no se tocan:
// Gemini los lee tal cual.

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'gemini.dart';

/// Largo máximo (el lado más largo) al que se achica una foto.
const ladoMaximoFotoFactura = 2000;

/// Calidad JPEG de la foto achicada.
const calidadJpegFactura = 85;

/// Devuelve la foto achicada y en JPEG, o null si [bytes] no es una imagen que se pueda abrir.
/// Una foto que ya es más chica que [ladoMaximo] no se agranda; solo se vuelve a guardar derecha y en JPEG.
Uint8List? achicarFotoDeFactura(Uint8List bytes, {int ladoMaximo = ladoMaximoFotoFactura, int calidad = calidadJpegFactura}) {
  final img.Image? original;
  try {
    original = img.decodeImage(bytes);
  } catch (_) {
    // Con un archivo que no es una imagen algunos decodificadores tiran en vez de devolver null.
    return null;
  }
  if (original == null) return null;
  // Aplica el giro EXIF y lo deja derecho.
  var foto = img.bakeOrientation(original);
  final mayor = foto.width > foto.height ? foto.width : foto.height;
  if (mayor > ladoMaximo) {
    foto = foto.width >= foto.height ? img.copyResize(foto, width: ladoMaximo) : img.copyResize(foto, height: ladoMaximo);
  }
  return Uint8List.fromList(img.encodeJpg(foto, quality: calidad));
}

/// Prepara un archivo elegido por el dueño para mandarlo: un PDF va tal cual; una foto se achica (en otro hilo, para no trabar la
/// pantalla con una foto de 12 megapíxeles). Null si no es ni PDF ni una imagen legible.
Future<AdjuntoGemini?> prepararArchivoDeFactura(String nombre, Uint8List bytes) async {
  final n = nombre.toLowerCase();
  if (n.endsWith('.pdf')) return AdjuntoGemini('application/pdf', bytes);
  final achicada = await compute(_achicar, bytes);
  return achicada == null ? null : AdjuntoGemini('image/jpeg', achicada);
}

Uint8List? _achicar(Uint8List bytes) => achicarFotoDeFactura(bytes);

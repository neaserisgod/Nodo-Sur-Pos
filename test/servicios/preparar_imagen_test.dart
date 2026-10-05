import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:la_plazoleta/servicios/preparar_imagen.dart';

/// Una "foto" con ruido (como una foto real: no se comprime tanto como un color liso).
Uint8List foto(int ancho, int alto, {int? orientacionExif}) {
  final imagen = img.Image(width: ancho, height: alto);
  var semilla = 12345;
  for (final p in imagen) {
    semilla = (semilla * 1103515245 + 12345) & 0x7fffffff;
    p
      ..r = semilla & 255
      ..g = (semilla >> 8) & 255
      ..b = (semilla >> 16) & 255;
  }
  if (orientacionExif != null) imagen.exif.imageIfd.orientation = orientacionExif;
  return Uint8List.fromList(img.encodeJpg(imagen, quality: 100));
}

void main() {
  test('una foto grande se achica al lado máximo, sin deformarla', () {
    final original = foto(2400, 1800);
    final chica = achicarFotoDeFactura(original, ladoMaximo: 1000)!;
    final r = img.decodeJpg(chica)!;
    expect(r.width, 1000);
    expect(r.height, 750);
    expect(chica.length, lessThan(original.length));
  });

  test('una foto vertical se achica por su lado largo (el alto)', () {
    final r = img.decodeJpg(achicarFotoDeFactura(foto(1200, 1800), ladoMaximo: 900)!)!;
    expect(r.height, 900);
    expect(r.width, 600);
  });

  test('una foto que ya es chica no se agranda', () {
    final r = img.decodeJpg(achicarFotoDeFactura(foto(800, 600), ladoMaximo: 2000)!)!;
    expect(r.width, 800);
    expect(r.height, 600);
  });

  test('respeta el giro del celular (EXIF): una foto marcada "girada 90°" sale derecha', () {
    // 300 de ancho × 200 de alto con la marca de girar 90° → tiene que quedar de 200 × 300.
    final r = img.decodeJpg(achicarFotoDeFactura(foto(300, 200, orientacionExif: 6))!)!;
    expect(r.width, 200);
    expect(r.height, 300);
  });

  test('algo que no es una imagen devuelve null (no tira)', () {
    expect(achicarFotoDeFactura(Uint8List.fromList([1, 2, 3, 4])), isNull);
  });

  test('una foto de celular de 3000 × 2250 queda en el tamaño de lectura y mucho más liviana', () {
    // Una hoja: fondo claro con renglones oscuros (no ruido, que no se parece a una factura).
    final hoja = img.Image(width: 3000, height: 2250);
    for (final p in hoja) {
      final renglon = (p.y % 30) < 3;
      final v = renglon ? 40 : 235 - (p.x ~/ 60);
      p
        ..r = v
        ..g = v
        ..b = v;
    }
    final original = Uint8List.fromList(img.encodeJpg(hoja, quality: 98));
    final chica = achicarFotoDeFactura(original)!;
    final r = img.decodeJpg(chica)!;
    expect(r.width, ladoMaximoFotoFactura);
    expect(chica.length, lessThan(500 * 1024));
    expect(chica.length, lessThan(original.length ~/ 2));
  });

  group('prepararArchivoDeFactura', () {
    test('un PDF va tal cual', () async {
      final pdf = Uint8List.fromList([37, 80, 68, 70]);
      final a = await prepararArchivoDeFactura('Factura.PDF', pdf);
      expect(a!.mimeType, 'application/pdf');
      expect(identical(a.bytes, pdf), isTrue);
    });

    test('una foto se achica y sale como JPEG', () async {
      final a = await prepararArchivoDeFactura('IMG_001.jpg', foto(300, 200));
      expect(a!.mimeType, 'image/jpeg');
    });

    test('un archivo que no es ni PDF ni imagen devuelve null', () async {
      expect(await prepararArchivoDeFactura('notas.txt', Uint8List.fromList([1, 2, 3])), isNull);
    });
  });
}

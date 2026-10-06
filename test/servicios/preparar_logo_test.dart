// Logo del ticket (rediseño v4, etapa 8.3): se achica y se pasa a blanco y negro, que es lo que se imprime bien en un ticket.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:la_plazoleta/servicios/preparar_logo.dart';

Uint8List _png(int ancho, int alto, {img.Color? color, int alfa = 255}) {
  final imagen = img.Image(width: ancho, height: alto, numChannels: 4);
  img.fill(imagen, color: color ?? img.ColorRgba8(200, 30, 30, alfa));
  return Uint8List.fromList(img.encodePng(imagen));
}

void main() {
  test('una imagen grande se achica al ancho máximo sin deformarse', () {
    final salida = prepararLogoTicket(_png(1200, 600))!;
    final logo = img.decodePng(salida)!;
    expect(logo.width, anchoMaximoLogoTicket);
    expect(logo.height, anchoMaximoLogoTicket ~/ 2);
  });

  test('una imagen chica no se agranda', () {
    final logo = img.decodePng(prepararLogoTicket(_png(100, 50))!)!;
    expect(logo.width, 100);
    expect(logo.height, 50);
  });

  test('queda en escala de grises', () {
    final logo = img.decodePng(prepararLogoTicket(_png(40, 40))!)!;
    final p = logo.getPixel(10, 10);
    expect(p.r, p.g);
    expect(p.g, p.b);
  });

  test('lo transparente queda blanco (en el ticket no hay fondo)', () {
    final logo = img.decodePng(prepararLogoTicket(_png(40, 40, alfa: 0))!)!;
    final p = logo.getPixel(10, 10);
    expect(p.r, 255);
  });

  test('algo que no es una imagen devuelve null', () {
    expect(prepararLogoTicket(Uint8List.fromList([1, 2, 3, 4])), isNull);
  });
}

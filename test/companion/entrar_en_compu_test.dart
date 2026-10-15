import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/entrar_en_compu.dart';

void main() {
  final p = 'a1' * 16;

  test('lee el número del pedido del QR de la compu', () {
    expect(pedidoDeQr('https://horsepos.com/vincular/qr/?p=$p'), p);
    expect(pedidoDeQr('  https://otro.dominio/vincular/qr/?p=$p\n'), p);
  });

  test('cualquier otra cosa no es un QR de compu', () {
    for (final malo in [
      '7790001234567',
      'http://horsepos.com/vincular/qr/?p=$p',
      'https://horsepos.com/vincular/?p=$p',
      'https://horsepos.com/vincular/qr/?p=xyz',
      'https://horsepos.com/vincular/qr/?p=${p.toUpperCase()}',
      'https://horsepos.com/vincular/qr/',
    ]) {
      expect(pedidoDeQr(malo), isNull, reason: malo);
    }
  });
}

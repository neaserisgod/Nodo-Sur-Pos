import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/buscar_pc.dart';

void main() {
  test('candidatas: la red privada del celular, sin la propia, con la última PC conocida primero', () {
    final c = candidatasPc(['192.168.0.57', '100.64.1.2'], preferida: '192.168.0.23');
    expect(c.first, '192.168.0.23');
    expect(c, isNot(contains('192.168.0.57')));
    expect(c.where((ip) => ip.startsWith('192.168.0.')).length, 253, reason: 'las 254 menos la del propio celular');
    expect(c.any((ip) => ip.startsWith('100.64.')), isFalse, reason: 'no es una red de local');
  });

  test('encuentra la PC entre todas las de la red', () async {
    final probadas = <String>[];
    final ip = await buscarPcEnElWifi(
      misDirecciones: () async => ['10.0.0.9'],
      probar: (ip, puerto) async {
        probadas.add(ip);
        return ip == '10.0.0.200';
      },
    );
    expect(ip, '10.0.0.200');
    expect(probadas.length, lessThan(254), reason: 'corta apenas la encuentra');
  });

  test('sin PC en la red devuelve null', () async {
    expect(await buscarPcEnElWifi(misDirecciones: () async => ['192.168.1.4'], probar: (_, _) async => false), isNull);
  });
}

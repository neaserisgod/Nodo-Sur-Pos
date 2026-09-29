import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/ajuste_a_disponible.dart';

ParteSeparacion _p(int efectivo, int mp) => ParteSeparacion(efectivoCentavos: efectivo, mpCentavos: mp);

void main() {
  test('si alcanza en las dos cajas, no cambia nada', () {
    final r = ajustarADisponible(
      partes: {'a': _p(6000, 3000)},
      efectivoDisponibleCentavos: 10000,
      mpDisponibleCentavos: 5000,
    );
    expect(r.partes['a'], _p(6000, 3000));
    expect(r.corridoAMpCentavos, 0);
    expect(r.faltanteCentavos, 0);
  });

  test('falta efectivo y sobra en MP: lo que falta pasa a MP', () {
    final r = ajustarADisponible(
      partes: {'a': _p(6000, 1000)},
      efectivoDisponibleCentavos: 4000,
      mpDisponibleCentavos: 10000,
    );
    expect(r.partes['a'], _p(4000, 3000));
    expect(r.corridoAMpCentavos, 2000);
    expect(r.faltanteCentavos, 0);
  });

  test('falta en MP y sobra efectivo: lo que falta pasa al cajón', () {
    final r = ajustarADisponible(
      partes: {'a': _p(1000, 5000)},
      efectivoDisponibleCentavos: 10000,
      mpDisponibleCentavos: 2000,
    );
    expect(r.partes['a'], _p(4000, 2000));
    expect(r.corridoAMpCentavos, -3000);
  });

  test('lo corrido se reparte en proporción a lo que cada uno tenía de ese lado', () {
    final r = ajustarADisponible(
      partes: {'a': _p(6000, 0), 'b': _p(3000, 0)},
      efectivoDisponibleCentavos: 6000,
      mpDisponibleCentavos: 10000,
    );
    expect(r.partes['a'], _p(4000, 2000));
    expect(r.partes['b'], _p(2000, 1000));
  });

  test('el total de cada proveedor nunca cambia, y la suma es exacta aunque la división no lo sea', () {
    final partes = {'a': _p(3333, 0), 'b': _p(3333, 0), 'c': _p(3334, 0)};
    final r = ajustarADisponible(partes: partes, efectivoDisponibleCentavos: 9000, mpDisponibleCentavos: 5000);
    for (final k in partes.keys) {
      expect(r.partes[k]!.totalCentavos, partes[k]!.totalCentavos);
    }
    expect(r.partes.values.fold<int>(0, (a, p) => a + p.mpCentavos), 1000);
  });

  test('si no alcanza ni moviendo, corre lo que puede y avisa cuánto falta', () {
    final r = ajustarADisponible(
      partes: {'a': _p(8000, 1000)},
      efectivoDisponibleCentavos: 3000,
      mpDisponibleCentavos: 2000,
    );
    expect(r.partes['a'], _p(7000, 2000));
    expect(r.corridoAMpCentavos, 1000);
    expect(r.faltanteCentavos, 4000); // 9.000 pedidos, 5.000 en las dos cajas
  });

  test('si faltan las dos, no mueve nada y suma los dos faltantes', () {
    final r = ajustarADisponible(
      partes: {'a': _p(5000, 5000)},
      efectivoDisponibleCentavos: 3000,
      mpDisponibleCentavos: 1000,
    );
    expect(r.partes['a'], _p(5000, 5000));
    expect(r.faltanteCentavos, 6000);
  });

  test('un disponible negativo (ya separado más de lo que hay) cuenta como 0', () {
    final r = ajustarADisponible(
      partes: {'a': _p(1000, 0)},
      efectivoDisponibleCentavos: -500,
      mpDisponibleCentavos: 5000,
    );
    expect(r.partes['a'], _p(0, 1000));
    expect(r.faltanteCentavos, 0);
  });
}

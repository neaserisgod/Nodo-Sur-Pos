import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/separacion_por_medio.dart';

LineaParaSeparacion _producto(int id, {required int costo, required int precio, bool conProveedor = true}) =>
    LineaParaSeparacion(
      lineaId: id,
      esCigarrillo: false,
      costoLineaCentavos: costo,
      precioLineaCentavos: precio,
      tieneProveedor: conProveedor,
    );

LineaParaSeparacion _atado(int id, {required int lista}) => LineaParaSeparacion(
      lineaId: id,
      esCigarrillo: true,
      costoLineaCentavos: lista,
      precioLineaCentavos: lista,
      tieneProveedor: true,
    );

VentaParaSeparacion _venta(
  List<LineaParaSeparacion> lineas, {
  int sesion = 1,
  int efectivo = 0,
  int mp = 0,
}) =>
    VentaParaSeparacion(sesionId: sesion, efectivoCentavos: efectivo, mpCentavos: mp, lineas: lineas);

void main() {
  group('paso 1 — cada costo se separa del medio en que se cobró', () {
    test('venta 100% efectivo: nada va a MP', () {
      final r = parteMpPorLinea([
        _venta([_producto(1, costo: 60000, precio: 100000)], efectivo: 100000),
      ]);
      expect(r[1]!.costoMpCentavos, 0);
    });

    test('venta 100% MP: todo su costo va a MP', () {
      final r = parteMpPorLinea([
        _venta([_producto(1, costo: 60000, precio: 100000)], mp: 100000),
      ]);
      expect(r[1]!.costoMpCentavos, 60000);
    });

    test('mixto sin cigarrillos: a prorrata de lo cobrado por MP', () {
      final r = parteMpPorLinea([
        _venta([_producto(1, costo: 60000, precio: 100000)], efectivo: 75000, mp: 25000),
      ]);
      expect(r[1]!.costoMpCentavos, 15000); // 25% de 60.000
    });

    test('100% MP con descuento: sigue siendo todo MP (el descuento no deja parte en efectivo)', () {
      final r = parteMpPorLinea([
        _venta([_producto(1, costo: 60000, precio: 100000)], mp: 90000),
      ]);
      expect(r[1]!.costoMpCentavos, 60000);
    });

    test('cigarrillos y líneas sin costo no aparecen; sin proveedor sí, solo con cómo se cobró', () {
      final r = parteMpPorLinea([
        _venta(
          [
            _atado(1, lista: 400000),
            const LineaParaSeparacion(
              lineaId: 2,
              esCigarrillo: false,
              costoLineaCentavos: null,
              precioLineaCentavos: 50000,
              tieneProveedor: false,
            ),
            _producto(3, costo: 10000, precio: 20000, conProveedor: false),
          ],
          efectivo: 470000,
        ),
      ]);
      expect(r.keys, [3]);
      expect(r[3], const ParteMpDeLinea(costoMpCentavos: 0, gananciaMpCentavos: 0));
    });
  });

  group('paso 2 — lo que entró por MP por cigarrillos se corre a MP desde el efectivo', () {
    test('atado por QR: el costo vendido en efectivo ese día pasa a MP por ese monto', () {
      final r = parteMpPorLinea([
        _venta([_atado(1, lista: 400000)], mp: 430000), // atado + recargo, todo por QR
        _venta([_producto(2, costo: 600000, precio: 1000000)], efectivo: 1000000),
      ]);
      expect(r[2]!.costoMpCentavos, 400000);
    });

    test('se reparte en proporción al costo en efectivo de cada línea', () {
      final r = parteMpPorLinea([
        _venta([_atado(1, lista: 300000)], mp: 300000),
        _venta([_producto(2, costo: 400000, precio: 600000)], efectivo: 600000), // 2/3 del costo
        _venta([_producto(3, costo: 200000, precio: 300000)], efectivo: 300000), // 1/3
      ]);
      expect(r[2]!.costoMpCentavos, 200000);
      expect(r[3]!.costoMpCentavos, 100000);
    });

    test('en un mixto cuenta lo que entró por MP, no el atado entero', () {
      final r = parteMpPorLinea([
        _venta([_atado(1, lista: 400000)], efectivo: 330000, mp: 100000),
        _venta([_producto(2, costo: 600000, precio: 1000000)], efectivo: 1000000),
      ]);
      expect(r[2]!.costoMpCentavos, 100000);
    });

    test('lo cobrado por MP cubre primero a los cigarrillos de la misma venta', () {
      // Atado $4.000 + queso $2.000, pagado $1.000 por QR y el resto en
      // efectivo: los $1.000 cubren al atado, el queso quedó en efectivo...
      // y después recibe el corrimiento de esos mismos $1.000.
      final r = parteMpPorLinea([
        _venta([_atado(1, lista: 400000), _producto(2, costo: 120000, precio: 200000)], efectivo: 530000, mp: 100000),
      ]);
      expect(r[2]!.costoMpCentavos, 100000);
    });

    test('con tope en el costo en efectivo del día: lo que sobra no se asigna a nadie', () {
      final r = parteMpPorLinea([
        _venta([_atado(1, lista: 900000)], mp: 900000),
        _venta([_producto(2, costo: 60000, precio: 100000)], efectivo: 100000),
      ]);
      expect(r[2]!.costoMpCentavos, 60000); // no más que su costo
    });

    test('una línea ya cobrada por MP no recibe corrimiento extra', () {
      final r = parteMpPorLinea([
        _venta([_atado(1, lista: 200000)], mp: 200000),
        _venta([_producto(2, costo: 100000, precio: 150000)], mp: 150000), // ya 100% MP
        _venta([_producto(3, costo: 300000, precio: 500000)], efectivo: 500000),
      ]);
      expect(r[2]!.costoMpCentavos, 100000);
      expect(r[3]!.costoMpCentavos, 200000); // todo el excedente cae en la única línea en efectivo
    });

    test('el reparto es por día: los cigarrillos por MP de un día no mueven el efectivo de otro', () {
      final r = parteMpPorLinea([
        _venta([_atado(1, lista: 400000)], sesion: 1, mp: 400000),
        _venta([_producto(2, costo: 600000, precio: 1000000)], sesion: 2, efectivo: 1000000),
      ]);
      expect(r[2]!.costoMpCentavos, 0);
    });

    test('venta sin pagos registrados (carga a mano): todo queda en efectivo, no divide por cero', () {
      final r = parteMpPorLinea([
        _venta([_producto(1, costo: 60000, precio: 100000)]),
      ]);
      expect(r[1]!.costoMpCentavos, 0);
    });
  });

  group('la ganancia se divide igual que el costo', () {
    test('cobrada por MP, su ganancia va a MP; en efectivo, al cajón', () {
      final r = parteMpPorLinea([
        _venta([_producto(1, costo: 60000, precio: 100000)], mp: 100000),
        _venta([_producto(2, costo: 60000, precio: 100000)], sesion: 2, efectivo: 100000),
      ]);
      expect(r[1], const ParteMpDeLinea(costoMpCentavos: 60000, gananciaMpCentavos: 40000));
      expect(r[2], const ParteMpDeLinea(costoMpCentavos: 0, gananciaMpCentavos: 0));
    });

    test('el excedente de cigarrillos sale primero del costo en efectivo; la ganancia no se toca si alcanza', () {
      final r = parteMpPorLinea([
        _venta([_atado(1, lista: 400000)], mp: 400000),
        _venta([_producto(2, costo: 600000, precio: 1000000)], efectivo: 1000000),
      ]);
      expect(r[2], const ParteMpDeLinea(costoMpCentavos: 400000, gananciaMpCentavos: 0));
    });

    test('si el excedente cubre todo el costo en efectivo, el resto sale de la ganancia', () {
      final r = parteMpPorLinea([
        _venta([_atado(1, lista: 800000)], mp: 800000),
        _venta([_producto(2, costo: 600000, precio: 1000000)], efectivo: 1000000),
      ]);
      expect(r[2], const ParteMpDeLinea(costoMpCentavos: 600000, gananciaMpCentavos: 200000));
    });

    test('con tope en la ganancia: lo que excede todo lo vendido en efectivo no se asigna', () {
      final r = parteMpPorLinea([
        _venta([_atado(1, lista: 2000000)], mp: 2000000),
        _venta([_producto(2, costo: 600000, precio: 1000000)], efectivo: 1000000),
      ]);
      expect(r[2], const ParteMpDeLinea(costoMpCentavos: 600000, gananciaMpCentavos: 400000));
    });

    test('una línea vendida por debajo del costo no recibe corrimiento de ganancia', () {
      final r = parteMpPorLinea([
        _venta([_atado(1, lista: 800000)], mp: 800000),
        _venta([_producto(2, costo: 600000, precio: 500000)], efectivo: 500000),
      ]);
      expect(r[2]!.gananciaMpCentavos, 0);
    });
  });

  test('una línea sin proveedor no absorbe el excedente de cigarrillos: todo va a la que tiene proveedor', () {
    final r = parteMpPorLinea([
      _venta([_atado(1, lista: 300000)], mp: 300000),
      _venta([_producto(2, costo: 300000, precio: 500000)], efectivo: 500000),
      _venta([_producto(3, costo: 300000, precio: 500000, conProveedor: false)], efectivo: 500000),
    ]);
    expect(r[2]!.costoMpCentavos, 300000);
    expect(r[3]!.costoMpCentavos, 0);
  });

  test('una línea sin proveedor cobrada por MP muestra su costo y ganancia en MP', () {
    final r = parteMpPorLinea([
      _venta([_producto(1, costo: 60000, precio: 100000, conProveedor: false)], mp: 100000),
    ]);
    expect(r[1], const ParteMpDeLinea(costoMpCentavos: 60000, gananciaMpCentavos: 40000));
  });
}

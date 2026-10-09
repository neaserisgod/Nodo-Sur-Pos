import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/codigo_proveedor.dart';

void main() {
  group('codigoProveedorNuevo (alta desde el celular, sin pedir el código)', () {
    test('iniciales del nombre, en mayúsculas y sin acentos', () {
      expect(codigoProveedorNuevo('Coca Cola', const []), 'CC');
      expect(codigoProveedorNuevo('Lácteos del Sur', const []), 'LDS');
      expect(codigoProveedorNuevo('Ñandú', const []), 'N');
    });

    test('hasta tres iniciales', () {
      expect(codigoProveedorNuevo('La Gran Distribuidora de Bariloche', const []), 'LGD');
    });

    test('ignora signos y espacios de más', () {
      expect(codigoProveedorNuevo('  Golosinas   "Oeste"  ', const []), 'GO');
    });

    test('si ya existe, le suma un número (sin distinguir mayúsculas)', () {
      expect(codigoProveedorNuevo('Coca Cola', const ['CC']), 'CC2');
      expect(codigoProveedorNuevo('Coca Cola', const ['cc', 'CC2']), 'CC3');
      // Los proveedores de fábrica usan una letra: "Fiambrería Sur" no pisa a "F".
      expect(codigoProveedorNuevo('Fiambrería', const ['F', 'S']), 'F2');
    });

    test('un nombre sin letras ni números cae en "P"', () {
      expect(codigoProveedorNuevo('---', const []), 'P');
      expect(codigoProveedorNuevo('', const ['P']), 'P2');
    });
  });
}

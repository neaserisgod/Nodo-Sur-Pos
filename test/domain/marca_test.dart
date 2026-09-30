import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/marca.dart';

void main() {
  group('MarcaNegocio — cómo se llama lo que se ve', () {
    test('el nombre del producto es Nodo Sur POS', () {
      expect(nombreProducto, 'Nodo Sur POS');
    });

    test('sin nada cargado se usa el nombre del producto, tanto de nombre como de encabezado', () {
      const marca = MarcaNegocio();
      expect(marca.nombre, nombreProducto);
      expect(marca.encabezadoTicketEfectivo, nombreProducto);
      expect(marca.configurada, isFalse);
    });

    test('con nombre de comercio, ese es el nombre y también el encabezado si no hay otro', () {
      const marca = MarcaNegocio(nombreComercio: 'Kiosco Del Centro');
      expect(marca.nombre, 'Kiosco Del Centro');
      expect(marca.encabezadoTicketEfectivo, 'Kiosco Del Centro');
      expect(marca.configurada, isTrue);
    });

    test('el encabezado del ticket cargado manda sobre el nombre', () {
      const marca = MarcaNegocio(nombreComercio: 'Kiosco Del Centro', encabezadoTicket: 'Kiosco Del Centro\nSan Martín 123\nMendoza');
      expect(marca.nombre, 'Kiosco Del Centro');
      expect(marca.encabezadoTicketEfectivo, 'Kiosco Del Centro\nSan Martín 123\nMendoza');
    });

    test('los espacios no cuentan: un nombre en blanco es como no tener nombre', () {
      const marca = MarcaNegocio(nombreComercio: '   ', encabezadoTicket: '  \n ');
      expect(marca.nombre, nombreProducto);
      expect(marca.encabezadoTicketEfectivo, nombreProducto);
      expect(marca.configurada, isFalse);
    });

    test('se ignoran los espacios de los costados', () {
      const marca = MarcaNegocio(nombreComercio: '  Mi comercio  ', encabezadoTicket: '  Mi comercio\nCalle 1  ');
      expect(marca.nombre, 'Mi comercio');
      expect(marca.encabezadoTicketEfectivo, 'Mi comercio\nCalle 1');
    });

    test('dos marcas con los mismos datos son iguales (para no avisar cambios que no son)', () {
      expect(const MarcaNegocio(nombreComercio: 'A'), const MarcaNegocio(nombreComercio: 'A'));
      expect(const MarcaNegocio(nombreComercio: 'A').hashCode, const MarcaNegocio(nombreComercio: 'A').hashCode);
      expect(const MarcaNegocio(nombreComercio: 'A') == const MarcaNegocio(nombreComercio: 'B'), isFalse);
      expect(const MarcaNegocio(encabezadoTicket: 'x') == const MarcaNegocio(), isFalse);
    });
  });
}

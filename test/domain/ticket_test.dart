import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/ticket.dart';

void main() {
  group('DesgloseTicket.tieneAlgoQueMostrar', () {
    test('sin recargo ni redondeo: no hay nada que desglosar', () {
      const d = DesgloseTicket();
      expect(d.tieneAlgoQueMostrar, false);
    });

    test('con recargo de cigarrillos: hay algo que mostrar', () {
      const d = DesgloseTicket(recargoCigarrillosCentavos: 40000);
      expect(d.tieneAlgoQueMostrar, true);
    });

    test('con redondeo: hay algo que mostrar', () {
      const d = DesgloseTicket(redondeoCentavos: 600);
      expect(d.tieneAlgoQueMostrar, true);
    });

    test('con descuento: hay algo que mostrar', () {
      const d = DesgloseTicket(descuentoCentavos: 50000);
      expect(d.tieneAlgoQueMostrar, true);
    });
  });

  group('construirTicket — el total sale siempre de sus propias líneas', () {
    test('una línea sin desglose: el total es el subtotal de la línea', () {
      final t = construirTicket(
        fecha: DateTime(2026, 8, 29),
        vendedor: 'Bruno',
        lineas: const [
          LineaTicket(
            nombreProducto: 'Coca-Cola 500ml',
            cantidad: 2,
            subtotalCentavos: 224000,
          ),
        ],
        desglose: const DesgloseTicket(),
      );
      expect(t.totalCentavos, 224000);
    });

    test(
      'suma líneas + recargo + redondeo, nunca un total pasado por separado',
      () {
        final t = construirTicket(
          fecha: DateTime(2026, 8, 29),
          vendedor: 'Bruno',
          lineas: const [
            LineaTicket(
              nombreProducto: 'Marlboro',
              cantidad: 1,
              subtotalCentavos: 500000,
            ),
            LineaTicket(
              nombreProducto: 'Queso barra',
              cantidad: 1,
              gramos: 200,
              subtotalCentavos: 24000,
            ),
          ],
          desglose: const DesgloseTicket(
            recargoCigarrillosCentavos: 30000,
            redondeoCentavos: 600,
          ),
        );
        // 500000 + 24000 + 30000 + 600 = 554600
        expect(t.totalCentavos, 554600);
      },
    );

    test(
      'resta el descuento antes del redondeo, mismo orden que calcularTotalVenta',
      () {
        final t = construirTicket(
          fecha: DateTime(2026, 8, 29),
          vendedor: 'Bruno',
          lineas: const [
            LineaTicket(
              nombreProducto: 'Paleta',
              cantidad: 1,
              subtotalCentavos: 850000,
            ),
          ],
          desglose: const DesgloseTicket(descuentoCentavos: 127500),
        );
        expect(t.totalCentavos, 722500);
      },
    );

    test('sin líneas ni desglose: total 0', () {
      final t = construirTicket(
        fecha: DateTime(2026, 8, 29),
        vendedor: 'Bruno',
        lineas: const [],
        desglose: const DesgloseTicket(),
      );
      expect(t.totalCentavos, 0);
    });

    test('una línea pesable conserva sus gramos y cantidad en 1', () {
      final t = construirTicket(
        fecha: DateTime(2026, 8, 29),
        vendedor: 'Bruno',
        lineas: const [
          LineaTicket(
            nombreProducto: 'Jamón crudo',
            cantidad: 1,
            gramos: 350,
            subtotalCentavos: 41965,
          ),
        ],
        desglose: const DesgloseTicket(),
      );
      expect(t.lineas.single.gramos, 350);
      expect(t.lineas.single.cantidad, 1);
    });
  });

  group(
    'contenidoTicketPosnetMp — lenguaje de tags de la API de Terminals de MP',
    () {
      test('el encabezado va centrado y en letra grande, línea por línea', () {
        final t = construirTicket(
          fecha: DateTime(2026, 8, 29, 14, 30),
          vendedor: 'Bruno',
          lineas: const [],
          desglose: const DesgloseTicket(),
        );
        final contenido = contenidoTicketPosnetMp(
          t,
          encabezadoNegocio: 'La Plazoleta\nBariloche',
        );
        expect(
          contenido,
          startsWith(
            '{center}{w}La Plazoleta{/w}{/center}{br}{center}{w}Bariloche{/w}{/center}{br}',
          ),
        );
      });

      test('cada ítem: descripción sin tag (queda a la izquierda) y precio con '
          '{left} — que en la terminal real alinea a la DERECHA, no a la izquierda '
          '(verificado a mano, no documentado por MercadoPago)', () {
        final t = construirTicket(
          fecha: DateTime(2026, 8, 29),
          vendedor: 'Bruno',
          lineas: const [
            LineaTicket(
              nombreProducto: 'Coca-Cola 500ml',
              cantidad: 2,
              subtotalCentavos: 224000,
            ),
          ],
          desglose: const DesgloseTicket(),
        );
        final contenido = contenidoTicketPosnetMp(
          t,
          encabezadoNegocio: 'La Plazoleta',
        );
        expect(
          contenido,
          contains('Coca-Cola 500ml (x2){br}{left}\$2.240{/left}{br}'),
        );
      });

      test('un pesable muestra los gramos en vez de la cantidad', () {
        final t = construirTicket(
          fecha: DateTime(2026, 8, 29),
          vendedor: 'Bruno',
          lineas: const [
            LineaTicket(
              nombreProducto: 'Jamón crudo',
              cantidad: 1,
              gramos: 350,
              subtotalCentavos: 41965,
            ),
          ],
          desglose: const DesgloseTicket(),
        );
        final contenido = contenidoTicketPosnetMp(
          t,
          encabezadoNegocio: 'La Plazoleta',
        );
        expect(contenido, contains('Jamón crudo (350g){br}'));
      });

      test(
        'recargo de cigarrillos y redondeo solo aparecen si son mayores a cero',
        () {
          final sinNinguno = construirTicket(
            fecha: DateTime(2026, 8, 29),
            vendedor: 'Bruno',
            lineas: const [],
            desglose: const DesgloseTicket(),
          );
          final conAmbos = construirTicket(
            fecha: DateTime(2026, 8, 29),
            vendedor: 'Bruno',
            lineas: const [],
            desglose: const DesgloseTicket(
              recargoCigarrillosCentavos: 30000,
              redondeoCentavos: 600,
            ),
          );

          expect(
            contenidoTicketPosnetMp(sinNinguno, encabezadoNegocio: 'x'),
            isNot(contains('Recargo')),
          );
          expect(
            contenidoTicketPosnetMp(sinNinguno, encabezadoNegocio: 'x'),
            isNot(contains('Redondeo')),
          );

          final contenido = contenidoTicketPosnetMp(
            conAmbos,
            encabezadoNegocio: 'x',
          );
          expect(
            contenido,
            contains('Recargo cigarrillos{br}{left}\$300{/left}{br}'),
          );
          expect(contenido, contains('Redondeo{br}{left}\$6{/left}{br}'));
        },
      );

      test('descuento aparece con signo negativo, solo si es mayor a cero', () {
        final sinDescuento = construirTicket(
          fecha: DateTime(2026, 8, 29),
          vendedor: 'Bruno',
          lineas: const [],
          desglose: const DesgloseTicket(),
        );
        final conDescuento = construirTicket(
          fecha: DateTime(2026, 8, 29),
          vendedor: 'Bruno',
          lineas: const [
            LineaTicket(
              nombreProducto: 'Paleta',
              cantidad: 1,
              subtotalCentavos: 850000,
            ),
          ],
          desglose: const DesgloseTicket(descuentoCentavos: 127500),
        );

        expect(
          contenidoTicketPosnetMp(sinDescuento, encabezadoNegocio: 'x'),
          isNot(contains('Descuento')),
        );

        final contenido = contenidoTicketPosnetMp(
          conDescuento,
          encabezadoNegocio: 'x',
        );
        expect(
          contenido,
          contains('Descuento{br}{left}-\$1.275{/left}{br}'),
        );
      });

      test(
        'el total va en negrita, alineado con {left} (derecha real) como el resto de los montos',
        () {
          final t = construirTicket(
            fecha: DateTime(2026, 8, 29),
            vendedor: 'Bruno',
            lineas: const [
              LineaTicket(
                nombreProducto: 'Marlboro',
                cantidad: 1,
                subtotalCentavos: 500000,
              ),
            ],
            desglose: const DesgloseTicket(),
          );
          final contenido = contenidoTicketPosnetMp(t, encabezadoNegocio: 'x');
          expect(
            contenido,
            contains('{left}{b}TOTAL \$5.000{/b}{/left}{br}'),
          );
        },
      );

      test('termina con el agradecimiento centrado', () {
        final t = construirTicket(
          fecha: DateTime(2026, 8, 29),
          vendedor: 'Bruno',
          lineas: const [],
          desglose: const DesgloseTicket(),
        );
        final contenido = contenidoTicketPosnetMp(t, encabezadoNegocio: 'x');
        expect(
          contenido,
          endsWith('{center}Gracias por su compra{/center}{br}'),
        );
      });
    },
  );
}

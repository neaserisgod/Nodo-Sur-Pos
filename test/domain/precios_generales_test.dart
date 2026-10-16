// Precios de todo el catálogo (El dueño, 2026-10-16), en markup sobre el costo: promedio sin cigarrillos ni fiambres, subir
// sobre el costo, igualar el markup y encontrar la última suba para deshacerla.
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/precios_generales.dart';

void main() {
  ProductoParaPrecios p(int? precio, int? costo, {bool cigarrillo = false, bool pesable = false, String? categoria}) => productoParaPrecios(
        precioCentavos: precio,
        costoCentavos: costo,
        tipoCigarrillo: cigarrillo ? 'atado' : 'ninguno',
        esPesable: pesable,
        nombreCategoria: categoria,
      );

  test('subir 15 % es sobre el costo: \$7.000 con costo \$6.000 queda en \$7.900 (no \$8.050)', () {
    expect(precioAlSubirSobreCosto(p(700000, 600000), 1500), 790000);
    // El ejemplo del dueño: costo 100 con markup 70 (precio 170) sube a markup 85.
    expect(precioAlSubirSobreCosto(p(17000, 10000), 1500), 18500);
  });

  test('subir no toca cigarrillos, fiambres ni productos sin costo', () {
    expect(precioAlSubirSobreCosto(p(700000, 600000, cigarrillo: true), 1500), isNull);
    expect(precioAlSubirSobreCosto(p(700000, 600000, pesable: true), 1500), isNull);
    expect(precioAlSubirSobreCosto(p(700000, 600000, categoria: 'Fiambres'), 1500), isNull);
    expect(precioAlSubirSobreCosto(p(700000, null), 1500), isNull);
  });

  test('el promedio es de markup sobre el costo, con la ganancia sobre el precio que da', () {
    final r = promedioDePrecios([
      p(17000, 10000), // markup 70 %, ganancia 41,2 %
      p(15000, 10000), // markup 50 %, ganancia 33,3 %
      p(100000, 10000, cigarrillo: true),
      p(100000, 10000, pesable: true),
      p(100000, null),
    ])!;
    expect(r.markupBp, 6000);
    expect(r.productos, 2);
    expect(r.gananciaBp, closeTo(3725, 2));
  });

  test('igualar el markup a 70 %: costo \$1.000 queda en \$1.700, por el porcentaje del proveedor (ganancia 41,17 %)', () {
    expect(gananciaBpDesdeMarkupBp(7000), 4117);
    expect(precioAlIgualarMarkup(p(120000, 100000), 7000), 170000);
    expect(precioAlIgualarMarkup(p(120000, 100000, categoria: 'fiambre'), 7000), isNull);
  });

  test('la última suba es el último minuto con muchos cambios; un precio tocado a mano después no la tapa', () {
    final suba = DateTime(2026, 10, 16, 13, 20, 5);
    final fotos = <FotoDePrecio>[
      for (var i = 0; i < 6; i++) (id: 100 + i, productoId: i, fecha: suba),
      (id: 50, productoId: 1, fecha: DateTime(2026, 10, 10, 9)), // un cambio viejo
      (id: 200, productoId: 9, fecha: DateTime(2026, 10, 16, 14)), // uno a mano después
    ];
    final lote = loteDeLaUltimaSuba(fotos);
    expect(lote.length, 6);
    expect(lote.map((f) => f.productoId).toSet(), {0, 1, 2, 3, 4, 5});
    expect(loteDeLaUltimaSuba(fotos.sublist(6)), isEmpty);
  });
}

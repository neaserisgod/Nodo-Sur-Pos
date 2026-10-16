// Precios de todo el catálogo (El dueño, 2026-10-16): la ganancia promedio sin cigarrillos y quién entra en cada acción.
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

  test('el promedio es de la ganancia sobre el precio y deja afuera cigarrillos y productos sin costo', () {
    final r = gananciaPromedio([
      p(100000, 70000), // 30 %
      p(100000, 50000), // 50 %
      p(100000, 99000, cigarrillo: true),
      p(100000, 10000, pesable: true),
      p(100000, 10000, categoria: 'Fiambres'),
      p(100000, null),
      p(null, 50000),
    ])!;
    expect(r.gananciaBp, 4000);
    expect(r.productos, 2);
  });

  test('sin productos con costo no hay promedio', () {
    expect(gananciaPromedio([p(100000, null), p(100000, 50000, cigarrillo: true)]), isNull);
  });

  test('subir todo toma los que tienen precio; igualar, los que tienen costo; nunca cigarrillos', () {
    expect(entraEnSubaGeneral(p(100000, null)), isTrue);
    expect(entraEnSubaGeneral(p(0, 50000)), isFalse);
    expect(entraEnSubaGeneral(p(100000, 50000, cigarrillo: true)), isFalse);
    expect(entraEnIgualarGanancia(p(null, 50000)), isTrue);
    expect(entraEnIgualarGanancia(p(100000, null)), isFalse);
  });

  test('igualar usa la misma fórmula que el porcentaje del proveedor: a la próxima centena', () {
    expect(precioAlIgualarGanancia(p(120000, 100000), 3000), 150000); // $1.000 con 30 % = $1.428,57 → $1.500
    expect(precioAlIgualarGanancia(p(120000, 100000, cigarrillo: true), 3000), isNull);
  });

  test('un fiambre es el que se vende por peso o el de la categoría Fiambres', () {
    expect(esFiambre(esPesable: true), isTrue);
    expect(esFiambre(esPesable: false, nombreCategoria: ' fiambres '), isTrue);
    expect(esFiambre(esPesable: false, nombreCategoria: 'Fiambre'), isTrue);
    expect(esFiambre(esPesable: false, nombreCategoria: 'Almacén'), isFalse);
    expect(entraEnSubaGeneral(p(100000, 50000, categoria: 'Fiambres')), isFalse);
    expect(entraEnIgualarGanancia(p(100000, 50000, pesable: true)), isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/linea_venta_reconstruccion.dart';
import 'package:la_plazoleta/domain/equilibrio.dart';

FilaLineaVenta _linea({int? costo, bool pesable = false}) => FilaLineaVenta(
      id: 1,
      ventaId: 1,
      nombreProductoFoto: 'Vino Blanco Anaia',
      esVarios: false,
      tipoCigarrillo: 'ninguno',
      esPesable: pesable,
      cantidad: pesable ? null : 2,
      gramos: pesable ? 250 : null,
      precioUnitarioCentavos: 750000,
      costoUnitarioCentavos: costo,
    );

void main() {
  group('lineaParaReposicionDesde — costo \$0 (Regla 4)', () {
    test('un costo \$0 guardado es "sin costo", no una ganancia del 100%', () {
      final r = lineaParaReposicionDesde(_linea(costo: 0));
      expect(r.costoLineaCentavos, isNull);

      final g = calcularGananciaBruta(lineas: [r]);
      expect(g.gananciaBrutaCentavos, 0);
      expect(g.vendidoSinCostoCentavos, 1500000);
    });

    test('lo mismo en un pesable', () {
      expect(lineaParaReposicionDesde(_linea(costo: 0, pesable: true)).costoLineaCentavos, isNull);
    });

    test('un costo real se sigue multiplicando por la cantidad', () {
      expect(lineaParaReposicionDesde(_linea(costo: 500000)).costoLineaCentavos, 1000000);
    });

    test('sin costo (null) sigue siendo sin costo', () {
      expect(lineaParaReposicionDesde(_linea()).costoLineaCentavos, isNull);
    });
  });
}

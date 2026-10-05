import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/unidades_bulto.dart';

/// Bultos vs. unidades (El dueño, 2026-10-05: "necesito discriminarlos"). Las descripciones y los costos son los de las facturas REALES.
void main() {
  group('sugerirUnidadesPorBulto (lo que dice la descripción)', () {
    test('el pack entre paréntesis (Serra, Elpar)', () {
      expect(sugerirUnidadesPorBulto('BG ALF AGUILA MINITORTA BL 69G(21)'), 21);
      expect(sugerirUnidadesPorBulto('D ANC SAL FINA PAQ 500G (12)'), 12);
      expect(sugerirUnidadesPorBulto('SW22204 - SALCHICHAS SWIFT S/GLUTEN 6 U X 225GR (24)'), 24);
      expect(sugerirUnidadesPorBulto('TS OCB PAP PREMIUM 25X50H (40)'), 40);
    });

    test('un paréntesis cortado por la impresión no cuenta ("(2")', () {
      expect(sugerirUnidadesPorBulto('BG ALF AGUILA MINITORTA DARK 69G (2'), isNull);
    });

    test('cantidad x tamaño: el pack es el número chico (Manaos "6X1500", Coca "473X6")', () {
      expect(sugerirUnidadesPorBulto('MANAOS LIMA-LIMON-PACK 6X1500'), 6);
      expect(sugerirUnidadesPorBulto('ALVURA AGUA MINERAL-6X1500 S/GAS'), 6);
      expect(sugerirUnidadesPorBulto('MONSTER NCY ULTRA WHITE 473X6*'), 6);
    });

    test('packs de packs: 4X6 son 24 latas (Bebidas del Lago)', () {
      expect(sugerirUnidadesPorBulto('ANDES ORIGEN IPA CAN 4X6 473'), 24);
    });

    test('"X24" suelto y "25U"', () {
      expect(sugerirUnidadesPorBulto('QUILMES 1890 CAN X24 473CC SMK'), 24);
      expect(sugerirUnidadesPorBulto('IMP ENCENDEDOR CANDELA TRANS 25U (4'), 25);
      expect(sugerirUnidadesPorBulto('CHUPET. MR.POPS FRUTAL 50 un'), 50);
    });

    test('sin pista en la descripción, null (no se adivina)', () {
      expect(sugerirUnidadesPorBulto('MP MARLBORO KS 20'), isNull);
      expect(sugerirUnidadesPorBulto('Shampoo Ceramidas'), isNull);
      expect(sugerirUnidadesPorBulto(''), isNull);
    });
  });

  group('inferirUnidadesPorCantidad (comparando con el costo que ya tenés)', () {
    test('un pack de 6: el costo por pack es 6 veces el de tu producto → 6 (Manaos)', () {
      // Tu botella cuesta $1.650; la factura cobra $9.907 por pack de 6 (1.651 c/u).
      final r = inferirUnidadesPorCantidad(costoPorCantidadCentavos: 990700, costoActualPorUnidadCentavos: 165000, packSugerido: 6);
      expect(r, isNotNull);
      expect(r!.unidades, 6);
    });

    test('la descripción dice "(21)" pero la factura ya cuenta unidades: el costo es parecido al tuyo → 1 (Serra)', () {
      final r = inferirUnidadesPorCantidad(costoPorCantidadCentavos: 147100, costoActualPorUnidadCentavos: 140000, packSugerido: 21);
      expect(r!.unidades, 1);
    });

    test('latas contadas de a una aunque el precio impreso sea por bulto de 4x6 → 1 (Bebidas del Lago)', () {
      final r = inferirUnidadesPorCantidad(costoPorCantidadCentavos: 226400, costoActualPorUnidadCentavos: 215000, packSugerido: 24);
      expect(r!.unidades, 1);
    });

    test('una suba de costo normal (30 %) no se confunde con un bulto', () {
      expect(inferirUnidadesPorCantidad(costoPorCantidadCentavos: 130000, costoActualPorUnidadCentavos: 100000, packSugerido: 12)!.unidades, 1);
    });

    test('un costo que no se parece ni a la unidad ni al pack no se adivina', () {
      // Cuesta 3 veces el tuyo y el pack es de 12: ni una cosa ni la otra.
      expect(inferirUnidadesPorCantidad(costoPorCantidadCentavos: 300000, costoActualPorUnidadCentavos: 100000, packSugerido: 12), isNull);
    });

    test('sin costo cargado en el producto, o sin pack conocido y muy distinto, devuelve null', () {
      expect(inferirUnidadesPorCantidad(costoPorCantidadCentavos: 100000, costoActualPorUnidadCentavos: null, packSugerido: 6), isNull);
      expect(inferirUnidadesPorCantidad(costoPorCantidadCentavos: 100000, costoActualPorUnidadCentavos: 0, packSugerido: 6), isNull);
      expect(inferirUnidadesPorCantidad(costoPorCantidadCentavos: 600000, costoActualPorUnidadCentavos: 100000), isNull);
    });

    test('sin pack conocido, si el costo se parece al tuyo es por unidad', () {
      expect(inferirUnidadesPorCantidad(costoPorCantidadCentavos: 105000, costoActualPorUnidadCentavos: 100000)!.unidades, 1);
    });

    test('explica por qué, para mostrárselo al dueño', () {
      final r = inferirUnidadesPorCantidad(costoPorCantidadCentavos: 990700, costoActualPorUnidadCentavos: 165000, packSugerido: 6)!;
      expect(r.motivo, contains('6'));
    });
  });
}

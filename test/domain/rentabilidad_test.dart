import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/rentabilidad.dart';

DatosDelMes datos({
  int ventas = 500000000, // $5.000.000
  int ventasConCosto = 500000000,
  int ganancia = 285000000, // $2.850.000
  int fijos = 135000000, // $1.350.000
  int variables = 0,
  int sueldo = 100000000, // $1.000.000
  int retiros = 0,
  int reserva = 0,
  int arrastre = 0,
  bool fijosCompletos = true,
}) =>
    DatosDelMes(
      ventasNetasCentavos: ventas,
      ventasConCostoCentavos: ventasConCosto,
      gananciaBrutaCentavos: ganancia,
      gastosFijosCentavos: fijos,
      gastosVariablesCentavos: variables,
      sueldoObjetivoCentavos: sueldo,
      retirosDelMesCentavos: retiros,
      reservaCentavos: reserva,
      arrastreCentavos: arrastre,
      fijosCompletos: fijosCompletos,
    );

void main() {
  group('calcularEstadoDeResultados', () {
    test('la cascada cierra: bruta − fijos − variables = operativo; − sueldo = después del sueldo', () {
      final e = calcularEstadoDeResultados(datos(variables: 5000000));
      expect(e.ventasNetasCentavos, 500000000);
      expect(e.costoMercaderiaCentavos, 215000000); // 5.000.000 − 2.850.000
      expect(e.gananciaBrutaCentavos, 285000000);
      expect(e.resultadoOperativoCentavos, 285000000 - 135000000 - 5000000);
      expect(e.resultadoDespuesDelSueldoCentavos, e.resultadoOperativoCentavos - 100000000);
      // costo + ganancia = ventas con costo, siempre
      expect(e.costoMercaderiaCentavos + e.gananciaBrutaCentavos, 500000000);
    });

    test('la ganancia bruta sobre el precio es 57% (no un markup)', () {
      expect(calcularEstadoDeResultados(datos()).gananciaBrutaBp, 5700);
    });

    test('retirable sale del resultado operativo, no de la ganancia bruta', () {
      // Bruta $2.850.000, fijos $1.350.000 → operativo $1.500.000.
      final e = calcularEstadoDeResultados(datos());
      expect(e.resultadoOperativoCentavos, 150000000);
      expect(e.retirableCentavos, 150000000);
    });

    test('lo ya retirado y la reserva bajan lo retirable', () {
      final e = calcularEstadoDeResultados(datos(retiros: 60000000, reserva: 30000000));
      expect(e.retirableCentavos, 150000000 - 30000000 - 60000000);
      expect(e.excesoDeRetirosCentavos, 0);
    });

    test('el arrastre del mes anterior suma a lo retirable (y evita un falso exceso a principio de mes)', () {
      // Mes recién empezado: operativo 0, pero quedaban $500.000 del anterior.
      final e = calcularEstadoDeResultados(datos(ganancia: 135000000, arrastre: 50000000, retiros: 40000000));
      expect(e.resultadoOperativoCentavos, 0);
      expect(e.retirableCentavos, 10000000);
      expect(e.excesoDeRetirosCentavos, 0);
    });

    test('retirar el sueldo no se cuenta como exceso: el sueldo no se resta dos veces', () {
      final e = calcularEstadoDeResultados(datos(retiros: 100000000));
      expect(e.excesoDeRetirosCentavos, 0);
      expect(e.retirableCentavos, 50000000);
    });

    test('retirar más de lo que ganó el negocio marca exceso y deja 0 retirable', () {
      final e = calcularEstadoDeResultados(datos(retiros: 210000000)); // operativo 1.500.000
      expect(e.retirableCentavos, 0);
      expect(e.excesoDeRetirosCentavos, 60000000);
      expect(e.advertencias.any((a) => a.contains('retiraste más')), isTrue);
    });

    test('un mes en pérdida: nada retirable y todo lo retirado es exceso', () {
      final e = calcularEstadoDeResultados(datos(ganancia: 100000000, retiros: 20000000));
      expect(e.resultadoOperativoCentavos, -35000000);
      expect(e.retirableCentavos, 0);
      expect(e.excesoDeRetirosCentavos, 20000000);
    });

    test('ventas sin costo o fijos sin cargar marcan el estado como incompleto', () {
      final sinCosto = calcularEstadoDeResultados(datos(ventas: 600000000));
      expect(sinCosto.vendidoSinCostoCentavos, 100000000);
      expect(sinCosto.esCompleto, isFalse);
      final sinFijos = calcularEstadoDeResultados(datos(fijosCompletos: false));
      expect(sinFijos.esCompleto, isFalse);
      expect(calcularEstadoDeResultados(datos()).esCompleto, isTrue);
    });

    test('sin ventas con costo no hay margen que mostrar (null, no 0)', () {
      final e = calcularEstadoDeResultados(datos(ventas: 0, ventasConCosto: 0, ganancia: 0));
      expect(e.gananciaBrutaBp, isNull);
    });
  });

  group('evaluarRetiro', () {
    test('dentro de lo retirable no pide confirmar', () {
      final e = calcularEstadoDeResultados(datos());
      final r = evaluarRetiro(montoCentavos: 100000000, estado: e);
      expect(r.requiereConfirmacion, isFalse);
      expect(r.excedeCentavos, 0);
    });

    test('por encima de lo retirable pide confirmar y dice cuánto se pasa', () {
      final e = calcularEstadoDeResultados(datos());
      final r = evaluarRetiro(montoCentavos: 170000000, estado: e);
      expect(r.requiereConfirmacion, isTrue);
      expect(r.excedeCentavos, 20000000);
    });
  });

  group('margen necesario y precio sugerido', () {
    test('fijos 1.350.000 + sueldo 1.000.000 + retener 500.000 sobre 5.000.000 → 57%', () {
      expect(
        margenNecesarioBp(
          gastosFijosCentavos: 135000000,
          gastosVariablesCentavos: 0,
          sueldoObjetivoCentavos: 100000000,
          gananciaARetenerCentavos: 50000000,
          ventaEstimadaCentavos: 500000000,
        ),
        5700,
      );
    });

    test('redondea hacia arriba: nunca queda corto', () {
      // 1.000 / 3.000 = 33,333…% → 3334 bp
      expect(
        margenNecesarioBp(
          gastosFijosCentavos: 100000,
          gastosVariablesCentavos: 0,
          sueldoObjetivoCentavos: 0,
          gananciaARetenerCentavos: 0,
          ventaEstimadaCentavos: 300000,
        ),
        3334,
      );
    });

    test('sin venta estimada, o con un objetivo imposible (≥ 100%), es null', () {
      expect(
        margenNecesarioBp(gastosFijosCentavos: 1, gastosVariablesCentavos: 0, sueldoObjetivoCentavos: 0, gananciaARetenerCentavos: 0, ventaEstimadaCentavos: 0),
        isNull,
      );
      expect(
        margenNecesarioBp(gastosFijosCentavos: 500000, gastosVariablesCentavos: 0, sueldoObjetivoCentavos: 0, gananciaARetenerCentavos: 0, ventaEstimadaCentavos: 500000),
        isNull,
      );
    });

    test('venta necesaria = necesario / margen, redondeada hacia arriba', () {
      expect(ventaNecesariaCentavos(necesarioCentavos: 285000000, margenBp: 5700), 500000000);
      expect(ventaNecesariaCentavos(necesarioCentavos: 100, margenBp: 0), isNull);
    });

    test('costo \$1.000 con 57% → precio mínimo \$2.326 → \$2.400 a la centena', () {
      expect(precioMinimoSugeridoCentavos(costoCentavos: 100000, margenBp: 5700), 240000);
    });

    test('estaPorDebajoDelMargen compara la ganancia real, no un markup', () {
      // Costo 1.000, precio 1.700 = 41,18% de ganancia < 57%.
      expect(estaPorDebajoDelMargen(costoCentavos: 100000, precioCentavos: 170000, margenNecesarioBp: 5700), isTrue);
      expect(estaPorDebajoDelMargen(costoCentavos: 100000, precioCentavos: 240000, margenNecesarioBp: 5700), isFalse);
      expect(estaPorDebajoDelMargen(costoCentavos: 0, precioCentavos: 170000, margenNecesarioBp: 5700), isFalse);
    });
  });
}

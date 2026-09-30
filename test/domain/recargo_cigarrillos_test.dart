import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/recargo_cigarrillos.dart';

void main() {
  const config = ConfigRecargoCigarrillos(
    primerAtadoCentavos: 30000, // $300
    atadoAdicionalCentavos: 10000, // $100
    cigarroSueltoCentavos: 5000, // $50 (El dueño, 2026-09-10: antes no llevaban recargo)
  );

  group('recargoCigarrillos — Regla 6', () {
    test('efectivo puro: sin recargo aunque haya atados', () {
      final r = recargoCigarrillos(
        cantidadAtados: 2,
        cantidadSueltos: 0,
        composicionPago: ComposicionPago.efectivo,
        config: config,
      );
      expect(r, 0);
    });

    test('virtual puro, 1 atado → recargo del primer atado', () {
      final r = recargoCigarrillos(
        cantidadAtados: 1,
        cantidadSueltos: 0,
        composicionPago: ComposicionPago.virtual,
        config: config,
      );
      expect(r, 30000);
    });

    test('virtual puro, 3 atados → primero + dos adicionales', () {
      final r = recargoCigarrillos(
        cantidadAtados: 3,
        cantidadSueltos: 0,
        composicionPago: ComposicionPago.virtual,
        config: config,
      );
      // 30000 + 10000 + 10000 = 50000
      expect(r, 50000);
    });

    test('mixto aplica el recargo completo, igual que 100% virtual', () {
      final r = recargoCigarrillos(
        cantidadAtados: 2,
        cantidadSueltos: 0,
        composicionPago: ComposicionPago.mixto,
        config: config,
      );
      // 30000 + 10000 = 40000, sin prorratear por la parte en efectivo
      expect(r, 40000);
    });

    test('cigarros sueltos generan recargo en pago virtual (Dueño, 2026-09-10: \$50 c/u)', () {
      final r = recargoCigarrillos(
        cantidadAtados: 0,
        cantidadSueltos: 5,
        composicionPago: ComposicionPago.virtual,
        config: config,
      );
      // 5 × 5000 = 25000
      expect(r, 25000);
    });

    test('cigarros sueltos: sin recargo en efectivo puro', () {
      final r = recargoCigarrillos(
        cantidadAtados: 0,
        cantidadSueltos: 5,
        composicionPago: ComposicionPago.efectivo,
        config: config,
      );
      expect(r, 0);
    });

    test('sueltos + atados: se suman los dos recargos', () {
      final r = recargoCigarrillos(
        cantidadAtados: 1,
        cantidadSueltos: 3,
        composicionPago: ComposicionPago.virtual,
        config: config,
      );
      // 30000 (primer atado) + 3 × 5000 (sueltos) = 45000
      expect(r, 45000);
    });

    test('venta sin cigarrillos → 0 recargo sin importar el medio', () {
      final r = recargoCigarrillos(
        cantidadAtados: 0,
        cantidadSueltos: 0,
        composicionPago: ComposicionPago.virtual,
        config: config,
      );
      expect(r, 0);
    });

    test('recalcula si cambia el medio de pago: no queda pegado al total (Regla 6)', () {
      // Caso de borde real: el cliente carga 2 atados y todavía no eligió
      // cómo paga. La cajera prueba distintos botones antes de cobrar y el
      // recargo tiene que aparecer y desaparecer en cada toque, no quedar
      // pegado al primer cálculo que se hizo.
      const cantidadAtados = 2;
      const cantidadSueltos = 0;

      int recargoCon(ComposicionPago medio) => recargoCigarrillos(
            cantidadAtados: cantidadAtados,
            cantidadSueltos: cantidadSueltos,
            composicionPago: medio,
            config: config,
          );

      // Efectivo → nada. Se toca "Mercado Pago" → aparece. Se arrepiente y
      // vuelve a "Efectivo" → desaparece. Se toca "Mixto" → vuelve a aparecer,
      // igual que en Mercado Pago puro (Regla 6: se aplica completo).
      expect(recargoCon(ComposicionPago.efectivo), 0);
      expect(recargoCon(ComposicionPago.virtual), 40000);
      expect(recargoCon(ComposicionPago.efectivo), 0);
      expect(recargoCon(ComposicionPago.mixto), 40000);
      expect(recargoCon(ComposicionPago.mixto), recargoCon(ComposicionPago.virtual));
    });
  });
}

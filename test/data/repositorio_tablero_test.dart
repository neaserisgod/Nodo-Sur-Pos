import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/repositorio_reposicion.dart';
import 'package:la_plazoleta/data/repositorio_tablero.dart';

import '../capturas/escenario_tablero.dart';

void main() {
  test('"Falta separar" del tablero es lo mismo que suma Separaciones (sin contar MP dos veces)', () async {
    final db = await crearEscenarioTablero();
    addTearDown(db.close);

    final tablero = await tableroDelDia(db);
    final separaciones = await separacionesDelDia(db);
    final esperado = separaciones.fold(0, (a, s) => a + s.faltaSepararCentavos);

    expect(esperado, greaterThan(0));
    expect(tablero.faltaSepararCentavos, esperado);
  });

  test('las anuladas no cuentan en lo vendido ni en los tickets', () async {
    final db = await crearEscenarioTablero();
    addTearDown(db.close);
    final antes = await tableroDelDia(db);

    final venta = (await db.select(db.ventas).get()).first;
    await (db.update(db.ventas)..where((v) => v.id.equals(venta.id))).write(
      venta.copyWith(anuladaEn: Value(DateTime.now())).toCompanion(false),
    );
    final despues = await tableroDelDia(db);

    expect(despues.tickets, antes.tickets - 1);
    expect(despues.vendidoCentavos, antes.vendidoCentavos - venta.totalCentavos);
  });
}

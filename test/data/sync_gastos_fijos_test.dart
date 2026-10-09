// Los gastos fijos viajan entre la PC y el celular (v63, El dueño 2026-10-09: independizar el celular): un fijo cargado en un
// equipo, con su monto y su vencimiento, aparece en el otro; el mismo nombre en los dos es un solo fijo; y un pago de un fijo
// desde la caja apunta al fijo correcto aunque los `id` locales no coincidan.
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_equilibrio.dart';
import 'package:la_plazoleta/data/repositorio_sincronizacion.dart';

import '../helpers/base_para_tests.dart';

Future<void> pasar(AppDatabase de, AppDatabase a, String tabla) async {
  await aplicarCambios(a, tabla: tabla, filas: await cambiosDesde(de, tabla: tabla, desde: 0));
}

void main() {
  late AppDatabase pc;
  late AppDatabase celular;
  setUp(() {
    pc = baseDeTest();
    celular = baseDeTest();
  });
  tearDown(() async {
    await pc.close();
    await celular.close();
  });

  test('un fijo nuevo con su monto y vencimiento llega al otro equipo', () async {
    // Un fijo de relleno en el celular para que los id locales NO coincidan.
    await crearConcepto(celular, 'Relleno');
    final id = await crearConcepto(pc, 'Alquiler local');
    await cargarMontoDelMes(pc, gastoFijoId: id, mesAnio: '2026-10', montoCentavos: 45000000);
    await configurarVencimiento(pc, gastoFijoId: id, dia: 10);

    await pasar(pc, celular, 'gastos_fijos');
    await pasar(pc, celular, 'gastos_fijos_montos');

    final fijo = (await celular.select(celular.gastosFijos).get()).singleWhere((g) => g.nombre == 'Alquiler local');
    expect(fijo.diaVencimiento, 10);
    final resumen = await fijosDelMes(celular, '2026-10');
    expect(resumen.conceptos.singleWhere((c) => c.concepto.nombre == 'Alquiler local').montoCentavos, 45000000);
  });

  test('el mismo nombre en los dos equipos es un solo fijo, y corregir el monto en uno gana en el otro', () async {
    final enPc = await crearConcepto(pc, 'Internet del local');
    final enCelular = await crearConcepto(celular, 'Internet del local');
    await cargarMontoDelMes(celular, gastoFijoId: enCelular, mesAnio: '2026-10', montoCentavos: 3000000);
    await pasar(celular, pc, 'gastos_fijos');
    await pasar(celular, pc, 'gastos_fijos_montos');
    expect((await pc.select(pc.gastosFijos).get()).where((g) => g.nombre == 'Internet del local'), hasLength(1));

    await Future<void>.delayed(const Duration(seconds: 1)); // actualizado_en guarda segundos
    await cargarMontoDelMes(pc, gastoFijoId: enPc, mesAnio: '2026-10', montoCentavos: 3500000);
    await pasar(pc, celular, 'gastos_fijos');
    await pasar(pc, celular, 'gastos_fijos_montos');
    final resumen = await fijosDelMes(celular, '2026-10');
    expect(resumen.conceptos.singleWhere((c) => c.concepto.nombre == 'Internet del local').montoCentavos, 3500000);
    expect((await celular.select(celular.gastosFijosMontos).get()).where((m) => m.mesAnio == '2026-10' && m.montoCentavos == 3500000), hasLength(1));
  });
}

// Seña de un encargue desde el celular (El dueño, 2026-10-09: independizar el celular; antes solo en la PC): entra a la caja
// abierta de la base del celular y, si se cancela, se devuelve desde ahí. Mismas reglas que la PC (`crearEncargueApartando`).
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/cliente_companion.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_cierre.dart' show ingresosEnEfectivoDelDia;

import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late PuertoLocal puerto;
  late int usuario;
  late int torta;

  setUp(() async {
    db = baseDeTest();
    puerto = PuertoLocal(db);
    usuario = (await db.select(db.usuarios).get()).first.id;
    torta = await db.into(db.productos).insert(ProductosCompanion.insert(nombre: 'Torta', precioCentavos: const Value(2000000), stock: const Value(3)));
  });
  tearDown(() => db.close());

  test('con la caja abierta, la seña entra al cajón y al cancelar se devuelve', () async {
    final sesion = await puerto.abrirSesion(usuarioId: usuario, fondoInicialCentavos: 0);
    final id = await puerto.crearEncargue(nombreCliente: 'Marta', lineas: [ApartadoCompanion(productoId: torta, cantidad: 1)], usuarioId: usuario, senaCentavos: 500000);

    expect(await ingresosEnEfectivoDelDia(db, sesion), 500000);
    expect((await puerto.encargues()).single.senaCentavos, 500000);

    await puerto.cancelarEncargue(id, usuarioId: usuario);
    final movimientos = await (db.select(db.movimientosDeCaja)..where((m) => m.sesionCajaId.equals(sesion))).get();
    expect(movimientos, hasLength(2), reason: 'la seña y su devolución');
    expect(await puerto.encargues(), isEmpty);
  });

  test('sin caja abierta no toma la seña y lo dice', () async {
    expect(
      () => puerto.crearEncargue(nombreCliente: 'Marta', lineas: [ApartadoCompanion(productoId: torta, cantidad: 1)], usuarioId: usuario, senaCentavos: 500000),
      throwsA(isA<ErrorCompanion>().having((e) => e.mensaje, 'mensaje', contains('caja abierta'))),
    );
  });
}

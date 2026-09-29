import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_promos.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/ui/venta/venta_controlador.dart';

/// La promo aparece en la venta como un producto más, con el stock que dan sus
/// artículos, y al cobrarla los descuenta (Bruno, 2026-09-29).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late int usuarioId;
  late int yerba;
  late int galletitas;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Bruno'));
    await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    yerba = await db.into(db.productos).insert(
          ProductosCompanion.insert(nombre: 'Yerba', costoCentavos: const Value(100000), precioCentavos: const Value(140000), stock: const Value(3)),
        );
    galletitas = await db.into(db.productos).insert(
          ProductosCompanion.insert(nombre: 'Galletitas', costoCentavos: const Value(50000), precioCentavos: const Value(90000), stock: const Value(1)),
        );
    await guardarPromo(
      db,
      nombre: 'Merienda',
      articulos: [(productoId: yerba, cantidad: 1), (productoId: galletitas, cantidad: 1)],
      markupBp: 3000,
      usuarioId: usuarioId,
    );
  });
  tearDown(() => db.close());

  test('aparece en la búsqueda, se cobra y desaparece cuando se acaba un artículo', () async {
    final c = VentaControlador(db);
    await c.cargarTodo();

    c.campoTexto.text = 'merienda';
    expect(c.coincidencias.map((p) => p.nombre), ['Merienda']);

    c.agregarProducto(c.coincidencias.single);
    c.elegirMedio(ComposicionPago.efectivo);
    expect(c.resultado!.totalCentavos, 200000);
    await c.cobrarActual();

    // Se llevó las galletitas (había 1): la promo ya no alcanza.
    final gall = await (db.select(db.productos)..where((p) => p.id.equals(galletitas))).getSingle();
    final ye = await (db.select(db.productos)..where((p) => p.id.equals(yerba))).getSingle();
    expect(gall.stock, 0);
    expect(ye.stock, 2);

    c.campoTexto.text = 'merienda';
    expect(c.coincidencias, isEmpty);
    expect(c.catalogoVisible.any((p) => p.nombre == 'Merienda'), false);
    c.dispose();
  });
}

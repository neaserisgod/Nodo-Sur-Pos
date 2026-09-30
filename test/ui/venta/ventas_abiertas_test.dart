import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_cierre.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/data/repositorio_ventas_abiertas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/venta.dart';
import 'package:la_plazoleta/ui/venta/venta_controlador.dart';
import '../../helpers/base_para_tests.dart';

/// Ventas abiertas (Bruno, 2026-09-29): la venta permanece y se puede armar
/// más de una a la vez.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late int usuarioId;
  late int sesionId;
  late Producto coca;
  late Producto fernet;

  Future<VentaControlador> nuevoControlador() async {
    final c = VentaControlador(db);
    await c.cargarTodo();
    return c;
  }

  // El guardado corre en cola, fuera del camino de la venta: los tests
  // esperan a que termine antes de mirar la base.
  Future<void> esperarGuardado() => Future<void>.delayed(const Duration(milliseconds: 50));

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Bruno'));
    sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    final idCoca = await db.into(db.productos).insert(
          ProductosCompanion.insert(
            nombre: 'Coca',
            precioCentavos: const Value(112000),
            costoCentavos: const Value(80000),
            stock: const Value(20),
          ),
        );
    final idFernet = await db.into(db.productos).insert(
          ProductosCompanion.insert(nombre: 'Fernet', precioCentavos: const Value(900000), stock: const Value(10)),
        );
    coca = await (db.select(db.productos)..where((p) => p.id.equals(idCoca))).getSingle();
    fernet = await (db.select(db.productos)..where((p) => p.id.equals(idFernet))).getSingle();
  });
  tearDown(() => db.close());

  test('la venta armada sobrevive a cerrar y volver a abrir la pantalla', () async {
    final c1 = await nuevoControlador();
    c1.agregarProducto(coca);
    c1.agregarProducto(coca);
    c1.elegirMedio(ComposicionPago.efectivo);
    await esperarGuardado();
    c1.dispose();

    final c2 = await nuevoControlador();
    expect(c2.carrito, hasLength(1));
    expect((c2.carrito.single as LineaVentaPorUnidad).cantidad, 2);
    expect(c2.medioElegido, ComposicionPago.efectivo);
    expect(c2.cantidadPestanas, 1);
    c2.dispose();
  });

  test('dos ventas a la vez: cada una conserva lo suyo al cambiar de pestaña', () async {
    final c = await nuevoControlador();
    c.agregarProducto(coca);
    c.nuevaVenta();
    expect(c.cantidadPestanas, 2);
    expect(c.carrito, isEmpty);
    c.agregarProducto(fernet);

    c.cambiarAPestana(0);
    expect(c.carrito.single.nombreProducto, 'Coca');
    c.cambiarAPestana(1);
    expect(c.carrito.single.nombreProducto, 'Fernet');
    await esperarGuardado();
    c.dispose();

    final c2 = await nuevoControlador();
    expect(c2.cantidadPestanas, 2);
    expect(c2.resumenPestanas.map((p) => p.lineas), [1, 1]);
    c2.dispose();
  });

  test('nueva venta con la actual vacía no abre otra pestaña', () async {
    final c = await nuevoControlador();
    c.nuevaVenta();
    expect(c.cantidadPestanas, 1);
    c.dispose();
  });

  test('cobrar una pestaña la cierra y deja la otra intacta; no queda fila en la base', () async {
    final c = await nuevoControlador();
    c.agregarProducto(coca);
    c.nuevaVenta();
    c.agregarProducto(fernet);
    c.elegirMedio(ComposicionPago.efectivo);

    final ventaId = await c.cobrarActual();
    expect(ventaId, isNotNull);
    expect(c.cantidadPestanas, 1);
    expect(c.carrito.single.nombreProducto, 'Coca');
    await esperarGuardado();

    final abiertas = await cargarVentasAbiertas(db, sesionId);
    expect(abiertas, hasLength(1));
    expect(abiertas.single.lineas.single.nombreProducto, 'Coca');
    c.dispose();
  });

  test('Esc (cancelar) con dos ventas cierra la pestaña y borra su fila', () async {
    final c = await nuevoControlador();
    c.agregarProducto(coca);
    c.nuevaVenta();
    c.agregarProducto(fernet);
    await esperarGuardado();
    c.cancelarVenta();
    await esperarGuardado();
    expect(c.cantidadPestanas, 1);
    expect(await cargarVentasAbiertas(db, sesionId), hasLength(1));
    c.dispose();
  });

  test('no se puede cerrar la caja con una venta abierta; descartarla lo permite', () async {
    final c = await nuevoControlador();
    c.agregarProducto(coca);
    await esperarGuardado();
    c.dispose();

    await expectLater(
      cerrarSesion(
        db,
        sesionId: sesionId,
        usuarioId: usuarioId,
        efectivoContadoCentavos: 0,
        mpContadoCentavos: 0,
        lataContadoCentavos: 0,
      ),
      throwsA(isA<VentasAbiertasPendientesException>()),
    );

    await descartarVentasAbiertas(db, sesionId);
    await cerrarSesion(
      db,
      sesionId: sesionId,
      usuarioId: usuarioId,
      efectivoContadoCentavos: 0,
      mpContadoCentavos: 0,
      lataContadoCentavos: 0,
    );
    final sesion = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).getSingle();
    expect(sesion.estado, 'CERRADA');
  });
}

// Entregar un encargue con seña desde Venta (rediseño v4, etapa 8.4): el cliente solo paga lo que falta; la seña ya está en la caja.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_cierre.dart';
import 'package:la_plazoleta/data/repositorio_encargues.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/ui/venta/venta_controlador.dart';
import '../../helpers/base_para_tests.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late int usuarioId;
  late int sesionId;
  late int coca; // $1.120 c/u

  Future<VentaControlador> nuevoControlador() async {
    final c = VentaControlador(db);
    await c.cargarTodo();
    return c;
  }

  Future<int> encargar({required int sena, bool enEfectivo = true, int cantidad = 5}) => crearEncargueApartando(
    db,
    nombreCliente: 'María',
    lineas: [LineaEncargueNueva(productoId: coca, cantidad: cantidad)],
    usuarioId: usuarioId,
    senaCentavos: sena,
    senaEsEfectivo: enEfectivo,
    sesionCajaId: sesionId,
  );

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 1000000);
    coca = await db.into(db.productos).insert(
      ProductosCompanion.insert(nombre: 'Coca', precioCentavos: const Value(112000), costoCentavos: const Value(80000), stock: const Value(20)),
    );
  });
  tearDown(() => db.close());

  test('el panel sabe cuánto es seña y cuánto falta, y los pagos suman solo lo que falta', () async {
    final id = await encargar(sena: 300000); // 5 × 1.120 = 5.600 → total en efectivo 5.600 (redondeo a $100 no cambia nada)
    final c = await nuevoControlador();
    await c.cargarEncargue(id);
    c.elegirMedio(ComposicionPago.efectivo);

    expect(c.senaAplicadaCentavos, 300000);
    expect(c.aCobrarCentavos, c.resultado!.totalCentavos - 300000);
    final pagos = c.construirPagos()!;
    expect(pagos.fold<int>(0, (s, p) => s + p.montoCentavos), c.aCobrarCentavos);
    c.dispose();
  });

  test('una venta común no tiene seña', () async {
    final c = await nuevoControlador();
    c.agregarProducto((await db.select(db.productos).get()).firstWhere((p) => p.id == coca));
    c.elegirMedio(ComposicionPago.efectivo);
    expect(c.senaAplicadaCentavos, 0);
    expect(c.aCobrarCentavos, c.resultado!.totalCentavos);
    c.dispose();
  });

  test('cobrar: queda UNA venta por el total, el cajón recibe solo el resto y el encargue se cierra', () async {
    final id = await encargar(sena: 300000);
    final conSena = await estadoCajaEnVivo(db, sesionId);
    final c = await nuevoControlador();
    await c.cargarEncargue(id);
    c.elegirMedio(ComposicionPago.efectivo);
    final total = c.resultado!.totalCentavos;
    final ventaId = await c.cobrarActual();
    expect(ventaId, isNotNull);

    final venta = await (db.select(db.ventas)..where((v) => v.id.equals(ventaId!))).getSingle();
    expect(venta.totalCentavos, total);
    final fin = await estadoCajaEnVivo(db, sesionId);
    expect(fin.efectivoEsperadoCentavos - conSena.efectivoEsperadoCentavos, total - 300000);
    expect(await listarEnarguesPendientes(db), isEmpty);
    expect(c.senaAplicadaCentavos, 0, reason: 'después de cobrar no queda seña en pantalla');
    c.dispose();
  });

  test('seña que cubre todo: no hay nada que cobrar y se cobra igual, sin pagos nuevos', () async {
    final id = await encargar(sena: 560000, cantidad: 5); // 5.600 = el total
    final c = await nuevoControlador();
    await c.cargarEncargue(id);
    c.elegirMedio(ComposicionPago.efectivo);
    expect(c.aCobrarCentavos, 0);
    expect(c.construirPagos(), isEmpty);
    expect(await c.cobrarActual(), isNotNull);
    expect(await listarEnarguesPendientes(db), isEmpty);
    c.dispose();
  });

  test('mixto con seña: el efectivo y Mercado Pago reparten solo lo que falta', () async {
    final id = await encargar(sena: 200000);
    final c = await nuevoControlador();
    await c.cargarEncargue(id);
    c.elegirMedio(ComposicionPago.mixto);
    final aCobrar = c.aCobrarCentavos!;
    c.confirmarMixto(100000, canalResto: 'qr');
    final pagos = c.construirPagos()!;
    expect(pagos.map((p) => p.montoCentavos), [100000, aCobrar - 100000]);
    c.dispose();
  });

  test('la venta retomada después de cerrar la app sigue sabiendo la seña', () async {
    final id = await encargar(sena: 300000);
    final c1 = await nuevoControlador();
    await c1.cargarEncargue(id);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    c1.dispose();

    final c2 = await nuevoControlador();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    c2.elegirMedio(ComposicionPago.efectivo);
    expect(c2.encargueId, id);
    expect(c2.senaAplicadaCentavos, 300000);
    c2.dispose();
  });
}

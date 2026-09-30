import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_carga_historica.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/recargo_cigarrillos.dart';
import 'package:la_plazoleta/domain/venta.dart';
import 'package:la_plazoleta/ui/carga_historica/carga_historica_controlador.dart';
import '../../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
  });
  tearDown(() => db.close());

  Future<int> crearProducto() => db.into(db.productos).insert(
        ProductosCompanion.insert(nombre: 'Fernet', precioCentavos: const Value(500000), stock: const Value(10)),
      );

  test('guardar sin fecha deja un error y no llega a guardar nada', () async {
    final c = CargaHistoricaControlador(db, usuarioId: usuarioId);
    await c.cargarTodo();

    final resultado = await c.guardarDia();

    expect(resultado, isNull);
    expect(c.error, isNotNull);
  });

  test('guardar sin ninguna venta agregada a la tanda deja un error', () async {
    final c = CargaHistoricaControlador(db, usuarioId: usuarioId);
    await c.cargarTodo();
    c.elegirFecha(DateTime(2026, 8, 20));

    final resultado = await c.guardarDia();

    expect(resultado, isNull);
    expect(c.error, isNotNull);
  });

  test('agregar una venta a la tanda vacía el carrito y sube el total de la tanda', () async {
    await crearProducto();
    final c = CargaHistoricaControlador(db, usuarioId: usuarioId);
    await c.cargarTodo();
    c.elegirFecha(DateTime(2026, 8, 20));

    c.campoTexto.text = 'Fernet';
    c.agregarProducto(c.coincidencias.single);
    expect(c.carrito, hasLength(1));

    c.elegirMedio(ComposicionPago.efectivo);
    final agregada = c.agregarVentaALaTanda();

    expect(agregada, isTrue);
    expect(c.carrito, isEmpty); // el carrito se vacía para la próxima venta
    expect(c.ventasCargadas, hasLength(1));
    expect(c.totalTandaCentavos, 500000);
  });

  test('agregar la venta sin elegir medio de pago deja un error y no suma nada a la tanda', () async {
    await crearProducto();
    final c = CargaHistoricaControlador(db, usuarioId: usuarioId);
    await c.cargarTodo();
    c.elegirFecha(DateTime(2026, 8, 20));

    c.campoTexto.text = 'Fernet';
    c.agregarProducto(c.coincidencias.single);
    final agregada = c.agregarVentaALaTanda();

    expect(agregada, isFalse);
    expect(c.error, isNotNull);
    expect(c.ventasCargadas, isEmpty);
  });

  test('guardar con datos válidos crea el día cerrado y devuelve el id de la sesión', () async {
    await crearProducto();
    final c = CargaHistoricaControlador(db, usuarioId: usuarioId);
    await c.cargarTodo();
    c.elegirFecha(DateTime(2026, 8, 20));
    c.campoTexto.text = 'Fernet';
    c.agregarProducto(c.coincidencias.single);
    c.elegirMedio(ComposicionPago.efectivo);
    c.agregarVentaALaTanda();

    final sesionId = await c.guardarDia();

    expect(sesionId, isNotNull);
    final sesion = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId!))).getSingle();
    expect(sesion.estado, 'CERRADA');
    expect(sesion.fechaApertura, DateTime(2026, 8, 20));
  });

  test('la venta guardada no toca el stock del producto', () async {
    final productoId = await crearProducto();
    final c = CargaHistoricaControlador(db, usuarioId: usuarioId);
    await c.cargarTodo();
    c.elegirFecha(DateTime(2026, 8, 20));
    c.campoTexto.text = 'Fernet';
    c.agregarProducto(c.coincidencias.single);
    c.elegirMedio(ComposicionPago.efectivo);
    c.agregarVentaALaTanda();

    await c.guardarDia();

    final producto = await (db.select(db.productos)..where((p) => p.id.equals(productoId))).getSingle();
    expect(producto.stock, 10);
  });

  test('avisa la fecha del último día cargado, para ayudar a cargar en orden', () async {
    final productoId = await crearProducto();
    final producto = await (db.select(db.productos)..where((p) => p.id.equals(productoId))).getSingle();
    final venta = Venta(lineas: [lineaDesdeProducto(producto, cantidad: 1)]);
    final resultado = calcularTotalVenta(
      venta: venta,
      composicionPago: ComposicionPago.efectivo,
      configRecargoCigarrillos: const ConfigRecargoCigarrillos(primerAtadoCentavos: 30000, atadoAdicionalCentavos: 10000),
      pasoRedondeoCentavos: 100,
    );
    final medioEfectivoId =
        (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
    await cargarDiaHistoricoDesdeVentas(
      db,
      fecha: DateTime(2026, 8, 19),
      usuarioId: usuarioId,
      ventas: [
        VentaHistoricaPendiente(
          venta: venta,
          resultado: resultado,
          pagos: [
            PagoARegistrar(medioPagoId: medioEfectivoId, montoCentavos: resultado.totalCentavos, esEfectivo: true),
          ],
        ),
      ],
    );

    final c = CargaHistoricaControlador(db, usuarioId: usuarioId);
    await c.cargarTodo();

    expect(c.ultimoDiaCargado, DateTime(2026, 8, 19));
  });
}

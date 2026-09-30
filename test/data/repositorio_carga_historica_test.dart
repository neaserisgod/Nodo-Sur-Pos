import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_carga_historica.dart';
import 'package:la_plazoleta/data/repositorio_historial.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/recargo_cigarrillos.dart';
import 'package:la_plazoleta/domain/venta.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int medioEfectivoId;
  late int medioVirtualId;

  const config = ConfigRecargoCigarrillos(primerAtadoCentavos: 30000, atadoAdicionalCentavos: 10000);

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Bruno'));
    medioEfectivoId =
        (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
    medioVirtualId =
        (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle()).id;
  });
  tearDown(() => db.close());

  Future<Producto> crearProducto({int stock = 10, int precioCentavos = 500000, int? costoCentavos}) async {
    final id = await db.into(db.productos).insert(
          ProductosCompanion.insert(
            nombre: 'Fernet',
            precioCentavos: Value(precioCentavos),
            costoCentavos: Value(costoCentavos),
            stock: Value(stock),
          ),
        );
    return (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
  }

  VentaHistoricaPendiente ventaDeUnaLinea(Producto producto, {int cantidad = 1}) {
    final linea = lineaDesdeProducto(producto, cantidad: cantidad);
    final venta = Venta(lineas: [linea]);
    final resultado = calcularTotalVenta(
      venta: venta,
      composicionPago: ComposicionPago.efectivo,
      configRecargoCigarrillos: config,
      pasoRedondeoCentavos: 10000,
    );
    return VentaHistoricaPendiente(
      venta: venta,
      resultado: resultado,
      pagos: [
        PagoARegistrar(medioPagoId: medioEfectivoId, montoCentavos: resultado.totalCentavos, esEfectivo: true),
      ],
    );
  }

  test('crea la sesión cerrada del día, con las ventas de la tanda y sin diferencia (arqueo automático)', () async {
    final producto = await crearProducto();
    final pendiente = ventaDeUnaLinea(producto);

    final sesionId = await cargarDiaHistoricoDesdeVentas(
      db,
      fecha: DateTime(2026, 8, 20),
      usuarioId: usuarioId,
      ventas: [pendiente],
    );

    final sesion = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).getSingle();
    expect(sesion.estado, 'CERRADA');
    expect(sesion.fechaApertura, DateTime(2026, 8, 20));
    expect(sesion.diferenciaCentavos, 0);
    expect(sesion.mpDiferenciaCentavos, 0);

    final ventas = await (db.select(db.ventas)..where((v) => v.sesionCajaId.equals(sesionId))).get();
    expect(ventas, hasLength(1));
    expect(ventas.single.fecha, DateTime(2026, 8, 20));
    expect(ventas.single.totalCentavos, pendiente.resultado.totalCentavos);
  });

  test('no toca el stock actual del producto vendido', () async {
    final producto = await crearProducto(stock: 10);
    final pendiente = ventaDeUnaLinea(producto, cantidad: 3);

    await cargarDiaHistoricoDesdeVentas(
      db,
      fecha: DateTime(2026, 8, 20),
      usuarioId: usuarioId,
      ventas: [pendiente],
    );

    final actualizado = await (db.select(db.productos)..where((p) => p.id.equals(producto.id))).getSingle();
    expect(actualizado.stock, 10); // sin cambios

    final movimientos =
        await (db.select(db.movimientosDeStock)..where((m) => m.productoId.equals(producto.id))).get();
    expect(movimientos, isEmpty); // ningún rastro de descuento (Regla 8 no aplica: no se movió nada)
  });

  test('dos ventas de la misma tanda caen bajo la misma sesión', () async {
    final producto = await crearProducto();

    final sesionId = await cargarDiaHistoricoDesdeVentas(
      db,
      fecha: DateTime(2026, 8, 20),
      usuarioId: usuarioId,
      ventas: [ventaDeUnaLinea(producto), ventaDeUnaLinea(producto)],
    );

    final ventas = await (db.select(db.ventas)..where((v) => v.sesionCajaId.equals(sesionId))).get();
    expect(ventas, hasLength(2));
  });

  test('el día cargado aparece en el Historial', () async {
    final producto = await crearProducto();
    await cargarDiaHistoricoDesdeVentas(
      db,
      fecha: DateTime(2026, 8, 20),
      usuarioId: usuarioId,
      ventas: [ventaDeUnaLinea(producto)],
    );

    final dias = await listarDias(db);
    expect(dias, hasLength(1));
    expect(dias.single.sesion.fechaApertura, DateTime(2026, 8, 20));
  });

  test('la línea queda con el costo actual del producto (costo-foto de hoy)', () async {
    final producto = await crearProducto(costoCentavos: 300000);

    await cargarDiaHistoricoDesdeVentas(
      db,
      fecha: DateTime(2026, 8, 20),
      usuarioId: usuarioId,
      ventas: [ventaDeUnaLinea(producto)],
    );

    final linea = await db.select(db.lineasDeVenta).getSingle();
    expect(linea.costoUnitarioCentavos, 300000);
  });

  test('el pendiente de cigarrillos se arrastra entre dos días históricos cargados en orden', () async {
    final cigarrilloId = await db.into(db.productos).insert(
          ProductosCompanion.insert(
            nombre: 'Marlboro Box',
            tipoCigarrillo: const Value('atado'),
            precioCentavos: const Value(450000),
            stock: const Value(20),
          ),
        );
    final cigarrillo = await (db.select(db.productos)..where((p) => p.id.equals(cigarrilloId))).getSingle();
    final linea = lineaDesdeProducto(cigarrillo, cantidad: 1);
    final venta = Venta(lineas: [linea]);
    final resultado = calcularTotalVenta(
      venta: venta,
      composicionPago: ComposicionPago.virtual,
      configRecargoCigarrillos: config,
      pasoRedondeoCentavos: 10000,
    );
    final pendiente = VentaHistoricaPendiente(
      venta: venta,
      resultado: resultado,
      pagos: [
        PagoARegistrar(medioPagoId: medioVirtualId, montoCentavos: resultado.totalCentavos, esEfectivo: false),
      ],
    );

    // Día 1: se vende un cigarrillo por QR (nunca genera efectivo real para
    // separar) → todo el precio de lista queda pendiente para el día
    // siguiente (Regla 6).
    await cargarDiaHistoricoDesdeVentas(
      db,
      fecha: DateTime(2026, 8, 19),
      usuarioId: usuarioId,
      ventas: [pendiente],
    );

    final sesion2Id = await cargarDiaHistoricoDesdeVentas(
      db,
      fecha: DateTime(2026, 8, 20),
      usuarioId: usuarioId,
      ventas: [],
    );

    final sesion2 = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesion2Id))).getSingle();
    expect(sesion2.lataPendienteCentavos, greaterThan(0));
  });
}

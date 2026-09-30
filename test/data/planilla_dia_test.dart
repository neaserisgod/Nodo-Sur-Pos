import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/planilla_dia.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/recargo_cigarrillos.dart';
import 'package:la_plazoleta/domain/venta.dart';

import '../helpers/planilla_fixture.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int proveedorFId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    proveedorFId = (await (db.select(db.proveedores)..where((p) => p.codigo.equals('F'))).getSingle()).id;
  });
  tearDown(() => db.close());

  test('un día histórico: cada renglón queda en la grilla de su medio, con la letra de proveedor', () async {
    final sesionId = await cargarDiaHistoricoFixture(
      db,
      fecha: DateTime(2026, 8, 20),
      usuarioId: usuarioId,
      cajaInicialNormalCentavos: 15000000,
      cajaInicialCigarrillosCentavos: 0,
      efectivoRealContadoCentavos: 15050000,
      mpContadoCentavos: 0,
      renglonesEfectivo: [
        RenglonPlanillaFixture(montoCentavos: 50000, detalle: 'Fiambre 300g', proveedorId: proveedorFId),
      ],
      renglonesMp: [
        RenglonPlanillaFixture(montoCentavos: 30000, detalle: 'Gaseosa'),
      ],
      gastos: const [],
    );

    final datos = await armarDatosPlanilla(db, sesionId);

    expect(datos.renglonesEfectivo, hasLength(1));
    expect(datos.renglonesEfectivo.single.letraProveedor, 'F');
    expect(datos.renglonesMp, hasLength(1));
    expect(datos.totalEfectivoCentavos, 50000);
    expect(datos.totalMpCentavos, 30000);
  });

  test(
      'pago mixto: un renglón en cada grilla, con el monto real de cada Pago '
      '(bug real, corrección de Dueño: no cada línea repartida proporcionalmente)', () async {
    final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    final medioEfectivo =
        (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
    final medioVirtual =
        (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle()).id;
    final productoId = await db.into(db.productos).insert(
          ProductosCompanion.insert(nombre: 'Fernet', precioCentavos: const Value(1000000), stock: const Value(5)),
        );
    final producto = await (db.select(db.productos)..where((p) => p.id.equals(productoId))).getSingle();

    final linea = lineaDesdeProducto(producto, cantidad: 1);
    final venta = Venta(lineas: [linea]);
    final resultado = calcularTotalVenta(
      venta: venta,
      composicionPago: ComposicionPago.mixto,
      configRecargoCigarrillos: const ConfigRecargoCigarrillos(primerAtadoCentavos: 30000, atadoAdicionalCentavos: 10000),
      pasoRedondeoCentavos: 10000,
    );
    // Un monto cualquiera en efectivo, no necesariamente la mitad — no
    // tiene por qué coincidir con ninguna proporción de la línea.
    const enEfectivo = 300000;
    await registrarVenta(
      db,
      venta: venta,
      resultado: resultado,
      sesionCajaId: sesionId,
      usuarioId: usuarioId,
      pagos: [
        PagoARegistrar(medioPagoId: medioEfectivo, montoCentavos: enEfectivo, esEfectivo: true),
        PagoARegistrar(medioPagoId: medioVirtual, montoCentavos: resultado.totalCentavos - enEfectivo, esEfectivo: false),
      ],
    );

    final datos = await armarDatosPlanilla(db, sesionId);

    expect(datos.renglonesEfectivo, hasLength(1));
    expect(datos.renglonesMp, hasLength(1));
    // Los montos son exactamente los de cada Pago, sin decimales ni reparto
    // proporcional de la línea.
    expect(datos.renglonesEfectivo.single.montoCentavos, enEfectivo);
    expect(datos.renglonesMp.single.montoCentavos, resultado.totalCentavos - enEfectivo);
    // El DETALLE es el mismo de los dos lados: lo que se vendió, no de dónde
    // salió la plata de cada renglón.
    expect(datos.renglonesEfectivo.single.detalle, 'Fernet');
    expect(datos.renglonesMp.single.detalle, 'Fernet');
  });

  test('una venta con varios productos de distintos proveedores: un renglón, todas las letras', () async {
    final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    final medioEfectivo =
        (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
    final proveedorWId = (await (db.select(db.proveedores)..where((p) => p.codigo.equals('W'))).getSingle()).id;

    final quesoId = await db.into(db.productos).insert(
          ProductosCompanion.insert(
            nombre: 'Queso barra',
            proveedorId: Value(proveedorFId),
            precioCentavos: const Value(500000),
            stock: const Value(10),
          ),
        );
    final cervezaId = await db.into(db.productos).insert(
          ProductosCompanion.insert(
            nombre: 'Cerveza',
            proveedorId: Value(proveedorWId),
            precioCentavos: const Value(300000),
            stock: const Value(10),
          ),
        );
    final queso = await (db.select(db.productos)..where((p) => p.id.equals(quesoId))).getSingle();
    final cerveza = await (db.select(db.productos)..where((p) => p.id.equals(cervezaId))).getSingle();

    final venta = Venta(lineas: [lineaDesdeProducto(queso, cantidad: 1), lineaDesdeProducto(cerveza, cantidad: 1)]);
    final resultado = calcularTotalVenta(
      venta: venta,
      composicionPago: ComposicionPago.efectivo,
      configRecargoCigarrillos: const ConfigRecargoCigarrillos(primerAtadoCentavos: 30000, atadoAdicionalCentavos: 10000),
      pasoRedondeoCentavos: 10000,
    );
    await registrarVenta(
      db,
      venta: venta,
      resultado: resultado,
      sesionCajaId: sesionId,
      usuarioId: usuarioId,
      pagos: [PagoARegistrar(medioPagoId: medioEfectivo, montoCentavos: resultado.totalCentavos, esEfectivo: true)],
    );

    final datos = await armarDatosPlanilla(db, sesionId);

    expect(datos.renglonesEfectivo, hasLength(1)); // un solo renglón para toda la venta
    expect(datos.renglonesEfectivo.single.detalle, 'Queso barra, Cerveza');
    expect(datos.renglonesEfectivo.single.letraProveedor, 'F,W'); // "Múltiple: poner todas las letras"
    expect(datos.renglonesEfectivo.single.montoCentavos, resultado.totalCentavos);
  });

  test('apertura y cierre reflejan la sesión tal cual, "queda en el cajón" incluido', () async {
    final sesionId = await cargarDiaHistoricoFixture(
      db,
      fecha: DateTime(2026, 8, 20),
      usuarioId: usuarioId,
      cajaInicialNormalCentavos: 15000000,
      cajaInicialCigarrillosCentavos: 0,
      efectivoRealContadoCentavos: 15050000,
      mpContadoCentavos: 0,
      renglonesEfectivo: [
        RenglonPlanillaFixture(montoCentavos: 50000, detalle: 'Cigarrillos', esCigarrillo: true),
      ],
      renglonesMp: const [],
      gastos: const [],
    );

    final datos = await armarDatosPlanilla(db, sesionId);

    expect(datos.sesion.fondoInicialCentavos, 15000000);
    expect(datos.quedaEnCajonCentavos, 15000000); // se separó todo lo del cigarrillo (50000) del contado (15050000)
  });

  test(
      'cigarrillo con el recargo cobrado en efectivo y el precio de lista por QR: '
      r'$300 y $4.500 exactos, sin decimales (el caso de la demo del ítem 3)', () async {
    final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    final medioEfectivo =
        (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
    final medioVirtual =
        (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle()).id;
    final cigarrilloId = await db.into(db.productos).insert(
          ProductosCompanion.insert(
            nombre: 'Marlboro Box',
            tipoCigarrillo: const Value('atado'),
            precioCentavos: const Value(450000),
            stock: const Value(10),
          ),
        );
    final cigarrillo = await (db.select(db.productos)..where((p) => p.id.equals(cigarrilloId))).getSingle();

    final venta = Venta(lineas: [lineaDesdeProducto(cigarrillo, cantidad: 1)]);
    final resultado = calcularTotalVenta(
      venta: venta,
      composicionPago: ComposicionPago.mixto,
      configRecargoCigarrillos: const ConfigRecargoCigarrillos(primerAtadoCentavos: 30000, atadoAdicionalCentavos: 10000),
      pasoRedondeoCentavos: 10000,
    );
    expect(resultado.recargoCigarrillosCentavos, 30000); // $300
    expect(resultado.totalCentavos, 480000); // $4.500 + $300, redondo

    await registrarVenta(
      db,
      venta: venta,
      resultado: resultado,
      sesionCajaId: sesionId,
      usuarioId: usuarioId,
      pagos: [
        PagoARegistrar(medioPagoId: medioEfectivo, montoCentavos: 30000, esEfectivo: true), // el recargo
        PagoARegistrar(medioPagoId: medioVirtual, montoCentavos: 450000, esEfectivo: false), // precio de lista
      ],
    );

    final datos = await armarDatosPlanilla(db, sesionId);

    expect(datos.renglonesEfectivo.single.montoCentavos, 30000); // $300,00 exactos
    expect(datos.renglonesMp.single.montoCentavos, 450000); // $4.500,00 exactos
    // El renglón de $300 sin esta aclaración se lee como si se hubiera
    // vendido un Marlboro a $300 (El dueño, revisión del demo del ítem 3).
    expect(datos.renglonesEfectivo.single.detalle, 'Marlboro Box + recargo QR');
    expect(datos.renglonesMp.single.detalle, 'Marlboro Box + recargo QR');
  });

  test('sin recargo de cigarrillos, el detalle no lleva la aclaración de más', () async {
    final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    final medioEfectivo =
        (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
    final productoId = await db.into(db.productos).insert(
          ProductosCompanion.insert(nombre: 'Fernet', precioCentavos: const Value(1000000), stock: const Value(5)),
        );
    final producto = await (db.select(db.productos)..where((p) => p.id.equals(productoId))).getSingle();
    final venta = Venta(lineas: [lineaDesdeProducto(producto, cantidad: 1)]);
    final resultado = calcularTotalVenta(
      venta: venta,
      composicionPago: ComposicionPago.efectivo,
      configRecargoCigarrillos: const ConfigRecargoCigarrillos(primerAtadoCentavos: 30000, atadoAdicionalCentavos: 10000),
      pasoRedondeoCentavos: 10000,
    );
    await registrarVenta(
      db,
      venta: venta,
      resultado: resultado,
      sesionCajaId: sesionId,
      usuarioId: usuarioId,
      pagos: [PagoARegistrar(medioPagoId: medioEfectivo, montoCentavos: resultado.totalCentavos, esEfectivo: true)],
    );

    final datos = await armarDatosPlanilla(db, sesionId);

    expect(datos.renglonesEfectivo.single.detalle, 'Fernet');
  });

  test('cigarrillos: sin letra, aunque la línea tenga un proveedor cargado (Regla 6)', () async {
    final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    final medioEfectivo =
        (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
    final ventaId = await db.into(db.ventas).insert(
          VentasCompanion.insert(
            sesionCajaId: sesionId,
            usuarioId: usuarioId,
            subtotalCentavos: 350000,
            totalCentavos: 350000,
          ),
        );
    await db.into(db.lineasDeVenta).insert(
          LineasDeVentaCompanion.insert(
            ventaId: ventaId,
            nombreProductoFoto: 'Marlboro Box',
            proveedorIdFoto: Value(proveedorFId), // cargado "por error"/legado: no debería importar
            tipoCigarrillo: const Value('atado'),
            precioUnitarioCentavos: 350000,
          ),
        );
    await db.into(db.pagos).insert(
          PagosCompanion.insert(ventaId: ventaId, medioPagoId: medioEfectivo, montoCentavos: 350000),
        );

    final datos = await armarDatosPlanilla(db, sesionId);

    expect(datos.renglonesEfectivo.single.letraProveedor, isNull);
  });
}

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_deuda_proveedores.dart';
import 'package:la_plazoleta/data/repositorio_facturas_compra.dart';
import 'package:la_plazoleta/data/repositorio_sincronizacion.dart';
import 'package:la_plazoleta/data/repositorio_vinculos_factura.dart';
import 'package:la_plazoleta/domain/aplicar_factura.dart';
import 'package:la_plazoleta/domain/vinculo_factura.dart';

import '../helpers/base_para_tests.dart';

/// La cuenta corriente y las facturas de compra viajan entre equipos desde la v61 (El dueño, 2026-10-07: "independizar la apk de
/// desktop"): una factura cargada en el celular deja la deuda en la PC, no se puede volver a cargar ahí y lo aprendido le sirve.
void main() {
  late AppDatabase pc;
  late AppDatabase celular;

  /// El mismo proveedor y el mismo producto en los dos equipos (como si ya hubieran sincronizado el catálogo).
  Future<({int proveedor, int producto, int usuario})> catalogo(AppDatabase db) async {
    final usuario = (await db.select(db.usuarios).get()).first.id;
    await db.customStatement("UPDATE usuarios SET global_id = 'usuario-inicial' WHERE id = $usuario");
    final proveedor = await db.into(db.proveedores).insert(
          ProveedoresCompanion.insert(codigo: 'EL', nombre: 'Elpar', globalId: const Value('prov-elpar')),
        );
    final producto = await db.into(db.productos).insert(
          ProductosCompanion.insert(
            nombre: 'Crema 200',
            proveedorId: Value(proveedor),
            precioCentavos: const Value(300000),
            costoCentavos: const Value(180000),
            stock: const Value(3),
            globalId: const Value('prod-crema'),
          ),
        );
    return (proveedor: proveedor, producto: producto, usuario: usuario);
  }

  /// Todo lo de [origen] a [destino], tabla por tabla en el orden de la sync. Devuelve las filas que no se pudieron aplicar.
  Future<List<Map<String, dynamic>>> sincronizar(AppDatabase origen, AppDatabase destino) async {
    final fallidas = <Map<String, dynamic>>[];
    for (final tabla in tablasSincronizables.keys) {
      fallidas.addAll(await aplicarCambios(destino, tabla: tabla, filas: await cambiosDesde(origen, tabla: tabla, desde: 0)));
    }
    return fallidas;
  }

  setUp(() {
    pc = baseDeTest();
    celular = baseDeTest();
  });
  tearDown(() async {
    await pc.close();
    await celular.close();
  });

  test('una factura aplicada en el celular llega a la PC: deuda, stock, costo y "ya se cargó"', () async {
    final c = await catalogo(celular);
    final p = await catalogo(pc);
    // `actualizado_en` va en segundos: el costo nuevo tiene que caer en un segundo posterior al alta del producto para ganar.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await aplicarFactura(
      celular,
      proveedorId: c.proveedor,
      numero: '0011-00266439',
      tipo: 'A',
      totalImpresoCentavos: 877421,
      lineas: [LineaParaAplicar(productoId: c.producto, unidades: 4, totalCentavos: 877421)],
      sumarStock: true,
      usuarioId: c.usuario,
    );

    expect(await sincronizar(celular, pc), isEmpty);

    expect(await saldoDeuda(pc, p.proveedor), 877421);
    final crema = await (pc.select(pc.productos)..where((t) => t.id.equals(p.producto))).getSingle();
    expect(crema.stock, 7, reason: 'el stock viaja por el movimiento, como una venta');
    expect(crema.costoCentavos, 219400);
    await expectLater(
      aplicarFactura(
        pc,
        proveedorId: p.proveedor,
        numero: '0011-00266439',
        tipo: 'A',
        totalImpresoCentavos: 877421,
        lineas: [LineaParaAplicar(productoId: p.producto, unidades: 4, totalCentavos: 877421)],
        sumarStock: true,
        usuarioId: p.usuario,
      ),
      throwsA(isA<FacturaYaCargadaException>()),
    );
  });

  test('deshacerla en la PC se ve en el celular', () async {
    final c = await catalogo(celular);
    await catalogo(pc);
    final r = await aplicarFactura(
      celular,
      proveedorId: c.proveedor,
      numero: '1',
      tipo: 'A',
      totalImpresoCentavos: 100000,
      lineas: [LineaParaAplicar(productoId: c.producto, unidades: 1, totalCentavos: 100000)],
      sumarStock: false,
      usuarioId: c.usuario,
    );
    await sincronizar(celular, pc);
    final enLaPc = await (pc.select(pc.facturasCompra)).getSingle();
    // El reloj de `actualizado_en` va en segundos: la edición tiene que caer en un segundo posterior para ganar.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await deshacerFactura(pc, facturaId: enLaPc.id, usuarioId: (await pc.select(pc.usuarios).get()).first.id);

    await sincronizar(pc, celular);
    final enElCelular = await (celular.select(celular.facturasCompra)..where((t) => t.id.equals(r.facturaId))).getSingle();
    expect(enElCelular.deshechaEn, isNotNull);
    expect(await saldoDeuda(celular, c.proveedor), 0, reason: 'el cargo anulado viaja con la anulación');
  });

  test('lo aprendido en un equipo le sirve al otro, y la misma clave aprendida en los dos queda en una sola fila', () async {
    final c = await catalogo(celular);
    final p = await catalogo(pc);
    await aprenderVinculo(celular, proveedorId: c.proveedor, productoId: c.producto, codigo: '123', descripcion: 'CREMA 200', unidadesPorCantidad: 6);
    await aprenderVinculo(pc, proveedorId: p.proveedor, productoId: p.producto, codigo: '123', descripcion: 'CREMA 200');
    await asociarCuit(celular, proveedorId: c.proveedor, cuit: '30670378213');
    await asociarCuit(pc, proveedorId: p.proveedor, cuit: '30670378213');

    expect(await sincronizar(celular, pc), isEmpty, reason: 'la clave repetida no choca con la local');

    final vinculos = await vinculosDe(pc, p.proveedor);
    expect(vinculos, hasLength(2), reason: 'una fila por código y una por descripción, sin duplicar');
    expect(vinculos.firstWhere((v) => v.tipoClave == TipoClaveVinculo.codigo).productoId, p.producto);
    expect((await proveedoresPorCuit(pc, '30670378213')).map((x) => x.id), [p.proveedor]);
  });

  test('un pago desde la caja viaja con su movimiento de caja', () async {
    final c = await catalogo(celular);
    final p = await catalogo(pc);
    await cargarDeuda(celular, proveedorId: c.proveedor, montoCentavos: 50000, fecha: DateTime(2026, 10, 7), usuarioId: c.usuario);
    await pagarDeuda(celular, proveedorId: c.proveedor, montoCentavos: 20000, origen: OrigenPagoDeuda.fuera, usuarioId: c.usuario);

    expect(await sincronizar(celular, pc), isEmpty);
    expect(await saldoDeuda(pc, p.proveedor), 30000);
  });
}

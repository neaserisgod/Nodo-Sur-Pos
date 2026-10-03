import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/numero_venta.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/recargo_cigarrillos.dart';
import 'package:la_plazoleta/domain/venta.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;

import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
  });
  tearDown(() => db.close());

  Future<String?> cobrarUna() async {
    final productoId = await db.into(db.productos).insert(
          ProductosCompanion.insert(nombre: 'Caramelo', precioCentavos: const Value(10000), stock: const Value(50)),
        );
    final venta = Venta(lineas: [
      LineaVentaPorUnidad(productoId: '$productoId', nombreProducto: 'Caramelo', proveedorId: null, cantidad: 1, precioUnitarioCentavos: 10000),
    ]);
    final resultado = calcularTotalVenta(
      venta: venta,
      composicionPago: ComposicionPago.efectivo,
      configRecargoCigarrillos: const ConfigRecargoCigarrillos(primerAtadoCentavos: 0, atadoAdicionalCentavos: 0),
      pasoRedondeoCentavos: 100,
    );
    final efectivo = await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle();
    final (id, _) = await registrarVenta(
      db,
      venta: venta,
      resultado: resultado,
      sesionCajaId: sesionId,
      usuarioId: usuarioId,
      pagos: [PagoARegistrar(medioPagoId: efectivo.id, montoCentavos: resultado.totalCentavos, esEfectivo: true)],
    );
    return (await (db.select(db.ventas)..where((v) => v.id.equals(id))).getSingle()).numero;
  }

  test('cada venta lleva el prefijo del equipo y un correlativo que sube de a uno', () async {
    final a = await cobrarUna();
    final b = await cobrarUna();
    expect(a, matches(RegExp(r'^[A-Z]{2}-0001$')));
    expect(b, '${a!.substring(0, 2)}-0002');
  });

  test('el prefijo se genera una sola vez y queda guardado', () async {
    final p1 = await prefijoDeVentas(db, azar: Random(1));
    final p2 = await prefijoDeVentas(db, azar: Random(2));
    expect(p2, p1);
  });

  test('etiquetaDeVenta usa el número global y cae al id en las ventas viejas', () {
    expect(etiquetaDeVenta(id: 7, numero: 'K7-0123'), 'K7-0123');
    expect(etiquetaDeVenta(id: 7), '#7');
  });
}

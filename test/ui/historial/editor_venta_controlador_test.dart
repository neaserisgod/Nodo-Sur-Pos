import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_historial.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/recargo_cigarrillos.dart';
import 'package:la_plazoleta/domain/venta.dart';
import 'package:la_plazoleta/ui/historial/editor_venta_controlador.dart';

import '../../helpers/planilla_fixture.dart';
import '../../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int usuarioEditorId;
  late int sesionId;
  late Producto cocaCola;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    usuarioEditorId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Ayuda finde'));
    sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    final idCoca = await db.into(db.productos).insert(
          ProductosCompanion.insert(nombre: 'Coca-Cola', precioCentavos: const Value(112000), stock: const Value(20)),
        );
    cocaCola = await (db.select(db.productos)..where((p) => p.id.equals(idCoca))).getSingle();
  });
  tearDown(() => db.close());

  Future<int> ventaCoca2Efectivo() async {
    final medioEfectivoId =
        (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
    final linea = lineaDesdeProducto(cocaCola, cantidad: 2);
    final venta = Venta(lineas: [linea]);
    final resultado = calcularTotalVenta(
      venta: venta,
      composicionPago: ComposicionPago.efectivo,
      configRecargoCigarrillos: const ConfigRecargoCigarrillos(primerAtadoCentavos: 30000, atadoAdicionalCentavos: 10000),
      pasoRedondeoCentavos: 10000,
    );
    final (ventaId, _) = await registrarVenta(
      db,
      venta: venta,
      resultado: resultado,
      sesionCajaId: sesionId,
      usuarioId: usuarioId,
      pagos: [PagoARegistrar(medioPagoId: medioEfectivoId, montoCentavos: resultado.totalCentavos, esEfectivo: true)],
    );
    return ventaId;
  }

  test('cargarTodo reconstruye las líneas y detecta el medio de pago original', () async {
    final ventaId = await ventaCoca2Efectivo();
    final c = EditorVentaControlador(db, ventaId: ventaId, usuarioId: usuarioEditorId);

    await c.cargarTodo();

    expect(c.lineas, hasLength(1));
    expect((c.lineas.single as LineaVentaPorUnidad).cantidad, 2);
    expect(c.medioElegido, ComposicionPago.efectivo);
  });

  test('cambiarCantidad recalcula el subtotal en vivo', () async {
    final ventaId = await ventaCoca2Efectivo();
    final c = EditorVentaControlador(db, ventaId: ventaId, usuarioId: usuarioEditorId);
    await c.cargarTodo();

    c.cambiarCantidad(0, 5);

    expect((c.lineas.single as LineaVentaPorUnidad).cantidad, 5);
    expect(c.subtotalCentavos, 112000 * 5);
  });

  test('quitarLinea saca la línea del carrito', () async {
    final ventaId = await ventaCoca2Efectivo();
    final c = EditorVentaControlador(db, ventaId: ventaId, usuarioId: usuarioEditorId);
    await c.cargarTodo();

    c.quitarLinea(0);

    expect(c.lineas, isEmpty);
  });

  test('buscar encuentra productos del catálogo por nombre', () async {
    final ventaId = await ventaCoca2Efectivo();
    final c = EditorVentaControlador(db, ventaId: ventaId, usuarioId: usuarioEditorId);
    await c.cargarTodo();

    c.buscar('coca');

    expect(c.resultadosBusqueda, hasLength(1));
  });

  test('guardar sin motivo no hace nada (Regla 9 exige dejar el motivo)', () async {
    final ventaId = await ventaCoca2Efectivo();
    final c = EditorVentaControlador(db, ventaId: ventaId, usuarioId: usuarioEditorId);
    await c.cargarTodo();

    final ok = await c.guardar(motivo: '');

    expect(ok, isFalse);
    final venta = await (db.select(db.ventas)..where((v) => v.id.equals(ventaId))).getSingle();
    expect(venta.editadaPorId, isNull);
  });

  test('guardar con motivo persiste los cambios vía editarVenta', () async {
    final ventaId = await ventaCoca2Efectivo();
    final c = EditorVentaControlador(db, ventaId: ventaId, usuarioId: usuarioEditorId);
    await c.cargarTodo();
    c.cambiarCantidad(0, 3);

    final ok = await c.guardar(motivo: 'Eran 3, no 2');

    expect(ok, isTrue);
    final venta = await (db.select(db.ventas)..where((v) => v.id.equals(ventaId))).getSingle();
    expect(venta.totalCentavos, c.resultado!.totalCentavos);
    expect(venta.editadaPorId, usuarioEditorId);
    expect(venta.motivoEdicion, 'Eran 3, no 2');
  });

  group('venta de carga histórica (sin producto real)', () {
    test('la línea se reconstruye como renglón libre editable, y agregarLineaLibre funciona', () async {
      final sesionHistoricaId = await cargarDiaHistoricoFixture(
        db,
        fecha: DateTime(2026, 8, 20),
        usuarioId: usuarioId,
        cajaInicialNormalCentavos: 0,
        cajaInicialCigarrillosCentavos: 0,
        efectivoRealContadoCentavos: 50000,
        mpContadoCentavos: 0,
        renglonesEfectivo: [RenglonPlanillaFixture(montoCentavos: 50000, detalle: 'Fiambre 300g')],
        renglonesMp: const [],
        gastos: const [],
      );
      final ventaId = (await ventasDelDia(db, sesionHistoricaId)).single.id;

      final c = EditorVentaControlador(db, ventaId: ventaId, usuarioId: usuarioEditorId);
      await c.cargarTodo();

      expect(c.lineas.single.nombreProducto, 'Fiambre 300g');
      expect(c.lineas.single.esVarios, isTrue);

      c.agregarLineaLibre(detalle: 'Gaseosa suelta', montoCentavos: 20000);
      expect(c.lineas, hasLength(2));

      final ok = await c.guardar(motivo: 'Se había olvidado la gaseosa');
      expect(ok, isTrue);
    });
  });
}

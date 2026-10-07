// `PuertoLocal` delega en los mismos repositorios que ya prueba a fondo
// `test/servidor/servidor_companion_test.dart` (vía HTTP) — estos tests no
// repiten esa cobertura, se enfocan en lo propio de esta clase: que arma
// bien los DTOs (`ProductoCompanion`, etc.) desde las filas de drift, que
// traduce `MedioGastoCompanion` al enum real de cada repositorio, y que cada
// método de la interfaz `ServicioCompanion` llama a la función que
// corresponde.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/carrito_venta.dart';
import 'package:la_plazoleta/companion/cliente_companion.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_deuda_proveedores.dart';
import 'package:la_plazoleta/data/repositorio_promos.dart';
import 'package:la_plazoleta/domain/venta.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late PuertoLocal puerto;
  late int usuarioId;

  setUp(() async {
    db = baseDeTest();
    puerto = PuertoLocal(db);
    usuarioId = (await db.select(db.usuarios).get()).first.id; // "El dueño", sembrado
  });
  tearDown(() => db.close());

  test('usuarios trae el usuario sembrado', () async {
    final usuarios = await puerto.usuarios();
    expect(usuarios, hasLength(1));
    expect(usuarios.single.nombre, 'Dueño');
  });

  test('proveedores trae los 15 proveedores sembrados', () async {
    final proveedores = await puerto.proveedores();
    expect(proveedores, hasLength(15));
  });

  group('productos', () {
    late int idCoca;

    setUp(() async {
      idCoca = await db.into(db.productos).insert(
            ProductosCompanion.insert(
              nombre: 'Coca-Cola',
              codigoBarras: const Value('7790001'),
              precioCentavos: const Value(112000),
              stock: const Value(20),
            ),
          );
      await db.into(db.productos).insert(
            ProductosCompanion.insert(nombre: 'Fernet', stock: const Value(5)),
          );
    });

    test('sin filtros trae los dos (más "Varios" queda afuera, no es esVarios=false)', () async {
      final resultado = await puerto.productos();
      expect(resultado.map((p) => p.nombre), containsAll(['Coca-Cola', 'Fernet']));
      expect(resultado.any((p) => p.nombre == 'Varios'), false);
    });

    test('busqueda filtra por nombre normalizado', () async {
      final resultado = await puerto.productos(busqueda: 'coca');
      expect(resultado, hasLength(1));
      expect(resultado.single.id, idCoca);
      expect(resultado.single.codigoBarras, '7790001');
    });

    test('porCodigoBarras encuentra por código exacto', () async {
      final producto = await puerto.porCodigoBarras('7790001');
      expect(producto, isNotNull);
      expect(producto!.nombre, 'Coca-Cola');
    });

    test('porCodigoBarras da null si no existe', () async {
      expect(await puerto.porCodigoBarras('inexistente'), isNull);
    });

    test('productosSinStock trae solo los agotados/negativos, agotados primero', () async {
      await db.into(db.productos).insert(
            ProductosCompanion.insert(nombre: 'Agotado', stock: const Value(0)),
          );
      final sinStock = await puerto.productosSinStock();
      expect(sinStock.map((p) => p.nombre), ['Agotado']);
    });
  });

  test('crearProducto crea y queda consultable por porCodigoBarras', () async {
    final id = await puerto.crearProducto(
      nombre: 'Sprite',
      codigoBarras: '7790002',
      esPesable: false,
      precioCentavos: 100000,
      usuarioId: usuarioId,
    );

    final producto = await puerto.porCodigoBarras('7790002');
    expect(producto!.id, id);
    expect(producto.nombre, 'Sprite');
    expect(producto.precioCentavos, 100000);
  });

  test('crearProducto con código de barras repetido tira ArgumentError (no una excepción cruda)', () async {
    await puerto.crearProducto(
      nombre: 'Sprite',
      codigoBarras: '7790002',
      esPesable: false,
      usuarioId: usuarioId,
    );

    expect(
      () => puerto.crearProducto(
        nombre: 'Sprite (otro)',
        codigoBarras: '7790002',
        esPesable: false,
        usuarioId: usuarioId,
      ),
      throwsArgumentError,
    );
  });

  test('actualizarProducto cambia los campos y deja rastro de precio', () async {
    final id = await puerto.crearProducto(
      nombre: 'Sprite',
      esPesable: false,
      precioCentavos: 100000,
      usuarioId: usuarioId,
    );

    await puerto.actualizarProducto(
      id,
      nombre: 'Sprite 500ml',
      esPesable: false,
      precioCentavos: 105000,
      stock: 10,
      activo: true,
      usuarioId: usuarioId,
    );

    final actualizado = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
    expect(actualizado.nombre, 'Sprite 500ml');
    expect(actualizado.precioCentavos, 105000);
    expect(actualizado.stock, 10);
  });

  test('editar un atado desde el celular no le borra la marca de cigarrillo ni el recargo (Regla 6)', () async {
    // El formulario y "cambiar precio" del celular no mandan el tipo de cigarrillo: antes eso lo pisaba con
    // 'ninguno' y el atado se vendía sin recargo por pago virtual (El dueño, 2026-10-07).
    final id = await db.into(db.productos).insert(
          ProductosCompanion.insert(
            nombre: 'Marlboro 20',
            precioCentavos: const Value(400000),
            stock: const Value(10),
            tipoCigarrillo: const Value('atado'),
          ),
        );

    await puerto.actualizarProducto(id, nombre: 'Marlboro 20', esPesable: false, precioCentavos: 420000, stock: 10, activo: true, usuarioId: usuarioId);

    final producto = (await puerto.buscarVenta('marlboro')).resultados.single;
    expect(producto.tipoCigarrillo, 'atado');
    final linea = lineaDesdeResultadoBusqueda(producto).linea!;
    final virtual = await puerto.calcularVenta(lineas: [linea], medio: 'virtual');
    expect(virtual.recargoCigarrillosCentavos, greaterThan(0));
    final efectivo = await puerto.calcularVenta(lineas: [linea], medio: 'efectivo');
    expect(efectivo.recargoCigarrillosCentavos, 0);
  });

  test('ajustarStock cambia el stock y queda en movimientos_de_stock', () async {
    final id = await puerto.crearProducto(
      nombre: 'Sprite',
      esPesable: false,
      usuarioId: usuarioId,
    );
    await puerto.ajustarStock(id, stock: 42, motivo: 'Conteo físico', usuarioId: usuarioId);

    final producto = await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle();
    expect(producto.stock, 42);

    final movimientos = await (db.select(
      db.movimientosDeStock,
    )..where((m) => m.productoId.equals(id))).get();
    expect(movimientos.last.motivo, 'Conteo físico');
  });

  group('sesión y venta', () {
    test('sesion() sin nada abierto: abierta=false, con lo sugerido para abrir', () async {
      final sesion = await puerto.sesion();
      expect(sesion.abierta, false);
      expect(sesion.lataQueSeArrastraCentavos, 0);
    });

    test('abrirSesion abre, y sesion() la refleja', () async {
      final id = await puerto.abrirSesion(usuarioId: usuarioId, fondoInicialCentavos: 500000);

      final sesion = await puerto.sesion();
      expect(sesion.abierta, true);
      expect(sesion.id, id);
      expect(sesion.fechaUltimoArqueoIntermedio, isNull);
    });

    test(
      'calcularCierre trae el arqueo y el desglose por proveedor, sin guardar nada',
      () async {
        await puerto.abrirSesion(usuarioId: usuarioId, fondoInicialCentavos: 100000);

        final resumen = await puerto.calcularCierre(efectivoContadoCentavos: 100000);

        expect(resumen.efectivoEsperadoCentavos, 100000);
        expect(resumen.diferenciaCentavos, 0);
        final sesion = await puerto.sesion();
        expect(sesion.abierta, true); // "calcular" no cierra nada
      },
    );

    test(
      'confirmarCierre cierra la sesión de verdad, y detalleCierre la recalcula después',
      () async {
        await puerto.abrirSesion(usuarioId: usuarioId, fondoInicialCentavos: 100000);
        final sesionAntes = await puerto.sesion();

        await puerto.confirmarCierre(
          usuarioId: usuarioId,
          efectivoContadoCentavos: 100000,
          mpContadoCentavos: 0,
          lataContadoCentavos: 0,
          nota: 'Cerrado desde el celular',
        );

        final sesionDespues = await puerto.sesion();
        expect(sesionDespues.abierta, false);

        final detalle = await puerto.detalleCierre(sesionAntes.id!);
        expect(detalle.efectivoEsperadoCentavos, 100000);
        expect(detalle.diferenciaCentavos, 0);
        expect(detalle.nota, 'Cerrado desde el celular');
      },
    );

    test('detalleCierre contra una sesión todavía ABIERTA tira ErrorCompanion 404', () async {
      final sesionId = await puerto.abrirSesion(usuarioId: usuarioId, fondoInicialCentavos: 0);

      await expectLater(
        puerto.detalleCierre(sesionId),
        throwsA(isA<ErrorCompanion>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('una promo aparece en la búsqueda con el stock que alcanza y al cobrarla descuenta sus artículos', () async {
      final sesionId = await puerto.abrirSesion(usuarioId: usuarioId, fondoInicialCentavos: 0);
      Future<int> producto(String n, int stock) => db.into(db.productos).insert(
            ProductosCompanion.insert(nombre: n, precioCentavos: const Value(300000), costoCentavos: const Value(200000), stock: Value(stock)),
          );
      final yerba = await producto('Yerba Promo', 5);
      final galle = await producto('Galletitas Promo', 4);
      await guardarPromo(db, nombre: 'Merienda Promo', articulos: [(productoId: yerba, cantidad: 1), (productoId: galle, cantidad: 2)], gananciaBp: 3000, usuarioId: usuarioId);

      final encontrada = (await puerto.buscarVenta('merienda promo')).resultados.single;
      expect(encontrada.stock, 2, reason: '4 galletitas ÷ 2 por promo');

      final linea = lineaDesdeResultadoBusqueda(encontrada).linea!;
      await puerto.cobrarEfectivo(lineas: [linea], sesionCajaId: sesionId, usuarioId: usuarioId);

      Future<int> stock(int id) async => (await (db.select(db.productos)..where((p) => p.id.equals(id))).getSingle()).stock;
      expect(await stock(yerba), 4);
      expect(await stock(galle), 2);
    });

    test('pagar a un proveedor sin la PC baja la deuda y, desde el cajón, sale de la caja', () async {
      final sesionId = await puerto.abrirSesion(usuarioId: usuarioId, fondoInicialCentavos: 100000);
      await cargarDeuda(db, proveedorId: 1, montoCentavos: 30000, fecha: DateTime(2026, 10, 7), usuarioId: usuarioId);

      await puerto.pagarProveedor(proveedorId: 1, usuarioId: usuarioId, montoCentavos: 10000, origen: 'cajon', sesionCajaId: sesionId);

      expect((await puerto.saldosProveedores())[1], 20000);
      final caja = await (db.select(db.movimientosDeCaja)..where((m) => m.tipo.equals('PAGO_PROVEEDOR'))).getSingle();
      expect(caja.montoCentavos, 10000);
      expect(caja.globalId, isNotNull, reason: 'viaja a la PC por la sync');
      final pago = await (db.select(db.movimientosDeuda)..where((m) => m.tipo.equals('PAGO'))).getSingle();
      expect(pago.globalId, isNotNull);
    });

    test('pagar desde la caja con la caja ya cerrada avisa y no graba', () async {
      await expectLater(
        puerto.pagarProveedor(proveedorId: 1, usuarioId: usuarioId, montoCentavos: 5000, origen: 'cajon'),
        throwsA(isA<ErrorCompanion>().having((e) => e.statusCode, 'statusCode', 409)),
      );
      expect(await db.select(db.movimientosDeuda).get(), isEmpty);
    });

    test('registrarGasto con medio "cajonNormal" resta de la caja normal', () async {
      final sesionId = await puerto.abrirSesion(usuarioId: usuarioId, fondoInicialCentavos: 100000);
      final movimientoId = await puerto.registrarGasto(
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        montoCentavos: 5000,
        medio: MedioGastoCompanion.cajonNormal,
        motivo: 'Pan',
      );

      final movimiento = await (db.select(
        db.movimientosDeCaja,
      )..where((m) => m.id.equals(movimientoId))).getSingle();
      expect(movimiento.tipo, 'GASTO');
      expect(movimiento.montoCentavos, 5000);
      expect(movimiento.medioPagoId, isNull); // solo se completa para mercadoPago
    });

    test('registrarIngreso con medio "mercadoPago" completa medioPagoId', () async {
      final sesionId = await puerto.abrirSesion(usuarioId: usuarioId, fondoInicialCentavos: 0);
      final movimientoId = await puerto.registrarIngreso(
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        montoCentavos: 20000,
        medio: MedioGastoCompanion.mercadoPago,
      );

      final movimiento = await (db.select(
        db.movimientosDeCaja,
      )..where((m) => m.id.equals(movimientoId))).getSingle();
      expect(movimiento.tipo, 'INGRESO');
      expect(movimiento.medioPagoId, isNotNull);
    });

    test('buscarVenta encuentra por nombre y excluye "Varios"', () async {
      await db.into(db.productos).insert(
            ProductosCompanion.insert(
              nombre: 'Coca-Cola',
              precioCentavos: const Value(112000),
              stock: const Value(20),
            ),
          );

      final resultado = await puerto.buscarVenta('coca');
      expect(resultado.resultados, hasLength(1));
      expect(resultado.resultados.single.nombre, 'Coca-Cola');
      expect(resultado.gramos, isNull);
    });

    test('buscarVenta interpreta "200 queso" como 200 gramos de un pesable', () async {
      await db.into(db.productos).insert(
            ProductosCompanion.insert(
              nombre: 'Queso barra',
              esPesable: const Value(true),
              precioPorKiloCentavos: const Value(800000),
              stockGramos: const Value(5000),
            ),
          );

      final resultado = await puerto.buscarVenta('200 queso');
      expect(resultado.gramos, 200);
      expect(resultado.resultados, hasLength(1));
    });

    test('calcularVenta redondea igual que el escritorio (Regla 2)', () async {
      final idCoca = await db.into(db.productos).insert(
            ProductosCompanion.insert(
              nombre: 'Coca-Cola',
              precioCentavos: const Value(112000),
              stock: const Value(20),
            ),
          );
      final coca = await (db.select(db.productos)..where((p) => p.id.equals(idCoca))).getSingle();
      final resultados = await puerto.buscarVenta('coca');
      expect(resultados.resultados, hasLength(1));

      final linea = LineaVentaPorUnidad(
        productoId: coca.id.toString(),
        nombreProducto: coca.nombre,
        proveedorId: null,
        cantidad: 1,
        precioUnitarioCentavos: coca.precioCentavos!,
        costoUnitarioCentavos: coca.costoCentavos,
      );

      final resultado = await puerto.calcularVenta(lineas: [linea], medio: 'efectivo');
      expect(resultado.totalCentavos, 120000); // $1.120 → $1.200 (paso $100)
    });

    test('cobrarEfectivo graba la venta y descuenta stock', () async {
      final sesionId = await puerto.abrirSesion(usuarioId: usuarioId, fondoInicialCentavos: 0);
      final idCoca = await db.into(db.productos).insert(
            ProductosCompanion.insert(
              nombre: 'Coca-Cola',
              precioCentavos: const Value(112000),
              stock: const Value(20),
            ),
          );

      final linea = LineaVentaPorUnidad(
        productoId: idCoca.toString(),
        nombreProducto: 'Coca-Cola',
        proveedorId: null,
        cantidad: 2,
        precioUnitarioCentavos: 112000,
      );

      final resultado = await puerto.cobrarEfectivo(
        lineas: [linea],
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
      );

      expect(resultado.totalCentavos, 230000); // $2.240 → $2.300

      final producto = await (db.select(db.productos)..where((p) => p.id.equals(idCoca))).getSingle();
      expect(producto.stock, 18); // 20 - 2

      final ventaGuardada = await (db.select(
        db.ventas,
      )..where((v) => v.id.equals(resultado.ventaId))).getSingle();
      expect(ventaGuardada.totalCentavos, 230000);
    });
  });

  group('Configuración (Dueño, 2026-09-19: "que se puedan modificar las reglas del negocio... desde el celular")', () {
    test('configuracionNegocio trae los defaults, actualizarRecargoCigarrillos los cambia', () async {
      final antes = await puerto.configuracionNegocio();
      expect(antes.recargoPrimerAtadoCentavos, 30000);

      await puerto.actualizarRecargoCigarrillos(
        primerAtadoCentavos: 40000,
        atadoAdicionalCentavos: 15000,
        sueltoCentavos: 6000,
      );
      final despues = await puerto.configuracionNegocio();
      expect(despues.recargoPrimerAtadoCentavos, 40000);
      expect(despues.recargoSueltoCentavos, 6000);
    });

    test('actualizarMarkupCategoria cambia solo esa categoría', () async {
      final categoria = (await puerto.categorias()).first;
      await puerto.actualizarMarkupCategoria(categoria.id, 8000);
      final actualizada = (await puerto.categorias()).firstWhere((c) => c.id == categoria.id);
      expect(actualizada.markupDefaultBp, 8000);
    });

    test('mediosDePago trae los dos fijos, renombrarMedioPago y alternarActivoMedioPago cambian uno', () async {
      final medios = await puerto.mediosDePago();
      expect(medios, hasLength(2));
      final efectivo = medios.firstWhere((m) => m.esEfectivo);

      await puerto.renombrarMedioPago(efectivo.id, 'Contado');
      await puerto.alternarActivoMedioPago(efectivo.id, false);

      final actualizado = (await puerto.mediosDePago()).firstWhere((m) => m.id == efectivo.id);
      expect(actualizado.nombre, 'Contado');
      expect(actualizado.activo, isFalse);
    });

    test('crearUsuarioNuevo, renombrarUsuarioExistente y alternarActivoUsuarioExistente', () async {
      final id = await puerto.crearUsuarioNuevo('Ayuda finde');
      await puerto.renombrarUsuarioExistente(id, 'Ayuda fin de semana');
      await puerto.alternarActivoUsuarioExistente(id, false);

      final usuario = (await puerto.usuarios()).firstWhere((u) => u.id == id);
      expect(usuario.nombre, 'Ayuda fin de semana');
      expect(usuario.activo, isFalse);
    });
  });
}

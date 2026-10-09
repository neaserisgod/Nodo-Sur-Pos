import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_reposicion.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;
  late int proveedorId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db
        .into(db.usuarios)
        .insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    sesionId = await db
        .into(db.sesionesDeCaja)
        .insert(
          SesionesDeCajaCompanion.insert(
            usuarioAbrioId: usuarioId,
            fondoInicialCentavos: 0,
          ),
        );
    proveedorId = (await (db.select(
      db.proveedores,
    )..where((p) => p.codigo.equals('S'))).getSingle()).id;
  });
  tearDown(() => db.close());

  /// Crea una venta mínima con una línea de un proveedor, en una fecha dada.
  Future<void> crearVenta({
    required DateTime fecha,
    required int proveedorId,
    required int precioCentavos,
    int? costoCentavos,
  }) async {
    final ventaId = await db
        .into(db.ventas)
        .insert(
          VentasCompanion.insert(
            sesionCajaId: sesionId,
            usuarioId: usuarioId,
            fecha: Value(fecha),
            subtotalCentavos: precioCentavos,
            totalCentavos: precioCentavos,
          ),
        );
    await db
        .into(db.lineasDeVenta)
        .insert(
          LineasDeVentaCompanion.insert(
            ventaId: ventaId,
            nombreProductoFoto: 'Producto',
            proveedorIdFoto: Value(proveedorId),
            precioUnitarioCentavos: precioCentavos,
            costoUnitarioCentavos: Value(costoCentavos),
          ),
        );
  }

  Future<void> ponerColchon(int proveedorId, int colchonCentavos) {
    return (db.update(
      db.proveedores,
    )..where((p) => p.id.equals(proveedorId))).write(
      ProveedoresCompanion(colchonReposicionCentavos: Value(colchonCentavos)),
    );
  }

  Future<Proveedor> proveedorActual() => (db.select(
    db.proveedores,
  )..where((p) => p.id.equals(proveedorId))).getSingle();

  ResumenReposicionProveedor de(
    List<ResumenReposicionProveedor> lista,
    int proveedorId,
  ) => lista.firstWhere((r) => r.proveedor.id == proveedorId);

  group('reposicionActual', () {
    test('los proveedores con caja aparte quedan afuera, sea cual sea su código', () async {
      final codigos = (await reposicionActual(db)).map((r) => r.proveedor.codigo);
      expect(codigos, isNot(contains('SC')));
      expect(codigos, contains('S'));

      await db.customStatement("UPDATE proveedores SET caja_aparte = 0 WHERE codigo = 'SC'");
      await db.customStatement("UPDATE proveedores SET caja_aparte = 1 WHERE codigo = 'S'");
      final despues = (await reposicionActual(db)).map((r) => r.proveedor.codigo);
      expect(despues, contains('SC'));
      expect(despues, isNot(contains('S')));
    });

    test(
      'proveedor sin ventas: costo real 0, sugerido a separar es solo el colchón',
      () async {
        await ponerColchon(proveedorId, 5000);
        final lista = await reposicionActual(db);
        final r = de(lista, proveedorId);
        expect(r.vendidoCentavos, 0);
        expect(r.costoRealCentavos, 0);
        expect(r.pendienteSinSepararCentavos, 0);
        expect(r.sugeridoASepararCentavos, 5000);
        expect(r.separadoCentavos, 0);
        expect(r.separadoFecha, isNull);
      },
    );

    test(
      'suma el costo real de las ventas del proveedor y le suma el colchón al sugerido',
      () async {
        await ponerColchon(proveedorId, 2000);
        await crearVenta(
          fecha: DateTime.now(),
          proveedorId: proveedorId,
          precioCentavos: 1000,
          costoCentavos: 600,
        );
        await crearVenta(
          fecha: DateTime.now(),
          proveedorId: proveedorId,
          precioCentavos: 1000,
          costoCentavos: 600,
        );

        final r = de(await reposicionActual(db), proveedorId);
        expect(
          r.vendidoCentavos,
          2000,
        ); // precio, no costo (bug real: la planilla mostraba el costo acá)
        expect(r.costoRealCentavos, 1200);
        expect(r.pendienteSinSepararCentavos, 1200);
        expect(r.sugeridoASepararCentavos, 3200);
      },
    );

    test(
      'Distribuidora de Cigarrillos (SC) no aparece: sus ventas siempre dan cero acá (Regla 6)',
      () async {
        final lista = await reposicionActual(db);
        expect(lista.any((r) => r.proveedor.codigo == 'SC'), false);
      },
    );
  });

  group('separarProveedor', () {
    test(
      'congela el costo real MÁS el colchón (Regla 13: el colchón es ganancia real, se gasta al separar)',
      () async {
        await ponerColchon(proveedorId, 1000);
        await crearVenta(
          fecha: DateTime.now(),
          proveedorId: proveedorId,
          precioCentavos: 1000,
          costoCentavos: 700,
        );

        await separarProveedor(db, proveedorId: proveedorId);

        final r = de(await reposicionActual(db), proveedorId);
        expect(r.separadoCentavos, 1700); // 700 costo real + 1000 colchón
        expect(r.separadoFecha, isNotNull);
        expect(
          r.colchonCentavos,
          0,
        ); // se gastó al separar, arranca de nuevo en 0
      },
    );

    test(
      'lo que se venda después de separar se acumula aparte, sin tocar lo ya separado',
      () async {
        // Fechas fijas en vez de relativas a DateTime.now(): separarProveedor
        // ya acepta [fecha] explícita (mismo patrón que registrarPagoFijo) así
        // que no hace falta depender del reloj real ni de su precisión de
        // segundo para garantizar el orden entre corte y venta.
        await crearVenta(
          fecha: DateTime(2026, 8, 1, 10),
          proveedorId: proveedorId,
          precioCentavos: 1000,
          costoCentavos: 600,
        );
        await separarProveedor(
          db,
          proveedorId: proveedorId,
          fecha: DateTime(2026, 8, 1, 12),
        );

        // Venta posterior a la separación.
        await crearVenta(
          fecha: DateTime(2026, 8, 1, 15),
          proveedorId: proveedorId,
          precioCentavos: 500,
          costoCentavos: 300,
        );

        final r = de(await reposicionActual(db), proveedorId);
        expect(r.separadoCentavos, 600); // congelado, no le suma la venta nueva
        expect(
          r.pendienteSinSepararCentavos,
          300,
        ); // la venta nueva se acumula aparte
      },
    );

    test(
      'separar de nuevo antes de pagar suma a lo ya congelado, no lo reemplaza',
      () async {
        await crearVenta(
          fecha: DateTime(2026, 8, 1, 10),
          proveedorId: proveedorId,
          precioCentavos: 1000,
          costoCentavos: 600,
        );
        await separarProveedor(
          db,
          proveedorId: proveedorId,
          fecha: DateTime(2026, 8, 1, 12),
        );
        await crearVenta(
          fecha: DateTime(2026, 8, 1, 15),
          proveedorId: proveedorId,
          precioCentavos: 500,
          costoCentavos: 300,
        );
        await separarProveedor(
          db,
          proveedorId: proveedorId,
          fecha: DateTime(2026, 8, 1, 18),
        );

        final r = de(await reposicionActual(db), proveedorId);
        expect(
          r.separadoCentavos,
          900,
        ); // 600 + 300, no se pierde lo separado antes
        expect(r.pendienteSinSepararCentavos, 0);
      },
    );
  });

  group('pagarProveedor', () {
    test('pago exacto: separado vuelve a 0 y no deja arrastre', () async {
      await crearVenta(
        fecha: DateTime.now(),
        proveedorId: proveedorId,
        precioCentavos: 1000,
        costoCentavos: 600,
      );
      await separarProveedor(db, proveedorId: proveedorId);

      await pagarProveedor(
        db,
        proveedorId: proveedorId,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        montoCentavos: 600,
      );

      final r = de(await reposicionActual(db), proveedorId);
      expect(r.separadoCentavos, 0);
      expect(r.pendienteSinSepararCentavos, 0);
    });

    test(
      'pago de menos: la diferencia vuelve a pendiente sin separar, no se pierde',
      () async {
        await crearVenta(
          fecha: DateTime.now(),
          proveedorId: proveedorId,
          precioCentavos: 1000,
          costoCentavos: 600,
        );
        await separarProveedor(db, proveedorId: proveedorId); // separado = 600

        await pagarProveedor(
          db,
          proveedorId: proveedorId,
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          montoCentavos: 400,
        );

        final r = de(await reposicionActual(db), proveedorId);
        expect(r.separadoCentavos, 0);
        expect(
          r.pendienteSinSepararCentavos,
          200,
        ); // 600 - 400, no se perdió ni se dio por saldado
      },
    );

    test(
      'la diferencia de un pago parcial se suma a lo que se venda después',
      () async {
        await crearVenta(
          fecha: DateTime(2026, 8, 1, 10),
          proveedorId: proveedorId,
          precioCentavos: 1000,
          costoCentavos: 600,
        );
        await separarProveedor(
          db,
          proveedorId: proveedorId,
          fecha: DateTime(2026, 8, 1, 12),
        ); // separado = 600
        await pagarProveedor(
          db,
          proveedorId: proveedorId,
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          montoCentavos: 400,
        );

        await crearVenta(
          fecha: DateTime(2026, 8, 1, 15),
          proveedorId: proveedorId,
          precioCentavos: 500,
          costoCentavos: 300,
        );

        final r = de(await reposicionActual(db), proveedorId);
        expect(
          r.pendienteSinSepararCentavos,
          500,
        ); // 200 de arrastre + 300 de la venta nueva
      },
    );

    test('pagar guarda ultimoPagoFecha sin importar el medio de pago', () async {
      await actualizarProveedorNivel2(
        db,
        proveedorId: proveedorId,
        colchonReposicionCentavos: 0,
        medioPago:
            'Transferencia', // no toca ninguna caja, y aun así hay que registrar la fecha
      );
      await crearVenta(
        fecha: DateTime.now(),
        proveedorId: proveedorId,
        precioCentavos: 1000,
        costoCentavos: 600,
      );
      await separarProveedor(db, proveedorId: proveedorId);

      await pagarProveedor(
        db,
        proveedorId: proveedorId,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        montoCentavos: 600,
        fecha: DateTime(2026, 8, 20),
      );

      final proveedor = await proveedorActual();
      expect(proveedor.ultimoPagoFecha, DateTime(2026, 8, 20));
    });

    test(
      'proveedor en efectivo: el pago escribe un movimiento de caja PAGO_PROVEEDOR',
      () async {
        await crearVenta(
          fecha: DateTime.now(),
          proveedorId: proveedorId,
          precioCentavos: 1000,
          costoCentavos: 600,
        );
        await separarProveedor(db, proveedorId: proveedorId);

        await pagarProveedor(
          db,
          proveedorId: proveedorId,
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          montoCentavos: 600,
        );

        final movimiento =
            await (db.select(db.movimientosDeCaja)..where(
                  (m) =>
                      m.proveedorId.equals(proveedorId) &
                      m.tipo.equals('PAGO_PROVEEDOR'),
                ))
                .getSingle();
        expect(movimiento.montoCentavos, 600);
        // Sin nota, "SALIDAS/PAGOS" de la planilla imprimiría el monto sin
        // decir de qué es (bug encontrado generando la demo del ítem 3).
        expect(movimiento.nota, 'Pago a Distribuidora');
      },
    );

    test(
      'proveedor que cobra por Mercado Pago: el pago escribe un movimiento con medioPagoId = MP',
      () async {
        await actualizarProveedorNivel2(
          db,
          proveedorId: proveedorId,
          colchonReposicionCentavos: 0,
          medioPago: 'Mercado Pago',
        );
        await crearVenta(
          fecha: DateTime.now(),
          proveedorId: proveedorId,
          precioCentavos: 1000,
          costoCentavos: 600,
        );
        await separarProveedor(db, proveedorId: proveedorId);

        await pagarProveedor(
          db,
          proveedorId: proveedorId,
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          montoCentavos: 600,
        );

        final medioMp = (await (db.select(
          db.mediosDePago,
        )..where((m) => m.esEfectivo.equals(false))).getSingle()).id;
        final movimiento =
            await (db.select(db.movimientosDeCaja)..where(
                  (m) =>
                      m.proveedorId.equals(proveedorId) &
                      m.tipo.equals('PAGO_PROVEEDOR'),
                ))
                .getSingle();
        expect(movimiento.montoCentavos, 600);
        expect(movimiento.medioPagoId, medioMp);
      },
    );

    test(
      'proveedor que no cobra en efectivo ni Mercado Pago: pagar no escribe movimiento de caja',
      () async {
        await actualizarProveedorNivel2(
          db,
          proveedorId: proveedorId,
          colchonReposicionCentavos: 0,
          medioPago: 'Cuenta corriente',
        );
        await crearVenta(
          fecha: DateTime.now(),
          proveedorId: proveedorId,
          precioCentavos: 1000,
          costoCentavos: 600,
        );
        await separarProveedor(db, proveedorId: proveedorId);

        await pagarProveedor(
          db,
          proveedorId: proveedorId,
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          montoCentavos: 600,
        );

        final movimientos = await (db.select(
          db.movimientosDeCaja,
        )..where((m) => m.proveedorId.equals(proveedorId))).get();
        expect(movimientos, isEmpty);
        final r = de(await reposicionActual(db), proveedorId);
        expect(r.separadoCentavos, 0);
      },
    );
  });

  group('avisoASepararAlAbrir', () {
    test('solo lista proveedores con algo sugerido para separar', () async {
      await ponerColchon(proveedorId, 1000);
      final otroId = (await (db.select(
        db.proveedores,
      )..where((p) => p.codigo.equals('C'))).getSingle()).id;
      // otroId queda sin colchón ni ventas: no aparece en el aviso.
      expect(otroId, isNot(proveedorId));

      final aviso = await avisoASepararAlAbrir(db);
      expect(
        aviso.any((a) => a.nombre == 'Distribuidora' && a.montoCentavos == 1000),
        true,
      );
      expect(aviso.any((a) => a.nombre == 'Coca Cola'), false);
    });
  });

  group('alta desde el celular (El dueño, 2026-10-09)', () {
    test('crearProveedorConCodigoAutomatico arma el código con las iniciales y no repite', () async {
      final a = await crearProveedorConCodigoAutomatico(db, nombre: 'Coca Cola', diaPedido: 'Martes', medioPago: 'Transferencia', whatsapp: '294 412-3456');
      final b = await crearProveedorConCodigoAutomatico(db, nombre: 'Café Cordobés');
      final pa = await (db.select(db.proveedores)..where((p) => p.id.equals(a))).getSingle();
      final pb = await (db.select(db.proveedores)..where((p) => p.id.equals(b))).getSingle();
      expect(pa.codigo, 'CC');
      expect(pb.codigo, 'CC2');
      expect(pa.diaPedido, 'Martes');
      expect(pa.medioPago, 'Transferencia');
      expect(pa.whatsapp, '294 412-3456');
      expect(pa.globalId, isNotNull, reason: 'viaja a la PC por la sync');
    });

    test('lineasParaPedirAProveedor: bajo el mínimo, o agotado y vendido hace poco', () async {
      Future<int> producto(String nombre, {required int stock, int minimo = 0}) => db.into(db.productos).insert(
            ProductosCompanion.insert(nombre: nombre, proveedorId: Value(proveedorId), stock: Value(stock), stockMinimo: Value(minimo)),
          );
      await producto('Bajo el mínimo', stock: 2, minimo: 5);
      await producto('Con stock', stock: 20, minimo: 5);
      await producto('Agotado viejo', stock: 0);

      final lineas = await lineasParaPedirAProveedor(db, proveedorId);
      expect(lineas.map((l) => l.nombre), ['Bajo el mínimo']);
    });
  });

  group('actualizarProveedorNivel2', () {
    test('guarda colchón y medio de pago', () async {
      await actualizarProveedorNivel2(
        db,
        proveedorId: proveedorId,
        colchonReposicionCentavos: 1200,
        medioPago: 'Transferencia',
      );

      final proveedor = await proveedorActual();
      expect(proveedor.colchonReposicionCentavos, 1200);
      expect(proveedor.medioPago, 'Transferencia');
    });
  });

  group('actualizarProveedorAvanzado', () {
    test('guarda código, días de pedido/entrega y activo', () async {
      await actualizarProveedorAvanzado(
        db,
        proveedorId: proveedorId,
        codigo: 'SR',
        diaPedido: 'Lunes',
        diaEntrega: 'Martes',
        activo: false,
      );

      final proveedor = await proveedorActual();
      expect(proveedor.codigo, 'SR');
      expect(proveedor.diaPedido, 'Lunes');
      expect(proveedor.diaEntrega, 'Martes');
      expect(proveedor.activo, isFalse);
    });

    test(
      'con colchonReposicionCentavos, también lo guarda (segunda corrección post-revisión)',
      () async {
        await actualizarProveedorAvanzado(
          db,
          proveedorId: proveedorId,
          codigo: 'S',
          activo: true,
          colchonReposicionCentavos: 50000,
        );

        final proveedor = await proveedorActual();
        expect(proveedor.colchonReposicionCentavos, 50000);
      },
    );

    test(
      'sin colchonReposicionCentavos, no toca el valor que ya tenía',
      () async {
        await actualizarProveedorNivel2(
          db,
          proveedorId: proveedorId,
          colchonReposicionCentavos: 30000,
          medioPago: 'Efectivo',
        );

        await actualizarProveedorAvanzado(
          db,
          proveedorId: proveedorId,
          codigo: 'S',
          activo: true,
        );

        final proveedor = await proveedorActual();
        expect(proveedor.colchonReposicionCentavos, 30000);
      },
    );
  });

  group(
    'productosDeProveedor (segunda corrección post-revisión: tabla de productos del panel derecho)',
    () {
      test('resuelve costo/precio por unidad, y calcula el margen', () async {
        await db
            .into(db.productos)
            .insert(
              ProductosCompanion.insert(
                nombre: 'Coca-Cola',
                proveedorId: Value(proveedorId),
                costoCentavos: const Value(80000),
                precioCentavos: const Value(150000),
              ),
            );

        final productos = await productosDeProveedor(db, proveedorId);

        expect(productos, hasLength(1));
        expect(productos.first.nombre, 'Coca-Cola');
        expect(productos.first.costoCentavos, 80000);
        expect(productos.first.precioCentavos, 150000);
        // gananciaBpDesdeCostoYPrecio(80000, 150000) = 4667 bp = 46,67%.
        expect(productos.first.gananciaBp, 4667);
      });

      test('un pesable usa costo/precio por kilo, no por unidad', () async {
        await db
            .into(db.productos)
            .insert(
              ProductosCompanion.insert(
                nombre: 'Queso',
                proveedorId: Value(proveedorId),
                esPesable: const Value(true),
                costoPorKiloCentavos: const Value(500000),
                precioPorKiloCentavos: const Value(850000),
              ),
            );

        final productos = await productosDeProveedor(db, proveedorId);

        expect(productos.first.costoCentavos, 500000);
        expect(productos.first.precioCentavos, 850000);
      });

      test('sin costo cargado: margen null, no un número inventado', () async {
        await db
            .into(db.productos)
            .insert(
              ProductosCompanion.insert(
                nombre: 'Producto sin costo',
                proveedorId: Value(proveedorId),
                precioCentavos: const Value(50000),
              ),
            );

        final productos = await productosDeProveedor(db, proveedorId);

        expect(productos.first.costoCentavos, isNull);
        expect(productos.first.gananciaBp, isNull);
      });

      test('un producto desactivado no aparece', () async {
        await db
            .into(db.productos)
            .insert(
              ProductosCompanion.insert(
                nombre: 'Dado de baja',
                proveedorId: Value(proveedorId),
                activo: const Value(false),
              ),
            );

        final productos = await productosDeProveedor(db, proveedorId);

        expect(productos, isEmpty);
      });

      test('un producto de otro proveedor no aparece', () async {
        final otroId = (await (db.select(
          db.proveedores,
        )..where((p) => p.codigo.equals('F'))).getSingle()).id;
        await db
            .into(db.productos)
            .insert(
              ProductosCompanion.insert(
                nombre: 'De otro proveedor',
                proveedorId: Value(otroId),
              ),
            );

        final productos = await productosDeProveedor(db, proveedorId);

        expect(productos, isEmpty);
      });
    },
  );

  group(
    'productosTodos / productosSinProveedor (fase 13, ítems "Todos"/"Sin proveedor")',
    () {
      test('productosTodos incluye productos con y sin proveedor', () async {
        await db
            .into(db.productos)
            .insert(
              ProductosCompanion.insert(
                nombre: 'Con proveedor',
                proveedorId: Value(proveedorId),
              ),
            );
        await db
            .into(db.productos)
            .insert(ProductosCompanion.insert(nombre: 'Huérfano'));

        final productos = await productosTodos(db);

        expect(
          productos.map((p) => p.nombre),
          containsAll(['Con proveedor', 'Huérfano']),
        );
      });

      test('productosTodos no incluye productos dados de baja', () async {
        await db
            .into(db.productos)
            .insert(
              ProductosCompanion.insert(
                nombre: 'Dado de baja',
                proveedorId: Value(proveedorId),
                activo: const Value(false),
              ),
            );

        final productos = await productosTodos(db);

        expect(productos, isEmpty);
      });

      test('productosSinProveedor solo trae los huérfanos', () async {
        await db
            .into(db.productos)
            .insert(
              ProductosCompanion.insert(
                nombre: 'Con proveedor',
                proveedorId: Value(proveedorId),
              ),
            );
        await db
            .into(db.productos)
            .insert(ProductosCompanion.insert(nombre: 'Huérfano'));

        final productos = await productosSinProveedor(db);

        expect(productos, hasLength(1));
        expect(productos.first.nombre, 'Huérfano');
      });

      test(
        '"Varios" (sentinela del botón de venta rápida) no aparece en ninguna de las dos: sin proveedor propio y sin precio/costo, listarlo se vería como "producto sin completar" sin serlo',
        () async {
          final todos = await productosTodos(db);
          final sinProveedor = await productosSinProveedor(db);

          expect(todos.any((p) => p.nombre == 'Varios'), isFalse);
          expect(sinProveedor.any((p) => p.nombre == 'Varios'), isFalse);
        },
      );

      test('cada producto trae su id, para poder editarlo', () async {
        final id = await db
            .into(db.productos)
            .insert(
              ProductosCompanion.insert(
                nombre: 'Coca-Cola',
                proveedorId: Value(proveedorId),
              ),
            );

        final productos = await productosDeProveedor(db, proveedorId);

        expect(productos.first.id, id);
      });
    },
  );

  group('retenerGanancia (Regla 13)', () {
    test('suma al colchón que ya hubiera, no lo reemplaza', () async {
      await ponerColchon(proveedorId, 500);

      await retenerGanancia(db, proveedorId: proveedorId, montoCentavos: 1500);

      final proveedor = await proveedorActual();
      expect(proveedor.colchonReposicionCentavos, 2000);
    });
  });

  group('registrarRetiroProveedor (Regla 13)', () {
    test(
      'en efectivo: movimiento tipo RETIRO en la caja normal, sin medioPagoId',
      () async {
        await registrarRetiroProveedor(
          db,
          proveedorId: proveedorId,
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          montoCentavos: 30000,
          porMercadoPago: false,
        );

        final movimiento = await (db.select(
          db.movimientosDeCaja,
        )..where((m) => m.tipo.equals('RETIRO'))).getSingle();
        expect(movimiento.montoCentavos, 30000);
        expect(movimiento.proveedorId, proveedorId);
        expect(movimiento.medioPagoId, isNull);
        expect(movimiento.nota, contains('Distribuidora'));

        final cajaNormal = (await (db.select(
          db.cajas,
        )..where((c) => c.esLata.equals(false))).getSingle()).id;
        expect(movimiento.cajaId, cajaNormal);
      },
    );

    test('por Mercado Pago: mismo movimiento, con medioPagoId de MP', () async {
      await registrarRetiroProveedor(
        db,
        proveedorId: proveedorId,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        montoCentavos: 30000,
        porMercadoPago: true,
      );

      final movimiento = await (db.select(
        db.movimientosDeCaja,
      )..where((m) => m.tipo.equals('RETIRO'))).getSingle();
      final mp = await (db.select(
        db.mediosDePago,
      )..where((m) => m.esEfectivo.equals(false))).getSingle();
      expect(movimiento.medioPagoId, mp.id);
    });
  });

  group('gananciaPendienteDeProveedores (Regla 13)', () {
    test('ganancia desde el corte propio, no el de reposición', () async {
      await crearVenta(
        fecha: DateTime.now(),
        proveedorId: proveedorId,
        precioCentavos: 1000,
        costoCentavos: 600,
      );
      // Separar (reposición) no debería afectar la ganancia pendiente de revisar.
      await separarProveedor(db, proveedorId: proveedorId);

      final pendientes = await gananciaPendienteDeProveedores(db);
      final serra = pendientes.firstWhere((p) => p.proveedor.id == proveedorId);
      expect(serra.vendidoCentavos, 1000);
      expect(serra.gananciaCentavos, 400);
    });

    test('proveedor sin ventas no aparece en la lista', () async {
      final pendientes = await gananciaPendienteDeProveedores(db);
      expect(pendientes.any((p) => p.proveedor.id == proveedorId), false);
    });

    test('Distribuidora de Cigarrillos (SC) nunca aparece (Regla 6)', () async {
      final pendientes = await gananciaPendienteDeProveedores(db);
      expect(pendientes.any((p) => p.proveedor.codigo == 'SC'), false);
    });
  });

  group('revisarGananciaProveedor (Regla 13)', () {
    test(
      'retira todo en efectivo: sin colchón nuevo, un movimiento RETIRO',
      () async {
        await revisarGananciaProveedor(
          db,
          proveedorId: proveedorId,
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          gananciaCentavos: 1000,
          retiroEfectivoCentavos: 1000,
        );

        final proveedor = await proveedorActual();
        expect(proveedor.colchonReposicionCentavos, 0);
        expect(proveedor.gananciaRevisadaFecha, isNotNull);
        final movimientos = await (db.select(
          db.movimientosDeCaja,
        )..where((m) => m.tipo.equals('RETIRO'))).get();
        expect(movimientos, hasLength(1));
        expect(movimientos.first.montoCentavos, 1000);
      },
    );

    test('no retira nada: todo queda como colchón, sin movimiento', () async {
      await revisarGananciaProveedor(
        db,
        proveedorId: proveedorId,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        gananciaCentavos: 1000,
      );

      final proveedor = await proveedorActual();
      expect(proveedor.colchonReposicionCentavos, 1000);
      final movimientos = await (db.select(
        db.movimientosDeCaja,
      )..where((m) => m.tipo.equals('RETIRO'))).get();
      expect(movimientos, isEmpty);
    });

    test(
      'retiro mixto: parte efectivo, parte Mercado Pago, resto colchón',
      () async {
        await revisarGananciaProveedor(
          db,
          proveedorId: proveedorId,
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          gananciaCentavos: 1000,
          retiroEfectivoCentavos: 300,
          retiroMercadoPagoCentavos: 400,
        );

        final proveedor = await proveedorActual();
        expect(proveedor.colchonReposicionCentavos, 300); // 1000 - 300 - 400
        final movimientos = await (db.select(
          db.movimientosDeCaja,
        )..where((m) => m.tipo.equals('RETIRO'))).get();
        expect(movimientos, hasLength(2));
      },
    );

    test('suma al colchón que ya hubiera, no lo reemplaza', () async {
      await ponerColchon(proveedorId, 500);

      await revisarGananciaProveedor(
        db,
        proveedorId: proveedorId,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        gananciaCentavos: 1000,
        retiroEfectivoCentavos: 200,
      );

      final proveedor = await proveedorActual();
      expect(proveedor.colchonReposicionCentavos, 1300); // 500 + (1000 - 200)
    });

    test('no vuelve a contar la misma ganancia al día siguiente', () async {
      await crearVenta(
        fecha: DateTime(2026, 8, 1, 10),
        proveedorId: proveedorId,
        precioCentavos: 1000,
        costoCentavos: 600,
      );

      await revisarGananciaProveedor(
        db,
        proveedorId: proveedorId,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        gananciaCentavos: 400,
        fecha: DateTime(2026, 8, 1, 12),
      );

      // Sin ventas nuevas: ya no debería aparecer.
      final pendientes = await gananciaPendienteDeProveedores(db);
      expect(pendientes.any((p) => p.proveedor.id == proveedorId), false);
    });
  });

  group('gananciaPorMedioDesde — Regla 13, de qué medio sale el retiro', () {
    Future<void> crearVentaConPagos({
      required int precioCentavos,
      required int costoCentavos,
      required int efectivoCentavos,
      required int virtualCentavos,
      DateTime? fecha,
    }) async {
      final ventaId = await db
          .into(db.ventas)
          .insert(
            VentasCompanion.insert(
              sesionCajaId: sesionId,
              usuarioId: usuarioId,
              fecha: fecha == null ? const Value.absent() : Value(fecha),
              subtotalCentavos: precioCentavos,
              totalCentavos: precioCentavos,
            ),
          );
      await db
          .into(db.lineasDeVenta)
          .insert(
            LineasDeVentaCompanion.insert(
              ventaId: ventaId,
              nombreProductoFoto: 'Producto',
              proveedorIdFoto: Value(proveedorId),
              precioUnitarioCentavos: precioCentavos,
              costoUnitarioCentavos: Value(costoCentavos),
            ),
          );
      if (efectivoCentavos > 0) {
        final medioEfectivo = (await (db.select(
          db.mediosDePago,
        )..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
        await db
            .into(db.pagos)
            .insert(
              PagosCompanion.insert(
                ventaId: ventaId,
                medioPagoId: medioEfectivo,
                montoCentavos: efectivoCentavos,
              ),
            );
      }
      if (virtualCentavos > 0) {
        final medioVirtual = (await (db.select(
          db.mediosDePago,
        )..where((m) => m.esEfectivo.equals(false))).getSingle()).id;
        await db
            .into(db.pagos)
            .insert(
              PagosCompanion.insert(
                ventaId: ventaId,
                medioPagoId: medioVirtual,
                montoCentavos: virtualCentavos,
              ),
            );
      }
    }

    test(
      'venta 100% efectivo: toda la ganancia sugerida es efectivo',
      () async {
        await crearVentaConPagos(
          precioCentavos: 10000,
          costoCentavos: 6000,
          efectivoCentavos: 10000,
          virtualCentavos: 0,
        );

        final r = await gananciaPorMedioDesde(db, await proveedorActual());

        expect(r.efectivoCentavos, 4000);
        expect(r.virtualCentavos, 0);
      },
    );

    test(
      'venta 100% Mercado Pago: toda la ganancia sugerida es virtual',
      () async {
        await crearVentaConPagos(
          precioCentavos: 10000,
          costoCentavos: 6000,
          efectivoCentavos: 0,
          virtualCentavos: 10000,
        );

        final r = await gananciaPorMedioDesde(db, await proveedorActual());

        expect(r.efectivoCentavos, 0);
        expect(r.virtualCentavos, 4000);
      },
    );

    test(
      'venta mixta: la ganancia de esa venta se reparte a prorrata de lo cobrado en cada medio',
      () async {
        await crearVentaConPagos(
          precioCentavos: 10000,
          costoCentavos: 6000,
          efectivoCentavos: 7000,
          virtualCentavos: 3000,
        );

        final r = await gananciaPorMedioDesde(db, await proveedorActual());

        expect(r.efectivoCentavos, 2800); // 4000 * 7000/10000
        expect(r.virtualCentavos, 1200);
      },
    );

    test(
      'una venta sin pagos registrados no aporta al reparto, y no crashea dividiendo por cero',
      () async {
        // No debería pasar en una venta real, pero un día cargado a mano
        // (u otro dato viejo) podría no tener Pagos — bug real encontrado al
        // escribir este test: sin este guard, `prorratearGananciaPorMedio`
        // dividía por cero (0 efectivo + 0 virtual) y tiraba una excepción
        // real en medio del ritual de apertura.
        final ventaId = await db
            .into(db.ventas)
            .insert(
              VentasCompanion.insert(
                sesionCajaId: sesionId,
                usuarioId: usuarioId,
                subtotalCentavos: 10000,
                totalCentavos: 10000,
              ),
            );
        await db
            .into(db.lineasDeVenta)
            .insert(
              LineasDeVentaCompanion.insert(
                ventaId: ventaId,
                nombreProductoFoto: 'Producto',
                proveedorIdFoto: Value(proveedorId),
                precioUnitarioCentavos: 10000,
                costoUnitarioCentavos: const Value(6000),
              ),
            );

        final r = await gananciaPorMedioDesde(db, await proveedorActual());

        expect(r.efectivoCentavos, 0);
        expect(r.virtualCentavos, 0);
      },
    );

    test('acumula el reparto de varias ventas del proveedor', () async {
      await crearVentaConPagos(
        precioCentavos: 10000,
        costoCentavos: 6000,
        efectivoCentavos: 10000,
        virtualCentavos: 0,
      );
      await crearVentaConPagos(
        precioCentavos: 5000,
        costoCentavos: 3000,
        efectivoCentavos: 0,
        virtualCentavos: 5000,
      );

      final r = await gananciaPorMedioDesde(db, await proveedorActual());

      expect(r.efectivoCentavos, 4000);
      expect(r.virtualCentavos, 2000);
    });

    test(
      'respeta el corte de gananciaRevisadaFecha, igual que gananciaPendienteDeProveedores',
      () async {
        await crearVentaConPagos(
          precioCentavos: 10000,
          costoCentavos: 6000,
          efectivoCentavos: 10000,
          virtualCentavos: 0,
          fecha: DateTime(2026, 8, 1, 10),
        );
        await revisarGananciaProveedor(
          db,
          proveedorId: proveedorId,
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          gananciaCentavos: 4000,
          fecha: DateTime(2026, 8, 1, 12),
        );
        await crearVentaConPagos(
          precioCentavos: 2000,
          costoCentavos: 1000,
          efectivoCentavos: 0,
          virtualCentavos: 2000,
          fecha: DateTime(2026, 8, 1, 14),
        );

        final r = await gananciaPorMedioDesde(db, await proveedorActual());

        // Solo la segunda venta (posterior al corte) entra en la cuenta.
        expect(r.efectivoCentavos, 0);
        expect(r.virtualCentavos, 1000);
      },
    );
  });

  group(
    'reporteProveedores — "Reportes" (Dueño, 2026-09-06: reemplaza a "revisar ganancias")',
    () {
      test(
        'lista TODOS los proveedores activos (salvo Distribuidora de Cigarrillos), no solo los pendientes',
        () async {
          final reportes = await reporteProveedores(db);

          // Sin ninguna venta todavía: nada pendiente, pero el proveedor sigue
          // apareciendo en cero — a diferencia de proveedoresParaSeparar
          // (pensada para no interrumpir con ruido en la apertura), acá "ver
          // detalladamente todo" incluye los que están en cero.
          final serra = reportes.firstWhere(
            (r) => r.proveedor.id == proveedorId,
          );
          expect(serra.vendidoCentavos, 0);
          expect(serra.sugeridoASepararCentavos, 0);
          expect(serra.gananciaSinRevisarCentavos, 0);
          expect(reportes.any((r) => r.proveedor.codigo == 'SC'), false);
        },
      );

      test(
        'junta costo real/colchón/separado (corte de reposición) con la ganancia sin revisar (corte propio)',
        () async {
          await crearVenta(
            fecha: DateTime(2026, 8, 1, 10),
            proveedorId: proveedorId,
            precioCentavos: 100000,
            costoCentavos: 60000,
          );
          await ponerColchon(proveedorId, 5000);

          final reportes = await reporteProveedores(db);
          final serra = reportes.firstWhere(
            (r) => r.proveedor.id == proveedorId,
          );

          expect(serra.vendidoCentavos, 100000);
          expect(serra.costoRealCentavos, 60000);
          expect(serra.pendienteSinSepararCentavos, 60000);
          expect(serra.colchonCentavos, 5000);
          expect(serra.sugeridoASepararCentavos, 65000); // costo real + colchón
          expect(
            serra.gananciaSinRevisarCentavos,
            40000,
          ); // 100000 - 60000, corte independiente
        },
      );

      test(
        'separadoCentavos y separadoFecha reflejan la última separación',
        () async {
          await crearVenta(
            fecha: DateTime(2026, 8, 1, 10),
            proveedorId: proveedorId,
            precioCentavos: 100000,
            costoCentavos: 60000,
          );
          await separarProveedor(
            db,
            proveedorId: proveedorId,
            fecha: DateTime(2026, 8, 1, 12),
          );

          final reportes = await reporteProveedores(db);
          final serra = reportes.firstWhere(
            (r) => r.proveedor.id == proveedorId,
          );

          expect(serra.separadoCentavos, 60000);
          expect(serra.separadoFecha, DateTime(2026, 8, 1, 12));
          // Ya separado: no queda pendiente sin separar.
          expect(serra.pendienteSinSepararCentavos, 0);
          expect(serra.sugeridoASepararCentavos, 0);
        },
      );
    },
  );

  group('separar dividido entre cajón y Mercado Pago (Dueño, 2026-09-26)', () {
    late int medioEfectivoId;
    late int medioMpId;
    late int otroProveedorId;
    late int serraCigarrosId;

    setUp(() async {
      medioEfectivoId = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
      medioMpId = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle()).id;
      otroProveedorId = (await (db.select(db.proveedores)..where((p) => p.codigo.equals('F'))).getSingle()).id;
      serraCigarrosId = (await (db.select(db.proveedores)..where((p) => p.codigo.equals('SC'))).getSingle()).id;
    });

    /// Venta de una línea con sus pagos, en la sesión del setUp (o [sesion]).
    Future<void> vender({
      required int proveedor,
      required int precio,
      int? costo,
      bool cigarrillo = false,
      int efectivo = 0,
      int mp = 0,
      int? sesion,
    }) async {
      final ventaId = await db.into(db.ventas).insert(
            VentasCompanion.insert(
              sesionCajaId: sesion ?? sesionId,
              usuarioId: usuarioId,
              subtotalCentavos: precio,
              totalCentavos: efectivo + mp,
            ),
          );
      await db.into(db.lineasDeVenta).insert(
            LineasDeVentaCompanion.insert(
              ventaId: ventaId,
              nombreProductoFoto: cigarrillo ? 'Atado' : 'Producto',
              proveedorIdFoto: Value(proveedor),
              tipoCigarrillo: Value(cigarrillo ? 'atado' : 'ninguno'),
              precioUnitarioCentavos: precio,
              costoUnitarioCentavos: Value(costo),
            ),
          );
      if (efectivo > 0) {
        await db.into(db.pagos).insert(PagosCompanion.insert(ventaId: ventaId, medioPagoId: medioEfectivoId, montoCentavos: efectivo));
      }
      if (mp > 0) {
        await db.into(db.pagos).insert(PagosCompanion.insert(ventaId: ventaId, medioPagoId: medioMpId, montoCentavos: mp));
      }
    }

    test('lo vendido por MP va "de Mercado Pago"; lo vendido en efectivo, del cajón', () async {
      await vender(proveedor: proveedorId, precio: 100000, costo: 60000, efectivo: 100000);
      await vender(proveedor: proveedorId, precio: 50000, costo: 30000, mp: 50000);

      final r = de(await reposicionActual(db), proveedorId);
      expect(r.sugeridoASepararCentavos, 90000);
      expect(r.costoRealMpCentavos, 30000);
      expect(r.sugeridoASepararEfectivoCentavos, 60000);
    });

    test('un atado cobrado por QR corre a MP el costo vendido en efectivo, repartido en proporción', () async {
      await vender(proveedor: serraCigarrosId, precio: 300000, costo: 300000, cigarrillo: true, mp: 300000);
      await vender(proveedor: proveedorId, precio: 600000, costo: 400000, efectivo: 600000); // 2/3
      await vender(proveedor: otroProveedorId, precio: 300000, costo: 200000, efectivo: 300000); // 1/3

      final lista = await reposicionActual(db);
      expect(de(lista, proveedorId).costoRealMpCentavos, 200000);
      expect(de(lista, otroProveedorId).costoRealMpCentavos, 100000);
    });

    test('en un mixto con cigarrillos cuenta solo lo que entró por MP', () async {
      await vender(proveedor: serraCigarrosId, precio: 400000, costo: 400000, cigarrillo: true, efectivo: 330000, mp: 100000);
      await vender(proveedor: proveedorId, precio: 1000000, costo: 600000, efectivo: 1000000);

      expect(de(await reposicionActual(db), proveedorId).costoRealMpCentavos, 100000);
    });

    test('el colchón va entero del cajón', () async {
      await vender(proveedor: proveedorId, precio: 50000, costo: 30000, mp: 50000);
      await ponerColchon(proveedorId, 20000);

      final r = de(await reposicionActual(db), proveedorId);
      expect(r.sugeridoASepararCentavos, 50000);
      expect(r.costoRealMpCentavos, 30000);
      expect(r.sugeridoASepararEfectivoCentavos, 20000);
    });

    test('separar congela la parte MP, y lo vendido después arranca de cero', () async {
      await vender(proveedor: proveedorId, precio: 100000, costo: 60000, efectivo: 100000);
      await vender(proveedor: proveedorId, precio: 50000, costo: 30000, mp: 50000);
      await separarProveedor(db, proveedorId: proveedorId, fecha: DateTime.now().add(const Duration(seconds: 1)));

      final p = await proveedorActual();
      expect(p.separadoCentavos, 90000);
      expect(p.separadoMpCentavos, 30000);
      final r = de(await reposicionActual(db), proveedorId);
      expect(r.costoRealMpCentavos, 0);
      expect(r.separadoEfectivoCentavos, 60000);
    });

    test('pedido para un solo proveedor, el reparto igual se hace contra el día entero', () async {
      // resumenReposicionDeProveedor carga solo las líneas de ESTE
      // proveedor, pero la parte que le toca depende también del efectivo
      // que vendió el otro ese día.
      await vender(proveedor: serraCigarrosId, precio: 300000, costo: 300000, cigarrillo: true, mp: 300000);
      await vender(proveedor: proveedorId, precio: 600000, costo: 400000, efectivo: 600000);
      await vender(proveedor: otroProveedorId, precio: 300000, costo: 200000, efectivo: 300000);

      final r = await resumenReposicionDeProveedor(db, await proveedorActual());
      expect(r.costoRealMpCentavos, 200000);
    });

    test('pagar divide el pago en dos movimientos: uno del cajón y otro por MP', () async {
      await vender(proveedor: proveedorId, precio: 100000, costo: 60000, efectivo: 100000);
      await vender(proveedor: proveedorId, precio: 50000, costo: 30000, mp: 50000);
      await separarProveedor(db, proveedorId: proveedorId);

      await pagarProveedor(
        db,
        proveedorId: proveedorId,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        montoCentavos: 90000,
        montoMpCentavos: 30000,
      );

      final movimientos = await (db.select(db.movimientosDeCaja)..where((m) => m.tipo.equals('PAGO_PROVEEDOR'))).get();
      expect(
        {for (final m in movimientos) m.medioPagoId: m.montoCentavos},
        {null: 60000, medioMpId: 30000},
      );
      final p = await proveedorActual();
      expect(p.separadoCentavos, 0);
      expect(p.separadoMpCentavos, 0);
      expect(p.pendienteBaseCentavos, 0);
    });

    test('sin parte MP, el pago de un proveedor en efectivo deja un solo movimiento', () async {
      await vender(proveedor: proveedorId, precio: 100000, costo: 60000, efectivo: 100000);
      await separarProveedor(db, proveedorId: proveedorId);
      await pagarProveedor(
        db,
        proveedorId: proveedorId,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        montoCentavos: 60000,
        montoMpCentavos: 0,
      );

      final movimientos = await db.select(db.movimientosDeCaja).get();
      expect(movimientos.single.medioPagoId, isNull);
      expect(movimientos.single.montoCentavos, 60000);
    });

    test('un proveedor por transferencia no graba movimientos aunque tenga parte en MP', () async {
      await actualizarProveedorNivel2(db, proveedorId: proveedorId, colchonReposicionCentavos: 0, medioPago: 'Transferencia');
      await vender(proveedor: proveedorId, precio: 50000, costo: 30000, mp: 50000);
      await separarProveedor(db, proveedorId: proveedorId);
      await pagarProveedor(
        db,
        proveedorId: proveedorId,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        montoCentavos: 30000,
        montoMpCentavos: 30000,
      );

      expect(await db.select(db.movimientosDeCaja).get(), isEmpty);
    });
  });

  group('ventas anuladas no cuentan (Dueño, 2026-09-26: "sin ventas anuladas")', () {
    test('ni en lo que hay que separar ni en la ganancia pendiente', () async {
      await crearVenta(fecha: DateTime(2026, 9, 1), proveedorId: proveedorId, precioCentavos: 100000, costoCentavos: 60000);
      await crearVenta(fecha: DateTime(2026, 9, 1), proveedorId: proveedorId, precioCentavos: 50000, costoCentavos: 30000);
      await db.customStatement('UPDATE ventas SET anulada_en = 1 WHERE id = (SELECT MAX(id) FROM ventas)');

      final r = de(await reposicionActual(db), proveedorId);
      expect(r.costoRealCentavos, 60000);
      expect(r.vendidoCentavos, 100000);

      final ganancia = (await gananciaPendienteDeProveedores(db)).firstWhere((g) => g.proveedor.id == proveedorId);
      expect(ganancia.gananciaCentavos, 40000);
    });
  });

  group('Separaciones del día (Dueño, 2026-09-26: "que sea del día" + montos actuales)', () {
    late int medioEfectivoId;
    late int medioMpId;
    late int cajaNormalId;
    late int otroProveedorId;

    setUp(() async {
      medioEfectivoId = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
      medioMpId = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle()).id;
      cajaNormalId = (await (db.select(db.cajas)..where((c) => c.esLata.equals(false))).getSingle()).id;
      otroProveedorId = (await (db.select(db.proveedores)..where((p) => p.codigo.equals('F'))).getSingle()).id;
    });

    /// Venta de una línea con sus pagos y, si hay efectivo, su movimiento de
    /// caja (de ahí sale el efectivo del cajón en vivo).
    Future<void> vender({
      required int proveedor,
      required int precio,
      required int costo,
      int efectivo = 0,
      int mp = 0,
      DateTime? fecha,
      bool cigarrillo = false,
    }) async {
      final ventaId = await db.into(db.ventas).insert(
            VentasCompanion.insert(
              sesionCajaId: sesionId,
              usuarioId: usuarioId,
              fecha: fecha == null ? const Value.absent() : Value(fecha),
              subtotalCentavos: precio,
              totalCentavos: efectivo + mp,
            ),
          );
      await db.into(db.lineasDeVenta).insert(
            LineasDeVentaCompanion.insert(
              ventaId: ventaId,
              nombreProductoFoto: 'Producto',
              proveedorIdFoto: Value(proveedor),
              tipoCigarrillo: Value(cigarrillo ? 'atado' : 'ninguno'),
              precioUnitarioCentavos: precio,
              costoUnitarioCentavos: Value(costo),
            ),
          );
      if (efectivo > 0) {
        await db.into(db.pagos).insert(PagosCompanion.insert(ventaId: ventaId, medioPagoId: medioEfectivoId, montoCentavos: efectivo));
        await db.into(db.movimientosDeCaja).insert(
              MovimientosDeCajaCompanion.insert(
                sesionCajaId: sesionId,
                cajaId: cajaNormalId,
                usuarioId: usuarioId,
                tipo: 'VENTA',
                montoCentavos: efectivo,
                ventaId: Value(ventaId),
              ),
            );
      }
      if (mp > 0) {
        await db.into(db.pagos).insert(PagosCompanion.insert(ventaId: ventaId, medioPagoId: medioMpId, montoCentavos: mp));
      }
    }

    SeparacionDelDia fila(List<SeparacionDelDia> filas, int id) => filas.firstWhere((f) => f.proveedor?.id == id);

    test('vendido = costo + ganancia, y la ganancia dividida entre cajón y MP', () async {
      await vender(proveedor: proveedorId, precio: 100000, costo: 60000, efectivo: 100000);
      await vender(proveedor: proveedorId, precio: 50000, costo: 30000, mp: 50000);

      final f = fila(await separacionesDelDia(db), proveedorId);
      expect(f.vendidoCentavos, 150000);
      expect(f.costoCentavos, 90000);
      expect(f.gananciaCentavos, 60000);
      expect(f.gananciaMpCentavos, 20000);
      expect(f.gananciaEfectivoCentavos, 40000);
      expect(f.faltaSepararCentavos, 90000);
      expect(f.faltaSepararMpCentavos, 30000);
    });

    test('lo vendido sin costo suma a vendido y se informa aparte, sin tocar costo ni ganancia', () async {
      await vender(proveedor: proveedorId, precio: 100000, costo: 60000, efectivo: 100000);
      final ventaId = await db.into(db.ventas).insert(
            VentasCompanion.insert(sesionCajaId: sesionId, usuarioId: usuarioId, subtotalCentavos: 26000, totalCentavos: 26000),
          );
      await db.into(db.lineasDeVenta).insert(
            LineasDeVentaCompanion.insert(
              ventaId: ventaId,
              nombreProductoFoto: 'Coca Lata',
              proveedorIdFoto: Value(proveedorId),
              precioUnitarioCentavos: 26000,
            ),
          );

      final f = fila(await separacionesDelDia(db), proveedorId);
      expect(f.vendidoCentavos, 126000);
      expect(f.vendidoSinCostoCentavos, 26000);
      expect(f.costoCentavos, 60000);
      expect(f.gananciaCentavos, 40000);
    });

    test('lo vendido sin proveedor aparece en una fila propia, al final, sin nada que separar', () async {
      await vender(proveedor: proveedorId, precio: 100000, costo: 60000, efectivo: 100000);
      final ventaId = await db.into(db.ventas).insert(
            VentasCompanion.insert(sesionCajaId: sesionId, usuarioId: usuarioId, subtotalCentavos: 50000, totalCentavos: 50000),
          );
      await db.into(db.lineasDeVenta).insert(
            LineasDeVentaCompanion.insert(
              ventaId: ventaId,
              nombreProductoFoto: 'Suelto',
              precioUnitarioCentavos: 50000,
              costoUnitarioCentavos: const Value(30000),
            ),
          );
      await db.into(db.pagos).insert(PagosCompanion.insert(ventaId: ventaId, medioPagoId: medioMpId, montoCentavos: 50000));

      final filas = await separacionesDelDia(db);
      final sinProveedor = filas.last;
      expect(sinProveedor.proveedor, isNull);
      expect(sinProveedor.nombre, 'Sin proveedor');
      expect(sinProveedor.vendidoCentavos, 50000);
      expect(sinProveedor.costoCentavos, 30000);
      expect(sinProveedor.gananciaMpCentavos, 20000);
      expect(sinProveedor.faltaSepararCentavos, 0);
      expect(ajustarSeparacionesADisponible(filas, null).partes.keys, [proveedorId]);
    });

    test('solo lo de hoy: lo de ayer no aparece', () async {
      final ayer = DateTime.now().subtract(const Duration(days: 1));
      await vender(proveedor: proveedorId, precio: 100000, costo: 60000, efectivo: 100000, fecha: ayer);
      await vender(proveedor: proveedorId, precio: 50000, costo: 30000, efectivo: 50000);

      final f = fila(await separacionesDelDia(db), proveedorId);
      expect(f.vendidoCentavos, 50000);
      expect(f.faltaSepararCentavos, 30000);
    });

    test('separar lo de hoy no se lleva lo de días anteriores ni el colchón: siguen en Avanzado', () async {
      final ayer = DateTime.now().subtract(const Duration(days: 1));
      await vender(proveedor: proveedorId, precio: 100000, costo: 60000, efectivo: 100000, fecha: ayer);
      await vender(proveedor: proveedorId, precio: 50000, costo: 30000, mp: 50000);
      await ponerColchon(proveedorId, 20000);

      await separarDelDia(db, proveedorId: proveedorId, montoMpCentavos: 30000, ahora: DateTime.now().add(const Duration(seconds: 1)));

      final p = await proveedorActual();
      expect(p.separadoCentavos, 30000);
      expect(p.separadoMpCentavos, 30000);
      expect(p.colchonReposicionCentavos, 20000);
      final avanzado = de(await reposicionActual(db), proveedorId);
      expect(avanzado.pendienteSinSepararCentavos, 60000); // lo de ayer, intacto
      expect(fila(await separacionesDelDia(db), proveedorId).faltaSepararCentavos, 0);
    });

    test('la plata de ahora: cajón menos lo que se lleva la lata y lo ya separado; MP menos lo separado', () async {
      await vender(proveedor: proveedorId, precio: 100000, costo: 60000, efectivo: 100000);
      final serraCigarros = (await (db.select(db.proveedores)..where((p) => p.codigo.equals('SC'))).getSingle()).id;
      await vender(proveedor: serraCigarros, precio: 40000, costo: 40000, efectivo: 40000, cigarrillo: true);
      await vender(proveedor: otroProveedorId, precio: 50000, costo: 30000, mp: 50000);
      await separarDelDia(db, proveedorId: otroProveedorId, montoMpCentavos: 30000);

      final d = await disponibleParaSepararAhora(db, sesionId);
      expect(d.efectivoEnCajonCentavos, 140000);
      expect(d.seLlevaLaLataCentavos, 40000);
      expect(d.separadoEfectivoCentavos, 0);
      expect(d.efectivoDisponibleCentavos, 100000);
      expect(d.saldoMpCentavos, 50000);
      expect(d.mpDisponibleCentavos, 20000);
    });

    test('si el efectivo no alcanza, lo que falta se separa de MP', () async {
      // Costo $600 cobrado en efectivo, pero del cajón salió un gasto de
      // $900 y la lata se lleva $400 al cierre: el cajón tiene $1.000 +
      // $400 − $900 = $500, y descontada la lata quedan $100. En MP hay
      // $1.000 de saldo inicial.
      await (db.update(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId)))
          .write(const SesionesDeCajaCompanion(saldoMpInicialCentavos: Value(100000)));
      await vender(proveedor: proveedorId, precio: 100000, costo: 60000, efectivo: 100000);
      final serraCigarros = (await (db.select(db.proveedores)..where((p) => p.codigo.equals('SC'))).getSingle()).id;
      await vender(proveedor: serraCigarros, precio: 40000, costo: 40000, efectivo: 40000, cigarrillo: true);
      await db.into(db.movimientosDeCaja).insert(
            MovimientosDeCajaCompanion.insert(
              sesionCajaId: sesionId,
              cajaId: cajaNormalId,
              usuarioId: usuarioId,
              tipo: 'GASTO',
              montoCentavos: 90000,
            ),
          );

      final filas = await separacionesDelDia(db);
      final disponible = await disponibleParaSepararAhora(db, sesionId);
      expect(disponible.efectivoDisponibleCentavos, 10000);
      expect(disponible.mpDisponibleCentavos, 100000);

      final ajuste = ajustarSeparacionesADisponible(filas, disponible);
      expect(ajuste.partes[proveedorId]!.efectivoCentavos, 10000);
      expect(ajuste.partes[proveedorId]!.mpCentavos, 50000);
      expect(ajuste.corridoAMpCentavos, 50000);
      expect(ajuste.faltanteCentavos, 0);
    });
  });

  group('Tildar y destildar en Separaciones (mock de Dueño, 2026-09-26)', () {
    late int medioEfectivoId;
    late int medioMpId;

    setUp(() async {
      medioEfectivoId = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle()).id;
      medioMpId = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle()).id;
    });

    Future<void> vender({required int precio, required int costo, int efectivo = 0, int mp = 0, DateTime? fecha, bool cigarrillo = false}) async {
      final ventaId = await db.into(db.ventas).insert(
            VentasCompanion.insert(
              sesionCajaId: sesionId,
              usuarioId: usuarioId,
              fecha: fecha == null ? const Value.absent() : Value(fecha),
              subtotalCentavos: precio,
              totalCentavos: efectivo + mp,
            ),
          );
      await db.into(db.lineasDeVenta).insert(
            LineasDeVentaCompanion.insert(
              ventaId: ventaId,
              nombreProductoFoto: 'Producto',
              proveedorIdFoto: Value(proveedorId),
              tipoCigarrillo: Value(cigarrillo ? 'atado' : 'ninguno'),
              precioUnitarioCentavos: precio,
              costoUnitarioCentavos: Value(costo),
            ),
          );
      if (efectivo > 0) {
        await db.into(db.pagos).insert(PagosCompanion.insert(ventaId: ventaId, medioPagoId: medioEfectivoId, montoCentavos: efectivo));
      }
      if (mp > 0) {
        await db.into(db.pagos).insert(PagosCompanion.insert(ventaId: ventaId, medioPagoId: medioMpId, montoCentavos: mp));
      }
    }

    SeparacionDelDia fila(List<SeparacionDelDia> filas) => filas.firstWhere((f) => f.proveedor?.id == proveedorId);

    test('tildar deja la tarjeta separada; destildar vuelve todo a como estaba', () async {
      final ayer = DateTime.now().subtract(const Duration(days: 1));
      await vender(precio: 100000, costo: 60000, efectivo: 100000, fecha: ayer);
      await vender(precio: 50000, costo: 30000, mp: 50000);
      final antes = await proveedorActual();

      await separarDelDia(db, proveedorId: proveedorId, montoMpCentavos: 30000, ahora: DateTime.now().add(const Duration(seconds: 1)));
      final f = fila(await separacionesDelDia(db));
      expect(f.separadaHoy, isTrue);
      expect(f.separadoHoyCentavos, 30000);
      expect(f.separadoHoyMpCentavos, 30000);
      expect(f.puedeDesmarcar, isTrue);

      await desmarcarDelDia(db, proveedorId: proveedorId);
      final despues = await proveedorActual();
      expect(despues.separadoCentavos, antes.separadoCentavos);
      expect(despues.separadoMpCentavos, antes.separadoMpCentavos);
      expect(despues.corteReposicionFecha, antes.corteReposicionFecha);
      expect(despues.pendienteBaseCentavos, antes.pendienteBaseCentavos);
      expect(fila(await separacionesDelDia(db)).faltaSepararCentavos, 30000);
      expect(de(await reposicionActual(db), proveedorId).pendienteSinSepararCentavos, 90000);
    });

    test('dos separaciones el mismo día se suman, y destildar vuelve al estado de la mañana', () async {
      await vender(precio: 50000, costo: 30000, efectivo: 50000);
      await separarDelDia(db, proveedorId: proveedorId, montoMpCentavos: 0, ahora: DateTime.now().add(const Duration(seconds: 1)));
      await vender(precio: 20000, costo: 12000, efectivo: 20000, fecha: DateTime.now().add(const Duration(seconds: 2)));

      final entreMedio = fila(await separacionesDelDia(db, ahora: DateTime.now().add(const Duration(seconds: 3))));
      expect(entreMedio.separadaHoy, isFalse); // se vendió más después de tildar
      expect(entreMedio.faltaSepararCentavos, 12000);

      await separarDelDia(db, proveedorId: proveedorId, montoMpCentavos: 0, ahora: DateTime.now().add(const Duration(seconds: 4)));
      expect((await proveedorActual()).separadoDelDiaCentavos, 42000);

      await desmarcarDelDia(db, proveedorId: proveedorId);
      final p = await proveedorActual();
      expect(p.separadoCentavos, 0);
      expect(p.corteReposicionFecha, isNull);
    });

    test('una tarjeta ya pagada no se puede destildar', () async {
      await vender(precio: 50000, costo: 30000, efectivo: 50000);
      await separarDelDia(db, proveedorId: proveedorId, montoMpCentavos: 0);
      await pagarProveedor(db, proveedorId: proveedorId, sesionCajaId: sesionId, usuarioId: usuarioId, montoCentavos: 30000, montoMpCentavos: 0);

      expect(fila(await separacionesDelDia(db)).puedeDesmarcar, isFalse);
      await desmarcarDelDia(db, proveedorId: proveedorId);
      expect((await proveedorActual()).corteReposicionFecha, isNotNull); // no se deshizo nada
    });

    test('cobrado del día por caja, y lo que se lleva la lata (cigarrillos de hoy, sin importar el medio)', () async {
      await vender(precio: 100000, costo: 60000, efectivo: 100000);
      await vender(precio: 40000, costo: 40000, mp: 40000, cigarrillo: true);
      await vender(precio: 70000, costo: 40000, efectivo: 70000, fecha: DateTime.now().subtract(const Duration(days: 1)));

      final c = await cobradoDelDia(db);
      expect(c.efectivoCentavos, 100000);
      expect(c.mpCentavos, 40000);
      expect(c.cigarrillosCentavos, 40000);
    });

    test('con Semana, lo vendido suma la semana pero lo que falta separar sigue siendo de hoy', () async {
      final ahora = DateTime(2026, 9, 26, 15);
      await vender(precio: 100000, costo: 60000, efectivo: 100000, fecha: DateTime(2026, 9, 22, 12)); // martes
      await vender(precio: 50000, costo: 30000, efectivo: 50000, fecha: DateTime(2026, 9, 26, 11));

      final semana = fila(await separacionesDelDia(db, ahora: ahora, desde: DateTime(2026, 9, 21)));
      expect(semana.vendidoCentavos, 150000);
      expect(semana.faltaSepararCentavos, 30000);
    });
  });

  group('vendidoSinCostoDesde — qué producto no tiene costo (Dueño, 2026-09-26)', () {
    Future<int> linea({required String nombre, int? proveedor, int? costo, int cantidad = 1, DateTime? fecha, String tipo = 'ninguno'}) async {
      final ventaId = await db.into(db.ventas).insert(
            VentasCompanion.insert(
              sesionCajaId: sesionId,
              usuarioId: usuarioId,
              fecha: fecha == null ? const Value.absent() : Value(fecha),
              subtotalCentavos: 26000 * cantidad,
              totalCentavos: 26000 * cantidad,
            ),
          );
      await db.into(db.lineasDeVenta).insert(
            LineasDeVentaCompanion.insert(
              ventaId: ventaId,
              nombreProductoFoto: nombre,
              proveedorIdFoto: Value(proveedor),
              tipoCigarrillo: Value(tipo),
              cantidad: Value(cantidad),
              precioUnitarioCentavos: 26000,
              costoUnitarioCentavos: Value(costo),
            ),
          );
      return ventaId;
    }

    test('agrupa por producto y proveedor; deja afuera lo que tiene costo, cigarrillos, anuladas y otros días', () async {
      final hoy = DateTime.now();
      final inicio = DateTime(hoy.year, hoy.month, hoy.day);
      await linea(nombre: 'Coca Lata', proveedor: proveedorId, cantidad: 2);
      await linea(nombre: 'Coca Lata', proveedor: proveedorId);
      await linea(nombre: 'Caramelo');
      await linea(nombre: 'Coca 2.25', proveedor: proveedorId, costo: 399400);
      await linea(nombre: 'Atado', tipo: 'atado');
      await linea(nombre: 'Ayer', fecha: inicio.subtract(const Duration(hours: 3)));
      final anulada = await linea(nombre: 'Anulada');
      await (db.update(db.ventas)..where((v) => v.id.equals(anulada))).write(VentasCompanion(anuladaEn: Value(DateTime.now())));

      final r = await vendidoSinCostoDesde(db, inicio);
      expect(r.map((v) => v.producto), ['Coca Lata', 'Caramelo']);
      expect(r.first.cantidad, 3);
      expect(r.first.vendidoCentavos, 78000);
      expect(r.first.proveedor, 'Distribuidora');
      expect(r.last.proveedor, isNull);
    });
  });
}

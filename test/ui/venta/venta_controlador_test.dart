import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/data/cobro_posnet.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ticket.dart'
    show configurarMpAccessToken, configurarMpTerminalCobroId;
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/cobro_posnet.dart' show ResultadoOrdenCobro;
import 'package:la_plazoleta/domain/descuento.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/venta.dart';
import 'package:la_plazoleta/ui/venta/venta_controlador.dart';
import '../../helpers/base_para_tests.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late VentaControlador c;
  late int usuarioId;
  late Producto cocaCola;
  late Producto marlboroAtado;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db
        .into(db.usuarios)
        .insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

    final idCoca = await db
        .into(db.productos)
        .insert(
          ProductosCompanion.insert(
            nombre: 'Coca-Cola 500ml',
            codigoBarras: const Value('7790001'),
            precioCentavos: const Value(112000),
            costoCentavos: const Value(80000),
            stock: const Value(20),
          ),
        );
    final idMarlboro = await db
        .into(db.productos)
        .insert(
          ProductosCompanion.insert(
            nombre: 'Marlboro',
            precioCentavos: const Value(500000),
            tipoCigarrillo: const Value('atado'),
          ),
        );
    cocaCola = await (db.select(
      db.productos,
    )..where((p) => p.id.equals(idCoca))).getSingle();
    marlboroAtado = await (db.select(
      db.productos,
    )..where((p) => p.id.equals(idMarlboro))).getSingle();

    c = VentaControlador(db);
    await c.cargarTodo();
  });

  tearDown(() {
    c.dispose();
    db.close();
  });

  group('búsqueda del campo único', () {
    test('escribir un texto actualiza las coincidencias', () {
      c.campoTexto.text = 'coca';
      expect(c.coincidencias, hasLength(1));
      expect(c.sinCoincidencias, false);
    });

    test('sin coincidencias: se muestra el aviso en vez del dropdown', () {
      c.campoTexto.text = 'producto que no existe';
      expect(c.coincidencias, isEmpty);
      expect(c.sinCoincidencias, true);
    });

    test('campo vacío: ni coincidencias ni aviso', () {
      c.campoTexto.text = '';
      expect(c.sinCoincidencias, false);
    });
  });

  group('agregar al carrito', () {
    test('agregarProducto suma cantidad 1 por defecto', () {
      c.agregarProducto(cocaCola);
      expect(c.carrito, hasLength(1));
      expect((c.carrito.single as LineaVentaPorUnidad).cantidad, 1);
    });

    test(
      'escanear el mismo producto de nuevo suma cantidad en la misma línea',
      () {
        c.agregarProducto(cocaCola);
        c.agregarProducto(cocaCola);
        expect(c.carrito, hasLength(1));
        expect((c.carrito.single as LineaVentaPorUnidad).cantidad, 2);
      },
    );

    test('"200 queso" agrega gramos, no cantidad de unidades', () async {
      final idQueso = await db
          .into(db.productos)
          .insert(
            ProductosCompanion.insert(
              nombre: 'Queso barra',
              esPesable: const Value(true),
              precioPorKiloCentavos: const Value(300000),
            ),
          );
      await c.cargarTodo();
      final queso = await (db.select(
        db.productos,
      )..where((p) => p.id.equals(idQueso))).getSingle();

      c.campoTexto.text = '200 queso';
      c.agregarProducto(queso);

      final linea = c.carrito.single as LineaVentaPesable;
      expect(linea.gramos, 200);
    });

    test('agregar limpia el campo y las coincidencias', () {
      c.campoTexto.text = 'coca';
      c.agregarProducto(cocaCola);
      expect(c.campoTexto.text, '');
      expect(c.coincidencias, isEmpty);
    });

    test(
      '"Varios" siempre agrega una línea nueva, nunca suma con otra',
      () async {
        final varios = await (db.select(
          db.productos,
        )..where((p) => p.esVarios.equals(true))).getSingle();
        c.agregarProducto(varios, montoVariosCentavos: 30000);
        c.agregarProducto(varios, montoVariosCentavos: 50000);
        expect(c.carrito, hasLength(2));
      },
    );

    // Bug real, ítem 4: un pesable sin gramos válidos o sin precio por
    // kilo cargado crasheaba (`!` sobre un valor null) en vez de avisar
    // (Regla 7: es un error, no un cero silencioso).
    group('pesables incompletos: avisa, no crashea (Regla 7)', () {
      late Producto quesoSinPrecio;
      late Producto quesoConPrecio;

      setUp(() async {
        final idSinPrecio = await db
            .into(db.productos)
            .insert(
              ProductosCompanion.insert(
                nombre: 'Jamón cocido',
                esPesable: const Value(true),
              ),
            );
        quesoSinPrecio = await (db.select(
          db.productos,
        )..where((p) => p.id.equals(idSinPrecio))).getSingle();

        final idConPrecio = await db
            .into(db.productos)
            .insert(
              ProductosCompanion.insert(
                nombre: 'Queso barra',
                esPesable: const Value(true),
                precioPorKiloCentavos: const Value(300000),
              ),
            );
        quesoConPrecio = await (db.select(
          db.productos,
        )..where((p) => p.id.equals(idConPrecio))).getSingle();
        await c.cargarTodo();
      });

      test('sin escribir gramos: no agrega, avisa, no crashea', () {
        c.campoTexto.text = 'jamon'; // sin el prefijo de gramos
        c.agregarProducto(quesoSinPrecio);

        expect(c.carrito, isEmpty);
        expect(c.avisoBusqueda, contains('gramos'));
      });

      test('con 0 gramos: no agrega, avisa', () {
        c.campoTexto.text = '0 jamon';
        c.agregarProducto(quesoConPrecio);

        expect(c.carrito, isEmpty);
        expect(c.avisoBusqueda, contains('gramos'));
      });

      test(
        'con gramos pero sin precio por kilo cargado: no agrega, avisa (Regla 7)',
        () {
          c.campoTexto.text = '200 jamon';
          c.agregarProducto(quesoSinPrecio);

          expect(c.carrito, isEmpty);
          expect(c.avisoBusqueda, contains('precio por kilo'));
        },
      );

      test(
        'con gramos y precio: se agrega normalmente y el aviso se limpia',
        () {
          c.campoTexto.text = '200 queso';
          c.agregarProducto(quesoConPrecio);

          expect(c.carrito, hasLength(1));
          expect(c.avisoBusqueda, isNull);
        },
      );

      test('volver a escribir limpia un aviso anterior', () {
        c.campoTexto.text = 'jamon';
        c.agregarProducto(quesoSinPrecio);
        expect(c.avisoBusqueda, isNotNull);

        c.campoTexto.text = 'jamon2';
        expect(c.avisoBusqueda, isNull);
      });
    });
  });

  group(
    'eliminarLinea (Dueño, 2026-09-06: tacho por fila, reemplaza a Backspace) y Escape',
    () {
      test(
        'eliminarLinea saca la línea en esa posición, no necesariamente la última',
        () {
          c.agregarProducto(cocaCola);
          c.agregarProducto(marlboroAtado);
          c.eliminarLinea(0); // saca la Coca-Cola, no el último atado
          expect(c.carrito, hasLength(1));
          expect(c.carrito.single.nombreProducto, 'Marlboro');
        },
      );

      test('restaurarLinea devuelve la línea quitada a su posición original', () {
        c.agregarProducto(cocaCola);
        c.agregarProducto(marlboroAtado);
        final quitada = c.carrito[0];
        c.eliminarLinea(0);
        c.restaurarLinea(0, quitada);
        expect(c.carrito.map((l) => l.nombreProducto), ['Coca-Cola 500ml', 'Marlboro']);
        expect(c.indiceUltimaLinea, 0);
      });

      test('eliminarLinea con un índice fuera de rango no rompe nada', () {
        c.agregarProducto(cocaCola);
        c.eliminarLinea(5);
        expect(c.carrito, hasLength(1));
        c.eliminarLinea(-1);
        expect(c.carrito, hasLength(1));
      });

      test('eliminarLinea con el carrito vacío no rompe nada', () {
        c.eliminarLinea(0);
        expect(c.carrito, isEmpty);
      });

      test('eliminar justo la línea resaltada apaga el resaltado', () {
        c.agregarProducto(cocaCola);
        c.agregarProducto(marlboroAtado);
        expect(c.indiceUltimaLinea, 1);
        c.eliminarLinea(1);
        expect(c.indiceUltimaLinea, isNull);
      });

      test(
        'eliminar una línea ANTES de la resaltada corrige el índice para seguir apuntando a la misma',
        () {
          c.agregarProducto(cocaCola);
          c.agregarProducto(marlboroAtado);
          expect(c.indiceUltimaLinea, 1);
          c.eliminarLinea(0); // saca la Coca-Cola, antes del Marlboro resaltado
          expect(c.indiceUltimaLinea, 0);
          expect(c.carrito[c.indiceUltimaLinea!].nombreProducto, 'Marlboro');
        },
      );

      test('cancelarVenta vacía el carrito y el medio elegido', () {
        c.agregarProducto(cocaCola);
        c.elegirMedio(ComposicionPago.efectivo);
        c.cancelarVenta();
        expect(c.carrito, isEmpty);
        expect(c.medioElegido, isNull);
      });
    },
  );

  group(
    'ajustarCantidad y editarCantidadExacta/editarGramosExacto (Dueño, 2026-09-06)',
    () {
      test('ajustarCantidad(+1) suma una unidad más', () {
        c.agregarProducto(cocaCola);
        c.ajustarCantidad(0, 1);
        expect((c.carrito.single as LineaVentaPorUnidad).cantidad, 2);
      });

      test('ajustarCantidad(-1) resta una unidad', () {
        c.agregarProducto(cocaCola);
        c.agregarProducto(cocaCola);
        c.ajustarCantidad(0, -1);
        expect((c.carrito.single as LineaVentaPorUnidad).cantidad, 1);
      });

      test('ajustarCantidad(-1) en 1 saca la línea entera', () {
        c.agregarProducto(cocaCola);
        c.ajustarCantidad(0, -1);
        expect(c.carrito, isEmpty);
      });

      test('ajustarCantidad no hace nada sobre una línea pesable', () async {
        final idQueso = await db
            .into(db.productos)
            .insert(
              ProductosCompanion.insert(
                nombre: 'Queso barra',
                esPesable: const Value(true),
                precioPorKiloCentavos: const Value(300000),
              ),
            );
        await c.cargarTodo();
        final queso = await (db.select(
          db.productos,
        )..where((p) => p.id.equals(idQueso))).getSingle();
        c.campoTexto.text = '200 queso';
        c.agregarProducto(queso);

        c.ajustarCantidad(0, 1);

        expect((c.carrito.single as LineaVentaPesable).gramos, 200);
      });

      test('ajustarCantidad con índice fuera de rango no rompe nada', () {
        c.agregarProducto(cocaCola);
        c.ajustarCantidad(5, 1);
        expect((c.carrito.single as LineaVentaPorUnidad).cantidad, 1);
      });

      test('editarCantidadExacta tipea un salto grande de una vez', () {
        c.agregarProducto(cocaCola);
        c.editarCantidadExacta(0, 12);
        expect((c.carrito.single as LineaVentaPorUnidad).cantidad, 12);
      });

      test('editarCantidadExacta con 0 o menos saca la línea', () {
        c.agregarProducto(cocaCola);
        c.editarCantidadExacta(0, 0);
        expect(c.carrito, isEmpty);
      });

      test('editarGramosExacto tipea el peso exacto de un pesable', () async {
        final idQueso = await db
            .into(db.productos)
            .insert(
              ProductosCompanion.insert(
                nombre: 'Queso barra',
                esPesable: const Value(true),
                precioPorKiloCentavos: const Value(300000),
              ),
            );
        await c.cargarTodo();
        final queso = await (db.select(
          db.productos,
        )..where((p) => p.id.equals(idQueso))).getSingle();
        c.campoTexto.text = '200 queso';
        c.agregarProducto(queso);

        c.editarGramosExacto(0, 350);

        expect((c.carrito.single as LineaVentaPesable).gramos, 350);
      });

      test('editarGramosExacto con 0 o menos saca la línea', () async {
        final idQueso = await db
            .into(db.productos)
            .insert(
              ProductosCompanion.insert(
                nombre: 'Queso barra',
                esPesable: const Value(true),
                precioPorKiloCentavos: const Value(300000),
              ),
            );
        await c.cargarTodo();
        final queso = await (db.select(
          db.productos,
        )..where((p) => p.id.equals(idQueso))).getSingle();
        c.campoTexto.text = '200 queso';
        c.agregarProducto(queso);

        c.editarGramosExacto(0, -5);

        expect(c.carrito, isEmpty);
      });

      test('editarGramosExacto no hace nada sobre una línea por unidad', () {
        c.agregarProducto(cocaCola);
        c.editarGramosExacto(0, 500);
        expect((c.carrito.single as LineaVentaPorUnidad).cantidad, 1);
      });
    },
  );

  group(
    'el recargo de cigarrillos se recalcula al cambiar el medio (punto crítico #2)',
    () {
      test('cigarrillos cargados con QR elegido: el recargo aparece', () {
        c.agregarProducto(marlboroAtado);
        c.elegirMedio(ComposicionPago.virtual);
        expect(c.resultado!.recargoCigarrillosCentavos, greaterThan(0));
      });

      test(
        'el mismo carrito, cambiando a efectivo: el recargo desaparece del total',
        () {
          c.agregarProducto(marlboroAtado);
          c.elegirMedio(ComposicionPago.virtual);
          final totalConRecargo = c.resultado!.totalCentavos;

          c.elegirMedio(ComposicionPago.efectivo);

          expect(c.resultado!.recargoCigarrillosCentavos, 0);
          expect(c.resultado!.totalCentavos, lessThan(totalConRecargo));
        },
      );

      test(
        'ida y vuelta varias veces: siempre refleja el medio actual, nunca queda pegado',
        () {
          c.agregarProducto(marlboroAtado);

          c.elegirMedio(ComposicionPago.efectivo);
          expect(c.resultado!.recargoCigarrillosCentavos, 0);

          c.elegirMedio(ComposicionPago.virtual);
          expect(c.resultado!.recargoCigarrillosCentavos, greaterThan(0));

          c.elegirMedio(ComposicionPago.mixto);
          expect(c.resultado!.recargoCigarrillosCentavos, greaterThan(0));

          c.elegirMedio(ComposicionPago.efectivo);
          expect(c.resultado!.recargoCigarrillosCentavos, 0);
        },
      );

      test('sin medio elegido todavía: no hay resultado, solo subtotal', () {
        c.agregarProducto(cocaCola);
        expect(c.resultado, isNull);
        expect(c.subtotalCentavos, 112000);
      });
    },
  );

  group('cobrar', () {
    test('no cobra si no se eligió medio de pago', () async {
      c.agregarProducto(cocaCola);
      final id = await c.cobrar(usuarioId: usuarioId, pagos: const []);
      expect(id, isNull);
    });

    test('no cobra un carrito vacío', () async {
      c.elegirMedio(ComposicionPago.efectivo);
      final id = await c.cobrar(usuarioId: usuarioId, pagos: const []);
      expect(id, isNull);
    });

    test(
      'cobrar registra la venta y deja el carrito listo para la próxima',
      () async {
        c.agregarProducto(cocaCola);
        c.elegirMedio(ComposicionPago.efectivo);
        final total = c.resultado!.totalCentavos;

        final medioEfectivo = await (db.select(
          db.mediosDePago,
        )..where((m) => m.esEfectivo.equals(true))).getSingle();

        final id = await c.cobrar(
          usuarioId: usuarioId,
          pagos: [
            PagoARegistrar(
              medioPagoId: medioEfectivo.id,
              montoCentavos: total,
              esEfectivo: true,
            ),
          ],
        );

        expect(id, isNotNull);
        expect(c.carrito, isEmpty);
        expect(c.medioElegido, isNull);

        final filaVenta = await (db.select(
          db.ventas,
        )..where((v) => v.id.equals(id!))).getSingle();
        expect(filaVenta.totalCentavos, total);
      },
    );

    // Bug real: sin la guarda `cobrando`, dos llamados a `cobrar()`
    // disparados antes de que el primero termine (doble clic/doble Enter en
    // "Cobrar") registraban la venta dos veces y descontaban el stock dos
    // veces — el botón no se deshabilitaba hasta que `cancelarVenta()`
    // vaciaba el carrito al final del primer `cobrar()`.
    test(
      'dos llamados a cobrar() en simultáneo solo registran una venta',
      () async {
        c.agregarProducto(cocaCola);
        c.elegirMedio(ComposicionPago.efectivo);
        final total = c.resultado!.totalCentavos;

        final medioEfectivo = await (db.select(
          db.mediosDePago,
        )..where((m) => m.esEfectivo.equals(true))).getSingle();

        final pagos = [
          PagoARegistrar(
            medioPagoId: medioEfectivo.id,
            montoCentavos: total,
            esEfectivo: true,
          ),
        ];

        final futuroA = c.cobrar(usuarioId: usuarioId, pagos: pagos);
        // Todavía no se le dio chance a `futuroA` de terminar (no hay
        // `await` de por medio): esto es justo la ventana del doble clic.
        final futuroB = c.cobrar(usuarioId: usuarioId, pagos: pagos);

        final idA = await futuroA;
        final idB = await futuroB;

        expect(idA, isNotNull);
        expect(idB, isNull);
        expect(c.cobrando, isFalse);

        final cantidadVentas = await (db.selectOnly(db.ventas)
              ..addColumns([db.ventas.id.count()]))
            .map((row) => row.read(db.ventas.id.count()))
            .getSingle();
        expect(cantidadVentas, 1);
      },
    );
  });

  group('mixto', () {
    test('sin confirmar el monto en efectivo, construirPagos da null', () {
      c.agregarProducto(cocaCola);
      c.elegirMedio(ComposicionPago.mixto);
      expect(c.construirPagos(), isNull);
    });

    test('confirmarMixto arma los dos pagos que suman el total', () {
      c.agregarProducto(cocaCola);
      c.confirmarMixto(50000);
      final pagos = c.construirPagos()!;
      expect(pagos, hasLength(2));
      final suma = pagos.fold<int>(0, (acc, p) => acc + p.montoCentavos);
      expect(suma, c.resultado!.totalCentavos);
      expect(pagos.first.esEfectivo, true);
      expect(pagos.first.montoCentavos, 50000);
    });

    test(
      'cambiar de mixto a otro medio olvida el monto en efectivo cargado',
      () {
        c.agregarProducto(cocaCola);
        c.confirmarMixto(50000);
        c.elegirMedio(ComposicionPago.efectivo);
        expect(c.montoEfectivoMixtoCentavos, isNull);
      },
    );

    // Bug real, ítem 4: el diálogo de Mixto dejaba terminar en un pago que
    // ya no era mixto (el cliente cambia de opinión) pero seguía
    // calculando como si lo fuera — redondeaba una venta 100% virtual, o
    // cobraba el recargo de cigarrillos en una 100% efectivo.
    group('la composición real se deriva del monto, no del botón (ítem 4)', () {
      test('confirmarMixto(0) es virtual puro: sin redondeo (Regla 2)', () {
        c.agregarProducto(
          cocaCola,
        ); // $1.120, redondea si se trata como mixto/efectivo
        c.confirmarMixto(0);

        expect(c.medioElegido, ComposicionPago.virtual);
        expect(c.montoEfectivoMixtoCentavos, isNull);
        expect(c.resultado!.redondeoCentavos, 0);
        expect(c.resultado!.totalCentavos, 112000); // sin redondear

        final pagos = c.construirPagos()!;
        expect(pagos, hasLength(1));
        expect(pagos.single.esEfectivo, false);
      });

      test(
        'confirmarMixto(total) es efectivo puro: sin recargo de cigarrillos (Regla 6)',
        () {
          c.agregarProducto(marlboroAtado);
          c.elegirMedio(ComposicionPago.mixto);
          final totalMixto = c.resultado!.totalCentavos;

          c.confirmarMixto(totalMixto);

          expect(c.medioElegido, ComposicionPago.efectivo);
          expect(c.montoEfectivoMixtoCentavos, isNull);
          expect(c.resultado!.recargoCigarrillosCentavos, 0);
          expect(
            c.resultado!.totalCentavos,
            lessThan(totalMixto),
          ); // el recargo se cae

          final pagos = c.construirPagos()!;
          expect(pagos, hasLength(1));
          expect(pagos.single.esEfectivo, true);
          expect(pagos.single.montoCentavos, c.resultado!.totalCentavos);
        },
      );

      test(
        'un monto genuinamente entre 0 y el total sigue siendo mixto de verdad',
        () {
          c.agregarProducto(marlboroAtado);
          c.elegirMedio(ComposicionPago.mixto);
          final totalMixto = c.resultado!.totalCentavos;

          c.confirmarMixto(totalMixto ~/ 2);

          expect(c.medioElegido, ComposicionPago.mixto);
          expect(c.montoEfectivoMixtoCentavos, totalMixto ~/ 2);
          expect(c.resultado!.recargoCigarrillosCentavos, greaterThan(0));
        },
      );
    });
  });

  group(
    'cobrarActual — el camino real de Enter-con-campo-vacío y el botón Cobrar',
    () {
      test('efectivo puro: arma el pago solo y cobra', () async {
        c.agregarProducto(cocaCola);
        c.elegirMedio(ComposicionPago.efectivo);
        final id = await c.cobrarActual();
        expect(id, isNotNull);
      });

      test('mixto sin confirmar: no cobra', () async {
        c.agregarProducto(cocaCola);
        c.elegirMedio(ComposicionPago.mixto);
        final id = await c.cobrarActual();
        expect(id, isNull);
      });

      test('mixto confirmado: cobra con los dos pagos', () async {
        c.agregarProducto(cocaCola);
        c.confirmarMixto(50000);
        final id = await c.cobrarActual();
        expect(id, isNotNull);

        final pagos = await (db.select(
          db.pagos,
        )..where((p) => p.ventaId.equals(id!))).get();
        expect(pagos, hasLength(2));
      });

      // Bug real, ítem 4: Enter con el campo vacío y sin medio elegido no
      // daba ninguna señal — indistinguible de que la app se colgó.
      group('avisoCobro: Enter sin medio elegido no queda en silencio', () {
        test('carrito con algo y sin medio elegido: avisa', () async {
          c.agregarProducto(cocaCola);
          final id = await c.cobrarActual();

          expect(id, isNull);
          expect(c.avisoCobro, contains('Elegí un medio de pago'));
        });

        test('carrito vacío: no avisa (no había nada para cobrar)', () async {
          final id = await c.cobrarActual();

          expect(id, isNull);
          expect(c.avisoCobro, isNull);
        });

        test('elegir un medio después limpia el aviso', () async {
          c.agregarProducto(cocaCola);
          await c.cobrarActual();
          expect(c.avisoCobro, isNotNull);

          c.elegirMedio(ComposicionPago.efectivo);
          expect(c.avisoCobro, isNull);
        });

        test('cobrar con éxito deja el aviso limpio', () async {
          c.agregarProducto(cocaCola);
          await c.cobrarActual(); // sin medio: deja el aviso prendido
          c.elegirMedio(ComposicionPago.efectivo);

          final id = await c.cobrarActual();

          expect(id, isNotNull);
          expect(c.avisoCobro, isNull);
        });
      });
    },
  );

  group('cobro por terminal Point (Fase 12)', () {
    test('elegirCanalDirecto elige virtual con un canal concreto', () {
      c.elegirCanalDirecto('qr');
      expect(c.medioElegido, ComposicionPago.virtual);
      expect(c.canalElegido, 'qr');
    });

    test('construirPagos lleva el canal en el pago virtual', () {
      c.agregarProducto(cocaCola);
      c.elegirCanalDirecto('debit_card');

      final pagos = c.construirPagos()!;

      expect(pagos, hasLength(1));
      expect(pagos.single.canal, 'debit_card');
      expect(pagos.single.esEfectivo, false);
    });

    test('montoParaPosnet es el total entero para QR/Débito directo', () {
      c.agregarProducto(cocaCola);
      c.elegirCanalDirecto('qr');

      expect(c.montoParaPosnet, c.resultado!.totalCentavos);
    });

    test(
      'montoParaPosnet en un mixto es el resto después del efectivo confirmado',
      () {
        c.agregarProducto(cocaCola);
        c.elegirMedio(ComposicionPago.mixto);
        c.confirmarMixto(50000, canalResto: 'debit_card');

        expect(c.montoParaPosnet, c.resultado!.totalCentavos - 50000);
        expect(c.canalElegido, 'debit_card');
      },
    );

    test(
      'confirmarMixto: si el cliente termina pagando todo en efectivo, no queda canal',
      () {
        c.agregarProducto(cocaCola);
        c.elegirMedio(ComposicionPago.mixto);
        c.confirmarMixto(c.resultado!.totalCentavos, canalResto: 'qr');

        expect(c.medioElegido, ComposicionPago.efectivo);
        expect(c.canalElegido, isNull);
      },
    );

    test(
      'iniciarCobroPosnet tira CobroPosnetException si falta configurar la terminal de cobro',
      () async {
        c.agregarProducto(cocaCola);
        c.elegirCanalDirecto('qr');

        await expectLater(
          c.iniciarCobroPosnet(),
          throwsA(isA<CobroPosnetException>()),
        );
      },
    );

    test(
      'iniciarCobroPosnet siembra la orden pendiente y guarda el id que responde la API',
      () async {
        await configurarMpAccessToken(db, 'TOKEN123');
        await configurarMpTerminalCobroId(db, 'N950NCC503383252');
        final client = MockClient((request) async {
          return http.Response(
            jsonEncode({'id': 'orden-mp-1', 'status': 'created'}),
            201,
          );
        });
        final controlador = VentaControlador(db, httpClientDePrueba: client);
        await controlador.cargarTodo();
        controlador.agregarProducto(cocaCola);
        controlador.elegirCanalDirecto('qr');

        final resultado = await controlador.iniciarCobroPosnet();

        expect(resultado.ordenIdMp, 'orden-mp-1');
        final fila = await (db.select(
          db.ordenesCobroPendientes,
        )..where((o) => o.id.equals(resultado.ordenPendienteId))).getSingle();
        expect(fila.canal, 'qr');
        expect(fila.montoCentavos, cocaCola.precioCentavos);
        expect(fila.ordenIdMp, 'orden-mp-1');
        expect(fila.estado, 'pendiente'); // el id no cambia el estado propio

        controlador.dispose();
      },
    );

    test('consultarEstadoPosnet clasifica el status de la API', () async {
      await configurarMpAccessToken(db, 'TOKEN123');
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'id': 'orden-mp-1', 'status': 'processed'}),
          200,
        );
      });
      final controlador = VentaControlador(db, httpClientDePrueba: client);
      await controlador.cargarTodo();

      final resultado = await controlador.consultarEstadoPosnet('orden-mp-1');

      expect(resultado, ResultadoOrdenCobro.aprobada);
      controlador.dispose();
    });

    test(
      'confirmarCobroPosnetAprobado graba la venta con el canal y cierra la orden pendiente',
      () async {
        await configurarMpAccessToken(db, 'TOKEN123');
        await configurarMpTerminalCobroId(db, 'N950NCC503383252');
        final client = MockClient((request) async {
          return http.Response(
            jsonEncode({'id': 'orden-mp-1', 'status': 'created'}),
            201,
          );
        });
        final controlador = VentaControlador(db, httpClientDePrueba: client);
        await controlador.cargarTodo();
        controlador.agregarProducto(cocaCola);
        controlador.elegirCanalDirecto('qr');
        final orden = await controlador.iniciarCobroPosnet();

        final ventaId = await controlador.confirmarCobroPosnetAprobado(
          orden.ordenPendienteId,
        );

        expect(ventaId, isNotNull);
        final pago = await (db.select(
          db.pagos,
        )..where((p) => p.ventaId.equals(ventaId!))).getSingle();
        expect(pago.canal, 'qr');
        final ordenFila = await (db.select(
          db.ordenesCobroPendientes,
        )..where((o) => o.id.equals(orden.ordenPendienteId))).getSingle();
        expect(ordenFila.estado, 'aprobada');
        expect(ordenFila.ventaId, ventaId);

        controlador.dispose();
      },
    );

    test(
      'resolverCobroPosnetNoAprobado cierra la orden sin tocar el carrito ni el medio elegido',
      () async {
        await configurarMpAccessToken(db, 'TOKEN123');
        await configurarMpTerminalCobroId(db, 'N950NCC503383252');
        final client = MockClient((request) async {
          return http.Response(
            jsonEncode({'id': 'orden-mp-1', 'status': 'created'}),
            201,
          );
        });
        final controlador = VentaControlador(db, httpClientDePrueba: client);
        await controlador.cargarTodo();
        controlador.agregarProducto(cocaCola);
        controlador.elegirCanalDirecto('qr');
        final orden = await controlador.iniciarCobroPosnet();

        await controlador.resolverCobroPosnetNoAprobado(
          orden.ordenPendienteId,
          estado: 'rechazada',
        );

        final ordenFila = await (db.select(
          db.ordenesCobroPendientes,
        )..where((o) => o.id.equals(orden.ordenPendienteId))).getSingle();
        expect(ordenFila.estado, 'rechazada');
        expect(ordenFila.ventaId, isNull);
        // El carrito y el medio siguen intactos: se puede reintentar o degradar a mano.
        expect(controlador.carrito, hasLength(1));
        expect(controlador.medioElegido, ComposicionPago.virtual);
        expect(controlador.canalElegido, 'qr');

        controlador.dispose();
      },
    );

    test(
      'cancelarCobroPosnet avisa a Mercado Pago y marca la orden cancelada',
      () async {
        await configurarMpAccessToken(db, 'TOKEN123');
        await configurarMpTerminalCobroId(db, 'N950NCC503383252');
        http.Request? pedidoDeCancelacion;
        final client = MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path.endsWith('/cancel')) {
            pedidoDeCancelacion = request;
            return http.Response('{}', 200);
          }
          return http.Response(
            jsonEncode({'id': 'orden-mp-1', 'status': 'created'}),
            201,
          );
        });
        final controlador = VentaControlador(db, httpClientDePrueba: client);
        await controlador.cargarTodo();
        controlador.agregarProducto(cocaCola);
        controlador.elegirCanalDirecto('qr');
        final orden = await controlador.iniciarCobroPosnet();

        await controlador.cancelarCobroPosnet(
          orden.ordenPendienteId,
          ordenIdMp: orden.ordenIdMp,
        );

        expect(pedidoDeCancelacion, isNotNull);
        expect(pedidoDeCancelacion!.url.path, '/v1/orders/orden-mp-1/cancel');
        final ordenFila = await (db.select(
          db.ordenesCobroPendientes,
        )..where((o) => o.id.equals(orden.ordenPendienteId))).getSingle();
        expect(ordenFila.estado, 'cancelada');

        controlador.dispose();
      },
    );

    test(
      'cancelarCobroPosnet: si la API no confirma, la orden queda pendiente (nunca se asume cancelada)',
      () async {
        await configurarMpAccessToken(db, 'TOKEN123');
        await configurarMpTerminalCobroId(db, 'N950NCC503383252');
        final client = MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path.endsWith('/cancel')) {
            return http.Response(
              jsonEncode({'message': 'ya no se puede cancelar'}),
              404,
            );
          }
          return http.Response(
            jsonEncode({'id': 'orden-mp-1', 'status': 'created'}),
            201,
          );
        });
        final controlador = VentaControlador(db, httpClientDePrueba: client);
        await controlador.cargarTodo();
        controlador.agregarProducto(cocaCola);
        controlador.elegirCanalDirecto('qr');
        final orden = await controlador.iniciarCobroPosnet();

        await expectLater(
          controlador.cancelarCobroPosnet(
            orden.ordenPendienteId,
            ordenIdMp: orden.ordenIdMp,
          ),
          throwsA(isA<CobroPosnetException>()),
        );

        final ordenFila = await (db.select(
          db.ordenesCobroPendientes,
        )..where((o) => o.id.equals(orden.ordenPendienteId))).getSingle();
        expect(ordenFila.estado, 'pendiente');

        controlador.dispose();
      },
    );
  });

  group('descuento sobre el total (Regla 17 generalizada)', () {
    test('sin tipear nada, el total sale igual que siempre', () {
      c.agregarProducto(cocaCola);
      c.elegirMedio(ComposicionPago.virtual);
      expect(c.resultado!.descuentoCentavos, 0);
      expect(c.resultado!.totalCentavos, cocaCola.precioCentavos);
    });

    test('monto fijo: se resta del total', () {
      c.agregarProducto(cocaCola);
      c.elegirMedio(ComposicionPago.virtual);
      c.elegirTipoDescuento(TipoDescuento.monto);
      c.campoDescuentoCtrl.text = '500';

      expect(c.resultado!.descuentoCentavos, 50000);
      expect(c.resultado!.totalCentavos, cocaCola.precioCentavos! - 50000);
    });

    test('porcentaje: default es monto, hay que elegirlo explícito', () {
      c.agregarProducto(cocaCola);
      c.elegirMedio(ComposicionPago.virtual);
      c.elegirTipoDescuento(TipoDescuento.porcentaje);
      c.campoDescuentoCtrl.text = '15';

      final esperado = (cocaCola.precioCentavos! * 1500) ~/ 10000;
      expect(c.resultado!.descuentoCentavos, esperado);
    });

    test('construirPagos ya cobra el total con el descuento aplicado', () {
      c.agregarProducto(cocaCola);
      c.elegirMedio(ComposicionPago.efectivo);
      c.elegirTipoDescuento(TipoDescuento.monto);
      c.campoDescuentoCtrl.text = '200';

      final pagos = c.construirPagos()!;
      expect(pagos.single.montoCentavos, c.resultado!.totalCentavos);
      expect(pagos.single.montoCentavos, lessThan(cocaCola.precioCentavos!));
    });

    test(
      'cancelarVenta limpia el descuento — no se arrastra a la próxima venta',
      () {
        c.agregarProducto(cocaCola);
        c.elegirMedio(ComposicionPago.virtual);
        c.elegirTipoDescuento(TipoDescuento.porcentaje);
        c.campoDescuentoCtrl.text = '15';

        c.cancelarVenta();

        expect(c.campoDescuentoCtrl.text, '');
        expect(c.tipoDescuento, TipoDescuento.monto);
      },
    );

    test(
      'cobrar con éxito también limpia el descuento para la próxima venta',
      () async {
        c.agregarProducto(cocaCola);
        c.elegirMedio(ComposicionPago.efectivo);
        c.elegirTipoDescuento(TipoDescuento.monto);
        c.campoDescuentoCtrl.text = '100';

        await c.cobrarActual();

        expect(c.campoDescuentoCtrl.text, '');
        expect(c.tipoDescuento, TipoDescuento.monto);
      },
    );

    test(
      'un texto inválido en el campo no rompe nada: se toma como sin descuento',
      () {
        c.agregarProducto(cocaCola);
        c.elegirMedio(ComposicionPago.virtual);
        c.elegirTipoDescuento(TipoDescuento.monto);
        c.campoDescuentoCtrl.text = 'abc';

        expect(c.resultado!.descuentoCentavos, 0);
        expect(c.resultado!.totalCentavos, cocaCola.precioCentavos);
      },
    );
  });
}

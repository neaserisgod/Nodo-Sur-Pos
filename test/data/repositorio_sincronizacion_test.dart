// Motor de sincronización (fase 2 del rediseño "companion sin depender del
// escritorio") — dos bases en memoria, una haciendo de PC y otra de celular,
// para probar `cambiosDesde`/`aplicarCambios` de punta a punta sin necesitar
// red ni un servidor real. `NativeDatabase.memory()` siempre pasa por
// `onCreate` (esquema en la versión más nueva, con el seed fijo de siempre:
// usuario "Bruno", los 15 proveedores, las 11 categorías reales — Regla 14),
// así que las aserciones de acá filtran por `global_id` no nulo en vez de
// contar filas a secas: el seed ya deja categorías puestas antes de que
// arranque cualquier sincronización.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/identidad_sync.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/data/repositorio_sincronizacion.dart';

void main() {
  // Simular dos dispositivos a propósito abre dos `AppDatabase` a la vez —
  // drift avisa de eso por si es un bug (una sola base por proceso, normal
  // en la app real); acá es justo lo que se quiere probar.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase pc;
  late AppDatabase celular;
  late int usuarioId;

  setUp(() async {
    pc = AppDatabase(NativeDatabase.memory());
    celular = AppDatabase(NativeDatabase.memory());
    establecerIdDispositivo('desktop');
    usuarioId = (await pc.select(pc.usuarios).get()).first.id;
  });

  tearDown(() async {
    await pc.close();
    await celular.close();
    establecerIdDispositivo('desktop');
  });

  test('cambiosDesde solo trae filas con global_id, respetando el cursor', () async {
    final id1 = await crearCategoria(pc, 'Fiambres importados');
    final id2 = await crearCategoria(pc, 'Bebidas sin alcohol');
    // `actualizado_en` es en segundos — dos altas dentro del mismo test
    // pueden caer en el mismo segundo real, así que se fuerza un cursor
    // distinto a mano en vez de confiar en el reloj de la máquina que corre
    // el test.
    await pc.customStatement('UPDATE categorias SET actualizado_en = 1000 WHERE id = $id1');
    await pc.customStatement('UPDATE categorias SET actualizado_en = 2000 WHERE id = $id2');

    final todo = await cambiosDesde(pc, tabla: 'categorias', desde: 0);
    expect(todo.length, 2); // las 11 categorías del seed no tienen global_id

    // `desde` es inclusivo a propósito (ver el comentario de `cambiosDesde`
    // sobre por qué `>=` y no `>`) — pedir desde el cursor exacto de la
    // segunda fila trae esa fila, no la excluye.
    final soloLaSegunda = await cambiosDesde(pc, tabla: 'categorias', desde: 2000);
    expect(soloLaSegunda.length, 1);
    expect(soloLaSegunda.single['nombre'], 'Bebidas sin alcohol');
  });

  test('dos filas con el mismo actualizado_en (mismo segundo real): ninguna se pierde entre pulls', () async {
    final id1 = await crearCategoria(pc, 'Fiambres importados');
    final id2 = await crearCategoria(pc, 'Bebidas sin alcohol');
    // Mismo segundo a propósito — el caso real que rompía con `>` estricto.
    await pc.customStatement('UPDATE categorias SET actualizado_en = 1000 WHERE id IN ($id1, $id2)');

    final primerPull = await cambiosDesde(pc, tabla: 'categorias', desde: 0);
    expect(primerPull.length, 2);
    final cursor = cursorMaximo('categorias', primerPull);
    expect(cursor, 1000);

    // El próximo pull "desde el cursor recién visto" no puede perderse
    // ninguna de las dos filas que comparten ese mismo cursor.
    final siguientePull = await cambiosDesde(pc, tabla: 'categorias', desde: cursor);
    expect(siguientePull.length, 2);
  });

  test('aplicarCambios inserta una fila nueva en la otra base, con id local propio', () async {
    await crearCategoria(pc, 'Fiambres importados');
    final filas = await cambiosDesde(pc, tabla: 'categorias', desde: 0);

    await aplicarCambios(celular, tabla: 'categorias', filas: filas);

    final sincronizadas =
        await (celular.select(celular.categorias)..where((c) => c.globalId.isNotNull())).get();
    expect(sincronizadas.length, 1);
    expect(sincronizadas.single.nombre, 'Fiambres importados');
    expect(sincronizadas.single.globalId, filas.single['global_id']);
    // El id numérico es autoincrement local (con el seed ya ocupando 1..11
    // de un lado y del otro) — no tiene por qué coincidir con el de la PC;
    // lo que importa es que insertó sin pedir el id de origen.
  });

  test('aplicarCambios no duplica: aplicar las mismas filas dos veces deja una sola fila', () async {
    await crearCategoria(pc, 'Fiambres importados');
    final filas = await cambiosDesde(pc, tabla: 'categorias', desde: 0);

    await aplicarCambios(celular, tabla: 'categorias', filas: filas);
    await aplicarCambios(celular, tabla: 'categorias', filas: filas);

    final sincronizadas =
        await (celular.select(celular.categorias)..where((c) => c.globalId.isNotNull())).get();
    expect(sincronizadas.length, 1);
  });

  test(
    'aplicarCambios: una fila con una referencia que no existe todavía no bloquea al resto del lote',
    () async {
      // Simula el bug real (Bruno, 2026-09-18: "no veo productos... ni
      // suelto, ni leche") — un producto cuya categoría todavía no llegó a
      // esta base (`PRAGMA foreign_keys = ON`) no se puede insertar, pero
      // antes de este fix eso tiraba TODA la tanda: cualquier producto que
      // viniera después en la misma lista tampoco se aplicaba, aunque no
      // tuviera nada que ver con la categoría faltante.
      final filaConReferenciaFaltante = {
        'global_id': 'falta-categoria',
        'nombre': 'Producto sin categoría local',
        'categoria_id': 999999, // no existe en `celular`
        'actualizado_en': 1000,
        'origen_dispositivo': 'desktop',
      };
      final filaValida = {
        'global_id': 'sin-problemas',
        'nombre': 'Producto normal',
        'actualizado_en': 1000,
        'origen_dispositivo': 'desktop',
      };

      final noAplicadas = await aplicarCambios(
        celular,
        tabla: 'productos',
        filas: [filaConReferenciaFaltante, filaValida],
      );

      expect(noAplicadas.length, 1);
      expect(noAplicadas.single['global_id'], 'falta-categoria');

      final productos =
          await (celular.select(celular.productos)..where((p) => p.globalId.isNotNull())).get();
      expect(productos.length, 1);
      expect(productos.single.nombre, 'Producto normal');
    },
  );

  test('conflicto: gana el cambio con actualizado_en más reciente', () async {
    final id = await crearCategoria(pc, 'Fiambres importados');
    var filas = await cambiosDesde(pc, tabla: 'categorias', desde: 0);
    await aplicarCambios(celular, tabla: 'categorias', filas: filas);
    final globalId = filas.single['global_id'];

    // El celular "edita" su copia primero (más vieja).
    await celular.customStatement(
      "UPDATE categorias SET nombre = 'Fiambres (celular)', actualizado_en = 1000 WHERE global_id = '$globalId'",
    );
    // La PC edita después (más nueva).
    await pc.customStatement(
      "UPDATE categorias SET nombre = 'Fiambres (PC)', actualizado_en = 2000 WHERE id = $id",
    );

    filas = await cambiosDesde(pc, tabla: 'categorias', desde: 0);
    await aplicarCambios(celular, tabla: 'categorias', filas: filas);

    final categoria = await (celular.select(
      celular.categorias,
    )..where((c) => c.globalId.equals(globalId as String))).getSingle();
    expect(categoria.nombre, 'Fiambres (PC)');
  });

  test('conflicto: una entrante más vieja que la local se descarta', () async {
    final id = await crearCategoria(pc, 'Fiambres importados');
    // Cursor fijo y chico a propósito — si se dejara el `DateTime.now()` real
    // de `crearCategoria`, sería un número mucho más grande que el 5000 que
    // el celular usa abajo para "su" edición más nueva, y el conflicto
    // dejaría de ser realmente "una entrante más vieja".
    await pc.customStatement('UPDATE categorias SET actualizado_en = 1000 WHERE id = $id');
    final filas = await cambiosDesde(pc, tabla: 'categorias', desde: 0);
    await aplicarCambios(celular, tabla: 'categorias', filas: filas);
    final globalId = filas.single['global_id'];

    // La copia del celular ya es "más nueva" que la de la PC.
    await celular.customStatement(
      "UPDATE categorias SET nombre = 'Fiambres (celular, más nuevo)', actualizado_en = 5000 WHERE global_id = '$globalId'",
    );

    // Reaplicar la foto vieja de la PC (actualizado_en menor) no debería
    // pisar lo que ya hizo el celular.
    await aplicarCambios(celular, tabla: 'categorias', filas: filas);

    final categoria = await (celular.select(
      celular.categorias,
    )..where((c) => c.globalId.equals(globalId as String))).getSingle();
    expect(categoria.nombre, 'Fiambres (celular, más nuevo)');
  });

  test('log inmutable (movimientos_de_stock): una fila ya vista nunca se pisa', () async {
    final productoId = await crearProducto(
      pc,
      nombre: 'Coca-Cola 500ml',
      precioCentavos: 100000,
      stock: 10,
      usuarioId: usuarioId,
    );
    final producto = await (pc.select(pc.productos)..where((p) => p.id.equals(productoId))).getSingle();
    await registrarAjusteDeStock(
      pc,
      productoId: productoId,
      usuarioId: usuarioId,
      anterior: producto,
      stock: 8,
      motivo: 'Conteo físico',
    );

    final filas = await cambiosDesde(pc, tabla: 'movimientos_de_stock', desde: 0);
    expect(filas.length, 1);

    // Para que el movimiento de la PC pueda insertarse en el celular sin
    // violar la clave foránea a `productos`, el producto tiene que existir
    // primero del lado del celular — mismo orden de dependencias que
    // documenta `tablasSincronizables`.
    await aplicarCambios(
      celular,
      tabla: 'productos',
      filas: await cambiosDesde(pc, tabla: 'productos', desde: 0),
    );

    await aplicarCambios(celular, tabla: 'movimientos_de_stock', filas: filas);
    // Reaplicar la misma foto (ej. un segundo pull que vuelve a traer esta
    // fila porque el cursor no avanzó todavía del otro lado) no debería
    // duplicar el movimiento.
    await aplicarCambios(celular, tabla: 'movimientos_de_stock', filas: filas);

    final movimientos = await celular.select(celular.movimientosDeStock).get();
    expect(movimientos.length, 1);
    expect(movimientos.single.stockPosterior, 8);

    // El movimiento sincronizado no es solo un dato de auditoría — mueve el
    // stock de verdad del lado del celular (fase 4: "qué pasa si el celular
    // vendió offline algo que en la PC quedó sin stock mientras tanto").
    final productoEnCelular =
        await (celular.select(celular.productos)..where((p) => p.id.equals(productoId))).getSingle();
    expect(productoEnCelular.stock, 8);
  });

  test(
    'dos dispositivos venden el mismo producto en paralelo: al sincronizar, las dos ventas se reflejan (ninguna se pisa)',
    () async {
      // Arranca con el mismo producto sincronizado a los dos lados —
      // "los dos vieron 10 unidades antes de separarse".
      final productoId = await crearProducto(
        pc,
        nombre: 'Coca-Cola 500ml',
        precioCentavos: 100000,
        stock: 10,
        usuarioId: usuarioId,
      );
      await aplicarCambios(
        celular,
        tabla: 'productos',
        filas: await cambiosDesde(pc, tabla: 'productos', desde: 0),
      );
      final usuarioIdCelular = (await celular.select(celular.usuarios).get()).first.id;

      // Cada uno vende offline, sin verse: la PC descuenta 3, el celular
      // descuenta 2 — sobre SU PROPIA copia, cada una arrancando en 10.
      // `ajustarStockRapido` (no `registrarAjusteDeStock` solo, que apenas dos
      // apunta el rastro): actualiza `productos.stock` Y deja el movimiento,
      // igual que hace de verdad una venta o un conteo.
      await ajustarStockRapido(pc, productoId: productoId, usuarioId: usuarioId, stock: 7);
      await ajustarStockRapido(
        celular,
        productoId: productoId,
        usuarioId: usuarioIdCelular,
        stock: 8,
      );

      // Sincroniza en las dos direcciones — mismo orden que
      // `ServicioSincronizacion` (push antes que pull, pero acá alcanza con
      // aplicar cada lado sin importar el orden: sumar deltas es conmutativo).
      await aplicarCambios(
        pc,
        tabla: 'movimientos_de_stock',
        filas: await cambiosDesde(celular, tabla: 'movimientos_de_stock', desde: 0),
      );
      await aplicarCambios(
        celular,
        tabla: 'movimientos_de_stock',
        filas: await cambiosDesde(pc, tabla: 'movimientos_de_stock', desde: 0),
      );

      // Las dos ventas (10−3 de la PC, 10−2 del celular) tienen que verse
      // reflejadas en las dos bases: 10 − 3 − 2 = 5. Si se hubiera
      // sincronizado `stock` como una columna cualquiera (gana el último),
      // una de las dos ventas habría desaparecido del conteo.
      final productoFinalPc =
          await (pc.select(pc.productos)..where((p) => p.id.equals(productoId))).getSingle();
      final productoFinalCelular =
          await (celular.select(celular.productos)..where((p) => p.id.equals(productoId))).getSingle();
      expect(productoFinalPc.stock, 5);
      expect(productoFinalCelular.stock, 5);
    },
  );

  test(
    'sincronizar un producto por OTRO motivo (ej. cambio de nombre) no pisa el stock local',
    () async {
      final productoId = await crearProducto(
        pc,
        nombre: 'Coca-Cola 500ml',
        precioCentavos: 100000,
        stock: 10,
        usuarioId: usuarioId,
      );
      await aplicarCambios(
        celular,
        tabla: 'productos',
        filas: await cambiosDesde(pc, tabla: 'productos', desde: 0),
      );

      // El celular vende offline (stock local baja a 8) sin que la PC se
      // entere todavía.
      await ajustarStockRapido(
        celular,
        productoId: productoId,
        usuarioId: (await celular.select(celular.usuarios).get()).first.id,
        stock: 8,
      );

      // Mientras tanto, en la PC alguien le cambia el nombre al producto —
      // una edición real, que sí tiene que ganar por `actualizado_en`, pero
      // SIN arrastrar el stock viejo (10) de la PC por encima del 8 que ya
      // tiene el celular.
      await pc.customStatement(
        "UPDATE productos SET nombre = 'Coca-Cola 500ml (promo)', actualizado_en = 999999999999 WHERE id = $productoId",
      );

      await aplicarCambios(
        celular,
        tabla: 'productos',
        filas: await cambiosDesde(pc, tabla: 'productos', desde: 0),
      );

      final productoFinal =
          await (celular.select(celular.productos)..where((p) => p.id.equals(productoId))).getSingle();
      expect(productoFinal.nombre, 'Coca-Cola 500ml (promo)'); // el cambio real sí se aplicó
      expect(productoFinal.stock, 8); // pero el stock local no se pisó con el 10 de la PC
    },
  );

  test(
    'ventas traduce sesion_caja_id por global_id: no asume que el id local coincide entre dispositivos',
    () async {
      // Bug real (Bruno, 2026-09-18, encontrado en vivo con la companion
      // recién instalada): la PC ya tenía 25 sesiones de caja acumuladas en
      // meses de uso; el celular, recién instalado, solo recibió unas
      // pocas por sync — le tocó un id local bien distinto para la MISMA
      // sesión. Una venta que copiara el `sesion_caja_id` crudo de la PC
      // (25) nunca iba a encontrar nada en el celular.
      for (var i = 0; i < 24; i++) {
        await pc.into(pc.sesionesDeCaja).insert(
          SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0),
        );
      }
      final sesionIdPc = await pc.into(pc.sesionesDeCaja).insert(
        SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0),
      );
      expect(sesionIdPc, 25); // confirma la premisa del bug real
      await pc.customStatement(
        "UPDATE sesiones_de_caja SET global_id = 'sesion-25', actualizado_en = 1000 WHERE id = $sesionIdPc",
      );

      // El celular sincroniza esa sesión sola — le toca un id local propio,
      // que NO tiene por qué ser 25 (acá, con la base vacía, es 1).
      await aplicarCambios(
        celular,
        tabla: 'sesiones_de_caja',
        filas: await cambiosDesde(pc, tabla: 'sesiones_de_caja', desde: 0),
      );
      final sesionEnCelular = await (celular.select(
        celular.sesionesDeCaja,
      )..where((s) => s.globalId.equals('sesion-25'))).getSingle();
      expect(sesionEnCelular.id, isNot(25));

      // Una venta de la PC referencia sesion_caja_id=25 (su propio id local).
      final ventaIdPc = await pc.into(pc.ventas).insert(
        VentasCompanion.insert(
          sesionCajaId: sesionIdPc,
          usuarioId: usuarioId,
          subtotalCentavos: 100000,
          totalCentavos: 100000,
        ),
      );
      await pc.customStatement(
        "UPDATE ventas SET global_id = 'venta-1', actualizado_en = 2000 WHERE id = $ventaIdPc",
      );

      final noAplicadas = await aplicarCambios(
        celular,
        tabla: 'ventas',
        filas: await cambiosDesde(pc, tabla: 'ventas', desde: 0),
      );
      expect(noAplicadas, isEmpty);

      final ventaEnCelular = await (celular.select(
        celular.ventas,
      )..where((v) => v.globalId.equals('venta-1'))).getSingle();
      // Traducido al id local del celular — nunca el 25 crudo de la PC.
      expect(ventaEnCelular.sesionCajaId, sesionEnCelular.id);
    },
  );

  test(
    'ventas con una sesion_caja_id_gid que todavía no llegó al celular no se aplica (se reintenta después)',
    () async {
      final sesionIdPc = await pc.into(pc.sesionesDeCaja).insert(
        SesionesDeCajaCompanion.insert(usuarioAbrioId: usuarioId, fondoInicialCentavos: 0),
      );
      await pc.customStatement(
        "UPDATE sesiones_de_caja SET global_id = 'sesion-1', actualizado_en = 1000 WHERE id = $sesionIdPc",
      );
      final ventaIdPc = await pc.into(pc.ventas).insert(
        VentasCompanion.insert(
          sesionCajaId: sesionIdPc,
          usuarioId: usuarioId,
          subtotalCentavos: 100000,
          totalCentavos: 100000,
        ),
      );
      await pc.customStatement(
        "UPDATE ventas SET global_id = 'venta-1', actualizado_en = 2000 WHERE id = $ventaIdPc",
      );

      // La venta llega ANTES que su sesión (fuera de orden) — el celular
      // todavía no tiene ninguna fila con global_id = 'sesion-1'.
      final noAplicadas = await aplicarCambios(
        celular,
        tabla: 'ventas',
        filas: await cambiosDesde(pc, tabla: 'ventas', desde: 0),
      );
      expect(noAplicadas.length, 1);
      final ventas = await (celular.select(celular.ventas)..where((v) => v.globalId.isNotNull())).get();
      expect(ventas, isEmpty);
    },
  );

  test(
    'configuracion_negocio_tabla.producto_vuelto_id se traduce por global_id, no por el id crudo de la PC',
    () async {
      final productoIdPc = await crearProducto(
        pc,
        nombre: 'Caramelo',
        precioCentavos: 50000,
        stock: 10,
        usuarioId: usuarioId,
      );
      await pc.customStatement(
        "UPDATE productos SET global_id = 'producto-vuelto-1' WHERE id = $productoIdPc",
      );
      // Un producto de relleno primero, para que el id local del celular NO
      // coincida por casualidad con el de la PC (las dos bases arrancan
      // vacías de productos, con el mismo autoincrement) — si el test no
      // fuerza esto, "traducido por global_id" podría estar pasando solo
      // porque los dos ids crudos ya coincidían.
      await crearProducto(celular, nombre: 'Relleno', precioCentavos: 1000, stock: 0, usuarioId: usuarioId);
      final productoIdCelular = await crearProducto(
        celular,
        nombre: 'Caramelo',
        precioCentavos: 50000,
        stock: 10,
        usuarioId: usuarioId,
      );
      await celular.customStatement(
        "UPDATE productos SET global_id = 'producto-vuelto-1' WHERE id = $productoIdCelular",
      );
      expect(productoIdPc, isNot(productoIdCelular));

      await pc.customStatement(
        "UPDATE configuracion_negocio_tabla SET producto_vuelto_id = $productoIdPc, "
        "global_id = 'config-negocio-1', actualizado_en = 1000 WHERE id = 1",
      );

      final noAplicadas = await aplicarCambios(
        celular,
        tabla: 'configuracion_negocio_tabla',
        filas: await cambiosDesde(pc, tabla: 'configuracion_negocio_tabla', desde: 0),
      );
      expect(noAplicadas, isEmpty);

      final filaEnCelular = await (celular.select(
        celular.configuracionNegocioTabla,
      )..where((c) => c.globalId.equals('config-negocio-1'))).getSingle();
      // Traducido al id local del celular — nunca el id crudo de la PC.
      expect(filaEnCelular.productoVueltoId, productoIdCelular);
    },
  );

  test('cursorMaximo usa id (no actualizado_en) para las tablas de solo-log', () async {
    final productoId = await crearProducto(
      pc,
      nombre: 'Coca-Cola 500ml',
      precioCentavos: 100000,
      stock: 10,
      usuarioId: usuarioId,
    );
    final producto = await (pc.select(pc.productos)..where((p) => p.id.equals(productoId))).getSingle();
    await registrarAjusteDeStock(
      pc,
      productoId: productoId,
      usuarioId: usuarioId,
      anterior: producto,
      stock: 8,
    );

    final filas = await cambiosDesde(pc, tabla: 'movimientos_de_stock', desde: 0);
    final cursor = cursorMaximo('movimientos_de_stock', filas);
    expect(cursor, filas.single['id']);
  });

  group('filtrarYaSubidas — no re-subir el borde en cada tick (cuota de Supabase, 2026-09-26)', () {
    /// Un tick de push como el de `sincronizacion_supabase.dart`, sin red:
    /// devuelve lo que se habría subido y guarda cursor/borde para el próximo.
    Future<List<Map<String, dynamic>>> Function() pusher(AppDatabase db, String tabla) {
      var cursor = 0;
      var borde = <String, String>{};
      return () async {
        final filas = await cambiosDesde(db, tabla: tabla, desde: cursor);
        final plan = filtrarYaSubidas(tabla, filas: filas, cursor: cursor, borde: borde);
        if (plan.aSubir.isNotEmpty) {
          cursor = plan.cursor;
          borde = plan.borde;
        }
        return plan.aSubir;
      };
    }

    test('una tabla entera en actualizado_en = 0 (proveedores) se sube una vez, no en cada tick', () async {
      // Como quedaron en la base real tras v30→v31: global_id, época 0.
      await pc.customStatement(
        'UPDATE proveedores SET global_id = lower(hex(randomblob(16))), actualizado_en = 0',
      );
      final total = (await cambiosDesde(pc, tabla: 'proveedores', desde: 0)).length;
      expect(total, greaterThan(1));
      final tick = pusher(pc, 'proveedores');

      expect((await tick()).length, total);
      expect(await tick(), isEmpty);
      expect(await tick(), isEmpty);
    });

    test('en un log (cursor por id) la última fila no se vuelve a subir', () async {
      final productoId = await pc.into(pc.productos).insert(ProductosCompanion.insert(nombre: 'Chicle'));
      final tick = pusher(pc, 'movimientos_de_stock');
      Future<void> movimiento() => pc.customStatement(
            "INSERT INTO movimientos_de_stock (producto_id, usuario_id, tipo, cantidad, stock_anterior, stock_posterior, "
            "global_id, origen_dispositivo, fecha) VALUES ($productoId, $usuarioId, 'AJUSTE', 1, 0, 1, "
            "lower(hex(randomblob(16))), 'desktop', 0)",
          );

      await movimiento();
      expect((await tick()).length, 1);
      expect(await tick(), isEmpty);

      await movimiento();
      expect((await tick()).length, 1, reason: 'solo el nuevo, no el anterior de vuelta');
    });

    test('una fila del borde editada de nuevo en el mismo segundo sí se vuelve a subir', () async {
      final id = await crearCategoria(pc, 'Fiambres importados');
      await pc.customStatement('UPDATE categorias SET actualizado_en = 5000 WHERE id = $id');
      final tick = pusher(pc, 'categorias');
      expect((await tick()).length, 1);
      expect(await tick(), isEmpty);

      await pc.customStatement("UPDATE categorias SET nombre = 'Fiambres', actualizado_en = 5000 WHERE id = $id");
      final resubida = await tick();
      expect(resubida.single['nombre'], 'Fiambres');
      expect(await tick(), isEmpty);
    });

    test('otra fila nueva en el mismo segundo que el borde se sube sola, sin arrastrar la ya subida', () async {
      final id1 = await crearCategoria(pc, 'Fiambres importados');
      await pc.customStatement('UPDATE categorias SET actualizado_en = 5000 WHERE id = $id1');
      final tick = pusher(pc, 'categorias');
      await tick();

      final id2 = await crearCategoria(pc, 'Bebidas sin alcohol');
      await pc.customStatement('UPDATE categorias SET actualizado_en = 5000 WHERE id = $id2');
      final segunda = await tick();
      expect(segunda.map((f) => f['nombre']), ['Bebidas sin alcohol']);
      expect(await tick(), isEmpty);
    });
  });
}

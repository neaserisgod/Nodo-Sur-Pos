// Pedidos de un local gastronómico en la base (`REGLAS-NEGOCIO.md` §22): se crean con el estado y la hora que dicen las reglas,
// avanzan solo por los pasos permitidos, y viajan por la sync a otro equipo.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_pedidos_gastronomia.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/data/repositorio_sincronizacion.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/domain/venta.dart';
import 'package:la_plazoleta/domain/bot_whatsapp.dart';
import 'package:la_plazoleta/domain/pedido_gastronomico.dart';

import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  final ahora = DateTime(2026, 10, 16, 20);
  const milanesa = LineaPedido(gid: 'plato-mila', nombre: 'Milanesa con papas', cantidad: 2, precioCentavos: 650000);
  const centro = ZonaEnvio(nombre: 'Centro', costoCentavos: 150000, demoraExtraMin: 15);

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Ana'));
  });
  tearDown(() => db.close());

  Future<PedidoGastronomia> leer(int id) =>
      (db.select(db.pedidosGastronomia)..where((p) => p.id.equals(id))).getSingle();

  test('la configuración de arranque: solo retiro, cocina normal', () async {
    expect((await configPedidosActual(db)).formasDisponibles, [FormaEntrega.retiro]);
    expect(await estadoCocinaActual(db), EstadoCocina.normal);
  });

  test('guardar la configuración y el estado de la cocina', () async {
    await guardarConfigPedidos(db, const ConfigPedidos(cadetePropio: true, zonas: [centro], confirmacionAutomatica: true));
    await cambiarEstadoCocina(db, EstadoCocina.demorada);
    final config = await configPedidosActual(db);
    expect(config.formasDisponibles, [FormaEntrega.retiro, FormaEntrega.cadetePropio]);
    expect(config.confirmacionAutomatica, isTrue);
    expect(await estadoCocinaActual(db), EstadoCocina.demorada);
  });

  test('un pedido de mostrador entra "por hacer", con número y hora', () async {
    final id = await crearPedido(db,
        canal: CanalPedido.mostrador, nombreCliente: 'Juan', lineas: const [milanesa], usuarioId: usuarioId, ahora: ahora);
    final p = await leer(id);
    expect(EstadoPedido.desdeClave(p.estado), EstadoPedido.porHacer);
    expect(p.numero, matches(RegExp(r'^[A-Z]{2}-P0001$')));
    expect(p.horaEstimada, ahora.add(const Duration(minutes: 30)));
    expect(p.globalId, isNotNull);
    final segundo = await crearPedido(db,
        canal: CanalPedido.mostrador, nombreCliente: 'Eva', lineas: const [milanesa], usuarioId: usuarioId, ahora: ahora);
    expect((await leer(segundo)).numero, endsWith('-P0002'));
  });

  test('uno de WhatsApp espera la confirmación del local', () async {
    final id = await crearPedido(db,
        canal: CanalPedido.whatsapp, nombreCliente: 'Caro', telefono: '5492944111111', lineas: const [milanesa], usuarioId: usuarioId);
    expect(EstadoPedido.desdeClave((await leer(id)).estado), EstadoPedido.porConfirmar);
  });

  test('uno de WhatsApp fuera de hora queda programado para cuando abre; el mostrador no se programa', () async {
    // Domingo: con el horario de arranque (lunes a sábado) abre el lunes a las 9.
    final domingo = DateTime(2026, 10, 18, 12);
    final id = await crearPedido(db,
        canal: CanalPedido.whatsapp, nombreCliente: 'Caro', lineas: const [milanesa], usuarioId: usuarioId, ahora: domingo);
    final p = await leer(id);
    expect(p.programado, isTrue);
    expect(p.horaEstimada, DateTime(2026, 10, 19, 9, 30));
    final mostrador = await crearPedido(db,
        canal: CanalPedido.mostrador, nombreCliente: 'Juan', lineas: const [milanesa], usuarioId: usuarioId, ahora: domingo);
    expect((await leer(mostrador)).programado, isFalse);
  });

  test('con la cocina pausada no entra nada de WhatsApp, pero el mostrador sí', () async {
    await cambiarEstadoCocina(db, EstadoCocina.pausada);
    expect(
      () => crearPedido(db, canal: CanalPedido.whatsapp, nombreCliente: 'Caro', lineas: const [milanesa], usuarioId: usuarioId),
      throwsA(isA<CocinaPausada>()),
    );
    final id = await crearPedido(db, canal: CanalPedido.mostrador, nombreCliente: 'Juan', lineas: const [milanesa], usuarioId: usuarioId);
    expect((await leer(id)).horaEstimada, isNull);
  });

  test('un envío pide una forma que el local tenga, dirección y zona, y cobra el envío de la zona', () async {
    expect(
      () => crearPedido(db,
          canal: CanalPedido.mostrador, nombreCliente: 'Juan', formaEntrega: FormaEntrega.cadetePropio, lineas: const [milanesa], usuarioId: usuarioId),
      throwsA(isA<PedidoIncompleto>()),
    );
    await guardarConfigPedidos(db, const ConfigPedidos(cadetePropio: true, zonas: [centro]));
    expect(
      () => crearPedido(db,
          canal: CanalPedido.mostrador, nombreCliente: 'Juan', formaEntrega: FormaEntrega.cadetePropio, lineas: const [milanesa], usuarioId: usuarioId),
      throwsA(isA<PedidoIncompleto>()),
    );
    final id = await crearPedido(db,
        canal: CanalPedido.mostrador,
        nombreCliente: 'Juan',
        formaEntrega: FormaEntrega.cadetePropio,
        direccion: 'Mitre 100',
        zona: centro,
        lineas: const [milanesa],
        usuarioId: usuarioId,
        ahora: ahora);
    final p = await leer(id);
    expect(p.costoEnvioCentavos, 150000);
    expect(p.zona, 'Centro');
    expect(p.horaEstimada, ahora.add(const Duration(minutes: 45)));
  });

  test('un pedido sin nada no se toma', () async {
    expect(
      () => crearPedido(db, canal: CanalPedido.mostrador, nombreCliente: 'Juan', lineas: const [], usuarioId: usuarioId),
      throwsA(isA<PedidoIncompleto>()),
    );
  });

  test('avanza solo por los pasos permitidos', () async {
    final id = await crearPedido(db, canal: CanalPedido.whatsapp, nombreCliente: 'Caro', lineas: const [milanesa], usuarioId: usuarioId);
    await expectLater(avanzarPedido(db, id, EstadoPedido.entregado), throwsA(isA<PasoDePedidoInvalido>()));
    await avanzarPedido(db, id, EstadoPedido.porHacer);
    await avanzarPedido(db, id, EstadoPedido.listo);
    await avanzarPedido(db, id, EstadoPedido.entregado);
    expect(EstadoPedido.desdeClave((await leer(id)).estado), EstadoPedido.entregado);
    await expectLater(avanzarPedido(db, id, EstadoPedido.cancelado), throwsA(isA<PasoDePedidoInvalido>()));
  });

  test('se cancela mientras no salió', () async {
    final id = await crearPedido(db, canal: CanalPedido.mostrador, nombreCliente: 'Juan', lineas: const [milanesa], usuarioId: usuarioId);
    await avanzarPedido(db, id, EstadoPedido.cancelado);
    expect(EstadoPedido.desdeClave((await leer(id)).estado), EstadoPedido.cancelado);
  });

  test('pago adelantado: espera el pago y al llegar sigue', () async {
    final id = await crearPedido(db,
        canal: CanalPedido.whatsapp, nombreCliente: 'Caro', lineas: const [milanesa], pagaAdelantado: true, usuarioId: usuarioId);
    expect(EstadoPedido.desdeClave((await leer(id)).estado), EstadoPedido.esperandoPago);
    await registrarPagoAdelantado(db, id);
    final p = await leer(id);
    expect(p.pagado, isTrue);
    expect(EstadoPedido.desdeClave(p.estado), EstadoPedido.porConfirmar);
  });

  test('la lista de trabajo trae los abiertos, del más viejo al más nuevo', () async {
    final a = await crearPedido(db, canal: CanalPedido.mostrador, nombreCliente: 'A', lineas: const [milanesa], usuarioId: usuarioId);
    final b = await crearPedido(db, canal: CanalPedido.mostrador, nombreCliente: 'B', lineas: const [milanesa], usuarioId: usuarioId);
    await avanzarPedido(db, a, EstadoPedido.cancelado);
    final c = await crearPedido(db, canal: CanalPedido.mostrador, nombreCliente: 'C', lineas: const [milanesa], usuarioId: usuarioId);
    expect([for (final p in await pedidosAbiertos(db)) p.id], [b, c]);
  });

  test('viaja por la sync a otro equipo, con su usuario', () async {
    final id = await crearPedido(db, canal: CanalPedido.mostrador, nombreCliente: 'Juan', lineas: const [milanesa], usuarioId: usuarioId);
    await (db.update(db.usuarios)..where((u) => u.id.equals(usuarioId))).write(const UsuariosCompanion(globalId: Value('u-ana')));
    final otro = AppDatabase(NativeDatabase.memory());
    addTearDown(otro.close);
    await aplicarCambios(otro, tabla: 'usuarios', filas: await cambiosDesde(db, tabla: 'usuarios', desde: 0));
    final pendientes = await aplicarCambios(otro,
        tabla: 'pedidos_gastronomia', filas: await cambiosDesde(db, tabla: 'pedidos_gastronomia', desde: 0));
    expect(pendientes, isEmpty);
    final llegado = await otro.select(otro.pedidosGastronomia).getSingle();
    expect(llegado.numero, (await leer(id)).numero);
    expect(lineasDe(llegado).single.nombre, 'Milanesa con papas');
  });

  group('cobrar un pedido', () {
    late int sesion;
    late int mila;

    setUp(() async {
      sesion = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
      mila = await crearProducto(db, nombre: 'Milanesa con papas', precioCentavos: 700000, costoCentavos: 300000, stock: 10, usuarioId: usuarioId);
    });

    Future<int> pedidoDeMila({FormaEntrega forma = FormaEntrega.retiro, ZonaEnvio? zona}) async {
      final p = await (db.select(db.productos)..where((x) => x.id.equals(mila))).getSingle();
      return crearPedido(db,
          canal: CanalPedido.mostrador,
          nombreCliente: 'Juan',
          formaEntrega: forma,
          direccion: forma.esEnvio ? 'Mitre 100' : null,
          zona: zona,
          // El precio del pedido es el que se le dijo al cliente, aunque hoy el plato valga otra cosa.
          lineas: [LineaPedido(gid: p.globalId!, nombre: p.nombre, cantidad: 2, precioCentavos: 650000)],
          usuarioId: usuarioId);
    }

    test('las líneas de la venta salen del pedido, al precio que se le dijo al cliente y con el costo de hoy', () async {
      final id = await pedidoDeMila();
      final lineas = await lineasDeVentaDePedido(db, await leer(id));
      final l = lineas.single as LineaVentaPorUnidad;
      expect(l.productoId, '$mila');
      expect(l.cantidad, 2);
      expect(l.precioUnitarioCentavos, 650000);
      expect(l.costoUnitarioCentavos, 300000);
    });

    test('el envío entra como una línea suelta (Varios) con el costo de la zona', () async {
      await guardarConfigPedidos(db, const ConfigPedidos(cadetePropio: true, zonas: [centro]));
      final id = await pedidoDeMila(forma: FormaEntrega.cadetePropio, zona: centro);
      final lineas = await lineasDeVentaDePedido(db, await leer(id));
      expect(lineas, hasLength(2));
      final envio = lineas.last as LineaVentaPorUnidad;
      expect(envio.esVarios, isTrue);
      expect(envio.nombreProducto, 'Envío · Centro');
      expect(envio.precioUnitarioCentavos, 150000);
    });

    test('cobrarlo graba la venta y la liga al pedido en la misma transacción; un retiro listo queda entregado', () async {
      final id = await pedidoDeMila();
      await avanzarPedido(db, id, EstadoPedido.listo);
      final r = await registrarVentaSegunMedio(db,
          lineas: await lineasDeVentaDePedido(db, await leer(id)),
          medio: ComposicionPago.efectivo,
          sesionCajaId: sesion,
          usuarioId: usuarioId,
          pedidoId: id);
      final p = await leer(id);
      expect(p.ventaId, r.ventaId);
      expect(EstadoPedido.desdeClave(p.estado), EstadoPedido.entregado);
      expect(r.totalCentavos, 1300000);
    });

    test('un envío cobrado antes de salir sigue en la lista hasta entregarse', () async {
      await guardarConfigPedidos(db, const ConfigPedidos(cadetePropio: true, zonas: [centro]));
      final id = await pedidoDeMila(forma: FormaEntrega.cadetePropio, zona: centro);
      await registrarVentaSegunMedio(db,
          lineas: await lineasDeVentaDePedido(db, await leer(id)),
          medio: ComposicionPago.efectivo,
          sesionCajaId: sesion,
          usuarioId: usuarioId,
          pedidoId: id);
      expect(EstadoPedido.desdeClave((await leer(id)).estado), EstadoPedido.porHacer);
    });

    test('no se cobra dos veces, ni uno cancelado: y si falla no queda venta', () async {
      final id = await pedidoDeMila();
      final lineas = await lineasDeVentaDePedido(db, await leer(id));
      await registrarVentaSegunMedio(db, lineas: lineas, medio: ComposicionPago.efectivo, sesionCajaId: sesion, usuarioId: usuarioId, pedidoId: id);
      final ventasAntes = (await db.select(db.ventas).get()).length;
      await expectLater(
        registrarVentaSegunMedio(db, lineas: lineas, medio: ComposicionPago.efectivo, sesionCajaId: sesion, usuarioId: usuarioId, pedidoId: id),
        throwsA(isA<PedidoYaCobrado>()),
      );
      expect((await db.select(db.ventas).get()).length, ventasAntes);

      final otro = await pedidoDeMila();
      await avanzarPedido(db, otro, EstadoPedido.cancelado);
      await expectLater(
        registrarVentaSegunMedio(db, lineas: lineas, medio: ComposicionPago.efectivo, sesionCajaId: sesion, usuarioId: usuarioId, pedidoId: otro),
        throwsA(isA<PedidoYaCobrado>()),
      );
    });
  });

  group('pedidos del bot pagados por transferencia (El dueño, 2026-10-23: quedaban trabados en "sin pagar")', () {
    Future<PedidoBot> delBot(int id, {String pago = 'alias'}) async {
      final gid = (await db.select(db.productos).get()).firstWhere((p) => p.globalId != null).globalId!;
      return PedidoBot(
        id: id,
        estado: EstadoPedidoBot.porConfirmar,
        clienteNombre: 'Lucas',
        clienteTelefono: '5492944555111',
        items: [ItemPedidoBot(gid: gid, nombre: 'Especial', cantidad: 1, precioCentavos: 1850000)],
        nota: 'Especial: sin cebolla',
        creado: ahora,
        actualizado: 1,
        formaEntrega: 'CADETE',
        direccion: 'Mitre 150',
        zona: 'Bariloche',
        costoEnvioCentavos: 250000,
        pago: pago,
      );
    }

    test('si el local confirma cada pedido, entra "por confirmar" con la nota de la transferencia', () async {
      final id = await importarPedidoDelBot(db, await delBot(1), usuarioId: usuarioId);
      final p = await leer(id);
      expect(EstadoPedido.desdeClave(p.estado), EstadoPedido.porConfirmar);
      expect(p.pagaAdelantado, isTrue);
      expect(p.pagado, isFalse);
      expect(p.nota, startsWith('💸 Paga por transferencia'));
      expect(p.nota, endsWith('Especial: sin cebolla'));
      await avanzarPedido(db, id, EstadoPedido.porHacer);
      expect(EstadoPedido.desdeClave((await leer(id)).estado), EstadoPedido.porHacer);
    });

    test('si entran solos, espera el pago y "Llegó el pago" lo manda a la cocina', () async {
      await guardarConfigPedidos(db, const ConfigPedidos(cadetePropio: true, zonas: [centro], confirmacionAutomatica: true));
      final id = await importarPedidoDelBot(db, await delBot(2), usuarioId: usuarioId);
      expect(EstadoPedido.desdeClave((await leer(id)).estado), EstadoPedido.esperandoPago);
      await registrarPagoAdelantado(db, id);
      final p = await leer(id);
      expect(EstadoPedido.desdeClave(p.estado), EstadoPedido.porHacer);
      expect(p.pagado, isTrue);
    });

    test('pagado por Mercado Pago entra directo a la cocina aunque el local confirme cada pedido', () async {
      final id = await importarPedidoDelBot(db, await delBot(3, pago: 'mp'), usuarioId: usuarioId);
      final p = await leer(id);
      expect(EstadoPedido.desdeClave(p.estado), EstadoPedido.porHacer);
      expect(p.pagado, isTrue);
      expect(p.nota, 'Especial: sin cebolla');
      expect(estadoParaElSitio(p), 'aceptado', reason: 'el bot le avisa al cliente que ya está en marcha');
    });
  });
}


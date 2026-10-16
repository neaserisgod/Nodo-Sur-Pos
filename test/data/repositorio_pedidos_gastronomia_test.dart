// Pedidos de un local gastronómico en la base (`REGLAS-NEGOCIO.md` §22): se crean con el estado y la hora que dicen las reglas,
// avanzan solo por los pasos permitidos, y viajan por la sync a otro equipo.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_pedidos_gastronomia.dart';
import 'package:la_plazoleta/data/repositorio_sincronizacion.dart';
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
}

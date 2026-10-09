// Aceptar o rechazar un pedido del bot de WhatsApp (`companion/pedidos_bot.dart`, plan en `docs/PLAN-BOT.md`), contra una base
// real (el mismo camino que sin PC) y un sitio de mentira.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/cliente_companion.dart' show ProductoCompanion;
import 'package:la_plazoleta/companion/pedidos_bot.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/servicio_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/domain/bot_whatsapp.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart' show ErrorNube;

import '../helpers/base_para_tests.dart';
import '../helpers/sitio_bot_falso.dart';

PedidoBot pedidoDe(String gid, {int cantidad = 2, int id = 7, String nombre = 'Cerveza'}) => PedidoBot(
  id: id,
  estado: EstadoPedidoBot.porConfirmar,
  clienteNombre: 'Sofi',
  clienteTelefono: '5492944555555',
  items: [ItemPedidoBot(gid: gid, nombre: nombre, cantidad: cantidad, precioCentavos: 150000)],
  creado: DateTime(2026, 10, 9, 18, 30),
  actualizado: 1,
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late PuertoLocal puerto;
  late SitioBotFalso sitio;
  late RegistroPedidosBotEnMemoria registro;
  late int cerveza;
  late String gid;

  setUp(() async {
    db = baseDeTest();
    usarBaseLocalDeTest(db);
    puerto = PuertoLocal(baseLocalCompanion());
    final provs = await puerto.proveedores();
    cerveza = await puerto.crearProducto(nombre: 'Cerveza', esPesable: false, stock: 3, proveedorId: provs[0].id, usuarioId: 1);
    gid = (await (db.select(db.productos)..where((p) => p.id.equals(cerveza))).getSingle()).globalId!;
    sitio = SitioBotFalso();
    registro = RegistroPedidosBotEnMemoria();
  });
  tearDown(() => db.close());

  Future<int> stock() async => (await (db.select(db.productos)..where((p) => p.id.equals(cerveza))).getSingle()).stock;
  Future<ResultadoAceptarPedido> aceptar(PedidoBot p) =>
      aceptarPedidoBot(pedido: p, servicio: puerto, acceso: sitio, registro: registro, usuarioId: 1);

  test('aceptar aparta como un encargue más, con el nombre del pedido, y recién después avisa', () async {
    expect(await aceptar(pedidoDe(gid)), isA<PedidoAceptado>());
    expect(await stock(), 1);
    final encargues = await puerto.encargues();
    expect(encargues.single.nombreCliente, 'Sofi (WhatsApp)');
    expect(sitio.resueltos, [(id: 7, aceptado: true)]);
    expect(registro.anotados, isEmpty);
  });

  test('sin stock no acepta, no aparta nada y dice qué falta', () async {
    final r = await aceptar(pedidoDe(gid, cantidad: 5));
    expect((r as PedidoConFaltantes).faltan, ['Cerveza: piden 5, quedan 3']);
    expect(await stock(), 3);
    expect(await puerto.encargues(), isEmpty);
    expect(sitio.resueltos, isEmpty);
  });

  test('si avisar falla, el encargue queda y al reintentar no se aparta dos veces', () async {
    sitio.fallaAlResolver = const ErrorNube('sin_red', 'Sin internet');
    expect(await aceptar(pedidoDe(gid)), isA<PedidoSinAvisar>());
    expect(await stock(), 1);
    expect(registro.anotados.keys, [7]);

    expect(await aceptar(pedidoDe(gid)), isA<PedidoAceptado>());
    expect(await stock(), 1, reason: 'el reintento solo avisa');
    expect((await puerto.encargues()).length, 1);
    expect(sitio.resueltos, [(id: 7, aceptado: true)]);
    expect(registro.anotados, isEmpty);
  });

  test('si otro equipo ya lo resolvió, lo dice y deja el encargue para que se revise', () async {
    sitio.fallaAlResolver = const ErrorNube('ya_resuelto', 'Ese pedido ya lo resolvió otro equipo.', estado: 409);
    expect(await aceptar(pedidoDe(gid)), isA<PedidoYaResuelto>());
    expect((await puerto.encargues()).length, 1);
    expect(registro.anotados, isEmpty);
  });

  test('una PC que no manda la identidad de los productos pide actualizarla', () async {
    final vieja = _SinGlobalId(puerto);
    final r = await aceptarPedidoBot(pedido: pedidoDe(gid), servicio: vieja, acceso: sitio, registro: registro, usuarioId: 1);
    expect(r, isA<PedidoPcVieja>());
    expect(await puerto.encargues(), isEmpty);
  });

  test('rechazar no toca la base; un pedido ya apartado no se rechaza', () async {
    await rechazarPedidoBot(pedido: pedidoDe(gid), acceso: sitio, registro: registro);
    expect(sitio.resueltos, [(id: 7, aceptado: false)]);
    expect(await stock(), 3);

    await registro.anotar(8, 1);
    expect(() => rechazarPedidoBot(pedido: pedidoDe(gid, id: 8), acceso: sitio, registro: registro), throwsStateError);
  });
}

/// La PC de antes de 2026-10-09: los productos llegan sin `globalId`. Aceptar no llega a usar nada más.
class _SinGlobalId implements ServicioCompanion {
  _SinGlobalId(this.base);
  final PuertoLocal base;

  @override
  Future<List<ProductoCompanion>> productos({
    String? busqueda,
    int? proveedorId,
    bool sinProveedor = false,
    bool sinCosto = false,
    bool sinCategoria = false,
    bool sinCodigoBarras = false,
  }) async => [
    for (final p in await base.productos())
      ProductoCompanion(id: p.id, nombre: p.nombre, esPesable: p.esPesable, stock: p.stock, stockGramos: p.stockGramos, activo: p.activo),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

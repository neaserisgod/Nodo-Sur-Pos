// La Point como comandera de Nodo Gastro (El dueño, 2026-10-24: "cuando un pedido se confirma como tal, debe imprimir la
// comanda", también los del bot): sale una vez por pedido confirmado, en el equipo que la tiene prendida, y lo que no salió se
// reintenta.
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_pedidos_gastronomia.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/domain/bot_whatsapp.dart';
import 'package:la_plazoleta/domain/pedido_gastronomico.dart';
import 'package:la_plazoleta/servicios/comandera_point.dart';

import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late List<({String contenido, String clave})> impresas;
  late RegistroComandasEnMemoria registro;
  late ComanderaPoint comandera;
  Object? fallar;
  const milanesa = LineaPedido(gid: 'plato-mila', nombre: 'Milanesa con papas', cantidad: 2, precioCentavos: 650000);

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Ana'));
    impresas = [];
    fallar = null;
    registro = RegistroComandasEnMemoria();
    comandera = ComanderaPoint(
      db: db,
      registro: registro,
      imprimir: (contenido, {required idempotencyKey, required externalReference}) async {
        if (fallar != null) throw fallar!;
        impresas.add((contenido: contenido, clave: idempotencyKey));
      },
    );
  });
  tearDown(() async {
    comandera.detener();
    errorComanda.value = null;
    await db.close();
  });

  Future<int> pedido(CanalPedido canal, {String nombre = 'Juan'}) =>
      crearPedido(db, canal: canal, nombreCliente: nombre, lineas: const [milanesa], usuarioId: usuarioId, ahora: DateTime.now());

  test('apagada (lo de fábrica) no imprime nada', () async {
    await comandera.iniciar();
    expect(comandera.andando, isFalse);
    await pedido(CanalPedido.mostrador);
    await comandera.revisar();
    expect(impresas, isEmpty);
  });

  test('prendida: el pedido del mostrador sale solo, una vez', () async {
    await comandera.activar(true);
    await pedido(CanalPedido.mostrador);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(impresas, hasLength(1));
    expect(impresas.single.contenido, contains('2 x Milanesa con papas'));
    await comandera.revisar();
    expect(impresas, hasLength(1));
  });

  test('uno de WhatsApp sale recién cuando el local lo acepta', () async {
    await comandera.activar(true);
    final id = await pedido(CanalPedido.whatsapp);
    await comandera.revisar();
    expect(impresas, isEmpty);
    await avanzarPedido(db, id, EstadoPedido.porHacer);
    await comandera.revisar();
    expect(impresas, hasLength(1));
  });

  test('uno del bot pagado por Mercado Pago entra directo a la cocina y sale al bajar', () async {
    final mila = await crearProducto(db, nombre: 'Milanesa con papas', precioCentavos: 700000, costoCentavos: 300000, stock: 10, usuarioId: usuarioId);
    final gid = (await (db.select(db.productos)..where((p) => p.id.equals(mila))).getSingle()).globalId!;
    await comandera.activar(true);
    await importarPedidoDelBot(
      db,
      PedidoBot(
        id: 7,
        estado: EstadoPedidoBot.porConfirmar,
        clienteNombre: 'Lucas',
        clienteTelefono: '5492944555111',
        items: [ItemPedidoBot(gid: gid, nombre: 'Milanesa con papas', cantidad: 1, precioCentavos: 700000)],
        creado: DateTime.now(),
        actualizado: 1,
        pago: 'mp',
      ),
      usuarioId: usuarioId,
    );
    await comandera.revisar();
    expect(impresas.single.contenido, contains('Lucas'));
    expect(impresas.single.contenido, contains('PAGADO'));
  });

  test('al prenderla, lo que ya estaba en la cocina no sale de golpe', () async {
    await pedido(CanalPedido.mostrador);
    await comandera.activar(true);
    await comandera.revisar();
    expect(impresas, isEmpty);
    await pedido(CanalPedido.mostrador, nombre: 'Eva');
    await comandera.revisar();
    expect(impresas.single.contenido, contains('Eva'));
  });

  test('lo que no salió se reintenta con otra clave y avisa por qué', () async {
    await comandera.activar(true);
    fallar = Exception('la terminal no contesta');
    await pedido(CanalPedido.mostrador);
    await comandera.revisar();
    expect(impresas, isEmpty);
    expect(errorComanda.value, contains('la terminal no contesta'));
    fallar = null;
    await comandera.revisar();
    expect(impresas, hasLength(1));
    expect(impresas.single.clave, isNot(endsWith('-0')), reason: 'cada reintento con otra clave');
    expect(errorComanda.value, isNull);
  });

  test('"Imprimir comanda" sale siempre y no la vuelve a mandar sola', () async {
    final id = await pedido(CanalPedido.mostrador);
    final p = await (db.select(db.pedidosGastronomia)..where((x) => x.id.equals(id))).getSingle();
    await comandera.imprimirDeNuevo(p);
    await comandera.imprimirDeNuevo(p);
    expect(impresas, hasLength(2));
    expect(impresas[0].clave, isNot(impresas[1].clave));
    await registro.fijarActiva(true);
    await comandera.iniciar();
    await comandera.revisar();
    expect(impresas, hasLength(2));
  });

  test('apagarla frena todo', () async {
    await comandera.activar(true);
    await comandera.activar(false);
    expect(comandera.andando, isFalse);
  });
}

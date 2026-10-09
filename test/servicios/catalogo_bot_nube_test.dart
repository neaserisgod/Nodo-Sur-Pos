// El catálogo del bot de WhatsApp lo publica el equipo que sube a la nube (`PublicadorCatalogoBot`, `docs/PLAN-BOT.md`): solo
// si el negocio tiene el bot y solo si cambió, para no gastar pedidos de Cloudflare de más.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/servicios/catalogo_bot_nube.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';

void main() {
  late AppDatabase db;
  late List<String> rutas;
  late List<Map<String, dynamic>> publicados;
  late bool tieneBot;
  late DateTime ahora;
  late PublicadorCatalogoBot publicador;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.productos).insert(ProductosCompanion.insert(
      nombre: 'Yerba', precioCentavos: const Value(520000), stock: const Value(3), globalId: const Value('g-yerba')));
    rutas = [];
    publicados = [];
    tieneBot = true;
    ahora = DateTime(2026, 10, 9, 10);
    final cliente = ClienteNube(http: MockClient((r) async {
      rutas.add(r.url.path);
      if (r.url.path == '/api/bot/estado') return http.Response(jsonEncode({'tieneBot': tieneBot}), 200);
      publicados.add(jsonDecode(r.body) as Map<String, dynamic>);
      return http.Response(jsonEncode({'ok': true, 'cambiado': true}), 200);
    }));
    publicador = PublicadorCatalogoBot(db: db, cliente: cliente, ahora: () => ahora);
  });
  tearDown(() => db.close());

  test('publica el catálogo, y no lo vuelve a mandar si no cambió', () async {
    expect(await publicador.publicarSiHaceFalta('tok'), isTrue);
    expect(publicados.single['items'], [{'gid': 'g-yerba', 'nombre': 'Yerba', 'precioCentavos': 520000, 'hay': true}]);
    expect(await publicador.publicarSiHaceFalta('tok'), isFalse);
    expect(publicados, hasLength(1));
  });

  test('si cambia un precio o se termina el stock, lo vuelve a publicar', () async {
    await publicador.publicarSiHaceFalta('tok');
    await (db.update(db.productos)..where((p) => p.globalId.equals('g-yerba'))).write(const ProductosCompanion(stock: Value(0)));
    expect(await publicador.publicarSiHaceFalta('tok'), isTrue);
    expect((publicados.last['items'] as List).single['hay'], isFalse);
  });

  test('sin el plan con bot no publica nada, y el plan se vuelve a preguntar recién a la hora', () async {
    tieneBot = false;
    expect(await publicador.publicarSiHaceFalta('tok'), isFalse);
    expect(await publicador.publicarSiHaceFalta('tok'), isFalse);
    expect(rutas, ['/api/bot/estado'], reason: 'una sola consulta del plan');
    tieneBot = true;
    ahora = ahora.add(const Duration(minutes: 61));
    expect(await publicador.publicarSiHaceFalta('tok'), isTrue);
    expect(rutas.where((r) => r == '/api/bot/estado'), hasLength(2));
  });

  test('si el sitio falla, no tira: se reintenta en la próxima vuelta', () async {
    final roto = PublicadorCatalogoBot(db: db, cliente: ClienteNube(http: MockClient((r) async => http.Response('{"error":"server"}', 500))));
    expect(await roto.publicarSiHaceFalta('tok'), isFalse);
  });
}

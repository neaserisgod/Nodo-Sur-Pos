// Los turnos del bot en la Agenda (`SincronizadorTurnosBot`, `docs/PLAN-SERVICIOS.md` etapa 5): bajan una sola vez, lo que el
// cliente cambia por WhatsApp se aplica, lo que la dueña hace en la app le llega al bot, y lo que ocupa la Agenda se publica sin
// datos de clientes.

import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/identidad_sync.dart' show globalIdDeTurnoRemoto;
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart';
import 'package:la_plazoleta/data/repositorio_turnos.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart' show abrirSesion;
import 'package:la_plazoleta/domain/turnos.dart';
import 'package:la_plazoleta/domain/plantillas_rubro.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import 'package:la_plazoleta/servicios/turnos_bot_nube.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';

/// Cierra la caja a lo bruto: lo único que importa acá es que no quede una abierta.
Future<void> cerrarSesionParaTest(AppDatabase db, int id) =>
    (db.update(db.sesionesDeCaja)..where((s) => s.id.equals(id))).write(SesionesDeCajaCompanion(estado: const Value('CERRADA'), fechaCierre: Value(DateTime.now())));

void main() {
  late AppDatabase db;
  late int usuario;
  late int semi;
  late List<Map<String, dynamic>> remotos;
  late List<Map<String, dynamic>> cambios;
  late List<List<dynamic>> ocupados;
  late List<Map<String, dynamic>> configs;
  late Map<String, dynamic>? configSitio;
  late SincronizadorTurnosBot sinc;
  final manana10 = () {
    final h = DateTime.now();
    return DateTime(h.year, h.month, h.day + 1, 10);
  }();
  int ms(DateTime d) => d.millisecondsSinceEpoch;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = baseDeTest();
    usuario = (await db.select(db.usuarios).get()).first.id;
    await configurarRubro(db, PlantillaRubro.desdeClave('unas')!);
    semi = await crearServicio(db, nombre: 'Semipermanente', precioCentavos: 1800000, duracionMinutos: 60, pideSena: true, usuarioId: usuario);
    remotos = [];
    cambios = [];
    ocupados = [];
    configs = [];
    configSitio = {'numero_actual': '5492944111111', 'numero_duena': '5492944222222', 'pausa_minutos': 60};
    var reloj = 0;
    final cliente = ClienteNube(http: MockClient((r) async {
      switch (r.url.path) {
        case '/api/bot/estado':
          return http.Response(jsonEncode({'tieneBot': true, 'puedeConfigurar': true}), 200);
        case '/api/bot/config':
          if (r.method == 'POST') {
            configSitio = (jsonDecode(r.body) as Map<String, dynamic>)['config'] as Map<String, dynamic>;
            configs.add(configSitio!);
            return http.Response(jsonEncode({'ok': true, 'version': configs.length + 1}), 200);
          }
          return http.Response(jsonEncode({'version': 1, 'config': configSitio}), 200);
        case '/api/bot/turnos':
          final desde = int.parse(r.url.queryParameters['desde']!);
          final lista = [for (final t in remotos) if ((t['actualizado'] as int) > desde) t];
          return http.Response(jsonEncode({'turnos': lista, 'hasta': lista.isEmpty ? desde : lista.last['actualizado'], 'mas': false}), 200);
        case '/api/bot/turno/cambio':
          cambios.add(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response(jsonEncode({'ok': true}), 200);
        case '/api/bot/ocupados':
          ocupados.add((jsonDecode(r.body) as Map<String, dynamic>)['turnos'] as List);
          return http.Response(jsonEncode({'ok': true, 'cambiado': true}), 200);
      }
      return http.Response('{}', 404);
    }));
    sinc = SincronizadorTurnosBot(db: db, cliente: cliente);
    remotos.add({
      'id': 'turno-bot-000001',
      'origen': 'bot',
      'estado': 'esperando_sena',
      'inicio': ms(manana10),
      'fin': ms(manana10.add(const Duration(hours: 1))),
      'cliente': {'nombre': 'Ana', 'telefono': '5492944111111'},
      'servicio': {'nombre': 'semipermanente'},
      'senaPedidaCentavos': 540000,
      'actualizado': ++reloj,
    });
  });
  tearDown(() {
    sinc.cerrar();
    return db.close();
  });

  Future<Turno> elDelBot() => (db.select(db.turnos)..where((t) => t.idRemoto.equals('turno-bot-000001'))..orderBy([(t) => OrderingTerm.asc(t.id)])..limit(1)).getSingle();

  test('un turno del bot entra a la Agenda una sola vez, esperando la seña y ocupando el horario', () async {
    await sinc.vuelta('tok');
    await sinc.vuelta('tok');
    final t = await elDelBot();
    expect(await db.select(db.turnos).get(), hasLength(1));
    expect(t.origen, 'BOT');
    expect(t.estado, 'ESPERANDO_SENA');
    expect(t.servicioId, semi);
    expect(t.inicio, manana10);
    expect(t.telefono, '5492944111111');
    expect(t.senaPedidaCentavos, 540000);
    expect(await horariosLibresDelDia(db, manana10, duracionMin: 60), isNot(contains(manana10)));
    expect(cambios, isEmpty, reason: 'bajarlo no es un cambio de la dueña');
  });

  test('la dueña lo mueve y anota la seña en la app: el bot se entera (una vez)', () async {
    await sinc.vuelta('tok');
    final t = await elDelBot();
    await registrarSenaDeTurno(db, t.id, montoCentavos: 540000, esEfectivo: false, usuarioId: usuario);
    await moverTurno(db, t.id, manana10.add(const Duration(hours: 3)));
    await sinc.vuelta('tok');
    expect(cambios, hasLength(1));
    expect(cambios.single['id'], 'turno-bot-000001');
    expect(cambios.single['estado'], 'confirmado');
    expect(cambios.single['inicio'], ms(manana10.add(const Duration(hours: 3))));
    await sinc.vuelta('tok');
    expect(cambios, hasLength(1), reason: 'sin cambios nuevos no se manda nada');
  });

  test('el mismo turno del bot tiene el mismo id en cada celular; uno que ya quedó doble se ve una sola vez', () async {
    await sinc.vuelta('tok');
    final t = await elDelBot();
    expect(t.globalId, globalIdDeTurnoRemoto('turno-bot-000001'), reason: 'la app de almacén y la de servicios lo bajan igual');
    // Como quedaba antes: otro celular le puso su propio id y la sincronización lo trajo.
    await db.into(db.turnos).insert(TurnosCompanion.insert(
          servicioId: Value(t.servicioId),
          servicioNombre: t.servicioNombre,
          duracionMinutos: t.duracionMinutos,
          inicio: t.inicio,
          nombreCliente: t.nombreCliente,
          usuarioId: t.usuarioId,
          origen: const Value('BOT'),
          idRemoto: const Value('turno-bot-000001'),
          globalId: const Value('00000000000000000000000000000abc'),
        ));
    final delDia = await turnosDelDia(db, manana10);
    expect(delDia.where((x) => x.turno.idRemoto == 'turno-bot-000001'), hasLength(1));
    expect(delDia.single.turno.id, t.id);
    remotos.single
      ..['estado'] = 'cancelado'
      ..['actualizado'] = 99;
    await sinc.vuelta('tok');
    expect((await elDelBot()).estado, 'CANCELADO', reason: 'el duplicado no frena los cambios del bot');
  });

  test('el cliente lo cancela por WhatsApp: se cancela en la Agenda', () async {
    await sinc.vuelta('tok');
    remotos.single
      ..['estado'] = 'cancelado'
      ..['actualizado'] = 99;
    await sinc.vuelta('tok');
    expect((await elDelBot()).estado, 'CANCELADO');
    expect(cambios, isEmpty, reason: 'no se le devuelve al bot su propio cambio');
  });

  test('cancelado por WhatsApp con seña a devolver y sin caja abierta: se cancela igual y no frena nada', () async {
    await guardarConfigAgenda(db, const ConfigAgenda(sena: ConfigSena(devolverAlCancelar: true)));
    await sinc.vuelta('tok');
    final sesion = await abrirSesion(db, usuarioId: usuario, fondoInicialCentavos: 0);
    await registrarSenaDeTurno(db, (await elDelBot()).id, montoCentavos: 540000, esEfectivo: true, usuarioId: usuario, sesionCajaId: sesion);
    await cerrarSesionParaTest(db, sesion);
    remotos.single
      ..['estado'] = 'cancelado'
      ..['actualizado'] = 99;
    await sinc.vuelta('tok');
    expect((await elDelBot()).estado, 'CANCELADO');
  });

  test('la seña pagada con el link de Mercado Pago entra a la caja como Mercado Pago, una sola vez', () async {
    await sinc.vuelta('tok');
    final sesion = await abrirSesion(db, usuarioId: usuario, fondoInicialCentavos: 0);
    remotos.single
      ..['estado'] = 'confirmado'
      ..['senaPagada'] = {'centavos': 540000, 'pagoId': '77001'}
      ..['actualizado'] = 99;
    await sinc.vuelta('tok');
    var t = await elDelBot();
    expect(t.estado, 'CONFIRMADO');
    expect(t.senaCentavos, 540000);
    expect(t.senaEsEfectivo, isFalse);
    expect(t.senaEnCaja, isTrue);
    remotos.single['actualizado'] = 100;
    await sinc.vuelta('tok');
    t = await elDelBot();
    expect(t.senaCentavos, 540000, reason: 'no se anota dos veces');
    final ingresos = await (db.select(db.movimientosDeCaja)..where((m) => m.sesionCajaId.equals(sesion))).get();
    expect(ingresos.where((m) => m.montoCentavos == 540000), hasLength(1));
  });

  test('un turno que llega ya pagado (la app estaba cerrada) también anota la seña', () async {
    remotos.single
      ..['estado'] = 'confirmado'
      ..['senaPagada'] = {'centavos': 540000, 'pagoId': '77002'};
    await sinc.vuelta('tok');
    final t = await elDelBot();
    expect(t.senaCentavos, 540000);
    expect(t.senaEnCaja, isFalse, reason: 'sin caja abierta entra al abrirla');
  });

  test('lo que carga la dueña se publica como ocupado, sin datos de clientes y sin los turnos del bot', () async {
    await sinc.vuelta('tok');
    await crearTurno(db, servicioId: semi, inicio: manana10.add(const Duration(hours: 5)), nombreCliente: 'Bea', telefono: '5492944222222', usuarioId: usuario);
    await sinc.vuelta('tok');
    final ultimo = ocupados.last.cast<Map<String, dynamic>>();
    expect(ultimo, hasLength(1));
    expect(ultimo.single.keys.toSet(), {'id', 'inicio', 'fin', 'estado'});
    expect(ultimo.single['inicio'], ms(manana10.add(const Duration(hours: 5))));
    expect(jsonEncode(ultimo), isNot(contains('Bea')));
    final antes = ocupados.length;
    await sinc.vuelta('tok');
    expect(ocupados, hasLength(antes), reason: 'igual que antes: no se vuelve a mandar');
  });

  test('los servicios, el horario y la seña del negocio llegan solos al bot, y solo cuando cambian', () async {
    await guardarConfigAgenda(db, const ConfigAgenda(aliasSena: 'caro.unas', titularSena: 'Carolina'));
    await sinc.vuelta('tok');
    expect(configs, hasLength(1));
    final servicio = (configs.single['servicios'] as List).single as Map;
    expect(servicio['nombre'], 'Semipermanente');
    expect(servicio['sena'], 5400);
    expect((configs.single['senas'] as Map)['alias_mp'], 'caro.unas');
    expect(configs.single['numero_actual'], '5492944111111', reason: 'los números quedan');
    await sinc.vuelta('tok');
    expect(configs, hasLength(1), reason: 'sin cambios no se vuelve a guardar');
    await editarServicio(db, id: semi, nombre: 'Semipermanente', precioCentavos: 2000000, duracionMinutos: 60, usuarioId: usuario);
    await sinc.vuelta('tok');
    expect(((configs.last['servicios'] as List).single as Map)['precio'], 20000);
  });

  test('sin la configuración básica del bot (los números) no publica nada', () async {
    configSitio = null;
    await sinc.vuelta('tok');
    expect(configs, isEmpty);
  });

  test('en un comercio no hace nada', () async {
    await configurarRubro(db, PlantillaRubro.desdeClave('almacen')!);
    await sinc.vuelta('tok');
    expect(await db.select(db.turnos).get(), isEmpty);
    expect(ocupados, isEmpty);
  });
}

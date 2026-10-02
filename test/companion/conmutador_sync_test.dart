// Quién sincroniza el celular: la PC por wifi o la nube. Las reglas (`conmutador_sync.dart`) con callbacks, y el
// traspaso de punta a punta con la sync real contra un servidor falso.

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/conmutador_sync.dart';
import 'package:la_plazoleta/companion/sync_nube_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/identidad_sync.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import 'package:la_plazoleta/servicios/sync_nube.dart';

import '../helpers/base_para_tests.dart';
import '../helpers/servidor_sync_falso.dart';

const _espera = Duration(milliseconds: 40);

Future<void> _pasar([int ms = 120]) => Future<void>.delayed(Duration(milliseconds: ms));

Future<void> _esperarHasta(bool Function() condicion, {String que = 'la condición'}) async {
  final limite = DateTime.now().add(const Duration(seconds: 3));
  while (!condicion()) {
    if (DateTime.now().isAfter(limite)) fail('no se cumplió: $que');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('las reglas', () {
    late int iniciadas;
    late int detenidas;
    late bool cuenta;
    late ConmutadorSync c;

    setUp(() {
      iniciadas = 0;
      detenidas = 0;
      cuenta = true;
      c = ConmutadorSync(
        iniciarNube: () => iniciadas++,
        detenerNube: () => detenidas++,
        hayCuenta: () async => cuenta,
        esperaTraspaso: _espera,
      );
      addTearDown(c.cerrar);
    });

    test('con la PC conectada la nube no se enciende', () async {
      c.definirPc(emparejada: true);
      c.pcConectada(true);
      await _pasar();
      expect(c.modo.value, ModoSync.pc);
      expect(iniciadas, 0);
    });

    test('si la PC deja de contestar, pasa a la nube pero recién después de la espera', () async {
      c.definirPc(emparejada: true);
      c.pcConectada(true);
      c.pcConectada(false);
      await _pasar(10);
      expect(iniciadas, 0, reason: 'todavía puede ser un corte de wifi de un instante');
      await _pasar();
      expect(iniciadas, 1);
      expect(c.modo.value, ModoSync.nube);
    });

    test('un corte corto que se recupera antes de la espera nunca toca la nube', () async {
      c.definirPc(emparejada: true);
      c.pcConectada(true);
      c.pcConectada(false);
      await _pasar(10);
      c.pcConectada(true);
      await _pasar(150);
      expect(iniciadas, 0);
      expect(c.modo.value, ModoSync.pc);
    });

    test('cuando la PC vuelve, la nube se pausa al instante', () async {
      c.definirPc(emparejada: true);
      c.pcConectada(false);
      await _pasar();
      expect(c.modo.value, ModoSync.nube);

      c.pcConectada(true);
      expect(detenidas, 1);
      expect(c.modo.value, ModoSync.pc);
    });

    test('muchos vaivenes no arrancan la nube dos veces seguidas', () async {
      c.definirPc(emparejada: true);
      c.pcConectada(false);
      c.pcConectada(false);
      await _pasar();
      c.pcConectada(false);
      await _pasar();
      expect(iniciadas, 1);
    });

    test('solo celular (sin PC): la nube arranca de una, sin esperar', () async {
      c.definirPc(emparejada: false);
      await _pasar(10);
      expect(iniciadas, 1);
      expect(c.modo.value, ModoSync.nube);
    });

    test('sin cuenta no hay nube: queda solo en el celular, y al vincular arranca', () async {
      cuenta = false;
      c.definirPc(emparejada: false);
      await _pasar(10);
      expect(iniciadas, 0);
      expect(c.modo.value, ModoSync.local);

      cuenta = true;
      c.reevaluar();
      await _pasar(10);
      expect(iniciadas, 1);
      expect(c.modo.value, ModoSync.nube);
    });

    test('al desvincular se apaga y no vuelve a arrancar sola', () async {
      c.definirPc(emparejada: false);
      await _pasar(10);
      cuenta = false;
      c.reevaluar();
      await _pasar(10);
      expect(detenidas, 1);
      expect(iniciadas, 1);
      expect(c.modo.value, ModoSync.local);
    });

    test('desconectar la PC desde Gestión pasa de inmediato al modo solo celular', () async {
      c.definirPc(emparejada: true);
      c.pcConectada(true);
      c.pcConectada(false); // el menú corta la escucha
      c.definirPc(emparejada: false);
      await _pasar(10);
      expect(iniciadas, 1, reason: 'sin PC no hay a quién esperar');
    });
  });

  group('el traspaso de punta a punta', () {
    late ServidorSyncFalso servidor;
    late AppDatabase dbPc;
    late AppDatabase dbCel;
    late ServicioSyncNube syncPc;
    late SyncNubeCompanion celular;
    late int usuarioPc;

    setUp(() async {
      servidor = ServidorSyncFalso();
      dbPc = baseDeTest();
      dbCel = baseDeTest();
      establecerIdDispositivo('desktop');
      usuarioPc = (await dbPc.select(dbPc.usuarios).get()).first.id;

      CuentaVinculada cuentaDe(String t) =>
          CuentaVinculada(token: t, email: 'a@b.com', idDispositivo: t, nombreDispositivo: t, vence: 99);
      final almacenPc = AlmacenCuentaEnMemoria();
      await almacenPc.guardar(cuentaDe('tok-pc'));
      syncPc = ServicioSyncNube(
        db: dbPc,
        almacenCuenta: almacenPc,
        cliente: ClienteNube(http: servidor.http_, abrirEscucha: servidor.abrir),
        almacenEstado: AlmacenEstadoSyncEnMemoria(),
      );

      final almacenCel = AlmacenCuentaEnMemoria();
      await almacenCel.guardar(cuentaDe('tok-cel'));
      celular = armarSyncNubeCompanion(
        almacen: almacenCel,
        almacenEstado: AlmacenEstadoSyncEnMemoria(),
        cliente: ClienteNube(http: servidor.http_, abrirEscucha: servidor.abrir),
        abrirNavegador: (_) async {},
        db: dbCel,
        esperaTraspaso: _espera,
      );
    });

    tearDown(() async {
      celular.servicio.detener();
      celular.conmutador.cerrar();
      await dbPc.close();
      await dbCel.close();
      establecerIdDispositivo('desktop');
    });

    Future<Producto?> enCel(String nombre) async =>
        (await dbCel.select(dbCel.productos).get()).where((p) => p.nombre == nombre).firstOrNull;

    test('con la PC conectada el celular no toca la nube; si la PC se apaga, se pone al día y sigue solo', () async {
      // 1) La PC está viva y tiene datos, que ya subió a la nube.
      await crearProducto(dbPc, nombre: 'Jamón cocido', precioCentavos: 365000, stock: 4, usuarioId: usuarioPc);
      await syncPc.sincronizar();

      // 2) El celular está con la PC por wifi: la nube del celular no hace nada.
      celular.conmutador.definirPc(emparejada: true);
      celular.conmutador.pcConectada(true);
      await _pasar(300);
      expect(celular.conmutador.modo.value, ModoSync.pc);
      expect(servidor.conexiones, 0);
      expect(servidor.consultasDe['tok-cel'], isNull);
      expect(await enCel('Jamón cocido'), isNull, reason: 'por wifi le llegaría de la PC; acá no hay wifi simulado');

      // 3) Se apaga la PC. El celular tiene que quedar sincronizando con la nube sin que nadie toque nada.
      celular.conmutador.pcConectada(false);
      await _esperarHasta(() => celular.conmutador.modo.value == ModoSync.nube, que: 'pasar a la nube');
      await _esperarHasta(() => servidor.conexiones >= 1, que: 'conectar los avisos');
      await _esperarHasta(() => celular.servicio.ultimo is SyncNubeOk, que: 'la primera vuelta');
      expect((await enCel('Jamón cocido'))!.precioCentavos, 365000, reason: 'se puso al día con lo que ya estaba en la nube');

      // 4) Lo que el celular hace sin PC sube solo a la nube.
      final usuarioCel = (await dbCel.select(dbCel.usuarios).get()).first.id;
      await crearProducto(dbCel, nombre: 'Yerba 1 kg', precioCentavos: 460000, stock: 3, usuarioId: usuarioCel);
      await _esperarHasta(() => servidor.lotes.any((l) => l.token == 'tok-cel'), que: 'que suba lo del celular');

      // 5) Y cuando la PC vuelve, lo recibe de la nube.
      await syncPc.sincronizar();
      final enPc = (await dbPc.select(dbPc.productos).get()).where((p) => p.nombre == 'Yerba 1 kg');
      expect(enPc.single.precioCentavos, 460000);
    });

    test('lo que hace otro dispositivo mientras el celular está en la nube le llega por aviso', () async {
      celular.conmutador.definirPc(emparejada: false); // solo celular
      await _esperarHasta(() => celular.servicio.escuchando, que: 'conectar los avisos');

      await crearProducto(dbPc, nombre: 'Leche 1 L', precioCentavos: 160000, stock: 8, usuarioId: usuarioPc);
      await syncPc.sincronizar();

      var visto = false;
      final limite = DateTime.now().add(const Duration(seconds: 3));
      while (!visto && DateTime.now().isBefore(limite)) {
        visto = await enCel('Leche 1 L') != null;
        if (!visto) await _pasar(20);
      }
      expect(visto, isTrue);
    });

    test('al volver la PC, la nube del celular se pausa y deja de consultar', () async {
      celular.conmutador.definirPc(emparejada: true);
      celular.conmutador.pcConectada(false);
      await _esperarHasta(() => celular.servicio.escuchando, que: 'conectar los avisos');
      await _pasar(150);

      celular.conmutador.pcConectada(true);
      expect(celular.servicio.escuchando, isFalse);
      final consultas = servidor.consultas;
      final conexiones = servidor.conexiones;
      servidor.cortarAvisos();
      await _pasar(300);
      expect(servidor.consultas, consultas);
      expect(servidor.conexiones, conexiones, reason: 'ni reconecta ni consulta mientras la PC contesta');
    });
  });
}

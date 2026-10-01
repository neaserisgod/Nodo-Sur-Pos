// Sync por la nube de punta a punta: dos bases en memoria (PC y celular), cada
// una con su servicio, hablando con un servidor falso que cumple el contrato
// de `/api/sync` del Worker (`NodoSurPage/functions/api/sync.js`): lotes
// numerados por orden de llegada, idempotentes por `X-Lote-Id`, y cada
// dispositivo recibe solo los de los otros.

import 'dart:convert';
import 'dart:io' show gzip;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/identidad_sync.dart';
import 'package:la_plazoleta/data/registro_sync_nube.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/data/repositorio_sincronizacion.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import 'package:la_plazoleta/servicios/sync_nube.dart';

import '../helpers/base_para_tests.dart';

class _Lote {
  _Lote(this.seq, this.token, this.id, this.bytes);
  final int seq;
  final String token;
  final String id;
  final List<int> bytes;
}

/// El Worker, en memoria. `token` identifica al dispositivo (como el token real).
class _Servidor {
  final lotes = <_Lote>[];
  var _seq = 0;
  bool caido = false;

  /// Simula un corte DESPUÉS de guardar: el lote queda, pero la respuesta nunca llega.
  bool perderRespuestaDelProximoPost = false;
  bool expirado = false;

  late final cliente = http.Client();

  MockClient get http_ => MockClient((r) async {
        if (caido) throw http.ClientException('sin red');
        final token = r.headers['Authorization']!.substring('Bearer '.length);
        if (r.method == 'POST') {
          final id = r.headers['X-Lote-Id']!;
          final previo = lotes.where((l) => l.id == id).firstOrNull;
          final lote = previo ?? _Lote(++_seq, token, id, r.bodyBytes);
          if (previo == null) lotes.add(lote);
          if (perderRespuestaDelProximoPost) {
            perderRespuestaDelProximoPost = false;
            throw http.ClientException('se cortó');
          }
          return http.Response(jsonEncode({'ok': true, 'seq': lote.seq, 'repetido': previo != null}), 200);
        }
        if (expirado) return http.Response(jsonEncode({'expirado': true, 'purgadoHasta': 9}), 200);
        final desde = int.parse(r.url.queryParameters['desde']!);
        final nuevos = lotes.where((l) => l.seq > desde).toList();
        return http.Response(
          jsonEncode({
            'expirado': false,
            'lotes': [
              for (final l in nuevos.where((l) => l.token != token))
                {'seq': l.seq, 'deviceId': l.token, 'creadoEn': 1, 'datos': base64Encode(l.bytes)},
            ],
            'hasta': nuevos.isEmpty ? desde : nuevos.last.seq,
            'mas': false,
          }),
          200,
        );
      });
}

class _Dispositivo {
  _Dispositivo(this.token, _Servidor servidor, this.db)
      : estado = AlmacenEstadoSyncEnMemoria(),
        cuenta = AlmacenCuentaEnMemoria() {
    cuenta.guardar(CuentaVinculada(token: token, email: 'a@b.com', idDispositivo: token, nombreDispositivo: token, vence: 99));
    servicio = ServicioSyncNube(
      db: db,
      almacenCuenta: cuenta,
      cliente: ClienteNube(http: servidor.http_),
      almacenEstado: estado,
      alAplicarBajada: () => bajadas++,
    );
  }

  final String token;
  final AppDatabase db;
  final AlmacenEstadoSyncEnMemoria estado;
  final AlmacenCuentaEnMemoria cuenta;
  late final ServicioSyncNube servicio;
  int bajadas = 0;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late _Servidor servidor;
  late AppDatabase dbPc;
  late AppDatabase dbCel;
  late _Dispositivo pc;
  late _Dispositivo cel;
  late int usuarioPc;
  late int usuarioCel;

  setUp(() async {
    servidor = _Servidor();
    dbPc = baseDeTest();
    dbCel = baseDeTest();
    establecerIdDispositivo('desktop');
    pc = _Dispositivo('tok-pc', servidor, dbPc);
    cel = _Dispositivo('tok-cel', servidor, dbCel);
    usuarioPc = (await dbPc.select(dbPc.usuarios).get()).first.id;
    usuarioCel = (await dbCel.select(dbCel.usuarios).get()).first.id;
  });

  tearDown(() async {
    await dbPc.close();
    await dbCel.close();
    establecerIdDispositivo('desktop');
  });

  Future<Producto> producto(AppDatabase db, String nombre) =>
      (db.select(db.productos)..where((p) => p.nombre.equals(nombre))).getSingle();

  Future<int> nuevoProducto(AppDatabase db, int usuario, String nombre, {int precio = 100000, int stock = 10}) =>
      crearProducto(db, nombre: nombre, precioCentavos: precio, stock: stock, usuarioId: usuario);

  test('lo que se carga en la PC llega al celular, con su categoría', () async {
    final cat = await crearCategoria(dbPc, 'Fiambres importados');
    await crearProducto(dbPc, nombre: 'Jamón cocido', precioCentavos: 365000, stock: 4, usuarioId: usuarioPc, categoriaId: cat);

    final subida = await pc.servicio.sincronizar() as SyncNubeOk;
    expect(subida.subidas, greaterThan(0));
    final bajada = await cel.servicio.sincronizar() as SyncNubeOk;
    expect(bajada.bajadas, greaterThan(0));

    final p = await producto(dbCel, 'Jamón cocido');
    expect(p.precioCentavos, 365000);
    expect(p.stock, 4);
    final c = await (dbCel.select(dbCel.categorias)..where((c) => c.id.equals(p.categoriaId!))).getSingle();
    expect(c.nombre, 'Fiambres importados');
    expect(cel.bajadas, 1, reason: 'las pantallas se enteran de que bajó algo');
  });

  test('no hay eco: lo recibido no se vuelve a subir como propio', () async {
    await nuevoProducto(dbPc, usuarioPc, 'Yerba 1 kg');
    await pc.servicio.sincronizar();
    await cel.servicio.sincronizar();
    final lotesAntes = servidor.lotes.length;

    final vuelta = await cel.servicio.sincronizar() as SyncNubeOk;
    expect(vuelta.subidas, 0);
    expect(vuelta.bajadas, 0);
    final vueltaPc = await pc.servicio.sincronizar() as SyncNubeOk;
    expect(vueltaPc.subidas, 0);
    expect(vueltaPc.bajadas, 0);
    expect(servidor.lotes.length, lotesAntes);
  });

  test('si se edita lo recibido, eso sí sube; y la otra punta lo recibe', () async {
    final id = await nuevoProducto(dbPc, usuarioPc, 'Yerba 1 kg', precio: 460000);
    await pc.servicio.sincronizar();
    await cel.servicio.sincronizar();

    final enCel = await producto(dbCel, 'Yerba 1 kg');
    await actualizarProducto(dbCel, id: enCel.id, nombre: 'Yerba 1 kg', esPesable: false, precioCentavos: 500000, stock: 10, activo: true, usuarioId: usuarioCel);
    final subida = await cel.servicio.sincronizar() as SyncNubeOk;
    expect(subida.subidas, greaterThan(0));

    await pc.servicio.sincronizar();
    expect((await (dbPc.select(dbPc.productos)..where((p) => p.id.equals(id))).getSingle()).precioCentavos, 500000);
  });

  test('gana el último en llegar al servidor, aunque su reloj diga que es más viejo', () async {
    final id = await nuevoProducto(dbPc, usuarioPc, 'Leche 1 L', precio: 160000);
    await pc.servicio.sincronizar();
    await cel.servicio.sincronizar();
    final idCel = (await producto(dbCel, 'Leche 1 L')).id;

    // Los dos cambian el precio sin verse. El reloj del celular está ATRASADO: su cambio dice ser más viejo.
    await actualizarProducto(dbPc, id: id, nombre: 'Leche 1 L', esPesable: false, precioCentavos: 170000, stock: 10, activo: true, usuarioId: usuarioPc);
    await dbPc.customStatement('UPDATE productos SET actualizado_en = 2000000 WHERE id = $id');
    await actualizarProducto(dbCel, id: idCel, nombre: 'Leche 1 L', esPesable: false, precioCentavos: 190000, stock: 10, activo: true, usuarioId: usuarioCel);
    await dbCel.customStatement('UPDATE productos SET actualizado_en = 1000000 WHERE id = $idCel');

    await pc.servicio.sincronizar(); // llega primero
    await cel.servicio.sincronizar(); // llega último: baja lo de la PC y después sube lo suyo
    await pc.servicio.sincronizar();

    expect((await producto(dbPc, 'Leche 1 L')).precioCentavos, 190000);
    expect((await producto(dbCel, 'Leche 1 L')).precioCentavos, 190000);
  });

  test('el stock suma los movimientos de los dos: ninguna venta se pierde ni se repite', () async {
    final id = await nuevoProducto(dbPc, usuarioPc, 'Coca-Cola 500ml');
    await pc.servicio.sincronizar();
    await cel.servicio.sincronizar();
    final idCel = (await producto(dbCel, 'Coca-Cola 500ml')).id;

    await ajustarStockRapido(dbPc, productoId: id, usuarioId: usuarioPc, stock: 7); // −3
    await ajustarStockRapido(dbCel, productoId: idCel, usuarioId: usuarioCel, stock: 8); // −2
    await pc.servicio.sincronizar();
    await cel.servicio.sincronizar();
    await pc.servicio.sincronizar();
    // Otra vuelta de cada uno: no puede mover nada más.
    await cel.servicio.sincronizar();
    await pc.servicio.sincronizar();

    expect((await producto(dbPc, 'Coca-Cola 500ml')).stock, 5);
    expect((await producto(dbCel, 'Coca-Cola 500ml')).stock, 5);
  });

  test('recibir un movimiento de stock no hace que el producto parezca editado', () async {
    final id = await nuevoProducto(dbPc, usuarioPc, 'Agua mineral');
    await pc.servicio.sincronizar();
    await cel.servicio.sincronizar();
    await ajustarStockRapido(dbPc, productoId: id, usuarioId: usuarioPc, stock: 6);
    await pc.servicio.sincronizar();

    final r = await cel.servicio.sincronizar() as SyncNubeOk;
    expect(r.bajadas, greaterThan(0));
    expect(r.subidas, 0, reason: 'el celular solo recibió; no tiene nada propio para mandar');
  });

  test('un corte con la respuesta perdida no duplica: al reintentar el servidor reconoce el lote', () async {
    await nuevoProducto(dbPc, usuarioPc, 'Fideos 500 g');
    servidor.perderRespuestaDelProximoPost = true;
    final fallo = await pc.servicio.sincronizar();
    expect(fallo, isA<SyncNubeFallida>());
    expect((fallo as SyncNubeFallida).sinRed, isTrue);
    final guardados = servidor.lotes.length;
    expect(guardados, 1, reason: 'el servidor sí lo recibió');

    final ok = await pc.servicio.sincronizar() as SyncNubeOk;
    expect(ok.subidas, greaterThan(0));
    expect(servidor.lotes.length, guardados, reason: 'el mismo lote, con el mismo id: no se guarda dos veces');
    await cel.servicio.sincronizar();
    expect((await producto(dbCel, 'Fideos 500 g')).stock, 10);
  });

  test('sin conexión no se pierde nada: lo pendiente sube cuando vuelve', () async {
    servidor.caido = true;
    await nuevoProducto(dbPc, usuarioPc, 'Aceite 1,5 L');
    final r = await pc.servicio.sincronizar() as SyncNubeFallida;
    expect(r.sinRed, isTrue);
    expect(servidor.lotes, isEmpty);

    servidor.caido = false;
    await pc.servicio.sincronizar();
    await cel.servicio.sincronizar();
    expect((await producto(dbCel, 'Aceite 1,5 L')).precioCentavos, 100000);
  });

  test('sin cuenta vinculada no hace nada', () async {
    await pc.cuenta.borrar();
    expect(await pc.servicio.sincronizar(), isA<SyncNubeSinCuenta>());
    expect(servidor.lotes, isEmpty);
  });

  test('si el servidor ya no guarda lo que faltaba, avisa que hace falta una copia', () async {
    servidor.expirado = true;
    expect(await cel.servicio.sincronizar(), isA<SyncNubeExpirada>());
    expect((await cel.estado.leer()).necesitaCopia, isTrue);
  });

  test('un lote de más de un MB se parte en varios, en el orden en que hay que aplicarlos', () async {
    final cat = await crearCategoria(dbPc, 'Almacén seco');
    for (var i = 0; i < 6; i++) {
      await crearProducto(dbPc, nombre: 'Producto $i', precioCentavos: 1000 + i, stock: 1, usuarioId: usuarioPc, categoriaId: cat);
    }
    final plan = await prepararSubidas(dbPc, EstadoSyncNube(), maxBytes: 1); // todo se pasa del tope
    expect(plan.lotes.length, greaterThan(6));
    expect(plan.lotes.every((l) => l.entradas.length == 1), isTrue);
    // La categoría va antes que los productos que la referencian.
    final tablas = [for (final l in plan.lotes) l.entradas.single.tabla];
    expect(tablas.indexOf('categorias'), lessThan(tablas.indexOf('productos')));

    // Y partido igual llega completo.
    final estado = EstadoSyncNube();
    for (final l in plan.lotes) {
      expect(l.bytes.length, lessThan(2000));
      expect(utf8.decode(gzip.decode(l.bytes)), contains('"v":1'));
    }
    expect(estado.cursorBajada, 0);
  });

  test('con un servidor que parte los lotes, el celular recibe todo igual', () async {
    final cat = await crearCategoria(dbPc, 'Almacén seco');
    for (var i = 0; i < 25; i++) {
      await crearProducto(dbPc, nombre: 'Producto $i', precioCentavos: 1000 + i, stock: 1, usuarioId: usuarioPc, categoriaId: cat);
    }
    final plan = await prepararSubidas(dbPc, EstadoSyncNube(), maxFilas: 10);
    expect(plan.lotes.length, greaterThan(2));
    await pc.servicio.sincronizar();
    await cel.servicio.sincronizar();
    final recibidos = (await dbCel.select(dbCel.productos).get()).where((p) => p.nombre.startsWith('Producto '));
    expect(recibidos.length, 25);
  });

  test('ninguna tabla sincronizada lleva columnas de tokens o credenciales', () async {
    for (final tabla in tablasSincronizables.keys) {
      final columnas = await dbPc.customSelect("SELECT name FROM pragma_table_info('$tabla')").get();
      for (final c in columnas) {
        final nombre = c.data['name'] as String;
        expect(nombre.contains('token') || nombre.contains('secret') || nombre.contains('password'), isFalse, reason: '$tabla.$nombre');
      }
    }
  });

  test('el registro se guarda y se lee igual; un archivo roto vuelve a empezar', () {
    final estado = EstadoSyncNube(cursorBajada: 7, cursoresSubida: {'productos': 5}, vistas: {
      'productos': {'g1': (valor: 5, huella: 'h')},
    });
    final leido = EstadoSyncNube.desdeJson(jsonDecode(jsonEncode(estado.toJson())));
    expect(leido.cursorBajada, 7);
    expect(leido.cursorDe('productos'), 5);
    expect(leido.vistas['productos']!['g1']!.huella, 'h');
    expect(EstadoSyncNube.desdeJson('basura').cursorBajada, 0);
  });
}

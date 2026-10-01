// Sync por la nube de punta a punta: dos bases en memoria (PC y celular), cada
// una con su servicio, hablando con un servidor falso que cumple el contrato
// de `/api/sync` del Worker (`NodoSurPage/functions/api/sync.js`): lotes
// numerados por orden de llegada, idempotentes por `X-Lote-Id`, y cada
// dispositivo recibe solo los de los otros.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show gzip;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/identidad_sync.dart';
import 'package:la_plazoleta/data/registro_sync_nube.dart';
import 'package:la_plazoleta/data/repositorio_productos.dart';
import 'package:la_plazoleta/data/repositorio_sincronizacion.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import 'package:la_plazoleta/servicios/sync_nube.dart';

import '../helpers/base_para_tests.dart';
import '../helpers/servidor_sync_falso.dart';

class _Dispositivo {
  _Dispositivo(this.token, ServidorSyncFalso servidor, this.db)
      : estado = AlmacenEstadoSyncEnMemoria(),
        cuenta = AlmacenCuentaEnMemoria() {
    cuenta.guardar(CuentaVinculada(token: token, email: 'a@b.com', idDispositivo: token, nombreDispositivo: token, vence: 99));
    servicio = ServicioSyncNube(
      db: db,
      almacenCuenta: cuenta,
      cliente: ClienteNube(http: servidor.http_, abrirEscucha: servidor.abrir),
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

  late ServidorSyncFalso servidor;
  late AppDatabase dbPc;
  late AppDatabase dbCel;
  late _Dispositivo pc;
  late _Dispositivo cel;
  late int usuarioPc;
  late int usuarioCel;

  setUp(() async {
    servidor = ServidorSyncFalso();
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

  group('aviso en vivo (sin consultar por tiempo)', () {
    // Tiempos cortos a propósito: lo que se prueba es el comportamiento, no los valores reales.
    void arrancar(_Dispositivo d, {StreamController<void>? cambios, List<Duration>? reintentos}) {
      d.servicio.iniciar(
        cambiosLocales: cambios?.stream ?? const Stream.empty(),
        agruparCambios: const Duration(milliseconds: 20),
        agruparAvisos: const Duration(milliseconds: 10),
        reintentos: reintentos ?? const [Duration(milliseconds: 30)],
        sinCuenta: const Duration(milliseconds: 30),
      );
      addTearDown(d.servicio.detener);
    }

    Future<void> esperar(bool Function() condicion, {String que = 'la condición'}) async {
      final limite = DateTime.now().add(const Duration(seconds: 3));
      while (!condicion()) {
        if (DateTime.now().isAfter(limite)) fail('no se cumplió: $que');
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test('conectado y sin novedades no se hace NINGUNA consulta por las dudas', () async {
      arrancar(cel);
      await esperar(() => cel.servicio.escuchando, que: 'conectar');
      await esperar(() => servidor.consultas >= 1, que: 'la puesta al día inicial');
      await Future<void>.delayed(const Duration(milliseconds: 100)); // que termine la inicial
      final consultas = servidor.consultas;
      await Future<void>.delayed(const Duration(milliseconds: 500)); // muchos "ticks" de lo que antes era el latido
      expect(servidor.consultas, consultas, reason: 'sin avisos no hay pedidos');
    });

    test('cuando otro dispositivo sube algo, llega el aviso y recién ahí se baja', () async {
      arrancar(cel);
      await esperar(() => cel.servicio.escuchando, que: 'conectar');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final antes = servidor.consultasDe['tok-cel'] ?? 0;

      await nuevoProducto(dbPc, usuarioPc, 'Jamón cocido');
      await pc.servicio.sincronizar();
      await esperar(() => (servidor.consultasDe['tok-cel'] ?? 0) > antes, que: 'que baje por el aviso');
      await esperar(() => cel.bajadas > 0, que: 'que se aplique');
      expect((await producto(dbCel, 'Jamón cocido')).stock, 10);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect((servidor.consultasDe['tok-cel'] ?? 0) - antes, 1, reason: 'una sola bajada por ese aviso');
    });

    test('un aviso no se dispara por los lotes propios', () async {
      arrancar(pc);
      await esperar(() => pc.servicio.escuchando, que: 'conectar');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final antes = servidor.consultas;
      await nuevoProducto(dbPc, usuarioPc, 'Yerba 1 kg');
      await pc.servicio.sincronizar(); // sube; el servidor no le avisa a quien subió
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(servidor.consultas - antes, 1, reason: 'la bajada de la propia vuelta, ninguna extra por aviso');
    });

    test('si se corta la conexión reconecta sola y se pone al día de lo que se perdió', () async {
      arrancar(cel);
      await esperar(() => cel.servicio.escuchando, que: 'conectar');
      servidor.cortarAvisos();
      await esperar(() => !cel.servicio.escuchando, que: 'notar el corte');
      await nuevoProducto(dbPc, usuarioPc, 'Leche 1 L'); // mientras el celular no escuchaba
      await pc.servicio.sincronizar();
      await esperar(() => cel.servicio.escuchando && servidor.conexiones >= 2, que: 'reconectar');
      await esperar(() => cel.bajadas > 0, que: 'ponerse al día');
      expect((await producto(dbCel, 'Leche 1 L')).precioCentavos, 100000);
    });

    test('sin aviso en vivo en el servidor consulta una vez por intento, cada vez más espaciado', () async {
      servidor.sinAvisoEnVivo = true;
      arrancar(cel, reintentos: const [Duration(milliseconds: 40), Duration(milliseconds: 80), Duration(milliseconds: 160)]);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(cel.servicio.escuchando, isFalse);
      expect(servidor.consultas, inInclusiveRange(3, 7), reason: 'espaciando: nada de una consulta cada pocos milisegundos');
      // Y aun así lo que sube otro le llega en alguno de esos intentos.
      await nuevoProducto(dbPc, usuarioPc, 'Fideos 500 g');
      await pc.servicio.sincronizar();
      await esperar(() => cel.bajadas > 0, que: 'llegar por consulta');
    });

    test('cuando vuelve el aviso en vivo, deja de consultar', () async {
      servidor.sinAvisoEnVivo = true;
      arrancar(cel, reintentos: const [Duration(milliseconds: 30)]);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      servidor.sinAvisoEnVivo = false;
      await esperar(() => cel.servicio.escuchando, que: 'conectar');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final consultas = servidor.consultas;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(servidor.consultas, consultas);
    });

    test('una ráfaga de cambios locales es una sola subida', () async {
      final cambios = StreamController<void>();
      addTearDown(cambios.close);
      arrancar(pc, cambios: cambios);
      await esperar(() => pc.servicio.escuchando, que: 'conectar');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final antes = servidor.subidas;
      await nuevoProducto(dbPc, usuarioPc, 'Agua mineral');
      cambios..add(null)..add(null)..add(null);
      await esperar(() => servidor.subidas > antes, que: 'que suba');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(servidor.subidas - antes, 1);
    });

    test('sin cuenta vinculada no abre conexiones; al vincular, empieza sola', () async {
      await cel.cuenta.borrar();
      arrancar(cel);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(servidor.conexiones, 0);
      expect(servidor.consultas, 0);
      await cel.cuenta.guardar(const CuentaVinculada(token: 'tok-cel', email: 'a@b.com', idDispositivo: 'tok-cel', nombreDispositivo: 'cel', vence: 99));
      await esperar(() => cel.servicio.escuchando, que: 'conectar al vincular');
    });

    test('detener corta todo: ni conexiones ni consultas nuevas', () async {
      arrancar(cel);
      await esperar(() => cel.servicio.escuchando, que: 'conectar');
      cel.servicio.detener();
      expect(cel.servicio.escuchando, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final consultas = servidor.consultas;
      final conexiones = servidor.conexiones;
      servidor.cortarAvisos();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(servidor.consultas, consultas);
      expect(servidor.conexiones, conexiones);
    });
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

// Revisión de blindaje (2026-10-04) del servidor que la PC le ofrece al celular por el wifi del local.
//
// Escucha en toda la red (`0.0.0.0`) y `/ping`, `/emparejar` y `/companion/apk` no piden llave, así que:
//  * un cuerpo con la forma equivocada es un 400 (antes: 500 y un renglón de stack trace en un log sin tope);
//  * un cuerpo desmedido se corta sin leerlo;
//  * el log de errores no crece sin límite;
//  * el cobro con la Point es idempotente de punta a punta (confirmar dos veces = una sola venta) y sobrevive a un corte de red.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_cobro.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/data/repositorio_ticket.dart' show configurarMpAccessToken, configurarMpTerminalCobroId;
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/venta.dart';
import 'package:la_plazoleta/domain/venta_json.dart';
import 'package:la_plazoleta/servidor/servidor_companion.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../helpers/base_para_tests.dart';

class _Documentos extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  _Documentos(this.carpeta);
  final String carpeta;

  @override
  Future<String?> getApplicationDocumentsPath() async => carpeta;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late AppDatabase db;
  late int puerto;
  late String token;
  late int usuarioId;
  late int sesionId;
  late Directory documentos;

  Uri url(String path, [int? p]) => Uri.parse('http://127.0.0.1:${p ?? puerto}$path');
  Map<String, String> headers({bool conToken = true}) => {
        'content-type': 'application/json',
        if (conToken) encabezadoToken: token,
      };

  Future<int> arrancar({http.Client? mock}) async {
    final server = await iniciarServidorCompanion(db, puerto: 0, httpClientDePrueba: mock);
    addTearDown(server.close);
    return server.port;
  }

  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'la_plazoleta',
      packageName: 'com.example.la_plazoleta',
      version: '1.0.0',
      buildNumber: '2',
      buildSignature: '',
    );
    documentos = await Directory.systemTemp.createTemp('blindaje_servidor_');
    addTearDown(() => documentos.delete(recursive: true));
    PathProviderPlatform.instance = _Documentos(documentos.path);
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    token = await regenerarTokenCompanion(db);
    puerto = await arrancar();
  });
  tearDown(() => db.close());

  group('cuerpos con la forma equivocada: 400, nunca 500', () {
    test('/emparejar (sin llave) con un arreglo, un texto, un código que no es texto o JSON roto', () async {
      for (final cuerpo in ['[]', '"hola"', '{"codigo": 123456}', '{"codigo": null}', '{no es json', '']) {
        final r = await http.post(url('/emparejar'), headers: headers(conToken: false), body: cuerpo);
        expect(r.statusCode, 400, reason: 'cuerpo ${jsonEncode(cuerpo)} → ${r.statusCode} ${r.body}');
      }
    });

    test('una ruta con llave con un arreglo, o un campo de otro tipo, también', () async {
      for (final cuerpo in ['[]', '"hola"', '{"lineas": "no es una lista", "medio": "efectivo"}', '{"lineas": [1, 2], "medio": 5}']) {
        final r = await http.post(url('/ventas/calcular'), headers: headers(), body: cuerpo);
        expect(r.statusCode, 400, reason: 'cuerpo ${jsonEncode(cuerpo)} → ${r.statusCode} ${r.body}');
      }
    });

    test('el 400 no se confunde con un error de verdad: un 500 de verdad sigue siendo 500', () async {
      // Una ruta con un id que no es número: FormatException → 400 también (no cambió).
      final r = await http.get(url('/ventas/xyz/detalle'), headers: headers());
      expect(r.statusCode, 400);
    });
  });

  group('cuerpos desmedidos', () {
    test('las rutas sin llave aceptan muy poco (2 KB), con o sin Content-Length', () async {
      final grande = jsonEncode({'codigo': '1' * 3000});
      final r = await http.post(url('/emparejar'), headers: headers(conToken: false), body: grande);
      expect(r.statusCode, 413);

      // Chunked: sin Content-Length. Se corta al pasarse, igual.
      final cliente = HttpClient();
      addTearDown(cliente.close);
      final pedido = await cliente.postUrl(url('/emparejar'));
      pedido.headers.contentType = ContentType.json;
      pedido.headers.chunkedTransferEncoding = true;
      pedido.add(utf8.encode(jsonEncode({'codigo': '1' * 3000})));
      final respuesta = await pedido.close();
      expect(respuesta.statusCode, 413);
      await respuesta.drain<void>();
    });

    test('las rutas con llave aceptan mucho más, pero no cualquier cosa', () async {
      final original = maximoCuerpoPedido;
      maximoCuerpoPedido = 10 * 1024;
      addTearDown(() => maximoCuerpoPedido = original);
      expect(original, 20 * 1024 * 1024, reason: 'el tope real no cambió');
      final r = await http.post(url('/ventas/calcular'), headers: headers(), body: jsonEncode({'relleno': 'x' * 20000}));
      expect(r.statusCode, 413);
      final ok = await http.post(url('/ventas/calcular'), headers: headers(), body: jsonEncode({'lineas': [], 'medio': 'efectivo'}));
      expect(ok.statusCode, isNot(413));
    });
  });

  group('log de errores acotado', () {
    test('pasado 1 MB se renombra a .1 y se empieza de nuevo', () async {
      final log = File('${documentos.path}/companion_errores.log');
      await log.writeAsString('x' * (tamanioMaximoLogErrores + 10));
      // Un TypeError anota (y responde 400).
      final r = await http.post(url('/emparejar'), headers: headers(conToken: false), body: '[]');
      expect(r.statusCode, 400);
      expect(File('${log.path}.1').existsSync(), isTrue);
      expect(log.lengthSync(), lessThan(tamanioMaximoLogErrores));
      expect(log.readAsStringSync(), contains('/emparejar'));
    });
  });

  group('cobro con la Point', () {
    Future<int> insertarCoca() => db.into(db.productos).insert(
          ProductosCompanion.insert(nombre: 'Coca-Cola 500ml', precioCentavos: const Value(112000), stock: const Value(20)),
        );
    Map<String, dynamic> linea(int id) => lineaVentaAJson(
          LineaVentaPorUnidad(
            productoId: '$id',
            nombreProducto: 'Coca-Cola 500ml',
            proveedorId: null,
            cantidad: 1,
            precioUnitarioCentavos: 112000,
            costoUnitarioCentavos: 80000,
          ),
        );

    test('confirmar dos veces (el celular no recibió la respuesta) devuelve la MISMA venta: una sola entrada en la caja', () async {
      await configurarMpAccessToken(db, 'TOKEN123');
      await configurarMpTerminalCobroId(db, 'N950NCC503383252');
      final cocaId = await insertarCoca();
      final mock = MockClient((r) async => http.Response(jsonEncode({'id': 'orden-mp-1', 'status': 'created'}), 201));
      final p = await arrancar(mock: mock);

      final iniciado = await http.post(
        url('/ventas/posnet/iniciar', p),
        headers: headers(),
        body: jsonEncode({'lineas': [linea(cocaId)], 'canal': 'qr', 'sesionCajaId': sesionId}),
      );
      expect(iniciado.statusCode, 201);
      final ordenPendienteId = (jsonDecode(iniciado.body) as Map)['ordenPendienteId'];
      final cuerpo = jsonEncode({'lineas': [linea(cocaId)], 'canal': 'qr', 'sesionCajaId': sesionId, 'usuarioId': usuarioId, 'ordenPendienteId': ordenPendienteId});

      final a = await http.post(url('/ventas/posnet/confirmar', p), headers: headers(), body: cuerpo);
      final b = await http.post(url('/ventas/posnet/confirmar', p), headers: headers(), body: cuerpo);

      expect(a.statusCode, 201);
      expect(b.statusCode, 201);
      expect((jsonDecode(b.body) as Map)['ventaId'], (jsonDecode(a.body) as Map)['ventaId']);
      expect(await db.select(db.ventas).get(), hasLength(1));
      final coca = await (db.select(db.productos)..where((x) => x.id.equals(cocaId))).getSingle();
      expect(coca.stock, 19, reason: 'el stock bajó una sola vez');
    });

    test('confirmar sin ordenPendienteId, o con una que no existe, no graba ninguna venta', () async {
      final cocaId = await insertarCoca();
      final base = {'lineas': [linea(cocaId)], 'canal': 'qr', 'sesionCajaId': sesionId, 'usuarioId': usuarioId};
      expect((await http.post(url('/ventas/posnet/confirmar'), headers: headers(), body: jsonEncode(base))).statusCode, 400);
      expect((await http.post(url('/ventas/posnet/confirmar'), headers: headers(), body: jsonEncode({...base, 'ordenPendienteId': 4242}))).statusCode, 400);
      expect(await db.select(db.ventas).get(), isEmpty);
    });

    test('no-aprobado: solo "rechazada" o "cancelada", y nunca sobre una orden que ya terminó en una venta', () async {
      final pendiente = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'qr', montoCentavos: 112000);
      Future<http.Response> cerrar(Object id, String estado) =>
          http.post(url('/ventas/posnet/no-aprobado'), headers: headers(), body: jsonEncode({'ordenPendienteId': id, 'estado': estado}));

      expect((await cerrar(pendiente.id, 'aprobada')).statusCode, 400, reason: 'aprobada la escribe /confirmar junto con la venta');
      expect((await cerrar(pendiente.id, 'cualquier cosa')).statusCode, 400);
      expect((await cerrar(9999, 'rechazada')).statusCode, 404);
      var orden = await (db.select(db.ordenesCobroPendientes)..where((o) => o.id.equals(pendiente.id))).getSingle();
      expect(orden.estado, 'pendiente');

      final ventaId = await db.into(db.ventas).insert(
            VentasCompanion.insert(sesionCajaId: sesionId, usuarioId: usuarioId, subtotalCentavos: 112000, totalCentavos: 112000),
          );
      await marcarOrdenResuelta(db, id: pendiente.id, estado: 'aprobada', ventaId: ventaId);
      expect((await cerrar(pendiente.id, 'rechazada')).statusCode, 409, reason: 'ese cobro está hecho');
      orden = await (db.select(db.ordenesCobroPendientes)..where((o) => o.id.equals(pendiente.id))).getSingle();
      expect(orden.estado, 'aprobada');

      final otra = await crearOrdenPendiente(db, sesionCajaId: sesionId, canal: 'debit_card', montoCentavos: 5000);
      expect((await cerrar(otra.id, 'rechazada')).statusCode, 200);
    });

    test('iniciar con la red caída: 502 con mensaje; el reintento reutiliza la orden (misma clave) y no crea otra', () async {
      await configurarMpAccessToken(db, 'TOKEN123');
      await configurarMpTerminalCobroId(db, 'N950NCC503383252');
      final cocaId = await insertarCoca();
      final claves = <String?>[];
      var caida = true;
      final mock = MockClient((r) async {
        claves.add(r.headers['X-Idempotency-Key']);
        if (caida) throw const SocketException('Network is unreachable');
        return http.Response(jsonEncode({'id': 'orden-mp-7', 'status': 'created'}), 201);
      });
      final p = await arrancar(mock: mock);
      final pedido = jsonEncode({'lineas': [linea(cocaId)], 'canal': 'qr', 'sesionCajaId': sesionId});

      final falla = await http.post(url('/ventas/posnet/iniciar', p), headers: headers(), body: pedido);
      expect(falla.statusCode, 502);
      expect((jsonDecode(falla.body) as Map)['error'], contains('conexión'));

      caida = false;
      final ok = await http.post(url('/ventas/posnet/iniciar', p), headers: headers(), body: pedido);
      expect(ok.statusCode, 201);
      expect(claves, hasLength(2));
      expect(claves[1], claves[0], reason: 'misma clave: Mercado Pago devuelve la misma orden');
      expect(await db.select(db.ordenesCobroPendientes).get(), hasLength(1));
    });

    test('un id de orden con ../ en /estado no llega a Mercado Pago', () async {
      await configurarMpAccessToken(db, 'TOKEN123');
      var llamadas = 0;
      final mock = MockClient((r) async {
        llamadas++;
        return http.Response(jsonEncode({'status': 'processed'}), 200);
      });
      final p = await arrancar(mock: mock);
      final r = await http.get(Uri.parse('http://127.0.0.1:$p/ventas/posnet/estado/..%2F..%2Fusers%2Fme'), headers: headers());
      expect(r.statusCode, 502);
      expect(llamadas, 0);
    });
  });

  group('cobrar una deuda dos veces', () {
    test('la segunda da 409 y no registra otro cobro', () async {
      final id = await db.into(db.pendientes).insert(
            PendientesCompanion.insert(tipo: 'FIADO', usuarioId: usuarioId, montoCentavos: const Value(5000), nombreLibre: const Value('Doña Rosa')),
          );
      final cuerpo = jsonEncode({'usuarioId': usuarioId, 'sesionCajaId': sesionId, 'efectivo': true});
      final a = await http.post(url('/deudas/$id/cobrar'), headers: headers(), body: cuerpo);
      final b = await http.post(url('/deudas/$id/cobrar'), headers: headers(), body: cuerpo);
      expect(a.statusCode, 200);
      expect(b.statusCode, 409);
      expect(await db.select(db.ventas).get(), hasLength(1));
    });
  });
}

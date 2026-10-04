import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_arqueo_intermedio.dart';
import 'package:la_plazoleta/data/repositorio_respaldo.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/servicios/copias_nube.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import 'package:la_plazoleta/servicios/nube.dart';
import 'package:la_plazoleta/ui/cierre/cierre_controlador.dart';
import '../../helpers/base_para_tests.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late int usuarioId;
  late int sesionId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    sesionId = await abrirSesion(
      db,
      usuarioId: usuarioId,
      fondoInicialCentavos: 100000,
    );
  });
  tearDown(() => db.close());

  group('punto crítico: oculto hasta confirmar (Regla 1 y 2)', () {
    test('arranca en fase de conteo, sin resumen', () async {
      final c = CierreControlador(db, sesionId: sesionId);
      await c.cargar();
      expect(c.fase, FaseCierre.conteo);
      expect(c.resumen, isNull);
    });

    test('confirmar sin escribir nada: error, sigue en conteo, sin resumen', () async {
      final c = CierreControlador(db, sesionId: sesionId);
      await c.cargar();
      await c.confirmarConteo();
      expect(c.fase, FaseCierre.conteo);
      expect(c.resumen, isNull);
      expect(c.error, isNotNull);
    });

    test('confirmar con un monto: recién ahí aparece el resumen', () async {
      final c = CierreControlador(db, sesionId: sesionId);
      await c.cargar();
      c.efectivoContadoCtrl.text = '1.000';
      await c.confirmarConteo();

      expect(c.fase, FaseCierre.revisado);
      expect(c.resumen, isNotNull);
      // esperada = 100000 (fondo) + 0 + 0 = 100000; contado 100000 (=$1.000)
      expect(c.resumen!.efectivoEsperadoCentavos, 100000);
      expect(c.resumen!.diferenciaCentavos, 0);
    });
  });

  group('corrección en vivo después de revelar (punto crítico #4)', () {
    test('cambiar el monto contado después de confirmar recalcula sin re-ocultar', () async {
      final c = CierreControlador(db, sesionId: sesionId);
      await c.cargar();
      c.efectivoContadoCtrl.text = '1.000';
      await c.confirmarConteo();
      expect(c.resumen!.diferenciaCentavos, 0);

      c.efectivoContadoCtrl.text = '1.200';
      // el listener del controller dispara la recarga async; se espera un tick
      await Future<void>.delayed(Duration.zero);

      expect(c.fase, FaseCierre.revisado); // no vuelve a taparse
      expect(c.resumen!.diferenciaCentavos, 20000); // contado 120000 - esperado 100000
    });

    test('corregir antes de confirmar no hace nada (sigue oculto)', () async {
      final c = CierreControlador(db, sesionId: sesionId);
      await c.cargar();
      c.efectivoContadoCtrl.text = '500';
      await Future<void>.delayed(Duration.zero);
      expect(c.fase, FaseCierre.conteo);
      expect(c.resumen, isNull);
    });
  });

  group('cerrar', () {
    test('cierra la sesión y guarda lo que ya se había calculado', () async {
      final c = CierreControlador(db, sesionId: sesionId);
      await c.cargar();
      c.efectivoContadoCtrl.text = '1.000';
      await c.confirmarConteo();
      c.mpContadoCtrl.text = '250';
      c.lataContadoCtrl.text = '0';

      final ok = await c.cerrar(usuarioId: usuarioId);

      expect(ok, true);
      expect(c.fase, FaseCierre.cerrado);

      final sesion = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).getSingle();
      expect(sesion.estado, 'CERRADA');
      expect(sesion.efectivoContadoCentavos, 100000);
      expect(sesion.mpContadoCentavos, 25000);
    });

    test('no cierra si falta el saldo de Mercado Pago', () async {
      final c = CierreControlador(db, sesionId: sesionId);
      await c.cargar();
      c.efectivoContadoCtrl.text = '1.000';
      await c.confirmarConteo();
      // mpContadoCtrl queda vacío

      final ok = await c.cerrar(usuarioId: usuarioId);
      expect(ok, false);
      expect(c.fase, FaseCierre.revisado);
    });

    test('con la PC vinculada a la cuenta, cerrar sube una copia a la nube sin frenar el cierre', () async {
      final tmp = await Directory.systemTemp.createTemp('nube_cierre_test_');
      addTearDown(() => tmp.delete(recursive: true));
      final almacen = AlmacenCuentaEnMemoria();
      await almacen.guardar(const CuentaVinculada(token: 't1', email: 'a@b.com', idDispositivo: 'dev-123', nombreDispositivo: 'Caja', vence: 1));
      final subidas = <String>[];
      final cliente = ClienteNube(http: MockClient((r) async {
        subidas.add('${r.method} ${r.url.path}');
        return http.Response('{"ok":true,"id":1,"createdAt":1,"guardadas":1}', 200);
      }));
      nubeApp = NubeApp(
        almacen: almacen,
        cliente: cliente,
        copias: ServicioCopiasNube(db: db, almacen: almacen, cliente: cliente, carpetaTemporal: tmp, versionApp: () async => '1.0.0'),
        idDispositivo: () async => 'dev-123',
        nombreDispositivo: () => 'Caja',
        abrirNavegador: (_) async {},
        carpetaTemporal: tmp,
      );
      addTearDown(() => nubeApp = null);

      final c = CierreControlador(db, sesionId: sesionId);
      await c.cargar();
      c.efectivoContadoCtrl.text = '1.000';
      await c.confirmarConteo();
      c.mpContadoCtrl.text = '250';
      c.lataContadoCtrl.text = '0';
      expect(await c.cerrar(usuarioId: usuarioId), true);
      await Future<void>.delayed(const Duration(milliseconds: 500)); // la subida sale en segundo plano

      expect(subidas, ['PUT /api/backup']);
      expect(nubeApp!.ultimoResultado, isA<SubidaOk>());
    });

    test('si la subida a la nube falla, el cierre igual queda hecho', () async {
      final tmp = await Directory.systemTemp.createTemp('nube_cierre_test_');
      addTearDown(() => tmp.delete(recursive: true));
      final almacen = AlmacenCuentaEnMemoria();
      await almacen.guardar(const CuentaVinculada(token: 't1', email: 'a@b.com', idDispositivo: 'dev-123', nombreDispositivo: 'Caja', vence: 1));
      final cliente = ClienteNube(http: MockClient((r) async => throw const SocketException('sin red')));
      nubeApp = NubeApp(
        almacen: almacen,
        cliente: cliente,
        copias: ServicioCopiasNube(db: db, almacen: almacen, cliente: cliente, carpetaTemporal: tmp, versionApp: () async => '1.0.0'),
        idDispositivo: () async => 'dev-123',
        nombreDispositivo: () => 'Caja',
        abrirNavegador: (_) async {},
        carpetaTemporal: tmp,
      );
      addTearDown(() => nubeApp = null);

      final c = CierreControlador(db, sesionId: sesionId);
      await c.cargar();
      c.efectivoContadoCtrl.text = '1.000';
      await c.confirmarConteo();
      c.mpContadoCtrl.text = '250';
      c.lataContadoCtrl.text = '0';
      expect(await c.cerrar(usuarioId: usuarioId), true);
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(c.fase, FaseCierre.cerrado);
      expect(nubeApp!.ultimoResultado, isA<SubidaFallida>());
    });

    test('sin carpeta de respaldo configurada, cierra igual y sin avisar nada (fase 10)', () async {
      final c = CierreControlador(db, sesionId: sesionId);
      await c.cargar();
      c.efectivoContadoCtrl.text = '1.000';
      await c.confirmarConteo();
      c.mpContadoCtrl.text = '250';
      c.lataContadoCtrl.text = '0';

      final ok = await c.cerrar(usuarioId: usuarioId);

      expect(ok, true);
      expect(c.ultimoRespaldoError, isNull);
    });

    test('con carpeta configurada, cerrar deja un respaldo real hecho (fase 10)', () async {
      final carpeta = await Directory.systemTemp.createTemp('respaldo_cierre_test_');
      addTearDown(() => carpeta.delete(recursive: true));
      await configurarCarpetaRespaldo(db, carpeta.path);

      final c = CierreControlador(db, sesionId: sesionId);
      await c.cargar();
      c.efectivoContadoCtrl.text = '1.000';
      await c.confirmarConteo();
      c.mpContadoCtrl.text = '250';
      c.lataContadoCtrl.text = '0';

      await c.cerrar(usuarioId: usuarioId);

      expect(c.ultimoRespaldoError, isNull);
      expect(await listarRespaldos(db), hasLength(1));
    });
  });

  group('reabrir (Regla 6)', () {
    test('reabre y vuelve a la fase de conteo', () async {
      final c = CierreControlador(db, sesionId: sesionId);
      await c.cargar();
      c.efectivoContadoCtrl.text = '1.000';
      await c.confirmarConteo();
      c.mpContadoCtrl.text = '0';
      c.lataContadoCtrl.text = '0';
      await c.cerrar(usuarioId: usuarioId);
      expect(c.puedeReabrir, true);

      final ok = await c.reabrir();

      expect(ok, true);
      expect(c.fase, FaseCierre.conteo);
      expect(c.resumen, isNull);
      final sesion = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).getSingle();
      expect(sesion.estado, 'ABIERTA');
    });

    test('no permite reabrir si ya se abrió una sesión nueva', () async {
      final c = CierreControlador(db, sesionId: sesionId);
      await c.cargar();
      c.efectivoContadoCtrl.text = '1.000';
      await c.confirmarConteo();
      c.mpContadoCtrl.text = '0';
      c.lataContadoCtrl.text = '0';
      await c.cerrar(usuarioId: usuarioId);

      await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

      final ok = await c.reabrir();
      expect(ok, false);
    });
  });

  group('cargar sobre una sesión ya cerrada', () {
    test('entra directo en fase cerrado, con el resumen ya calculado', () async {
      final c1 = CierreControlador(db, sesionId: sesionId);
      await c1.cargar();
      c1.efectivoContadoCtrl.text = '1.000';
      await c1.confirmarConteo();
      c1.mpContadoCtrl.text = '0';
      c1.lataContadoCtrl.text = '0';
      await c1.cerrar(usuarioId: usuarioId);

      final c2 = CierreControlador(db, sesionId: sesionId);
      await c2.cargar();

      expect(c2.fase, FaseCierre.cerrado);
      expect(c2.resumen, isNotNull);
      expect(c2.resumen!.diferenciaCentavos, 0);
      expect(c2.puedeReabrir, true);
    });
  });

  group('arqueos del turno (opcionales, Dueño 2026-09-28)', () {
    test('sin arqueos, el conteo arranca vacío', () async {
      final c = CierreControlador(db, sesionId: sesionId);
      await c.cargar();
      expect(c.efectivoContadoCtrl.text, isEmpty);
      expect(c.precargadoDe, isNull);
      expect(c.arqueos, isEmpty);
    });

    test('precarga efectivo y MP del último arqueo, nunca la lata, sin revelar nada', () async {
      await registrarArqueoIntermedio(db, sesionId: sesionId, usuarioId: usuarioId, efectivoContadoCentavos: 150000, mpContadoCentavos: 0, lataContadoCentavos: 0);
      await registrarArqueoIntermedio(db, sesionId: sesionId, usuarioId: usuarioId, efectivoContadoCentavos: 320000, mpContadoCentavos: 45000, lataContadoCentavos: 10000);

      final c = CierreControlador(db, sesionId: sesionId);
      await c.cargar();

      expect(c.efectivoContadoCtrl.text, '3.200');
      expect(c.mpContadoCtrl.text, '450');
      expect(c.lataContadoCtrl.text, isEmpty);
      expect(c.precargadoDe?.efectivoContadoCentavos, 320000);
      expect(c.arqueos, hasLength(2));
      // Precargar no es revelar: sigue en conteo, sin diferencia a la vista.
      expect(c.fase, FaseCierre.conteo);
      expect(c.resumen, isNull);
    });

    test(
      'si después del arqueo entró plata por MP, MP arranca vacío y el efectivo se precarga igual (El dueño, '
      '2026-10-04: el cierre arrastró el MP de las 19:20)',
      () async {
        await registrarArqueoIntermedio(db, sesionId: sesionId, usuarioId: usuarioId, efectivoContadoCentavos: 320000, mpContadoCentavos: 45000, lataContadoCentavos: 0);
        final arqueo = (await arqueosDelTurno(db, sesionId)).single;
        final medioMpId = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle()).id;
        final ventaId = await db.into(db.ventas).insert(
          VentasCompanion.insert(
            sesionCajaId: sesionId,
            usuarioId: usuarioId,
            subtotalCentavos: 8194000,
            totalCentavos: 8194000,
            fecha: Value(arqueo.fecha.add(const Duration(minutes: 80))),
          ),
        );
        await db.into(db.pagos).insert(PagosCompanion.insert(ventaId: ventaId, medioPagoId: medioMpId, montoCentavos: 8194000));

        final c = CierreControlador(db, sesionId: sesionId);
        await c.cargar();

        expect(c.efectivoContadoCtrl.text, '3.200');
        expect(c.efectivoPrecargado, isTrue);
        expect(c.mpContadoCtrl.text, isEmpty);
        expect(c.mpPrecargado, isFalse);
      },
    );
  });
}

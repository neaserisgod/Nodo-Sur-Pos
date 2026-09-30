import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/ui/impresion/impresion_controlador.dart';
import '../../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db
        .into(db.usuarios)
        .insert(UsuariosCompanion.insert(nombre: 'Bruno'));
    sesionId = await db
        .into(db.sesionesDeCaja)
        .insert(
          SesionesDeCajaCompanion.insert(
            usuarioAbrioId: usuarioId,
            fondoInicialCentavos: 0,
          ),
        );
  });
  tearDown(() => db.close());

  test('cargarTodo trae la configuración y las últimas ventas', () async {
    final c = ImpresionControlador(db);
    await c.cargarTodo();

    expect(c.mpAccessToken, isNull);
    expect(c.mpTerminalId, isNull);
    expect(c.posnetConfigurado, isFalse);
    expect(c.cargando, isFalse);
  });

  test(
    'guardarAccessToken y guardarTerminalId persisten y quedan reflejados',
    () async {
      final c = ImpresionControlador(db);
      await c.cargarTodo();

      await c.guardarAccessToken('TOKEN-1');
      await c.guardarTerminalId('TERM-1');

      expect(c.mpAccessToken, 'TOKEN-1');
      expect(c.mpTerminalId, 'TERM-1');
      expect(c.posnetConfigurado, isTrue);
    },
  );

  test(
    'guardarTerminalCobroId persiste aparte de la terminal que imprime (fase 12)',
    () async {
      final c = ImpresionControlador(db);
      await c.cargarTodo();

      await c.guardarTerminalId('TERM-IMPRIME');
      await c.guardarTerminalCobroId('TERM-COBRA');

      expect(c.mpTerminalId, 'TERM-IMPRIME');
      expect(c.mpTerminalCobroId, 'TERM-COBRA');
    },
  );

  test(
    'ticketDePrueba sin configurar el posnet deja un mensaje de error claro',
    () async {
      final c = ImpresionControlador(db);
      await c.cargarTodo();

      await c.ticketDePrueba();

      expect(c.mensaje, contains('Falta configurar'));
      expect(c.procesando, isFalse);
    },
  );

  test(
    'ticketDePrueba con posnet configurado manda el POST correcto',
    () async {
      http.Request? capturada;
      final client = MockClient((request) async {
        capturada = request;
        return http.Response('{}', 200);
      });

      final c = ImpresionControlador(db, httpClientDePrueba: client);
      await c.cargarTodo();
      await c.guardarAccessToken('TOKEN-1');
      await c.guardarTerminalId('TERM-1');

      await c.ticketDePrueba();

      expect(c.mensaje, contains('enviado'));
      expect(capturada, isNotNull);
      expect(capturada!.headers['Authorization'], 'Bearer TOKEN-1');
    },
  );

  test('reimprimirEnPosnet arma el ticket real de la venta indicada', () async {
    final ventaId = await db
        .into(db.ventas)
        .insert(
          VentasCompanion.insert(
            sesionCajaId: sesionId,
            usuarioId: usuarioId,
            subtotalCentavos: 5000,
            totalCentavos: 5000,
          ),
        );
    http.Request? capturada;
    final client = MockClient((request) async {
      capturada = request;
      return http.Response('{}', 200);
    });

    final c = ImpresionControlador(db, httpClientDePrueba: client);
    await c.cargarTodo();
    await c.guardarAccessToken('TOKEN-1');
    await c.guardarTerminalId('TERM-1');

    await c.reimprimirEnPosnet(ventaId);

    expect(c.mensaje, contains('Enviado'));
    expect(capturada!.body, contains('La Plazoleta'));
  });

  test(
    'guardarPdf sin carpeta configurada deja un mensaje de error claro',
    () async {
      final ventaId = await db
          .into(db.ventas)
          .insert(
            VentasCompanion.insert(
              sesionCajaId: sesionId,
              usuarioId: usuarioId,
              subtotalCentavos: 1000,
              totalCentavos: 1000,
            ),
          );
      final c = ImpresionControlador(db);
      await c.cargarTodo();

      await c.guardarPdf(ventaId);

      expect(c.mensaje, contains('Falta configurar'));
    },
  );

  test('guardarPdf con carpeta configurada escribe el archivo real', () async {
    final carpeta = await Directory.systemTemp.createTemp(
      'impresion_controlador_test_',
    );
    addTearDown(() => carpeta.delete(recursive: true));
    final ventaId = await db
        .into(db.ventas)
        .insert(
          VentasCompanion.insert(
            sesionCajaId: sesionId,
            usuarioId: usuarioId,
            subtotalCentavos: 1000,
            totalCentavos: 1000,
          ),
        );

    final c = ImpresionControlador(db);
    await c.cargarTodo();
    await c.guardarCarpetaTickets(carpeta.path);

    await c.guardarPdf(ventaId);

    expect(c.mensaje, contains('Guardado en'));
    expect(Directory(carpeta.path).listSync(), isNotEmpty);
  });

  group('buscar', () {
    test('filtra por número de venta', () async {
      final ventaId = await db
          .into(db.ventas)
          .insert(
            VentasCompanion.insert(
              sesionCajaId: sesionId,
              usuarioId: usuarioId,
              subtotalCentavos: 1000,
              totalCentavos: 1000,
            ),
          );
      final c = ImpresionControlador(db);
      await c.cargarTodo();

      await c.buscar(numero: ventaId);

      expect(c.resultados.map((v) => v.id), [ventaId]);
    });
  });
}

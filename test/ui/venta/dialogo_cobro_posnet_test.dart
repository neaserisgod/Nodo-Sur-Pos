// Cubre los cuatro desenlaces del diálogo de cobro por Point (fase 12):
// aprobado, rechazado, cancelado y timeout — más el caso de falta de
// configuración (fase "error"). Nunca golpea la red real: siempre
// `MockClient`. El polling usa `Future.delayed`, que en un test widget
// corre sobre el reloj falso — se avanza a mano con `tester.pump(duration)`,
// nunca con `pumpAndSettle()` (el `CircularProgressIndicator` es una
// animación indefinida que nunca "asienta", mismo gotcha que el
// `Timer.periodic` de tema automático documentado en TRAMPAS.md).

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ticket.dart'
    show configurarMpAccessToken, configurarMpTerminalCobroId;
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:la_plazoleta/ui/venta/dialogo_cobro_posnet.dart';
import 'package:la_plazoleta/ui/venta/venta_controlador.dart';
import '../../helpers/base_para_tests.dart';

Future<VentaControlador> _controladorConCocaCola(
  AppDatabase db, {
  http.Client? client,
  bool configurarTerminal = true,
}) async {
  final usuarioId = await db
      .into(db.usuarios)
      .insert(UsuariosCompanion.insert(nombre: 'Bruno'));
  await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
  final idCoca = await db
      .into(db.productos)
      .insert(
        ProductosCompanion.insert(
          nombre: 'Coca-Cola 500ml',
          precioCentavos: const Value(112000),
          stock: const Value(20),
        ),
      );
  if (configurarTerminal) {
    await configurarMpAccessToken(db, 'TOKEN123');
    await configurarMpTerminalCobroId(db, 'N950NCC503383252');
  }
  final controlador = VentaControlador(db, httpClientDePrueba: client);
  await controlador.cargarTodo();
  final coca = await (db.select(
    db.productos,
  )..where((p) => p.id.equals(idCoca))).getSingle();
  controlador.agregarProducto(coca);
  controlador.elegirCanalDirecto('qr');
  return controlador;
}

Future<void> _abrir(WidgetTester tester, VentaControlador controlador) async {
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaPlazoleta.oscuro,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () =>
              mostrarDialogoCobroPosnet(context, controlador: controlador),
          child: const Text('Abrir'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pump(); // abre el diálogo, initState dispara _iniciar()
  await tester.pump(); // resuelve el POST (mock, sin timers) -> fase esperando
}

MockClient _clienteConEstado(String estado) {
  return MockClient((request) async {
    if (request.method == 'POST') {
      return http.Response(
        jsonEncode({'id': 'orden-mp-1', 'status': 'created'}),
        201,
      );
    }
    return http.Response(
      jsonEncode({'id': 'orden-mp-1', 'status': estado}),
      200,
    );
  });
}

void main() {
  late AppDatabase db;

  setUp(() => db = baseDeTest());
  tearDown(() => db.close());

  testWidgets('aprobado: graba la venta y muestra "Listo"', (tester) async {
    final controlador = await _controladorConCocaCola(
      db,
      client: _clienteConEstado('processed'),
    );
    await _abrir(tester, controlador);

    await tester.pump(const Duration(seconds: 2)); // primer poll: aprobado
    await tester
        .pump(); // flush de confirmarCobroPosnetAprobado (grabar la venta)

    expect(find.textContaining('Pago aprobado'), findsOneWidget);
    expect(find.text('Listo'), findsOneWidget);
    expect(controlador.carrito, isEmpty); // cobrarActual ya vació el carrito

    controlador.dispose();
  });

  testWidgets('rechazado: ofrece cobrar a mano o reintentar', (tester) async {
    final controlador = await _controladorConCocaCola(
      db,
      client: _clienteConEstado('failed'),
    );
    await _abrir(tester, controlador);

    await tester.pump(const Duration(seconds: 2)); // primer poll: rechazado

    expect(find.text('El pago no se aprobó en la terminal.'), findsOneWidget);
    expect(find.text('Cobrar a mano'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);

    controlador.dispose();
  });

  testWidgets('timeout: no asume nada, deja la orden pendiente', (
    tester,
  ) async {
    final controlador = await _controladorConCocaCola(
      db,
      client: _clienteConEstado('created'),
    );
    await _abrir(tester, controlador);

    // 30 intentos x 2s = 60s: el timeout completo (ver `_pollear`, cuenta
    // intentos, no compara contra un reloj de pared).
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(seconds: 2));
    }
    await tester.pump();

    expect(
      find.text('No se pudo confirmar el pago a tiempo. Revisá la terminal.'),
      findsOneWidget,
    );
    final orden = await db.select(db.ordenesCobroPendientes).getSingle();
    expect(orden.estado, 'pendiente'); // nunca se asume rechazada ni cancelada

    controlador.dispose();
  });

  testWidgets(
    'cancelar avisa a Mercado Pago (POST .../cancel) antes de cerrar',
    (tester) async {
      // Bug real (Bruno: "cuando cancelo el QR no cancela el
      // dispositivo") — "Cancelar" tiene que mandar el POST de
      // cancelación, no solo actualizar la fila local.
      final pedidosDeCancelacion = <Uri>[];
      final client = MockClient((request) async {
        if (request.method == 'POST' && request.url.path.endsWith('/cancel')) {
          pedidosDeCancelacion.add(request.url);
          return http.Response('{}', 200);
        }
        return http.Response(
          jsonEncode({'id': 'orden-mp-1', 'status': 'created'}),
          201,
        );
      });
      final controlador = await _controladorConCocaCola(db, client: client);
      await _abrir(tester, controlador);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pump();

      expect(pedidosDeCancelacion, hasLength(1));
      expect(pedidosDeCancelacion.single.path, '/v1/orders/orden-mp-1/cancel');

      final orden = await db.select(db.ordenesCobroPendientes).getSingle();
      expect(orden.estado, 'cancelada');
      expect(
        controlador.carrito,
        hasLength(1),
      ); // cancelar no toca la venta en curso

      // El `Future.delayed(2s)` del loop de polling en curso sigue vivo (el
      // cancel es un flag propio, `_cancelado`, no cancela el Timer real) —
      // se lo deja disparar e ignorarse solo, para no terminar el test con
      // un timer pendiente.
      await tester.pump(const Duration(seconds: 2));

      controlador.dispose();
    },
  );

  testWidgets(
    'si la orden ya llegó a la terminal (at_terminal), MP rechaza el cancel y avisa con mensaje claro',
    (tester) async {
      // Caso real, no hipotético (Bruno probó contra el posnet): la orden
      // pasa a `at_terminal` casi al instante de crearse, y desde ahí MP
      // devuelve 409 `cannot_cancel_order` — este es el desenlace más común
      // al tocar "Cancelar", no una excepción rara.
      final client = MockClient((request) async {
        if (request.method == 'POST' && request.url.path.endsWith('/cancel')) {
          return http.Response(
            jsonEncode({
              'errors': [
                {
                  'code': 'cannot_cancel_order',
                  'message':
                      "the order cannot be canceled because the current status, 'at_terminal', doesn't allow cancelation",
                },
              ],
            }),
            409,
          );
        }
        return http.Response(
          jsonEncode({'id': 'orden-mp-1', 'status': 'created'}),
          201,
        );
      });
      final controlador = await _controladorConCocaCola(db, client: client);
      await _abrir(tester, controlador);

      await tester.tap(find.text('Cancelar'));
      await tester.pump();

      expect(
        find.textContaining('No se pudo cancelar automáticamente'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Mercado Pago no permite cancelarla por API'),
        findsOneWidget,
      );
      expect(find.text('Cerrar'), findsOneWidget);
      expect(find.text('Reintentar'), findsNothing);
      expect(find.text('Cobrar a mano'), findsNothing);

      final orden = await db.select(db.ordenesCobroPendientes).getSingle();
      expect(
        orden.estado,
        'pendiente',
      ); // nunca se asume cancelada sin confirmación

      await tester.pump(const Duration(seconds: 2));

      controlador.dispose();
    },
  );

  testWidgets('sin terminal configurada: fase error con "Cobrar a mano"', (
    tester,
  ) async {
    final controlador = await _controladorConCocaCola(
      db,
      configurarTerminal: false,
    );
    await _abrir(tester, controlador);

    expect(
      find.textContaining('Configurá el access token y la terminal de cobro'),
      findsOneWidget,
    );
    expect(find.text('Cobrar a mano'), findsOneWidget);

    await tester.tap(find.text('Cobrar a mano'));
    await tester.pump();

    expect(
      controlador.carrito,
      isEmpty,
    ); // cobrarActual() de todas formas cobró
    controlador.dispose();
  });
}

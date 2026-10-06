// Turnos y Point como módulos: apagados, el botón "Cambiar de turno" no está y QR/Débito se cobran a mano, sin terminal.
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ticket.dart' show configurarMpAccessToken, configurarMpTerminalCobroId;
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/servicios/modulos_activos.dart';
import 'package:la_plazoleta/ui/navegacion/route_observer.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:la_plazoleta/ui/venta/acciones_venta.dart';
import 'package:la_plazoleta/ui/venta/pantalla_venta.dart';
import 'package:la_plazoleta/ui/venta/venta_controlador.dart';
import '../../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = baseDeTest());
  tearDown(() {
    modulosActuales.value = ModulosNegocio.todosActivos;
    return db.close();
  });

  testWidgets('sin el módulo Turnos el menú Caja no tiene turno ni arqueo; "Cerrar caja" sigue', (tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    await tester.pumpWidget(
      MaterialApp(theme: TemaPlazoleta.oscuro, navigatorObservers: [routeObserver], home: PantallaVenta(db: db)),
    );
    await tester.pumpAndSettle();
    // Desde el rediseño v4 el turno y el cierre viven en el menú "Caja ▾".
    await tester.tap(find.byKey(const Key('boton_caja')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu_caja_turno')), findsOneWidget);
    await tester.tapAt(const Offset(5, 5)); // cierra el menú
    await tester.pumpAndSettle();

    modulosActuales.value = ModulosNegocio.todosActivos.conModulo(Modulo.turnos, activo: false);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('boton_caja')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu_caja_turno')), findsNothing);
    expect(find.byKey(const Key('menu_caja_arqueo')), findsNothing);
    expect(find.byKey(const Key('menu_caja_cerrar')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('sin el módulo Point, cobrar con QR graba la venta a mano y no toca la terminal', (tester) async {
    final pedidos = <http.Request>[];
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    final idCoca = await db.into(db.productos).insert(
      ProductosCompanion.insert(nombre: 'Coca-Cola 500ml', precioCentavos: const Value(112000), stock: const Value(20)),
    );
    await configurarMpAccessToken(db, 'TOKEN123');
    await configurarMpTerminalCobroId(db, 'N950NCC503383252');
    final c = VentaControlador(db, httpClientDePrueba: MockClient((r) async {
      pedidos.add(r);
      return http.Response('{}', 500);
    }));
    await c.cargarTodo();
    c.agregarProducto(await (db.select(db.productos)..where((p) => p.id.equals(idCoca))).getSingle());
    c.elegirCanalDirecto('qr');
    modulosActuales.value = ModulosNegocio.todosActivos.conModulo(Modulo.cobroPoint, activo: false);

    await tester.pumpWidget(
      MaterialApp(
        theme: TemaPlazoleta.oscuro,
        home: Builder(builder: (context) => ElevatedButton(onPressed: () => cobrarOAbrirPosnet(context, c), child: const Text('Cobrar'))),
      ),
    );
    await tester.tap(find.text('Cobrar'));
    await tester.pumpAndSettle();

    expect(pedidos, isEmpty);
    expect(await db.select(db.ventas).get(), hasLength(1));
    expect(find.byType(Dialog), findsNothing);
    c.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}

// Etapa D (El dueño, 2026-10-04): la campanita de Venta muestra los avisos de Mercado Pago — cobro sin venta, contracargo,
// reclamo — con "Visto" para sacarlos, y se prende el punto de acento.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_avisos_mp.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/avisos_mp.dart';
import 'package:la_plazoleta/servicios/avisos_mp_servicio.dart';
import 'package:la_plazoleta/servicios/copias_nube.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import 'package:la_plazoleta/servicios/nube.dart';
import 'package:la_plazoleta/ui/navegacion/route_observer.dart';
import 'package:la_plazoleta/ui/tema/iconos.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:la_plazoleta/ui/venta/pantalla_venta.dart';
import '../../helpers/base_para_tests.dart';

Future<void> _abrirVenta(WidgetTester tester, AppDatabase db) async {
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: TemaPlazoleta.oscuro, navigatorObservers: [routeObserver], home: PantallaVenta(db: db)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sin avisos: "Sin novedades"; con un cobro sin venta y un contracargo: se ven, y "Visto" saca cada uno', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    // El I/O real no avanza dentro del reloj falso de testWidgets: va por runAsync.
    final tmp = (await tester.runAsync(() => Directory.systemTemp.createTemp('campanita_')))!;
    addTearDown(() => tmp.deleteSync(recursive: true));
    final almacen = AlmacenCuentaEnMemoria();
    final cliente = ClienteNube(http: MockClient((_) async => http.Response('{}', 404)));
    final servicio = ServicioAvisosMp(db: db, almacen: almacen, cliente: cliente, repaso: const Duration(days: 1));
    nubeApp = NubeApp(
      almacen: almacen,
      cliente: cliente,
      copias: ServicioCopiasNube(db: db, almacen: almacen, cliente: cliente, carpetaTemporal: tmp, versionApp: () async => '1.0.0'),
      avisosMp: servicio,
      idDispositivo: () async => 'dev',
      nombreDispositivo: () => 'Caja',
      abrirNavegador: (_) async {},
      carpetaTemporal: tmp,
    );
    addTearDown(() => nubeApp = null);

    await _abrirVenta(tester, db);
    await tester.tap(find.byIcon(IconosPlazoleta.notificationsOutlined));
    await tester.pumpAndSettle();
    expect(find.text('Sin novedades por ahora.'), findsOneWidget);
    await tester.tap(find.byIcon(IconosPlazoleta.notificationsOutlined));
    await tester.pumpAndSettle();

    final hace = DateTime.now().subtract(const Duration(minutes: 30));
    await tester.runAsync(() async {
      await guardarAvisosMp(db, [
        AvisoMp(idServidor: 1, tipo: TipoAvisoMp.cobro, mpId: '9', pagoId: '9', montoCentavos: 777700, estado: 'approved', fecha: hace, creado: hace),
        AvisoMp(idServidor: 2, tipo: TipoAvisoMp.contracargo, mpId: 'CB1', pagoId: '9', montoCentavos: 500000, estado: 'documentacion', fecha: hace, creado: hace),
      ]);
      await servicio.recalcular();
    });
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(IconosPlazoleta.notificationsOutlined));
    await tester.pumpAndSettle();
    expect(find.textContaining('Entraron \$7.777 a Mercado Pago'), findsOneWidget);
    expect(find.textContaining('Contracargo de'), findsOneWidget);
    expect(find.text('Sin novedades por ahora.'), findsNothing);

    await tester.tap(find.descendant(of: find.byKey(const ValueKey('aviso_mp_1')), matching: find.text('Visto')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Entraron'), findsNothing);
    expect(find.textContaining('Contracargo de'), findsOneWidget);
  });
}

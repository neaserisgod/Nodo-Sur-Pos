// Etapa E (2026-10-04): el botón "Traer saldo de Mercado Pago" del cierre llena el MP contado y muestra las diferencias con un
// botón para cargarlas.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/servicios/copias_nube.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import 'package:la_plazoleta/servicios/nube.dart';
import 'package:la_plazoleta/ui/cierre/pantalla_cierre.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import '../../helpers/base_para_tests.dart';

http.Response _json(Object cuerpo) => http.Response(jsonEncode(cuerpo), 200, headers: {'content-type': 'application/json'});

void main() {
  testWidgets('sin cuenta vinculada no hay botón; con cuenta, trae el saldo, llena el campo y ofrece cargar lo que falta', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
    await db.into(db.productos).insert(ProductosCompanion.insert(nombre: 'Agua', precioCentavos: const Value(1000), stock: const Value(1)));

    Future<void> abrirCierre() async {
      await tester.pumpWidget(const SizedBox()); // estado nuevo: el controlador toma la cuenta que haya en ese momento
      await tester.pumpWidget(MaterialApp(theme: TemaPlazoleta.oscuro, home: PantallaCierre(db: db, sesionId: sesionId, usuarioId: usuarioId)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '0');
      await tester.tap(find.text('Confirmar conteo'));
      await tester.pumpAndSettle();
    }

    await abrirCierre();
    expect(find.byKey(const Key('boton_traer_saldo_mp')), findsNothing, reason: 'sin cuenta de Nodo Sur no hay con qué pedirlo');

    final tmp = (await tester.runAsync(() => Directory.systemTemp.createTemp('cierre_saldo_')))!;
    addTearDown(() => tmp.deleteSync(recursive: true));
    final almacen = AlmacenCuentaEnMemoria();
    await almacen.guardar(const CuentaVinculada(token: 't1', email: 'a@b.com', idDispositivo: 'dev', nombreDispositivo: 'Caja', vence: 1));
    final cliente = ClienteNube(http: MockClient((r) async {
      if (r.url.path == '/api/mp/saldo' && r.method == 'POST') return _json({'id': 3});
      if (r.url.path == '/api/mp/saldo') {
        return _json({
          'estado': 'listo',
          'saldoDisponibleCentavos': 5000000,
          'aLiberarCentavos': 0,
          'hasta': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'movimientos': [
            {'fecha': DateTime.now().millisecondsSinceEpoch ~/ 1000, 'tipo': 'release', 'descripcion': 'payment', 'creditoCentavos': 0, 'debitoCentavos': 6604000},
          ],
        });
      }
      return _json({'cobros': [], 'truncado': false});
    }));
    nubeApp = NubeApp(
      almacen: almacen,
      cliente: cliente,
      copias: ServicioCopiasNube(db: db, almacen: almacen, cliente: cliente, carpetaTemporal: tmp, versionApp: () async => '1.0.0'),
      idDispositivo: () async => 'dev',
      nombreDispositivo: () => 'Caja',
      abrirNavegador: (_) async {},
      carpetaTemporal: tmp,
    );
    addTearDown(() => nubeApp = null);

    await abrirCierre();
    await tester.ensureVisible(find.byKey(const Key('boton_traer_saldo_mp')));
    await tester.tap(find.byKey(const Key('boton_traer_saldo_mp')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    final campo = find.descendant(of: find.byKey(const Key('campo_mp_contado')), matching: find.byType(TextField));
    expect(tester.widget<TextField>(campo).controller!.text, '50.000', reason: 'el saldo llenó el MP contado');
    expect(find.byKey(const Key('saldo_mp_total')), findsOneWidget);
    expect(find.byKey(const Key('diferencias_saldo_mp')), findsOneWidget);
    expect(find.textContaining('Salió de Mercado Pago y no está en la app'), findsOneWidget);

    await tester.ensureVisible(find.text('Cargar como gasto por MP'));
    await tester.tap(find.text('Cargar como gasto por MP'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('diferencias_saldo_mp')), findsNothing, reason: 'cargado: ya no es una diferencia');
    final gastos = await tester.runAsync(() => db.select(db.movimientosDeCaja).get());
    expect(gastos!.where((m) => m.tipo == 'GASTO'), hasLength(1));
  });
}

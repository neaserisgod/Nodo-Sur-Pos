// Las mismas guías de accesibilidad de Flutter que `venta_accesibilidad_test.dart`, sobre el resto de las pantallas de
// gestión de la PC (con un producto y un proveedor cargados). Mide; un fallo dice qué pantalla debe corregirse.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/ui/dashboard/pantalla_dashboard.dart';
import 'package:la_plazoleta/ui/historial/pantalla_historial.dart';
import 'package:la_plazoleta/ui/navegacion/route_observer.dart';
import 'package:la_plazoleta/ui/proveedores/pantalla_proveedores.dart';
import 'package:la_plazoleta/ui/separaciones/pantalla_separaciones.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import '../helpers/base_para_tests.dart';

typedef _Armar = Widget Function(AppDatabase db, int usuarioId, int sesionId);

final _pantallas = <String, _Armar>{
  'Inicio': (db, u, s) => PantallaDashboard(db: db),
  'Historial': (db, u, s) => PantallaHistorial(db: db, usuarioId: u),
  'Proveedores': (db, u, s) => PantallaProveedores(db: db, usuarioId: u, sesionCajaId: s),
  'Separaciones': (db, u, s) => PantallaSeparaciones(db: db, usuarioId: u, sesionCajaId: s),
};

Future<void> _mostrar(WidgetTester tester, Brightness brillo, _Armar armar) async {
  final db = baseDeTest();
  addTearDown(db.close);
  final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
  final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
  final proveedorId = await db.into(db.proveedores).insert(ProveedoresCompanion.insert(codigo: 'SUR', nombre: 'Distribuidora Sur'));
  await db.into(db.productos).insert(ProductosCompanion.insert(
        nombre: 'Coca-Cola 500ml',
        precioCentavos: const Value(112000),
        stock: const Value(20),
        proveedorId: Value(proveedorId),
      ));
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: brillo == Brightness.dark ? TemaPlazoleta.oscuro : TemaPlazoleta.claro,
    navigatorObservers: [routeObserver],
    home: Scaffold(body: armar(db, usuarioId, sesionId)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  for (final entrada in _pantallas.entries) {
    for (final brillo in [Brightness.light, Brightness.dark]) {
      final nombre = '${entrada.key}, tema ${brillo == Brightness.light ? 'claro' : 'oscuro'}';
      group(nombre, () {
        testWidgets('objetivos táctiles de 48 dp', (tester) async {
          final h = tester.ensureSemantics();
          await _mostrar(tester, brillo, entrada.value);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          h.dispose();
        });
        testWidgets('todo lo que se toca tiene etiqueta', (tester) async {
          final h = tester.ensureSemantics();
          await _mostrar(tester, brillo, entrada.value);
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          h.dispose();
        });
        testWidgets('contraste del texto', (tester) async {
          final h = tester.ensureSemantics();
          await _mostrar(tester, brillo, entrada.value);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          h.dispose();
        });
      });
    }
  }
}

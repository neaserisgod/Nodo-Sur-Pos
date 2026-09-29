// Antes probaba el salto a Reportes; Reportes se sacó del menú el
// 2026-09-26 y el mismo salto se prueba hacia Separaciones.
//
// Bug real (2026-09-12, Bruno: "al navegar entre apartados... se erra
// fuerte o se lockea y tengo que clickear varias veces"): el switch de
// `navegarASeccionDeGestion` no tenía caso para 'reportes' — tocar
// "Reportes" desde CUALQUIER pantalla que no fuera Venta volvía a Venta
// (por el `popUntil`) y no navegaba a ningún lado, en silencio. Desde Venta
// misma "Reportes" sí funcionaba (pasa por `_irAReportes`, no por acá), así
// que el síntoma era justo ese: falla seguido, pero no siempre.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/ui/navegacion/route_observer.dart';
import 'package:la_plazoleta/ui/separaciones/pantalla_separaciones.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:la_plazoleta/ui/venta/pantalla_venta.dart';

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaPlazoleta.oscuro,
      navigatorObservers: [routeObserver],
      home: PantallaVenta(db: db),
    ),
  );
  await tester.pumpAndSettle();
}

/// La navbar pasó a ser un solo botón que abre un dropdown de secciones
/// (Bruno, rediseño 2026-09-25) — hay que abrirlo antes de poder tocar el
/// nombre de la sección destino, en vez de tocar directo un ícono con
/// tooltip propio.
Future<void> _navegarA(WidgetTester tester, String etiqueta) async {
  await tester.tap(find.byTooltip('Cambiar de sección'));
  await tester.pumpAndSettle();
  // Adentro del menú: con la pantalla de atrás visible, "Venta" también
  // puede ser una métrica de la pantalla (Proveedores).
  await tester.tap(find.descendant(of: find.byKey(const Key('menu_secciones')), matching: find.text(etiqueta)).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'desde una pantalla de gestión (no Venta), tocar "Separaciones" en la navbar llega a Separaciones',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final usuarioId = await db
          .into(db.usuarios)
          .insert(UsuariosCompanion.insert(nombre: 'Bruno'));
      await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

      await _pump(tester, db);

      // Venta → Historial (por `_irAHistorial`, propio de la venta).
      await _navegarA(tester, 'Historial');

      // Historial → Separaciones, por la navbar COMPARTIDA
      // (`navegarASeccionDeGestion`) — el salto que fallaba era hacia
      // Reportes; Reportes se sacó del menú (2026-09-26) y Separaciones es
      // la sección que heredó su lugar (y también necesita la sesión).
      await _navegarA(tester, 'Separaciones');

      expect(find.byType(PantallaSeparaciones), findsOneWidget);
      // La recarga periódica de Separaciones deja un timer vivo.
      await tester.pumpWidget(const SizedBox());
    },
  );
}

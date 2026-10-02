// Antes probaba el salto a Reportes; Reportes se sacó del menú el
// 2026-09-26 y el mismo salto se prueba hacia Separaciones.
//
// Bug real (2026-09-12, el dueño: "al navegar entre apartados... se erra
// fuerte o se lockea y tengo que clickear varias veces"): el switch de
// `navegarASeccionDeGestion` no tenía caso para 'reportes' — tocar
// "Reportes" desde CUALQUIER pantalla que no fuera Venta volvía a Venta
// (por el `popUntil`) y no navegaba a ningún lado, en silencio. Desde Venta
// misma "Reportes" sí funcionaba (pasa por `_irAReportes`, no por acá), así
// que el síntoma era justo ese: falla seguido, pero no siempre.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/ui/navegacion/navbar_superior.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/ui/navegacion/route_observer.dart';
import 'package:la_plazoleta/ui/separaciones/pantalla_separaciones.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:la_plazoleta/ui/venta/pantalla_venta.dart';
import '../../helpers/base_para_tests.dart';

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

/// La navbar es una fila de pastillas (rediseño "antigravity"): se toca
/// directo la del destino, dentro de la barra.
Future<void> _navegarA(WidgetTester tester, String etiqueta) async {
  await tester.tap(find.descendant(of: find.byType(NavbarSuperior), matching: find.text(etiqueta)).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'desde una pantalla de gestión (no Venta), tocar "Separaciones" en la navbar llega a Separaciones',
    (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await db
          .into(db.usuarios)
          .insert(UsuariosCompanion.insert(nombre: 'Dueño'));
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

// Configuración del rediseño v4: una sola lista con todas las secciones (el nombre del grupo arriba de las suyas) y, a la
// derecha, el título de la sección con su descripción — sin pastillas.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/ui/configuracion/pantalla_configuracion.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import '../../helpers/base_para_tests.dart';

void main() {
  testWidgets('todas las secciones están a un toque, sin pasar por un grupo', (tester) async {
    tester.view.physicalSize = const Size(1366, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = baseDeTest();
    addTearDown(db.close);
    await tester.pumpWidget(MaterialApp(theme: TemaPlazoleta.claro, home: PantallaConfiguracion(db: db, usuarioId: 1)));
    await tester.pumpAndSettle();

    // Secciones de grupos distintos, visibles a la vez.
    for (final s in ['comercio', 'usuarios', 'cajaYRedondeo', 'mediosPago', 'categorias', 'impresion', 'respaldo', 'apariencia', 'modulos']) {
      expect(find.byKey(Key('pastilla_$s')), findsOneWidget, reason: s);
    }
    // Un toque en una sección de otro grupo la abre directo, con su título y su descripción.
    await tester.tap(find.byKey(const Key('pastilla_mediosPago')));
    await tester.pumpAndSettle();
    expect(find.text('Cómo se cobra y a qué caja va cada cosa.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pastilla_apariencia')));
    await tester.pumpAndSettle();
    expect(find.text('Cómo se ve y cómo se mueve.'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/ui/kit/kit.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/domain/forma_de_trabajo.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/domain/plantillas_rubro.dart';
import 'package:la_plazoleta/servicios/modulos_activos.dart';
import 'package:la_plazoleta/ui/configuracion/pantalla_configuracion.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import '../../helpers/base_para_tests.dart';

Future<void> _pump(WidgetTester tester, AppDatabase db) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: TemaPlazoleta.oscuro, home: PantallaConfiguracion(db: db, usuarioId: 1)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('grupo_apariencia')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('pastilla_modulos')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lista todos los módulos de un comercio, todos prendidos en uno que ya existía', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    await _pump(tester, db);
    for (final m in Modulo.values) {
      final interruptor = find.byKey(Key('modulo_${m.clave}'));
      if (!m.valePara(FormaDeTrabajo.productos)) {
        expect(interruptor, findsNothing, reason: '${m.clave} es de servicios');
        continue;
      }
      expect(interruptor, findsOneWidget, reason: m.clave);
      expect(tester.widget<Interruptor>(interruptor).valor, isTrue, reason: m.clave);
    }
  });

  testWidgets('una barbería solo ve los módulos que valen para servicios', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    await configurarRubro(db, PlantillaRubro.barberia);
    await _pump(tester, db);
    for (final m in Modulo.values) {
      expect(find.byKey(Key('modulo_${m.clave}')), m.valePara(FormaDeTrabajo.servicios) ? findsOneWidget : findsNothing, reason: m.clave);
    }
  });

  testWidgets('apagar y prender un módulo se guarda', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    await _pump(tester, db);

    await tester.ensureVisible(find.byKey(const Key('modulo_promos')));
    await tester.tap(find.byKey(const Key('modulo_promos')));
    await tester.pumpAndSettle();
    expect((await modulosNegocioActuales(db)).estaActivo(Modulo.promos), isFalse);
    expect(tester.widget<Interruptor>(find.byKey(const Key('modulo_promos'))).valor, isFalse);

    await tester.tap(find.byKey(const Key('modulo_promos')));
    await tester.pumpAndSettle();
    expect((await modulosNegocioActuales(db)).estaActivo(Modulo.promos), isTrue);
  });

  testWidgets('apagar Caja aparte esconde "Recargo de cigarrillos" del menú al instante', (tester) async {
    final db = baseDeTest();
    addTearDown(db.close);
    addTearDown(() => modulosActuales.value = ModulosNegocio.todosActivos);
    await _pump(tester, db);
    await tester.tap(find.byKey(const Key('grupo_cajaYCobros')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pastilla_cigarrillos')), findsOneWidget);

    modulosActuales.value = ModulosNegocio.todosActivos.conModulo(Modulo.cajaAparte, activo: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pastilla_cigarrillos')), findsNothing);
    expect(find.byKey(const Key('pastilla_cajaYRedondeo')), findsOneWidget);
  });
}

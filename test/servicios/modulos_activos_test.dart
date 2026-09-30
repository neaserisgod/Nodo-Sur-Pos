import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_configuracion.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/servicios/modulos_activos.dart';

void main() {
  tearDown(() => modulosActuales.value = ModulosNegocio.todosActivos);

  test('sin leer la base, todo está activo', () {
    expect(moduloActivo(Modulo.promos), isTrue);
  });

  test('seguirModulos refleja lo guardado y sus cambios', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final sub = seguirModulos(db);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(moduloActivo(Modulo.promos), isTrue);

    await configurarModulo(db, Modulo.promos, activo: false);
    await pumpEventQueue();
    expect(moduloActivo(Modulo.promos), isFalse);
    expect(moduloActivo(Modulo.fiado), isTrue);

    await configurarModulo(db, Modulo.promos, activo: true);
    await pumpEventQueue();
    expect(moduloActivo(Modulo.promos), isTrue);
  });

  testWidgets('SiModulo oculta y muestra su hijo al cambiar el módulo', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SiModulo(Modulo.promos, hijo: Text('hola'))));
    expect(find.text('hola'), findsOneWidget);
    modulosActuales.value = ModulosNegocio.todosActivos.conModulo(Modulo.promos, activo: false);
    await tester.pump();
    expect(find.text('hola'), findsNothing);
  });
}

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/servicios/modulos_activos.dart';
import 'package:la_plazoleta/ui/cierre/pantalla_cierre.dart';
import 'package:la_plazoleta/ui/tema/superficie.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import '../../helpers/base_para_tests.dart';

Future<int> _crearSesionConCigarrillos(AppDatabase db, int usuarioId) async {
  final sesionId = await abrirSesion(
    db,
    usuarioId: usuarioId,
    fondoInicialCentavos: 0,
  );
  final ventaId = await db.into(db.ventas).insert(
        VentasCompanion.insert(
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          subtotalCentavos: 450000,
          totalCentavos: 450000,
        ),
      );
  await db.into(db.lineasDeVenta).insert(
        LineasDeVentaCompanion.insert(
          ventaId: ventaId,
          nombreProductoFoto: 'Marlboro',
          tipoCigarrillo: const Value('atado'),
          cantidad: const Value(1),
          precioUnitarioCentavos: 450000,
        ),
      );
  return sesionId;
}

/// El kit puso la etiqueta de `CampoTexto`/`CampoPlata` fuera del `TextField`
/// (fija, no la flotante de Material) — cada campo que un test necesita
/// tocar tiene una `Key` propia en el widget que lo instancia.
Finder _campo(String llave) => find.descendant(of: find.byKey(Key(llave)), matching: find.byType(TextField));

Future<void> _pump(WidgetTester tester, AppDatabase db, int sesionId, int usuarioId) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaPlazoleta.oscuro,
      home: PantallaCierre(db: db, sesionId: sesionId, usuarioId: usuarioId),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('pantalla de cierre — oculto hasta confirmar (Regla 1 y 2)', () {
    testWidgets('al entrar, no hay ningún número de diferencia ni separación en pantalla', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
      final sesionId = await _crearSesionConCigarrillos(db, usuarioId);

      await _pump(tester, db, sesionId, usuarioId);

      expect(find.textContaining('Diferencia'), findsNothing);
      expect(find.textContaining('Separado'), findsNothing);
      expect(find.text('Confirmar conteo'), findsOneWidget);
    });

    testWidgets('confirmar el conteo revela diferencia y separación juntas', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
      final sesionId = await _crearSesionConCigarrillos(db, usuarioId);

      await _pump(tester, db, sesionId, usuarioId);

      await tester.enterText(find.byType(TextField).first, '1.000');
      await tester.tap(find.text('Confirmar conteo'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Diferencia'), findsOneWidget);
      // "A separar", no "Separado" (bug real, el dueño: el label viejo leía
      // como si ya se hubiese hecho en vez de decir que hay que hacerlo).
      expect(find.textContaining('A separar a la lata'), findsOneWidget);
    });

    testWidgets(
        'los tres totales grandes (efectivo, MP, lata) aparecen antes que nada, así solo hay que '
        'contar y pasar plata', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
      final sesionId = await _crearSesionConCigarrillos(db, usuarioId);

      await _pump(tester, db, sesionId, usuarioId);
      await tester.enterText(find.byType(TextField).first, '4.500');
      await tester.tap(find.text('Confirmar conteo'));
      await tester.pumpAndSettle();

      expect(find.text('Efectivo del día'), findsOneWidget);
      expect(find.text('Mercado Pago del día'), findsOneWidget);
      expect(find.text('A la lata de cigarrillos'), findsOneWidget);
    });

    testWidgets('escribir la lata contada muestra la lata esperada y la diferencia', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
      final sesionId = await _crearSesionConCigarrillos(db, usuarioId);

      await _pump(tester, db, sesionId, usuarioId);
      await tester.enterText(find.byType(TextField).first, '4.500');
      await tester.tap(find.text('Confirmar conteo'));
      await tester.pumpAndSettle();

      expect(find.text('Lata esperada'), findsNothing);

      final campoLataContada = _campo('campo_lata_contada');
      await tester.ensureVisible(campoLataContada);
      await tester.enterText(campoLataContada, '4.400');
      await tester.pumpAndSettle();

      // Etiqueta y valor son celdas separadas de una misma fila (plata
      // alineada a la derecha, `DISENO.md`) — se verifica por estructura, no
      // por texto concatenado. `.first` sobre el ancestro toma el `Row`
      // angosto de la fila (etiqueta + valor), no el `Row` ancho de las dos
      // columnas que también lo contiene — necesario porque "Separado a la
      // lata" cae en el mismo monto que "Lata esperada" en este escenario
      // (separación completa), y "Diferencia" se repite (Arqueo y lata).
      final bloqueCigarrillos = find.ancestor(of: find.text('Lata esperada'), matching: find.byType(Superficie));

      final filaLataEsperada = find.ancestor(of: find.text('Lata esperada'), matching: find.byType(Row)).first;
      expect(find.descendant(of: filaLataEsperada, matching: find.text('\$4.500')), findsOneWidget);

      final diferenciaDeLaLata = find.descendant(of: bloqueCigarrillos, matching: find.text('Diferencia'));
      final filaDiferenciaLata = find.ancestor(of: diferenciaDeLaLata, matching: find.byType(Row)).first;
      expect(find.descendant(of: filaDiferenciaLata, matching: find.text('-\$100')), findsOneWidget);
    });
  });

  group('separación parcial (Regla 4)', () {
    testWidgets('si no alcanza el efectivo, avisa y muestra el pendiente', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
      final sesionId = await _crearSesionConCigarrillos(db, usuarioId); // $4.500 en cigarrillos

      await _pump(tester, db, sesionId, usuarioId);

      await tester.enterText(find.byType(TextField).first, '1.000'); // mucho menos que lo vendido en cigarrillos
      await tester.tap(find.text('Confirmar conteo'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No alcanzó el efectivo'), findsOneWidget);
    });
  });

  group('flujo completo: cerrar y reabrir', () {
    testWidgets('cerrar caja muestra la pantalla final, y reabrir vuelve al conteo', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
      final sesionId =
          await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

      await _pump(tester, db, sesionId, usuarioId);

      await tester.enterText(find.byType(TextField).first, '0');
      await tester.tap(find.text('Confirmar conteo'));
      await tester.pumpAndSettle();

      final campoLataContada = _campo('campo_lata_contada');
      await tester.ensureVisible(campoLataContada);
      await tester.enterText(campoLataContada, '0');

      final campoMpContado = _campo('campo_mp_contado');
      await tester.ensureVisible(campoMpContado);
      await tester.enterText(campoMpContado, '0');
      await tester.ensureVisible(find.text('Cerrar caja'));
      await tester.tap(find.text('Cerrar caja'));
      await tester.pumpAndSettle();

      expect(find.text('Caja cerrada'), findsOneWidget);

      await tester.tap(find.text('Reabrir'));
      await tester.pumpAndSettle();
      // confirmación dentro del diálogo
      await tester.tap(find.text('Reabrir').last);
      await tester.pumpAndSettle();

      expect(find.text('Confirmar conteo'), findsOneWidget);

      final sesion = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).getSingle();
      expect(sesion.estado, 'ABIERTA');
    });
  });

  group('sin el módulo de caja aparte', () {
    testWidgets('no hay lata en el cierre y se cierra sin contarla', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      addTearDown(() => modulosActuales.value = ModulosNegocio.todosActivos);
      modulosActuales.value = ModulosNegocio.todosActivos.conModulo(Modulo.cajaAparte, activo: false);
      final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

      await _pump(tester, db, sesionId, usuarioId);
      await tester.enterText(find.byType(TextField).first, '0');
      await tester.tap(find.text('Confirmar conteo'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('campo_lata_contada')), findsNothing);
      expect(find.text('A la lata de cigarrillos'), findsNothing);
      expect(find.text('Efectivo del día'), findsOneWidget);

      final campoMpContado = _campo('campo_mp_contado');
      await tester.ensureVisible(campoMpContado);
      await tester.enterText(campoMpContado, '0');
      await tester.ensureVisible(find.text('Cerrar caja'));
      await tester.tap(find.text('Cerrar caja'));
      await tester.pumpAndSettle();

      expect(find.text('Caja cerrada'), findsOneWidget);
      final sesion = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).getSingle();
      expect(sesion.estado, 'CERRADA');
      expect(sesion.lataDiferenciaCentavos, 0);
    });
  });
}

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/servicios/modulos_activos.dart';
import 'package:la_plazoleta/ui/cierre/pantalla_cierre.dart';
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

/// Cada campo del cierre tiene una `Key` propia en el `Campo` del kit; el `TextField` está adentro.
Finder _campo(String llave) => find.descendant(of: find.byKey(Key(llave)), matching: find.byType(TextField));

/// A 1920×1080, la pantalla para la que está hecho el mock (el tamaño de test por defecto, 800×600, no es una caja real).
Future<void> _pump(WidgetTester tester, AppDatabase db, int sesionId, int usuarioId) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: TemaPlazoleta.oscuro,
      home: PantallaCierre(db: db, sesionId: sesionId, usuarioId: usuarioId),
    ),
  );
  await tester.pumpAndSettle();
}

/// Paso 1: las tres cajas a ciegas (la lata solo con el módulo de caja aparte) y confirmar.
Future<void> _contarYConfirmar(WidgetTester tester, {required String efectivo, String mp = '0', String? lata = '0'}) async {
  await tester.enterText(_campo('campo_efectivo_contado'), efectivo);
  await tester.enterText(_campo('campo_mp_contado'), mp);
  if (lata != null) await tester.enterText(_campo('campo_lata_contada'), lata);
  await tester.pump();
  await tester.tap(find.text('Confirmar conteo'));
  await tester.pumpAndSettle();
}

Future<int> _usuario(AppDatabase db) => db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));

void main() {
  group('pantalla de cierre — oculto hasta confirmar (Regla 1 y 2)', () {
    testWidgets('al entrar, no hay ningún número de diferencia ni separación en pantalla', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await _usuario(db);
      final sesionId = await _crearSesionConCigarrillos(db, usuarioId);

      await _pump(tester, db, sesionId, usuarioId);

      expect(find.text('¿Cuánta plata hay en cada caja?'), findsOneWidget);
      expect(find.text('Paso 1 de 2'), findsOneWidget);
      expect(find.textContaining('Diferencia'), findsNothing);
      expect(find.textContaining('A separar'), findsNothing);
      expect(find.textContaining('Debería haber'), findsNothing);
      expect(find.text('Confirmar conteo'), findsOneWidget);
    });

    testWidgets('sin las tres cajas contadas no se puede confirmar: el paso 2 ya no tiene campos', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await _usuario(db);
      final sesionId = await _crearSesionConCigarrillos(db, usuarioId);

      await _pump(tester, db, sesionId, usuarioId);
      await tester.enterText(_campo('campo_efectivo_contado'), '4.500');
      await tester.enterText(_campo('campo_mp_contado'), '0');
      await tester.pump();
      await tester.tap(find.text('Confirmar conteo'));
      await tester.pumpAndSettle();

      expect(find.text('Paso 1 de 2'), findsOneWidget, reason: 'falta la lata: el botón está apagado');
      expect(find.textContaining('Diferencia'), findsNothing);
    });

    testWidgets('confirmar el conteo revela diferencia y separación juntas', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await _usuario(db);
      final sesionId = await _crearSesionConCigarrillos(db, usuarioId);

      await _pump(tester, db, sesionId, usuarioId);
      await _contarYConfirmar(tester, efectivo: '1.000');

      expect(find.text('Paso 2 de 2'), findsOneWidget);
      expect(find.text('Diferencia del cajón'), findsOneWidget);
      // "A separar", no "Separado" (bug real, el dueño: el label viejo leía
      // como si ya se hubiese hecho en vez de decir que hay que hacerlo).
      expect(find.text('A separar a la lata (cigarrillos)'), findsOneWidget);
    });

    testWidgets(
        'lo que tiene que haber en cada caja (efectivo, MP, lata) está a la vista, así solo hay que contar y pasar plata',
        (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await _usuario(db);
      final sesionId = await _crearSesionConCigarrillos(db, usuarioId);

      await _pump(tester, db, sesionId, usuarioId);
      await _contarYConfirmar(tester, efectivo: '4.500');

      expect(find.text('Debería haber en el cajón'), findsOneWidget);
      expect(find.text('Debería haber en Mercado Pago'), findsOneWidget);
      expect(find.text('Debería haber en la lata'), findsOneWidget);
    });

    testWidgets('la lata contada se compara con la esperada', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await _usuario(db);
      final sesionId = await _crearSesionConCigarrillos(db, usuarioId);

      await _pump(tester, db, sesionId, usuarioId);
      await _contarYConfirmar(tester, efectivo: '4.500', lata: '4.400');

      final esperada = find.byKey(const Key('lata_esperada'));
      await tester.ensureVisible(esperada);
      expect(find.descendant(of: esperada, matching: find.text(r'$ 4.500')), findsOneWidget);
      expect(find.text(r'−$ 100'), findsOneWidget);
      expect(find.text(r'Faltan $ 100'), findsOneWidget);
    });

    testWidgets('volver a contar tapa todo de nuevo y conserva lo escrito', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await _usuario(db);
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

      await _pump(tester, db, sesionId, usuarioId);
      await _contarYConfirmar(tester, efectivo: '500');
      expect(find.text(r'Sobran $ 500 en el cajón'), findsOneWidget);

      await tester.tap(find.text('Volver a contar'));
      await tester.pumpAndSettle();

      expect(find.text('Paso 1 de 2'), findsOneWidget);
      expect(find.textContaining('Diferencia'), findsNothing);
      expect(tester.widget<TextField>(_campo('campo_efectivo_contado')).controller!.text, '500');

      await tester.enterText(_campo('campo_efectivo_contado'), '0');
      await tester.pump();
      await tester.tap(find.text('Confirmar conteo'));
      await tester.pumpAndSettle();
      expect(find.text('Cuadró el cajón'), findsOneWidget);
    });
  });

  group('separación parcial (Regla 4)', () {
    testWidgets('si no alcanza el efectivo, avisa y muestra el pendiente', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await _usuario(db);
      final sesionId = await _crearSesionConCigarrillos(db, usuarioId); // $4.500 en cigarrillos

      await _pump(tester, db, sesionId, usuarioId);
      await _contarYConfirmar(tester, efectivo: '1.000'); // mucho menos que lo vendido en cigarrillos

      expect(find.textContaining('No alcanzó el efectivo'), findsOneWidget);
    });
  });

  group('flujo completo: cerrar y reabrir', () {
    testWidgets('cerrar caja muestra la pantalla final, y reabrir vuelve al conteo', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await _usuario(db);
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

      await _pump(tester, db, sesionId, usuarioId);
      await _contarYConfirmar(tester, efectivo: '0');
      await tester.tap(find.text('Cerrar caja'));
      await tester.pumpAndSettle();

      expect(find.text('Caja cerrada'), findsOneWidget);
      expect(find.textContaining('Vendiste'), findsOneWidget);

      await tester.tap(find.text('Reabrir caja'));
      await tester.pumpAndSettle();
      // confirmación dentro del diálogo
      await tester.tap(find.text('Reabrir'));
      await tester.pumpAndSettle();

      expect(find.text('Confirmar conteo'), findsOneWidget);

      final sesion = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).getSingle();
      expect(sesion.estado, 'ABIERTA');
    });
  });

  group('desglose de Mercado Pago (El dueño, 2026-10-04)', () {
    testWidgets('el desglose de MP muestra el saldo al abrir y lo cobrado, con la cantidad de ventas', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await _usuario(db);
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0, mpInicialCentavos: 8746000);
      final medioMpId = (await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle()).id;
      final ventaId = await db.into(db.ventas).insert(
        VentasCompanion.insert(sesionCajaId: sesionId, usuarioId: usuarioId, subtotalCentavos: 1000000, totalCentavos: 1000000),
      );
      await db.into(db.pagos).insert(PagosCompanion.insert(ventaId: ventaId, medioPagoId: medioMpId, montoCentavos: 1000000));

      await _pump(tester, db, sesionId, usuarioId);
      await _contarYConfirmar(tester, efectivo: '0');

      final inicial = find.byKey(const Key('mp_desglose_inicial'));
      await tester.ensureVisible(inicial);
      expect(find.descendant(of: inicial, matching: find.text(r'$ 87.460')), findsOneWidget);
      final cobros = find.byKey(const Key('mp_desglose_cobros'));
      expect(find.descendant(of: cobros, matching: find.text('+ Cobrado por MP (1 venta)')), findsOneWidget);
      expect(find.descendant(of: cobros, matching: find.text(r'$ 10.000')), findsOneWidget);
      expect(find.textContaining('Lo que salió de Mercado Pago sin pasar por la app'), findsOneWidget);
    });
  });

  group('sin el módulo de caja aparte', () {
    testWidgets('no hay lata en el cierre y se cierra sin contarla', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      addTearDown(() => modulosActuales.value = ModulosNegocio.todosActivos);
      modulosActuales.value = ModulosNegocio.todosActivos.conModulo(Modulo.cajaAparte, activo: false);
      final usuarioId = await _usuario(db);
      final sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);

      await _pump(tester, db, sesionId, usuarioId);
      expect(find.byKey(const Key('campo_lata_contada')), findsNothing);
      await _contarYConfirmar(tester, efectivo: '0', lata: null);

      expect(find.text('A separar a la lata (cigarrillos)'), findsNothing);
      expect(find.text('Lata de cigarrillos'), findsNothing);
      expect(find.text('Debería haber en el cajón'), findsOneWidget);

      await tester.tap(find.text('Cerrar caja'));
      await tester.pumpAndSettle();

      expect(find.text('Caja cerrada'), findsOneWidget);
      final sesion = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).getSingle();
      expect(sesion.estado, 'CERRADA');
      expect(sesion.lataDiferenciaCentavos, 0);
    });
  });

  group('faltantes: a dónde fue la plata (El dueño, 2026-10-07)', () {
    Future<int> sesionConMp(AppDatabase db, int usuarioId) =>
        abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0, mpInicialCentavos: 10000000, lataInicialCentavos: 0);

    testWidgets('un faltante de Mercado Pago se anota como gasto mío y la caja queda en cero', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await _usuario(db);
      final sesionId = await sesionConMp(db, usuarioId);

      await _pump(tester, db, sesionId, usuarioId);
      await _contarYConfirmar(tester, efectivo: '0', mp: '0');

      expect(find.byKey(const Key('cierre_faltantes')), findsOneWidget);
      expect(find.text('Faltan \$ 100.000 en Mercado Pago'), findsOneWidget);

      await tester.tap(find.byKey(const Key('faltante_mercadoPago')));
      await tester.pumpAndSettle();
      expect(find.text('¿A dónde fueron?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('faltante_anotar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cierre_faltantes')), findsNothing);
      final retiro = await (db.select(db.movimientosDeCaja)..where((m) => m.tipo.equals('RETIRO'))).getSingle();
      expect(retiro.montoCentavos, 10000000);
    });

    testWidgets('cerrar con un faltante sin explicar avisa antes, y "No sé" cierra igual', (tester) async {
      final db = baseDeTest();
      addTearDown(db.close);
      final usuarioId = await _usuario(db);
      final sesionId = await sesionConMp(db, usuarioId);

      await _pump(tester, db, sesionId, usuarioId);
      await _contarYConfirmar(tester, efectivo: '0', mp: '0');
      await tester.tap(find.text('Cerrar caja'));
      await tester.pumpAndSettle();

      expect(find.text('Quedan \$ 100.000 sin explicar'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cerrar_sin_explicar')));
      await tester.pumpAndSettle();

      final sesion = await (db.select(db.sesionesDeCaja)..where((s) => s.id.equals(sesionId))).getSingle();
      expect(sesion.estado, 'CERRADA');
      expect(sesion.mpDiferenciaCentavos, -10000000);
    });
  });
}

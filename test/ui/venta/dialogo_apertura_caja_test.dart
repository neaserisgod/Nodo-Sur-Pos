import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_cierre.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:la_plazoleta/ui/venta/dialogo_apertura_caja.dart';

Future<void> _abrirDialogo(WidgetTester tester, AppDatabase db) async {
  // El viewport de test por defecto (800×600) es más chico que el piso real
  // de la app (1366×768 desde la fase 13) — se fija acá, mismo criterio que
  // el resto de los tests de esta pantalla (ver TRAMPAS.md).
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: TemaPlazoleta.oscuro,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (context) => DialogoAperturaCaja(db: db),
          ),
          child: const Text('Abrir'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

/// El kit puso la etiqueta de `CampoTexto`/`CampoPlata` FUERA del `TextField`
/// (fija, no la flotante de Material) — así que ya no se puede encontrar el
/// campo por su texto de label como antes (`find.widgetWithText`). Cada
/// campo tiene una `Key` propia en el widget que lo instancia (mismo
/// criterio que `pantalla_cierre_test.dart`).
Finder _campo(String llave) => find.descendant(
  of: find.byKey(Key(llave)),
  matching: find.byType(TextField),
);

void main() {
  late AppDatabase db;
  late int usuarioId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    usuarioId = await db
        .into(db.usuarios)
        .insert(UsuariosCompanion.insert(nombre: 'Bruno'));
  });
  tearDown(() => db.close());

  testWidgets(
    'primera apertura del día: el fondo inicial arranca vacío, sin precarga',
    (tester) async {
      await _abrirDialogo(tester, db);

      final campo = tester.widget<TextField>(_campo('campo_fondo_inicial'));
      expect(campo.controller!.text, isEmpty);
      expect(find.textContaining('Precargado'), findsNothing);
    },
  );

  testWidgets(
    'cambio de turno: precarga con lo que quedó en el cajón del cierre de hoy',
    (tester) async {
      final sesionAnteriorId = await abrirSesion(
        db,
        usuarioId: usuarioId,
        fondoInicialCentavos: 0,
      );
      await cerrarSesion(
        db,
        sesionId: sesionAnteriorId,
        usuarioId: usuarioId,
        efectivoContadoCentavos: 500000, // $5.000
        mpContadoCentavos: 0,
        lataContadoCentavos: 0,
      );
      // Sin cigarrillos vendidos ni separación: queda en el cajón = todo el contado.

      await _abrirDialogo(tester, db);

      final campo = tester.widget<TextField>(_campo('campo_fondo_inicial'));
      expect(campo.controller!.text, '5.000');
      // Específico al fondo: lata y MP (2026-09-12) también dicen "Precargado"
      // ahora, y en este escenario los tres se precargan a la vez (los tres
      // cerraron en $0 o el contado indicado, sin importar el día para lata/MP).
      expect(
        find.textContaining('Precargado con lo que quedó en el cajón'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'si la última cerrada fue ayer, no precarga (primera apertura del día)',
    (tester) async {
      final sesionAnteriorId = await abrirSesion(
        db,
        usuarioId: usuarioId,
        fondoInicialCentavos: 0,
      );
      await cerrarSesion(
        db,
        sesionId: sesionAnteriorId,
        usuarioId: usuarioId,
        efectivoContadoCentavos: 500000,
        mpContadoCentavos: 0,
        lataContadoCentavos: 0,
        fechaCierre: DateTime.now().subtract(const Duration(days: 1)),
      );

      await _abrirDialogo(tester, db);

      final campo = tester.widget<TextField>(_campo('campo_fondo_inicial'));
      expect(campo.controller!.text, isEmpty);
      // Específico al fondo: a diferencia de lata y MP (2026-09-12), que sí
      // precargan sin importar el día — la sesión de ayer sigue siendo la
      // "última cerrada" para esas dos, aunque no sea de hoy.
      expect(
        find.textContaining('Precargado con lo que quedó en el cajón'),
        findsNothing,
      );
    },
  );

  testWidgets('fondo inicial negativo no abre la caja y avisa el error', (
    tester,
  ) async {
    await _abrirDialogo(tester, db);

    await tester.enterText(_campo('campo_fondo_inicial'), '-500');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Abrir caja'));
    await tester.pumpAndSettle();

    expect(find.text('El fondo inicial no puede ser negativo'), findsOneWidget);
    expect(await sesionAbierta(db), isNull);
  });

  group('Caja cigarrillos editable (2026-09-12, reboot de la base)', () {
    testWidgets('primera apertura del día: arranca vacío, sin precarga', (
      tester,
    ) async {
      await _abrirDialogo(tester, db);

      final campo = tester.widget<TextField>(_campo('campo_lata_inicial'));
      expect(campo.controller!.text, isEmpty);
      expect(
        find.textContaining('Precargado con lo que quedó en la lata'),
        findsNothing,
      );
    });

    testWidgets(
      'con un cierre anterior, precarga con lo que quedó en la lata',
      (tester) async {
        final sesionAnteriorId = await abrirSesion(
          db,
          usuarioId: usuarioId,
          fondoInicialCentavos: 0,
          lataInicialCentavos: 200000, // $2.000
        );
        await cerrarSesion(
          db,
          sesionId: sesionAnteriorId,
          usuarioId: usuarioId,
          efectivoContadoCentavos: 0,
          mpContadoCentavos: 0,
          lataContadoCentavos: 200000,
        );
        // Sin cigarrillos vendidos ni pagos a Serra: la lata queda igual.

        await _abrirDialogo(tester, db);

        final campo = tester.widget<TextField>(_campo('campo_lata_inicial'));
        expect(campo.controller!.text, '2.000');
        expect(
          find.textContaining('Precargado con lo que quedó en la lata'),
          findsOneWidget,
        );
      },
    );

    testWidgets('monto negativo no abre la caja y avisa el error', (
      tester,
    ) async {
      await _abrirDialogo(tester, db);

      await tester.enterText(_campo('campo_lata_inicial'), '-500');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Abrir caja'));
      await tester.pumpAndSettle();

      expect(
        find.text('La caja de cigarrillos no puede ser negativa'),
        findsOneWidget,
      );
      expect(await sesionAbierta(db), isNull);
    });

    testWidgets('corregirlo a mano pisa el arrastre automático', (
      tester,
    ) async {
      final sesionAnteriorId = await abrirSesion(
        db,
        usuarioId: usuarioId,
        fondoInicialCentavos: 0,
        lataInicialCentavos: 200000,
      );
      await cerrarSesion(
        db,
        sesionId: sesionAnteriorId,
        usuarioId: usuarioId,
        efectivoContadoCentavos: 0,
        mpContadoCentavos: 0,
        lataContadoCentavos: 200000,
      );

      await _abrirDialogo(tester, db);
      await tester.enterText(_campo('campo_lata_inicial'), '9.000');
      final botonAbrir = find.widgetWithText(ElevatedButton, 'Abrir caja');
      await tester.ensureVisible(botonAbrir);
      await tester.tap(botonAbrir);
      await tester.pumpAndSettle();

      final sesion = await sesionAbierta(db);
      expect(sesion!.lataInicialCentavos, 900000);
    });
  });

  group('Monto Mercado Pago (2026-09-12, reboot de la base)', () {
    testWidgets('primera apertura del día: arranca vacío, sin precarga', (
      tester,
    ) async {
      await _abrirDialogo(tester, db);

      final campo = tester.widget<TextField>(_campo('campo_mp_inicial'));
      expect(campo.controller!.text, isEmpty);
      expect(
        find.textContaining('Precargado con lo último contado en Mercado Pago'),
        findsNothing,
      );
    });

    testWidgets(
      'con un cierre anterior, precarga con lo último contado en Mercado Pago',
      (tester) async {
        final sesionAnteriorId = await abrirSesion(
          db,
          usuarioId: usuarioId,
          fondoInicialCentavos: 0,
        );
        await cerrarSesion(
          db,
          sesionId: sesionAnteriorId,
          usuarioId: usuarioId,
          efectivoContadoCentavos: 0,
          mpContadoCentavos: 320000, // $3.200
          lataContadoCentavos: 0,
        );

        await _abrirDialogo(tester, db);

        final campo = tester.widget<TextField>(_campo('campo_mp_inicial'));
        expect(campo.controller!.text, '3.200');
        expect(
          find.textContaining(
            'Precargado con lo último contado en Mercado Pago',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'precarga sin importar el día: a diferencia del fondo, MP no se "cierra" a la noche',
      (tester) async {
        final sesionAnteriorId = await abrirSesion(
          db,
          usuarioId: usuarioId,
          fondoInicialCentavos: 0,
        );
        await cerrarSesion(
          db,
          sesionId: sesionAnteriorId,
          usuarioId: usuarioId,
          efectivoContadoCentavos: 0,
          mpContadoCentavos: 150000,
          lataContadoCentavos: 0,
          fechaCierre: DateTime.now().subtract(const Duration(days: 3)),
        );

        await _abrirDialogo(tester, db);

        final campo = tester.widget<TextField>(_campo('campo_mp_inicial'));
        expect(campo.controller!.text, '1.500');
      },
    );

    testWidgets('monto negativo no abre la caja y avisa el error', (
      tester,
    ) async {
      await _abrirDialogo(tester, db);

      await tester.enterText(_campo('campo_mp_inicial'), '-500');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Abrir caja'));
      await tester.pumpAndSettle();

      expect(
        find.text('El monto de Mercado Pago no puede ser negativo'),
        findsOneWidget,
      );
      expect(await sesionAbierta(db), isNull);
    });

    testWidgets(
      'lo que se tipea queda guardado como saldoMpInicialCentavos de la sesión',
      (tester) async {
        await _abrirDialogo(tester, db);

        await tester.enterText(_campo('campo_mp_inicial'), '1.000');
        await tester.tap(find.widgetWithText(ElevatedButton, 'Abrir caja'));
        await tester.pumpAndSettle();

        final sesion = await sesionAbierta(db);
        expect(sesion!.saldoMpInicialCentavos, 100000);
      },
    );
  });

  testWidgets('sin nada para separar, no muestra el aviso de reposición', (
    tester,
  ) async {
    await _abrirDialogo(tester, db);
    expect(find.text('Para separar:'), findsNothing);
  });

  testWidgets(
    'con costo real pendiente, avisa cuánto separar de cada proveedor (Regla 5 extendida)',
    (tester) async {
      final proveedorId = (await (db.select(
        db.proveedores,
      )..where((p) => p.codigo.equals('S'))).getSingle()).id;
      final sesionId = await db
          .into(db.sesionesDeCaja)
          .insert(
            SesionesDeCajaCompanion.insert(
              usuarioAbrioId: usuarioId,
              fondoInicialCentavos: 0,
            ),
          );
      final ventaId = await db
          .into(db.ventas)
          .insert(
            VentasCompanion.insert(
              sesionCajaId: sesionId,
              usuarioId: usuarioId,
              subtotalCentavos: 100000,
              totalCentavos: 100000,
            ),
          );
      await db
          .into(db.lineasDeVenta)
          .insert(
            LineasDeVentaCompanion.insert(
              ventaId: ventaId,
              nombreProductoFoto: 'Producto',
              proveedorIdFoto: Value(proveedorId),
              precioUnitarioCentavos: 100000,
              costoUnitarioCentavos: const Value(60000),
            ),
          );

      await _abrirDialogo(tester, db);

      expect(find.text('Para separar:'), findsOneWidget);
      expect(find.textContaining('Serra: \$600'), findsOneWidget);
    },
  );
}

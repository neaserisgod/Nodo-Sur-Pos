// "Pedir por WhatsApp" y el campo de WhatsApp del proveedor (rediseño v4, etapa 8.2).
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/ui/proveedores/lista_proveedores.dart';
import 'package:la_plazoleta/ui/proveedores/pantalla_proveedores.dart';
import 'package:la_plazoleta/ui/proveedores/pedir_por_whatsapp.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import '../../helpers/base_para_tests.dart';

Future<void> _pump(WidgetTester tester, AppDatabase db, int usuarioId, {Size tamanio = const Size(1920, 1080)}) async {
  tester.view.physicalSize = tamanio;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: TemaPlazoleta.oscuro, home: PantallaProveedores(db: db, usuarioId: usuarioId, sesionCajaId: null)));
  await tester.pumpAndSettle();
}

Future<void> _entrarA(WidgetTester tester, String nombre) async {
  final lista = find.byType(ListaProveedores);
  final fila = find.descendant(of: lista, matching: find.text(nombre));
  await tester.scrollUntilVisible(fila, 200, scrollable: find.descendant(of: lista, matching: find.byType(Scrollable)).last);
  await tester.tap(fila);
  await tester.pumpAndSettle();
}

Finder _campo(String llave) => find.descendant(of: find.byKey(Key(llave)), matching: find.byType(TextField));

void main() {
  tearDown(() => abrirUrlParaTests = null);

  Future<(AppDatabase, int)> preparar({String? whatsapp, bool conStockBajo = true}) async {
    final db = baseDeTest();
    addTearDown(db.close);
    final usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    final proveedorId = await db
        .into(db.proveedores)
        .insert(ProveedoresCompanion.insert(codigo: 'SE', nombre: 'Serra', whatsapp: Value(whatsapp)));
    await db.into(db.productos).insert(
      ProductosCompanion.insert(
        nombre: 'Alfajor triple',
        proveedorId: Value(proveedorId),
        precioCentavos: const Value(100000),
        stock: Value(conStockBajo ? 2 : 50),
        stockMinimo: const Value(6),
      ),
    );
    await db.into(db.productos).insert(
      ProductosCompanion.insert(nombre: 'Galletita', proveedorId: Value(proveedorId), precioCentavos: const Value(100000), stock: const Value(40), stockMinimo: const Value(6)),
    );
    return (db, usuarioId);
  }

  testWidgets('con número y stock bajo, abre wa.me con el pedido de lo que falta', (tester) async {
    final (db, usuarioId) = await preparar(whatsapp: '294 4123456');
    Uri? abierta;
    abrirUrlParaTests = (u) async {
      abierta = u;
      return true;
    };
    await _pump(tester, db, usuarioId);
    await _entrarA(tester, 'Serra');
    await tester.tap(find.byKey(const Key('boton_pedir_whatsapp')));
    await tester.pumpAndSettle();

    expect(abierta, isNotNull);
    expect(abierta!.host, 'wa.me');
    expect(abierta!.path, '/5492944123456');
    final texto = abierta!.queryParameters['text']!;
    expect(texto, contains('Hola Serra'));
    expect(texto, contains('- Alfajor triple (quedan 2)'));
    expect(texto, isNot(contains('Galletita')), reason: 'lo que tiene stock de sobra no se pide');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sin número avisa y no abre nada', (tester) async {
    final (db, usuarioId) = await preparar();
    var abrio = false;
    abrirUrlParaTests = (u) async => abrio = true;
    await _pump(tester, db, usuarioId);
    await _entrarA(tester, 'Serra');
    await tester.tap(find.byKey(const Key('boton_pedir_whatsapp')));
    await tester.pumpAndSettle();
    expect(abrio, isFalse);
    expect(find.text('Cargale el WhatsApp a Serra'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('con número pero sin nada con stock bajo avisa y no abre nada', (tester) async {
    final (db, usuarioId) = await preparar(whatsapp: '294 4123456', conStockBajo: false);
    var abrio = false;
    abrirUrlParaTests = (u) async => abrio = true;
    await _pump(tester, db, usuarioId);
    await _entrarA(tester, 'Serra');
    await tester.tap(find.byKey(const Key('boton_pedir_whatsapp')));
    await tester.pumpAndSettle();
    expect(abrio, isFalse);
    expect(find.text('No hay nada con stock bajo para pedirle a Serra'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('en "Avanzado" se guarda el WhatsApp y uno que no es número se rechaza', (tester) async {
    final (db, usuarioId) = await preparar();
    await _pump(tester, db, usuarioId);
    await _entrarA(tester, 'Serra');
    await tester.tap(find.text('Avanzado'));
    await tester.pumpAndSettle();

    await tester.enterText(_campo('campo_whatsapp'), 'hola');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('El WhatsApp no parece un número de teléfono'), findsOneWidget);

    await tester.enterText(_campo('campo_whatsapp'), '294 4123456');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final serra = await (db.select(db.proveedores)..where((p) => p.codigo.equals('SE'))).getSingle();
    expect(serra.whatsapp, '294 4123456');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('un proveedor nuevo puede nacer con WhatsApp', (tester) async {
    final (db, usuarioId) = await preparar();
    await _pump(tester, db, usuarioId);
    await tester.tap(find.byKey(const Key('boton_nuevo_proveedor')));
    await tester.pumpAndSettle();
    await tester.enterText(_campo('campo_nombre'), 'Andina');
    await tester.enterText(_campo('campo_codigo'), 'AN');
    await tester.enterText(_campo('campo_whatsapp'), '+54 9 294 555-1234');
    await tester.tap(find.text('Crear proveedor'));
    await tester.pumpAndSettle();
    final andina = await (db.select(db.proveedores)..where((p) => p.codigo.equals('AN'))).getSingle();
    expect(andina.whatsapp, '+54 9 294 555-1234');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a 1366 px el botón entra junto al filtro de stock bajo (sin desbordes)', (tester) async {
    final (db, usuarioId) = await preparar(whatsapp: '294 4123456');
    await _pump(tester, db, usuarioId, tamanio: const Size(1366, 768));
    await _entrarA(tester, 'Serra');
    expect(find.byKey(const Key('boton_pedir_whatsapp')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

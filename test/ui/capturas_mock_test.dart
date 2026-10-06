// Capturas de la PC con los datos del mock v4, a 1920×1040 (el área útil del mock: 1920×1080 menos la barra de la
// ventana), para compararlas a ojo contra `capturas-mock/k_*.png`. Guardan PNG en `capturas/mock/` (ignorada por git).
// No comprueban píxeles: solo que cada pantalla se dibuje sin errores, en claro y en oscuro, y a 1366×768.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_gastos.dart';
import 'package:la_plazoleta/domain/medio_pago.dart';
import 'package:la_plazoleta/ui/dashboard/pantalla_dashboard.dart';
import 'package:la_plazoleta/ui/historial/pantalla_historial.dart';
import 'package:la_plazoleta/ui/navegacion/route_observer.dart';
import 'package:la_plazoleta/ui/proveedores/lista_proveedores.dart';
import 'package:la_plazoleta/ui/separaciones/pantalla_separaciones.dart';
import 'package:la_plazoleta/ui/proveedores/pantalla_proveedores.dart';
import 'package:la_plazoleta/ui/tema/tema.dart';
import 'package:la_plazoleta/ui/venta/pantalla_venta.dart';
import 'package:la_plazoleta/ui/venta/venta_controlador.dart';
import 'package:provider/provider.dart';

import '../helpers/datos_mock.dart';

final _clave = GlobalKey();

/// flutter_test no carga las fuentes del pubspec: sin esto todo se dibuja con cajas.
Future<void> _cargarFuentes() async {
  final fija = FontLoader('Figtree');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    fija.addFont(rootBundle.load('fonts/Figtree-$f.ttf'));
  }
  await fija.load();
  final variable = FontLoader('FigtreeV')..addFont(rootBundle.load('fonts/FigtreeVariable.ttf'));
  await variable.load();
}

Future<void> capturarMock(
  WidgetTester tester,
  String nombre,
  Widget Function() pantalla, {
  bool oscuro = false,
  Size tamanio = const Size(1920, 1040),
  Future<void> Function()? antes,
}) async {
  tester.view.physicalSize = tamanio;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _clave,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: TemaPlazoleta.claro,
        darkTheme: TemaPlazoleta.oscuro,
        themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
        navigatorObservers: [routeObserver],
        home: pantalla(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  if (antes != null) {
    await antes();
    await tester.pump(const Duration(milliseconds: 600));
  }
  // Lo que lee la base de verdad (drift) no avanza con el reloj falso: se le da tiempo real y se vuelve a dibujar.
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump(const Duration(milliseconds: 400));
  }
  await tester.pump(const Duration(seconds: 1));
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final limite = _clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final imagen = await limite.toImage(pixelRatio: 1);
    final bytes = await imagen.toByteData(format: ui.ImageByteFormat.png);
    final sufijo = '${oscuro ? '-oscuro' : ''}${tamanio.width < 1900 ? '-${tamanio.width.toInt()}' : ''}';
    final archivo = File('capturas/mock/$nombre$sufijo.png');
    await archivo.create(recursive: true);
    await archivo.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_cargarFuentes);

  for (final oscuro in [false, true]) {
    for (final tamanio in [const Size(1920, 1040), const Size(1366, 728)]) {
      final sufijo = '${oscuro ? ' (oscuro)' : ''} ${tamanio.width.toInt()}';

      testWidgets('venta con carrito$sufijo', (tester) async {
        final b = (await tester.runAsync(baseDelMock))!;
        addTearDown(b.db.close);
        await capturarMock(
          tester,
          'venta',
          () => PantallaVenta(db: b.db),
          oscuro: oscuro,
          tamanio: tamanio,
          antes: () async {
            final c = Provider.of<VentaControlador>(tester.element(find.byType(Scaffold).first), listen: false);
            c.agregarProducto(b.productos['cerveza']!);
            c.agregarProducto(b.productos['cerveza']!);
            c.campoTexto.text = '250 jamon';
            c.agregarProducto(b.productos['jamon']!);
            c.agregarProducto(b.productos['pan']!);
            c.agregarProducto(b.productos['pan']!);
            c.agregarProducto(b.productos['pan']!);
            c.campoTexto.clear();
            c.elegirMedio(ComposicionPago.efectivo);
          },
        );
      });

      testWidgets('mega-menú de Historial$sufijo', (tester) async {
        final b = (await tester.runAsync(baseDelMock))!;
        addTearDown(b.db.close);
        await capturarMock(tester, 'venta-mega', () => PantallaVenta(db: b.db), oscuro: oscuro, tamanio: tamanio, antes: () async {
          final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
          await mouse.addPointer(location: Offset.zero);
          addTearDown(mouse.removePointer);
          await mouse.moveTo(tester.getCenter(find.text('Historial')));
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump(const Duration(milliseconds: 600));
        });
      });

      testWidgets('menú de caja$sufijo', (tester) async {
        final b = (await tester.runAsync(baseDelMock))!;
        addTearDown(b.db.close);
        await capturarMock(tester, 'venta-caja', () => PantallaVenta(db: b.db), oscuro: oscuro, tamanio: tamanio, antes: () async {
          await tester.tap(find.byKey(const Key('boton_caja')));
        });
      });

      testWidgets('inicio$sufijo', (tester) async {
        final b = (await tester.runAsync(baseDelMock))!;
        addTearDown(b.db.close);
        await capturarMock(tester, 'inicio', () => PantallaDashboard(db: b.db), oscuro: oscuro, tamanio: tamanio);
      });

      testWidgets('inicio este mes$sufijo', (tester) async {
        final b = (await tester.runAsync(baseDelMock))!;
        addTearDown(b.db.close);
        await capturarMock(tester, 'inicio-mes', () => PantallaDashboard(db: b.db), oscuro: oscuro, tamanio: tamanio, antes: () async {
          await tester.tap(find.text('Este mes'));
        });
      });

      testWidgets('proveedores$sufijo', (tester) async {
        final b = (await tester.runAsync(baseDelMock))!;
        addTearDown(b.db.close);
        await capturarMock(
          tester,
          'proveedores',
          () => PantallaProveedores(db: b.db, usuarioId: b.usuarioId, sesionCajaId: b.sesionId),
          oscuro: oscuro,
          tamanio: tamanio,
          antes: () async {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
            await tester.pump();
            final lista = tester.widget<ListaProveedores>(find.byType(ListaProveedores));
            await tester.runAsync(() => lista.controlador.seleccionar(b.proveedores['quilmes']!));
            await tester.pump();
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
          },
        );
      });

      testWidgets('separaciones$sufijo', (tester) async {
        final b = (await tester.runAsync(baseDelMock))!;
        addTearDown(b.db.close);
        await capturarMock(
          tester,
          'separaciones',
          () => PantallaSeparaciones(db: b.db, usuarioId: b.usuarioId, sesionCajaId: b.sesionId),
          oscuro: oscuro,
          tamanio: tamanio,
        );
      });

      testWidgets('separaciones ganancia$sufijo', (tester) async {
        final b = (await tester.runAsync(baseDelMock))!;
        addTearDown(b.db.close);
        await capturarMock(
          tester,
          'separaciones-ganancia',
          () => PantallaSeparaciones(db: b.db, usuarioId: b.usuarioId, sesionCajaId: b.sesionId),
          oscuro: oscuro,
          tamanio: tamanio,
          antes: () async {
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
            await tester.pump();
            await tester.tap(find.byKey(const Key('boton_ganancia')));
            await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
          },
        );
      });

      for (final (pestana, archivo) in [(null, 'historial'), ('movimientos', 'historial-movimientos'), ('cierres', 'historial-cierres')]) {
        testWidgets('$archivo$sufijo', (tester) async {
          final b = (await tester.runAsync(baseDelMock))!;
          addTearDown(b.db.close);
          await tester.runAsync(() async {
            await registrarGastoRapido(b.db, sesionCajaId: b.sesionId, usuarioId: b.usuarioId, montoCentavos: 800000, medio: MedioGasto.cajonNormal, motivo: 'Flete de Quilmes');
            await registrarGastoRapido(b.db, sesionCajaId: b.sesionId, usuarioId: b.usuarioId, montoCentavos: 350000, medio: MedioGasto.lata, motivo: 'Bolsas');
            // Tres días cerrados como los del mock: uno cuadró, uno faltó y uno sobró.
            for (final (dias, vendido, diferencia) in [(1, 43120000, 0), (2, 61280000, -130000), (3, 54890000, 50000)]) {
              final apertura = DateTime.now().subtract(Duration(days: dias, hours: 6));
              final id = await b.db.into(b.db.sesionesDeCaja).insert(SesionesDeCajaCompanion.insert(
                    usuarioAbrioId: b.usuarioId,
                    fondoInicialCentavos: 3000000,
                    fechaApertura: Value(apertura),
                    fechaCierre: Value(apertura.add(const Duration(hours: 13))),
                    estado: const Value('CERRADA'),
                    efectivoEsperadoCentavos: Value(3000000 + vendido ~/ 2),
                    efectivoContadoCentavos: Value(3000000 + vendido ~/ 2 + diferencia),
                    diferenciaCentavos: Value(diferencia),
                  ));
              final venta = await b.db.into(b.db.ventas).insert(VentasCompanion.insert(sesionCajaId: id, usuarioId: b.usuarioId, subtotalCentavos: vendido, totalCentavos: vendido, fecha: Value(apertura)));
              final efectivo = await (b.db.select(b.db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle();
              await b.db.into(b.db.pagos).insert(PagosCompanion.insert(ventaId: venta, medioPagoId: efectivo.id, montoCentavos: vendido));
            }
          });
          await capturarMock(
            tester,
            archivo,
            () => PantallaHistorial(db: b.db, usuarioId: b.usuarioId, pestanaInicial: pestana),
            oscuro: oscuro,
            tamanio: tamanio,
          );
        });
      }

      testWidgets('venta vacía$sufijo', (tester) async {
        final b = (await tester.runAsync(baseDelMock))!;
        addTearDown(b.db.close);
        await capturarMock(tester, 'venta-vacia', () => PantallaVenta(db: b.db), oscuro: oscuro, tamanio: tamanio);
      });
    }
  }
}

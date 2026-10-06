// Capturas de la companion para revisar el diseño a ojo: dibujan las
// pantallas con la base de test y guardan PNG en `capturas/companion/`
// (carpeta ignorada por git). No comprueban pixeles: solo que cada pantalla
// se dibuje sin excepciones, en claro y en oscuro.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/app_ns.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/bienvenida/pantalla_bienvenida.dart';
import 'package:la_plazoleta/companion/bienvenida/pantalla_listo.dart';
import 'package:la_plazoleta/companion/bienvenida/vista_entrar_con_google.dart';
import 'package:la_plazoleta/companion/configurar/asistente_negocio.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:la_plazoleta/companion/conmutador_sync.dart';
import 'package:la_plazoleta/companion/modo_uso.dart';
import 'package:la_plazoleta/companion/pantalla_cuenta_companion.dart';
import 'package:la_plazoleta/companion/pantalla_elegir_modo.dart';
import 'package:la_plazoleta/companion/sync_nube_companion.dart';
import 'package:la_plazoleta/servicios/cuenta_nube.dart';
import 'package:la_plazoleta/servicios/sync_nube.dart';

import 'package:la_plazoleta/companion/pantalla_conteo_stock.dart';
import 'package:la_plazoleta/companion/pantalla_consultar_precio.dart';
import 'package:la_plazoleta/companion/pantalla_movimiento_caja.dart';

import 'package:la_plazoleta/companion/pantalla_carrito_venta.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/domain/plantillas_rubro.dart';
import 'package:la_plazoleta/domain/venta.dart';

import '../helpers/base_para_tests.dart';
import '../helpers/controlador_falso_ns.dart';
import '../helpers/servidor_sync_falso.dart';

final _clave = GlobalKey();

/// flutter_test no carga las fuentes del pubspec: sin esto todo se dibuja con
/// Ahem (cajas) y los textos desbordan por culpa del test, no de la app.
Future<void> _cargarFigtree() async {
  final cargador = FontLoader('Figtree');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    cargador.addFont(rootBundle.load('fonts/Figtree-$f.ttf'));
  }
  await cargador.load();
}

Future<void> _capturar(WidgetTester tester, String nombre, Widget pantalla, {bool oscuro = false}) async {
  tester.view.physicalSize = const Size(390 * 2, 844 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _clave,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: TemaCompanion.claro,
        darkTheme: TemaCompanion.oscuro,
        themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
        home: pantalla,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final limite = _clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final imagen = await limite.toImage(pixelRatio: 2);
    final bytes = await imagen.toByteData(format: ui.ImageByteFormat.png);
    final archivo = File('capturas/companion/$nombre${oscuro ? '-oscuro' : ''}.png');
    await archivo.create(recursive: true);
    await archivo.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({
        // Usuario ya elegido, para que las pantallas no pidan elegirlo.
        'companion_usuario_id': 1,
        'companion_usuario_nombre': 'Dueño',
      }));

  Future<void> preparar(WidgetTester tester) async {
    await _cargarFigtree();
    final db = await tester.runAsync(() async => baseDeTest());
    usarBaseLocalDeTest(db!);
  }

  for (final oscuro in [false, true]) {
    final sufijo = oscuro ? ' (oscuro)' : '';
    testWidgets('consultar precio$sufijo', (tester) async {
      await preparar(tester);
      await _capturar(tester, 'consultar-precio', const PantallaConsultarPrecio(), oscuro: oscuro);
    });
    testWidgets('conteo de stock$sufijo', (tester) async {
      await preparar(tester);
      await _capturar(tester, 'conteo-stock', const PantallaConteoStock(), oscuro: oscuro);
    });
    testWidgets('movimiento de caja$sufijo', (tester) async {
      await preparar(tester);
      await _capturar(tester, 'movimiento-caja', AppNs(controlador: ControladorFalsoNs(), version: 0, child: const PantallaMovimientoCaja()), oscuro: oscuro);
    });
    testWidgets('carrito$sufijo', (tester) async {
      await preparar(tester);
      final carrito = <LineaVenta>[
        const LineaVentaPorUnidad(productoId: 'a', nombreProducto: 'Cerveza lata 473 ml', proveedorId: null, cantidad: 2, precioUnitarioCentavos: 210000),
        const LineaVentaPorUnidad(productoId: 'b', nombreProducto: 'Gaseosa cola 2,25 L', proveedorId: null, cantidad: 1, precioUnitarioCentavos: 290000),
        const LineaVentaPesable(productoId: 'c', nombreProducto: 'Jamón cocido', proveedorId: null, gramos: 250, precioPorKiloCentavos: 1460000),
      ];
      final servicio = PuertoLocal(baseLocalCompanion());
      await tester.runAsync(() => servicio.abrirSesion(usuarioId: 1, fondoInicialCentavos: 2000000));
      await _capturar(
        tester,
        'carrito',
        AppNs(controlador: ControladorFalsoNs(), version: 0, child: Scaffold(body: PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: carrito))),
        oscuro: oscuro,
      );
    });
    // La bienvenida, en cada parada (lo que se ve al tocar Siguiente).
    for (var paso = 0; paso < paradasBienvenida.length; paso++) {
      testWidgets('bienvenida ${paso + 1}$sufijo', (tester) async {
        await preparar(tester);
        await _capturar(
          tester,
          'bienvenida-${paso + 1}',
          PantallaBienvenida(alTerminar: (_) {}, pasoInicial: paso, segundoFijo: paradasBienvenida[paso]),
          oscuro: oscuro,
        );
      });
    }
    testWidgets('entrar con google$sufijo', (tester) async {
      await preparar(tester);
      await _capturar(tester, 'entrar-google', VistaEntrarConGoogle(alEntrar: () {}), oscuro: oscuro);
    });
    for (final paso in PasoNegocio.values) {
      testWidgets('configurar negocio ${paso.name}$sufijo', (tester) async {
        await preparar(tester);
        await _capturar(
          tester,
          'configurar-${paso.name}',
          AsistenteNegocio(
            pasoInicial: paso,
            nombreInicial: 'Almacén Don Pepe',
            rubroInicial: PlantillaRubro.almacen,
            alGuardarNegocio: (_, _) async {},
            alEscanear: (_) async => null,
            alGuardarProducto: (_) async {},
            alAbrirWeb: (_) {},
            alTerminar: (_, _) {},
          ),
          oscuro: oscuro,
        );
      });
    }
    testWidgets('listo$sufijo', (tester) async {
      await preparar(tester);
      await _capturar(tester, 'listo', PantallaListo(nombre: 'Bruno', alSeguir: (_) {}), oscuro: oscuro);
    });
    testWidgets('elegir modo$sufijo', (tester) async {
      await preparar(tester);
      await _capturar(tester, 'elegir-modo', PantallaElegirModo(alElegir: (_, _) {}), oscuro: oscuro);
    });
    testWidgets('cambiar modo$sufijo', (tester) async {
      await preparar(tester);
      await _capturar(tester, 'cambiar-modo', PantallaElegirModo(alElegir: (_, _) {}, actual: ModoUso.pcYCelular), oscuro: oscuro);
    });
    for (final vinculada in [false, true]) {
      testWidgets('cuenta ${vinculada ? 'vinculada' : 'sin vincular'}$sufijo', (tester) async {
        await preparar(tester);
        final almacen = AlmacenCuentaEnMemoria();
        if (vinculada) {
          await almacen.guardar(const CuentaVinculada(
              token: 't', email: 'bruno@correo.com', idDispositivo: 'android-1', nombreDispositivo: 'Celular (android)', vence: 99));
        }
        final servidor = ServidorSyncFalso();
        final sync = armarSyncNubeCompanion(
          almacen: almacen,
          almacenEstado: AlmacenEstadoSyncEnMemoria(),
          cliente: ClienteNube(http: servidor.http_, abrirEscucha: servidor.abrir),
          abrirNavegador: (_) async {},
          db: baseLocalCompanion(),
        );
        sync.conmutador.modo.value = vinculada ? ModoSync.nube : ModoSync.local;
        await _capturar(tester, 'cuenta-${vinculada ? 'vinculada' : 'sin-vincular'}', PantallaCuentaCompanion(sync: sync), oscuro: oscuro);
      });
    }
  }
}

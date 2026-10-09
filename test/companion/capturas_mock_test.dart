// Capturas de las pantallas del mock del celular (390×844 @2x) en
// `capturas/companion-mock/`, para ponerlas al lado de las del paquete del mock.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:la_plazoleta/companion/pantalla_carga_historica.dart';
import 'package:la_plazoleta/companion/app_ns.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/pantalla_carrito_venta.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/domain/venta.dart';
import 'package:la_plazoleta/companion/cliente_companion.dart' show ApartadoCompanion, DetalleVentaCompanion, ErrorCompanion, LineaTicketCompanion, MedioGastoCompanion, MedioVentaHistorialCompanion, ProductoCompanion, VentaDelHistorialCompanion;
import 'package:la_plazoleta/domain/cobro_posnet.dart';
import 'package:la_plazoleta/domain/descuento.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';
import 'package:la_plazoleta/companion/pantalla_consultar_precio.dart';
import 'package:la_plazoleta/companion/pantalla_movimiento_caja.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_buscador_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_caja_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_cierre_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_mas_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_productos_ns.dart';
import 'package:la_plazoleta/companion/pantalla_conteo_stock.dart';
import 'package:la_plazoleta/companion/pantalla_formulario_producto.dart';
import 'package:la_plazoleta/companion/pantalla_formulario_proveedor.dart';
import 'package:la_plazoleta/companion/pantalla_proveedores.dart';
import 'package:la_plazoleta/data/database.dart' show AppDatabase, ProveedoresCompanion;
import 'package:la_plazoleta/data/repositorio_deuda_proveedores.dart' show cargarDeuda;
import 'package:drift/drift.dart' show Value;
import 'package:la_plazoleta/companion/pantallas/pantalla_inicio_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_notificaciones_ns.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/companion/configurar/asistente_negocio.dart';
import 'package:la_plazoleta/companion/configurar/negocio_nuevo.dart';
import 'package:la_plazoleta/companion/pantallas/hoja_actualizar_ns.dart';

import '../helpers/base_para_tests.dart';
import '../helpers/controlador_falso_ns.dart';

final _clave = GlobalKey();

Future<void> _cargarFigtree() async {
  final cargador = FontLoader('Figtree');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    cargador.addFont(rootBundle.load('fonts/Figtree-$f.ttf'));
  }
  await cargador.load();
}

/// Dibuja [pantalla] dentro del mismo marco que el mock y guarda el PNG.
Future<void> capturarNs(
  WidgetTester tester,
  String nombre,
  Widget pantalla, {
  bool oscuro = false,
  ControladorFalsoNs? controlador,
  PestaniaNs? barra,
  Future<void> Function(WidgetTester)? antes,
}) async {
  tester.view.physicalSize = const Size(390 * 2, 844 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final c = controlador ?? ControladorFalsoNs();
  await tester.pumpWidget(
    RepaintBoundary(
      key: _clave,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: TemaCompanion.claro,
        darkTheme: TemaCompanion.oscuro,
        themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
        home: AppNs(
          controlador: c,
          version: 0,
          child: Builder(
            builder: (context) => Scaffold(
              backgroundColor: context.ns.paper,
              extendBody: true,
              body: SafeArea(bottom: false, child: pantalla),
              bottomNavigationBar: barra == null ? null : BarraInferiorNs(activa: barra, onSeleccionar: (_) {}, hayActualizacion: true),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump(const Duration(milliseconds: 700));
  if (antes != null) await antes(tester);
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final limite = _clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final imagen = await limite.toImage(pixelRatio: 2);
    final bytes = await imagen.toByteData(format: ui.ImageByteFormat.png);
    final archivo = File('capturas/companion-mock/$nombre${oscuro ? '-oscuro' : ''}.png');
    await archivo.create(recursive: true);
    await archivo.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

/// Puerto local con una terminal Point de mentira: el estado de la orden lo elige cada captura.
class _PuertoPosnet extends PuertoLocal {
  _PuertoPosnet(super.base, {this.estado = ResultadoOrdenCobro.pendiente, this.nuncaCrea = false, this.falloAlCrear, this.falloAlGuardar, this.falloAlAnotar, this.falloAlListar, this.conHistorial = false});
  final Object? falloAlAnotar;
  final Object? falloAlListar;
  final bool conHistorial;

  @override
  Future<List<ProductoCompanion>> productos({String? busqueda, int? proveedorId, bool sinCategoria = false, bool sinCodigoBarras = false, bool sinCosto = false, bool sinProveedor = false}) {
    if (falloAlListar != null) return Future.error(falloAlListar!);
    return super.productos(busqueda: busqueda, proveedorId: proveedorId, sinCategoria: sinCategoria, sinCodigoBarras: sinCodigoBarras, sinCosto: sinCosto, sinProveedor: sinProveedor);
  }

  static VentaDelHistorialCompanion _v(int id, int h, int m, int total, MedioVentaHistorialCompanion medio) =>
      VentaDelHistorialCompanion(ventaId: id, numero: '#0$id', fecha: DateTime.now().copyWith(hour: h, minute: m), totalCentavos: total, medio: medio, detalle: '', anulada: false, sesionAbierta: true);

  @override
  Future<List<VentaDelHistorialCompanion>> historialDeVentas({required DateTime desde, required DateTime hasta, MedioVentaHistorialCompanion? filtroMedio}) async {
    if (!conHistorial) return super.historialDeVentas(desde: desde, hasta: hasta, filtroMedio: filtroMedio);
    return [
      _v(143, 20, 12, 1435000, MedioVentaHistorialCompanion.efectivo),
      _v(142, 19, 48, 900000, MedioVentaHistorialCompanion.qr),
      _v(141, 19, 20, 530000, MedioVentaHistorialCompanion.debitCard),
      _v(140, 18, 55, 920000, MedioVentaHistorialCompanion.efectivo),
    ];
  }

  @override
  Future<DetalleVentaCompanion> detalleVenta(int ventaId) async {
    if (!conHistorial) return super.detalleVenta(ventaId);
    return DetalleVentaCompanion(
      fecha: DateTime(2026, 9, 29, 18, 55),
      vendedor: 'Lucía',
      lineas: const [
        LineaTicketCompanion(nombreProducto: 'Leche entera 1 L', cantidad: 2, subtotalCentavos: 320000),
        LineaTicketCompanion(nombreProducto: 'Facturas (docena)', cantidad: 1, subtotalCentavos: 650000),
      ],
      recargoCigarrillosCentavos: 0,
      descuentoCentavos: 48500,
      redondeoCentavos: -1500,
      totalCentavos: 920000,
    );
  }
  final ResultadoOrdenCobro estado;
  final bool nuncaCrea;
  final Object? falloAlCrear;
  final Object? falloAlGuardar;

  @override
  Future<({int ordenPendienteId, String ordenIdMp, int totalCentavos})> iniciarCobroPosnet({
    required List<LineaVenta> lineas,
    required String canal,
    required int sesionCajaId,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
    int? montoEfectivoMixtoCentavos,
  }) async {
    if (nuncaCrea) await Completer<void>().future;
    if (falloAlCrear != null) throw falloAlCrear!;
    return (ordenPendienteId: 1, ordenIdMp: 'ORD1', totalCentavos: 1625000);
  }

  @override
  Future<ResultadoOrdenCobro> consultarEstadoPosnet(String ordenIdMp) async => estado;

  @override
  Future<int> registrarGasto({required int sesionCajaId, required int usuarioId, required int montoCentavos, required MedioGastoCompanion medio, String? motivo}) async {
    if (falloAlAnotar != null) throw falloAlAnotar!;
    return super.registrarGasto(sesionCajaId: sesionCajaId, usuarioId: usuarioId, montoCentavos: montoCentavos, medio: medio, motivo: motivo);
  }

  // Las líneas de las capturas no son productos de la base: la venta se da por asentada sin tocarla.
  @override
  Future<({int ventaId, int totalCentavos})> cobrarEfectivo({
    required List<LineaVenta> lineas,
    required int sesionCajaId,
    required int usuarioId,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
    int? encargueId,
    String? claveCobro,
  }) async => (ventaId: 1, totalCentavos: Venta(lineas: lineas).subtotalCentavos);

  @override
  Future<({int ventaId, int totalCentavos})> cobrarVirtualAMano({
    required List<LineaVenta> lineas,
    required int sesionCajaId,
    required int usuarioId,
    required String canal,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
    int? encargueId,
    String? claveCobro,
    int? montoEfectivoMixtoCentavos,
  }) async => (ventaId: 1, totalCentavos: Venta(lineas: lineas).subtotalCentavos);

  @override
  Future<void> resolverCobroPosnetNoAprobado({required int ordenPendienteId, required String estado}) async {}

  @override
  Future<({int ventaId, int totalCentavos})> confirmarCobroPosnet({
    required int ordenPendienteId,
    required List<LineaVenta> lineas,
    required String canal,
    required int sesionCajaId,
    required int usuarioId,
    TipoDescuento? tipoDescuento,
    int valorDescuento = 0,
    int? encargueId,
    int? montoEfectivoMixtoCentavos,
  }) async {
    if (falloAlGuardar != null) throw falloAlGuardar!;
    return (ventaId: 1, totalCentavos: 1625000);
  }
}

/// Deja correr las animaciones: el primer cuadro arranca los controladores y el segundo los avanza.
Future<void> esperar(WidgetTester t) async {
  await t.pump(const Duration(milliseconds: 60));
  await t.pump(const Duration(milliseconds: 900));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _cargarFigtree();
  });

  Future<PuertoLocal> servicioConCaja(WidgetTester t, {bool abrir = true}) async {
    final db = await t.runAsync(() async => baseDeTest());
    usarBaseLocalDeTest(db!);
    final servicio = PuertoLocal(baseLocalCompanion());
    if (abrir) await t.runAsync(() => servicio.abrirSesion(usuarioId: 1, fondoInicialCentavos: 3000000));
    return servicio;
  }

  testWidgets('03-inicio', (t) async {
    SharedPreferences.setMockInitialValues({});
    await servicioConCaja(t);
    await capturarNs(t, '03-inicio', const PantallaInicioNs(), barra: PestaniaNs.inicio);
  });
  testWidgets('03b-inicio-tablero', (t) async {
    SharedPreferences.setMockInitialValues({});
    await servicioConCaja(t);
    await capturarNs(t, '03b-inicio-tablero', const PantallaInicioNs(), barra: PestaniaNs.inicio, antes: (t) async {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
      await esperar(t);
      await t.drag(find.byType(Scrollable).first, const Offset(0, -560));
      await esperar(t);
    });
  });
  testWidgets('03-inicio oscuro', (t) async {
    SharedPreferences.setMockInitialValues({});
    await servicioConCaja(t);
    await capturarNs(t, '03-inicio', const PantallaInicioNs(), barra: PestaniaNs.inicio, oscuro: true);
  });
  testWidgets('45-notificaciones', (t) async {
    await capturarNs(t, '45-notificaciones', const PantallaNotificacionesNs());
  });
  testWidgets('42-buscador-inicio', (t) async {
    await capturarNs(t, '42-buscador-inicio', const PantallaBuscadorNs(origen: PestaniaNs.inicio));
  });

  // ───────── Vender ─────────
  List<LineaVenta> tresLineas() => [
        const LineaVentaPorUnidad(productoId: 'a', nombreProducto: 'Cerveza lata 473 ml', proveedorId: null, cantidad: 2, precioUnitarioCentavos: 210000),
        const LineaVentaPesable(productoId: 'b', nombreProducto: 'Jamón cocido', proveedorId: null, gramos: 250, precioPorKiloCentavos: 1460000),
        const LineaVentaPorUnidad(productoId: 'c', nombreProducto: 'Pan lactal grande', proveedorId: null, cantidad: 3, precioUnitarioCentavos: 280000),
      ];

  testWidgets('05-vender-vacio', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(t, '05-vender-vacio', PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: []), barra: PestaniaNs.vender);
  });
  testWidgets('15-vender-caja-cerrada', (t) async {
    final servicio = await servicioConCaja(t, abrir: false);
    await capturarNs(t, '15-vender-caja-cerrada', PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: []), controlador: ControladorFalsoNs(abierta: false), barra: PestaniaNs.vender);
  });
  testWidgets('07-vender-carrito', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(t, '07-vender-carrito', PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: tresLineas()), barra: PestaniaNs.vender);
  });
  testWidgets('07-vender-carrito oscuro', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(t, '07-vender-carrito', PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: tresLineas()), barra: PestaniaNs.vender, oscuro: true);
  });
  testWidgets('08-vender-carrito-descuento', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(
      t,
      '08-vender-carrito-descuento',
      PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: tresLineas()),
      barra: PestaniaNs.vender,
      antes: (t) async {
        await t.tap(find.text('Descuento'));
        await esperar(t);
        await t.tap(find.text('Porcentaje'));
        await esperar(t);
        await t.enterText(find.byType(TextField).last, '10');
        await esperar(t);
        await t.tap(find.text('Listo'));
        await esperar(t);
      },
    );
  });
  testWidgets('08b-descuento-libre', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(
      t,
      '08b-descuento-libre',
      PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: tresLineas()),
      barra: PestaniaNs.vender,
      antes: (t) async {
        await t.tap(find.text('Descuento'));
        await esperar(t);
        await t.tap(find.text('Porcentaje'));
        await esperar(t);
        await t.enterText(find.byType(TextField).last, '12,5');
        await esperar(t);
      },
    );
  });
  testWidgets('08c-cantidad-exacta-gramos', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(
      t,
      '08c-cantidad-exacta-gramos',
      PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: tresLineas()),
      barra: PestaniaNs.vender,
      antes: (t) async {
        await t.tap(find.text('250 g'));
        await esperar(t);
        await t.enterText(find.byType(TextField).last, '320');
        await esperar(t);
      },
    );
  });
  testWidgets('08d-quitar-linea-deshacer', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(
      t,
      '08d-quitar-linea-deshacer',
      PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: tresLineas()),
      barra: PestaniaNs.vender,
      antes: (t) async {
        await t.tap(find.text('Quitar del carrito').last);
        await esperar(t);
      },
    );
    await t.pump(const Duration(seconds: 6));
  });
  Future<PuertoLocal> servicioConEncargues(WidgetTester t) async {
    final servicio = await servicioConCaja(t);
    final provs = (await t.runAsync(() => servicio.proveedores()))!;
    final pan = (await t.runAsync(() => servicio.crearProducto(nombre: 'Pan lactal grande', esPesable: false, stock: 20, proveedorId: provs[0].id, usuarioId: 1, precioCentavos: 280000)))!;
    final fact = (await t.runAsync(() => servicio.crearProducto(nombre: 'Facturas (docena)', esPesable: false, stock: 20, proveedorId: provs[0].id, usuarioId: 1, precioCentavos: 650000)))!;
    await t.runAsync(() => servicio.crearEncargue(nombreCliente: 'Marta Gómez', usuarioId: 1, lineas: [ApartadoCompanion(productoId: pan, cantidad: 2), ApartadoCompanion(productoId: fact, cantidad: 1)]));
    await t.runAsync(() => servicio.crearEncargue(nombreCliente: 'Kiosco de la esquina', usuarioId: 1, lineas: [ApartadoCompanion(productoId: pan, cantidad: 5)]));
    return servicio;
  }
  testWidgets('08e-entregar-encargue-lista', (t) async {
    final servicio = await servicioConEncargues(t);
    await capturarNs(
      t,
      '08e-entregar-encargue-lista',
      PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: []),
      barra: PestaniaNs.vender,
      antes: (t) async {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await esperar(t);
        await t.tap(find.text('Entregar un encargue'));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
        await esperar(t);
      },
    );
  });
  testWidgets('08f-encargue-cargado', (t) async {
    final servicio = await servicioConEncargues(t);
    await capturarNs(
      t,
      '08f-encargue-cargado',
      PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: []),
      barra: PestaniaNs.vender,
      antes: (t) async {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await esperar(t);
        await t.tap(find.text('Entregar un encargue'));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
        await esperar(t);
        await t.tap(find.text('Marta Gómez'));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await esperar(t);
      },
    );
    await t.pump(const Duration(seconds: 4));
  });
  Future<void> irACobro(WidgetTester t, {String? medio}) async {
    await t.tap(find.text('Cobrar'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await esperar(t);
    if (medio != null) {
      await t.tap(find.text(medio));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await esperar(t);
    }
  }

  Future<void> terminarTest(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(minutes: 11));
  }

  testWidgets('09-cobro-efectivo', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(
      t,
      '09-cobro-efectivo',
      PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: tresLineas()),
      antes: (t) async {
        await irACobro(t);
        await t.tap(find.text('\$\u00A020.000'));
        await esperar(t);
      },
    );
  });
  testWidgets('09b-cobro-caramelo', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(
      t,
      '09b-cobro-caramelo',
      PantallaCarritoVenta(
        cliente: null,
        servicio: servicio,
        usuarioId: 1,
        carrito: [
          const LineaVentaPorUnidad(productoId: 'a', nombreProducto: 'Agua mineral 1,5 L', proveedorId: null, cantidad: 1, precioUnitarioCentavos: 120000),
          const LineaVentaPorUnidad(productoId: 'b', nombreProducto: 'Yerba 1 kg', proveedorId: null, cantidad: 1, precioUnitarioCentavos: 460000),
        ],
      ),
      antes: (t) async {
        await irACobro(t);
        await t.enterText(find.byType(TextField).last, '5900');
        await esperar(t);
      },
    );
  });
  testWidgets('10-cobro-credito', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(t, '10-cobro-credito', PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: tresLineas()), antes: (t) => irACobro(t, medio: 'Tarjeta de crédito (1 pago)'));
  });
  testWidgets('11-cobro-qr', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(t, '11-cobro-qr', PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: tresLineas()), antes: (t) => irACobro(t, medio: 'QR de Mercado Pago'));
  });

  // Estados de la terminal: la hoja "Cobrar por …" sobre la pantalla de Cobrar.
  Future<void> capturarTerminal(WidgetTester t, String nombre, String medio, PuertoLocal servicio, {Future<void> Function(WidgetTester)? despues}) async {
    await capturarNs(
      t,
      nombre,
      PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: tresLineas()),
      antes: (t) async {
        await irACobro(t, medio: medio);
        await t.tap(find.textContaining('Confirmar cobro'));
        await t.pump(const Duration(milliseconds: 100));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await t.pump(const Duration(seconds: 3));
        if (despues != null) await despues(t);
        await esperar(t);
      },
    );
    await terminarTest(t);
  }

  Future<_PuertoPosnet> terminal(WidgetTester t, {ResultadoOrdenCobro estado = ResultadoOrdenCobro.pendiente, bool nuncaCrea = false, Object? falloAlCrear, Object? falloAlGuardar, Object? falloAlAnotar, Object? falloAlListar, bool conHistorial = false}) async {
    await servicioConCaja(t);
    return _PuertoPosnet(baseLocalCompanion(), estado: estado, nuncaCrea: nuncaCrea, falloAlCrear: falloAlCrear, falloAlGuardar: falloAlGuardar, falloAlAnotar: falloAlAnotar, falloAlListar: falloAlListar, conHistorial: conHistorial);
  }

  testWidgets('11b-cobro-terminal-enviando', (t) async {
    await capturarTerminal(t, '11b-cobro-terminal-enviando', 'QR de Mercado Pago', await terminal(t, nuncaCrea: true));
  });
  testWidgets('12-terminal-esperando', (t) async {
    await capturarTerminal(t, '12-terminal-esperando', 'QR de Mercado Pago', await terminal(t));
  });
  testWidgets('12b-terminal-cliente-confirma', (t) async {
    await capturarTerminal(t, '12b-terminal-cliente-confirma', 'Tarjeta de débito', await terminal(t, estado: ResultadoOrdenCobro.confirmarEnTerminal));
  });
  testWidgets('13-terminal-rechazado', (t) async {
    await capturarTerminal(t, '13-terminal-rechazado', 'Tarjeta de débito', await terminal(t, estado: ResultadoOrdenCobro.rechazada));
  });
  testWidgets('13c-terminal-sin-sin-conexion', (t) async {
    await capturarTerminal(t, '13c-terminal-sin-conexion', 'QR de Mercado Pago', await terminal(t, falloAlCrear: const SocketException('x')));
  });
  testWidgets('13d-terminal-cobrado-sin-guardar', (t) async {
    await capturarTerminal(
      t,
      '13d-terminal-cobrado-sin-guardar',
      'Tarjeta de débito',
      await terminal(t, estado: ResultadoOrdenCobro.aprobada, falloAlGuardar: const ErrorCompanion(500, 'la caja no respondió.')),
    );
  });
  testWidgets('14-venta-cobrada', (t) async {
    final servicio = await terminal(t);
    await capturarNs(
      t,
      '14-venta-cobrada',
      PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: tresLineas()),
      antes: (t) async {
        await irACobro(t);
        await t.tap(find.text('\$\u00A020.000'));
        await esperar(t);
        await t.tap(find.textContaining('Confirmar cobro'));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
        await t.pump(const Duration(milliseconds: 1500));
      },
    );
  });
  testWidgets('14b-venta-cobrada-a-mano', (t) async {
    final servicio = await terminal(t);
    await capturarNs(
      t,
      '14b-venta-cobrada-a-mano',
      PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: tresLineas()),
      antes: (t) async {
        await irACobro(t, medio: 'QR de Mercado Pago');
        await t.tap(find.text('Cobrar a mano (sin terminal)'));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
        await t.pump(const Duration(milliseconds: 1500));
      },
    );
  });

  // ───────── Caja ─────────
  testWidgets('29-caja-resumen', (t) async {
    await capturarNs(t, '29-caja-resumen', const PantallaCajaNs(), barra: PestaniaNs.caja);
  });
  testWidgets('29-caja-resumen oscuro', (t) async {
    await capturarNs(t, '29-caja-resumen', const PantallaCajaNs(), barra: PestaniaNs.caja, oscuro: true);
  });

  testWidgets('31-caja-ventas', (t) async {
    await servicioConCaja(t);
    final c = ControladorFalsoNs()..segmentoCaja.value = 2;
    await capturarNs(t, '31-caja-ventas', const PantallaCajaNs(), controlador: c, barra: PestaniaNs.caja);
  });
  testWidgets('18-gasto-ingreso', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(t, '18-gasto-ingreso', const PantallaMovimientoCaja(), controlador: ControladorConServicio(servicio), barra: null);
  });
  testWidgets('18b-gasto-lata', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(
      t,
      '18b-gasto-lata',
      const PantallaMovimientoCaja(),
      controlador: ControladorConServicio(servicio),
      barra: null,
      antes: (t) async {
        await t.tap(find.text('Lata cigarrillos'));
        await t.enterText(find.byType(TextField).first, '3500');
        await t.pump();
        await t.enterText(find.byType(TextField).last, 'Compra de cambio');
        await esperar(t);
      },
    );
  });
  testWidgets('18c-gasto-caja-cerrada', (t) async {
    final servicio = await servicioConCaja(t, abrir: false);
    await capturarNs(
      t,
      '18c-gasto-caja-cerrada',
      const PantallaMovimientoCaja(),
      controlador: ControladorConServicio(servicio, abierta: false),
      barra: null,
      antes: (t) async {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await esperar(t);
        await t.enterText(find.byType(TextField).first, '30000');
        await esperar(t);
      },
    );
  });
  testWidgets('18d-gasto-error-pc', (t) async {
    final servicio = await terminal(t, falloAlAnotar: const ErrorCompanion(409, 'La caja ya se cerró, este gasto no se guardó'));
    await capturarNs(
      t,
      '18d-gasto-error-pc',
      const PantallaMovimientoCaja(),
      controlador: ControladorConServicio(servicio),
      barra: null,
      antes: (t) async {
        await t.enterText(find.byType(TextField).first, '3500');
        await esperar(t);
        await t.tap(find.text('Anotar gasto'));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await esperar(t);
      },
    );
  });
  testWidgets('17-consultar-precio', (t) async {
    await servicioConCaja(t);
    await capturarNs(t, '17-consultar-precio', const PantallaConsultarPrecio());
  });
  testWidgets('32b-contar-la-caja-2-horas', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(
      t,
      '32b-contar-la-caja-2-horas',
      const PantallaCajaNs(),
      controlador: ControladorConServicio(servicio),
      barra: PestaniaNs.caja,
      antes: (t) async {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await esperar(t);
        await t.tap(find.text('Contar la caja'));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await esperar(t);
      },
    );
  });
  testWidgets('32c-contar-la-caja-cerrada', (t) async {
    final servicio = await servicioConCaja(t, abrir: false);
    await capturarNs(
      t,
      '32c-contar-la-caja-cerrada',
      const PantallaCajaNs(),
      controlador: ControladorConServicio(servicio, abierta: false),
      barra: PestaniaNs.caja,
      antes: (t) async {
        await t.tap(find.text('Contar la caja'));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await esperar(t);
      },
    );
  });
  testWidgets('33-cerrar-caja-etapa1', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(t, '33-cerrar-caja-etapa1', PantallaCierreNs(servicio: servicio, usuarioId: 1));
  });
  Finder campoDe(String etiqueta) => find.descendant(of: find.ancestor(of: find.text(etiqueta), matching: find.byType(CampoNs)).first, matching: find.byType(TextField));
  Future<void> irAEtapa2(WidgetTester t) async {
    await t.enterText(find.byType(TextField).first, '252600');
    await esperar(t);
    await t.tap(find.text('Confirmar conteo'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await esperar(t);
  }
  testWidgets('34-cerrar-caja-etapa2', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(t, '34-cerrar-caja-etapa2', PantallaCierreNs(servicio: servicio, usuarioId: 1), antes: (t) async {
      await irAEtapa2(t);
      await t.enterText(campoDe('MP contado (según la app de Mercado Pago)'), '250800');
      await esperar(t);
    });
  });
  testWidgets('34b-cerrar-caja-etapa2-resultado', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(t, '34b-cerrar-caja-etapa2-resultado', PantallaCierreNs(servicio: servicio, usuarioId: 1), antes: (t) async {
      await irAEtapa2(t);
      await t.enterText(campoDe('MP contado (según la app de Mercado Pago)'), '250800');
      await t.pump();
      await t.enterText(campoDe('Lata contada'), '42000');
      await esperar(t);
    });
  });
  testWidgets('35-cerrar-caja-cerrada', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(t, '35-cerrar-caja-cerrada', PantallaCierreNs(servicio: servicio, usuarioId: 1), antes: (t) async {
      await irAEtapa2(t);
      await t.enterText(campoDe('MP contado (según la app de Mercado Pago)'), '250800');
      await t.pump();
      await t.enterText(campoDe('Lata contada'), '42000');
      await esperar(t);
      await t.tap(find.text('Cerrar caja').last);
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await esperar(t);
    });
    await t.pump(const Duration(seconds: 6));
  });


  // ───────── Productos ─────────
  Future<PuertoLocal> conCatalogo(WidgetTester t) async {
    final servicio = await servicioConCaja(t);
    final provs = (await t.runAsync(() => servicio.proveedores()))!;
    Future<void> crear(String nombre, int precio, int stock, {bool peso = false, int prov = 0}) => servicio.crearProducto(
          nombre: nombre,
          esPesable: peso,
          precioCentavos: peso ? null : precio * 100,
          costoCentavos: peso ? null : precio * 70,
          precioPorKiloCentavos: peso ? precio * 100 : null,
          costoPorKiloCentavos: peso ? precio * 70 : null,
          stock: peso ? 0 : stock,
          stockGramos: peso ? stock : null,
          proveedorId: provs[prov].id,
          usuarioId: 1,
        );
    await t.runAsync(() async {
      await crear('Cerveza lata 473 ml', 2100, 48);
      await crear('Gaseosa cola 2,25 L', 2900, 4);
      await crear('Agua mineral 1,5 L', 1200, 30);
      await crear('Alfajor triple', 1200, 0);
      await crear('Pan lactal grande', 2800, 14, prov: 1);
      await crear('Jamón cocido', 14600, 3200, peso: true, prov: 1);
    });
    return servicio;
  }

  testWidgets('19-productos', (t) async {
    final servicio = await conCatalogo(t);
    await capturarNs(t, '19-productos', const PantallaProductosNs(), controlador: ControladorConServicio(servicio), barra: PestaniaNs.productos, antes: (t) async {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
      await esperar(t);
    });
  });
  testWidgets('05b-vender-buscando-con-teclado', (t) async {
    final servicio = await conCatalogo(t);
    // Sin barra: con el teclado abierto el menú la esconde (acá la captura no pasa por el menú).
    await capturarNs(t, '05b-vender-buscando-con-teclado', PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: tresLineas()), antes: (t) async {
      // Teclado de Android abierto: ~300 de alto en un celular de 844.
      t.view.viewInsets = const FakeViewPadding(bottom: 300 * 2);
      await t.enterText(find.byType(TextField).first, 'a');
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await esperar(t);
    });
  });
  testWidgets('05c-vender-carrito-con-teclado', (t) async {
    final servicio = await conCatalogo(t);
    await capturarNs(t, '05c-vender-carrito-con-teclado', PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: tresLineas()), antes: (t) async {
      t.view.viewInsets = const FakeViewPadding(bottom: 300 * 2);
      await t.tap(find.byType(TextField).first);
      await esperar(t);
    });
  });
  testWidgets('23-controlar-stock', (t) async {
    final servicio = await conCatalogo(t);
    final c = ControladorConServicio(servicio)..productosEnConteo.value = true;
    await capturarNs(t, '23-controlar-stock', const PantallaProductosNs(), controlador: c, barra: PestaniaNs.productos, antes: (t) async {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
      await esperar(t);
    });
  });
  testWidgets('24-conteo-por-proveedor', (t) async {
    await conCatalogo(t);
    await capturarNs(t, '24-conteo-por-proveedor', const PantallaConteoStock(), antes: (t) async {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));
      await esperar(t);
    });
  });
  testWidgets('28-producto-nuevo', (t) async {
    final servicio = await conCatalogo(t);
    final provs = (await t.runAsync(() => servicio.proveedores()))!;
    final cats = (await t.runAsync(() => servicio.categorias()))!;
    await capturarNs(t, '28-producto-nuevo', PantallaFormularioProducto(cliente: servicio, usuarioId: 1, proveedores: provs, categorias: cats));
  });

  /// Los chips de filtro viajan en una fila que se desliza: se la corre hasta que el chip pedido se vea y se lo toca.
  Future<void> tocarChip(WidgetTester t, String texto) async {
    bool visible() => find.text(texto).evaluate().isNotEmpty && t.getCenter(find.text(texto).first).dx < 360;
    for (var i = 0; i < 8 && !visible(); i++) {
      await t.drag(find.byType(FilaChipsNs).first, const Offset(-250, 0));
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.tap(find.text(texto));
  }

  Future<void> esperarCarga(WidgetTester t) async {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await esperar(t);
  }
  testWidgets('19d-productos-de-un-proveedor', (t) async {
    final servicio = await conCatalogo(t);
    final provs = (await t.runAsync(() => servicio.proveedores()))!;
    await capturarNs(t, '19d-productos-de-un-proveedor', const PantallaProductosNs(), controlador: ControladorConServicio(servicio), barra: PestaniaNs.productos, antes: (t) async {
      await esperarCarga(t);
      await tocarChip(t, provs[1].nombre);
      await esperar(t);
    });
  });
  testWidgets('19e-productos-sin-resultados', (t) async {
    final servicio = await conCatalogo(t);
    await capturarNs(t, '19e-productos-sin-resultados', const PantallaProductosNs(), controlador: ControladorConServicio(servicio), barra: PestaniaNs.productos, antes: (t) async {
      await esperarCarga(t);
      await t.enterText(find.byType(TextField).first, 'zzz');
      await esperar(t);
    });
  });
  testWidgets('19g-productos-error-de-red', (t) async {
    final servicio = await terminal(t, falloAlListar: const SocketException('x'));
    await capturarNs(t, '19g-productos-error-de-red', const PantallaProductosNs(), controlador: ControladorConServicio(servicio), barra: PestaniaNs.productos, antes: esperarCarga);
  });
  testWidgets('21-productos-elegir-varios', (t) async {
    final servicio = await conCatalogo(t);
    await capturarNs(t, '21-productos-elegir-varios', const PantallaProductosNs(), controlador: ControladorConServicio(servicio), barra: null, antes: (t) async {
      await esperarCarga(t);
      await t.tap(find.text('Elegir varios'));
      await esperar(t);
      await t.tap(find.text('Agua mineral 1,5 L'));
      await t.tap(find.text('Pan lactal grande'));
      await esperar(t);
    });
  });
  Future<void> abrirLote(WidgetTester t, PuertoLocal servicio) async {
    final provs = (await t.runAsync(() => servicio.proveedores()))!;
    await esperarCarga(t);
    await tocarChip(t, provs[0].nombre);
    await esperar(t);
    await t.tap(find.text('Elegir varios'));
    await esperar(t);
    await t.tap(find.text('Cerveza lata 473 ml'));
    await t.tap(find.text('Agua mineral 1,5 L'));
    await esperar(t);
    await t.tap(find.text('Editar (2)'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await esperar(t);
  }
  testWidgets('26-lote-proveedor-subio-precio', (t) async {
    final servicio = await conCatalogo(t);
    await capturarNs(t, '26-lote-proveedor-subio-precio', const PantallaProductosNs(), controlador: ControladorConServicio(servicio), barra: null, antes: (t) async {
      await abrirLote(t, servicio);
      await t.enterText(find.byType(TextField).last, '10');
      await esperar(t);
    });
  });
  testWidgets('27-lote-confirmar-cambio', (t) async {
    final servicio = await conCatalogo(t);
    await capturarNs(t, '27-lote-confirmar-cambio', const PantallaProductosNs(), controlador: ControladorConServicio(servicio), barra: null, antes: (t) async {
      await abrirLote(t, servicio);
      await t.enterText(find.byType(TextField).last, '10');
      await esperar(t);
      await t.tap(find.text('Revisar'));
      await esperar(t);
    });
  });
  testWidgets('28b-producto-nuevo-ganancia', (t) async {
    final servicio = await conCatalogo(t);
    final provs = (await t.runAsync(() => servicio.proveedores()))!;
    final cats = (await t.runAsync(() => servicio.categorias()))!;
    await capturarNs(t, '28b-producto-nuevo-ganancia', PantallaFormularioProducto(cliente: servicio, usuarioId: 1, proveedores: provs, categorias: cats), antes: (t) async {
      await t.enterText(find.byType(TextField).at(0), 'Alfajor triple');
      await t.pump();
      await t.enterText(campoDe('Precio de venta'), '1200');
      await t.pump();
      await t.enterText(campoDe('Lo que te cuesta'), '800');
      await esperar(t);
    });
  });
  testWidgets('31-historial-hoy', (t) async {
    final servicio = await terminal(t, conHistorial: true);
    final c = ControladorConServicio(servicio)..segmentoCaja.value = 2;
    await capturarNs(t, '31-historial-hoy', const PantallaCajaNs(), controlador: c, barra: PestaniaNs.caja, antes: (t) async {
      await esperarCarga(t);
      await t.tap(find.text('Venta #0140'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await esperar(t);
    });
  });
  testWidgets('31e-historial-anular-venta', (t) async {
    final servicio = await terminal(t, conHistorial: true);
    final c = ControladorConServicio(servicio)..segmentoCaja.value = 2;
    await capturarNs(t, '31e-historial-anular-venta', const PantallaCajaNs(), controlador: c, barra: PestaniaNs.caja, antes: (t) async {
      await esperarCarga(t);
      await t.tap(find.text('Venta #0143'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await esperar(t);
      await t.tap(find.text('Anular venta'));
      await esperar(t);
      await t.enterText(find.byType(TextField).last, 'Error de carga');
      await esperar(t);
    });
  });
  testWidgets('30-caja-separar', (t) async {
    await servicioConCaja(t);
    final c = ControladorFalsoNs()..segmentoCaja.value = 1;
    await capturarNs(t, '30-caja-separar', const PantallaCajaNs(), controlador: c, barra: PestaniaNs.caja, antes: esperarCarga);
  });

  testWidgets('39b-dias-historicos-vacio', (t) async {
    SharedPreferences.setMockInitialValues({'companion_usuario_id': 1, 'companion_usuario_nombre': 'Ana'});
    await servicioConCaja(t);
    await capturarNs(t, '39b-dias-historicos-vacio', const PantallaCargaHistorica(), antes: esperarCarga);
  });
  testWidgets('40-nuevo-dia-fecha', (t) async {
    SharedPreferences.setMockInitialValues({'companion_usuario_id': 1, 'companion_usuario_nombre': 'Ana'});
    await servicioConCaja(t);
    await capturarNs(t, '40-nuevo-dia-fecha', const PantallaCargaHistorica(), antes: (t) async {
      await esperarCarga(t);
      await t.tap(find.text('Nuevo día'));
      await esperar(t);
    });
  });

  Future<AppDatabase> conProveedores(WidgetTester t) async {
    SharedPreferences.setMockInitialValues({'companion_usuario_id': 1, 'companion_usuario_nombre': 'Ana'});
    final db = (await t.runAsync(() async => baseDeTest()))!;
    await t.runAsync(() async {
      final usuario = (await db.select(db.usuarios).get()).first.id;
      final provs = await db.select(db.proveedores).get();
      await (db.update(db.proveedores)..where((p) => p.id.equals(provs[0].id))).write(const ProveedoresCompanion(diaPedido: Value('Martes'), diaEntrega: Value('Jueves'), whatsapp: Value('294 412-3456'), medioPago: Value('Transferencia')));
      await (db.update(db.proveedores)..where((p) => p.id.equals(provs[1].id))).write(const ProveedoresCompanion(diaPedido: Value('Lunes')));
      await cargarDeuda(db, proveedorId: provs[0].id, montoCentavos: 18450000, fecha: DateTime(2026, 10, 7), nota: 'Factura 0003-2214', usuarioId: usuario);
      await cargarDeuda(db, proveedorId: provs[1].id, montoCentavos: 4200000, fecha: DateTime(2026, 10, 8), nota: 'Remito 88', usuarioId: usuario);
    });
    return db;
  }

  testWidgets('46-proveedores', (t) async {
    final db = await conProveedores(t);
    await capturarNs(t, '46-proveedores', PantallaProveedores(db: db, usuarioId: 1), antes: esperarCarga);
  });
  testWidgets('46b-proveedor-ficha', (t) async {
    final db = await conProveedores(t);
    final p = (await t.runAsync(() => db.select(db.proveedores).get()))!.first;
    await capturarNs(t, '46b-proveedor-ficha', PantallaProveedor(db: db, proveedor: p, usuarioId: 1), antes: esperarCarga);
  });
  testWidgets('46c-proveedor-nuevo', (t) async {
    final db = await conProveedores(t);
    await capturarNs(t, '46c-proveedor-nuevo', PantallaFormularioProveedor(db: db), antes: esperarCarga);
  });

  testWidgets('37-mas', (t) async {
    await capturarNs(t, '37-mas', const PantallaMasNs(), barra: PestaniaNs.mas);
  });
  testWidgets('37-mas oscuro', (t) async {
    await capturarNs(t, '37-mas', const PantallaMasNs(), barra: PestaniaNs.mas, oscuro: true);
  });
  testWidgets('09-cobro-efectivo oscuro', (t) async {
    final servicio = await servicioConCaja(t);
    await capturarNs(
      t,
      '09-cobro-efectivo',
      PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: 1, carrito: tresLineas()),
      oscuro: true,
      antes: (t) async {
        await t.tap(find.text('Cobrar'));
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
        await esperar(t);
        await t.tap(find.text('\$\u00A020.000'));
        await esperar(t);
      },
    );
  });

  AsistenteNegocio asistente({PasoNegocio paso = PasoNegocio.negocio}) => AsistenteNegocio(
        pasoInicial: paso,
        alGuardarNegocio: (_, _) async {},
        alEscanear: (_) async => '7798123400055',
        alGuardarProducto: (_) async {},
        alAbrirWeb: (_) {},
        alTerminar: (_, _) {},
        categoriasExistentes: const ['Golosinas', 'Bebidas', 'Lácteos'],
      );

  testWidgets('02m-asistente-1-negocio', (t) async {
    await capturarNs(t, '02m-asistente-1-negocio', asistente());
  });
  testWidgets('02n-asistente-1-rubro', (t) async {
    await capturarNs(t, '02n-asistente-1-rubro', asistente(), antes: (t) async {
      await t.enterText(find.byType(TextField).first, 'Almacén Don Pepe');
      await t.pump();
      await t.tap(find.byKey(const Key('rubro-kiosco')));
      await esperar(t);
      await t.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await esperar(t);
    });
  });
  testWidgets('02o-asistente-2-escanear', (t) async {
    await capturarNs(t, '02o-asistente-2-escanear', asistente(paso: PasoNegocio.producto));
  });
  testWidgets('02p-asistente-2-completar', (t) async {
    await capturarNs(t, '02p-asistente-2-completar', asistente(paso: PasoNegocio.producto), antes: (t) async {
      await t.tap(find.byKey(const Key('asistente-escanear')));
      await esperar(t);
    });
  });
  testWidgets('02r-asistente-3-cobros', (t) async {
    await capturarNs(t, '02r-asistente-3-cobros', asistente(paso: PasoNegocio.cobros));
  });
  testWidgets('04d-inicio-pendiente-del-asistente', (t) async {
    SharedPreferences.setMockInitialValues({'companion_configuracion_pendiente': ['producto', 'cobros']});
    await servicioConCaja(t);
    addTearDown(() => pasosPendientesNegocio.value = {});
    await capturarNs(t, '04d-inicio-pendiente-del-asistente', const PantallaInicioNs(), barra: PestaniaNs.inicio, antes: (t) async {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await esperar(t);
    });
  });
  testWidgets('41-actualizar-app', (t) async {
    await capturarNs(
      t,
      '41-actualizar-app',
      Builder(builder: (context) => Center(child: TextButton(onPressed: () => mostrarHojaActualizar(context, descargar: () async => File('x'), instalar: (_) async {}), child: const Text('abrir')))),
      antes: (t) async {
        await t.tap(find.text('abrir'));
        await esperar(t);
      },
    );
  });
}

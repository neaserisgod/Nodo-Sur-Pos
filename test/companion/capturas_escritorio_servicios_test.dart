// Capturas de Nodo Sur Servicios con ventana de compu (Windows y navegador ancho, `docs/PLAN-ESCRITORIO-SERVICIOS.md`): el menú
// lateral, la Agenda con el turno elegido al costado y Cobrar con el cobro a la derecha, a 1440×900. Guardan PNG en
// `capturas/servicios-escritorio/` (ignorada por git). No comparan píxeles: fallan si una pantalla no se dibuja o desborda.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/app_ns.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/kit/kit_ns.dart';
import 'package:la_plazoleta/companion/modo_uso.dart';
import 'package:la_plazoleta/companion/pantalla_carrito_venta.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_agenda_ns.dart';
import 'package:la_plazoleta/companion/puerto_local.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart';
import 'package:la_plazoleta/data/repositorio_turnos.dart';
import 'package:la_plazoleta/domain/forma_de_trabajo.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/domain/turnos.dart';
import 'package:la_plazoleta/domain/venta.dart';
import 'package:la_plazoleta/servicios/modulos_activos.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';
import '../helpers/capturas.dart';
import '../helpers/controlador_falso_ns.dart';

final _clave = GlobalKey();

/// Sin PC: la Agenda se usa en "Solo celular" (con la PC muestra un aviso en vez de la agenda).
class _SoloCelular extends ControladorFalsoNs {
  @override
  ModoUso? get modoUso => ModoUso.soloCelular;
}

Future<void> _cargarFigtree() async {
  final cargador = FontLoader('Figtree');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    cargador.addFont(rootBundle.load('fonts/Figtree-$f.ttf'));
  }
  await cargador.load();
}

Future<void> _esperar(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _guardar(WidgetTester tester, String nombre, {bool oscuro = false}) async {
  await tester.runAsync(() async {
    final limite = _clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final imagen = await limite.toImage(pixelRatio: 1);
    final bytes = await imagen.toByteData(format: ui.ImageByteFormat.png);
    final archivo = File('capturas/servicios-escritorio/$nombre${oscuro ? '-oscuro' : ''}.png');
    await archivo.create(recursive: true);
    await archivo.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late int usuario;
  final hoy = DateTime.now();
  final dia = DateTime(hoy.year, hoy.month, hoy.day);
  const todosLosDias = HorarioAtencion({
    1: (desdeMin: 540, hastaMin: 1200),
    2: (desdeMin: 540, hastaMin: 1200),
    3: (desdeMin: 540, hastaMin: 1200),
    4: (desdeMin: 540, hastaMin: 1200),
    5: (desdeMin: 540, hastaMin: 1200),
    6: (desdeMin: 540, hastaMin: 1200),
    7: (desdeMin: 540, hastaMin: 1200),
  });

  Future<void> sembrar(WidgetTester tester) async {
    await _cargarFigtree();
    SharedPreferences.setMockInitialValues({});
    modulosActuales.value = const ModulosNegocio({}, forma: FormaDeTrabajo.servicios);
    await tester.runAsync(() async {
      db = baseDeTest();
      usarBaseLocalDeTest(db);
      usuario = (await db.select(db.usuarios).get()).first.id;
      await guardarConfigAgenda(db, const ConfigAgenda(horario: todosLosDias));
      final semi = await crearServicio(db, nombre: 'Semipermanente manos', precioCentavos: 1800000, duracionMinutos: 60, usuarioId: usuario);
      final escul = await crearServicio(db, nombre: 'Esculpidas en polygel', precioCentavos: 3200000, duracionMinutos: 120, pideSena: true, usuarioId: usuario);
      final retiro = await crearServicio(db, nombre: 'Retiro', precioCentavos: 600000, duracionMinutos: 20, usuarioId: usuario);
      await crearServicio(db, nombre: 'Perfilado + tinte de cejas', precioCentavos: 900000, duracionMinutos: 30, usuarioId: usuario);
      await crearProductoDeVenta(db, nombre: 'Aceite de cutículas 10 ml', precioCentavos: 550000, costoCentavos: 250000, stockInicial: 9, usuarioId: usuario);
      await crearTurno(db, servicioId: retiro, inicio: dia.add(const Duration(hours: 9)), nombreCliente: 'Martina R.', telefono: '2944 154218', usuarioId: usuario);
      await crearTurno(db, servicioId: semi, inicio: dia.add(const Duration(hours: 11)), nombreCliente: 'Lucía P.', telefono: '2944 152778', usuarioId: usuario);
      await crearTurno(db, servicioId: escul, inicio: dia.add(const Duration(hours: 13, minutes: 30)), nombreCliente: 'Flor D.',
          usuarioId: usuario, estado: EstadoTurno.esperandoSena, origen: 'BOT', senaVence: dia.add(const Duration(days: 1)));
      await crearTurno(db, servicioId: semi, inicio: dia.add(const Duration(hours: 17)), nombreCliente: 'Juli S.', usuarioId: usuario);
    });
    addTearDown(() => tester.runAsync(db.close));
    addTearDown(() => modulosActuales.value = ModulosNegocio.todosActivos);
  }

  /// La disposición de la compu tal como la arma `PantallaMenuCompanion` con la ventana ancha.
  Future<void> abrir(WidgetTester tester, PestaniaNs activa, Widget pantalla, {bool oscuro = false}) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      key: _clave,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: TemaCompanion.claro,
        darkTheme: TemaCompanion.oscuro,
        themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
        home: AppNs(
          controlador: _SoloCelular(),
          version: 0,
          child: Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MenuLateralNs(activa: activa, onSeleccionar: (_) {}),
                Expanded(child: ConMenuLateralNs(child: pantalla)),
              ],
            ),
          ),
        ),
      ),
    ));
    await _esperar(tester);
  }

  for (final oscuro in temasDeCaptura) {
    final s = oscuro ? ' (oscuro)' : '';
    testWidgets('agenda con el turno al costado$s', (tester) async {
      await sembrar(tester);
      await abrir(tester, PestaniaNs.inicio, PantallaAgendaNs(db: db, usuarioId: usuario), oscuro: oscuro);
      expect(find.text('Elegí un turno de la lista para ver el detalle y qué hacer con él.'), findsOneWidget);
      await _guardar(tester, 'agenda-vacia', oscuro: oscuro);
      await tester.tap(find.text('Lucía P.').first);
      await _esperar(tester);
      // El detalle y los botones del turno quedan en el panel, sin hoja.
      expect(find.text('Escribirle por WhatsApp'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      await _guardar(tester, 'agenda', oscuro: oscuro);
    });
    testWidgets('cobrar con el cobro a la derecha$s', (tester) async {
      await sembrar(tester);
      final servicio = PuertoLocal(baseLocalCompanion());
      await tester.runAsync(() => servicio.abrirSesion(usuarioId: usuario, fondoInicialCentavos: 0));
      final carrito = <LineaVenta>[];
      await abrir(tester, PestaniaNs.vender, PantallaCarritoVenta(cliente: null, servicio: servicio, usuarioId: usuario, carrito: carrito), oscuro: oscuro);
      expect(find.text('Tocá un servicio o un producto para sumarlo.'), findsOneWidget);
      await tester.tap(find.text('Semipermanente manos').first);
      await _esperar(tester);
      await _guardar(tester, 'cobrar', oscuro: oscuro);
    });
  }
}

// Capturas de Nodo Sur Servicios para revisar el diseño a ojo (revisión del 2026-10-14): Agenda con turnos en cada estado,
// Servicios e insumos, el creador de servicio, la configuración de la Agenda y las hojas de turno. Guardan PNG en
// `capturas/servicios/` (ignorada por git). No comparan píxeles: fallan si una pantalla no se dibuja o desborda.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/bienvenida/vista_entrar_con_google.dart';
import 'package:la_plazoleta/companion/configurar/asistente_negocio.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_agenda_ns.dart';
import 'package:la_plazoleta/edicion.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_config_agenda_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_servicios_ns.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart';
import 'package:la_plazoleta/data/repositorio_turnos.dart';
import 'package:la_plazoleta/domain/forma_de_trabajo.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/domain/servicios.dart';
import 'package:la_plazoleta/domain/turnos.dart';
import 'package:la_plazoleta/servicios/modulos_activos.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';
import '../helpers/capturas.dart';

final _clave = GlobalKey();

Future<void> _cargarFigtree() async {
  final cargador = FontLoader('Figtree');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    cargador.addFont(rootBundle.load('fonts/Figtree-$f.ttf'));
  }
  await cargador.load();
}

Future<void> _abrir(WidgetTester tester, Widget pantalla, {bool oscuro = false}) async {
  tester.view.physicalSize = const Size(390 * 2, 844 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RepaintBoundary(
    key: _clave,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: TemaCompanion.claro,
      darkTheme: TemaCompanion.oscuro,
      themeMode: oscuro ? ThemeMode.dark : ThemeMode.light,
      home: pantalla,
    ),
  ));
  await _esperar(tester);
}

Future<void> _esperar(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _guardar(WidgetTester tester, String nombre, {bool oscuro = false}) async {
  await tester.runAsync(() async {
    final limite = _clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final imagen = await limite.toImage(pixelRatio: 2);
    final bytes = await imagen.toByteData(format: ui.ImageByteFormat.png);
    final archivo = File('capturas/servicios/$nombre${oscuro ? '-oscuro' : ''}.png');
    await archivo.create(recursive: true);
    await archivo.writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
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
    6: (desdeMin: 600, hastaMin: 1080),
    7: null,
  });

  Future<void> sembrar(WidgetTester tester) async {
    await _cargarFigtree();
    SharedPreferences.setMockInitialValues({});
    modulosActuales.value = const ModulosNegocio({}, forma: FormaDeTrabajo.servicios);
    await tester.runAsync(() async {
      db = baseDeTest();
      usuario = (await db.select(db.usuarios).get()).first.id;
      await guardarConfigAgenda(db, const ConfigAgenda(horario: todosLosDias));
      final top = await crearInsumo(db, nombre: 'Top coat', unidad: UnidadInsumo.ml, contenidoEnvaseMilesimas: 15000, costoEnvaseCentavos: 1100000,
          stockMinimoMilesimas: 5000, stockInicialMilesimas: 3000, usuarioId: usuario);
      await crearInsumo(db, nombre: 'Guantes de nitrilo talle M (caja x 100)', unidad: UnidadInsumo.u, contenidoEnvaseMilesimas: 100000,
          costoEnvaseCentavos: 900000, stockInicialMilesimas: 64000, usuarioId: usuario);
      final semi = await crearServicio(db, nombre: 'Esmaltado semipermanente con diseño', precioCentavos: 1800000, duracionMinutos: 90,
          pideSena: true, receta: [(insumoId: top, milesimas: 500)], usuarioId: usuario);
      final corte = await crearServicio(db, nombre: 'Corte', precioCentavos: 850000, duracionMinutos: 30, usuarioId: usuario);
      await crearTurno(db, servicioId: corte, inicio: dia.add(const Duration(hours: 9)), nombreCliente: 'Lucía Fernández', telefono: '2944 111111', usuarioId: usuario);
      await crearTurno(db, servicioId: semi, inicio: dia.add(const Duration(hours: 10)), nombreCliente: 'María José de los Ángeles Rodríguez',
          usuarioId: usuario, estado: EstadoTurno.esperandoSena, origen: 'BOT', senaVence: dia.add(const Duration(days: 2)));
      final dejo = await crearTurno(db, servicioId: semi, inicio: dia.add(const Duration(hours: 12)), nombreCliente: 'Ana', usuarioId: usuario);
      await registrarSenaDeTurno(db, dejo, montoCentavos: 540000, esEfectivo: true, usuarioId: usuario);
      final novino = await crearTurno(db, servicioId: corte, inicio: dia.add(const Duration(hours: 15)), nombreCliente: 'Pedro', usuarioId: usuario);
      await marcarNoVino(db, novino);
      await crearTurno(db, servicioId: corte, inicio: dia.add(const Duration(hours: 18, minutes: 30)), nombreCliente: 'Sobreturno', usuarioId: usuario);
    });
    addTearDown(() => tester.runAsync(db.close));
    addTearDown(() => modulosActuales.value = ModulosNegocio.todosActivos);
  }

  for (final oscuro in temasDeCaptura) {
    final s = oscuro ? ' (oscuro)' : '';
    testWidgets('agenda$s', (tester) async {
      await sembrar(tester);
      await _abrir(tester, Scaffold(body: PantallaAgendaNs(db: db, usuarioId: usuario)), oscuro: oscuro);
      await _guardar(tester, 'agenda', oscuro: oscuro);
      await tester.tap(find.byKey(const Key('agenda_nuevo')));
      await _esperar(tester);
      await _guardar(tester, 'agenda-nuevo-turno', oscuro: oscuro);
    });
    testWidgets('servicios$s', (tester) async {
      await sembrar(tester);
      await _abrir(tester, Scaffold(body: PantallaServiciosNs(db: db, usuarioId: usuario)), oscuro: oscuro);
      await _guardar(tester, 'servicios', oscuro: oscuro);
    });
    testWidgets('editor de servicio$s', (tester) async {
      await sembrar(tester);
      await _abrir(tester, PantallaEditorServicioNs(db: db, usuarioId: usuario), oscuro: oscuro);
      await _guardar(tester, 'editor-servicio', oscuro: oscuro);
    });
    testWidgets('entrar con google$s', (tester) async {
      await _cargarFigtree();
      edicionActual = Edicion.servicios;
      addTearDown(() => edicionActual = Edicion.almacen);
      await _abrir(tester, VistaEntrarConGoogle(alEntrar: () {}, trabajando: false, error: null), oscuro: oscuro);
      await _guardar(tester, 'entrar-google', oscuro: oscuro);
    });
    testWidgets('configurá tu negocio$s', (tester) async {
      await _cargarFigtree();
      edicionActual = Edicion.servicios;
      addTearDown(() => edicionActual = Edicion.almacen);
      Widget asistente(PasoNegocio paso) => AsistenteNegocio(
            key: ValueKey(paso),
            pasoInicial: paso,
            nombreInicial: 'Barbería Lucho',
            alGuardarNegocio: (_, _) async {},
            alEscanear: (_) async => null,
            alGuardarProducto: (_) async {},
            alGuardarServicio: (_) async {},
            alAbrirWeb: (_) {},
            alTerminar: (_, _) {},
          );
      for (final paso in PasoNegocio.values) {
        await _abrir(tester, asistente(paso), oscuro: oscuro);
        await _guardar(tester, 'asistente-${paso.name}', oscuro: oscuro);
      }
    });
    testWidgets('configuración de la agenda$s', (tester) async {
      await sembrar(tester);
      await _abrir(tester, PantallaConfigAgendaNs(db: db), oscuro: oscuro);
      await _guardar(tester, 'config-agenda', oscuro: oscuro);
    });
  }
}

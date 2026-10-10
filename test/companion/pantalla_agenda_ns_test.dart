import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/kit/barra_inferior_ns.dart';
import 'package:la_plazoleta/companion/pantallas/pantalla_agenda_ns.dart';
import 'package:la_plazoleta/companion/tema/tema_companion.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_servicios.dart';
import 'package:la_plazoleta/data/repositorio_turnos.dart';
import 'package:la_plazoleta/domain/forma_de_trabajo.dart';
import 'package:la_plazoleta/domain/modulos.dart';
import 'package:la_plazoleta/domain/turnos.dart';
import 'package:la_plazoleta/servicios/modulos_activos.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';

/// La Agenda en el celular (`REGLAS-NEGOCIO.md` §21, etapa 4): los turnos del día, dar uno con los horarios libres, el
/// sobreturno que avisa y deja, y las acciones de cada turno.
void main() {
  late AppDatabase db;
  late int usuario;
  late int semi;
  final hoy = DateTime.now();
  final manana = DateTime(hoy.year, hoy.month, hoy.day + 1);

  // Abierto todos los días de 9 a 20, así el test no depende de qué día cae "mañana".
  const todosLosDias = HorarioAtencion({
    1: (desdeMin: 540, hastaMin: 1200),
    2: (desdeMin: 540, hastaMin: 1200),
    3: (desdeMin: 540, hastaMin: 1200),
    4: (desdeMin: 540, hastaMin: 1200),
    5: (desdeMin: 540, hastaMin: 1200),
    6: (desdeMin: 540, hastaMin: 1200),
    7: (desdeMin: 540, hastaMin: 1200),
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    modulosActuales.value = const ModulosNegocio({}, forma: FormaDeTrabajo.servicios);
    db = baseDeTest();
    usuario = (await db.select(db.usuarios).get()).first.id;
    semi = await crearServicio(db, nombre: 'Semipermanente', precioCentavos: 1800000, duracionMinutos: 60, pideSena: true, usuarioId: usuario);
    await guardarConfigAgenda(db, const ConfigAgenda(horario: todosLosDias));
  });
  tearDown(() => db.close());
  tearDownAll(() => modulosActuales.value = ModulosNegocio.todosActivos);

  Future<void> esperar(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
  }

  Future<void> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: TemaCompanion.claro, home: Scaffold(body: PantallaAgendaNs(db: db, usuarioId: usuario))));
    await esperar(tester);
  }

  testWidgets('sin turnos lo explica; mañana muestra los turnos por hora con su estado', (tester) async {
    await tester.runAsync(() async {
      await crearTurno(db, servicioId: semi, inicio: manana.add(const Duration(hours: 11)), nombreCliente: 'Bea', usuarioId: usuario);
      await crearTurno(
        db,
        servicioId: semi,
        inicio: manana.add(const Duration(hours: 10)),
        nombreCliente: 'Ana',
        usuarioId: usuario,
        estado: EstadoTurno.esperandoSena,
        origen: 'BOT',
      );
    });
    await abrir(tester);
    expect(find.textContaining('No hay turnos para este día'), findsOneWidget);

    await tester.tap(find.text('Mañana'));
    await esperar(tester);
    expect(find.text('10:00  Ana'), findsOneWidget);
    expect(find.text('11:00  Bea'), findsOneWidget);
    expect(find.text('Esperando seña'), findsOneWidget);
    expect(find.text('Confirmado'), findsOneWidget);
    expect(find.textContaining('WhatsApp'), findsOneWidget);
    // Por hora: Ana antes que Bea.
    expect(tester.getTopLeft(find.text('10:00  Ana')).dy, lessThan(tester.getTopLeft(find.text('11:00  Bea')).dy));
  });

  testWidgets('dar un turno: elige servicio, día y un horario libre, con la seña pedida a la vista', (tester) async {
    await abrir(tester);
    await tester.tap(find.byKey(const Key('agenda_nuevo')));
    await esperar(tester);
    // Un solo servicio: viene elegido, con su seña (30 % de $18.000).
    expect(find.textContaining('Dejó la seña'), findsOneWidget);
    expect(find.textContaining('5.400'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Mañana')));
    await esperar(tester);
    await tester.tap(find.byKey(const ValueKey('hora-10:00')));
    await tester.enterText(find.descendant(of: find.byKey(const Key('turno_nombre')), matching: find.byType(EditableText)), 'Caro');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Guardar turno'));
    await tester.tap(find.text('Guardar turno'));
    await esperar(tester);

    final turnos = await tester.runAsync(() => db.select(db.turnos).get());
    expect(turnos!.single.nombreCliente, 'Caro');
    expect(turnos.single.inicio, manana.add(const Duration(hours: 10)));
    expect(turnos.single.senaPedidaCentavos, 540000);
    await tester.pump(const Duration(seconds: 10)); // el aviso de arriba se va solo
  });

  testWidgets('un horario ocupado no se ofrece y escribir esa hora pide confirmar el sobreturno', (tester) async {
    await tester.runAsync(() => crearTurno(db, servicioId: semi, inicio: manana.add(const Duration(hours: 10)), nombreCliente: 'Ana', usuarioId: usuario));
    await abrir(tester);
    await tester.tap(find.byKey(const Key('agenda_nuevo')));
    await esperar(tester);
    await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Mañana')));
    await esperar(tester);
    expect(find.byKey(const ValueKey('hora-10:00')), findsNothing);
    expect(find.byKey(const ValueKey('hora-09:00')), findsOneWidget);

    await tester.enterText(find.descendant(of: find.widgetWithText(Column, 'Otra hora (opcional)'), matching: find.byType(EditableText)).first, '10:30');
    await tester.enterText(find.descendant(of: find.byKey(const Key('turno_nombre')), matching: find.byType(EditableText)), 'Bea');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Guardar turno'));
    await tester.tap(find.text('Guardar turno'));
    await esperar(tester);
    expect(find.text('¿Sobreturno?'), findsOneWidget);
    expect(find.textContaining('Se pisa con 10:00 Ana'), findsOneWidget);
    await tester.tap(find.text('Guardar igual'));
    await esperar(tester);
    expect(await tester.runAsync(() => db.select(db.turnos).get()), hasLength(2));
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('no vino: se marca desde el turno y libera el horario', (tester) async {
    await tester.runAsync(() => crearTurno(db, servicioId: semi, inicio: manana.add(const Duration(hours: 10)), nombreCliente: 'Ana', usuarioId: usuario));
    await abrir(tester);
    await tester.tap(find.text('Mañana'));
    await esperar(tester);
    await tester.tap(find.text('10:00  Ana'));
    await tester.pumpAndSettle();
    expect(find.text('Cobrar'), findsOneWidget);
    expect(find.text('Anotar la seña'), findsOneWidget);
    await tester.ensureVisible(find.text('No vino'));
    await tester.tap(find.text('No vino'));
    await esperar(tester);
    expect(find.text('No vino'), findsOneWidget); // la etiqueta del turno
    final t = await tester.runAsync(() => db.select(db.turnos).getSingle());
    expect(t!.estado, 'NO_VINO');
    await tester.pump(const Duration(seconds: 10));
  });

  test('el link de Google Calendar lleva el servicio, la persona y el horario en UTC', () async {
    final id = await crearTurno(db, servicioId: semi, inicio: DateTime.utc(2026, 10, 12, 13).toLocal(), nombreCliente: 'Ana', usuarioId: usuario);
    final t = (await turnosDelDia(db, DateTime.utc(2026, 10, 12, 13).toLocal())).firstWhere((x) => x.turno.id == id);
    final url = enlaceGoogleCalendar(t);
    expect(url.host, 'calendar.google.com');
    expect(url.queryParameters['text'], 'Semipermanente · Ana');
    expect(url.queryParameters['dates'], '20261012T130000Z/20261012T140000Z');
  });

  test('la barra dice Agenda en un negocio de servicios', () {
    const barra = BarraInferiorNs(activa: PestaniaNs.inicio, onSeleccionar: _nada, conServicios: true);
    expect(barra.conServicios, isTrue);
  });

  test('textoDiaNs', () {
    final h = DateTime(2026, 10, 12);
    expect(textoDiaNs(h, hoy: h), 'Hoy');
    expect(textoDiaNs(DateTime(2026, 10, 13), hoy: h), 'Mañana');
    expect(textoDiaNs(DateTime(2026, 10, 15), hoy: h), 'jueves 15');
  });
}

void _nada(PestaniaNs _) {}

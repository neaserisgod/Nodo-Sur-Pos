import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/pdf_planilla.dart';
import 'package:la_plazoleta/data/repositorio_equilibrio.dart';

import '../helpers/planilla_fixture.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Bruno'));
  });
  tearDown(() => db.close());

  test('genera un PDF real a partir de un día cargado', () async {
    final sesionId = await cargarDiaHistoricoFixture(
      db,
      fecha: DateTime(2026, 8, 20),
      usuarioId: usuarioId,
      cajaInicialNormalCentavos: 15000000,
      cajaInicialCigarrillosCentavos: 0,
      efectivoRealContadoCentavos: 15050000,
      mpContadoCentavos: 0,
      renglonesEfectivo: [RenglonPlanillaFixture(montoCentavos: 50000, detalle: 'Fiambre 300g')],
      renglonesMp: const [],
      gastos: const [],
    );

    final bytes = await generarPdfPlanilla(db, sesionId);

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  // El paquete `pdf` no deja extraer texto legible de los bytes generados
  // (fuentes con glyphs propios, sin mapeo Unicode directo — confirmado a
  // mano: ni "RETIRO" ni ningún texto plano aparece en los bytes crudos).
  // Por eso estos dos tests solo confirman que ambas ramas generan un PDF
  // válido sin fallar — la rama que realmente importa (que el total sea
  // verificable sumando lo impreso) ya está probada donde se calcula:
  // `test/domain/retiro_test.dart` y `test/data/repositorio_equilibrio_test.dart`.
  test('con la opción de fijos pendientes apagada (default), genera el PDF sin fallar', () async {
    final mesAnio = '2026-08';
    for (final c in await db.select(db.gastosFijos).get()) {
      await cargarMontoDelMes(db, gastoFijoId: c.id, mesAnio: mesAnio, montoCentavos: 100000);
    }
    final sesionId = await cargarDiaHistoricoFixture(
      db,
      fecha: DateTime(2026, 8, 20),
      usuarioId: usuarioId,
      cajaInicialNormalCentavos: 15000000,
      cajaInicialCigarrillosCentavos: 0,
      efectivoRealContadoCentavos: 15050000,
      mpContadoCentavos: 0,
      renglonesEfectivo: [RenglonPlanillaFixture(montoCentavos: 50000, detalle: 'Fiambre 300g')],
      renglonesMp: const [],
      gastos: const [],
    );

    final bytes = await generarPdfPlanilla(db, sesionId);

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('con la opción de fijos pendientes prendida, genera el PDF sin fallar', () async {
    final mesAnio = '2026-08';
    for (final c in await db.select(db.gastosFijos).get()) {
      await cargarMontoDelMes(db, gastoFijoId: c.id, mesAnio: mesAnio, montoCentavos: 100000);
    }
    await db
        .update(db.configuracionTabla)
        .write(const ConfiguracionTablaCompanion(retiroDescuentaFijosPendientes: Value(true)));
    final sesionId = await cargarDiaHistoricoFixture(
      db,
      fecha: DateTime(2026, 8, 20),
      usuarioId: usuarioId,
      cajaInicialNormalCentavos: 15000000,
      cajaInicialCigarrillosCentavos: 0,
      efectivoRealContadoCentavos: 15050000,
      mpContadoCentavos: 0,
      renglonesEfectivo: [RenglonPlanillaFixture(montoCentavos: 50000, detalle: 'Fiambre 300g')],
      renglonesMp: const [],
      gastos: const [],
    );

    final bytes = await generarPdfPlanilla(db, sesionId);

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('nombreArchivoPlanilla incluye fecha y hora de apertura', () {
    expect(
      nombreArchivoPlanilla(DateTime(2026, 8, 20, 14, 30)),
      'control_caja_2026-08-20_1430.pdf',
    );
  });

  test('dos turnos el mismo día generan archivos distintos, ninguno pisa al otro', () async {
    final carpeta = await Directory.systemTemp.createTemp('pdf_planilla_test_');
    addTearDown(() => carpeta.delete(recursive: true));

    Future<int> abrirSesionA(DateTime fechaApertura) => db.into(db.sesionesDeCaja).insert(
          SesionesDeCajaCompanion.insert(
            usuarioAbrioId: usuarioId,
            fondoInicialCentavos: 0,
            fechaApertura: Value(fechaApertura),
          ),
        );

    final turnoManiana = await abrirSesionA(DateTime(2026, 8, 20, 8, 0));
    final turnoTarde = await abrirSesionA(DateTime(2026, 8, 20, 14, 30));

    final rutaManiana = await guardarPdfPlanilla(db, sesionId: turnoManiana, carpetaDestino: carpeta.path);
    final rutaTarde = await guardarPdfPlanilla(db, sesionId: turnoTarde, carpetaDestino: carpeta.path);

    expect(rutaManiana, isNot(equals(rutaTarde)));
    expect(File(rutaManiana).existsSync(), isTrue);
    expect(File(rutaTarde).existsSync(), isTrue);
  });

  test('guardarPdfPlanilla escribe el archivo real en la carpeta indicada', () async {
    final carpeta = await Directory.systemTemp.createTemp('pdf_planilla_test_');
    addTearDown(() => carpeta.delete(recursive: true));

    final sesionId = await cargarDiaHistoricoFixture(
      db,
      fecha: DateTime(2026, 8, 20),
      usuarioId: usuarioId,
      cajaInicialNormalCentavos: 0,
      cajaInicialCigarrillosCentavos: 0,
      efectivoRealContadoCentavos: 0,
      mpContadoCentavos: 0,
      renglonesEfectivo: const [],
      renglonesMp: const [],
      gastos: const [],
    );

    final ruta = await guardarPdfPlanilla(db, sesionId: sesionId, carpetaDestino: carpeta.path);

    expect(File(ruta).existsSync(), isTrue);
    expect(ruta, endsWith('control_caja_2026-08-20_0000.pdf'));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_medios_pago.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = baseDeTest();
  });
  tearDown(() => db.close());

  test('listarMediosDePago trae los 2 sembrados', () async {
    final medios = await listarMediosDePago(db);
    expect(medios.map((m) => m.nombre), containsAll(['Efectivo', 'Mercado Pago']));
  });

  test('renombrarMedioDePago cambia el nombre sin tocar esEfectivo', () async {
    final efectivo = (await listarMediosDePago(db)).firstWhere((m) => m.esEfectivo);

    await renombrarMedioDePago(db, efectivo.id, 'Contado');

    final actualizado = (await listarMediosDePago(db)).firstWhere((m) => m.id == efectivo.id);
    expect(actualizado.nombre, 'Contado');
    expect(actualizado.esEfectivo, isTrue);
  });

  test('renombrarMedioDePago al mismo nombre que ya tiene no falla', () async {
    final efectivo = (await listarMediosDePago(db)).firstWhere((m) => m.esEfectivo);

    await renombrarMedioDePago(db, efectivo.id, efectivo.nombre);

    final actualizado = (await listarMediosDePago(db)).firstWhere((m) => m.id == efectivo.id);
    expect(actualizado.nombre, efectivo.nombre);
  });

  test('renombrarMedioDePago no deja pisar el nombre del otro medio', () async {
    final medios = await listarMediosDePago(db);
    final efectivo = medios.firstWhere((m) => m.esEfectivo);
    final mp = medios.firstWhere((m) => !m.esEfectivo);

    expect(
      () => renombrarMedioDePago(db, efectivo.id, mp.nombre),
      throwsArgumentError,
    );

    // No se tocó nada: sigue con su nombre original.
    final sinCambios = (await listarMediosDePago(db)).firstWhere((m) => m.id == efectivo.id);
    expect(sinCambios.nombre, efectivo.nombre);
  });

  test('desactivarMedioDePago y activarMedioDePago alternan sin borrar', () async {
    final mp = (await listarMediosDePago(db)).firstWhere((m) => !m.esEfectivo);

    await desactivarMedioDePago(db, mp.id);
    expect((await listarMediosDePago(db)).firstWhere((m) => m.id == mp.id).activo, isFalse);

    await activarMedioDePago(db, mp.id);
    expect((await listarMediosDePago(db)).firstWhere((m) => m.id == mp.id).activo, isTrue);
  });
}

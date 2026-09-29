import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_gastos.dart';
import 'package:la_plazoleta/data/repositorio_ingresos.dart';
import 'package:la_plazoleta/data/repositorio_movimientos_caja.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Bruno'));
    sesionId = await abrirSesion(db, usuarioId: usuarioId, fondoInicialCentavos: 0);
  });
  tearDown(() => db.close());

  DateTime hoy() {
    final a = DateTime.now();
    return DateTime(a.year, a.month, a.day);
  }

  test('lista gastos e ingresos con su caja, medio y quién; sin las ventas', () async {
    await registrarGastoRapido(db, sesionCajaId: sesionId, usuarioId: usuarioId, montoCentavos: 350000, medio: MedioGasto.cajonNormal, motivo: 'Flete');
    await registrarIngresoRapido(db, sesionCajaId: sesionId, usuarioId: usuarioId, montoCentavos: 100000, medio: MedioGasto.mercadoPago);
    await registrarGastoRapido(db, sesionCajaId: sesionId, usuarioId: usuarioId, montoCentavos: 20000, medio: MedioGasto.lata);
    final cajaNormal = await (db.select(db.cajas)..where((c) => c.esLata.equals(false))).getSingle();
    await db.into(db.movimientosDeCaja).insert(
          MovimientosDeCajaCompanion.insert(sesionCajaId: sesionId, cajaId: cajaNormal.id, usuarioId: usuarioId, tipo: 'VENTA', montoCentavos: 99900),
        );

    final lista = await movimientosDeCaja(db, desde: hoy(), hasta: hoy().add(const Duration(days: 1)));

    expect(lista, hasLength(3));
    expect(lista.any((m) => m.tipo == 'VENTA'), isFalse);
    final flete = lista.firstWhere((m) => m.nota == 'Flete');
    expect(flete.esSalida, isTrue);
    expect(flete.esLata, isFalse);
    expect(flete.usuario, 'Bruno');
    final ingreso = lista.firstWhere((m) => m.tipo == 'INGRESO');
    expect(ingreso.esSalida, isFalse);
    expect(ingreso.esMercadoPago, isTrue);
    expect(lista.firstWhere((m) => m.montoCentavos == 20000).esLata, isTrue);
  });

  test('respeta el período', () async {
    await registrarGastoRapido(db, sesionCajaId: sesionId, usuarioId: usuarioId, montoCentavos: 350000, medio: MedioGasto.cajonNormal);
    final ayer = hoy().subtract(const Duration(days: 1));
    expect(await movimientosDeCaja(db, desde: ayer, hasta: hoy()), isEmpty);
  });
}

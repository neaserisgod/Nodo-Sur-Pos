import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_cierre.dart';
import 'package:la_plazoleta/data/repositorio_deuda_proveedores.dart';
import 'package:la_plazoleta/data/repositorio_equilibrio.dart';
import 'package:la_plazoleta/data/repositorio_faltantes.dart';
import 'package:la_plazoleta/data/repositorio_rentabilidad.dart';
import 'package:la_plazoleta/data/repositorio_ventas.dart';
import 'package:la_plazoleta/domain/faltantes_cierre.dart';
import '../helpers/base_para_tests.dart';

void main() {
  late AppDatabase db;
  late int usuarioId;
  late int sesionId;

  // El cajón, Mercado Pago y la lata arrancan con $100.000 cada uno; se cuentan $80.000: faltan $20.000 en cada caja.
  const inicial = 10000000;
  const contado = 8000000;
  const falta = 2000000;

  setUp(() async {
    db = baseDeTest();
    usuarioId = await db.into(db.usuarios).insert(UsuariosCompanion.insert(nombre: 'Dueño'));
    sesionId = await abrirSesion(
      db,
      usuarioId: usuarioId,
      fondoInicialCentavos: inicial,
      mpInicialCentavos: inicial,
      lataInicialCentavos: inicial,
    );
  });
  tearDown(() => db.close());

  Future<ResumenCierre> resumen() => calcularResumenCierre(
        db,
        sesionId: sesionId,
        efectivoContadoCentavos: contado,
        mpContadoCentavos: contado,
        lataContadoCentavos: contado,
      );

  Future<void> anotar(CajaDelCierre caja, DestinoFaltante destino, {int? proveedorId, int? gastoFijoId}) => anotarFaltante(
        db,
        sesionCajaId: sesionId,
        usuarioId: usuarioId,
        caja: caja,
        montoCentavos: falta,
        destino: destino,
        proveedorId: proveedorId,
        gastoFijoId: gastoFijoId,
      );

  test('antes de anotar, faltan \$20.000 en cada caja', () async {
    final r = await resumen();
    expect(r.diferenciaCentavos, -falta);
    expect(r.mpDiferenciaCentavos, -falta);
    expect(r.lataDiferenciaCentavos, -falta);
  });

  test('gasto mío: un RETIRO que deja cada caja en cero y cuenta como "ya retirado" en Equilibrio', () async {
    for (final caja in CajaDelCierre.values) {
      await anotar(caja, DestinoFaltante.gastoMio);
    }
    final r = await resumen();
    expect(r.diferenciaCentavos, 0);
    expect(r.mpDiferenciaCentavos, 0);
    expect(r.lataDiferenciaCentavos, 0);

    final estado = await estadoDeResultadosDelMes(db, mesAnioDe(DateTime.now()));
    expect(estado.retirosDelMesCentavos, falta * 3);
  });

  test('gasto del negocio: deja la caja en cero', () async {
    await anotar(CajaDelCierre.mercadoPago, DestinoFaltante.negocio);
    expect((await resumen()).mpDiferenciaCentavos, 0);
  });

  test('proveedor: deja la caja en cero y baja lo que se le debe', () async {
    final serra = await db.into(db.proveedores).insert(ProveedoresCompanion.insert(codigo: 'SE', nombre: 'Serra'));
    await anotar(CajaDelCierre.efectivo, DestinoFaltante.proveedor, proveedorId: serra);
    expect((await resumen()).diferenciaCentavos, 0);
    expect(await saldoDeuda(db, serra), 0); // sin deuda previa: el pago queda como cargo y pago, no como saldo a favor
  });

  test('fijo: deja Mercado Pago en cero y el fijo queda pagado ese mes', () async {
    final luz = (await (db.select(db.gastosFijos)..where((g) => g.nombre.equals('Luz'))).getSingle()).id;
    await anotar(CajaDelCierre.mercadoPago, DestinoFaltante.fijo, gastoFijoId: luz);
    expect((await resumen()).mpDiferenciaCentavos, 0);
    expect((await pagadoPorConceptoDelMes(db, mesAnioDe(DateTime.now())))[luz], falta);
  });

  test('un fijo no se paga desde la lata', () async {
    final luz = (await (db.select(db.gastosFijos)..where((g) => g.nombre.equals('Luz'))).getSingle()).id;
    expect(destinoPosible(DestinoFaltante.fijo, CajaDelCierre.lata), isFalse);
    await expectLater(anotar(CajaDelCierre.lata, DestinoFaltante.fijo, gastoFijoId: luz), throwsArgumentError);
  });

  test('proveedor o fijo sin elegir cuál: no graba nada', () async {
    await expectLater(anotar(CajaDelCierre.efectivo, DestinoFaltante.proveedor), throwsArgumentError);
    await expectLater(anotar(CajaDelCierre.efectivo, DestinoFaltante.fijo), throwsArgumentError);
    expect((await resumen()).diferenciaCentavos, -falta);
  });
}

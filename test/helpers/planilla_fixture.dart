// Fixture de prueba: arma un día cerrado con renglones sueltos de texto
// libre (sin pasar por un producto real del catálogo), tal como hacía la
// pantalla de carga histórica por planilla (fase 9) antes de reemplazarse
// por la carga con carrito de producto real (`lib/data/repositorio_carga_historica.dart`).
//
// Se movió acá (fuera de `lib/`) porque dejó de ser una pantalla real de la
// app, pero varios tests de OTRAS features (planilla PDF, editor de venta,
// detalle de día) todavía necesitan poder armar un día cerrado con renglones
// de texto libre — más flexible que un carrito real — sin que esos tests
// tengan que saber nada de productos/stock.

import 'package:drift/drift.dart';
import 'package:la_plazoleta/data/database.dart';
import 'package:la_plazoleta/data/repositorio_cierre.dart';

class RenglonPlanillaFixture {
  final int montoCentavos;
  final String detalle;
  final DateTime? hora;
  final int? proveedorId;
  final bool esCigarrillo;
  final int? costoCentavos;

  const RenglonPlanillaFixture({
    required this.montoCentavos,
    required this.detalle,
    this.hora,
    this.proveedorId,
    this.esCigarrillo = false,
    this.costoCentavos,
  });
}

class GastoPlanillaFixture {
  final int montoCentavos;
  final String motivo;
  final bool deLata;

  const GastoPlanillaFixture({
    required this.montoCentavos,
    required this.motivo,
    required this.deLata,
  });
}

Future<void> _cargarRenglon(
  AppDatabase db, {
  required RenglonPlanillaFixture renglon,
  required DateTime fecha,
  required int sesionId,
  required int usuarioId,
  required int medioPagoId,
  required bool esEfectivo,
  required Caja cajaNormal,
}) async {
  final fechaVenta = renglon.hora ?? fecha;
  final ventaId = await db.into(db.ventas).insert(
        VentasCompanion.insert(
          sesionCajaId: sesionId,
          usuarioId: usuarioId,
          fecha: Value(fechaVenta),
          subtotalCentavos: renglon.montoCentavos,
          totalCentavos: renglon.montoCentavos,
        ),
      );

  await db.into(db.lineasDeVenta).insert(
        LineasDeVentaCompanion.insert(
          ventaId: ventaId,
          nombreProductoFoto: renglon.detalle,
          proveedorIdFoto: Value(renglon.esCigarrillo ? null : renglon.proveedorId),
          tipoCigarrillo: Value(renglon.esCigarrillo ? 'atado' : 'ninguno'),
          precioUnitarioCentavos: renglon.montoCentavos,
          costoUnitarioCentavos: Value(renglon.costoCentavos),
        ),
      );

  await db.into(db.pagos).insert(
        PagosCompanion.insert(ventaId: ventaId, medioPagoId: medioPagoId, montoCentavos: renglon.montoCentavos),
      );

  if (esEfectivo) {
    await db.into(db.movimientosDeCaja).insert(
          MovimientosDeCajaCompanion.insert(
            sesionCajaId: sesionId,
            cajaId: cajaNormal.id,
            usuarioId: usuarioId,
            tipo: 'VENTA',
            montoCentavos: renglon.montoCentavos,
            ventaId: Value(ventaId),
            medioPagoId: Value(medioPagoId),
            fecha: Value(fechaVenta),
          ),
        );
  }
}

/// Arma un día completo con renglones de texto libre: crea la sesión ya
/// cerrada, sus ventas (una por renglón), sus gastos, y calcula/persiste el
/// arqueo con la misma fórmula que un cierre real. Solo para tests.
Future<int> cargarDiaHistoricoFixture(
  AppDatabase db, {
  required DateTime fecha,
  required int usuarioId,
  required int cajaInicialNormalCentavos,
  required int cajaInicialCigarrillosCentavos,
  required int efectivoRealContadoCentavos,
  required int mpContadoCentavos,
  required List<RenglonPlanillaFixture> renglonesEfectivo,
  required List<RenglonPlanillaFixture> renglonesMp,
  required List<GastoPlanillaFixture> gastos,
  int? lataContadoCentavos,
  String? nota,
}) {
  return db.transaction(() async {
    final medioEfectivo =
        await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(true))).getSingle();
    final medioVirtual =
        await (db.select(db.mediosDePago)..where((m) => m.esEfectivo.equals(false))).getSingle();
    final cajaNormal = await (db.select(db.cajas)..where((c) => c.esLata.equals(false))).getSingle();
    final cajaLata = await (db.select(db.cajas)..where((c) => c.esLata.equals(true))).getSingle();

    final sesionId = await db.into(db.sesionesDeCaja).insert(
          SesionesDeCajaCompanion.insert(
            fechaApertura: Value(fecha),
            usuarioAbrioId: usuarioId,
            fondoInicialCentavos: cajaInicialNormalCentavos,
            lataInicialCentavos: Value(cajaInicialCigarrillosCentavos),
          ),
        );

    for (final renglon in renglonesEfectivo) {
      await _cargarRenglon(
        db,
        renglon: renglon,
        fecha: fecha,
        sesionId: sesionId,
        usuarioId: usuarioId,
        medioPagoId: medioEfectivo.id,
        esEfectivo: true,
        cajaNormal: cajaNormal,
      );
    }
    for (final renglon in renglonesMp) {
      await _cargarRenglon(
        db,
        renglon: renglon,
        fecha: fecha,
        sesionId: sesionId,
        usuarioId: usuarioId,
        medioPagoId: medioVirtual.id,
        esEfectivo: false,
        cajaNormal: cajaNormal,
      );
    }

    for (final gasto in gastos) {
      await db.into(db.movimientosDeCaja).insert(
            MovimientosDeCajaCompanion.insert(
              sesionCajaId: sesionId,
              cajaId: gasto.deLata ? cajaLata.id : cajaNormal.id,
              usuarioId: usuarioId,
              tipo: 'GASTO',
              montoCentavos: gasto.montoCentavos,
              nota: Value(gasto.motivo),
              fecha: Value(fecha),
            ),
          );
    }

    final lataContado = lataContadoCentavos ??
        (await calcularResumenCierre(
          db,
          sesionId: sesionId,
          efectivoContadoCentavos: efectivoRealContadoCentavos,
          mpContadoCentavos: mpContadoCentavos,
        ))
            .lataFinalCentavos;

    await cerrarSesion(
      db,
      sesionId: sesionId,
      usuarioId: usuarioId,
      efectivoContadoCentavos: efectivoRealContadoCentavos,
      mpContadoCentavos: mpContadoCentavos,
      lataContadoCentavos: lataContado,
      nota: nota ?? 'Fixture de prueba',
      fechaCierre: fecha,
    );

    return sesionId;
  });
}

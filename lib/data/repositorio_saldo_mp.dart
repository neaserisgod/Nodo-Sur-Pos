// Lo que la app anotó por Mercado Pago en un turno que NO son ventas (gastos, pagos a proveedores, ingresos) y las devoluciones
// por ventas anuladas, para emparejarlo con los movimientos del reporte de Liquidaciones (`domain/saldo_mp.dart`).

import 'package:drift/drift.dart';

import '../domain/saldo_mp.dart';
import 'database.dart';
import 'repositorio_cierre.dart' show tiposEgresoDeCaja;

typedef MovimientosMpDelTurno = ({List<MovimientoMpEnApp> enApp, List<MovimientoMpEnApp> anuladas});

Future<MovimientosMpDelTurno> movimientosMpDelTurno(AppDatabase db, int sesionId) async {
  final m = db.movimientosDeCaja;
  final filas = await (db.select(m).join([
    innerJoin(db.mediosDePago, db.mediosDePago.id.equalsExp(m.medioPagoId)),
  ])..where(m.sesionCajaId.equals(sesionId) & db.mediosDePago.esEfectivo.equals(false) & m.tipo.isIn([...tiposEgresoDeCaja, 'INGRESO']))).get();

  final anuladas = await (db.select(db.pagos).join([
    innerJoin(db.ventas, db.ventas.id.equalsExp(db.pagos.ventaId)),
    innerJoin(db.mediosDePago, db.mediosDePago.id.equalsExp(db.pagos.medioPagoId)),
  ])..where(db.ventas.sesionCajaId.equals(sesionId) & db.ventas.anuladaEn.isNotNull() & db.mediosDePago.esEfectivo.equals(false))).get();

  return (
    enApp: [
      for (final f in filas)
        MovimientoMpEnApp(
          fecha: f.readTable(m).fecha,
          montoCentavos: f.readTable(m).montoCentavos,
          esSalida: tiposEgresoDeCaja.contains(f.readTable(m).tipo),
        ),
    ],
    anuladas: [
      for (final f in anuladas)
        MovimientoMpEnApp(
          fecha: f.readTable(db.ventas).anuladaEn ?? f.readTable(db.ventas).fecha,
          montoCentavos: f.readTable(db.pagos).montoCentavos,
          esSalida: true,
        ),
    ],
  );
}

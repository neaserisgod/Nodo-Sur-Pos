// Lista de los movimientos de caja para verlos uno por uno (El dueño,
// 2026-09-28: "revisá si hay un apartado para ver los movimientos, los
// movimientos de caja y eso" — no había: se registraban, pero solo se veían
// sumados en el cierre). Historial → Movimientos.
//
// Sin las ventas: cada venta ya tiene su lista (Historial → Ventas), y
// mezclarlas acá taparía los gastos y retiros entre cientos de cobros.

import 'package:drift/drift.dart';

import 'database.dart';
import 'repositorio_cierre.dart' show tiposEgresoDeCaja;

/// Los tipos que se listan — todo lo de `movimientos_de_caja` menos 'VENTA'.
const tiposMovimientoVisible = ['GASTO', 'INGRESO', 'PAGO_PROVEEDOR', 'RETIRO', 'DEVOLUCION_SENA'];

class MovimientoDeCaja {
  const MovimientoDeCaja({
    required this.id,
    required this.sesionCajaId,
    required this.fecha,
    required this.tipo,
    required this.montoCentavos,
    required this.esLata,
    required this.esMercadoPago,
    required this.usuario,
    this.proveedor,
    this.nota,
  });

  final int id;
  final int sesionCajaId;
  final DateTime fecha;

  /// 'GASTO' | 'INGRESO' | 'PAGO_PROVEEDOR' | 'RETIRO'.
  final String tipo;

  /// Siempre positivo en la base; el signo lo da el tipo ([esSalida]).
  final int montoCentavos;
  final bool esLata;
  final bool esMercadoPago;
  final String usuario;
  final String? proveedor;
  final String? nota;

  /// Misma lista que usa el arqueo para restar (Regla 3).
  bool get esSalida => tiposEgresoDeCaja.contains(tipo);
}

/// Los movimientos entre [desde] (incluido) y [hasta] (excluido), del más
/// nuevo al más viejo.
Future<List<MovimientoDeCaja>> movimientosDeCaja(
  AppDatabase db, {
  required DateTime desde,
  required DateTime hasta,
}) async {
  final m = db.movimientosDeCaja;
  final filas = await (db.select(m).join([
    innerJoin(db.cajas, db.cajas.id.equalsExp(m.cajaId)),
    leftOuterJoin(db.usuarios, db.usuarios.id.equalsExp(m.usuarioId)),
    leftOuterJoin(db.proveedores, db.proveedores.id.equalsExp(m.proveedorId)),
    leftOuterJoin(db.mediosDePago, db.mediosDePago.id.equalsExp(m.medioPagoId)),
  ])
        ..where(m.tipo.isIn(tiposMovimientoVisible) & m.fecha.isBiggerOrEqualValue(desde) & m.fecha.isSmallerThanValue(hasta))
        ..orderBy([OrderingTerm.desc(m.fecha), OrderingTerm.desc(m.id)]))
      .get();
  return [
    for (final f in filas)
      () {
        final mov = f.readTable(m);
        final medio = f.readTableOrNull(db.mediosDePago);
        return MovimientoDeCaja(
          id: mov.id,
          sesionCajaId: mov.sesionCajaId,
          fecha: mov.fecha,
          tipo: mov.tipo,
          montoCentavos: mov.montoCentavos,
          esLata: f.readTable(db.cajas).esLata,
          esMercadoPago: medio != null && !medio.esEfectivo,
          usuario: f.readTableOrNull(db.usuarios)?.nombre ?? '—',
          proveedor: f.readTableOrNull(db.proveedores)?.nombre,
          nota: mov.nota,
        );
      }(),
  ];
}

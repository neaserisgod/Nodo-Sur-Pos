// Devolverle al cliente lo cobrado por la Point al anular una venta (etapa B, el dueño 2026-10-04: "preguntar cada vez";
// devuelven el dueño y el encargado). Siempre por el servidor de Nodo Sur, con la cuenta vinculada a ESTE equipo: el sitio es
// el que sabe el rol de cada persona (la app no tiene roles propios todavía), así que un empleado no puede devolver aunque
// tenga la app abierta. Sin cuenta vinculada no se ofrece: se devuelve desde la app de Mercado Pago.
//
// Sirve igual en la PC (la orden está en su base) y en el celular (la orden está en la base de la PC o en la suya, según el
// modo): quien llama trae el [CobroPoint] de la venta.

import 'dart:async';

import '../data/database.dart';
import '../data/repositorio_cobro.dart';
import 'cuenta_nube.dart';
import 'registro_errores.dart';

/// Con qué orden de la Point se cobró una venta.
class CobroPoint {
  const CobroPoint({required this.ordenIdMp, required this.externalReference, required this.montoCentavos, required this.devuelta, this.ordenLocalId});
  final String ordenIdMp;
  final String externalReference;
  final int montoCentavos;
  final bool devuelta;

  /// La fila de `ordenes_cobro_pendientes` en la base de ESTE equipo, para anotarla como devuelta (null si la orden vive en
  /// la base de la PC: el sitio igual contesta "ya devuelta" si se intenta de nuevo).
  final int? ordenLocalId;

  factory CobroPoint.deOrden(OrdenCobroPendiente o) => CobroPoint(
    ordenIdMp: o.ordenIdMp!,
    externalReference: o.externalReference,
    montoCentavos: o.montoCentavos,
    devuelta: o.estado == 'devuelta',
    ordenLocalId: o.id,
  );

  Map<String, dynamic> toJson() => {
    'ordenIdMp': ordenIdMp,
    'externalReference': externalReference,
    'montoCentavos': montoCentavos,
    'devuelta': devuelta,
  };

  static CobroPoint? desdeJson(Map<String, dynamic> j) {
    final id = j['ordenIdMp'], ref = j['externalReference'], monto = j['montoCentavos'];
    if (id is! String || ref is! String || monto is! int) return null;
    return CobroPoint(ordenIdMp: id, externalReference: ref, montoCentavos: monto, devuelta: j['devuelta'] == true);
  }

  /// Clave de idempotencia de la devolución: fija por orden (la misma desde cualquier equipo), así un reintento nunca
  /// devuelve dos veces. Mercado Pago acepta letras, números y guiones, hasta 64.
  String get claveDevolucion {
    final base = 'devolver-$externalReference'.replaceAll(RegExp(r'[^\w-]'), '');
    return base.length > 64 ? base.substring(0, 64) : base;
  }
}

/// El cobro con la Point de una venta, de la base de este equipo.
Future<CobroPoint?> cobroPointDeVenta(AppDatabase db, int ventaId) async {
  final o = await ordenCobradaDeVenta(db, ventaId);
  return o == null ? null : CobroPoint.deOrden(o);
}

enum ResultadoDevolucionMp { devuelta, yaDevuelta, sinPermiso, noCobrada, error }

/// Si corresponde ofrecer la devolución: la venta se cobró con la Point, no se devolvió, este equipo está vinculado y quien
/// lo vinculó puede devolver. Nunca lanza: ante cualquier duda, no se ofrece (se puede devolver desde la app de Mercado Pago).
Future<bool> puedeOfrecerDevolucion(CobroPoint? cobro, {required AlmacenCuenta? almacen, required ClienteNube? cliente}) async {
  if (cobro == null || cobro.devuelta || almacen == null || cliente == null) return false;
  try {
    final cuenta = await almacen.leer();
    if (cuenta == null) return false;
    final estado = await cliente.estadoMp(cuenta.token);
    return estado.conectado && estado.puedeDevolver;
  } catch (e, st) {
    // Sin dato no se ofrece devolver (mejor no ofrecer que ofrecer de más), pero si no es solo falta de internet queda anotado.
    unawaited(registrarSiNoEsDeRed('Consultar si se puede devolver por Mercado Pago', e, st));
    return false;
  }
}

/// Devuelve y, si la orden vive en [db], la anota. "Ya estaba devuelta" también se anota: es la verdad en Mercado Pago.
Future<({ResultadoDevolucionMp resultado, String? mensaje})> devolverPorMp(
  CobroPoint cobro, {
  required AlmacenCuenta almacen,
  required ClienteNube cliente,
  AppDatabase? db,
}) async {
  Future<void> anotar() async {
    if (db != null && cobro.ordenLocalId != null) await marcarOrdenDevuelta(db, cobro.ordenLocalId!);
  }

  final cuenta = await almacen.leer();
  if (cuenta == null) {
    return (resultado: ResultadoDevolucionMp.error, mensaje: 'Este equipo ya no está vinculado a la cuenta');
  }
  try {
    await cliente.devolverOrdenPoint(cuenta.token, cobro.ordenIdMp, idempotencyKey: cobro.claveDevolucion);
    await anotar();
    return (resultado: ResultadoDevolucionMp.devuelta, mensaje: null);
  } on ErrorNube catch (e) {
    switch (e.codigo) {
      case 'ya_devuelta':
        await anotar();
        return (resultado: ResultadoDevolucionMp.yaDevuelta, mensaje: e.mensaje);
      case 'sin_permiso_devolver':
        return (resultado: ResultadoDevolucionMp.sinPermiso, mensaje: e.mensaje);
      case 'no_cobrada':
        return (resultado: ResultadoDevolucionMp.noCobrada, mensaje: e.mensaje);
      default:
        return (resultado: ResultadoDevolucionMp.error, mensaje: e.mensaje);
    }
  }
}

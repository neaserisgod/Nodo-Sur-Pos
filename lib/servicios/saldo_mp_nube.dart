// Pide el saldo real de la cuenta de Mercado Pago con la cuenta de Nodo Sur vinculada a este equipo (etapa E, 2026-10-04).
// El reporte de Liquidaciones tarda unos minutos: se pide una vez y se pregunta cada pocos segundos hasta que esté.
//
// Nunca frena el cierre: sin cuenta, sin internet o con un reporte que no llega, tira un [ErrorNube] con un texto para mostrar y
// el cierre sigue con el MP contado a mano.

import '../domain/saldo_mp.dart';
import 'cuenta_nube.dart';

typedef TraerSaldoMp = Future<SaldoMp> Function(DateTime desde);

const esperaEntreConsultasSaldo = Duration(seconds: 4);
const limiteEsperaSaldo = Duration(minutes: 5);

TraerSaldoMp traerSaldoMpDeCuenta(
  AlmacenCuenta almacen,
  ClienteNube cliente, {
  Duration espera = esperaEntreConsultasSaldo,
  Duration limite = limiteEsperaSaldo,
  Future<void> Function(Duration)? dormir,
}) => (desde) async {
  final cuenta = await almacen.leer();
  if (cuenta == null) {
    throw const ErrorNube('sin_cuenta', 'Vinculá este equipo a tu cuenta de Nodo Sur para traer el saldo de Mercado Pago.');
  }
  final id = await cliente.pedirSaldoMp(cuenta.token, desde: desde);
  final pausa = dormir ?? (d) => Future<void>.delayed(d);
  var esperado = Duration.zero;
  var fallasSeguidas = 0;
  while (true) {
    try {
      final estado = await cliente.estadoSaldoMp(cuenta.token, id);
      fallasSeguidas = 0;
      if (estado.listo) return estado.saldo!;
      if (estado.fallo) {
        throw ErrorNube('mp_reporte', 'Mercado Pago no pudo armar el reporte del saldo (${estado.motivo ?? 'sin detalle'}). Contá el saldo en su app.');
      }
    } on ErrorNube catch (e) {
      // Una consulta suelta que falla (red, 502) no corta la espera; recién tres seguidas sí. Lo demás (sin permiso, sin MP) corta.
      final pasajero = e.codigo == 'sin_red' || e.codigo == 'mp_error';
      if (!pasajero || ++fallasSeguidas >= 3) rethrow;
    }
    if (esperado >= limite) {
      throw const ErrorNube('mp_demora', 'El reporte de Mercado Pago todavía no está. Probá de nuevo en unos minutos.');
    }
    await pausa(espera);
    esperado += espera;
  }
};

// La seña que la clienta pagó con el link de Mercado Pago del bot (Nodo Sur Servicios, El dueño, 2026-10-10): devolverla cuando se
// cancela el turno con tiempo, después de que la dueña lo confirma. Por el sitio, con la cuenta vinculada de este celular (el token
// del negocio en Mercado Pago nunca sale del servidor).

import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'cuenta_nube.dart';
import 'registro_errores.dart';

enum ResultadoDevolucionSena {
  devuelta,

  /// Esa seña no entró por el link (la anotaron a mano, o es una transferencia): se devuelve como siempre, a mano.
  noEsDelLink,
  error,
}

typedef DevolverSenaMp = Future<({ResultadoDevolucionSena resultado, String? mensaje})> Function(String turnoRemoto);

/// La devolución de verdad; las pruebas la reemplazan.
DevolverSenaMp devolverSenaMpDelCelular = (turnoRemoto) async {
  try {
    final cuenta = await AlmacenCuentaEnArchivo((await getApplicationSupportDirectory()).path).leer();
    if (cuenta == null) return (resultado: ResultadoDevolucionSena.error, mensaje: 'Este celular no está vinculado a la cuenta');
    await ClienteNube(http: http.Client()).devolverSenaMp(cuenta.token, turnoRemoto);
    return (resultado: ResultadoDevolucionSena.devuelta, mensaje: null);
  } on ErrorNube catch (e) {
    if (e.codigo == 'sin_sena_mp') return (resultado: ResultadoDevolucionSena.noEsDelLink, mensaje: null);
    return (resultado: ResultadoDevolucionSena.error, mensaje: e.mensaje);
  } catch (e, st) {
    unawaited(registrarSiNoEsDeRed('Devolver la seña por Mercado Pago', e, st));
    return (resultado: ResultadoDevolucionSena.error, mensaje: 'No se pudo devolver (¿hay internet?). Probá de nuevo: no se devuelve dos veces.');
  }
};

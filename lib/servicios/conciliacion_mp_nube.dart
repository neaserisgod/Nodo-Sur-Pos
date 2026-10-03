// Lee los cobros de Mercado Pago con la cuenta de Nodo Sur vinculada a este equipo (PC o celular).

import '../data/repositorio_conciliacion_mp.dart';
import 'cuenta_nube.dart';

LeerCobrosMp leerCobrosMpDeCuenta(AlmacenCuenta almacen, ClienteNube cliente) => (desde, hasta) async {
  final cuenta = await almacen.leer();
  if (cuenta == null) {
    throw const ErrorNube('sin_cuenta', 'Vinculá este equipo a tu cuenta de Nodo Sur para ver lo que cobró Mercado Pago.');
  }
  return cliente.cobrosMp(cuenta.token, desde: desde, hasta: hasta);
};

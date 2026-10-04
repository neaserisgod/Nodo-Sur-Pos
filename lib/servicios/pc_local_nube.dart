import 'dart:async';

// La PC vinculada a Nodo Sur avisa su dirección del wifi y la llave de su servidor para celulares, así un celular de la
// misma sucursal se conecta con un toque (`pantalla_emparejamiento.dart`). Se avisa al abrir la app y cada vez que
// cambia la llave. Nunca frena nada: sin cuenta, sin red local o sin internet, no pasa nada.

import '../data/database.dart';
import '../data/repositorio_configuracion.dart';
import '../servidor/servidor_companion.dart' show direccionesIpLocales, ipRecomendada, puertoServidorCompanion;
import 'cuenta_nube.dart';
import 'registro_errores.dart';

Future<void> avisarPcLocal(AppDatabase db, {required AlmacenCuenta almacen, required ClienteNube cliente}) async {
  try {
    final cuenta = await almacen.leer();
    if (cuenta == null) return;
    final ip = ipRecomendada(await direccionesIpLocales());
    if (ip == null) return;
    final llave = await tokenCompanionActual(db) ?? await regenerarTokenCompanion(db);
    await cliente.publicarPcLocal(cuenta.token, ip: ip, puerto: puertoServidorCompanion, llave: llave);
  } catch (e, st) {
    // Es una comodidad para el celular: si no se pudo, se emparejará con el código. Se anota para saber por qué.
    unawaited(registrarSiNoEsDeRed('Avisar dónde está la PC en el wifi', e, st));
  }
}

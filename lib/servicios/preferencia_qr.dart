// Dónde sale el QR en ESTE equipo (`domain/cobro_qr.dart`). Es de cada equipo, no del negocio: se guarda en el equipo y no
// viaja por la sync (un celular puede mostrar el QR y la PC usar la Point).

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/cobro_qr.dart';

const _clave = 'cobro_qr_donde';

Future<DondeQr> leerDondeQr() async => DondeQr.desdeClave((await SharedPreferences.getInstance()).getString(_clave));

Future<void> guardarDondeQr(DondeQr d) async => (await SharedPreferences.getInstance()).setString(_clave, d.clave);

/// Lo que eligió la pantalla de cobro con "Preguntar cada vez", para el próximo cobro con QR. Lo lee (y lo borra) quien arma
/// la orden: así la elección no pasa por todas las capas del cobro, que son las mismas con y sin la PC.
bool? qrEnPantallaElegidoParaElCobro;

// La IA de Google con la clave del NEGOCIO, por el sitio de Nodo Sur (El dueño, 2026-10-07: "la clave es por cuenta"). La clave queda
// en el servidor (`/api/ia/*`, cifrada como el token de Mercado Pago): este equipo manda el pedido y recibe la respuesta de Google tal
// cual, sin verla nunca. Lo usa `ClienteGemini` cuando el equipo no tiene una clave propia (`servicios/gemini.dart`).

import 'cuenta_nube.dart';
import 'gemini.dart';

class AccesoIaNube implements AccesoIaCuenta {
  /// [cuenta] devuelve el almacén de la cuenta vinculada y el cliente del sitio (se pide en cada uso: un equipo se puede vincular o
  /// desvincular con la app abierta).
  AccesoIaNube(this.cuenta);

  final Future<({AlmacenCuenta almacen, ClienteNube cliente})?> Function() cuenta;

  Future<({String token, ClienteNube cliente})?> _vinculada() async {
    final c = await cuenta();
    final vinculada = await c?.almacen.leer();
    if (c == null || vinculada == null) return null;
    return (token: vinculada.token, cliente: c.cliente);
  }

  /// Los errores del sitio, con su mensaje legible, como errores de la IA (lo único que muestran las pantallas de IA).
  Future<T> _traducir<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on ErrorNube catch (e) {
      throw ErrorGemini(e.pideVincularDeNuevo ? 'Este equipo ya no está vinculado a la cuenta: volvé a vincularlo para usar la IA.' : e.mensaje);
    }
  }

  @override
  Future<({bool configurada, String? modelo, bool puedeCambiar})?> estado() async {
    final v = await _vinculada();
    if (v == null) return null;
    return v.cliente.estadoIa(v.token);
  }

  @override
  Future<void> guardarClave(String? clave, {String? modelo}) => _traducir(() async {
    final v = await _vinculada();
    if (v == null) throw const ErrorGemini('Este equipo no está vinculado a la cuenta.');
    await v.cliente.guardarClaveIa(v.token, clave, modelo: modelo);
  });

  @override
  Future<({int estado, String cuerpo})> generar({required String modelo, required String cuerpo, required Duration limite}) => _traducir(() async {
    final v = await _vinculada();
    if (v == null) throw const ErrorGemini('Para usar la IA del negocio, vinculá este equipo a la cuenta.');
    return v.cliente.generarIa(v.token, modelo: modelo, cuerpo: cuerpo, limite: limite);
  });
}

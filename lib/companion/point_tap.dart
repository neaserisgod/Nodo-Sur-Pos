// PRUEBA de Point Tap: cobrar con tarjeta acercándola al celular, con la app de Mercado Pago (El dueño, 2026-10-13). Habla con
// el canal "nodosur/point_tap" de `MainActivity.kt`, que usa la integración por Intent del ejemplo oficial de Mercado Pago. No se
// sabe todavía si la app actual de Mercado Pago lo acepta para Point Tap: esto existe para averiguarlo en un celular real, y
// devuelve la respuesta cruda.

import 'package:flutter/services.dart';

const _canal = MethodChannel('nodosur/point_tap');

/// Si está la app de Mercado Pago y si alguna app acepta el pedido de cobro. Null si no se pudo preguntar (no es Android).
Future<Map<String, Object?>?> disponibilidadPointTap() async {
  try {
    return (await _canal.invokeMapMethod<String, Object?>('disponible'));
  } on MissingPluginException {
    return null;
  } on PlatformException catch (e) {
    return {'error_canal': e.message};
  }
}

/// Pide el cobro a la app de Mercado Pago y devuelve TODO lo que conteste. [tipo]: 'debit_card', 'credit_card' o null.
Future<Map<String, Object?>> cobrarConPointTap({required int montoCentavos, required String descripcion, String? tipo}) async {
  try {
    return (await _canal.invokeMapMethod<String, Object?>('cobrar', {
          'monto': montoCentavos / 100,
          'descripcion': descripcion,
          'tipo': tipo,
        })) ??
        {'error_canal': 'sin respuesta'};
  } on MissingPluginException {
    return {'error_canal': 'Esta versión de la app no tiene la prueba (hace falta Android)'};
  } on PlatformException catch (e) {
    return {'error_canal': '${e.code}: ${e.message}'};
  }
}

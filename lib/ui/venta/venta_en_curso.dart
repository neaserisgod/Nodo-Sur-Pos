import 'package:flutter/foundation.dart';

/// Verdadero mientras Venta tiene algo cargado en alguna pestaña. Lo lee el
/// actualizador (`servicios/actualizaciones.dart`) para no avisar ni ofrecer
/// nada con una venta abierta: es la pantalla de mostrador, con gente
/// esperando (Bruno, 2026-09-30).
///
/// Al salir de Venta con el carrito cargado NO se apaga: el borrador sigue
/// guardado y la venta sigue abierta para todo efecto práctico.
final ValueNotifier<bool> hayVentaEnCurso = ValueNotifier<bool>(false);

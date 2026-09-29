// Un solo observador de rutas, compartido por toda la app (registrado en
// `MaterialApp.navigatorObservers`, `main.dart`).
//
// Bug real (Bruno, 2026-09-05: "no aparecen productos, no proveedores...
// la pantalla de venta no detecta hasta restart"): cada `_irAX()` de
// `pantalla_venta.dart` refrescaba `VentaControlador` a mano después de SU
// propio `Navigator.push` — pero saltar de una sección de gestión a OTRA
// (ej. Historial → Proveedores, por la barra lateral compartida,
// `navegacion_gestion.dart`) nunca pasa por ninguno de esos `_irAX`: ese
// salto hace `popUntil` hasta la venta y empuja el destino directo, sin que
// nada le avise a `VentaControlador` que hay que recargar. Cualquier
// `_irAX` nuevo (o cualquier salto entre dos secciones que no sea Venta)
// repetiría el mismo bug si el refresco sigue viviendo ahí.
//
// `RouteObserver`/`RouteAware` es la solución genérica de Flutter para
// "avisame cuando esta pantalla vuelve a estar arriba de todo, sin importar
// cómo se llegó ni cómo se volvió" — `PantallaVenta` se suscribe una sola
// vez y reacciona en `didPopNext()`, sin que cada `_irAX` tenga que
// acordarse de nada.

import 'package:flutter/material.dart';

final RouteObserver<PageRoute<dynamic>> routeObserver = RouteObserver<PageRoute<dynamic>>();

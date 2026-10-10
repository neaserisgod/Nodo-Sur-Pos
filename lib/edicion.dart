// Qué edición de la app es (El dueño, 2026-10-10, `docs/PLAN-APP-SERVICIOS.md`). En Android salen dos del mismo código:
// "almacen" (la de siempre) y "servicios" (Nodo Sur Servicios: turnos, con el bot de WhatsApp adentro). La elige el flavor de
// Gradle al compilar (`--flavor`); Windows y las pruebas no tienen flavor y son la de almacén.

import 'package:flutter/services.dart' show appFlavor;

enum Edicion { almacen, servicios }

/// La edición con la que se compiló. Se puede pisar en las pruebas.
Edicion edicionActual = appFlavor == 'servicios' ? Edicion.servicios : Edicion.almacen;

bool get esEdicionServicios => edicionActual == Edicion.servicios;

/// Con qué nombre busca sus actualizaciones en el sitio: cada edición es un APK distinto.
String get plataformaActualizacion => esEdicionServicios ? 'android-servicios' : 'android';

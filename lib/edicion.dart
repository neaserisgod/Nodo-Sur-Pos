// Qué edición de la app es (El dueño, 2026-10-10, `docs/PLAN-APP-SERVICIOS.md`). Del mismo código salen dos: "almacen" (la de
// siempre) y "servicios" (Nodo Sur Servicios: turnos, con el bot de WhatsApp adentro). En Android la elige el flavor de Gradle
// (`--flavor`); en Windows, que no tiene flavors, `--dart-define=EDICION=servicios` (El dueño, 2026-10-15: "la versión de
// escritorio de Nodo Sur Servicios", `docs/PLAN-ESCRITORIO-SERVICIOS.md`). Sin nada de eso (y en las pruebas) es la de almacén.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show appFlavor;

enum Edicion { almacen, servicios }

const _edicionDefinida = String.fromEnvironment('EDICION');

/// La edición con la que se compiló. Se puede pisar en las pruebas.
Edicion edicionActual = appFlavor == 'servicios' || _edicionDefinida == 'servicios' ? Edicion.servicios : Edicion.almacen;

bool get esEdicionServicios => edicionActual == Edicion.servicios;

/// Nodo Sur Servicios instalado en una compu con Windows: la app del celular, con ventana de PC y su propio instalador.
bool get esEscritorioServicios => esEdicionServicios && !kIsWeb && Platform.isWindows;

/// Con qué nombre busca sus actualizaciones en el sitio: cada edición de cada sistema es un instalador distinto.
String get plataformaActualizacion => esEscritorioServicios ? 'windows-servicios' : esEdicionServicios ? 'android-servicios' : 'android';

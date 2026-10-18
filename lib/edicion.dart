// Qué edición de la app es (El dueño, 2026-10-10, `docs/PLAN-APP-SERVICIOS.md`). Del mismo código salen tres: "almacen" (la de
// siempre), "servicios" (Nodo Sur Servicios: turnos, con el bot de WhatsApp adentro) y "gastronomia" (rotisería y comida para
// llevar, El dueño, 2026-10-16: "versión aparte, como Servicios", `docs/PLAN-GASTRONOMIA.md`). En Android la elige el flavor de
// Gradle (`--flavor`); en Windows, que no tiene flavors, `--dart-define=EDICION=servicios` (o `gastronomia`) (El dueño, 2026-10-15:
// "la versión de escritorio de Nodo Sur Servicios", `docs/PLAN-ESCRITORIO-SERVICIOS.md`). Sin nada de eso (y en las pruebas) es
// la de almacén.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show appFlavor;

enum Edicion { almacen, servicios, gastronomia }

const _edicionDefinida = String.fromEnvironment('EDICION');

Edicion _edicionCompilada() {
  final clave = appFlavor ?? _edicionDefinida;
  return switch (clave) {
    'servicios' => Edicion.servicios,
    'gastronomia' => Edicion.gastronomia,
    _ => Edicion.almacen,
  };
}

/// La edición con la que se compiló. Se puede pisar en las pruebas.
Edicion edicionActual = _edicionCompilada();

bool get esEdicionServicios => edicionActual == Edicion.servicios;

bool get esEdicionGastronomia => edicionActual == Edicion.gastronomia;

/// Una app aparte de la del almacén, armada sobre la del celular: sin PC con la que emparejarse ("Solo celular", se sincroniza
/// por internet), con el bot de WhatsApp adentro y sus propias actualizaciones. Lo que es solo de una (la caja simple y la
/// persona sola de Servicios, sus textos, sus rubros) pregunta por [esEdicionServicios] o [esEdicionGastronomia].
bool get esEdicionAparte => edicionActual != Edicion.almacen;

/// Una edición aparte instalada en una compu con Windows: la app del celular, con ventana de PC y su propio instalador.
bool get esEscritorioAparte => esEdicionAparte && !kIsWeb && Platform.isWindows;

/// El rubro que la edición ya trae: Nodo Gastro es un solo rubro para toda la gastronomía, sin elegir (El dueño, 2026-10-18). Lo
/// usa quien necesita un rubro y no hay uno guardado (el dueño salteó el primer paso del alta). Null: hay que elegirlo.
String? get rubroDeEdicion => esEdicionGastronomia ? 'rotiseria' : null;

/// El nombre que se ve en la ventana y en la tienda.
String get nombreDeEdicion => switch (edicionActual) {
      Edicion.almacen => 'Nodo Sur POS',
      Edicion.servicios => 'Nodo Sur Servicios',
      Edicion.gastronomia => 'Nodo Gastro',
    };

/// Con qué nombre busca sus actualizaciones en el sitio: cada edición de cada sistema es un instalador distinto.
String get plataformaActualizacion => switch (edicionActual) {
      Edicion.almacen => 'android',
      Edicion.servicios => esEscritorioAparte ? 'windows-servicios' : 'android-servicios',
      Edicion.gastronomia => esEscritorioAparte ? 'windows-gastronomia' : 'android-gastronomia',
    };

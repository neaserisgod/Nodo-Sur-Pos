// Plantillas por rubro: datos de ejemplo con los que un comercio nuevo puede
// arrancar (categorías y conceptos de gastos fijos comunes del rubro).
//
// Son una ayuda, no una regla: el comercio las edita, las borra o no las usa.
// No traen proveedores (cada comercio tiene los suyos), ni productos, ni
// márgenes: el margen de referencia de una categoría es de cada comercio y
// arranca en 0 ("sin referencia", Regla 14) en vez de regalar los de otro.
//
// Las claves no se renombran nunca: se guardan en la configuración (`configuracion_negocio.rubro`, v63) y el bot de
// WhatsApp usa las mismas (`botdemo/src/plantillas.js`): el rubro que se elige en la app le llega tal cual.

import 'forma_de_trabajo.dart';

/// Una categoría de ejemplo. [markupDefaultBp] es informativo (Regla 14).
class CategoriaDePlantilla {
  const CategoriaDePlantilla(this.nombre, {this.markupDefaultBp = 0});

  final String nombre;
  final int markupDefaultBp;
}

class PlantillaRubro {
  const PlantillaRubro({
    required this.clave,
    required this.nombre,
    required this.descripcion,
    this.forma = FormaDeTrabajo.productos,
    this.categorias = const [],
    this.gastosFijos = const [],
  });

  final String clave;
  final String nombre;
  final String descripcion;

  /// Vende productos o da servicios: decide qué partes de la app se ven (`forma_de_trabajo.dart`).
  final FormaDeTrabajo forma;
  final List<CategoriaDePlantilla> categorias;

  /// Conceptos de gastos fijos, sin monto: el monto se carga por mes
  /// (Regla 12), porque cambia.
  final List<String> gastosFijos;

  static const kiosco = PlantillaRubro(
    clave: 'kiosco',
    nombre: 'Kiosco',
    descripcion: 'Golosinas, bebidas, cigarrillos y artículos de paso.',
    categorias: [
      CategoriaDePlantilla('Golosinas'),
      CategoriaDePlantilla('Bebidas'),
      CategoriaDePlantilla('Gaseosas'),
      CategoriaDePlantilla('Cigarrillos'),
      CategoriaDePlantilla('Galletitas y snacks'),
      CategoriaDePlantilla('Helados'),
      CategoriaDePlantilla('Lácteos'),
      CategoriaDePlantilla('Limpieza y perfumería'),
    ],
    gastosFijos: ['Alquiler', 'Luz', 'Internet', 'Sueldos'],
  );

  static const almacen = PlantillaRubro(
    clave: 'almacen',
    nombre: 'Almacén',
    descripcion: 'Almacén de barrio: comestibles, bebidas, limpieza y fiambres.',
    categorias: [
      CategoriaDePlantilla('Almacén'),
      CategoriaDePlantilla('Bebidas'),
      CategoriaDePlantilla('Gaseosas'),
      CategoriaDePlantilla('Cervezas'),
      CategoriaDePlantilla('Vinos'),
      CategoriaDePlantilla('Golosinas'),
      CategoriaDePlantilla('Galletitas y panificados'),
      CategoriaDePlantilla('Yerbas y té'),
      CategoriaDePlantilla('Lácteos'),
      CategoriaDePlantilla('Higiene y limpieza'),
      CategoriaDePlantilla('Cigarrillos'),
      CategoriaDePlantilla('Fiambres'),
    ],
    gastosFijos: ['Alquiler', 'Luz', 'Internet', 'Sueldos'],
  );

  static const fiambreria = PlantillaRubro(
    clave: 'fiambreria',
    nombre: 'Fiambrería',
    descripcion: 'Fiambres, quesos y lácteos, con productos que se venden por peso.',
    categorias: [
      CategoriaDePlantilla('Fiambres'),
      CategoriaDePlantilla('Quesos'),
      CategoriaDePlantilla('Embutidos'),
      CategoriaDePlantilla('Lácteos'),
      CategoriaDePlantilla('Panificados'),
      CategoriaDePlantilla('Almacén'),
      CategoriaDePlantilla('Bebidas'),
    ],
    gastosFijos: ['Alquiler', 'Luz', 'Internet', 'Sueldos'],
  );

  static const barberia = PlantillaRubro(
    clave: 'barberia',
    nombre: 'Barbería',
    descripcion: 'Cortes, barba y color, con turnos.',
    forma: FormaDeTrabajo.servicios,
    categorias: [
      CategoriaDePlantilla('Cortes'),
      CategoriaDePlantilla('Barba'),
      CategoriaDePlantilla('Color'),
    ],
    gastosFijos: ['Alquiler', 'Luz', 'Internet', 'Sueldos'],
  );

  /// La clave es `unas` (sin tilde ni eñe), la que ya guarda el bot en los negocios instalados.
  static const unas = PlantillaRubro(
    clave: 'unas',
    nombre: 'Uñas y belleza',
    descripcion: 'Manos, pies, cejas y pestañas, con turnos.',
    forma: FormaDeTrabajo.servicios,
    categorias: [
      CategoriaDePlantilla('Manos'),
      CategoriaDePlantilla('Pies'),
      CategoriaDePlantilla('Cejas y pestañas'),
    ],
    gastosFijos: ['Alquiler', 'Luz', 'Internet', 'Sueldos'],
  );

  /// Un servicio que no es barbería ni uñas: sin categorías de ejemplo.
  static const servicio = PlantillaRubro(
    clave: 'servicio',
    nombre: 'Otro servicio',
    descripcion: 'Peluquería, estética, masajes, tatuajes…',
    forma: FormaDeTrabajo.servicios,
    gastosFijos: ['Alquiler', 'Luz', 'Internet'],
  );

  /// Sin ejemplos: el comercio arma todo a mano.
  static const otro = PlantillaRubro(
    clave: 'otro',
    nombre: 'Otro',
    descripcion: 'Empezar desde cero, sin categorías de ejemplo.',
    gastosFijos: ['Alquiler', 'Luz', 'Internet'],
  );

  static const List<PlantillaRubro> todas = [kiosco, almacen, fiambreria, barberia, unas, servicio, otro];

  /// Las de una forma de trabajar, en el orden de [todas] (el alta los muestra en dos grupos). "Otro" es de productos.
  static List<PlantillaRubro> deForma(FormaDeTrabajo forma) => [for (final p in todas) if (p.forma == forma && p != otro) p];

  static PlantillaRubro? desdeClave(String clave) {
    for (final plantilla in todas) {
      if (plantilla.clave == clave) return plantilla;
    }
    return null;
  }
}

/// La forma de trabajar según la clave guardada. Sin rubro elegido (un negocio anterior a la v63) o con una clave de una
/// versión más nueva, productos: es la app de siempre, y actualizar no le cambia nada a un negocio que ya funciona.
FormaDeTrabajo formaDeRubro(String clave) => PlantillaRubro.desdeClave(clave)?.forma ?? FormaDeTrabajo.productos;

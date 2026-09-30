// Plantillas por rubro: datos de ejemplo con los que un comercio nuevo puede
// arrancar (categorías y conceptos de gastos fijos comunes del rubro).
//
// Son una ayuda, no una regla: el comercio las edita, las borra o no las usa.
// No traen proveedores (cada comercio tiene los suyos), ni productos, ni
// márgenes: el margen de referencia de una categoría es de cada comercio y
// arranca en 0 ("sin referencia", Regla 14) en vez de regalar los de otro.
//
// Las claves no se renombran nunca: se van a guardar en la configuración.

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
    this.categorias = const [],
    this.gastosFijos = const [],
  });

  final String clave;
  final String nombre;
  final String descripcion;
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

  /// Sin ejemplos: el comercio arma todo a mano.
  static const otro = PlantillaRubro(
    clave: 'otro',
    nombre: 'Otro',
    descripcion: 'Empezar desde cero, sin categorías de ejemplo.',
    gastosFijos: ['Alquiler', 'Luz', 'Internet'],
  );

  static const List<PlantillaRubro> todas = [kiosco, almacen, fiambreria, otro];

  static PlantillaRubro? desdeClave(String clave) {
    for (final plantilla in todas) {
      if (plantilla.clave == clave) return plantilla;
    }
    return null;
  }
}

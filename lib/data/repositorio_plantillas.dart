// Aplicar una plantilla por rubro (`domain/plantillas_rubro.dart`) a la base:
// carga las categorías y los conceptos de gastos fijos de ejemplo.
//
// Es idempotente y no pisa nada: lo que el comercio ya tiene (por nombre, sin
// importar mayúsculas) se respeta tal cual, con su margen de referencia. Se
// puede aplicar más de una plantilla (un almacén que también es fiambrería).
//
// Como el resto de las semillas de escritorio (`_seedDatosFijos`), las filas
// se insertan sin `global_id` ni `actualizado_en`: recién sincronizan cuando
// se editan de verdad. Solo corre en el escritorio (la companion recibe estas
// filas por sincronización).

import 'package:drift/drift.dart';

import '../domain/plantillas_rubro.dart';
import 'database.dart';

class ResultadoPlantilla {
  const ResultadoPlantilla({required this.categoriasNuevas, required this.gastosFijosNuevos});

  final int categoriasNuevas;
  final int gastosFijosNuevos;
}

Future<ResultadoPlantilla> aplicarPlantillaRubro(AppDatabase db, PlantillaRubro plantilla) {
  return db.transaction(() async {
    final categoriasExistentes = {
      for (final c in await db.select(db.categorias).get()) c.nombre.trim().toLowerCase(),
    };
    var categoriasNuevas = 0;
    for (final categoria in plantilla.categorias) {
      if (!categoriasExistentes.add(categoria.nombre.toLowerCase())) continue;
      await db.into(db.categorias).insert(
            CategoriasCompanion.insert(
              nombre: categoria.nombre,
              markupDefaultBp: Value(categoria.markupDefaultBp),
            ),
          );
      categoriasNuevas++;
    }

    final fijosExistentes = {
      for (final g in await db.select(db.gastosFijos).get()) g.nombre.trim().toLowerCase(),
    };
    var gastosFijosNuevos = 0;
    for (final nombre in plantilla.gastosFijos) {
      if (!fijosExistentes.add(nombre.toLowerCase())) continue;
      await db.into(db.gastosFijos).insert(GastosFijosCompanion.insert(nombre: nombre));
      gastosFijosNuevos++;
    }

    return ResultadoPlantilla(categoriasNuevas: categoriasNuevas, gastosFijosNuevos: gastosFijosNuevos);
  });
}

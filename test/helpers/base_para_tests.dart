// Base de datos de prueba con un catálogo de ejemplo.
//
// La app real arranca sin categorías, proveedores ni gastos fijos (cada
// comercio carga los suyos o parte de una plantilla por rubro). Pero casi todos
// los tests se escribieron contra un catálogo ya cargado — categorías, 15
// proveedores con sus códigos, los conceptos de gastos fijos y un usuario —, y
// reescribirlos uno por uno no aporta nada: acá queda ese catálogo, como
// fixture de test, para que sigan probando lo mismo.
//
// Los tests que verifican cómo arranca una base NUEVA de verdad usan
// `AppDatabase(NativeDatabase.memory())` directo, sin este catálogo.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:la_plazoleta/data/database.dart';

const _categoriasDeTest = [
  ('Almacén', 5000),
  ('Bebidas', 7000),
  ('Cervezas', 5000),
  ('Gaseosas', 5000),
  ('Vinos', 0),
  ('Cigarrillos', 0),
  ('Golosinas', 7000),
  ('Galletitas y panificados', 0),
  ('Yerbas y té', 0),
  ('Higiene y limpieza', 0),
  ('Fiambres', 9000),
];

const _proveedoresDeTest = [
  ('S', 'Distribuidora'),
  ('F', 'Fiambrería'),
  ('C', 'Coca Cola'),
  ('W', 'Golosinas Oeste'),
  ...proveedoresNuevosV10,
];

const _gastosFijosDeTest = ['Alquiler', 'Ayuda fin de semana', 'Luz', 'Internet'];

/// Carga el catálogo de ejemplo sobre una base recién creada. Es el `alCrear`
/// de [AppDatabase]: corre al final de `onCreate`.
Future<void> sembrarCatalogoDeTest(AppDatabase db) async {
  await db.customStatement("UPDATE usuarios SET nombre = 'Dueño'");
  // Un comercio ya cargado, como una instalación en uso: así los tests de pantalla no se topan con el aviso
  // de primer arranque ("Datos de tu comercio"), que aparece solo en una base nueva de verdad.
  await db.customStatement("UPDATE configuracion_negocio_tabla SET nombre_comercio = 'Comercio de prueba', modulos_desactivados = ''");
  for (final (nombre, markupBp) in _categoriasDeTest) {
    await db.into(db.categorias).insert(CategoriasCompanion.insert(nombre: nombre, markupDefaultBp: Value(markupBp)));
  }
  for (final (codigo, nombre) in _proveedoresDeTest) {
    await db.into(db.proveedores).insert(
      ProveedoresCompanion.insert(codigo: codigo, nombre: nombre, cajaAparte: Value(codigo == 'SC')),
    );
  }
  for (final nombre in _gastosFijosDeTest) {
    await db.into(db.gastosFijos).insert(GastosFijosCompanion.insert(nombre: nombre));
  }
}

/// Base en memoria con el catálogo de ejemplo.
AppDatabase baseDeTest() => AppDatabase(NativeDatabase.memory(), sembrarCatalogoDeTest);

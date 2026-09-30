import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/plantillas_rubro.dart';

void main() {
  group('plantillas por rubro — datos de ejemplo para un comercio nuevo', () {
    test('hay una plantilla por rubro y una vacía, con claves estables y únicas', () {
      expect(
        PlantillaRubro.todas.map((p) => p.clave).toList(),
        ['kiosco', 'almacen', 'fiambreria', 'otro'],
      );
      final claves = PlantillaRubro.todas.map((p) => p.clave);
      expect(claves.toSet().length, claves.length);
      for (final clave in claves) {
        expect(clave, matches(RegExp(r'^[a-z][a-z0-9_]*$')));
      }
    });

    test('desdeClave encuentra la plantilla, y una clave desconocida devuelve null', () {
      expect(PlantillaRubro.desdeClave('almacen')?.nombre, 'Almacén');
      expect(PlantillaRubro.desdeClave('kiosco')?.nombre, 'Kiosco');
      expect(PlantillaRubro.desdeClave('nave_espacial'), isNull);
    });

    test('kiosco, almacén y fiambrería traen categorías; "otro" arranca vacío', () {
      for (final clave in ['kiosco', 'almacen', 'fiambreria']) {
        expect(PlantillaRubro.desdeClave(clave)!.categorias, isNotEmpty, reason: clave);
      }
      expect(PlantillaRubro.otro.categorias, isEmpty);
    });

    test('ninguna plantilla repite categorías ni conceptos de gastos fijos (sin importar mayúsculas)', () {
      for (final p in PlantillaRubro.todas) {
        final categorias = p.categorias.map((c) => c.nombre.toLowerCase()).toList();
        expect(categorias.toSet().length, categorias.length, reason: p.clave);
        final fijos = p.gastosFijos.map((g) => g.toLowerCase()).toList();
        expect(fijos.toSet().length, fijos.length, reason: p.clave);
      }
    });

    test('los nombres no tienen espacios de más ni quedan vacíos', () {
      for (final p in PlantillaRubro.todas) {
        expect(p.nombre.trim(), p.nombre);
        expect(p.nombre, isNotEmpty);
        for (final c in p.categorias) {
          expect(c.nombre.trim(), c.nombre, reason: p.clave);
          expect(c.nombre, isNotEmpty, reason: p.clave);
        }
        for (final g in p.gastosFijos) {
          expect(g.trim(), g, reason: p.clave);
          expect(g, isNotEmpty, reason: p.clave);
        }
      }
    });

    test('los márgenes de referencia no son negativos y arrancan sin dato (0) en las plantillas', () {
      // Los márgenes de un local concreto no se regalan como ejemplo de otro:
      // 0 significa "sin referencia" (Regla 14), el comercio carga los suyos.
      for (final p in PlantillaRubro.todas) {
        for (final c in p.categorias) {
          expect(c.markupDefaultBp, 0, reason: '${p.clave}/${c.nombre}');
        }
      }
    });

    test('ninguna plantilla trae datos personales de un comercio en particular', () {
      const personales = ['serra', 'mazzota', 'bruno', 'wesley', 'jam rock', 'plazoleta', 'bustillo', 'bariloche'];
      for (final p in PlantillaRubro.todas) {
        final texto = [p.clave, p.nombre, p.descripcion, ...p.categorias.map((c) => c.nombre), ...p.gastosFijos].join(' ').toLowerCase();
        for (final nombre in personales) {
          expect(texto.contains(nombre), isFalse, reason: '${p.clave} menciona "$nombre"');
        }
      }
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/forma_de_trabajo.dart';
import 'package:la_plazoleta/domain/plantillas_rubro.dart';

void main() {
  group('plantillas por rubro — datos de ejemplo para un comercio nuevo', () {
    test('hay una plantilla por rubro y una vacía, con claves estables y únicas', () {
      expect(
        PlantillaRubro.todas.map((p) => p.clave).toList(),
        // Las mismas claves que el bot de WhatsApp (`botdemo/src/plantillas.js`): no se renombran nunca.
        ['kiosco', 'almacen', 'fiambreria', 'barberia', 'unas', 'peluqueria', 'estetica', 'servicio', 'otro'],
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
      // Vacío es "sin elegir" (`configuracion_negocio_tabla.rubro`, v63): un negocio viejo no tiene rubro guardado.
      expect(PlantillaRubro.desdeClave(''), isNull);
    });

    test('kiosco, almacén, fiambrería, barbería, uñas, peluquería y estética traen categorías; "otro" y "otro servicio" arrancan vacíos', () {
      for (final clave in ['kiosco', 'almacen', 'fiambreria', 'barberia', 'unas', 'peluqueria', 'estetica']) {
        expect(PlantillaRubro.desdeClave(clave)!.categorias, isNotEmpty, reason: clave);
      }
      expect(PlantillaRubro.otro.categorias, isEmpty);
      expect(PlantillaRubro.servicio.categorias, isEmpty);
    });

    test('cada rubro trae su forma de trabajar: los comercios venden productos, barbería, uñas, peluquería y estética dan servicios', () {
      for (final p in [PlantillaRubro.kiosco, PlantillaRubro.almacen, PlantillaRubro.fiambreria, PlantillaRubro.otro]) {
        expect(p.forma, FormaDeTrabajo.productos, reason: p.clave);
      }
      for (final p in [PlantillaRubro.barberia, PlantillaRubro.unas, PlantillaRubro.peluqueria, PlantillaRubro.estetica, PlantillaRubro.servicio]) {
        expect(p.forma, FormaDeTrabajo.servicios, reason: p.clave);
      }
    });

    test('deForma arma los dos grupos del alta, sin "otro", en el orden de todas', () {
      expect(PlantillaRubro.deForma(FormaDeTrabajo.productos).map((p) => p.clave), ['kiosco', 'almacen', 'fiambreria']);
      expect(PlantillaRubro.deForma(FormaDeTrabajo.servicios).map((p) => p.clave), ['barberia', 'unas', 'peluqueria', 'estetica', 'servicio']);
    });

    test('formaDeRubro: sin rubro o con una clave desconocida es productos, la app de siempre', () {
      // Un negocio anterior a la v63 (La Plazoleta) no tiene rubro guardado: actualizar no le puede cambiar nada.
      expect(formaDeRubro(''), FormaDeTrabajo.productos);
      expect(formaDeRubro('almacen'), FormaDeTrabajo.productos);
      expect(formaDeRubro('barberia'), FormaDeTrabajo.servicios);
      expect(formaDeRubro('unas'), FormaDeTrabajo.servicios);
      expect(formaDeRubro('peluqueria'), FormaDeTrabajo.servicios);
      expect(formaDeRubro('estetica'), FormaDeTrabajo.servicios);
      // Una clave de una versión más nueva se lee como "sin elegir".
      expect(formaDeRubro('rubro_del_futuro'), FormaDeTrabajo.productos);
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

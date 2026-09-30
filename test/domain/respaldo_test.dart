import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/respaldo.dart';

void main() {
  group('nombreArchivoRespaldo', () {
    test('incluye fecha y hora sin espacios ni caracteres inválidos para un nombre de archivo', () {
      final nombre = nombreArchivoRespaldo(DateTime(2026, 8, 30, 14, 5, 9));
      expect(nombre, 'la_plazoleta_2026-08-30_140509.sqlite');
    });
  });

  group('nombresAEliminar — rotar, no pisar (pedido explícito de Dueño)', () {
    test('con menos copias que el máximo, no elimina nada', () {
      final r = nombresAEliminar(
        nombresOrdenadosDeViejoANuevo: ['a', 'b', 'c'],
        maximoCopias: 5,
      );
      expect(r, isEmpty);
    });

    test('justo en el máximo, no elimina nada', () {
      final r = nombresAEliminar(
        nombresOrdenadosDeViejoANuevo: ['a', 'b', 'c'],
        maximoCopias: 3,
      );
      expect(r, isEmpty);
    });

    test('con exceso, elimina las más viejas (las primeras de la lista ordenada)', () {
      final r = nombresAEliminar(
        nombresOrdenadosDeViejoANuevo: ['viejo1', 'viejo2', 'nuevo1', 'nuevo2'],
        maximoCopias: 2,
      );
      expect(r, ['viejo1', 'viejo2']);
    });

    test('lista vacía no rompe nada', () {
      expect(nombresAEliminar(nombresOrdenadosDeViejoANuevo: [], maximoCopias: 5), isEmpty);
    });
  });
}

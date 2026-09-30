import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/modulos.dart';

void main() {
  group('ModulosNegocio — qué partes de la app usa cada comercio', () {
    test('sin nada desactivado, todos los módulos están activos', () {
      final modulos = ModulosNegocio.desdeTexto('');
      for (final modulo in Modulo.values) {
        expect(modulos.estaActivo(modulo), isTrue, reason: modulo.clave);
      }
      expect(modulos.desactivados, isEmpty);
    });

    test('los desactivados quedan apagados y el resto sigue activo', () {
      final modulos = ModulosNegocio.desdeTexto('pesables,fiado');
      expect(modulos.estaActivo(Modulo.pesables), isFalse);
      expect(modulos.estaActivo(Modulo.fiado), isFalse);
      expect(modulos.estaActivo(Modulo.promos), isTrue);
      expect(modulos.estaActivo(Modulo.cajaAparte), isTrue);
    });

    test('ida y vuelta: lo que se guarda como texto se lee igual', () {
      final original = ModulosNegocio({Modulo.compararPrecios, Modulo.turnos});
      final leido = ModulosNegocio.desdeTexto(original.aTexto());
      expect(leido.desactivados, {Modulo.compararPrecios, Modulo.turnos});
    });

    test('el texto guardado es estable: mismo orden siempre, sin repetidos', () {
      final a = ModulosNegocio({Modulo.turnos, Modulo.fiado}).aTexto();
      final b = ModulosNegocio({Modulo.fiado, Modulo.turnos}).aTexto();
      expect(a, b);
      expect(ModulosNegocio.desdeTexto('fiado,fiado,turnos').aTexto(), b);
    });

    test('tolera espacios, mayúsculas y claves vacías', () {
      final modulos = ModulosNegocio.desdeTexto(' Fiado , ,PESABLES,');
      expect(modulos.desactivados, {Modulo.fiado, Modulo.pesables});
    });

    test('una clave desconocida (de una versión más nueva) se ignora sin romper nada', () {
      final modulos = ModulosNegocio.desdeTexto('fiado,modulo_que_no_existe_todavia');
      expect(modulos.desactivados, {Modulo.fiado});
    });

    test('activar y desactivar devuelve una copia nueva, sin tocar la original', () {
      const todos = ModulosNegocio({});
      final sinFiado = todos.conModulo(Modulo.fiado, activo: false);
      expect(todos.estaActivo(Modulo.fiado), isTrue);
      expect(sinFiado.estaActivo(Modulo.fiado), isFalse);
      expect(sinFiado.conModulo(Modulo.fiado, activo: true).estaActivo(Modulo.fiado), isTrue);
    });

    test('las claves son únicas (se guardan en la base: no pueden chocar ni cambiar)', () {
      final claves = Modulo.values.map((m) => m.clave).toList();
      expect(claves.toSet().length, claves.length);
      for (final clave in claves) {
        expect(clave, matches(RegExp(r'^[a-z][a-z0-9_]*$')));
      }
    });

    test('hay un módulo por cada parte opcional que encontró la auditoría', () {
      expect(
        Modulo.values.map((m) => m.clave).toSet(),
        {
          'caja_aparte',
          'pesables',
          'promos',
          'fiado',
          'retiro_ganancias',
          'equilibrio',
          'turnos',
          'carga_historica',
          'comparar_precios',
          'cobro_point',
        },
      );
    });
  });
}

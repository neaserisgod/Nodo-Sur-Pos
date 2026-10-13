import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/usuarios_repetidos.dart';

PerfilParaUnificar p(int id, String nombre, String? gid, {bool activo = true}) => (id: id, nombre: nombre, globalId: gid, activo: activo);

void main() {
  test('mismo nombre sin importar mayúsculas, acentos ni espacios = misma persona', () {
    final g = agruparRepetidos([p(1, 'Bruno Fuentes', 'c'), p(2, ' bruno fuentes ', 'a'), p(3, 'BRUNO FUENTES', 'b'), p(4, 'Carolina', 'z')]);
    expect(g, hasLength(1));
    expect(g.single.queda, 2, reason: 'el de global_id menor');
    expect(g.single.repetidos, [3, 1]);
    expect(agruparRepetidos([p(1, 'José', 'a'), p(2, 'Jose', 'b')]).single.repetidos, [2]);
  });

  test('la elección no depende del orden ni del id local: todos los equipos eligen el mismo', () {
    final a = agruparRepetidos([p(1, 'Ana', 'g2'), p(2, 'Ana', 'g1')]).single;
    final b = agruparRepetidos([p(7, 'Ana', 'g1'), p(9, 'Ana', 'g2')]).single;
    expect(a.queda, 2);
    expect(b.queda, 7);
  });

  test('sin global_id van al final; entre ellos, el id menor', () {
    expect(agruparRepetidos([p(5, 'Ana', null), p(9, 'Ana', 'g'), p(3, 'Ana', null)]).single.repetidos, [3, 5]);
    expect(agruparRepetidos([p(5, 'Ana', null), p(3, 'Ana', null)]).single.queda, 3);
  });

  test('si alguno del grupo está activo, la persona está activa', () {
    expect(agruparRepetidos([p(1, 'Ana', 'a', activo: false), p(2, 'Ana', 'b')]).single.activo, isTrue);
    expect(agruparRepetidos([p(1, 'Ana', 'a', activo: false), p(2, 'Ana', 'b', activo: false)]).single.activo, isFalse);
  });

  test('nombres distintos o vacíos no se juntan', () {
    expect(agruparRepetidos([p(1, 'Ana', 'a'), p(2, 'Ana María', 'b'), p(3, '', 'c'), p(4, '  ', 'd')]), isEmpty);
  });
}

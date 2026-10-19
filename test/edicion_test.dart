// Las tres ediciones del mismo código (`lib/edicion.dart`): almacén, Nodo Sur Servicios y Nodo Gastro (El dueño,
// 2026-10-16: "versión aparte, como Servicios"). Cada una con su nombre y sus actualizaciones; las dos aparte, sin PC.
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/forma_de_trabajo.dart';
import 'package:la_plazoleta/edicion.dart';
import 'package:la_plazoleta/servicios/modulos_activos.dart';
import 'package:la_plazoleta/domain/modulos.dart';

void main() {
  tearDown(() => edicionActual = Edicion.almacen);

  test('sin flavor ni EDICION es la de almacén', () {
    expect(edicionActual, Edicion.almacen);
    expect(esEdicionAparte, isFalse);
    expect(nombreDeEdicion, 'Nodo Gestión');
    expect(plataformaActualizacion, 'android');
  });

  test('Servicios y Gastronomía son aparte, cada una con su nombre y su canal de actualizaciones', () {
    edicionActual = Edicion.servicios;
    expect(esEdicionAparte, isTrue);
    expect(esEdicionGastronomia, isFalse);
    expect(plataformaActualizacion, 'android-servicios');

    edicionActual = Edicion.gastronomia;
    expect(esEdicionAparte, isTrue);
    expect(esEdicionServicios, isFalse);
    expect(nombreDeEdicion, 'Nodo Gastro');
    expect(plataformaActualizacion, 'android-gastronomia');
  });

  test('cada edición ve los módulos de su forma', () {
    edicionActual = Edicion.gastronomia;
    expect(modulosDeEdicion(ModulosNegocio.todosActivos).forma, FormaDeTrabajo.gastronomia);
    edicionActual = Edicion.servicios;
    expect(modulosDeEdicion(ModulosNegocio.todosActivos).forma, FormaDeTrabajo.servicios);
    edicionActual = Edicion.almacen;
    expect(modulosDeEdicion(ModulosNegocio.todosActivos).forma, FormaDeTrabajo.productos);
  });
}

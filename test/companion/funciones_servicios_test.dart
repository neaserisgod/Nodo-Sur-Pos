import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/funciones_ns.dart';
import 'package:la_plazoleta/edicion.dart';

/// El buscador de funciones en un negocio de servicios (El dueño, 2026-10-10: "muchas cosas siguen siendo genéricas de
/// almacén"): no ofrece lo que es de un almacén y suma servicios e insumos.
void main() {
  test('un almacén ve todo como siempre', () {
    expect(funcionesDelNegocio(), indiceFunciones);
    expect(buscarFunciones('cigarrillos').map((f) => f.titulo), contains('Recargo de cigarrillos'));
  });

  test('un negocio de servicios no ve escanear, stock de productos, separar, cigarrillos, vuelto ni promos', () {
    final titulos = funcionesDelNegocio(servicios: true).map((f) => f.titulo).toList();
    for (final t in ['Consultar un precio', 'Agregar un producto nuevo', 'Controlar el stock', 'Ver qué separar para cada proveedor',
        'Recargo de cigarrillos', 'Producto para dar de vuelto', 'Promos', 'Cargar días anteriores', 'Ganancia de referencia por categoría']) {
      expect(titulos, isNot(contains(t)), reason: t);
    }
    expect(titulos, containsAll(['Agregar un servicio nuevo', 'Insumos: comprar y contar', 'Cerrar el día', 'Cobrar un turno o un servicio']));
    expect(titulos, isNot(contains('Vender')));
    // Lo que se buscaba con las palabras de almacén se sigue encontrando.
    expect(buscarFunciones('cerrar caja', servicios: true).first.titulo, 'Cerrar el día');
    expect(buscarFunciones('cigarrillos', servicios: true), isEmpty);
    expect(buscarFunciones('tintura', servicios: true).first.titulo, 'Insumos: comprar y contar');
  });

  test('las secciones siguen en orden y "Productos y stock" se llama "Servicios e insumos"', () {
    final encabezados = todasLasFunciones(servicios: true).map((r) => r.encabezado).whereType<String>().toList();
    expect(encabezados, ['Cobrar', 'Servicios e insumos', 'Caja', 'Configuración y cuenta']);
  });

  test('la app Nodo Sur Servicios: además, sin PC, arqueo, varios usuarios ni facturas de compra, aunque el rubro sea de almacén', () {
    edicionActual = Edicion.servicios;
    addTearDown(() => edicionActual = Edicion.almacen);
    final titulos = funcionesDelNegocio().map((f) => f.titulo).toList();
    for (final t in ['Contar la plata de la caja (sin cerrar)', 'Cargar una factura de compra', 'Cambiar de usuario', 'Desconectar de esta PC',
        'Estado de la conexión con la PC', 'Agregar o desactivar usuarios', 'Recargo de cigarrillos', 'Controlar el stock']) {
      expect(titulos, isNot(contains(t)), reason: t);
    }
    expect(titulos, containsAll(['Agregar un servicio nuevo', 'Cerrar el día', 'Actualizar la aplicación']));
  });
}

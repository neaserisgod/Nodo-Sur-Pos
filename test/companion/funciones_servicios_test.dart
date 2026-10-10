import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/funciones_ns.dart';

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
    expect(titulos, containsAll(['Agregar un servicio nuevo', 'Insumos: comprar y contar', 'Cerrar la caja']));
    expect(buscarFunciones('cigarrillos', servicios: true), isEmpty);
    expect(buscarFunciones('tintura', servicios: true).first.titulo, 'Insumos: comprar y contar');
  });

  test('las secciones siguen en orden y "Productos y stock" se llama "Servicios e insumos"', () {
    final encabezados = todasLasFunciones(servicios: true).map((r) => r.encabezado).whereType<String>().toList();
    expect(encabezados, ['Vender', 'Servicios e insumos', 'Caja', 'Configuración y cuenta']);
  });
}

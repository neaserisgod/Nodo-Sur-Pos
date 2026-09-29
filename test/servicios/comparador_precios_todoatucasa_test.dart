// Prueba la conversión de una página cruda de la API (formato real,
// confirmado con una request de verdad el 2026-09-14 — ver el comentario
// de cabecera de `comparador_precios_todoatucasa.dart`) a filas listas
// para guardar. No pega a la red: eso queda para probarlo a mano cuando
// haga falta, acá solo importa que el parseo sea correcto.

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/servicios/comparador_precios_todoatucasa.dart';

void main() {
  test('extrae código de barras, nombre y precio (en centavos) de cada producto', () {
    final filas = filasDesdePagina([
      {
        'bar_code': '039800011329',
        'description': 'Pilas AA E91 Max BP4 CHICA Energizer 4Un',
        'price': 10839.44,
        'reference_price': 2709.86,
        'reference_uom': '1 Un',
      },
      {
        'bar_code': '025700712008',
        'description': 'Bolsas Hermeticas P/Llevar Sellado Int.Chicas Ziploc 14Un',
        'price': 4467.63,
      },
    ]);

    expect(filas, hasLength(2));
    expect(filas[0].codigoBarras, '039800011329');
    expect(filas[0].nombreProducto, 'Pilas AA E91 Max BP4 CHICA Energizer 4Un');
    expect(filas[0].comercio, 'Todo a tu Casa');
    expect(filas[0].precioCentavos, 1083944);
    expect(filas[0].precioReferenciaCentavos, 270986);
    expect(filas[0].unidadReferencia, '1 Un');
    expect(filas[1].precioCentavos, 446763);
  });

  test('sin código de barras válido (o "0") queda con codigoBarras vacío, no se descarta', () {
    final filas = filasDesdePagina([
      {'bar_code': '', 'description': 'Banana x Kg', 'price': 1200.0},
      {'bar_code': '0', 'description': 'Tomate x Kg', 'price': 900.0},
    ]);

    expect(filas, hasLength(2));
    expect(filas.every((f) => f.codigoBarras.isEmpty), isTrue);
    expect(filas[0].nombreProducto, 'Banana x Kg');
  });

  test('descarta productos sin nombre o sin precio', () {
    final filas = filasDesdePagina([
      {'bar_code': '039800011329', 'description': '', 'price': 100.0}, // nombre vacío
      {'bar_code': '039800011329', 'description': 'Algo', 'price': null}, // sin precio
      {'price': 100.0}, // ni siquiera trae description
      {'bar_code': '039800011329', 'description': 'Este sí', 'price': 100.0},
    ]);

    expect(filas, hasLength(1));
    expect(filas.single.nombreProducto, 'Este sí');
  });
}

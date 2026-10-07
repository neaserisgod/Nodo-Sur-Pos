// Aplicar una factura de compra ya revisada (El dueño, 2026-10-07): qué la frena y qué se aplica a cada producto. Funciones puras; lo
// que escribe en la base está en `data/repositorio_facturas_compra.dart`.
//
// Decisiones del dueño: entra stock (casilla por factura), el costo pasa a ser lo que se pagó de verdad, la deuda se carga en la cuenta
// corriente SIEMPRE (también el contado: el pago va por "Pagar proveedor", un solo camino, para no contar el gasto dos veces), y lo que
// no es del local se marca "No va": no suma stock ni cambia costo, pero entra en la deuda.

import 'dinero.dart';

/// Una línea de la factura tal como queda después de revisarla.
class LineaParaAplicar {
  const LineaParaAplicar({
    required this.productoId,
    required this.unidades,
    required this.totalCentavos,
    this.noVa = false,
  });

  /// Null si no se vinculó con ningún producto.
  final int? productoId;

  /// Unidades sueltas que entran (cantidad × unidades por bulto).
  final int unidades;

  /// Lo que costó la línea entera, con todo (`CostoDeLinea.totalCentavos`).
  final int totalCentavos;

  /// No es del local: entra en la deuda, pero no en el stock ni en el costo.
  final bool noVa;
}

/// Lo que se le aplica a un producto: todas sus líneas juntas.
class AplicacionAProducto {
  const AplicacionAProducto({required this.productoId, required this.unidades, required this.costoUnitarioCentavos});

  final int productoId;
  final int unidades;

  /// Lo que pagó cada unidad, redondeado hacia arriba al peso (convención 5). Con el mismo producto en dos líneas a distinto precio,
  /// el promedio de lo que se pagó por todas.
  final int costoUnitarioCentavos;
}

/// "NC", "Nota de crédito"...: una nota de crédito resta en vez de sumar, y eso todavía no se aplica.
bool esNotaDeCredito(String? tipo) {
  final t = (tipo ?? '').toLowerCase().replaceAll(RegExp(r'[^a-zé]'), '');
  return t.startsWith('nc') || t.contains('credito') || t.contains('crédito');
}

/// El número de factura para comparar si ya se cargó: solo los dígitos de cada parte, sin ceros adelante ("0011-00266439" = "11-266439").
/// Null si no tiene ningún dígito.
String? numeroDeFacturaNormalizado(String? numero) {
  final partes = [for (final p in (numero ?? '').split(RegExp(r'\D+'))) if (p.isNotEmpty) p.replaceFirst(RegExp(r'^0+(?=.)'), '')];
  return partes.isEmpty ? null : partes.join('-');
}

/// Por qué no se puede aplicar todavía (vacío = se puede). La factura que no cierra con su total no está acá: se puede aplicar,
/// pero la pantalla pide confirmarlo.
List<String> motivosParaNoAplicar({required int? proveedorId, required String? tipo, required List<LineaParaAplicar> lineas}) {
  return [
    if (proveedorId == null) 'Elegí de qué proveedor es la factura.',
    if (esNotaDeCredito(tipo)) 'Es una nota de crédito: todavía no se aplican desde acá.',
    if (lineas.isEmpty) 'La factura no tiene productos.',
    for (var i = 0; i < lineas.length; i++)
      if (lineas[i].productoId == null && !lineas[i].noVa) 'Línea ${i + 1}: elegí el producto, crealo o marcala "No va".',
  ];
}

/// Las líneas que tocan el stock y el costo, juntas por producto, en el orden en que aparecen.
List<AplicacionAProducto> aplicacionesPorProducto(List<LineaParaAplicar> lineas) {
  final unidades = <int, int>{};
  final totales = <int, int>{};
  for (final l in lineas) {
    final id = l.productoId;
    if (l.noVa || id == null || l.unidades <= 0) continue;
    unidades[id] = (unidades[id] ?? 0) + l.unidades;
    totales[id] = (totales[id] ?? 0) + l.totalCentavos;
  }
  return [
    for (final id in unidades.keys)
      AplicacionAProducto(
        productoId: id,
        unidades: unidades[id]!,
        costoUnitarioCentavos: redondearFraccionHaciaArriba(totales[id]!, unidades[id]!, centavosPorPeso),
      ),
  ];
}

/// Lo que se carga en la cuenta corriente: el total impreso si la factura lo trae (es lo que se le debe al proveedor), o la suma de
/// las líneas si no.
int montoDeLaDeuda({required int? totalImpresoCentavos, required List<LineaParaAplicar> lineas}) =>
    totalImpresoCentavos ?? lineas.fold(0, (a, l) => a + l.totalCentavos);

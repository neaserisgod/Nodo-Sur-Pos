// Descuento sobre el total de una venta — generaliza la Regla 17
// (REGLAS-NEGOCIO.md, "Jam Rock": 15% fijo sobre el importe total) a
// cualquier venta: el cajero tipea un monto o un porcentaje, en vez de
// tener el 15% de Jam Rock hardcodeado. `Ventas.descuentoCentavos`
// (lib/data/tables/ventas.dart) ya existía en el esquema para esto — lo
// que faltaba era este cálculo y quien lo llame.

enum TipoDescuento { monto, porcentaje }

/// [valor] es centavos si `tipo == monto`, basis points (10000 = 100%,
/// mismo lenguaje que `Categoria.markupDefaultBp`) si `tipo == porcentaje`.
///
/// Nunca negativo, nunca mayor que [baseCentavos]: no se puede "regalar"
/// más de lo que vale la venta, ni por un valor negativo tipeado por error
/// ni por un porcentaje o monto que superen el total.
int calcularDescuento({
  required int baseCentavos,
  required TipoDescuento tipo,
  required int valor,
}) {
  final bruto = switch (tipo) {
    TipoDescuento.monto => valor,
    TipoDescuento.porcentaje => (baseCentavos * valor) ~/ 10000,
  };
  return bruto.clamp(0, baseCentavos);
}

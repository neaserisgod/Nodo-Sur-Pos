// El período de las pestañas de Historial (Ventas y Movimientos) — uno solo
// para las dos, así "7 días" quiere decir lo mismo en las dos.

enum PeriodoHistorial { hoy, ayer, ultimaSemana, esteMes }

extension EtiquetaPeriodoHistorial on PeriodoHistorial {
  String get etiqueta => switch (this) {
    PeriodoHistorial.hoy => 'Hoy',
    PeriodoHistorial.ayer => 'Ayer',
    PeriodoHistorial.ultimaSemana => '7 días',
    PeriodoHistorial.esteMes => 'Este mes',
  };

  ({DateTime desde, DateTime hasta}) rango() {
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    return switch (this) {
      PeriodoHistorial.hoy => (desde: hoy, hasta: hoy.add(const Duration(days: 1))),
      PeriodoHistorial.ayer => (desde: hoy.subtract(const Duration(days: 1)), hasta: hoy),
      PeriodoHistorial.ultimaSemana => (desde: hoy.subtract(const Duration(days: 6)), hasta: hoy.add(const Duration(days: 1))),
      PeriodoHistorial.esteMes => (desde: DateTime(ahora.year, ahora.month, 1), hasta: hoy.add(const Duration(days: 1))),
    };
  }
}

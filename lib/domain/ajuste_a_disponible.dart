// Ajusta lo que hay que separar a la plata que hay de verdad en cada caja
// (Bruno, 2026-09-26: "que tenga en cuenta los montos actuales tanto de
// efectivo como de mp"). La división cajón/MP de `separacion_por_medio.dart`
// dice de dónde DEBERÍA salir cada peso según cómo se cobró; esto la
// corrige cuando el cajón (o MP) no tiene tanto: lo que falta de un lado se
// pasa al otro si ahí sobra, repartido entre los proveedores en proporción a
// lo que cada uno tenía de ese lado. El total de cada proveedor nunca
// cambia — solo de qué caja sale. Si no alcanza entre las dos, se informa
// cuánto falta en vez de inventarlo.

class ParteSeparacion {
  final int efectivoCentavos;
  final int mpCentavos;

  const ParteSeparacion({required this.efectivoCentavos, required this.mpCentavos});

  int get totalCentavos => efectivoCentavos + mpCentavos;

  @override
  bool operator ==(Object other) =>
      other is ParteSeparacion && other.efectivoCentavos == efectivoCentavos && other.mpCentavos == mpCentavos;

  @override
  int get hashCode => Object.hash(efectivoCentavos, mpCentavos);

  @override
  String toString() => 'ParteSeparacion(efectivo: $efectivoCentavos, mp: $mpCentavos)';
}

class ResultadoAjuste<K> {
  final Map<K, ParteSeparacion> partes;

  /// Lo que se pasó del cajón a MP (positivo) o de MP al cajón (negativo).
  final int corridoAMpCentavos;

  /// Lo que no alcanza entre las dos cajas — 0 si alcanza.
  final int faltanteCentavos;

  const ResultadoAjuste({
    required this.partes,
    required this.corridoAMpCentavos,
    required this.faltanteCentavos,
  });
}

/// [efectivoDisponibleCentavos]/[mpDisponibleCentavos] pueden ser negativos
/// (ya separado más de lo que hay): se tratan como 0 de lugar libre.
ResultadoAjuste<K> ajustarADisponible<K>({
  required Map<K, ParteSeparacion> partes,
  required int efectivoDisponibleCentavos,
  required int mpDisponibleCentavos,
}) {
  final efectivoPedido = partes.values.fold<int>(0, (a, p) => a + p.efectivoCentavos);
  final mpPedido = partes.values.fold<int>(0, (a, p) => a + p.mpCentavos);
  final efectivoLibre = efectivoDisponibleCentavos < 0 ? 0 : efectivoDisponibleCentavos;
  final mpLibre = mpDisponibleCentavos < 0 ? 0 : mpDisponibleCentavos;

  final faltaEnCajon = efectivoPedido - efectivoLibre;
  final faltaEnMp = mpPedido - mpLibre;

  // Solo uno de los dos lados puede necesitar correrse al otro — si faltan
  // los dos, no hay adónde mover nada.
  var corridoAMp = 0;
  if (faltaEnCajon > 0 && faltaEnMp < 0) {
    corridoAMp = faltaEnCajon < -faltaEnMp ? faltaEnCajon : -faltaEnMp;
  } else if (faltaEnMp > 0 && faltaEnCajon < 0) {
    final aCajon = faltaEnMp < -faltaEnCajon ? faltaEnMp : -faltaEnCajon;
    corridoAMp = -aCajon;
  }

  final faltante = (faltaEnCajon > 0 ? faltaEnCajon : 0) +
      (faltaEnMp > 0 ? faltaEnMp : 0) -
      corridoAMp.abs();

  return ResultadoAjuste(
    partes: corridoAMp == 0
        ? Map.of(partes)
        : _repartir(partes, corridoAMp, corridoAMp > 0 ? efectivoPedido : mpPedido),
    corridoAMpCentavos: corridoAMp,
    faltanteCentavos: faltante,
  );
}

/// Mueve [corridoAMp] entre los lados de cada parte, en proporción a lo que
/// cada una tenía del lado que se vacía ([base] = total de ese lado). El
/// resto de la división entera se asigna a las primeras partes, un centavo
/// cada una, para que la suma sea exacta.
Map<K, ParteSeparacion> _repartir<K>(Map<K, ParteSeparacion> partes, int corridoAMp, int base) {
  final aMover = corridoAMp.abs();
  final haciaMp = corridoAMp > 0;
  final claves = partes.keys.toList();
  final movido = <K, int>{
    for (final k in claves)
      k: (haciaMp ? partes[k]!.efectivoCentavos : partes[k]!.mpCentavos) * aMover ~/ base,
  };
  var resto = aMover - movido.values.fold<int>(0, (a, m) => a + m);
  for (final k in claves) {
    if (resto == 0) break;
    final ladoQueSeVacia = haciaMp ? partes[k]!.efectivoCentavos : partes[k]!.mpCentavos;
    if (movido[k]! < ladoQueSeVacia) {
      movido[k] = movido[k]! + 1;
      resto--;
    }
  }
  return {
    for (final k in claves)
      k: haciaMp
          ? ParteSeparacion(
              efectivoCentavos: partes[k]!.efectivoCentavos - movido[k]!,
              mpCentavos: partes[k]!.mpCentavos + movido[k]!,
            )
          : ParteSeparacion(
              efectivoCentavos: partes[k]!.efectivoCentavos + movido[k]!,
              mpCentavos: partes[k]!.mpCentavos - movido[k]!,
            ),
  };
}

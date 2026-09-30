// Helpers de dinero. Todos los montos son enteros de centavos (Regla 1 de
// REGLAS-NEGOCIO.md): nunca double, para que el arqueo diario no acumule
// error de punto flotante disfrazado de diferencia de caja.

/// Centavos que tiene un peso entero. El negocio no maneja centavos: todo
/// precio o costo calculado se redondea hacia arriba a un múltiplo de esto.
const int centavosPorPeso = 100;

/// Formatea centavos como moneda es-AR, SIN centavos: 150050 → "$1.501"
/// (El dueño, 2026-09-16: "dejemos de mostrar centavos" — coherente con "el
/// negocio no maneja centavos" de arriba). Redondea al peso más cercano,
/// no trunca — mostrar de menos sistemáticamente sería más engañoso que
/// redondear, y esto es solo la CAPA DE TEXTO: `precioCentavos` sigue
/// siendo el entero de centavos real (Regla 1), esto no cambia qué se
/// guarda ni qué se calcula, solo cómo se lee.
///
/// Es el único punto de conversión centavos → texto (Regla 1): si el
/// formato se repitiera en cada pantalla, un día alguien lo escribe distinto
/// y el mismo monto se ve diferente en dos lugares.
///
/// [conSigno] en `false` omite el "$" — para las líneas del carrito de la
/// pantalla de venta (fase 11): en una columna donde todo es plata, repetir
/// el signo en cada fila es ruido, no información.
String formatearARS(int centavos, {bool conSigno = true}) {
  final negativo = centavos < 0;
  final absoluto = centavos.abs();
  final pesos = (absoluto + centavosPorPeso ~/ 2) ~/ centavosPorPeso;
  final signo = negativo ? '-' : '';
  final simbolo = conSigno ? r'$' : '';
  return '$signo$simbolo${_agruparMiles(pesos)}';
}

/// Formatea centavos como decimal para la API de Mercado Pago (Fase 12,
/// Orders API): 174000 → "1740.00". Sin agrupador de miles, sin símbolo,
/// punto como separador decimal — un formato completamente distinto al de
/// [formatearARS], que da `"$1.740,00"` (agrupado, con signo, coma
/// decimal). Mezclarlos mandaría un monto inválido o, peor, uno décuplo o
/// centuplicado sin que la API avise.
///
/// Precondición: [centavos] >= 0 (todo monto de venta de este negocio lo es).
String formatearParaMercadoPago(int centavos) {
  final pesos = centavos ~/ centavosPorPeso;
  final centavosResto = centavos % centavosPorPeso;
  return '$pesos.${centavosResto.toString().padLeft(2, '0')}';
}

String _agruparMiles(int pesos) {
  final texto = pesos.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < texto.length; i++) {
    final posicionDesdeElFinal = texto.length - i;
    if (i != 0 && posicionDesdeElFinal % 3 == 0) buffer.write('.');
    buffer.write(texto[i]);
  }
  return buffer.toString();
}

/// Parsea un monto en texto a centavos.
///
/// Acepta "1.500,50" (es-AR), "1500.50", "$1.500,50" y "1500". Es el único
/// punto de conversión texto → centavos (Regla 1): así todos los campos de
/// carga de precio/costo entienden los mismos formatos.
int parsearARS(String valor) {
  var limpio = valor.replaceAll('\$', '').trim();
  // Quita puntos de miles: un punto seguido de exactamente 3 dígitos es
  // separador de miles en es-AR, nunca decimal (el decimal usa coma).
  limpio = limpio.replaceAllMapped(RegExp(r'\.(\d{3})'), (m) => m.group(1)!);
  limpio = limpio.replaceAll(',', '.');
  final numero = double.tryParse(limpio);
  if (numero == null) {
    throw FormatException('Monto inválido: "$valor"');
  }
  return (numero * centavosPorPeso).round();
}

/// Redondea [centavos] hacia arriba al múltiplo de [pasoCentavos] más cercano.
///
/// Precondición: [centavos] >= 0 y [pasoCentavos] > 0 (todo monto de venta o
/// precio de este negocio es no negativo).
///
/// Único punto de esta fórmula (Regla 3 de convenciones): la usa el redondeo
/// del total de venta en efectivo, al paso configurable (Regla 2 de negocio).
int redondearHaciaArriba(int centavos, int pasoCentavos) {
  return redondearFraccionHaciaArriba(centavos, 1, pasoCentavos);
}

/// Redondea la fracción [numerador]/[denominador] hacia arriba al múltiplo
/// de [paso] más cercano, en una sola operación exacta con enteros.
///
/// La usa el triángulo de `markup` para llevar un precio o costo calculado
/// al peso entero (Regla 1) sin encadenar un redondeo al centavo primero:
/// redondear dos veces (al centavo y después al peso) puede alejar el
/// resultado final del valor exacto en más de lo que un solo redondeo lo haría.
///
/// Precondición: [numerador] >= 0, [denominador] > 0, [paso] > 0.
int redondearFraccionHaciaArriba(int numerador, int denominador, int paso) {
  final unidades = _ceilDiv(numerador, denominador * paso);
  return unidades * paso;
}

int _ceilDiv(int a, int b) => (a + b - 1) ~/ b;

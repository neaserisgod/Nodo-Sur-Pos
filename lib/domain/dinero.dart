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
///
/// [separado] deja un espacio entre el signo y el número (`$ 16.300`): es como escribe la plata el mock v4 de la PC
/// (2026-10-06), y las pantallas hechas con ese mock lo piden así. El resto (tickets, PDF, celular) sigue sin espacio.
String formatearARS(int centavos, {bool conSigno = true, bool separado = false}) {
  final negativo = centavos < 0;
  final absoluto = centavos.abs();
  final pesos = (absoluto + centavosPorPeso ~/ 2) ~/ centavosPorPeso;
  final signo = negativo ? '-' : '';
  final simbolo = conSigno ? (separado ? r'$ ' : r'$') : '';
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

/// Tope de un monto tipeado: $100.000.000.000 en centavos. Muy por encima de
/// cualquier plata de este negocio, y lo bastante bajo para que ninguna cuenta
/// posterior (× 10.000 de un porcentaje, × cantidad) desborde un `int` de 64
/// bits: un "1e30" o un dígito de más no puede terminar en un total basura.
const int maximoMontoCentavos = 10000000000000;

final _soloDigitos = RegExp(r'^\d+$');
final _miles = RegExp(r'^\d{1,3}(\.\d{3})+$');

/// Parsea un monto en texto a centavos.
///
/// Acepta "1.500,50" (es-AR), "1500.50", "$1.500,50", "1500" y "-200". Es el
/// único punto de conversión texto → centavos (Regla 1): así todos los campos
/// de carga de precio/costo entienden los mismos formatos.
///
/// Estricto a propósito: todo lo que no sea un número decimal común lanza
/// [FormatException] — "1e3", "NaN", "Infinity", "1,2,3", "12abc" o un monto
/// fuera de [maximoMontoCentavos]. `double.tryParse` aceptaba los primeros
/// (y "1e3" se leía como $1.000, "Infinity" tiraba un error no capturado por
/// quien solo atrapa `FormatException`). Se hace con enteros, sin pasar por
/// `double`: el redondeo al centavo es exacto (medio centavo hacia arriba).
///
/// Regla del punto: es separador de miles solo si el texto entero es grupos
/// de exactamente 3 dígitos ("1.500", "2.093.000", nunca "0.500" ni "1.5");
/// si no, es decimal. La coma es siempre decimal (es-AR).
int parsearARS(String valor) {
  final original = valor;
  var limpio = valor.replaceAll(r'$', '').replaceAll(RegExp(r'\s'), '');
  var negativo = false;
  if (limpio.startsWith('-')) {
    negativo = true;
    limpio = limpio.substring(1);
  }
  Never invalido() => throw FormatException('Monto inválido: "$original"');
  if (limpio.isEmpty) invalido();

  String entera;
  String fraccion = '';
  final coma = limpio.indexOf(',');
  if (coma != -1) {
    if (limpio.indexOf(',', coma + 1) != -1) invalido();
    entera = limpio.substring(0, coma);
    fraccion = limpio.substring(coma + 1);
    // Con coma decimal, los puntos de la parte entera solo pueden ser miles.
    if (entera.contains('.')) {
      if (!_miles.hasMatch(entera)) invalido();
      entera = entera.replaceAll('.', '');
    }
  } else if (_miles.hasMatch(limpio) && !limpio.startsWith('0.')) {
    entera = limpio.replaceAll('.', '');
  } else {
    final punto = limpio.indexOf('.');
    if (punto == -1) {
      entera = limpio;
    } else {
      if (limpio.indexOf('.', punto + 1) != -1) invalido();
      entera = limpio.substring(0, punto);
      fraccion = limpio.substring(punto + 1);
    }
  }

  if (entera.isEmpty && fraccion.isEmpty) invalido();
  if (entera.isEmpty) entera = '0';
  if (!_soloDigitos.hasMatch(entera)) invalido();
  if (fraccion.isNotEmpty && !_soloDigitos.hasMatch(fraccion)) invalido();
  // Más dígitos que el tope ya son demasiado grandes: se corta antes de parsear.
  if (entera.length > 14) invalido();

  final pesos = int.parse(entera);
  final dosDecimales = fraccion.padRight(2, '0');
  var centavos = int.parse(dosDecimales.substring(0, 2));
  // Medio centavo hacia arriba, mirando solo el tercer decimal.
  if (dosDecimales.length > 2 && int.parse(dosDecimales[2]) >= 5) centavos += 1;

  final total = pesos * centavosPorPeso + centavos;
  if (total > maximoMontoCentavos) invalido();
  return negativo ? -total : total;
}

/// Redondea [centavos] hacia arriba al múltiplo de [pasoCentavos] más cercano.
///
/// Un [pasoCentavos] ≤ 0 lanza [ArgumentError] (no hay múltiplos de 0): la
/// capa que lo guarda como configuración lo rechaza antes, y
/// `redondeoDeVenta` lo trata como "sin redondeo" para que una configuración
/// rota nunca trabe el cobro.
///
/// Único punto de esta fórmula (Regla 3 de convenciones): la usa el redondeo
/// del total de venta en efectivo, al paso configurable (Regla 2 de negocio).
int redondearHaciaArriba(int centavos, int pasoCentavos) {
  return redondearFraccionHaciaArriba(centavos, 1, pasoCentavos);
}

/// Redondea la fracción [numerador]/[denominador] hacia arriba al múltiplo
/// de [paso] más cercano, en una sola operación exacta con enteros.
///
/// La usa el triángulo de `ganancia` para llevar un precio o costo calculado
/// al peso entero (Regla 1) sin encadenar un redondeo al centavo primero:
/// redondear dos veces (al centavo y después al peso) puede alejar el
/// resultado final del valor exacto en más de lo que un solo redondeo lo haría.
///
/// Es un techo verdadero también con [numerador] negativo (−150/100 → −1, no
/// 0): la división entera de Dart trunca hacia cero y con negativos daba un
/// resultado un paso más abajo. [denominador] y [paso] tienen que ser > 0.
int redondearFraccionHaciaArriba(int numerador, int denominador, int paso) {
  if (denominador <= 0) throw ArgumentError('denominador tiene que ser > 0');
  if (paso <= 0) throw ArgumentError('paso tiene que ser > 0');
  final unidades = _ceilDiv(numerador, denominador * paso);
  return unidades * paso;
}

/// Techo de a/b con b > 0, correcto para a negativo.
int _ceilDiv(int a, int b) {
  final cociente = a ~/ b; // trunca hacia cero
  return a > 0 && a % b != 0 ? cociente + 1 : cociente;
}

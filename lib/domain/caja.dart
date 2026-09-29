// Caja y arqueo (Regla 10). La lata de cigarrillos es efectivo físico de
// verdad, no un saldo contable: al cierre, Bruno saca billetes del cajón y
// los mete en una lata aparte para pagarle a Serra Cigarros. Por eso la
// separación ocurre una vez al día, al cerrar, y no en cada venta.
//
// El orden es obligatorio: primero se cuenta, después se compara, recién
// después se separa (Regla 10, "primero se cuenta, después se compara"). Si
// la separación de cigarrillos participara del cálculo de la diferencia, un
// error al separar se confundiría con un descuadre de caja y se perdería la
// señal de auditoría.

/// Caja esperada = inicial + efectivo de ventas − gastos en efectivo +
/// ingresos en efectivo (fórmula de la Regla 10, extendida 2026-09-13 con
/// "Ingreso rápido" — Bruno: un botón de ingreso de dinero, espejo de
/// "Gasto rápido", con las mismas tres cajas).
///
/// NO suma el redondeo: "efectivo de ventas" sale de los movimientos de
/// caja, que ya guardan el total FINAL cobrado (post-redondeo, lo que
/// físicamente entra al cajón). Sumarlo otra vez daba un faltante falso
/// igual al redondeo acumulado (~$3.000/día). Revisión 2026-09-29.
///
/// Los cigarrillos cobrados en efectivo van adentro de "efectivo de ventas"
/// como cualquier otra venta: la separación no participa de este cálculo.
int cajaEsperadaCentavos({
  required int inicialCentavos,
  required int efectivoDeVentasCentavos,
  required int gastosEnEfectivoCentavos,
  required int ingresosEnEfectivoCentavos,
}) {
  return inicialCentavos +
      efectivoDeVentasCentavos -
      gastosEnEfectivoCentavos +
      ingresosEnEfectivoCentavos;
}

/// Diferencia de arqueo = contado − esperado. Positiva si sobra, negativa si
/// falta. Se calcula ANTES de separar cigarrillos (Regla 10).
///
/// Misma función para efectivo y para Mercado Pago (ver [mpEsperadoCentavos]):
/// "contado − esperado" no cambia de significado según la caja.
int diferenciaArqueo({
  required int contadoCentavos,
  required int esperadoCentavos,
}) {
  return contadoCentavos - esperadoCentavos;
}

/// MP esperado = saldo inicial + lo cobrado por medios no efectivo en las
/// ventas de la sesión, menos los gastos pagados con Mercado Pago — misma
/// forma que `cajaEsperadaCentavos`, sin el redondeo (Regla 2: eso es propio
/// del efectivo).
///
/// [inicialCentavos] volvió a existir el 2026-09-12 (Bruno, reboot de la
/// base): hasta esa fecha MP arrancaba siempre en 0 (`DECISIONES.md`,
/// "Mercado Pago se arquea como una caja más") porque lo que importaba era
/// solo lo movido en el día, no el saldo de la cuenta — pero esa cuenta es
/// real y no queda en 0 después de un reseteo de datos. Sigue sin ser el
/// modelo viejo que esa decisión descartó (preguntar el saldo actual al
/// abrir Y al cerrar, sin relación con lo vendido): acá el inicial es un
/// término que se SUMA una vez, igual que el fondo inicial del efectivo — el
/// resto de la fórmula (y la explicación de por qué la diferencia casi nunca
/// da cero) no cambió.
/// [ingresosPorMpCentavos] mismo agregado 2026-09-13 que
/// [cajaEsperadaCentavos] — un "Ingreso rápido" a Mercado Pago (poco común,
/// pero la caja está disponible igual que para gastar) suma acá.
int mpEsperadoCentavos({
  required int inicialCentavos,
  required int pagosNoEfectivoCentavos,
  required int gastosPorMpCentavos,
  required int ingresosPorMpCentavos,
}) {
  return inicialCentavos +
      pagosNoEfectivoCentavos -
      gastosPorMpCentavos +
      ingresosPorMpCentavos;
}

class ResultadoSeparacionCigarrillos {
  /// Lo que efectivamente se apartó a la lata en este cierre.
  final int separadoCentavos;

  /// Lo que no alcanzó a separarse y se arrastra al próximo cierre.
  final int pendienteCentavos;

  /// Efectivo contado − lo separado: lo que queda en el cajón normal.
  final int quedaEnCajonCentavos;

  /// true si no alcanzó el efectivo contado para separar todo lo que
  /// correspondía.
  final bool esSeparacionParcial;

  const ResultadoSeparacionCigarrillos({
    required this.separadoCentavos,
    required this.pendienteCentavos,
    required this.quedaEnCajonCentavos,
    required this.esSeparacionParcial,
  });
}

/// Separa a la lata el precio de lista de los cigarrillos vendidos, sin
/// importar el medio de pago (Regla 6): los cobrados por QR quedaron en
/// Mercado Pago, no en el cajón, pero a Serra se le paga en efectivo igual —
/// esa plata sale del efectivo que entró por las demás ventas del día. El
/// recargo por pago virtual existe justamente para cubrir ese costo.
///
/// No se puede separar más efectivo del que hay físicamente contado: si no
/// alcanza (mucho vendido por QR, poco en efectivo), se separa lo que hay y
/// el resto queda pendiente para el próximo cierre. No es un error del
/// sistema, es que esa plata todavía está en Mercado Pago.
ResultadoSeparacionCigarrillos separarCigarrillos({
  required int efectivoContadoCentavos,
  required int precioListaCigarrillosVendidosHoyCentavos,
  required int pendienteDeCierresAnterioresCentavos,
}) {
  final montoASeparar =
      precioListaCigarrillosVendidosHoyCentavos +
      pendienteDeCierresAnterioresCentavos;
  final separado = montoASeparar < efectivoContadoCentavos
      ? montoASeparar
      : efectivoContadoCentavos;
  final pendiente = montoASeparar - separado;

  return ResultadoSeparacionCigarrillos(
    separadoCentavos: separado,
    pendienteCentavos: pendiente,
    quedaEnCajonCentavos: efectivoContadoCentavos - separado,
    esSeparacionParcial: pendiente > 0,
  );
}

/// Lo que queda en el cajón normal después de separar cigarrillos a la
/// lata — la línea "QUEDA EN EL CAJON" del papel. Es la "Caja inicial
/// NORMAL" que se precarga al turno que entra (Bruno, sesión del
/// 31/08/2026): el que se va cuenta y separa, el que entra arranca de ahí
/// en vez de volver a contar la misma plata.
int quedaEnCajonCentavos({
  required int efectivoContadoCentavos,
  required int lataSeparadoCentavos,
}) {
  return efectivoContadoCentavos - lataSeparadoCentavos;
}

/// Saldo de la lata para el próximo cierre: lo que tenía + lo separado hoy −
/// lo que ya se le pagó a Serra desde ahí + lo que se le haya ingresado a
/// mano (mismo agregado 2026-09-13 que las dos funciones de arriba).
int lataNuevaCentavos({
  required int lataInicialCentavos,
  required int separadoHoyCentavos,
  required int pagosASerraDesdeLataCentavos,
  required int ingresosALaLataCentavos,
}) {
  return lataInicialCentavos +
      separadoHoyCentavos -
      pagosASerraDesdeLataCentavos +
      ingresosALaLataCentavos;
}

/// Cada cuánto se sugiere un arqueo durante el turno (2026-09-12; no
/// bloqueante desde el 2026-09-15; opcional desde el 2026-09-28, y el aviso
/// es solo un punto en la campanita) — fijo en el código, no configurable. No corta la sesión (a diferencia de un
/// cierre real): es un chequeo de disciplina que se registra y listo, el
/// arrastre de cigarrillos y el resto de la sesión siguen exactamente igual.
const Duration intervaloArqueoObligatorio = Duration(hours: 2);

/// true si ya pasaron 2 horas desde [desde] (la apertura de la sesión, o el
/// último arqueo intermedio registrado, lo que sea más reciente) — muestra
/// el aviso de contar de nuevo (ver `VentaControlador.arqueoIntermedioVencido`),
/// sin bloquear la venta.
bool necesitaArqueoIntermedio({
  required DateTime desde,
  required DateTime ahora,
}) {
  return ahora.difference(desde) >= intervaloArqueoObligatorio;
}

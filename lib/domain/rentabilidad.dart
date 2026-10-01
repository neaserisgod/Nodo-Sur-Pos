// Estado de resultados del mes y plata realmente retirable (asistente contable
// del POS). Funciones puras, todo en centavos y basis points.
//
// Es la cuenta que faltaba entre "ganancia bruta" y "lo que me puedo llevar":
//
//     ventas netas
//   − costo de la mercadería vendida (costo-foto, Regla 4)
//   = GANANCIA BRUTA
//   − gastos fijos del mes
//   − gastos variables (gastos rápidos que no son un fijo)
//   = RESULTADO OPERATIVO            (lo que deja el negocio funcionando)
//   − sueldo objetivo del dueño
//   = RESULTADO DESPUÉS DEL SUELDO   (lo que queda para el negocio)
//
// Y por separado, los retiros que ya hizo el dueño: la ganancia bruta NO es
// plata disponible (todavía hay que pagar los gastos), por eso lo retirable
// sale del resultado y no de la ganancia bruta.
//
// Principio de todo el módulo: avisar antes que inventar (como Equilibrio). Si
// falta un dato —ventas sin costo cargado, un fijo sin monto— el número se
// marca incompleto, nunca se completa con un 0 que haga parecer que hay más.

import 'ganancia.dart';

/// Los insumos del mes, ya agregados por la capa de datos.
class DatosDelMes {
  const DatosDelMes({
    required this.ventasNetasCentavos,
    required this.ventasConCostoCentavos,
    required this.gananciaBrutaCentavos,
    required this.gastosFijosCentavos,
    required this.gastosVariablesCentavos,
    required this.sueldoObjetivoCentavos,
    required this.retirosDelMesCentavos,
    this.reservaCentavos = 0,
    this.arrastreCentavos = 0,
    this.fijosCompletos = true,
  });

  /// Todo lo vendido, neto de descuentos (lo que de verdad entró por las ventas
  /// que se calculan por línea). Incluye lo vendido sin costo.
  final int ventasNetasCentavos;

  /// La parte de [ventasNetasCentavos] con costo conocido: el denominador del
  /// margen real.
  final int ventasConCostoCentavos;

  /// Suma de (precio − costo) de las líneas CON costo.
  final int gananciaBrutaCentavos;

  /// Fijos del mes sin el sueldo del dueño (que va aparte).
  final int gastosFijosCentavos;

  /// Gastos del mes que no son un fijo (gasto rápido).
  final int gastosVariablesCentavos;

  /// Sueldo mensual que el dueño se fijó como objetivo. 0 si no cargó uno.
  final int sueldoObjetivoCentavos;

  /// Lo que el dueño ya retiró en el mes (movimientos tipo RETIRO).
  final int retirosDelMesCentavos;

  /// Colchón que el dueño quiere dejar siempre en el negocio (opcional).
  final int reservaCentavos;

  /// Lo que quedó sin retirar del mes anterior (su retirable, nunca negativo):
  /// la ganancia de los últimos días de un mes se retira recién en el
  /// siguiente, y sin esto el primer retiro de cada mes se vería como exceso.
  /// 0 si el mes anterior no se puede calcular completo (más vale avisar de
  /// más que dar por retirable plata que no se sabe si existe).
  final int arrastreCentavos;

  /// false si algún fijo activo no tiene monto cargado este mes.
  final bool fijosCompletos;

  int get vendidoSinCostoCentavos => ventasNetasCentavos - ventasConCostoCentavos;
}

class EstadoDeResultados {
  const EstadoDeResultados({
    required this.ventasNetasCentavos,
    required this.costoMercaderiaCentavos,
    required this.gananciaBrutaCentavos,
    required this.gastosFijosCentavos,
    required this.gastosVariablesCentavos,
    required this.resultadoOperativoCentavos,
    required this.sueldoObjetivoCentavos,
    required this.resultadoDespuesDelSueldoCentavos,
    required this.retirosDelMesCentavos,
    required this.retirableCentavos,
    required this.excesoDeRetirosCentavos,
    required this.gananciaBrutaBp,
    required this.vendidoSinCostoCentavos,
    required this.esCompleto,
    required this.advertencias,
  });

  final int ventasNetasCentavos;

  /// Costo de lo vendido CON costo conocido = ventas con costo − ganancia bruta.
  final int costoMercaderiaCentavos;
  final int gananciaBrutaCentavos;
  final int gastosFijosCentavos;
  final int gastosVariablesCentavos;

  /// Ganancia bruta − fijos − variables. Puede ser negativo: el negocio perdió.
  final int resultadoOperativoCentavos;
  final int sueldoObjetivoCentavos;

  /// Resultado operativo − sueldo objetivo.
  final int resultadoDespuesDelSueldoCentavos;
  final int retirosDelMesCentavos;

  /// Lo que se puede retirar HOY sin comerse los gastos del negocio:
  /// resultado operativo + arrastre del mes anterior − reserva − retiros ya
  /// hechos, nunca negativo.
  final int retirableCentavos;

  /// Cuánto de lo ya retirado excede lo que el resultado operativo justifica.
  /// Positivo = el dueño se llevó plata que el negocio todavía no ganó.
  final int excesoDeRetirosCentavos;

  /// Ganancia bruta / ventas con costo, en basis points (misma definición que
  /// el resto de la app: ganancia sobre el precio). Null sin ventas con costo.
  final int? gananciaBrutaBp;

  final int vendidoSinCostoCentavos;

  /// false si hay ventas sin costo o fijos sin cargar: los números son una
  /// cota, no el resultado completo. La pantalla tiene que decirlo.
  final bool esCompleto;
  final List<String> advertencias;
}

EstadoDeResultados calcularEstadoDeResultados(DatosDelMes d) {
  final costo = d.ventasConCostoCentavos - d.gananciaBrutaCentavos;
  final operativo = d.gananciaBrutaCentavos - d.gastosFijosCentavos - d.gastosVariablesCentavos;
  final despuesDelSueldo = operativo - d.sueldoObjetivoCentavos;

  // Retirable: del resultado operativo, menos el colchón, menos lo que ya se
  // llevó. El sueldo objetivo NO se resta: es un tope de referencia, y el
  // dueño cobra su sueldo justamente retirando — restarlo dos veces haría que
  // retirar el sueldo pareciera un exceso.
  final techo = operativo - d.reservaCentavos + d.arrastreCentavos;
  final retirable = techo - d.retirosDelMesCentavos;
  final exceso = d.retirosDelMesCentavos - (techo < 0 ? 0 : techo);

  final bp = d.ventasConCostoCentavos > 0
      ? gananciaBpDesdeCostoYPrecio(costo, d.ventasConCostoCentavos)
      : null;

  final advertencias = <String>[
    if (d.vendidoSinCostoCentavos > 0)
      'Hay ventas sin costo cargado: la ganancia real es distinta (puede ser menor).',
    if (!d.fijosCompletos) 'Faltan montos de gastos fijos de este mes: el resultado está sobreestimado.',
    if (d.sueldoObjetivoCentavos == 0) 'No cargaste un sueldo objetivo para el dueño.',
    if (operativo < 0) 'El negocio no cubre sus gastos este mes.',
    if (exceso > 0) 'Ya retiraste más de lo que el negocio ganó después de gastos.',
  ];

  return EstadoDeResultados(
    ventasNetasCentavos: d.ventasNetasCentavos,
    costoMercaderiaCentavos: costo,
    gananciaBrutaCentavos: d.gananciaBrutaCentavos,
    gastosFijosCentavos: d.gastosFijosCentavos,
    gastosVariablesCentavos: d.gastosVariablesCentavos,
    resultadoOperativoCentavos: operativo,
    sueldoObjetivoCentavos: d.sueldoObjetivoCentavos,
    resultadoDespuesDelSueldoCentavos: despuesDelSueldo,
    retirosDelMesCentavos: d.retirosDelMesCentavos,
    retirableCentavos: retirable < 0 ? 0 : retirable,
    excesoDeRetirosCentavos: exceso < 0 ? 0 : exceso,
    gananciaBrutaBp: bp,
    vendidoSinCostoCentavos: d.vendidoSinCostoCentavos,
    esCompleto: d.vendidoSinCostoCentavos == 0 && d.fijosCompletos,
    advertencias: advertencias,
  );
}

/// Qué pasa si el dueño quiere retirar [montoCentavos] ahora.
class EvaluacionDeRetiro {
  const EvaluacionDeRetiro({
    required this.montoCentavos,
    required this.retirableCentavos,
    required this.excedeCentavos,
  });

  final int montoCentavos;
  final int retirableCentavos;

  /// Lo que pasa de lo retirable. 0 si entra.
  final int excedeCentavos;

  /// El retiro se permite siempre (decisión del dueño, 2026-10-01: "avisa y
  /// pide confirmar"), pero si excede hay que mostrar el aviso y confirmar.
  bool get requiereConfirmacion => excedeCentavos > 0;
}

EvaluacionDeRetiro evaluarRetiro({required int montoCentavos, required EstadoDeResultados estado}) {
  final excede = montoCentavos - estado.retirableCentavos;
  return EvaluacionDeRetiro(
    montoCentavos: montoCentavos,
    retirableCentavos: estado.retirableCentavos,
    excedeCentavos: excede < 0 ? 0 : excede,
  );
}

/// Margen mínimo (ganancia sobre el precio, en bp) que tienen que dejar las
/// ventas para cubrir fijos + sueldo + ganancia a retener, dada una venta
/// estimada del mes. Null si no hay venta estimada, o si el objetivo pide un
/// margen de 100% o más (imposible: ningún precio lo logra).
///
/// Ejemplo: fijos $1.350.000 + sueldo $1.000.000 + retener $500.000 sobre
/// $5.000.000 de venta → 57%. Es el margen del NEGOCIO (mezcla de productos),
/// no un porcentaje para ponerle a cada precio sin mirar el mix.
int? margenNecesarioBp({
  required int gastosFijosCentavos,
  required int gastosVariablesCentavos,
  required int sueldoObjetivoCentavos,
  required int gananciaARetenerCentavos,
  required int ventaEstimadaCentavos,
}) {
  if (ventaEstimadaCentavos <= 0) return null;
  final necesario = gastosFijosCentavos + gastosVariablesCentavos + sueldoObjetivoCentavos + gananciaARetenerCentavos;
  if (necesario <= 0) return 0;
  // Techo: quedarse corto por un redondeo haría que el objetivo no se cumpla.
  final bp = (necesario * 10000 + ventaEstimadaCentavos - 1) ~/ ventaEstimadaCentavos;
  return bp >= 10000 ? null : bp;
}

/// Venta mensual necesaria para cubrir [necesarioCentavos] con un margen de
/// [margenBp]: necesario / margen. Null con margen ≤ 0.
int? ventaNecesariaCentavos({required int necesarioCentavos, required int margenBp}) {
  if (margenBp <= 0) return null;
  return (necesarioCentavos * 10000 + margenBp - 1) ~/ margenBp;
}

/// Precio mínimo SUGERIDO para un producto: el que deja [margenBp] de ganancia
/// sobre el precio, redondeado a la próxima centena. Es una sugerencia para
/// mostrar y comparar: nunca se aplica solo (Regla 14).
int precioMinimoSugeridoCentavos({required int costoCentavos, required int margenBp}) =>
    precioConGananciaACentena(costoCentavos, margenBp);

/// Si el precio actual de un producto deja menos ganancia que el margen
/// necesario. Un producto sin costo (≤ 0) o sin precio no se puede evaluar.
bool estaPorDebajoDelMargen({required int costoCentavos, required int precioCentavos, required int margenNecesarioBp}) {
  if (costoCentavos <= 0 || precioCentavos <= 0) return false;
  return gananciaBpDesdeCostoYPrecio(costoCentavos, precioCentavos) < margenNecesarioBp;
}

/// El margen necesario del mes contra los gastos REALES ya cargados en [estado]
/// (fijos, variables y sueldo objetivo), la ganancia que el dueño quiere
/// retener y la venta que espera. Un solo lugar para esta cuenta: la pantalla
/// no arma el `margenNecesarioBp` a mano.
int? margenNecesarioBpDe(
  EstadoDeResultados estado, {
  required int ventaObjetivoCentavos,
  required int gananciaARetenerCentavos,
}) =>
    margenNecesarioBp(
      gastosFijosCentavos: estado.gastosFijosCentavos,
      gastosVariablesCentavos: estado.gastosVariablesCentavos,
      sueldoObjetivoCentavos: estado.sueldoObjetivoCentavos,
      gananciaARetenerCentavos: gananciaARetenerCentavos,
      ventaEstimadaCentavos: ventaObjetivoCentavos,
    );

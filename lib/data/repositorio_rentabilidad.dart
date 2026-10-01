// Arma los insumos del estado de resultados (`domain/rentabilidad.dart`) desde
// la base. Nada de cuentas acá: solo sumar lo que ya está registrado, con el
// mismo criterio que el resto (ventas no anuladas, precio neto de descuento,
// costo-foto) para que este número nunca discuta con Equilibrio.

import 'package:drift/drift.dart';

import '../domain/ganancia.dart';
import '../domain/rentabilidad.dart';
import 'database.dart';
import 'repositorio_equilibrio.dart';

(DateTime, DateTime) _rango(String mesAnio) {
  final partes = mesAnio.split('-');
  final anio = int.parse(partes[0]);
  final mes = int.parse(partes[1]);
  return (DateTime(anio, mes), DateTime(anio, mes + 1));
}

Future<int> _sumaMovimientos(
  AppDatabase db,
  String mesAnio, {
  required String tipo,
  required bool soloSinGastoFijo,
}) async {
  final (inicio, fin) = _rango(mesAnio);
  final m = db.movimientosDeCaja;
  final query = db.selectOnly(m)
    ..addColumns([m.montoCentavos.sum()])
    ..where(
      m.tipo.equals(tipo) &
          m.fecha.isBiggerOrEqualValue(inicio) &
          m.fecha.isSmallerThanValue(fin) &
          (soloSinGastoFijo ? m.gastoFijoId.isNull() : const Constant(true)),
    );
  final fila = await query.getSingle();
  return fila.read(m.montoCentavos.sum()) ?? 0;
}

/// Nombre del concepto de gasto fijo que representa el sueldo del dueño. Es una
/// convención exacta (no una búsqueda aproximada): el nombre es único en la
/// tabla, así que o existe o no existe.
const nombreConceptoSueldo = 'Sueldo del dueño';

Future<int?> conceptoSueldoId(AppDatabase db) async {
  final fila = await (db.select(db.gastosFijos)..where((g) => g.nombre.equals(nombreConceptoSueldo))).getSingleOrNull();
  return fila?.id;
}

String _mesAnterior(String mesAnio) {
  final (inicio, _) = _rango(mesAnio);
  final anterior = DateTime(inicio.year, inicio.month - 1);
  return mesAnioDe(anterior);
}

/// Estado de resultados de [mesAnio] ("YYYY-MM").
///
/// [sueldoGastoFijoId] es el concepto de gasto fijo que representa el sueldo
/// del dueño: su monto del mes se toma como sueldo objetivo y se saca de los
/// fijos, para no contarlo dos veces. Si no se pasa, se busca el concepto
/// llamado [nombreConceptoSueldo]; sin ninguno, el sueldo objetivo es 0 y el
/// estado lo advierte.
///
/// Los fijos sin monto cargado NO se suman como 0: el estado queda incompleto
/// (`fijosCompletos: false`) y lo dice.
Future<EstadoDeResultados> estadoDeResultadosDelMes(
  AppDatabase db,
  String mesAnio, {
  int? sueldoGastoFijoId,
  int reservaCentavos = 0,
  bool conArrastre = true,
}) async {
  sueldoGastoFijoId ??= await conceptoSueldoId(db);

  // El retirable que dejó el mes anterior, calculado sin arrastre propio (no
  // se encadena hacia atrás) y solo si ese mes se puede calcular completo.
  var arrastre = 0;
  if (conArrastre) {
    final anterior = await estadoDeResultadosDelMes(
      db,
      _mesAnterior(mesAnio),
      sueldoGastoFijoId: sueldoGastoFijoId,
      reservaCentavos: reservaCentavos,
      conArrastre: false,
    );
    if (anterior.esCompleto) arrastre = anterior.retirableCentavos;
  }

  final ganancia = await gananciaBrutaDelMes(db, mesAnio);
  final fijos = await fijosDelMes(db, mesAnio);

  var gastosFijos = 0;
  var sueldo = 0;
  for (final c in fijos.conceptos) {
    final monto = c.montoCentavos;
    if (monto == null) continue;
    if (sueldoGastoFijoId != null && c.concepto.id == sueldoGastoFijoId) {
      sueldo += monto;
    } else {
      gastosFijos += monto;
    }
  }

  final variables = await _sumaMovimientos(db, mesAnio, tipo: 'GASTO', soloSinGastoFijo: true);
  final retiros = await _sumaMovimientos(db, mesAnio, tipo: 'RETIRO', soloSinGastoFijo: false);

  return calcularEstadoDeResultados(
    DatosDelMes(
      ventasNetasCentavos: ganancia.ventaConCostoCentavos + ganancia.vendidoSinCostoCentavos,
      ventasConCostoCentavos: ganancia.ventaConCostoCentavos,
      gananciaBrutaCentavos: ganancia.gananciaBrutaCentavos,
      gastosFijosCentavos: gastosFijos,
      gastosVariablesCentavos: variables,
      sueldoObjetivoCentavos: sueldo,
      retirosDelMesCentavos: retiros,
      reservaCentavos: reservaCentavos,
      arrastreCentavos: arrastre,
      fijosCompletos: fijos.faltantes.isEmpty,
    ),
  );
}

/// Un producto cuyo precio actual deja menos ganancia que el margen necesario.
class ProductoBajoMargen {
  const ProductoBajoMargen({
    required this.nombre,
    required this.esPesable,
    required this.costoCentavos,
    required this.precioCentavos,
    required this.gananciaBp,
    required this.precioSugeridoCentavos,
  });

  final String nombre;

  /// Costo y precios por kilo si es pesable, por unidad si no.
  final bool esPesable;
  final int costoCentavos;
  final int precioCentavos;

  /// Ganancia sobre el precio que deja hoy, en basis points.
  final int gananciaBp;

  /// El precio que dejaría exactamente el margen necesario (a la centena).
  /// Solo una sugerencia: nunca se aplica solo (Regla 14).
  final int precioSugeridoCentavos;
}

/// Productos activos con costo y precio cargados que dejan menos de
/// [margenNecesarioBp], de menor a mayor ganancia (los peores primero).
///
/// Quedan afuera los cigarrillos (su ganancia es un monto fijo por atado,
/// Regla 6), "Varios" (sin costo) y las promos (su precio sale de otra cuenta):
/// compararlos contra un margen del negocio no tiene sentido.
Future<List<ProductoBajoMargen>> productosPorDebajoDelMargen(AppDatabase db, int margenNecesarioBp) async {
  if (margenNecesarioBp <= 0 || margenNecesarioBp >= 10000) return const [];
  final productos = await (db.select(db.productos)
        ..where(
          (p) =>
              p.activo.equals(true) &
              p.esVarios.equals(false) &
              p.esPromo.equals(false) &
              p.tipoCigarrillo.equals('ninguno'),
        ))
      .get();

  final resultado = <ProductoBajoMargen>[];
  for (final p in productos) {
    final costo = p.esPesable ? p.costoPorKiloCentavos : p.costoCentavos;
    final precio = p.esPesable ? p.precioPorKiloCentavos : p.precioCentavos;
    if (costo == null || precio == null) continue;
    if (!estaPorDebajoDelMargen(costoCentavos: costo, precioCentavos: precio, margenNecesarioBp: margenNecesarioBp)) {
      continue;
    }
    resultado.add(
      ProductoBajoMargen(
        nombre: p.nombre,
        esPesable: p.esPesable,
        costoCentavos: costo,
        precioCentavos: precio,
        gananciaBp: gananciaBpDesdeCostoYPrecio(costo, precio),
        precioSugeridoCentavos: precioMinimoSugeridoCentavos(costoCentavos: costo, margenBp: margenNecesarioBp),
      ),
    );
  }
  resultado.sort((a, b) {
    final porGanancia = a.gananciaBp.compareTo(b.gananciaBp);
    return porGanancia != 0 ? porGanancia : a.nombre.compareTo(b.nombre);
  });
  return resultado;
}

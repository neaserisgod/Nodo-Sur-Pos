// Estado de la pantalla de rentabilidad y equilibrio (fase 7). Todo lo que
// depende de los fijos del mes queda en null si falta cargar algún concepto
// (Regla 12: "avisar antes que inventar") — la pantalla lo refleja mostrando
// un aviso en vez de un número en esas tarjetas puntuales.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/database.dart';
import '../../data/repositorio_equilibrio.dart';
import '../../data/repositorio_rentabilidad.dart';
import '../../domain/equilibrio.dart';
import '../../domain/rentabilidad.dart';

class EquilibrioControlador extends ChangeNotifier {
  EquilibrioControlador(this.db, {required this.usuarioId, this.sesionCajaId});

  final AppDatabase db;
  final int usuarioId;

  /// Null si no hay sesión de caja abierta: registrar un pago de fijo queda
  /// deshabilitado en ese caso (no hay dónde grabar el movimiento de caja).
  final int? sesionCajaId;

  late String mesAnio;
  ResumenFijosDelMes? fijos;
  ResultadoGananciaBruta? ganancia;
  ResultadoEquilibrio? equilibrio;
  int? fijosPagadosCentavos;
  int? fijosPendientesCentavos;

  /// Lo pagado de cada concepto este mes (para "Pagado / Pendiente" en la lista).
  Map<int, int> pagadoPorConcepto = const {};
  int? ventaDiariaEquilibrio;
  int? reservaDiariaCentavos;

  /// Estado de resultados del mes (ganancia bruta → retirable). Siempre se
  /// calcula, aunque falten fijos: en ese caso viene marcado incompleto.
  EstadoDeResultados? estado;

  /// Si ya existe el concepto de fijo "Sueldo del dueño".
  bool tieneConceptoSueldo = false;

  // ─── Margen necesario ────────────────────────────────────────────────
  // Los dos datos que el dueño tipea: cuánto espera vender en el mes y cuánta
  // ganancia quiere dejar en el negocio además de gastos y sueldo. Se guardan
  // en el dispositivo (son del dueño, no del negocio contable) y la pantalla
  // los recalcula contra los gastos reales del mes.

  static const _claveVenta = 'objetivo_venta_centavos';
  static const _claveRetener = 'objetivo_retener_centavos';

  /// true cuando ya se leyeron del dispositivo (o se supo que no se puede):
  /// la tarjeta rellena sus campos recién entonces.
  bool objetivoCargado = false;

  int ventaObjetivoCentavos = 0;
  int gananciaARetenerCentavos = 0;

  /// Null sin venta objetivo, o si el objetivo pide 100% o más (imposible).
  int? margenNecesario;

  /// Venta mensual que haría falta con el margen que hoy tiene el negocio.
  int? ventaNecesariaConMargenActualCentavos;

  List<ProductoBajoMargen> productosBajoMargen = const [];

  Future<void> _leerObjetivo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      ventaObjetivoCentavos = prefs.getInt(_claveVenta) ?? 0;
      gananciaARetenerCentavos = prefs.getInt(_claveRetener) ?? 0;
    } catch (_) {
      // Sin almacenamiento disponible: arranca vacío, se puede tipear igual.
    }
  }

  Future<void> _recalcularMargenNecesario() async {
    final e = estado;
    if (e == null) return;
    final bp = margenNecesario = margenNecesarioBpDe(
      e,
      ventaObjetivoCentavos: ventaObjetivoCentavos,
      gananciaARetenerCentavos: gananciaARetenerCentavos,
    );
    final actual = e.gananciaBrutaBp;
    ventaNecesariaConMargenActualCentavos = (bp == null || actual == null)
        ? null
        : ventaNecesariaCentavos(
            necesarioCentavos: e.gastosFijosCentavos +
                e.gastosVariablesCentavos +
                e.sueldoObjetivoCentavos +
                gananciaARetenerCentavos,
            margenBp: actual,
          );
    productosBajoMargen = bp == null ? const [] : await productosPorDebajoDelMargen(db, bp);
  }

  Future<void> guardarObjetivo({required int ventaCentavos, required int retenerCentavos}) async {
    ventaObjetivoCentavos = ventaCentavos < 0 ? 0 : ventaCentavos;
    gananciaARetenerCentavos = retenerCentavos < 0 ? 0 : retenerCentavos;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_claveVenta, ventaObjetivoCentavos);
      await prefs.setInt(_claveRetener, gananciaARetenerCentavos);
    } catch (_) {
      // No se pudo guardar: se usa igual en esta sesión.
    }
    await _recalcularMargenNecesario();
    notifyListeners();
  }

  bool cargando = true;

  Future<void> cargarTodo() async {
    mesAnio = mesAnioDe(DateTime.now());
    fijos = await fijosDelMes(db, mesAnio);
    ganancia = await gananciaBrutaDelMes(db, mesAnio);

    final totalFijos = fijos!.total;
    if (totalFijos == null) {
      equilibrio = null;
      fijosPagadosCentavos = null;
    } else {
      equilibrio = calcularEquilibrio(
        gastosFijosCentavos: totalFijos,
        gananciaBrutaCentavos: ganancia!.gananciaBrutaCentavos,
      );
      fijosPagadosCentavos = await fijosPagadosDelMes(db, mesAnio);
    }
    fijosPendientesCentavos = await fijosPendientesDelMes(db, mesAnio);
    pagadoPorConcepto = await pagadoPorConceptoDelMes(db, mesAnio);

    final referencias = await referenciasDiarias(db, mesAnio);
    ventaDiariaEquilibrio = referencias.ventaDiaria;
    reservaDiariaCentavos = referencias.reservaDiaria;

    estado = await estadoDeResultadosDelMes(db, mesAnio);
    tieneConceptoSueldo = await conceptoSueldoId(db) != null;
    cargando = false;
    notifyListeners();

    // El objetivo del dueño vive en el dispositivo (`shared_preferences`) y
    // se lee aparte: la pantalla no tiene que esperarlo para mostrarse, y un
    // almacenamiento lento o ausente no puede dejarla vacía.
    unawaited(_cargarObjetivo());
  }

  Future<void> _cargarObjetivo() async {
    await _leerObjetivo();
    await _recalcularMargenNecesario();
    objetivoCargado = true;
    if (!_descartado) notifyListeners();
  }

  bool _descartado = false;

  @override
  void dispose() {
    _descartado = true;
    super.dispose();
  }

  Future<void> cargarMonto({required int gastoFijoId, required int montoCentavos, int? diaVencimiento}) async {
    await cargarMontoDelMes(db, gastoFijoId: gastoFijoId, mesAnio: mesAnio, montoCentavos: montoCentavos);
    await configurarVencimiento(db, gastoFijoId: gastoFijoId, dia: diaVencimiento);
    await cargarTodo();
  }

  Future<void> agregarConcepto(String nombre) async {
    await crearConcepto(db, nombre);
    await cargarTodo();
  }

  /// No hace nada si no hay sesión abierta — ver [sesionCajaId].
  ///
  /// [fecha] default a ahora — El dueño a veces paga un fijo un día y lo carga
  /// otro, así que el diálogo deja elegir la fecha real del pago (ver
  /// `registrarPagoFijo`).
  Future<void> registrarPago({
    required int gastoFijoId,
    required int montoCentavos,
    bool pagadoConMp = false,
    DateTime? fecha,
  }) async {
    final sesion = sesionCajaId;
    // Antes volvía en silencio y el diálogo se cerraba como si el pago estuviera guardado.
    if (sesion == null) throw StateError('Hace falta una caja abierta para registrar el pago');
    await registrarPagoFijo(
      db,
      gastoFijoId: gastoFijoId,
      sesionCajaId: sesion,
      usuarioId: usuarioId,
      montoCentavos: montoCentavos,
      pagadoConMp: pagadoConMp,
      fecha: fecha,
    );
    await cargarTodo();
  }
}

// Estado de la pantalla de rentabilidad y equilibrio (fase 7). Todo lo que
// depende de los fijos del mes queda en null si falta cargar algún concepto
// (Regla 12: "avisar antes que inventar") — la pantalla lo refleja mostrando
// un aviso en vez de un número en esas tarjetas puntuales.

import 'package:flutter/widgets.dart';

import '../../data/database.dart';
import '../../data/repositorio_equilibrio.dart';
import '../../domain/equilibrio.dart';

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
  int? ventaDiariaEquilibrio;
  int? reservaDiariaCentavos;

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

    final referencias = await referenciasDiarias(db, mesAnio);
    ventaDiariaEquilibrio = referencias.ventaDiaria;
    reservaDiariaCentavos = referencias.reservaDiaria;

    cargando = false;
    notifyListeners();
  }

  Future<void> cargarMonto({required int gastoFijoId, required int montoCentavos}) async {
    await cargarMontoDelMes(db, gastoFijoId: gastoFijoId, mesAnio: mesAnio, montoCentavos: montoCentavos);
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
    if (sesion == null) return;
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

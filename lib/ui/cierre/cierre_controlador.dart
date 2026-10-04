import 'dart:async';

// Estado del cierre de caja. Tres fases, en el orden que exige la Regla 10:
// contar, comparar, separar. La fase `conteo` es la única garantía real de
// "oculto hasta confirmar" — mientras dure, la pantalla ni siquiera arma
// los widgets de diferencia/separación, no los muestra deshabilitados.

import 'package:flutter/widgets.dart';

import '../../domain/modulos.dart';
import '../../servicios/modulos_activos.dart';
import '../../servicios/nube.dart';
import '../../data/database.dart';
import '../../data/pdf_planilla.dart';
import '../../data/repositorio_carga_historica.dart' show ResumenDiaHistorico, resumenDiaHistorico;
import '../../data/repositorio_arqueo_intermedio.dart' show ArqueoDelTurno, arqueosDelTurno;
import '../../data/repositorio_cierre.dart';
import '../../data/repositorio_conciliacion_mp.dart';
import '../../domain/conciliacion_mp.dart';
import '../../domain/saldo_mp.dart';
import '../../servicios/saldo_mp_nube.dart';
import '../../data/repositorio_gastos.dart' show MedioGasto, registrarGastoRapido;
import '../../data/repositorio_ingresos.dart' show registrarIngresoRapido;
import '../../data/repositorio_saldo_mp.dart';
import '../../servicios/conciliacion_mp_nube.dart';
import '../../data/repositorio_cobro.dart';
import '../../data/repositorio_respaldo.dart';
import '../../data/repositorio_ventas_abiertas.dart';
import '../../domain/dinero.dart';

enum FaseCierre { conteo, revisado, cerrado }

class CierreControlador extends ChangeNotifier {
  CierreControlador(this.db, {required this.sesionId, LeerCobrosMp? leerCobrosMp, TraerSaldoMp? traerSaldoMp})
      : leerCobrosMp = leerCobrosMp ?? (nubeApp == null ? null : leerCobrosMpDeCuenta(nubeApp!.almacen, nubeApp!.cliente)),
        traerSaldoMp = traerSaldoMp ?? (nubeApp == null ? null : traerSaldoMpDeCuenta(nubeApp!.almacen, nubeApp!.cliente)) {
    // Mientras ya se reveló el resultado, corregir el conteo recalcula en
    // vivo (El dueño: "cuento hasta que dé" no debería volver a tapar nada —
    // ocultar es para no sesgar el primer conteo, no para trabar la
    // corrección). Antes de revelar, este listener no hace nada.
    efectivoContadoCtrl.addListener(_alCambiarConteo);
    mpContadoCtrl.addListener(_alCambiarConteo);
    lataContadoCtrl.addListener(_alCambiarConteo);
  }

  final AppDatabase db;
  final int sesionId;

  /// Cómo leer los cobros reales de Mercado Pago para "Mercado Pago según Mercado Pago". Null si esta PC no tiene cuenta
  /// de Nodo Sur vinculada: la sección lo dice, el cierre sigue igual.
  final LeerCobrosMp? leerCobrosMp;

  Future<ConciliacionMp> Function()? get cargarMpReal {
    final leer = leerCobrosMp;
    return leer == null
        ? null
        : () async {
            final c = await conciliarMpDeSesion(db, sesionId, leer);
            _ultimaConciliacion = c;
            return c;
          };
  }

  ConciliacionMp? _ultimaConciliacion;

  // --- Saldo real de Mercado Pago (etapa E, El dueño 2026-10-04): se pide con un botón; al llegar llena el "MP contado" y queda
  // editable; las diferencias se avisan y se cargan con un toque como gasto o ingreso por MP.

  /// Cómo traer el saldo real. Null si esta PC no tiene cuenta de Nodo Sur vinculada: el botón no aparece.
  final TraerSaldoMp? traerSaldoMp;
  SaldoMp? saldoMp;
  bool pidiendoSaldo = false;
  String? errorSaldo;

  /// Lo que no cierra entre el reporte de Mercado Pago y la app. Null hasta tener el saldo y haber revelado el cierre.
  DiferenciasSaldoMp? diferenciasSaldo;
  final Set<int> _ventasSinCobroCargadas = {};

  /// Pide el saldo, lo pone en el "MP contado" (en pesos enteros, como todo contado) y deja los números para editar.
  Future<void> traerSaldo() async {
    final traer = traerSaldoMp;
    if (traer == null || pidiendoSaldo || sesion == null) return;
    pidiendoSaldo = true;
    errorSaldo = null;
    notifyListeners();
    try {
      final saldo = await traer(sesion!.fechaApertura);
      saldoMp = saldo;
      mpPrecargado = false;
      mpContadoCtrl.text = formatearARS(((saldo.contadoSugeridoCentavos / centavosPorPeso).round()) * centavosPorPeso, conSigno: false);
      await recalcularDiferenciasSaldo();
    } catch (e) {
      errorSaldo = '$e';
    } finally {
      pidiendoSaldo = false;
      notifyListeners();
    }
  }

  /// Cruza los movimientos del reporte con lo que la app anotó por MP en el turno y con las ventas marcadas MP que no entraron.
  /// Solo con el cierre ya revelado (primero se cuenta, después se compara).
  Future<void> recalcularDiferenciasSaldo() async {
    final saldo = saldoMp;
    if (saldo == null || fase != FaseCierre.revisado) return;
    final locales = await movimientosMpDelTurno(db, sesionId);
    var conciliacion = _ultimaConciliacion;
    final cargar = cargarMpReal;
    if (conciliacion == null && cargar != null) {
      try {
        conciliacion = await cargar();
      } catch (_) {
        // sin los cobros no se pueden listar las ventas sin cobro, pero lo demás se muestra igual
      }
    }
    diferenciasSaldo = compararSaldoMp(
      movimientos: saldo.movimientos,
      enApp: locales.enApp,
      anuladasEnApp: locales.anuladas,
      ventasSinCobro: [
        for (final v in conciliacion?.ventasSinCobro ?? const <PagoMpRegistrado>[])
          if (!_ventasSinCobroCargadas.contains(v.ventaId)) v,
      ],
    );
    notifyListeners();
  }

  String _cuando(DateTime? f) => f == null ? '' : ' (${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')} ${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')})';

  /// Un toque: lo que salió de Mercado Pago y la app no tiene, como gasto por MP.
  Future<void> cargarEgresoSinRegistrar(MovimientoSaldoMp m) => _cargarMovimiento(
    () => registrarGastoRapido(
      db,
      sesionCajaId: sesionId,
      usuarioId: sesion!.usuarioAbrioId,
      montoCentavos: m.debitoCentavos,
      medio: MedioGasto.mercadoPago,
      motivo: 'Movimiento en MP que no estaba en la app: ${m.descripcion.isEmpty ? m.tipo : m.descripcion}${_cuando(m.fecha)}',
    ),
  );

  /// Un toque: lo que entró a Mercado Pago sin ser un cobro y la app no tiene, como ingreso por MP.
  Future<void> cargarIngresoSinRegistrar(MovimientoSaldoMp m) => _cargarMovimiento(
    () => registrarIngresoRapido(
      db,
      sesionCajaId: sesionId,
      usuarioId: sesion!.usuarioAbrioId,
      montoCentavos: m.creditoCentavos,
      medio: MedioGasto.mercadoPago,
      motivo: 'Movimiento en MP que no estaba en la app: ${m.descripcion.isEmpty ? m.tipo : m.descripcion}${_cuando(m.fecha)}',
    ),
  );

  /// Un toque: una venta marcada como cobrada por MP que nunca entró, como gasto por MP (para que la caja de MP cuadre).
  Future<void> cargarVentaSinCobroComoGasto(PagoMpRegistrado v) => _cargarMovimiento(() async {
    final id = await registrarGastoRapido(
      db,
      sesionCajaId: sesionId,
      usuarioId: sesion!.usuarioAbrioId,
      montoCentavos: v.montoCentavos,
      medio: MedioGasto.mercadoPago,
      motivo: 'Cobro marcado MP que no entró (venta #${v.ventaId})',
    );
    _ventasSinCobroCargadas.add(v.ventaId);
    return id;
  });

  Future<void> _cargarMovimiento(Future<int> Function() cargar) async {
    if (sesion == null || fase != FaseCierre.revisado) return;
    try {
      await cargar();
      errorSaldo = null;
    } catch (e) {
      errorSaldo = 'No se pudo cargar: $e';
      notifyListeners();
      return;
    }
    final efectivo = _parsear(efectivoContadoCtrl.text);
    if (efectivo != null) await _recalcular(efectivo);
    await recalcularDiferenciasSaldo();
  }

  final TextEditingController efectivoContadoCtrl = TextEditingController();
  final TextEditingController mpContadoCtrl = TextEditingController();
  final TextEditingController lataContadoCtrl = TextEditingController();
  final TextEditingController notaCtrl = TextEditingController();

  FaseCierre fase = FaseCierre.conteo;
  SesionCaja? sesion;
  ResumenCierre? resumen;

  /// Desglose por proveedor y detalle de "vendido sin costo cargado" — la
  /// misma función que ya arma la companion (`resumenDiaHistorico`, Regla
  /// 3), agregada acá porque la pantalla de escritorio nunca la pedía: el
  /// modal de cierre solo mostraba el agregado de `resumen.reposicion`
  /// (`vendidoSinCostoCentavos`), sin decir a qué proveedor separarle ni
  /// qué producto específico falta completar (El dueño: "faltan datos
  /// importantes" en el cierre).
  ResumenDiaHistorico? resumenDia;

  bool puedeReabrir = false;
  String? error;

  /// Ventas armadas y sin cobrar de esta sesión: bloquean el cierre hasta
  /// cobrarlas o descartarlas (El dueño, 2026-09-29).
  int ventasAbiertas = 0;

  /// Los arqueos hechos durante el turno (opcionales, el dueño 2026-09-28),
  /// del más viejo al más nuevo — se muestran en el resumen como registro.
  List<ArqueoDelTurno> arqueos = [];

  /// El arqueo del que salió la precarga del conteo, o null si se arrancó
  /// de cero. El dueño eligió precargar ("las dos cosas": precargar y además
  /// mostrarlos): el cierre arranca con lo último que se contó, para
  /// corregir en vez de tipear todo de nuevo.
  ArqueoDelTurno? precargadoDe;

  /// Qué campo se precargó de [precargadoDe]: solo el de la caja que no se movió desde ese arqueo
  /// (`cajasMovidasDesde`). Si se movió, el campo arranca vacío y hay que contar de nuevo.
  bool efectivoPrecargado = false;
  bool mpPrecargado = false;

  /// Null si el respaldo automático salió bien o no hay carpeta configurada
  /// (en ese caso no se avisa nada, silencioso a propósito: configurar el
  /// respaldo es de la pantalla de Respaldo, no algo que este cierre exija).
  /// Si falla habiendo carpeta configurada, sí se avisa — pero nunca bloquea
  /// el cierre, que ya terminó antes de intentar esto.
  String? ultimoRespaldoError;

  /// Mismo criterio que [ultimoRespaldoError]: null si la planilla se
  /// generó bien o no hay carpeta de tickets configurada todavía (silencioso
  /// — configurar la carpeta es de la pantalla de Impresión, no algo que
  /// este cierre exija). Si falla habiendo carpeta, avisa sin bloquear.
  String? ultimoPlanillaError;

  /// Cobros por Point (fase 12) que se quedaron en 'pendiente' sin que la
  /// API llegara a confirmar nada (se agotaron los 60s de polling) —
  /// cancelados o rechazados explícitamente no entran acá, esos ya tienen
  /// una resolución clara. Informativo nada más, nunca bloquea el cierre:
  /// la duda se resuelve mirando la cuenta de Mercado Pago, no reteniendo
  /// la caja.
  List<OrdenCobroPendiente> ordenesCobroSinResolver = [];

  int? _parsear(String texto) {
    if (texto.trim().isEmpty) return null;
    try {
      return parsearARS(texto);
    } on FormatException {
      return null;
    }
  }

  Future<void> cargar() async {
    sesion = await (db.select(
      db.sesionesDeCaja,
    )..where((s) => s.id.equals(sesionId))).getSingle();
    ordenesCobroSinResolver = await ordenesSinResolverDeSesion(db, sesionId);
    arqueos = await arqueosDelTurno(db, sesionId);
    ventasAbiertas = await cantidadVentasAbiertasConLineas(db, sesionId);
    await _precargarDelUltimoArqueo();

    if (sesion!.estado == 'CERRADA') {
      fase = FaseCierre.cerrado;
      // Recalcula con el mismo conteo que ya se guardó: mismo cálculo de
      // siempre, no una reconstrucción aparte a partir de columnas
      // guardadas (Regla 3 — una sola fórmula).
      final resultados = await Future.wait([
        calcularResumenCierre(
          db,
          sesionId: sesionId,
          efectivoContadoCentavos: sesion!.efectivoContadoCentavos ?? 0,
          mpContadoCentavos: sesion!.mpContadoCentavos,
          lataContadoCentavos: sesion!.lataContadoCentavos,
        ),
        resumenDiaHistorico(db, sesionId),
      ]);
      resumen = resultados[0] as ResumenCierre;
      resumenDia = resultados[1] as ResumenDiaHistorico;
      puedeReabrir = await esUltimaSesion(db, sesionId);
    }
    notifyListeners();
  }

  /// Efectivo y Mercado Pago salen del último arqueo del turno, solo si el
  /// campo sigue vacío (nunca pisa lo que se esté escribiendo). La lata NO:
  /// el arqueo del turno la cuenta antes de separar los cigarrillos del día
  /// (`lataEsperadaIntermedia`), y la del cierre es después de separarlos —
  /// son dos montos distintos a propósito, precargar uno con el otro
  /// sembraría una diferencia falsa.
  ///
  /// Y solo en la caja que no se movió después de ese arqueo (El dueño, 2026-10-04): si entró o salió plata, lo
  /// contado ya no es lo que hay, y precargarlo invita a cerrar con un saldo viejo.
  Future<void> _precargarDelUltimoArqueo() async {
    if (fase != FaseCierre.conteo || arqueos.isEmpty) return;
    if (efectivoContadoCtrl.text.isNotEmpty || mpContadoCtrl.text.isNotEmpty) return;
    final ultimo = arqueos.last;
    final movidas = await cajasMovidasDesde(db, sesionId, ultimo.fecha);
    efectivoPrecargado = !movidas.efectivo;
    mpPrecargado = !movidas.mp;
    if (efectivoPrecargado) {
      efectivoContadoCtrl.text = formatearARS(ultimo.efectivoContadoCentavos, conSigno: false);
    }
    if (mpPrecargado) mpContadoCtrl.text = formatearARS(ultimo.mpContadoCentavos, conSigno: false);
    precargadoDe = efectivoPrecargado || mpPrecargado ? ultimo : null;
  }

  /// Primera confirmación: recién acá se calcula y se revela todo junto
  /// (diferencia y separación) por primera vez.
  Future<void> confirmarConteo() async {
    final monto = _parsear(efectivoContadoCtrl.text);
    if (monto == null) {
      error = 'Contá el efectivo y anotalo antes de confirmar';
      notifyListeners();
      return;
    }
    error = null;
    fase = FaseCierre.revisado;
    await _recalcular(monto);
    await recalcularDiferenciasSaldo();
  }

  void _alCambiarConteo() {
    if (fase != FaseCierre.revisado) return;
    final monto = _parsear(efectivoContadoCtrl.text);
    if (monto == null) return;
    _recalcular(monto);
  }

  /// [mpContadoCentavos]/[lataContadoCentavos] null hasta que se escribe
  /// algo en su campo (Regla 1/2: la diferencia no se ve hasta confirmar lo
  /// contado, igual que la de efectivo — vale para las tres cajas).
  Future<void> _recalcular(int efectivoContadoCentavos) async {
    final resultados = await Future.wait([
      calcularResumenCierre(
        db,
        sesionId: sesionId,
        efectivoContadoCentavos: efectivoContadoCentavos,
        mpContadoCentavos: _parsear(mpContadoCtrl.text),
        lataContadoCentavos: _parsear(lataContadoCtrl.text),
      ),
      resumenDiaHistorico(db, sesionId),
    ]);
    resumen = resultados[0] as ResumenCierre;
    resumenDia = resultados[1] as ResumenDiaHistorico;
    notifyListeners();
  }

  Future<void> descartarVentasAbiertasYRecargar() async {
    await descartarVentasAbiertas(db, sesionId);
    error = null;
    await cargar();
  }

  Future<bool> cerrar({required int usuarioId}) async {
    if (ventasAbiertas > 0) {
      error = _avisoVentasAbiertas(ventasAbiertas);
      notifyListeners();
      return false;
    }
    final efectivo = _parsear(efectivoContadoCtrl.text);
    final mpContado = _parsear(mpContadoCtrl.text);
    // Sin el módulo de caja aparte no hay lata que contar: se da por buena la esperada (diferencia 0).
    final lataContado = moduloActivo(Modulo.cajaAparte) ? _parsear(lataContadoCtrl.text) : (resumen?.lataFinalCentavos ?? 0);
    if (efectivo == null || mpContado == null || lataContado == null) {
      error = 'Falta el efectivo contado, el MP contado o la lata contada';
      notifyListeners();
      return false;
    }

    try {
      await cerrarSesion(
        db,
        sesionId: sesionId,
        usuarioId: usuarioId,
        efectivoContadoCentavos: efectivo,
        mpContadoCentavos: mpContado,
        lataContadoCentavos: lataContado,
        nota: notaCtrl.text.trim().isEmpty ? null : notaCtrl.text.trim(),
      );
    } on VentasAbiertasPendientesException catch (e) {
      ventasAbiertas = e.cantidad;
      error = _avisoVentasAbiertas(e.cantidad);
      notifyListeners();
      return false;
    } on SesionYaNoAbiertaException {
      // El dueño, 2026-09-19: "aislar los usuarios para que no se pisen" — ya
      // la cerraron mientras se llenaba este mismo diálogo (por ejemplo,
      // desde el celular). `cargar()` va a mostrar el cierre real, ya hecho
      // por la otra persona, en vez de un error genérico.
      error = 'La caja ya se cerró desde otro lado mientras tanto';
      notifyListeners();
      await cargar();
      return false;
    }
    await _respaldarSinBloquearElCierre();
    await _generarPlanillaSinBloquearElCierre();
    await cargar();
    return true;
  }

  static String _avisoVentasAbiertas(int n) => n == 1
      ? 'Hay 1 venta armada sin cobrar. Cobrala o descartala antes de cerrar.'
      : 'Hay $n ventas armadas sin cobrar. Cobralas o descartalas antes de cerrar.';

  /// El respaldo corre solo al cerrar caja (fase 10) — nunca puede ser la
  /// razón por la que un cierre ya hecho parezca fallar.
  Future<void> _respaldarSinBloquearElCierre() async {
    // La copia en la cuenta de Nodo Sur (si la PC está vinculada) sale en segundo plano: el cierre no espera a
    // internet y su resultado solo se ve en Configuración → Cuenta de Nodo Sur.
    unawaited(nubeApp?.subirCopia());
    try {
      final carpeta = await carpetaRespaldo(db);
      if (carpeta == null) {
        ultimoRespaldoError = null;
        return;
      }
      await hacerRespaldo(db);
      ultimoRespaldoError = null;
    } catch (e) {
      ultimoRespaldoError = 'No se pudo hacer el respaldo automático: $e';
    }
  }

  /// La planilla "Control diario de caja" (fase 9/ítem 3) se generaba solo a
  /// mano desde Historial — El dueño la quiere sola al cerrar, en la misma
  /// carpeta de tickets (mismo criterio de "carpeta ya configurada" que el
  /// respaldo, no hace falta una segunda carpeta para esto).
  Future<void> _generarPlanillaSinBloquearElCierre() async {
    try {
      final config = await db.select(db.configuracionTabla).getSingle();
      final carpeta = config.rutaTicketsCarpeta;
      if (carpeta == null) {
        ultimoPlanillaError = null;
        return;
      }
      await guardarPdfPlanilla(db, sesionId: sesionId, carpetaDestino: carpeta);
      ultimoPlanillaError = null;
    } catch (e) {
      ultimoPlanillaError =
          'No se pudo generar la planilla automáticamente: $e';
    }
  }

  /// Regla 6: reabre la última sesión cerrada. Vuelve a la fase de conteo —
  /// reabrir no reconstruye el arqueo anterior, se cuenta de nuevo.
  Future<bool> reabrir() async {
    try {
      await reabrirSesion(db, sesionId: sesionId);
    } on StateError {
      return false;
    }
    fase = FaseCierre.conteo;
    resumen = null;
    error = null;
    efectivoContadoCtrl.clear();
    mpContadoCtrl.clear();
    lataContadoCtrl.clear();
    notaCtrl.clear();
    precargadoDe = null;
    efectivoPrecargado = false;
    mpPrecargado = false;
    saldoMp = null;
    diferenciasSaldo = null;
    errorSaldo = null;
    _ventasSinCobroCargadas.clear();
    _ultimaConciliacion = null;
    await cargar();
    return true;
  }

  @override
  void dispose() {
    efectivoContadoCtrl.dispose();
    mpContadoCtrl.dispose();
    lataContadoCtrl.dispose();
    notaCtrl.dispose();
    super.dispose();
  }
}

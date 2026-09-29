// Estado del arqueo sugerido cada 2hs (turnos por usuario, 2026-09-12; ya no
// bloqueante, Bruno 2026-09-15).
// Dos fases nada más — conteo y revisado, mismo orden "primero se cuenta,
// después se compara" que el cierre real (Regla 10) — sin fase "cerrado":
// al confirmar, esto ya terminó, no hay nada más que mostrar.

import 'package:flutter/widgets.dart';

import '../../data/database.dart';
import '../../data/repositorio_arqueo_intermedio.dart';
import '../../data/repositorio_cierre.dart'
    show ResumenCierre, calcularResumenCierre;
import '../../domain/caja.dart' show diferenciaArqueo;
import '../../domain/dinero.dart';

enum FaseArqueoIntermedio { conteo, revisado }

class ArqueoIntermedioControlador extends ChangeNotifier {
  ArqueoIntermedioControlador(this.db, {required this.sesionId}) {
    // Mismo criterio que `CierreControlador`: mientras ya se reveló el
    // resultado, corregir el conteo recalcula en vivo.
    efectivoContadoCtrl.addListener(_alCambiarConteo);
    mpContadoCtrl.addListener(_alCambiarConteo);
    lataContadoCtrl.addListener(_alCambiarConteo);
  }

  final AppDatabase db;
  final int sesionId;

  final TextEditingController efectivoContadoCtrl = TextEditingController();
  final TextEditingController mpContadoCtrl = TextEditingController();
  final TextEditingController lataContadoCtrl = TextEditingController();

  FaseArqueoIntermedio fase = FaseArqueoIntermedio.conteo;
  ResumenCierre? resumen;

  /// A diferencia de `resumen.lataFinalCentavos` (que asume separado todo
  /// lo vendido hoy, correcto para un cierre real): acá se compara la lata
  /// contra lo que debería seguir habiendo SIN separar nada todavía (Bruno,
  /// 2026-09-13: "solo al cerrar") — `lataEsperadaIntermedia`, misma
  /// fórmula que guarda `registrarArqueoIntermedio`.
  int? lataEsperadaCentavos;
  int? lataDiferenciaCentavos;
  String? error;

  int? _parsear(String texto) {
    if (texto.trim().isEmpty) return null;
    try {
      return parsearARS(texto);
    } on FormatException {
      return null;
    }
  }

  Future<void> confirmarConteo() async {
    final monto = _parsear(efectivoContadoCtrl.text);
    if (monto == null) {
      error = 'Contá el efectivo y anotalo antes de confirmar';
      notifyListeners();
      return;
    }
    error = null;
    fase = FaseArqueoIntermedio.revisado;
    await _recalcular(monto);
  }

  void _alCambiarConteo() {
    if (fase != FaseArqueoIntermedio.revisado) return;
    final monto = _parsear(efectivoContadoCtrl.text);
    if (monto == null) return;
    _recalcular(monto);
  }

  Future<void> _recalcular(int efectivoContadoCentavos) async {
    final lataContado = _parsear(lataContadoCtrl.text);
    final futuroResumen = calcularResumenCierre(
      db,
      sesionId: sesionId,
      efectivoContadoCentavos: efectivoContadoCentavos,
      mpContadoCentavos: _parsear(mpContadoCtrl.text),
      // Sin `lataContadoCentavos`: ver `lataEsperadaIntermedia` abajo, la
      // lata de esta pantalla no se calcula como la de un cierre real.
    );
    final futuroLataEsperada = lataEsperadaIntermedia(db, sesionId);
    resumen = await futuroResumen;
    lataEsperadaCentavos = await futuroLataEsperada;
    lataDiferenciaCentavos = lataContado == null
        ? null
        : diferenciaArqueo(
            contadoCentavos: lataContado,
            esperadoCentavos: lataEsperadaCentavos!,
          );
    notifyListeners();
  }

  /// true si guardó. A diferencia del cierre real, acá los tres contados son
  /// siempre obligatorios — no hay "todavía no lo escribí", es como el
  /// cierre de punta a punta en una sola confirmación.
  Future<bool> confirmarArqueo({required int usuarioId}) async {
    final efectivo = _parsear(efectivoContadoCtrl.text);
    final mp = _parsear(mpContadoCtrl.text);
    final lata = _parsear(lataContadoCtrl.text);
    if (efectivo == null || mp == null || lata == null) {
      error = 'Falta el efectivo contado, el MP contado o la lata contada';
      notifyListeners();
      return false;
    }
    await registrarArqueoIntermedio(
      db,
      sesionId: sesionId,
      usuarioId: usuarioId,
      efectivoContadoCentavos: efectivo,
      mpContadoCentavos: mp,
      lataContadoCentavos: lata,
    );
    return true;
  }

  @override
  void dispose() {
    efectivoContadoCtrl.dispose();
    mpContadoCtrl.dispose();
    lataContadoCtrl.dispose();
    super.dispose();
  }
}

// Interruptor "Cobrar e imprimir por Nodo Sur" (El dueño, 2026-10-02: probar la integración Nodo Sur POS sin tener que borrar el
// access token local). Es de ESTE equipo, no de la base: no viaja con las copias ni con la sync, y apagarlo devuelve al camino de
// siempre (directo con el token local) sin perder nada.

import 'package:shared_preferences/shared_preferences.dart';

const _clave = 'cobro_por_nodo_sur';

abstract final class PreferenciaCobroNube {
  // Se lee UNA vez al arrancar (`cargar`) y después se consulta en memoria: el cobro y la impresión no pueden esperar a disco
  // (prioridad operación sobre arranque, CLAUDE.md), y los tests no necesitan simular el almacenamiento.
  static bool _valor = false;

  /// Lo que dice el interruptor ahora. Apagado hasta que se cargue, o si la lectura falla: lo que ya andaba sigue andando.
  static bool get activo => _valor;

  static Future<void> cargar() async {
    try {
      _valor = (await SharedPreferences.getInstance()).getBool(_clave) ?? false;
    } catch (_) {
      _valor = false;
    }
  }

  static Future<void> guardar(bool valor) async {
    _valor = valor;
    try {
      await (await SharedPreferences.getInstance()).setBool(_clave, valor);
    } catch (_) {
      // Sin almacenamiento el interruptor vale hasta cerrar la app; no se rompe nada.
    }
  }
}

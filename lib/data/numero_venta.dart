// Número de venta legible y único entre dispositivos (El dueño, 2026-10-03): "<prefijo>-<correlativo>", ej. "K7-0123".
//
// El `id` de una venta es local: la PC y cada celular tienen el suyo, y al sincronizar se reasigna. Un ticket o un
// reclamo ("la venta 123") necesita un nombre que sea el mismo en todos lados, así que cada dispositivo tiene un prefijo
// propio (no se sincroniza: vive en `configuracion_tabla`) y numera sus ventas en orden. Dos dispositivos no pueden
// repetir número salvo que sorteen el mismo prefijo (1 en 576): por eso `prefijoDeVentas` reintenta contra el prefijo
// que ya vio en ventas sincronizadas de otros dispositivos.

import 'dart:math';

import 'package:drift/drift.dart';

import 'database.dart';

// Sin letras que se confunden con números (I, O) para que el ticket se lea bien en papel.
const _letras = 'ABCDEFGHJKLMNPQRSTUVWXYZ';

/// El prefijo de este equipo; lo genera y lo guarda la primera vez.
Future<String> prefijoDeVentas(AppDatabase db, {Random? azar}) async {
  final config = await db.select(db.configuracionTabla).getSingle();
  final actual = config.prefijoVentas;
  if (actual != null && actual.isNotEmpty) return actual;

  final usados = {
    for (final fila in await db.customSelect(
      "SELECT DISTINCT substr(numero, 1, instr(numero, '-') - 1) AS p FROM ventas WHERE numero IS NOT NULL",
    ).get())
      fila.data['p'] as String,
  };
  final rnd = azar ?? Random.secure();
  String nuevo;
  do {
    nuevo = '${_letras[rnd.nextInt(_letras.length)]}${_letras[rnd.nextInt(_letras.length)]}';
  } while (usados.contains(nuevo));
  await db.update(db.configuracionTabla).write(ConfiguracionTablaCompanion(prefijoVentas: Value(nuevo)));
  return nuevo;
}

/// El número que le toca a la próxima venta de este equipo. Se llama dentro de la transacción de `registrarVenta`.
Future<String> siguienteNumeroDeVenta(AppDatabase db) async {
  final prefijo = await prefijoDeVentas(db);
  final fila = await db.customSelect(
    'SELECT MAX(CAST(substr(numero, ?) AS INTEGER)) AS n FROM ventas WHERE numero LIKE ?',
    variables: [Variable<int>(prefijo.length + 2), Variable<String>('$prefijo-%')],
  ).getSingle();
  final siguiente = (fila.data['n'] as int? ?? 0) + 1;
  return '$prefijo-${siguiente.toString().padLeft(4, '0')}';
}

/// Cómo se nombra una venta en pantalla y en el ticket: el número global, o el `id` local en las ventas viejas.
String etiquetaDeVenta({required int id, String? numero}) => numero ?? '#$id';

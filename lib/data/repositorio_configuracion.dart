// Configuración centralizada (fase 8): recargo de cigarrillos, fondo fijo,
// paso de redondeo, y el producto del botón de vuelto. Todo sobre la fila
// única de `configuracion_tabla` — salvo recargo/redondeo/vuelto, que desde
// la migración v32→v33 viven en `configuracion_negocio_tabla` (El dueño,
// 2026-09-19: "que se puedan modificar las reglas del negocio... desde el
// celular") — ver el comentario de cabecera de
// `tables/configuracion_negocio.dart` para el porqué de la separación.

import 'dart:math';

import 'package:drift/drift.dart';

import '../domain/modulos.dart';
import 'database.dart';

/// La fila única de `configuracion_negocio_tabla`, o los defaults de
/// fábrica si todavía no existe — pasa en la companion antes de la primera
/// sincronización exitosa (esa tabla nunca se siembra en Android, ver el
/// comentario de `_seedDatosFijos` en `database.dart`: si lo hiciera, la
/// fila real que llegue por sync después quedaría duplicada). Vender nunca
/// puede bloquearse esperando red (Regla 8), así que acá se degrada a estos
/// valores en vez de tirar.
Future<ConfiguracionNegocio> configuracionNegocioActual(AppDatabase db) async {
  final fila = await db.select(db.configuracionNegocioTabla).getSingleOrNull();
  return fila ??
      const ConfiguracionNegocio(
        id: 0,
        recargoPrimerAtadoCentavos: 30000,
        recargoAtadoAdicionalCentavos: 10000,
        recargoSueltoCentavos: 5000,
        pasoRedondeoCentavos: 10000,
        nombreComercio: '',
        encabezadoTicket: '',
        modulosDesactivados: '',
      );
}

/// Qué módulos usa este comercio. Sin configuración legible (la companion
/// antes de la primera sincronización) se asume todo activo: vender nunca
/// puede frenarse por esto (Regla 8).
Future<ModulosNegocio> modulosNegocioActuales(AppDatabase db) async {
  final config = await configuracionNegocioActual(db);
  return ModulosNegocio.desdeTexto(config.modulosDesactivados);
}

/// Prende o apaga un módulo sin tocar los demás. Solo cambia lo que se ve y
/// lo que entra en cada cálculo: la lógica y los datos del módulo quedan
/// como están.
Future<void> configurarModulo(AppDatabase db, Modulo modulo, {required bool activo}) async {
  final actuales = await modulosNegocioActuales(db);
  await db.update(db.configuracionNegocioTabla).write(
        ConfiguracionNegocioTablaCompanion(
          modulosDesactivados: Value(actuales.conModulo(modulo, activo: activo).aTexto()),
          actualizadoEn: Value(DateTime.now()),
        ),
      );
}

Future<void> configurarNombreComercio(AppDatabase db, String nombre) {
  return db.update(db.configuracionNegocioTabla).write(
        ConfiguracionNegocioTablaCompanion(
          nombreComercio: Value(nombre.trim()),
          actualizadoEn: Value(DateTime.now()),
        ),
      );
}

Future<void> configurarEncabezadoTicket(AppDatabase db, String encabezado) {
  return db.update(db.configuracionNegocioTabla).write(
        ConfiguracionNegocioTablaCompanion(
          encabezadoTicket: Value(encabezado.trim()),
          actualizadoEn: Value(DateTime.now()),
        ),
      );
}

Future<void> configurarRecargoCigarrillos(
  AppDatabase db, {
  required int primerAtadoCentavos,
  required int atadoAdicionalCentavos,
  required int sueltoCentavos,
}) {
  if (primerAtadoCentavos < 0 || atadoAdicionalCentavos < 0 || sueltoCentavos < 0) {
    throw const FormatException('Los recargos no pueden ser negativos');
  }
  return db.update(db.configuracionNegocioTabla).write(
        ConfiguracionNegocioTablaCompanion(
          recargoPrimerAtadoCentavos: Value(primerAtadoCentavos),
          recargoAtadoAdicionalCentavos: Value(atadoAdicionalCentavos),
          recargoSueltoCentavos: Value(sueltoCentavos),
          actualizadoEn: Value(DateTime.now()),
        ),
      );
}

Future<void> configurarUmbralFaltante(AppDatabase db, int montoCentavos) {
  if (montoCentavos < 0) throw const FormatException('El monto no puede ser negativo');
  return db.update(db.configuracionTabla).write(ConfiguracionTablaCompanion(umbralFaltanteCentavos: Value(montoCentavos)));
}

Future<void> configurarFondoFijo(AppDatabase db, int montoCentavos) {
  if (montoCentavos < 0) throw const FormatException('El fondo fijo no puede ser negativo');
  return db.update(db.configuracionTabla).write(ConfiguracionTablaCompanion(fondoFijoCentavos: Value(montoCentavos)));
}

Future<void> configurarPasoRedondeo(AppDatabase db, int montoCentavos) {
  // Un paso de 0 o negativo rompería el redondeo de cada cobro en efectivo.
  if (montoCentavos <= 0) throw const FormatException('El paso de redondeo tiene que ser mayor a 0');
  return db.update(db.configuracionNegocioTabla).write(
        ConfiguracionNegocioTablaCompanion(
          pasoRedondeoCentavos: Value(montoCentavos),
          actualizadoEn: Value(DateTime.now()),
        ),
      );
}

Future<void> configurarProductoVuelto(AppDatabase db, int? productoId) {
  return db.update(db.configuracionNegocioTabla).write(
        ConfiguracionNegocioTablaCompanion(
          productoVueltoId: Value(productoId),
          actualizadoEn: Value(DateTime.now()),
        ),
      );
}

Future<void> configurarTemaOscuro(AppDatabase db, bool oscuro) {
  return db.update(db.configuracionTabla).write(ConfiguracionTablaCompanion(temaOscuro: Value(oscuro)));
}

/// Elegir un modo a mano mientras el automático está prendido no tiene
/// efecto (el tema del sistema sigue mandando) — por eso tocar el
/// switch de "Modo oscuro" lo apaga acá mismo, en la misma escritura: es
/// más intuitivo que el dueño vea su elección aplicada al toque que forzarlo a
/// primero ir a apagar el automático.
Future<void> configurarTemaOscuroManual(AppDatabase db, bool oscuro) {
  return db.update(db.configuracionTabla).write(
        ConfiguracionTablaCompanion(temaOscuro: Value(oscuro), temaAutomatico: const Value(false)),
      );
}

Future<void> configurarTemaAutomatico(AppDatabase db, bool automatico) {
  return db.update(db.configuracionTabla).write(ConfiguracionTablaCompanion(temaAutomatico: Value(automatico)));
}

Future<void> configurarBarraLateralPlegada(AppDatabase db, bool plegada) {
  return db.update(db.configuracionTabla).write(ConfiguracionTablaCompanion(barraLateralPlegada: Value(plegada)));
}

/// Selector de período compartido entre Proveedores y Productos (fase 13).
/// Guarda `PeriodoResumen.name` ('hoy'/'semana'/'mes'/'desdeUltimoPago').
Future<void> configurarPeriodoResumen(AppDatabase db, String periodo) {
  return db.update(db.configuracionTabla).write(ConfiguracionTablaCompanion(periodoResumen: Value(periodo)));
}

// ─── Companion app Android (spike 2026-09-07) ────────────────────────────

Future<String?> tokenCompanionActual(AppDatabase db) async {
  final config = await db.select(db.configuracionTabla).getSingle();
  return config.companionToken;
}

/// Genera un token nuevo (32 caracteres, alfanumérico) y lo guarda —
/// invalida cualquier emparejamiento anterior (un celular viejo con el
/// token de antes deja de poder pegarle al servidor). Se llama desde la
/// pantalla de emparejamiento cada vez que se quiere generar un QR nuevo,
/// nunca automáticamente: generar uno nuevo por las dudas invalidaría sin
/// avisar un celular ya emparejado y andando.
Future<String> regenerarTokenCompanion(AppDatabase db) async {
  const caracteres = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final azar = Random.secure();
  final token = String.fromCharCodes(
    Iterable.generate(32, (_) => caracteres.codeUnitAt(azar.nextInt(caracteres.length))),
  );
  await db.update(db.configuracionTabla).write(ConfiguracionTablaCompanion(companionToken: Value(token)));
  return token;
}

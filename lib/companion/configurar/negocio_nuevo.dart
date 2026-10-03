// El negocio nuevo del celular: decidir si el que acaba de entrar es el dueño de un negocio que todavía no tiene nada,
// dejarle la base lista para vender, y recordar qué pasos de "Configurá tu negocio" le faltan.
//
// Por qué hace falta: en Android no se siembra nada al crear la base (`_seedDatosFijos`), a propósito. Una companion
// que sembrara sus propias filas sin `global_id` chocaba con las reales al llegar por sincronización (DECISIONES,
// 2026-09-18). Eso está bien cuando los datos vienen de la PC o de otro celular, pero un dueño que usa SOLO el celular
// y arranca de cero se quedaba sin la fila de reglas del negocio (recargo, redondeo) y sin categorías, y el celular no
// tiene cómo crearlas. Acá se crean, con `global_id` propio, recién DESPUÉS de bajar todo lo de la nube y comprobar
// que no hay nada: así no se repite el choque de antes.

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/database.dart';
import '../../data/repositorio_configuracion.dart';
import '../../data/repositorio_productos.dart' as repo_productos;
import '../../domain/modulos.dart';
import '../../domain/plantillas_rubro.dart';
import '../../servicios/sync_nube.dart';
import '../../data/identidad_sync.dart';
import 'asistente_negocio.dart';

/// Rol del dueño en la cuenta de Nodo Sur (`/api/device/me`). Solo el dueño configura el negocio.
const rolDuenio = 'owner';

/// Paso de redondeo en efectivo con que arranca un negocio nuevo ($100, el default de CLAUDE.md).
const pasoRedondeoInicialCentavos = 10000;

/// ¿La base todavía no tiene nada del negocio? Sin reglas, sin categorías y sin productos.
Future<bool> baseSinNegocio(AppDatabase db) async {
  final config = await (db.select(db.configuracionNegocioTabla)..limit(1)).get();
  if (config.isNotEmpty) return false;
  final categorias = await (db.select(db.categorias)..limit(1)).get();
  if (categorias.isNotEmpty) return false;
  final productos = await (db.select(db.productos)..where((p) => p.esVarios.equals(false))..limit(1)).get();
  return productos.isEmpty;
}

/// Baja todo lo que haya en la nube y recién ahí decide si el negocio es nuevo. Si la sincronización no termina bien
/// (sin internet, sesión vencida) devuelve false: ante la duda no se crea nada, porque crear filas que después llegan
/// de la nube es justo el choque que hay que evitar.
Future<bool> esNegocioNuevoTrasSincronizar({
  required ServicioSyncNube sync,
  required AppDatabase db,
  Duration limite = const Duration(seconds: 25),
}) async {
  try {
    final hasta = DateTime.now().add(limite);
    // Si ya hay una vuelta corriendo (la que arranca sola al vincular), se espera a que termine: pedir otra encima
    // devuelve al instante el resultado viejo, sin haber bajado nada todavía.
    while (sync.enCurso && DateTime.now().isBefore(hasta)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    final r = await sync.sincronizar().timeout(hasta.difference(DateTime.now()));
    if (r is! SyncNubeOk) return false;
    return await baseSinNegocio(db);
  } catch (_) {
    return false;
  }
}

/// Deja la base de un negocio nuevo lista para vender: la fila de reglas del negocio con el recargo de cigarrillos en
/// $0 (El dueño, 2026-10-03: "si no vende cigarrillos, recargo en $0"; se cambia desde Configuración) y el redondeo en
/// $100. El comparador de precios arranca apagado, igual que en la PC. Idempotente: si la fila ya está, no la toca.
Future<void> prepararNegocioNuevo(AppDatabase db) async {
  final existente = await (db.select(db.configuracionNegocioTabla)..limit(1)).get();
  if (existente.isNotEmpty) return;
  await db.into(db.configuracionNegocioTabla).insert(
        ConfiguracionNegocioTablaCompanion(
          recargoPrimerAtadoCentavos: const Value(0),
          recargoAtadoAdicionalCentavos: const Value(0),
          recargoSueltoCentavos: const Value(0),
          pasoRedondeoCentavos: const Value(pasoRedondeoInicialCentavos),
          modulosDesactivados: Value(Modulo.compararPrecios.clave),
          globalId: Value(generarGlobalId()),
          origenDispositivo: Value(idDispositivoActual),
          actualizadoEn: Value(DateTime.now()),
        ),
      );
}

/// Paso 1: el nombre del comercio y las categorías de la plantilla del rubro. Las categorías que ya existan (mismo
/// nombre, sin importar mayúsculas) no se repiten. A diferencia de `aplicarPlantillaRubro` del escritorio, cada
/// categoría nace con `global_id` (`crearCategoria`), porque en el celular no hay una PC que las suba después.
Future<void> guardarNegocio(AppDatabase db, {required String nombre, required PlantillaRubro rubro}) async {
  await prepararNegocioNuevo(db);
  await db.transaction(() async {
    await configurarNombreComercio(db, nombre);
    final existentes = {for (final c in await db.select(db.categorias).get()) c.nombre.trim().toLowerCase()};
    for (final c in rubro.categorias) {
      if (!existentes.add(c.nombre.toLowerCase())) continue;
      await repo_productos.crearCategoria(db, c.nombre);
    }
  });
}

// ---------------------------------------------------------------------------------------------------------------------
// Pasos pendientes (la tarjeta de Inicio)

const _clavePendientes = 'companion_configuracion_pendiente';

/// Los pasos que faltan, para que Inicio muestre la tarjeta al toque cuando cambian.
final ValueNotifier<Set<PasoNegocio>> pasosPendientesNegocio = ValueNotifier(const {});

Future<Set<PasoNegocio>> leerPasosPendientes() async {
  final prefs = await SharedPreferences.getInstance();
  final guardados = prefs.getStringList(_clavePendientes) ?? const [];
  final pasos = {for (final p in PasoNegocio.values) if (guardados.contains(p.name)) p};
  pasosPendientesNegocio.value = pasos;
  return pasos;
}

Future<void> guardarPasosPendientes(Set<PasoNegocio> pasos) async {
  final prefs = await SharedPreferences.getInstance();
  if (pasos.isEmpty) {
    await prefs.remove(_clavePendientes);
  } else {
    await prefs.setStringList(_clavePendientes, [for (final p in PasoNegocio.values) if (pasos.contains(p)) p.name]);
  }
  pasosPendientesNegocio.value = Set.unmodifiable(pasos);
}

Future<void> marcarPasoHecho(PasoNegocio paso) async {
  final actuales = await leerPasosPendientes();
  await guardarPasosPendientes({...actuales}..remove(paso));
}

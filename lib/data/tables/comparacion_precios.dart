import 'package:drift/drift.dart';

/// Precios de referencia bajados de fuentes externas (comparador de
/// precios, Bruno 2026-09-14: "una noción de los precios de mi local y
/// ajustarlos según si están muy caros o muy baratos") — el dato que se ve
/// al lado de cada producto propio en `PantallaCompararPrecios`. Dos
/// fuentes hoy: SEPA/Precios Claros (`comparador_precios.dart`, La Anónima
/// y Carrefour) y la API de "Todo a tu Casa"
/// (`comparador_precios_todoatucasa.dart`).
///
/// Se reemplaza por completo, pero **por fuente** — cada actualización
/// exitosa de una fuente borra e inserta solo sus propias filas ([fuente]),
/// sin tocar las de la otra (`reemplazarPreciosReferencia`,
/// `repositorio_comparacion_precios.dart`). Esto NO es un historial, es
/// una foto del último dato bajado de cada fuente. Si en el futuro hace
/// falta ver la evolución en el tiempo, es una tabla/decisión aparte.
@DataClassName('PrecioReferenciaExterna')
class PreciosReferenciaExterna extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Mismo formato que `Productos.codigoBarras` — el cruce principal entre
  /// las dos tablas es por este valor (Regla 3: un identificador confiable
  /// primero). El cruce por [nombre] (v29, "todo lo que esté en mi
  /// sistema") es el respaldo para lo que no tiene código — pesables sobre
  /// todo — y es a propósito menos preciso.
  TextColumn get codigoBarras => text()();

  /// Nombre/descripción del producto tal como lo reporta la fuente (ej.
  /// "BANANA X KG", "Pilas AA E91 Max BP4 CHICA Energizer 4Un") — desde
  /// v29, único dato para cruzar productos SIN código de barras
  /// (`comparacionDePrecios`, `normalizarTexto` para ignorar
  /// mayúsculas/acentos). Nunca se usa para pisar un cruce por código: si
  /// hay EAN, el EAN manda.
  TextColumn get nombreProducto => text().withDefault(const Constant(''))();

  /// Precio por unidad de referencia (ej. por kilo) — no el precio del
  /// producto como viene empaquetado. SEPA lo trae como
  /// `productos_precio_referencia`, la API de Todo a tu Casa como
  /// `reference_price`. Solo tiene sentido junto con [unidadReferencia]:
  /// sin saber en qué unidad está, comparar un precio "de referencia" a
  /// ciegas contra el precio por kilo local puede comparar cosas que no
  /// son lo mismo (Regla: nunca inventar un dato, `REGLAS-NEGOCIO.md`).
  IntColumn get precioReferenciaCentavos => integer().nullable()();

  /// La unidad de [precioReferenciaCentavos] tal como la reporta la fuente
  /// (ej. "kgr", "1 Un") — `comparacionDePrecios` solo usa este precio
  /// para pesables cuando acá dice explícitamente una unidad de peso; si
  /// no, lo descarta en vez de arriesgar una comparación de unidades
  /// distintas.
  TextColumn get unidadReferencia => text().nullable()();

  /// Nombre para mostrar (ej. "La Anonima", "Hipermercado Carrefour",
  /// "Todo a tu Casa") — texto libre a propósito, no un enum: si mañana se
  /// suma un comercio nuevo no hace falta tocar el esquema.
  TextColumn get comercio => text()();

  /// 'sepa' | 'todoatucasa' — a qué actualización pertenece esta fila, para
  /// poder reemplazar/refrescar una fuente sin pisar la otra. Distinto de
  /// [comercio] (que es lo que se muestra): SEPA solo, ya trae más de un
  /// comercio bajo la misma corrida.
  TextColumn get fuente => text()();

  /// Promedio entre las sucursales de Bariloche encontradas para este
  /// comercio y este código de barras (puede haber más de una — La
  /// Anónima sola tiene 5 en Bariloche). Para "Todo a tu Casa" (un solo
  /// local online, sin sucursales) es directo, no hay nada que promediar.
  IntColumn get precioCentavos => integer()();

  DateTimeColumn get actualizadoEn => dateTime()();
}

// Cruce entre el catálogo propio y `precios_referencia_externa`
// (comparador de precios, el dueño 2026-09-14). No es domain/: comparar dos
// precios no es una fórmula de negocio, es una lectura.
//
// Dos caminos de cruce, nunca mezclados en el mismo producto (El dueño,
// 2026-09-14: "todo lo que esté en mi sistema" — antes un producto sin
// coincidencia simplemente no aparecía, ahora entra igual con "—"):
// - **Por código de barras** (`tipoCoincidencia == 'codigo'`): productos
//   por unidad con `codigoBarras` cargado. Exacto — Regla 3, un solo
//   identificador confiable.
// - **Por nombre** (`tipoCoincidencia == 'nombre'`): SOLO pesables (nunca
//   tienen código de barras). Se compara `precioPorKiloCentavos` contra
//   `precioReferenciaCentavos` de la fuente, y solo cuando esa fuente
//   confirma que su referencia está en una unidad de peso
//   (`unidadReferencia` contiene "kg") — comparar un precio de referencia
//   en otra unidad sería comparar cosas que no son lo mismo. El cruce por
//   nombre es aproximado (mayúsculas/acentos ignorados, y contención en
//   cualquier sentido, no igualdad exacta — dos comercios rara vez
//   describen el mismo producto letra por letra) y se marca como tal para
//   que se confíe menos que en un código de barras.
// Productos sin código de barras que NO son pesables (dato incompleto del
// catálogo propio) no intentan cruzarse por nombre: mejor mostrarlos sin
// coincidencia que arriesgar un cruce falso sobre un dato que en realidad
// debería tener su propio código de barras cargado.

import 'package:drift/drift.dart';

import 'database.dart';
import 'normalizacion_texto.dart';

/// Un producto propio del catálogo (activo, con algún precio propio) más
/// lo que se haya podido cruzar de `precios_referencia_externa`. Con
/// [preciosPorComercio] vacío si no se encontró en ningún comercio — el
/// producto igual genera fila (El dueño: "todo lo que esté en mi sistema").
class ComparacionPrecio {
  final int productoId;
  final String nombre;
  final int miPrecioCentavos;

  /// Si es pesable, [miPrecioCentavos] y los valores de [preciosPorComercio]
  /// son precio por kilo, no precio del producto entero.
  final bool esPesable;

  /// 'codigo' | 'nombre' — cómo se intentó cruzar este producto (ver
  /// comentario de cabecera). Nunca ambos a la vez.
  final String tipoCoincidencia;

  /// Comercio -> precio de referencia (puede haber más de un comercio por
  /// producto). Vacío si no se encontró en ninguno.
  final Map<String, int> preciosPorComercio;

  const ComparacionPrecio({
    required this.productoId,
    required this.nombre,
    required this.miPrecioCentavos,
    required this.esPesable,
    required this.tipoCoincidencia,
    required this.preciosPorComercio,
  });

  /// La mayor diferencia porcentual (en valor absoluto) contra cualquiera
  /// de los comercios encontrados — para ordenar "lo que más se aleja"
  /// primero. `null` si no se encontró en ningún comercio (esos van al
  /// final de la lista, no participan del orden por diferencia).
  double? get mayorDiferenciaAbs {
    if (preciosPorComercio.isEmpty) return null;
    return preciosPorComercio.values
        .map((precioComercio) => (precioComercio - miPrecioCentavos).abs() / miPrecioCentavos)
        .reduce((a, b) => a > b ? a : b);
  }
}

Future<DateTime?> fechaUltimaComparacionDePrecios(AppDatabase db) async {
  final fila = await (db.select(db.preciosReferenciaExterna)
        ..orderBy([(t) => OrderingTerm.desc(t.actualizadoEn)])
        ..limit(1))
      .getSingleOrNull();
  return fila?.actualizadoEn;
}

/// Cuándo actualizó por última vez UNA fuente puntual ('sepa' |
/// 'todoatucasa') — cada servicio de ingesta usa esto para decidir si le
/// toca correr de nuevo, sin importar cuándo actualizó la otra fuente.
Future<DateTime?> fechaUltimaActualizacionDeFuente(AppDatabase db, String fuente) async {
  final fila = await (db.select(db.preciosReferenciaExterna)
        ..where((t) => t.fuente.equals(fuente))
        ..orderBy([(t) => OrderingTerm.desc(t.actualizadoEn)])
        ..limit(1))
      .getSingleOrNull();
  return fila?.actualizadoEn;
}

/// Una fila ya lista para guardar — cada servicio de ingesta
/// (`comparador_precios.dart`, `comparador_precios_todoatucasa.dart`)
/// arma su propia lista con su propio criterio (SEPA promedia entre
/// sucursales antes de llegar acá) y la pasa a [reemplazarPreciosReferencia].
/// [codigoBarras] vacío ('') significa "sin código válido" — ese producto
/// solo puede cruzarse por [nombreProducto].
class PrecioReferenciaFila {
  final String codigoBarras;
  final String nombreProducto;
  final String comercio;
  final int precioCentavos;
  final int? precioReferenciaCentavos;
  final String? unidadReferencia;
  const PrecioReferenciaFila({
    required this.codigoBarras,
    required this.nombreProducto,
    required this.comercio,
    required this.precioCentavos,
    this.precioReferenciaCentavos,
    this.unidadReferencia,
  });
}

/// Reemplaza las filas de [fuente] por [filas] — nunca toca las de otra
/// fuente (Regla de esta tabla: cada actualización es dueña solo de lo
/// suyo). Una corrida vacía (ej. la API/el archivo vino vacío por algo
/// transitorio) no borra lo que ya había: mejor un dato viejo que ninguno.
Future<void> reemplazarPreciosReferencia(
  AppDatabase db, {
  required String fuente,
  required List<PrecioReferenciaFila> filas,
}) async {
  if (filas.isEmpty) return;
  final ahora = DateTime.now();
  await db.transaction(() async {
    await (db.delete(db.preciosReferenciaExterna)..where((t) => t.fuente.equals(fuente))).go();
    for (final fila in filas) {
      await db.into(db.preciosReferenciaExterna).insert(
        PreciosReferenciaExternaCompanion.insert(
          codigoBarras: fila.codigoBarras,
          nombreProducto: Value(fila.nombreProducto),
          comercio: fila.comercio,
          fuente: fuente,
          precioCentavos: fila.precioCentavos,
          precioReferenciaCentavos: Value(fila.precioReferenciaCentavos),
          unidadReferencia: Value(fila.unidadReferencia),
          actualizadoEn: ahora,
        ),
      );
    }
  });
}

/// Mínimo de caracteres normalizados para intentar un cruce por nombre —
/// nombres cortos ("Pan", "Sal") dan falsos positivos por contención
/// (“empanada” contiene “pan”). Por debajo de esto, mejor sin coincidencia
/// que una coincidencia falsa.
const _largoMinimoParaCruzarPorNombre = 4;

bool _nombresCoinciden(String localNormalizado, String externoNormalizado) {
  if (localNormalizado.length < _largoMinimoParaCruzarPorNombre) return false;
  return externoNormalizado.contains(localNormalizado) ||
      localNormalizado.contains(externoNormalizado);
}

bool _esUnidadDePeso(String? unidad) => (unidad ?? '').toLowerCase().contains('kg');

/// Ordenado por mayor diferencia primero (El dueño: para ver de un vistazo lo
/// que más vale la pena revisar), lo sin coincidencia al final, alfabético
/// entre sí.
Future<List<ComparacionPrecio>> comparacionDePrecios(AppDatabase db) async {
  // Todo el catálogo activo con algún precio propio — Regla: "Varios" no
  // tiene precio fijo (Regla 5/9), no hay nada que mostrarle como "mi
  // precio", así que queda afuera aunque esté activo.
  final productos = await (db.select(db.productos)
        ..where(
          (p) =>
              p.activo.equals(true) &
              p.esVarios.equals(false) &
              (p.precioCentavos.isNotNull() | p.precioPorKiloCentavos.isNotNull()),
        ))
      .get();
  if (productos.isEmpty) return const [];

  final referencias = await db.select(db.preciosReferenciaExterna).get();
  final porEan = <String, List<PrecioReferenciaExterna>>{};
  final porNombreNormalizado = <String, List<PrecioReferenciaExterna>>{};
  for (final r in referencias) {
    if (r.codigoBarras.isNotEmpty) {
      porEan.putIfAbsent(r.codigoBarras, () => []).add(r);
    } else if (r.nombreProducto.isNotEmpty) {
      porNombreNormalizado
          .putIfAbsent(normalizarTexto(r.nombreProducto), () => [])
          .add(r);
    }
  }

  final resultado = <ComparacionPrecio>[];
  for (final producto in productos) {
    if (producto.esPesable) {
      final miPrecio = producto.precioPorKiloCentavos;
      if (miPrecio == null) continue; // pesable sin precio por kilo cargado: nada que mostrar
      final nombreNormalizado = normalizarTexto(producto.nombre);
      final precios = <String, int>{};
      for (final entrada in porNombreNormalizado.entries) {
        if (!_nombresCoinciden(nombreNormalizado, entrada.key)) continue;
        for (final r in entrada.value) {
          if (r.precioReferenciaCentavos == null || !_esUnidadDePeso(r.unidadReferencia)) {
            continue;
          }
          precios[r.comercio] = r.precioReferenciaCentavos!;
        }
      }
      resultado.add(
        ComparacionPrecio(
          productoId: producto.id,
          nombre: producto.nombre,
          miPrecioCentavos: miPrecio,
          esPesable: true,
          tipoCoincidencia: 'nombre',
          preciosPorComercio: precios,
        ),
      );
    } else {
      final miPrecio = producto.precioCentavos;
      if (miPrecio == null) continue; // por unidad sin precio cargado: nada que mostrar
      final encontrados = porEan[producto.codigoBarras ?? ''];
      resultado.add(
        ComparacionPrecio(
          productoId: producto.id,
          nombre: producto.nombre,
          miPrecioCentavos: miPrecio,
          esPesable: false,
          tipoCoincidencia: 'codigo',
          preciosPorComercio: {
            for (final r in encontrados ?? const <PrecioReferenciaExterna>[])
              r.comercio: r.precioCentavos,
          },
        ),
      );
    }
  }

  resultado.sort((a, b) {
    final diferenciaA = a.mayorDiferenciaAbs;
    final diferenciaB = b.mayorDiferenciaAbs;
    if (diferenciaA == null && diferenciaB == null) {
      return normalizarTexto(a.nombre).compareTo(normalizarTexto(b.nombre));
    }
    if (diferenciaA == null) return 1;
    if (diferenciaB == null) return -1;
    return diferenciaB.compareTo(diferenciaA);
  });
  return resultado;
}

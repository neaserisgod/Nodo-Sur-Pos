// Importador de CSV de productos (Fase 2, CLAUDE.md). Formato con
// encabezado, columnas por nombre (no por posición) para que reordenar
// columnas en la planilla no rompa nada:
//
//   codigo_barras,nombre,proveedor,categoria,es_pesable,precio,costo,
//   precio_por_kilo,costo_por_kilo,stock,stock_gramos
//
// `proveedor` es el código de Regla 16 (S/F/C/B/W/G/O), no un id interno: es
// lo que alguien realmente escribiría a mano en una planilla. `categoria` es
// el nombre; si no existe todavía, se crea (el markup de referencia de una
// categoría es solo informativo, así que crearla vacía no inventa una regla
// de negocio). Un proveedor con código desconocido, en cambio, es un error:
// los códigos de proveedor son una lista cerrada (Regla 16), no un campo
// libre.

import 'package:csv/csv.dart';
import 'package:drift/drift.dart';

import '../domain/dinero.dart';
import 'database.dart';
import 'identidad_sync.dart';
import 'repositorio_productos.dart';

class ErrorImportacionCsv {
  /// 1-based; la fila 1 es el encabezado, así que la primera fila de datos
  /// es la 2 — el número que alguien buscaría abriendo el archivo en un
  /// editor de planillas.
  final int fila;
  final String mensaje;

  const ErrorImportacionCsv({required this.fila, required this.mensaje});
}

class ResultadoImportacionCsv {
  final int insertados;
  final int actualizados;
  final List<ErrorImportacionCsv> errores;

  const ResultadoImportacionCsv({
    required this.insertados,
    required this.actualizados,
    required this.errores,
  });
}

const _columnasEsperadas = [
  'codigo_barras',
  'nombre',
  'proveedor',
  'categoria',
  'es_pesable',
  'precio',
  'costo',
  'precio_por_kilo',
  'costo_por_kilo',
  'stock',
  'stock_gramos',
];

/// Importa productos desde [contenidoCsv]. Cada fila que falla queda
/// registrada en el resultado en vez de abortar el archivo entero: un error
/// en la fila 200 no debería tirar abajo las 199 anteriores.
///
/// El precio y el costo se parsean con `parsearARS`
/// (lib/domain/dinero.dart) — el mismo helper que cualquier campo de precio
/// de la app, así que el CSV acepta "1.500,50", "1500.50" y "1500" por igual.
///
/// [usuarioId] es quien corre la importación: cada alta o cambio de precio
/// que produce queda en `historial_de_precios` a su nombre (Regla 14, "cada
/// cambio de precio o costo queda en historial" — una importación masiva no
/// es una excepción a esa regla).
Future<ResultadoImportacionCsv> importarProductosDesdeCsv(
  AppDatabase db,
  String contenidoCsv, {
  required int usuarioId,
}) async {
  final filas = Csv(fieldDelimiter: ',', autoDetect: false).decode(contenidoCsv);

  if (filas.isEmpty) {
    return const ResultadoImportacionCsv(insertados: 0, actualizados: 0, errores: []);
  }

  final encabezado = filas.first.map((c) => c.toString().trim()).toList();
  final indice = {for (var i = 0; i < encabezado.length; i++) encabezado[i]: i};

  final faltantes = _columnasEsperadas.where((c) => !indice.containsKey(c)).toList();
  if (faltantes.isNotEmpty) {
    return ResultadoImportacionCsv(
      insertados: 0,
      actualizados: 0,
      errores: [
        ErrorImportacionCsv(fila: 1, mensaje: 'Faltan columnas: ${faltantes.join(', ')}'),
      ],
    );
  }

  String? campo(List<dynamic> fila, String columna) {
    final posicion = indice[columna]!;
    // Una fila más corta que el encabezado (planilla con celdas finales vacías) no es un error: esa celda está en blanco.
    if (posicion >= fila.length) return null;
    final valor = fila[posicion].toString().trim();
    return valor.isEmpty ? null : valor;
  }

  var insertados = 0;
  var actualizados = 0;
  final errores = <ErrorImportacionCsv>[];

  final proveedoresPorCodigo = {
    for (final p in await db.select(db.proveedores).get()) p.codigo: p,
  };
  final categoriasPorNombre = {
    for (final c in await db.select(db.categorias).get()) c.nombre: c,
  };

  // Todo o nada: si algo inesperado corta la importación a la mitad, no queda una lista de precios a medio actualizar.
  await db.transaction(() async {
  for (var i = 1; i < filas.length; i++) {
    final numeroFila = i + 1;
    final fila = filas[i];
    if (fila.every((c) => c.toString().trim().isEmpty)) continue;

    try {
      final nombre = campo(fila, 'nombre');
      if (nombre == null) {
        errores.add(ErrorImportacionCsv(fila: numeroFila, mensaje: 'Falta el nombre'));
        continue;
      }

      final codigoBarras = campo(fila, 'codigo_barras');

      final proveedorCodigo = campo(fila, 'proveedor');
      int? proveedorId;
      if (proveedorCodigo != null) {
        final proveedor = proveedoresPorCodigo[proveedorCodigo];
        if (proveedor == null) {
          errores.add(ErrorImportacionCsv(
            fila: numeroFila,
            mensaje: 'Proveedor desconocido: "$proveedorCodigo"',
          ));
          continue;
        }
        proveedorId = proveedor.id;
      }

      final categoriaNombre = campo(fila, 'categoria');
      int? categoriaId;
      if (categoriaNombre != null) {
        var categoria = categoriasPorNombre[categoriaNombre];
        if (categoria == null) {
          final id = await db.into(db.categorias).insert(
                CategoriasCompanion.insert(
                  nombre: categoriaNombre,
                  globalId: Value(generarGlobalId()),
                  origenDispositivo: Value(idDispositivoActual),
                  actualizadoEn: Value(DateTime.now()),
                ),
              );
          categoria = Categoria(
            id: id,
            nombre: categoriaNombre,
            markupDefaultBp: 0,
            activo: true,
          );
          categoriasPorNombre[categoriaNombre] = categoria;
        }
        categoriaId = categoria.id;
      }

      final esPesable = _parsearBooleano(campo(fila, 'es_pesable'));

      int? precioCentavos;
      int? costoCentavos;
      int? precioPorKiloCentavos;
      int? costoPorKiloCentavos;

      if (esPesable) {
        final precioPorKiloTexto = campo(fila, 'precio_por_kilo');
        if (precioPorKiloTexto == null) {
          errores.add(ErrorImportacionCsv(
            fila: numeroFila,
            mensaje: 'Pesable sin precio_por_kilo (Regla 7: no puede quedar en blanco)',
          ));
          continue;
        }
        precioPorKiloCentavos = parsearARS(precioPorKiloTexto);
        final costoPorKiloTexto = campo(fila, 'costo_por_kilo');
        if (costoPorKiloTexto != null) costoPorKiloCentavos = parsearARS(costoPorKiloTexto);
      } else {
        final precioTexto = campo(fila, 'precio');
        if (precioTexto == null) {
          errores.add(ErrorImportacionCsv(fila: numeroFila, mensaje: 'Falta el precio'));
          continue;
        }
        precioCentavos = parsearARS(precioTexto);
        final costoTexto = campo(fila, 'costo');
        if (costoTexto != null) costoCentavos = parsearARS(costoTexto);
      }

      final stockTexto = campo(fila, 'stock');
      final stockGramosTexto = campo(fila, 'stock_gramos');
      final stock = stockTexto == null ? 0 : int.parse(stockTexto);
      final stockGramos = stockGramosTexto == null ? null : int.parse(stockGramosTexto);

      final companion = ProductosCompanion(
        codigoBarras: Value(codigoBarras),
        nombre: Value(nombre),
        proveedorId: Value(proveedorId),
        categoriaId: Value(categoriaId),
        esPesable: Value(esPesable),
        precioCentavos: Value(precioCentavos),
        costoCentavos: Value(costoCentavos),
        precioPorKiloCentavos: Value(precioPorKiloCentavos),
        costoPorKiloCentavos: Value(costoPorKiloCentavos),
        stock: Value(stock),
        stockGramos: Value(stockGramos),
        actualizadoEn: Value(DateTime.now()),
      );

      // Matchea por código de barras si lo trae; si no, por nombre exacto. Si hay más de uno no se adivina cuál.
      final coincidentes = codigoBarras != null
          ? await (db.select(db.productos)..where((p) => p.codigoBarras.equals(codigoBarras))).get()
          : await (db.select(db.productos)..where((p) => p.nombre.equals(nombre))).get();
      if (coincidentes.length > 1) {
        errores.add(ErrorImportacionCsv(
          fila: numeroFila,
          mensaje: 'Hay ${coincidentes.length} productos con ${codigoBarras != null ? 'ese código de barras' : 'ese nombre'}: '
              'no se sabe cuál actualizar (corregilo en Proveedores)',
        ));
        continue;
      }
      final existente = coincidentes.firstOrNull;

      if (existente == null) {
        // `globalId`/`origenDispositivo` solo en el alta — no en `companion`
        // en sí, que también se usa tal cual para actualizar un producto ya
        // existente más abajo, y ahí no hay que regenerar su identidad.
        final nuevoId = await db.into(db.productos).insert(
              companion.copyWith(
                globalId: Value(generarGlobalId()),
                origenDispositivo: Value(idDispositivoActual),
              ),
            );
        await registrarCambioDePrecio(
          db,
          productoId: nuevoId,
          usuarioId: usuarioId,
          anterior: null,
          precioCentavos: precioCentavos,
          costoCentavos: costoCentavos,
          precioPorKiloCentavos: precioPorKiloCentavos,
          costoPorKiloCentavos: costoPorKiloCentavos,
        );
        insertados++;
      } else {
        // Reimportar una lista de precios no puede dejar el stock en 0: solo se toca si la planilla trae el dato, y
        // entonces queda en el registro de movimientos como cualquier ajuste (Regla 6).
        await (db.update(db.productos)..where((p) => p.id.equals(existente.id)))
            .write(companion.copyWith(stock: const Value.absent(), stockGramos: const Value.absent()));
        if (esPesable ? stockGramosTexto != null : stockTexto != null) {
          await ajustarStockRapido(
            db,
            productoId: existente.id,
            usuarioId: usuarioId,
            stock: esPesable ? existente.stock : stock,
            stockGramos: esPesable ? stockGramos : null,
            motivo: 'Importación CSV',
          );
        }

        await registrarCambioDePrecio(
          db,
          productoId: existente.id,
          usuarioId: usuarioId,
          anterior: existente,
          precioCentavos: precioCentavos,
          costoCentavos: costoCentavos,
          precioPorKiloCentavos: precioPorKiloCentavos,
          costoPorKiloCentavos: costoPorKiloCentavos,
        );
        await completarCostoDeVentasSinCosto(
          db,
          productoId: existente.id,
          costoCentavos: costoCentavos,
          costoPorKiloCentavos: costoPorKiloCentavos,
        );
        actualizados++;
      }
    } on FormatException catch (e) {
      errores.add(ErrorImportacionCsv(fila: numeroFila, mensaje: e.message));
    } on ArgumentError catch (e) {
      errores.add(ErrorImportacionCsv(fila: numeroFila, mensaje: '${e.message}'));
    }
  }
  });

  return ResultadoImportacionCsv(
    insertados: insertados,
    actualizados: actualizados,
    errores: errores,
  );
}

bool _parsearBooleano(String? valor) {
  if (valor == null) return false;
  final normalizado = valor.trim().toLowerCase();
  return normalizado == 'true' ||
      normalizado == '1' ||
      normalizado == 'si' ||
      normalizado == 'sí';
}

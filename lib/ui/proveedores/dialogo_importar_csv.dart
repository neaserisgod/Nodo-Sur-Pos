// Importar CSV, ahora desde Proveedores (fase 13: absorbe Productos).
//
// "Lenguaje de diseño" (mock `DialogosProveedores` → Importar lista de
// precios): el archivo se elige con el selector nativo (`file_selector`, que
// el proyecto ya usa para las carpetas de PDF y respaldo) en vez de tipear
// la ruta, y el resultado se ve en tres cifras (actualizados, nuevos, con
// error). El mapeo de columnas del mock no está: el importador lee un
// formato fijo de columnas, y mapear a mano abriría la puerta a importar
// precios en la columna del costo.
//
// Pasado al kit (corrección post-aprobación): `Modal` + `CampoTexto` en vez
// de `AlertDialog`.

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/importacion_csv.dart';
import '../comun/botones.dart';
import '../comun/modal.dart';
import '../comun/tarjetas.dart';
import '../tema/iconos.dart';
import '../tema/tokens.dart';

Future<void> mostrarDialogoImportarCsv(
  BuildContext context, {
  required AppDatabase db,
  required int usuarioId,
}) {
  return mostrarModal<void>(
    context,
    builder: (context) => _DialogoImportarCsv(db: db, usuarioId: usuarioId),
  );
}

class _DialogoImportarCsv extends StatefulWidget {
  const _DialogoImportarCsv({required this.db, required this.usuarioId});
  final AppDatabase db;
  final int usuarioId;

  @override
  State<_DialogoImportarCsv> createState() => _DialogoImportarCsvState();
}

class _DialogoImportarCsvState extends State<_DialogoImportarCsv> {
  XFile? _archivo;
  int? _filas;
  ResultadoImportacionCsv? _resultado;
  String? _error;
  bool _importando = false;

  Future<void> _elegir() async {
    final archivo = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
    );
    if (archivo == null) return;
    final contenido = await archivo.readAsString();
    // Sin contar el encabezado ni las líneas vacías del final.
    final filas =
        contenido.split('\n').where((l) => l.trim().isNotEmpty).length - 1;
    if (!mounted) return;
    setState(() {
      _archivo = archivo;
      _filas = filas < 0 ? 0 : filas;
      _resultado = null;
      _error = null;
    });
  }

  Future<void> _importar() async {
    final archivo = _archivo;
    if (archivo == null) return;
    setState(() {
      _importando = true;
      _error = null;
      _resultado = null;
    });
    try {
      final contenido = await archivo.readAsString();
      final resultado = await importarProductosDesdeCsv(
        widget.db,
        contenido,
        usuarioId: widget.usuarioId,
      );
      if (mounted) setState(() => _resultado = resultado);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo leer el archivo: $e');
    } finally {
      if (mounted) setState(() => _importando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final r = _resultado;
    return Modal(
      titulo: 'Importar lista de precios',
      subtitulo: 'Un CSV con productos, precios y costos',
      ancho: 620,
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BloqueSuave(
            child: Row(
              children: [
                IconoPlz(IconosPlazoleta.descripcionArchivo, color: colores.acento),
                const SizedBox(width: Espaciado.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _archivo?.name ?? 'Ningún archivo elegido',
                        style: textTheme.titleSmall,
                      ),
                      if (_filas != null)
                        Text('$_filas filas', style: textTheme.bodySmall),
                    ],
                  ),
                ),
                BotonSecundario(
                  texto: _archivo == null ? 'Elegir archivo' : 'Cambiar',
                  onPressed: _importando ? null : _elegir,
                ),
              ],
            ),
          ),
          const SizedBox(height: Espaciado.md),
          Text(
            'Si un producto ya existe (mismo código de barras, o mismo nombre si no tiene código), '
            'reimportarlo ACTUALIZA su precio y costo — no solo agrega productos nuevos.',
            style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.medium),
          ),
          if (_error != null) ...[
            const SizedBox(height: Espaciado.sm),
            Text(_error!, style: TextStyle(color: colores.error)),
          ],
          if (r != null) ...[
            const SizedBox(height: Espaciado.md),
            Row(
              children: [
                Expanded(
                  child: _Cifra(
                    valor: r.actualizados,
                    texto: 'actualizados',
                    tono: Tono.acento,
                  ),
                ),
                const SizedBox(width: Espaciado.sm),
                Expanded(
                  child: _Cifra(
                    valor: r.insertados,
                    texto: 'productos nuevos',
                    tono: Tono.ganancia,
                  ),
                ),
                const SizedBox(width: Espaciado.sm),
                Expanded(
                  child: _Cifra(
                    valor: r.errores.length,
                    texto: 'con error',
                    tono: r.errores.isEmpty ? Tono.neutro : Tono.error,
                  ),
                ),
              ],
            ),
            for (final e in r.errores.take(10))
              Text('Fila ${e.fila}: ${e.mensaje}', style: textTheme.bodySmall),
          ],
        ],
      ),
      botones: [
        BotonSecundario(
          texto: r == null ? 'Cancelar' : 'Cerrar',
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (r == null)
          BotonPrimario(
            texto: _importando
                ? 'Importando…'
                : (_filas == null ? 'Importar' : 'Importar $_filas'),
            onPressed: _importando || _archivo == null ? null : _importar,
          ),
      ],
    );
  }
}

class _Cifra extends StatelessWidget {
  const _Cifra({required this.valor, required this.texto, required this.tono});

  final int valor;
  final String texto;
  final Tono tono;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Espaciado.md,
        vertical: Espaciado.sm,
      ),
      decoration: BoxDecoration(
        color: context.colores.fondo,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Text(
            '$valor',
            style: textTheme.titleLarge
                ?.copyWith(fontWeight: Pesos.fuerte)
                .tabular,
          ),
          const SizedBox(width: Espaciado.sm),
          Expanded(
            child: Insignia(texto: texto, tono: tono),
          ),
        ],
      ),
    );
  }
}

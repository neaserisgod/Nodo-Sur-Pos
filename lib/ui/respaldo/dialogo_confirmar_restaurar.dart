// Confirmación fuerte antes de restaurar (acción destructiva e irreversible,
// pedida explícitamente por el dueño). Al confirmar: cierra la base, copia el
// archivo elegido encima de la real, y reinicia la app sola.

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/repositorio_respaldo.dart';
import '../../servicios/nube.dart';
import '../comun/botones.dart';
import '../comun/modal.dart';
import '../tema/tokens.dart';

Future<void> mostrarDialogoConfirmarRestaurar(
  BuildContext context, {
  required AppDatabase db,
  required ArchivoRespaldo archivo,
  required String fechaFormateada,
  VoidCallback reiniciarApp = reiniciarAppComoNueva,
  Future<void> Function() olvidarRegistroSync = _olvidarRegistroSync,
  Future<String> Function() resolverRutaDestino = rutaArchivoBaseDeDatos,
  Future<void> Function({required String rutaRespaldo, required String rutaDestino}) copiarArchivo =
      restaurarDesdeArchivo,
}) async {
  final confirmado = await mostrarModal<bool>(
    context,
    builder: (context) => Modal(
      titulo: '¿Restaurar este respaldo?',
      contenido: Text(
        'Esto reemplaza TODOS los datos actuales por los del respaldo del '
        '$fechaFormateada. No se puede deshacer. La aplicación se va a '
        'cerrar y volver a abrir sola con esos datos.',
      ),
      botones: [
        BotonSecundario(texto: 'Cancelar', onPressed: () => Navigator.of(context).pop(false)),
        // No es `BotonPrimario` a propósito: esto es destructivo, no la
        // acción de todos los días — el color con significado que le
        // corresponde es `colores.error` (Regla de armonía), nunca el
        // acento ámbar de una acción normal.
        SizedBox(
          height: Medidas.alturaControl,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colores.error,
              foregroundColor: context.colores.errorTexto,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restaurar y reiniciar'),
          ),
        ),
      ],
    ),
  );

  if (confirmado != true) return;

  final rutaDestino = await resolverRutaDestino();
  await db.close();
  await copiarArchivo(rutaRespaldo: archivo.ruta, rutaDestino: rutaDestino);
  // El registro de sync dice "esto ya lo subí / hasta acá bajé" sobre la base que se acaba de reemplazar: dejarlo
  // haría que la PC no baje lo que la copia no tiene o que suba como nuevo lo que ya estaba. Se baja todo de nuevo.
  await olvidarRegistroSync();
  reiniciarApp();
}

Future<void> _olvidarRegistroSync() async {
  try {
    await nubeApp?.sync?.reiniciar();
  } catch (_) {
    // Sin registro que borrar no hay nada que arreglar; la restauración no puede fallar por esto.
  }
}

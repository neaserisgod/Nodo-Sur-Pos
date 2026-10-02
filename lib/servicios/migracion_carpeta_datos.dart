import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Archivos que viven en la carpeta de datos de la app y que no se pueden perder en una actualización:
/// la cuenta de Nodo Sur vinculada, el estado de la sincronización y las preferencias.
const archivosDeCarpetaDatos = ['nodosur_cuenta.json', 'nodosur_sync.json'];
const archivoPreferencias = 'shared_preferences.json';

/// Nombre del producto en Runner.rc hasta la compilación 2102. Desde la 2103 es "Nodo Sur POS".
const nombreCarpetaViejo = 'la_plazoleta';

class ResultadoMigracion {
  final bool huboCarpetaVieja;
  final List<String> archivosTraidos;
  final List<String> fallos;
  const ResultadoMigracion({required this.huboCarpetaVieja, this.archivosTraidos = const [], this.fallos = const []});
}

/// En Windows la carpeta de datos es `%APPDATA%\<empresa>\<nombre del producto>`. Al renombrar el producto
/// la app pasó a mirar una carpeta nueva y "perdió" la vinculación y las preferencias (los archivos seguían
/// en la vieja). Esto los trae a la nueva sin pisar nada que ya exista allá y sin borrar la vieja, que queda
/// de respaldo. Nunca tira: un fallo se informa en el resultado, no frena el arranque.
Future<ResultadoMigracion> migrarCarpetaDatosVieja({required Directory nueva, String nombreViejo = nombreCarpetaViejo}) async {
  final vieja = Directory(p.join(p.dirname(nueva.path), nombreViejo));
  if (p.equals(vieja.path, nueva.path) || !await vieja.exists()) {
    return const ResultadoMigracion(huboCarpetaVieja: false);
  }
  final traidos = <String>[];
  final fallos = <String>[];

  for (final nombre in archivosDeCarpetaDatos) {
    try {
      final origen = File(p.join(vieja.path, nombre));
      final destino = File(p.join(nueva.path, nombre));
      if (!await origen.exists() || await destino.exists()) continue;
      await nueva.create(recursive: true);
      await origen.copy(destino.path);
      traidos.add(nombre);
    } catch (e) {
      fallos.add('$nombre: $e');
    }
  }

  try {
    final origen = File(p.join(vieja.path, archivoPreferencias));
    if (await origen.exists()) {
      final viejas = jsonDecode(await origen.readAsString()) as Map<String, dynamic>;
      final destino = File(p.join(nueva.path, archivoPreferencias));
      final actuales = await destino.exists() ? jsonDecode(await destino.readAsString()) as Map<String, dynamic> : <String, dynamic>{};
      // Lo que ya hay en la carpeta nueva gana: es lo más reciente que hizo la persona.
      final faltan = {for (final e in viejas.entries) if (!actuales.containsKey(e.key)) e.key: e.value};
      if (faltan.isNotEmpty) {
        await nueva.create(recursive: true);
        await destino.writeAsString(jsonEncode({...faltan, ...actuales}));
        traidos.add(archivoPreferencias);
      }
    }
  } catch (e) {
    fallos.add('$archivoPreferencias: $e');
  }

  return ResultadoMigracion(huboCarpetaVieja: true, archivosTraidos: traidos, fallos: fallos);
}

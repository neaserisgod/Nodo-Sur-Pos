// El perfil del celular sale de la CUENTA con que se entró, no de una lista (El dueño, 2026-10-02: "que los empleados
// directamente logueen con su perfil en lugar de seleccionar; eso del selector solo en el POS de escritorio").
//
// El sitio sabe quién es la persona (`GET /api/device/me`: el nombre de su cuenta de Google y su rol); acá se busca el
// perfil del POS con ese nombre (sin mayúsculas ni acentos) o, si no hay, se crea. No se agrega ninguna columna: el perfil
// de un POS es solo un nombre (Regla 18), y como `usuarios` ya se sincroniza, el perfil nuevo aparece en la PC y en los
// demás celulares.

import '../data/normalizacion_texto.dart';
import '../servicios/cuenta_nube.dart';
import 'cliente_companion.dart' show UsuarioCompanion;
import 'emparejamiento.dart';
import 'servicio_companion.dart';

/// El perfil de esta persona existe en el POS pero el dueño lo desactivó. Entrar con la cuenta no lo reactiva: el dueño
/// decidió que esa persona no opera, y eso se levanta desde la PC.
class PerfilDesactivado implements Exception {
  const PerfilDesactivado(this.nombre);
  final String nombre;
  @override
  String toString() => 'El perfil de $nombre está desactivado en el POS. Pedile al dueño que lo active.';
}

const _largoMaximoNombre = 60; // el del campo `usuarios.nombre`

/// Busca o crea el perfil de [perfil] en [servicio] y lo deja guardado como el usuario de este celular.
Future<UsuarioCompanion> resolverPerfilDeCuenta({required PerfilDeCuenta perfil, required ServicioCompanion servicio}) async {
  var nombre = perfil.nombre.trim();
  if (nombre.isEmpty) nombre = perfil.email.split('@').first;
  if (nombre.length > _largoMaximoNombre) nombre = nombre.substring(0, _largoMaximoNombre).trim();
  final buscado = normalizarTexto(nombre);

  final existentes = await servicio.usuarios();
  final coincidencias = [for (final u in existentes) if (normalizarTexto(u.nombre) == buscado) u];
  UsuarioCompanion elegido;
  if (coincidencias.isEmpty) {
    final id = await servicio.crearUsuarioNuevo(nombre);
    elegido = UsuarioCompanion(id: id, nombre: nombre);
  } else {
    // Si hay uno activo y otro desactivado con el mismo nombre, gana el activo.
    final activo = coincidencias.where((u) => u.activo).firstOrNull;
    if (activo == null) throw PerfilDesactivado(coincidencias.first.nombre);
    elegido = activo;
  }
  await guardarUsuario(elegido);
  return elegido;
}

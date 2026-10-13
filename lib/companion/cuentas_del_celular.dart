// Varias cuentas en un mismo celular, sin cerrar ninguna y sin mezclar nada (El dueño, 2026-10-13). El porqué y el índice
// están en `domain/cuentas_del_celular.dart`; acá se mueven los archivos.
//
// La cuenta ACTIVA vive donde vivió siempre: la base (`la_plazoleta.sqlite` en documentos), la carpeta de datos (cuenta
// vinculada, registro de la sync, bot de WhatsApp) y las preferencias. Cada GUARDADA vive en `cuentas_guardadas/<id>/` dentro
// de la carpeta de datos: `base/`, `soporte/` y `preferencias.json`. Cambiar de cuenta es mover la activa a su carpeta y traer
// la elegida a su lugar. Mover un archivo dentro del mismo almacenamiento es instantáneo (no se copia la base).
//
// Si el celular se apaga a la mitad, el índice dice en qué paso quedó y `terminarCambioPendiente` (al abrir la app, antes de
// tocar nada) lo termina: cada paso "mueve lo que quede", así que repetirlo no rompe nada.
//
// Solo Android: en el navegador no hay carpetas (la versión web no tiene varias cuentas).

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/cuentas_del_celular.dart';
import '../servicios/almacenes_del_equipo.dart';
import '../servicios/cuenta_nube.dart' show PerfilDeCuenta;
import 'base_local.dart';
import 'borrar_celular.dart';
import 'emparejamiento.dart' show leerUsuario;

const _carpetaGuardadas = 'cuentas_guardadas';
const _archivoIndice = 'indice.json';
const _archivoPreferencias = 'preferencias.json';

/// Lo que hay en la carpeta de datos y NO es de una cuenta: las otras cuentas y los registros de errores del aparato.
const _soporteDelAparato = {_carpetaGuardadas, 'logs'};

/// Los archivos de la base (`AppDatabase._abrirConexion`, `driftDatabase(name: 'la_plazoleta')`).
final _archivosBase = [for (final s in ['', '-wal', '-shm', '-journal']) '$nombreBaseCelular.sqlite$s'];

/// Dónde guarda la app sus cosas. En la app real, las de Android; en los tests, carpetas temporales.
class CarpetasDelCelular {
  const CarpetasDelCelular({required this.documentos, required this.soporte});
  final Directory documentos;
  final Directory soporte;

  static Future<CarpetasDelCelular> delSistema() async =>
      CarpetasDelCelular(documentos: await getApplicationDocumentsDirectory(), soporte: await getApplicationSupportDirectory());

  Directory get guardadas => Directory(p.join(soporte.path, _carpetaGuardadas));
  Directory guardada(String id) => Directory(p.join(guardadas.path, id));
  File get _indice => File(p.join(guardadas.path, _archivoIndice));
}

Future<IndiceCuentas> leerIndiceCuentas([CarpetasDelCelular? carpetas]) async {
  final c = carpetas ?? await CarpetasDelCelular.delSistema();
  try {
    if (!await c._indice.exists()) return IndiceCuentas.vacio;
    return IndiceCuentas.desdeJson(jsonDecode(await c._indice.readAsString()));
  } catch (_) {
    return IndiceCuentas.vacio;
  }
}

/// Se escribe aparte y se renombra: un corte de luz deja el índice viejo o el nuevo, nunca uno a medias.
Future<void> _guardarIndice(CarpetasDelCelular c, IndiceCuentas indice) async {
  await c.guardadas.create(recursive: true);
  final temporal = File('${c._indice.path}.nuevo');
  await temporal.writeAsString(jsonEncode(indice.toJson()), flush: true);
  await temporal.rename(c._indice.path);
}

/// La activa, con un id fijo (la primera vez se le inventa uno) y lo último que se sabe de ella.
CuentaDelCelular identificarActiva(IndiceCuentas indice, {required String? email, required String? nombre, NegocioDeLaCuenta? negocio}) =>
    CuentaDelCelular(
      id: indice.activa?.id ?? _idNuevo(),
      email: email,
      nombre: nombre,
      negocio: negocio?.negocio,
      sucursal: negocio?.sucursal,
      nombreNegocio: negocio?.nombreNegocio,
      nombreSucursal: negocio?.nombreSucursal,
    );

/// En qué negocio y sucursal está la cuenta activa, tal como lo dijo el sitio al entrar. Se guarda en las preferencias de la
/// cuenta (viaja con ella al cambiar), así cambiar de cuenta no necesita internet para saber cómo mostrarla.
typedef NegocioDeLaCuenta = ({int? negocio, int? sucursal, String? nombreNegocio, String? nombreSucursal});

const _claveNegocio = 'companion_negocio_de_la_cuenta';

Future<void> guardarNegocioDeEstaCuenta(PerfilDeCuenta perfil) async {
  if (perfil.negocio == null) return;
  await (await SharedPreferences.getInstance()).setString(
    _claveNegocio,
    jsonEncode({
      'negocio': perfil.negocio,
      'sucursal': perfil.sucursal,
      'nombreNegocio': perfil.nombreNegocio,
      'nombreSucursal': perfil.nombreSucursal,
    }),
  );
}

Future<NegocioDeLaCuenta?> leerNegocioDeEstaCuenta() async {
  try {
    final texto = (await SharedPreferences.getInstance()).getString(_claveNegocio);
    if (texto == null) return null;
    final j = jsonDecode(texto) as Map<String, dynamic>;
    return (
      negocio: (j['negocio'] as num?)?.toInt(),
      sucursal: (j['sucursal'] as num?)?.toInt(),
      nombreNegocio: j['nombreNegocio'] as String?,
      nombreSucursal: j['nombreSucursal'] as String?,
    );
  } catch (_) {
    return null;
  }
}

String _idNuevo() {
  final azar = Random.secure().nextInt(1 << 32).toRadixString(36);
  return 'c${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}$azar';
}

/// Guarda la activa como [actual] y trae [destino] (null: deja el lugar vacío para entrar con otra cuenta). Antes, quien
/// llama tiene que haber frenado todo lo que escribe (sync, base, bot): ver `frenarLoQueEscribe`.
Future<void> cambiarDeCuenta({required CuentaDelCelular actual, required String? destino, CarpetasDelCelular? carpetas}) async {
  final c = carpetas ?? await CarpetasDelCelular.delSistema();
  final indice = await leerIndiceCuentas(c);
  if (indice.cambio != null) await _terminar(c, indice);
  await _terminar(c, empezarCambio(await leerIndiceCuentas(c), actual: actual, destino: destino));
}

/// La activa ya se borró ("Cerrar sesión y borrar"): si hay otras guardadas trae la última usada y devuelve cuál; si no, deja
/// el celular sin cuentas y devuelve null.
Future<CuentaDelCelular?> traerOtraTrasBorrar([CarpetasDelCelular? carpetas, String? preferida]) async {
  final c = carpetas ?? await CarpetasDelCelular.delSistema();
  final indice = await leerIndiceCuentas(c);
  if (indice.guardadas.isEmpty) {
    if (await c._indice.exists()) await _guardarIndice(c, const IndiceCuentas());
    return null;
  }
  await _terminar(c, empezarTraerTrasBorrar(indice, preferida: preferida));
  return (await leerIndiceCuentas(c)).activa;
}

/// Al abrir la app, antes de leer nada: si un cambio quedó a medias, lo termina. Devuelve si había uno.
Future<bool> terminarCambioPendiente([CarpetasDelCelular? carpetas]) async {
  final c = carpetas ?? await CarpetasDelCelular.delSistema();
  final indice = await leerIndiceCuentas(c);
  if (indice.cambio == null) return false;
  await _terminar(c, indice);
  return true;
}

Future<void> _terminar(CarpetasDelCelular c, IndiceCuentas indice) async {
  var actual = indice;
  final cambio = actual.cambio!;
  if (cambio.paso == PasoCambio.guardando) {
    await _guardarIndice(c, actual);
    if (cambio.guardarComo != null) await _guardarActiva(c, cambio.guardarComo!);
    actual = IndiceCuentas(activa: actual.activa, guardadas: actual.guardadas, cambio: cambio.conPaso(PasoCambio.trayendo));
  }
  // Se anota "trayendo" ANTES de traer: si no, repetir "guardando" después de un corte devolvería a la carpeta lo ya traído.
  await _guardarIndice(c, actual);
  if (cambio.traer != null) await _traer(c, cambio.traer!);
  await _guardarIndice(c, terminarCambio(actual));
}

/// Mueve la base, la carpeta de datos (menos lo del aparato) y las preferencias de la cuenta a su carpeta guardada.
Future<void> _guardarActiva(CarpetasDelCelular c, String id) async {
  final destino = c.guardada(id);
  final base = Directory(p.join(destino.path, 'base'));
  final soporte = Directory(p.join(destino.path, 'soporte'));
  await base.create(recursive: true);
  await soporte.create(recursive: true);
  for (final nombre in _archivosBase) {
    await _mover(File(p.join(c.documentos.path, nombre)), p.join(base.path, nombre));
  }
  if (await c.soporte.exists()) {
    await for (final e in c.soporte.list()) {
      final nombre = p.basename(e.path);
      if (_soporteDelAparato.contains(nombre)) continue;
      await _mover(e, p.join(soporte.path, nombre));
    }
  }
  // Preferencias: se suman a las que ya se hubieran guardado en un intento cortado (nunca se pisan con menos) y recién
  // después se sacan de las activas.
  final prefs = await SharedPreferences.getInstance();
  final archivo = File(p.join(destino.path, _archivoPreferencias));
  final guardadas = await _leerPreferencias(archivo);
  final deLaCuenta = [for (final k in prefs.getKeys()) if (esPreferenciaDeLaCuenta(k)) k];
  for (final k in deLaCuenta) {
    final v = _codificar(prefs.get(k));
    if (v != null) guardadas[k] = v;
  }
  final temporal = File('${archivo.path}.nuevo');
  await temporal.writeAsString(jsonEncode(guardadas), flush: true);
  await temporal.rename(archivo.path);
  for (final k in deLaCuenta) {
    await prefs.remove(k);
  }
}

/// Lo inverso: trae la cuenta guardada a su lugar y borra su carpeta.
Future<void> _traer(CarpetasDelCelular c, String id) async {
  final origen = c.guardada(id);
  if (!await origen.exists()) return;
  final base = Directory(p.join(origen.path, 'base'));
  if (await base.exists()) {
    await c.documentos.create(recursive: true);
    await for (final e in base.list()) {
      await _mover(e, p.join(c.documentos.path, p.basename(e.path)));
    }
  }
  final soporte = Directory(p.join(origen.path, 'soporte'));
  if (await soporte.exists()) {
    await for (final e in soporte.list()) {
      await _mover(e, p.join(c.soporte.path, p.basename(e.path)));
    }
  }
  final archivo = File(p.join(origen.path, _archivoPreferencias));
  if (await archivo.exists()) {
    final prefs = await SharedPreferences.getInstance();
    for (final MapEntry(:key, :value) in (await _leerPreferencias(archivo)).entries) {
      await _escribir(prefs, key, value);
    }
  }
  await origen.delete(recursive: true);
}

/// Mueve [e] a [destino], pisando lo que hubiera ahí (lo dejado por un intento cortado). Si no se puede renombrar (otro
/// almacenamiento), copia y borra.
Future<void> _mover(FileSystemEntity e, String destino) async {
  if (!await e.exists()) return;
  final previo = FileSystemEntity.typeSync(destino);
  if (previo == FileSystemEntityType.directory) await Directory(destino).delete(recursive: true);
  if (previo == FileSystemEntityType.file || previo == FileSystemEntityType.link) await File(destino).delete();
  try {
    await e.rename(destino);
  } on FileSystemException {
    await _copiar(e, destino);
    await e.delete(recursive: true);
  }
}

Future<void> _copiar(FileSystemEntity e, String destino) async {
  if (e is File) {
    await e.copy(destino);
  } else if (e is Directory) {
    await Directory(destino).create(recursive: true);
    await for (final hijo in e.list()) {
      await _copiar(hijo, p.join(destino, p.basename(hijo.path)));
    }
  }
}

// Las preferencias van con su tipo: en JSON un entero y un decimal se confunden, y una lista vuelve sin tipo.
Map<String, dynamic>? _codificar(Object? v) => switch (v) {
  bool() => {'t': 'b', 'v': v},
  int() => {'t': 'i', 'v': v},
  double() => {'t': 'd', 'v': v},
  String() => {'t': 's', 'v': v},
  List() => {'t': 'l', 'v': [for (final x in v) '$x']},
  _ => null,
};

Future<void> _escribir(SharedPreferences prefs, String k, Object? cod) async {
  if (cod is! Map) return;
  final v = cod['v'];
  switch (cod['t']) {
    case 'b' when v is bool:
      await prefs.setBool(k, v);
    case 'i' when v is num:
      await prefs.setInt(k, v.toInt());
    case 'd' when v is num:
      await prefs.setDouble(k, v.toDouble());
    case 's' when v is String:
      await prefs.setString(k, v);
    case 'l' when v is List:
      await prefs.setStringList(k, [for (final x in v) '$x']);
  }
}

Future<Map<String, dynamic>> _leerPreferencias(File archivo) async {
  try {
    if (!await archivo.exists()) return {};
    final j = jsonDecode(await archivo.readAsString());
    return j is Map<String, dynamic> ? j : {};
  } catch (_) {
    return {};
  }
}

/// Lo que hacen los botones de cambiar de cuenta: frena todo lo que escribe, guarda la activa (con su mail, su perfil y su
/// negocio, para mostrarla en la lista) y trae [destino] (null: deja el lugar vacío para entrar con otra cuenta o en otro
/// negocio). Después hay que cerrar la app (`cerrarLaApp`): lo que quedó en memoria es de la cuenta anterior.
Future<void> pasarACuenta(String? destino) async {
  final email = (await (await almacenCuentaDelEquipo()).leer())?.email;
  final nombre = (await leerUsuario())?.nombre;
  final negocio = await leerNegocioDeEstaCuenta();
  await frenarLoQueEscribe();
  final indice = await leerIndiceCuentas();
  await cambiarDeCuenta(actual: identificarActiva(indice, email: email, nombre: nombre, negocio: negocio), destino: destino);
}

// Varios negocios en un mismo celular, sin cerrar ninguno y sin mezclar nada (El dueño, 2026-10-13). El porqué y el índice
// están en `domain/cuentas_del_celular.dart`; acá se mueven los archivos.
//
// La cuenta ACTIVA vive donde vivió siempre: la base (`la_plazoleta.sqlite` en documentos), la carpeta de datos (cuenta
// vinculada, registro de la sync, bot de WhatsApp) y las preferencias. Cada GUARDADA vive en `cuentas_guardadas/<id>/` dentro
// de la carpeta de datos: `base/`, `soporte/`, `preferencias.json` y `cuenta.json` (quién es, para rearmar el índice si hiciera
// falta). Cambiar de cuenta es mover la activa a su carpeta y traer la elegida a su lugar. Mover dentro del mismo
// almacenamiento es renombrar: instantáneo, no se copia la base.
//
// Blindaje (El dueño, 2026-10-13: "blindalo lo más que puedas"):
//  * Se cambia en DOS tiempos. Primero solo se GUARDA la activa; lo elegido se TRAE recién con todo frenado y la app desarmada
//    (`volverAEmpezar`, que corre `terminarCambioAlArrancar`, lo mismo que `main` al abrir). Así lo que todavía escribía algo
//    en segundo plano (una vuelta de la sync, una preferencia) cae en la cuenta vieja y no en la nueva: antes de traer se
//    vuelve a barrer el lugar de la activa hacia la carpeta de la vieja. La app ya no se cierra (2026-10-14).
//  * Cada paso se anota en el índice ANTES de hacerse, y cada paso "mueve lo que quede": si el celular se apaga a la mitad,
//    al abrir se repite y termina. Repetir nunca rompe nada.
//  * Nunca se borra nada de una cuenta que se guarda o se trae. Si en el destino ya hay algo con el mismo nombre (lo dejó un
//    intento cortado, o escribió algo tarde), se aparta a `conflictos/` en vez de pisarlo.
//  * El índice se escribe aparte y se renombra (nunca queda a medias) y se guarda el anterior. Si aun así no se puede leer,
//    se rearma con el `cuenta.json` de cada carpeta: una cuenta guardada nunca queda invisible.
//  * Si al abrir no se puede terminar un cambio, la app NO sigue con media cuenta puesta: muestra el problema y deja
//    reintentar (`companion_app.dart`).
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
import '../servicios/registro_errores.dart';
import 'base_local.dart';
import 'borrar_celular.dart';
import 'emparejamiento.dart' show leerUsuario;

const _carpetaGuardadas = 'cuentas_guardadas';
const _archivoIndice = 'indice.json';
const _archivoPreferencias = 'preferencias.json';
const _archivoCuenta = 'cuenta.json';

/// Dentro de `cuentas_guardadas/`: lo que se encontró en el lugar de la activa al traer otra y no era de nadie conocido.
/// Nunca se borra: queda apartado por si hiciera falta recuperarlo a mano.
const _carpetaHuerfanos = '_huerfanos';

/// Lo que hay en la carpeta de datos y NO es de una cuenta: las otras cuentas y los registros de errores del aparato.
const _soporteDelAparato = {_carpetaGuardadas, 'logs'};

/// Los archivos de la base (`AppDatabase._abrirConexion`, `driftDatabase(name: 'la_plazoleta')`).
final _archivosBase = [for (final s in ['', '-wal', '-shm', '-journal']) '$nombreBaseCelular.sqlite$s'];

/// "Pasar a" una cuenta cuya carpeta ya no está en el celular (se borró a mano, o el índice quedó viejo).
class CuentaNoEstaEnElCelular implements Exception {
  const CuentaNoEstaEnElCelular();
  @override
  String toString() => 'Ese negocio ya no está guardado en este celular.';
}

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
  File get _indiceAnterior => File('${_indice.path}.anterior');
  Directory get _huerfanos => Directory(p.join(guardadas.path, _carpetaHuerfanos));
}

// --- índice -----------------------------------------------------------------------------------------------------------------

/// Las cuentas del celular, para mostrarlas: sin las guardadas cuya carpeta ya no existe (traerlas daría un lugar vacío).
Future<IndiceCuentas> leerIndiceCuentas([CarpetasDelCelular? carpetas]) async {
  final c = carpetas ?? await CarpetasDelCelular.delSistema();
  final indice = await _leerIndice(c);
  if (indice.cambio != null) return indice; // a mitad de un cambio se muestra tal cual: lo termina el próximo arranque
  final presentes = [
    for (final g in indice.guardadas)
      if (await c.guardada(g.id).exists()) g,
  ];
  return presentes.length == indice.guardadas.length ? indice : IndiceCuentas(activa: indice.activa, guardadas: presentes);
}

Future<IndiceCuentas> _leerIndice(CarpetasDelCelular c) async {
  var primero = true;
  for (final archivo in [c._indice, c._indiceAnterior]) {
    try {
      if (await archivo.exists()) {
        final j = jsonDecode(await archivo.readAsString());
        if (j is Map<String, dynamic>) {
          final indice = IndiceCuentas.desdeJson(j);
          // El de respaldo puede estar un paso atrás: se completa con las carpetas que existen.
          return primero ? indice : await _completarConCarpetas(c, indice);
        }
      }
    } catch (e, st) {
      await registrarError('Índice de cuentas ilegible: ${p.basename(archivo.path)}', e, st);
    }
    primero = false;
  }
  return _completarConCarpetas(c, IndiceCuentas.vacio);
}

/// Suma al índice las carpetas guardadas que no figuran (cada una dice quién es en su `cuenta.json`).
Future<IndiceCuentas> _completarConCarpetas(CarpetasDelCelular c, IndiceCuentas indice) async {
  final conocidas = {for (final g in indice.guardadas) g.id, if (indice.cambio == null) ?indice.activa?.id};
  final sumar = [
    for (final g in (await _rearmarIndice(c)).guardadas)
      if (!conocidas.contains(g.id)) g,
  ];
  if (sumar.isEmpty) return indice;
  return IndiceCuentas(activa: indice.activa, guardadas: [...indice.guardadas, ...sumar], cambio: indice.cambio);
}

/// Sin índice que se pueda leer: cada carpeta guardada dice quién es. La activa queda sin nombre (se anota al entrar).
Future<IndiceCuentas> _rearmarIndice(CarpetasDelCelular c) async {
  if (!await c.guardadas.exists()) return IndiceCuentas.vacio;
  final guardadas = <CuentaDelCelular>[];
  await for (final e in c.guardadas.list()) {
    if (e is! Directory || p.basename(e.path).startsWith('_')) continue;
    try {
      final j = jsonDecode(await File(p.join(e.path, _archivoCuenta)).readAsString()) as Map<String, dynamic>;
      guardadas.add(CuentaDelCelular.desdeJson({...j, 'id': p.basename(e.path)}));
    } catch (_) {
      // Una carpeta sin `cuenta.json` igual se ofrece, con su id: mejor "Sin cuenta" que invisible.
      guardadas.add(CuentaDelCelular(id: p.basename(e.path), email: null));
    }
  }
  return IndiceCuentas(guardadas: guardadas);
}

/// Se escribe aparte y se renombra: un corte de luz deja el índice viejo o el nuevo, nunca uno a medias. El anterior queda
/// como respaldo.
Future<void> _guardarIndice(CarpetasDelCelular c, IndiceCuentas indice) async {
  await c.guardadas.create(recursive: true);
  if (await c._indice.exists()) await c._indice.copy(c._indiceAnterior.path);
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
      negocio: negocio?.negocio ?? indice.activa?.negocio,
      sucursal: negocio?.sucursal ?? indice.activa?.sucursal,
      nombreNegocio: negocio?.nombreNegocio ?? indice.activa?.nombreNegocio,
      nombreSucursal: negocio?.nombreSucursal ?? indice.activa?.nombreSucursal,
    );

String _idNuevo() {
  final azar = Random.secure().nextInt(1 << 32).toRadixString(36);
  return 'c${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}$azar';
}

/// Al entrar con una cuenta: queda anotada como la activa. Sin esto, una cuenta recién agregada seguiría figurando como "lugar
/// vacío", y la pantalla de entrar ofrecería "Volver a…" (que descarta lo de este lugar) aunque ya tenga ventas.
Future<void> anotarCuentaActiva({required PerfilDeCuenta perfil, CarpetasDelCelular? carpetas}) async {
  final c = carpetas ?? await CarpetasDelCelular.delSistema();
  final indice = await _leerIndice(c);
  if (indice.cambio != null) return; // lo termina el próximo arranque; no se pisa a la mitad
  // Un celular que nunca tuvo más de una cuenta no necesita índice.
  if (indice.activa == null && indice.guardadas.isEmpty && !await c.guardadas.exists()) return;
  final negocio = (negocio: perfil.negocio, sucursal: perfil.sucursal, nombreNegocio: perfil.nombreNegocio, nombreSucursal: perfil.nombreSucursal);
  final activa = identificarActiva(indice, email: perfil.email, nombre: perfil.nombre, negocio: negocio);
  await _guardarIndice(c, IndiceCuentas(activa: activa, guardadas: indice.guardadas));
}

// --- negocio de la cuenta activa ---------------------------------------------------------------------------------------------

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

// --- cambiar ----------------------------------------------------------------------------------------------------------------

/// Guarda la activa como [actual] y trae [destino] (null: deja el lugar vacío para entrar con otra cuenta). Antes, quien
/// llama tiene que haber frenado todo lo que escribe (sync, base, bot): ver `frenarLoQueEscribe`.
///
/// Con [soloGuardar] (lo que hace la app de verdad) se guarda la activa y se deja anotado el resto: lo termina
/// `terminarCambioAlArrancar` al abrir de nuevo. Sin él, se hace todo ya (tests, y el arranque mismo).
Future<void> cambiarDeCuenta({
  required CuentaDelCelular actual,
  required String? destino,
  CarpetasDelCelular? carpetas,
  bool soloGuardar = false,
}) async {
  final c = carpetas ?? await CarpetasDelCelular.delSistema();
  var indice = await _leerIndice(c);
  if (indice.cambio != null) {
    await _terminar(c, indice);
    indice = await _leerIndice(c);
  }
  if (destino != null && !await c.guardada(destino).exists()) throw const CuentaNoEstaEnElCelular();
  final empezado = empezarCambio(indice, actual: actual, destino: destino);
  await _guardarIndice(c, empezado);
  await _guardarActiva(c, actual);
  if (!soloGuardar) await _terminar(c, empezado);
}

/// La activa ya se borró ("Cerrar sesión y borrar") y hay otras guardadas: deja anotado traer [preferida] (si no, la última
/// usada) y la devuelve; se trae al abrir de nuevo, como cualquier cambio. Sin otras, deja el celular sin cuentas y devuelve
/// null. Con [ahora] la trae ya (tests).
Future<CuentaDelCelular?> traerOtraTrasBorrar([CarpetasDelCelular? carpetas, String? preferida, bool ahora = false]) async {
  final c = carpetas ?? await CarpetasDelCelular.delSistema();
  final indice = await leerIndiceCuentas(c);
  if (indice.guardadas.isEmpty) {
    if (await c._indice.exists()) await _guardarIndice(c, const IndiceCuentas());
    return null;
  }
  final empezado = empezarTraerTrasBorrar(indice, preferida: preferida);
  // Se anota como "guardando" sin nada que guardar: al abrir, se vuelve a vaciar el lugar (por si algo escribió tarde) y
  // recién después se trae la otra.
  final anotado = IndiceCuentas(guardadas: empezado.guardadas, cambio: empezado.cambio!.conPaso(PasoCambio.guardando));
  await _guardarIndice(c, anotado);
  if (ahora) await _terminar(c, anotado);
  final id = empezado.cambio!.traer;
  return indice.guardadas.firstWhere((g) => g.id == id);
}

/// Si un cambio quedó a medias (o se dejó para el arranque), lo termina. Devuelve si había uno.
Future<bool> terminarCambioPendiente([CarpetasDelCelular? carpetas]) async {
  final c = carpetas ?? await CarpetasDelCelular.delSistema();
  final indice = await _leerIndice(c);
  if (indice.cambio == null) return false;
  await _terminar(c, indice);
  return true;
}

/// Lo primero que hace la app en Android, antes de leer nada de la cuenta (`main.dart`). Devuelve el error si no pudo terminar
/// un cambio (la app no tiene que seguir con media cuenta puesta), o null.
Future<Object?> terminarCambioAlArrancar() async {
  try {
    await terminarCambioPendiente();
    return null;
  } catch (e, st) {
    await registrarError('Terminar el cambio de cuenta al arrancar', e, st);
    return e;
  }
}

Future<void> _terminar(CarpetasDelCelular c, IndiceCuentas indice) async {
  var actual = indice;
  final cambio = actual.cambio!;
  if (cambio.paso == PasoCambio.guardando) {
    // Se vuelve a barrer el lugar de la activa: lo que se escribió después de guardarla (antes de que la app se cerrara) es de
    // ella y va a su carpeta; si se borró, se descarta.
    if (cambio.guardarComo != null) {
      await _guardarActiva(c, actual.activa ?? CuentaDelCelular(id: cambio.guardarComo!, email: null));
    } else {
      await descartarActiva(c);
    }
    actual = IndiceCuentas(activa: actual.activa, guardadas: actual.guardadas, cambio: cambio.conPaso(PasoCambio.trayendo));
    // "Trayendo" se anota ANTES de traer: si no, repetir "guardando" después de un corte devolvería a la carpeta lo ya traído.
    await _guardarIndice(c, actual);
  }
  var faltaLaTraida = false;
  if (cambio.traer != null) {
    if (await c.guardada(cambio.traer!).exists()) {
      await _traer(c, cambio.traer!);
    } else {
      faltaLaTraida = !await _yaSeTrajo(c);
    }
  }
  final terminado = terminarCambio(actual);
  // La que se iba a traer ya no estaba: el lugar queda vacío (para entrar de nuevo), nunca a nombre de una cuenta sin datos.
  await _guardarIndice(c, faltaLaTraida ? IndiceCuentas(guardadas: terminado.guardadas) : terminado);
}

/// La carpeta de la traída no existe: o ya se trajo entera (y se borró su carpeta vacía, justo antes de un corte) o falta.
/// Si en el lugar de la activa hay una base o una cuenta vinculada, es que se trajo.
Future<bool> _yaSeTrajo(CarpetasDelCelular c) async =>
    await File(p.join(c.documentos.path, _archivosBase.first)).exists() || await _hayAlgoDeLaCuenta(c);

Future<bool> _hayAlgoDeLaCuenta(CarpetasDelCelular c) async {
  if (!await c.soporte.exists()) return false;
  await for (final e in c.soporte.list()) {
    if (!_soporteDelAparato.contains(p.basename(e.path))) return true;
  }
  return false;
}

/// Mueve la base, la carpeta de datos (menos lo del aparato) y las preferencias de la cuenta a su carpeta guardada.
Future<void> _guardarActiva(CarpetasDelCelular c, CuentaDelCelular cuenta) async {
  final destino = c.guardada(cuenta.id);
  final base = Directory(p.join(destino.path, 'base'));
  final soporte = Directory(p.join(destino.path, 'soporte'));
  final conflictos = Directory(p.join(destino.path, 'conflictos'));
  await base.create(recursive: true);
  await soporte.create(recursive: true);
  // Quién es, para poder rearmar el índice desde las carpetas. Un barrido sin datos de la cuenta no pisa lo que ya se sabía.
  final datos = File(p.join(destino.path, _archivoCuenta));
  if (cuenta.email != null || cuenta.nombreNegocio != null || !await datos.exists()) {
    await _escribirSeguro(datos, jsonEncode(cuenta.toJson()));
  }
  for (final nombre in _archivosBase) {
    await _mover(File(p.join(c.documentos.path, nombre)), p.join(base.path, nombre), apartarEn: conflictos);
  }
  if (await c.soporte.exists()) {
    await for (final e in c.soporte.list()) {
      final nombre = p.basename(e.path);
      if (_soporteDelAparato.contains(nombre)) continue;
      await _mover(e, p.join(soporte.path, nombre), apartarEn: conflictos);
    }
  }
  // Preferencias: se suman a las ya guardadas (un intento cortado, o el barrido del arranque), con las de ahora ganando, y
  // recién después de escritas se sacan de las activas.
  final prefs = await SharedPreferences.getInstance();
  final archivo = File(p.join(destino.path, _archivoPreferencias));
  final guardadas = await _leerPreferencias(archivo);
  final deLaCuenta = [for (final k in prefs.getKeys()) if (esPreferenciaDeLaCuenta(k)) k];
  if (deLaCuenta.isEmpty && await archivo.exists()) return;
  for (final k in deLaCuenta) {
    final v = _codificar(prefs.get(k));
    if (v != null) guardadas[k] = v;
  }
  await _escribirSeguro(archivo, jsonEncode(guardadas));
  for (final k in deLaCuenta) {
    await prefs.remove(k);
  }
}

/// Saca del lugar de la activa todo lo que es de una cuenta (base, carpeta de datos, preferencias), sin guardarlo. Lo usa
/// "Cerrar sesión y borrar".
Future<void> descartarActiva(CarpetasDelCelular c) async {
  for (final nombre in _archivosBase) {
    await _borrar(File(p.join(c.documentos.path, nombre)));
  }
  if (await c.soporte.exists()) {
    await for (final e in c.soporte.list()) {
      if (_soporteDelAparato.contains(p.basename(e.path))) continue;
      await _borrar(e);
    }
  }
  final prefs = await SharedPreferences.getInstance();
  for (final k in [...prefs.getKeys()]) {
    if (esPreferenciaDeLaCuenta(k)) await prefs.remove(k);
  }
}

/// Lo inverso de guardar: trae la cuenta guardada a su lugar y borra su carpeta (ya vacía).
Future<void> _traer(CarpetasDelCelular c, String id) async {
  final origen = c.guardada(id);
  // Lo que haya en el lugar de la activa a esta altura no es de nadie conocido (se guardó o se descartó en el paso anterior):
  // se aparta, nunca se mezcla con la que llega.
  final huerfanos = Directory(p.join(c._huerfanos.path, '${DateTime.now().millisecondsSinceEpoch}'));
  final base = Directory(p.join(origen.path, 'base'));
  if (await base.exists()) {
    await c.documentos.create(recursive: true);
    await for (final e in base.list()) {
      await _mover(e, p.join(c.documentos.path, p.basename(e.path)), apartarEn: huerfanos);
    }
  }
  final soporte = Directory(p.join(origen.path, 'soporte'));
  if (await soporte.exists()) {
    await c.soporte.create(recursive: true);
    await for (final e in soporte.list()) {
      await _mover(e, p.join(c.soporte.path, p.basename(e.path)), apartarEn: huerfanos);
    }
  }
  final prefs = await SharedPreferences.getInstance();
  final sueltas = [for (final k in prefs.getKeys()) if (esPreferenciaDeLaCuenta(k)) k];
  if (sueltas.isNotEmpty) {
    await huerfanos.create(recursive: true);
    await _escribirSeguro(
      File(p.join(huerfanos.path, _archivoPreferencias)),
      jsonEncode({for (final k in sueltas) k: _codificar(prefs.get(k))}),
    );
    for (final k in sueltas) {
      await prefs.remove(k);
    }
  }
  for (final MapEntry(:key, :value) in (await _leerPreferencias(File(p.join(origen.path, _archivoPreferencias)))).entries) {
    await _escribir(prefs, key, value);
  }
  // Lo que pudiera haber quedado en conflictos de esa cuenta viaja con ella: no se pierde al borrar la carpeta.
  final conflictos = Directory(p.join(origen.path, 'conflictos'));
  if (await conflictos.exists() && !(await conflictos.list().isEmpty)) {
    await _mover(conflictos, p.join(c._huerfanos.path, '$id-conflictos-${DateTime.now().millisecondsSinceEpoch}'), apartarEn: huerfanos);
  }
  await origen.delete(recursive: true);
}

/// Mueve [e] a [destino]. Si ahí ya hay algo, NO se pisa: se aparta a [apartarEn] con un nombre único. Si no se puede
/// renombrar (otro almacenamiento), copia y recién después borra el original.
Future<void> _mover(FileSystemEntity e, String destino, {required Directory apartarEn}) async {
  if (!await e.exists()) return;
  if (FileSystemEntity.typeSync(destino, followLinks: false) != FileSystemEntityType.notFound) {
    await apartarEn.create(recursive: true);
    final aparte = p.join(apartarEn.path, '${p.basename(destino)}.${DateTime.now().microsecondsSinceEpoch}');
    await _renombrarOCopiar(_entidad(destino), aparte);
  }
  await _renombrarOCopiar(e, destino);
}

FileSystemEntity _entidad(String ruta) =>
    FileSystemEntity.isDirectorySync(ruta) ? Directory(ruta) : File(ruta);

Future<void> _renombrarOCopiar(FileSystemEntity e, String destino) async {
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

Future<void> _borrar(FileSystemEntity e) async {
  try {
    if (await e.exists()) await e.delete(recursive: true);
  } on FileSystemException catch (err, st) {
    // Un archivo que no se deja borrar no frena el resto; queda anotado.
    await registrarError('No se pudo borrar ${p.basename(e.path)}', err, st);
  }
}

Future<void> _escribirSeguro(File archivo, String texto) async {
  final temporal = File('${archivo.path}.nuevo');
  await temporal.writeAsString(texto, flush: true);
  await temporal.rename(archivo.path);
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

// --- lo que usan las pantallas ----------------------------------------------------------------------------------------------

/// Lo que hacen los botones de cambiar de cuenta: frena todo lo que escribe y guarda la activa (con su mail, su perfil y su
/// negocio, para mostrarla en la lista). Lo elegido ([destino]; null deja el lugar vacío para entrar con otra cuenta o en otro
/// negocio) se trae después, al armar la app de cero (`volverAEmpezar`).
///
/// Lanza [CuentaNoEstaEnElCelular] ANTES de frenar nada si el destino ya no está: la app puede seguir como si nada.
Future<void> pasarACuenta(String? destino) async {
  final c = await CarpetasDelCelular.delSistema();
  if (destino != null && (!await c.guardada(destino).exists() || !(await leerIndiceCuentas(c)).guardadas.any((g) => g.id == destino))) {
    throw const CuentaNoEstaEnElCelular();
  }
  final email = (await (await almacenCuentaDelEquipo()).leer())?.email;
  final nombre = (await leerUsuario())?.nombre;
  final negocio = await leerNegocioDeEstaCuenta();
  await frenarLoQueEscribe();
  final indice = await _leerIndice(c);
  await cambiarDeCuenta(
    actual: identificarActiva(indice, email: email, nombre: nombre, negocio: negocio),
    destino: destino,
    carpetas: c,
    soloGuardar: true,
  );
}

// Lo que la sync por la nube tiene que recordar entre una vuelta y otra, y la
// lógica de qué subir y cómo aplicar lo que bajó. No habla con la red ni con
// archivos: eso es `servicios/sync_nube.dart`. Las filas se leen y se
// escriben con el mismo motor de siempre (`repositorio_sincronizacion.dart`,
// Regla 3), acá solo se decide cuáles.
//
// Por qué hace falta un "registro" y no alcanza con el cursor de siempre
// (`cambiosDesde`): con "gana el último en llegar" (ver `aplicarCambios`,
// `ordenDeLlegada`), una fila que este dispositivo recibió de otro y vuelve a
// subir como si fuera suya llegaría DESPUÉS de lo que ese otro haya editado
// mientras tanto, y lo pisaría con datos viejos. Por eso cada fila que se
// sube o se aplica deja su huella acá: lo que ya está sincronizado no se
// vuelve a subir.

import 'dart:convert';
import 'dart:io' show gzip;

import 'package:crypto/crypto.dart';

import 'database.dart';
import 'repositorio_sincronizacion.dart';

/// Columnas que no cuentan para saber si una fila cambió. El stock de un
/// producto lo mueve cada movimiento de stock aplicado (nunca viaja como
/// valor, ver `_columnasStockDeProductos`): si contara, aplicar un
/// movimiento de otro dispositivo haría parecer "editado" al producto.
const _columnasFueraDeHuella = {
  'productos': {'stock', 'stock_gramos'},
};

String huellaSyncNube(String tabla, Map<String, dynamic> fila) {
  final fuera = _columnasFueraDeHuella[tabla];
  if (fuera == null) return huellaDeFila(fila);
  return huellaDeFila({
    for (final e in fila.entries)
      if (!fuera.contains(e.key)) e.key: e.value,
  });
}

/// Una fila sincronizada: su valor de cursor (`actualizado_en` o `id`, ver
/// `valorCursorDe`) y la huella de su contenido.
typedef VistaFila = ({int valor, String huella});

class EstadoSyncNube {
  EstadoSyncNube({
    this.cursorBajada = 0,
    Map<String, int>? cursoresSubida,
    Map<String, Map<String, VistaFila>>? vistas,
    Map<String, List<Map<String, dynamic>>>? sinAplicar,
    this.necesitaCopia = false,
  })  : cursoresSubida = cursoresSubida ?? {},
        vistas = vistas ?? {},
        sinAplicar = sinAplicar ?? {};

  /// Último número de orden del servidor (`seq`) ya aplicado.
  int cursorBajada;

  /// Por tabla: desde dónde buscar cambios propios para subir.
  final Map<String, int> cursoresSubida;

  /// Por tabla y `global_id`: las filas que ya están sincronizadas y todavía
  /// pueden volver a aparecer en [cambiosDesde] (su valor es >= al cursor).
  final Map<String, Map<String, VistaFila>> vistas;

  /// Filas bajadas que no se pudieron aplicar todavía (falta una fila de la
  /// que dependen). Se reintentan en la próxima bajada.
  final Map<String, List<Map<String, dynamic>>> sinAplicar;

  /// El servidor ya no guarda lo que este dispositivo se perdió (estuvo
  /// apagado más tiempo que la retención): hay que ponerse al día desde una
  /// copia de seguridad.
  bool necesitaCopia;

  int cursorDe(String tabla) => cursoresSubida[tabla] ?? 0;

  void _recordar(String tabla, String globalId, int valor, String huella) {
    if (valor < cursorDe(tabla)) return; // ya no puede reaparecer: no hace falta recordarla
    (vistas[tabla] ??= {})[globalId] = (valor: valor, huella: huella);
  }

  void _podar(String tabla) {
    final cursor = cursorDe(tabla);
    vistas[tabla]?.removeWhere((_, v) => v.valor < cursor);
  }

  Map<String, dynamic> toJson() => {
        'cursorBajada': cursorBajada,
        'necesitaCopia': necesitaCopia,
        'cursoresSubida': cursoresSubida,
        'vistas': {
          for (final t in vistas.entries)
            t.key: {for (final f in t.value.entries) f.key: [f.value.valor, f.value.huella]},
        },
        'sinAplicar': sinAplicar,
      };

  /// Un archivo roto o de otra forma vuelve a empezar de cero: el peor caso es
  /// volver a bajar todo y volver a subir lo que no esté en el servidor, y
  /// ambas cosas son seguras (el servidor repite lotes iguales, y aplicar es
  /// un upsert por `global_id`).
  factory EstadoSyncNube.desdeJson(Object? crudo) {
    try {
      final j = crudo as Map<String, dynamic>;
      return EstadoSyncNube(
        cursorBajada: (j['cursorBajada'] as num?)?.toInt() ?? 0,
        necesitaCopia: j['necesitaCopia'] == true,
        cursoresSubida: {
          for (final e in (j['cursoresSubida'] as Map? ?? const {}).entries) e.key as String: (e.value as num).toInt(),
        },
        vistas: {
          for (final t in (j['vistas'] as Map? ?? const {}).entries)
            t.key as String: {
              for (final f in (t.value as Map).entries)
                f.key as String: (valor: ((f.value as List)[0] as num).toInt(), huella: (f.value as List)[1] as String),
            },
        },
        sinAplicar: {
          for (final e in (j['sinAplicar'] as Map? ?? const {}).entries)
            e.key as String: [for (final f in e.value as List) Map<String, dynamic>.from(f as Map)],
        },
      );
    } catch (_) {
      return EstadoSyncNube();
    }
  }
}

/// Una fila lista para subir y lo que hace falta para confirmarla después.
class EntradaLote {
  const EntradaLote(this.tabla, this.fila, this.huella, this.valor, {required this.ultimaDeSuTabla});
  final String tabla;
  final Map<String, dynamic> fila;
  final String huella;
  final int valor;

  /// Es la última pendiente de su tabla en este recorrido: si el lote que la
  /// lleva se confirma, no queda nada más de esa tabla por subir.
  final bool ultimaDeSuTabla;
}

class LoteParaSubir {
  const LoteParaSubir({required this.id, required this.bytes, required this.sha256, required this.entradas});
  final String id;
  final List<int> bytes;
  final String sha256;
  final List<EntradaLote> entradas;
}

class PlanSubida {
  const PlanSubida(this.lotes, this.maxEscaneadoPorTabla);
  final List<LoteParaSubir> lotes;

  /// Mayor valor de cursor visto por tabla, incluidas las filas que no hacía
  /// falta subir (ya sincronizadas).
  final Map<String, int> maxEscaneadoPorTabla;
}

/// Tope de un lote: el servidor acepta 1 MB, se deja margen.
const maxBytesLote = 900 * 1024;
const maxFilasLote = 2000;

String _hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Arma el JSON de un lote, con las tablas en el orden en que hay que
/// aplicarlas (`tablasSincronizables`) y las filas en el orden de subida.
List<int> _plano(List<EntradaLote> entradas) {
  final porTabla = <String, List<Map<String, dynamic>>>{};
  for (final e in entradas) {
    (porTabla[e.tabla] ??= []).add(e.fila);
  }
  return utf8.encode(jsonEncode({
    'v': 1,
    'tablas': {
      for (final t in tablasSincronizables.keys)
        if (porTabla.containsKey(t)) t: porTabla[t],
    },
  }));
}

LoteParaSubir _armarLote(List<EntradaLote> entradas) {
  final plano = _plano(entradas);
  final id = 'l${_hex(plano).substring(0, 31)}';
  final comprimido = gzip.encode(plano);
  return LoteParaSubir(id: id, bytes: comprimido, sha256: _hex(comprimido), entradas: entradas);
}

/// Parte [entradas] en lotes que entren en [maxBytes]: si uno comprimido se
/// pasa, se divide a la mitad (nunca desordena: los lotes salen en el orden
/// en que hay que aplicarlos).
List<LoteParaSubir> _empacar(List<EntradaLote> entradas, {required int maxBytes}) {
  final lote = _armarLote(entradas);
  if (lote.bytes.length <= maxBytes || entradas.length == 1) return [lote];
  final mitad = entradas.length ~/ 2;
  return [
    ..._empacar(entradas.sublist(0, mitad), maxBytes: maxBytes),
    ..._empacar(entradas.sublist(mitad), maxBytes: maxBytes),
  ];
}

/// Qué subir ahora: de cada tabla, lo que cambió desde el cursor y no está ya
/// en el registro con la misma huella.
Future<PlanSubida> prepararSubidas(
  AppDatabase db,
  EstadoSyncNube estado, {
  int maxFilas = maxFilasLote,
  int maxBytes = maxBytesLote,
}) async {
  final entradas = <EntradaLote>[];
  final maxEscaneado = <String, int>{};
  for (final tabla in tablasSincronizables.keys) {
    final filas = await cambiosDesde(db, tabla: tabla, desde: estado.cursorDe(tabla));
    if (filas.isEmpty) continue;
    final vistas = estado.vistas[tabla] ?? const <String, VistaFila>{};
    final pendientes = [
      for (final f in filas)
        if (vistas[f['global_id']]?.huella != huellaSyncNube(tabla, f)) f,
    ];
    maxEscaneado[tabla] = cursorMaximo(tabla, filas);
    for (var i = 0; i < pendientes.length; i++) {
      final f = pendientes[i];
      entradas.add(EntradaLote(tabla, f, huellaSyncNube(tabla, f), valorCursorDe(tabla, f),
          ultimaDeSuTabla: i == pendientes.length - 1));
    }
  }
  final lotes = <LoteParaSubir>[];
  for (var i = 0; i < entradas.length; i += maxFilas) {
    final fin = i + maxFilas < entradas.length ? i + maxFilas : entradas.length;
    lotes.addAll(_empacar(entradas.sublist(i, fin), maxBytes: maxBytes));
  }
  return PlanSubida(lotes, maxEscaneado);
}

/// Los logs de solo-inserción tienen cursor por `id` local, que solo sube: si
/// no hay nada que subir de una tabla así, todo lo escaneado ya está
/// sincronizado y el cursor puede pasarlo (si no, lo recibido de otros
/// dispositivos se escanearía para siempre). En las tablas por
/// `actualizado_en` NO se hace: un valor alto que vino de un reloj adelantado
/// dejaría sin subir las ediciones propias siguientes.
void avanzarSinSubir(EstadoSyncNube estado, PlanSubida plan) {
  final conPendientes = {for (final l in plan.lotes) for (final e in l.entradas) e.tabla};
  for (final e in plan.maxEscaneadoPorTabla.entries) {
    if (conPendientes.contains(e.key) || tablasSincronizables[e.key]!) continue;
    if (e.value > estado.cursorDe(e.key)) estado.cursoresSubida[e.key] = e.value;
    estado._podar(e.key);
  }
}

/// El servidor recibió [lote]: pasa al registro y el cursor avanza.
void confirmarSubida(EstadoSyncNube estado, PlanSubida plan, LoteParaSubir lote) {
  final tablas = {for (final e in lote.entradas) e.tabla};
  for (final tabla in tablas) {
    final suyas = lote.entradas.where((e) => e.tabla == tabla).toList();
    var cursor = estado.cursorDe(tabla);
    for (final e in suyas) {
      if (e.valor > cursor) cursor = e.valor;
    }
    final terminada = suyas.any((e) => e.ultimaDeSuTabla);
    if (terminada && !tablasSincronizables[tabla]!) {
      final visto = plan.maxEscaneadoPorTabla[tabla] ?? 0;
      if (visto > cursor) cursor = visto;
    }
    estado.cursoresSubida[tabla] = cursor;
    for (final e in suyas) {
      estado._recordar(tabla, e.fila['global_id'] as String, e.valor, e.huella);
    }
    estado._podar(tabla);
  }
}

/// Un lote bajado del servidor, ya descomprimido y en orden.
class LoteBajado {
  const LoteBajado({required this.seq, required this.deviceId, required this.creadoEn, required this.bytes});
  final int seq;
  final String deviceId;
  final int creadoEn;
  final List<int> bytes;
}

/// Aplica [lotes] (en el orden que dio el servidor: el último pisa a los
/// anteriores) y deja en el registro cómo quedó cada fila, para que no se
/// suban de vuelta. Devuelve cuántas filas se aplicaron.
Future<int> aplicarLotesBajados(AppDatabase db, EstadoSyncNube estado, List<LoteBajado> lotes) async {
  var aplicadas = 0;
  for (final lote in lotes) {
    Map<String, dynamic> tablas;
    try {
      final j = jsonDecode(utf8.decode(gzip.decode(lote.bytes))) as Map<String, dynamic>;
      tablas = (j['tablas'] as Map).cast<String, dynamic>();
    } catch (_) {
      continue; // un lote ilegible no puede trabar a los siguientes
    }
    for (final tabla in tablasSincronizables.keys) {
      final nuevas = [for (final f in (tablas[tabla] as List? ?? const [])) Map<String, dynamic>.from(f as Map)];
      final pendientes = estado.sinAplicar[tabla] ?? const <Map<String, dynamic>>[];
      if (nuevas.isEmpty && pendientes.isEmpty) continue;
      // Si una fila vuelve a llegar, la nueva reemplaza a la que estaba esperando.
      final gidsNuevos = {for (final f in nuevas) f['global_id']};
      final aAplicar = [
        for (final f in pendientes)
          if (!gidsNuevos.contains(f['global_id'])) f,
        ...nuevas,
      ];
      final fallidas = await aplicarCambios(db, tabla: tabla, filas: aAplicar, ordenDeLlegada: true);
      if (fallidas.isEmpty) {
        estado.sinAplicar.remove(tabla);
      } else {
        estado.sinAplicar[tabla] = fallidas;
      }
      final fallidasIds = {for (final f in fallidas) f['global_id']};
      for (final f in aAplicar) {
        final gid = f['global_id'] as String?;
        if (gid == null || fallidasIds.contains(gid)) continue;
        aplicadas++;
        final local = await filaLocalPorGlobalId(db, tabla: tabla, globalId: gid);
        if (local != null) estado._recordar(tabla, gid, valorCursorDe(tabla, local), huellaSyncNube(tabla, local));
      }
    }
    estado.cursorBajada = lote.seq;
  }
  return aplicadas;
}

// Servidor de sync falso: cumple el contrato de `/api/sync` y de los avisos en vivo de `NodoSurPage`
// (`functions/api/sync.js`): lotes numerados por orden de llegada, idempotentes por `X-Lote-Id`, cada dispositivo
// recibe solo los de los otros, y un canal de avisos por dispositivo conectado. `token` identifica al dispositivo.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show WebSocketException;

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class LoteFalso {
  LoteFalso(this.seq, this.token, this.id, this.bytes);
  final int seq;
  final String token;
  final String id;
  final List<int> bytes;
}

/// El Worker, en memoria. `token` identifica al dispositivo (como el token real).
class ServidorSyncFalso {
  final lotes = <LoteFalso>[];
  var _seq = 0;
  bool caido = false;

  /// Simula un corte DESPUÉS de guardar: el lote queda, pero la respuesta nunca llega.
  bool perderRespuestaDelProximoPost = false;
  bool expirado = false;

  /// Avisos en vivo: un canal por dispositivo conectado. `sinAvisoEnVivo` imita un servidor sin el Durable Object.
  final canales = <String, StreamController<String>>{};
  bool sinAvisoEnVivo = false;
  int conexiones = 0;
  int consultas = 0; // GET /api/sync
  final consultasDe = <String, int>{};
  int subidas = 0; // POST /api/sync

  Future<Stream<dynamic>> abrir(Uri uri, Map<String, String> cabeceras) async {
    if (caido) throw const WebSocketException('sin red');
    if (sinAvisoEnVivo) throw const WebSocketException('was not upgraded to websocket, HTTP status code: 503');
    final token = cabeceras['Authorization']!.substring('Bearer '.length);
    conexiones++;
    final c = canales[token] = StreamController<String>();
    return c.stream;
  }

  /// Corta las conexiones de avisos (se reinició el servidor, se cayó la red).
  void cortarAvisos() {
    for (final c in canales.values) {
      c.close();
    }
    canales.clear();
  }

  MockClient get http_ => MockClient((r) async {
        if (caido) throw http.ClientException('sin red');
        final token = r.headers['Authorization']!.substring('Bearer '.length);
        if (r.method == 'POST') {
          subidas++;
          final id = r.headers['X-Lote-Id']!;
          final previo = lotes.where((l) => l.id == id).firstOrNull;
          final lote = previo ?? LoteFalso(++_seq, token, id, r.bodyBytes);
          if (previo == null) {
            lotes.add(lote);
            for (final e in canales.entries) {
              if (e.key != token) e.value.add('{"seq":${lote.seq}}');
            }
          }
          if (perderRespuestaDelProximoPost) {
            perderRespuestaDelProximoPost = false;
            throw http.ClientException('se cortó');
          }
          return http.Response(jsonEncode({'ok': true, 'seq': lote.seq, 'repetido': previo != null}), 200);
        }
        consultas++;
        consultasDe[token] = (consultasDe[token] ?? 0) + 1;
        if (expirado) return http.Response(jsonEncode({'expirado': true, 'purgadoHasta': 9}), 200);
        final desde = int.parse(r.url.queryParameters['desde']!);
        final nuevos = lotes.where((l) => l.seq > desde).toList();
        return http.Response(
          jsonEncode({
            'expirado': false,
            'lotes': [
              for (final l in nuevos.where((l) => l.token != token))
                {'seq': l.seq, 'deviceId': l.token, 'creadoEn': 1, 'datos': base64Encode(l.bytes)},
            ],
            'hasta': nuevos.isEmpty ? desde : nuevos.last.seq,
            'mas': false,
          }),
          200,
        );
      });
}


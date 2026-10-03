// Encontrar la PC del local en el wifi sin tipear su dirección (El dueño, 2026-10-03: "mejorar el emparejamiento"):
// el celular prueba `/ping` en el puerto de la PC en todas las direcciones de su misma red (las 254 de x.x.x.1 a
// x.x.x.254), de a muchas a la vez y con un tiempo corto. En un wifi de local tarda uno o dos segundos.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../servidor/servidor_companion.dart' show puertoServidorCompanion;

typedef ProbarPc = Future<bool> Function(String ip, int puerto);

/// Las direcciones a probar, a partir de las del propio celular: solo redes privadas (192.168.x, 10.x, 172.16-31.x),
/// sin la propia, y primero [preferida] (la última PC conocida) si es de esa red.
List<String> candidatasPc(List<String> propias, {String? preferida}) {
  final resultado = <String>[];
  if (preferida != null) resultado.add(preferida);
  for (final ip in propias) {
    final o = ip.split('.').map(int.tryParse).toList();
    if (o.length != 4 || o.any((x) => x == null)) continue;
    final privada = o[0] == 10 || (o[0] == 192 && o[1] == 168) || (o[0] == 172 && o[1]! >= 16 && o[1]! <= 31);
    if (!privada) continue;
    for (var i = 1; i <= 254; i++) {
      final candidata = '${o[0]}.${o[1]}.${o[2]}.$i';
      if (candidata != ip && !resultado.contains(candidata)) resultado.add(candidata);
    }
  }
  return resultado;
}

/// `/ping` de la PC: responde `app: la_plazoleta` (así no se confunde con otro aparato que tenga ese puerto abierto).
Future<bool> probarPcPorHttp(String ip, int puerto) async {
  try {
    final r = await http
        .get(Uri(scheme: 'http', host: ip, port: puerto, path: '/ping'))
        .timeout(const Duration(milliseconds: 900));
    if (r.statusCode != 200) return false;
    final j = jsonDecode(r.body);
    return j is Map && j['app'] == 'la_plazoleta';
  } catch (_) {
    return false;
  }
}

Future<List<String>> direccionesDelCelular() async {
  final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
  return [for (final i in interfaces) for (final d in i.addresses) d.address];
}

/// La dirección de la PC, o null si no hay ninguna en este wifi.
Future<String?> buscarPcEnElWifi({
  ProbarPc probar = probarPcPorHttp,
  Future<List<String>> Function() misDirecciones = direccionesDelCelular,
  String? preferida,
  int puerto = puertoServidorCompanion,
  int deAMuchas = 64,
}) async {
  final candidatas = candidatasPc(await misDirecciones(), preferida: preferida);
  for (var i = 0; i < candidatas.length; i += deAMuchas) {
    final tanda = candidatas.skip(i).take(deAMuchas).toList();
    final resultados = await Future.wait([for (final ip in tanda) probar(ip, puerto)]);
    final j = resultados.indexOf(true);
    if (j >= 0) return tanda[j];
  }
  return null;
}

// Corre solo los tests que pueden cambiar de resultado por lo que se tocó, en vez de la suite entera (~2.900 tests,
// 5 a 12 minutos). Arma el grafo de `import`/`export`/`part` de lib/ y test/ y, desde cada archivo cambiado, sube por
// quienes lo usan (directa o indirectamente) hasta llegar a los `*_test.dart`. Es exacto, no adivina por nombre: tocar
// `dinero.dart` corre casi todo porque casi todo lo usa, y tocar una pantalla corre solo sus tests.
//
//   dart run tool/tests_afectados.dart                      # lista los tests afectados contra origin/main
//   dart run tool/tests_afectados.dart --correr             # y los corre (sin el benchmark)
//   dart run tool/tests_afectados.dart --base HEAD~1 --correr -- --reporter failures-only
//
// Cambios que no se pueden seguir por imports (pubspec, configuración del análisis o de los tests) corren la suite
// entera. Un fixture o asset corre los tests que lo nombran; si ninguno lo nombra, también la suite entera.
import 'dart:io';

const _todoSiCambia = {'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'dart_test.yaml'};

Future<void> main(List<String> args) async {
  final separador = args.indexOf('--');
  final propios = separador == -1 ? args : args.sublist(0, separador);
  final extra = separador == -1 ? <String>[] : args.sublist(separador + 1);
  final iBase = propios.indexOf('--base');
  final base = iBase == -1 ? 'origin/main' : propios[iBase + 1];
  final correr = propios.contains('--correr');

  final cambiados = await _cambiados(base);
  final resultado = _afectados(cambiados);

  if (resultado == null) {
    stdout.writeln('Cambió algo que afecta a todo: se corre la suite entera.');
    if (correr) exit(await _flutterTest(const [], extra));
    stdout.writeln('TODOS');
    return;
  }
  if (resultado.isEmpty) {
    stdout.writeln('Ningún test afectado (${cambiados.length} archivos cambiados).');
    return;
  }
  stdout.writeln('${resultado.length} tests afectados por ${cambiados.length} archivos cambiados.');
  if (!correr) {
    resultado.forEach(stdout.writeln);
    return;
  }
  exit(await _flutterTest(resultado, extra));
}

Future<Set<String>> _cambiados(String base) async {
  Future<List<String>> git(List<String> a) async {
    final r = await Process.run('git', a);
    if (r.exitCode != 0) {
      stderr.writeln('git ${a.join(' ')}: ${r.stderr}');
      exit(2);
    }
    return (r.stdout as String).split('\n').where((l) => l.trim().isNotEmpty).toList();
  }

  return {
    ...await git(['diff', '--name-only', '$base...HEAD']),
    ...await git(['diff', '--name-only', 'HEAD']),
    ...await git(['ls-files', '--others', '--exclude-standard']),
  };
}

/// null = correr todo. Si no, los tests afectados, ordenados.
List<String>? _afectados(Set<String> cambiados) {
  if (cambiados.any(_todoSiCambia.contains)) return null;

  final dart = [
    for (final dir in ['lib', 'test'])
      if (Directory(dir).existsSync())
        ...Directory(dir)
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => f.path.replaceAll(r'\', '/'))
            .where((p) => p.endsWith('.dart')),
  ];
  final paquete = RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1)!;

  // Quién usa a quién: usadoPor[a] = archivos que importan, exportan o tienen como `part` a `a`.
  final usadoPor = <String, Set<String>>{};
  final directiva = RegExp(r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''', multiLine: true);
  final condicional = RegExp(r'''\bif\s*\([^)]*\)\s*['"]([^'"]+\.dart)['"]''');
  final contenido = <String, String>{};
  for (final archivo in dart) {
    final texto = File(archivo).readAsStringSync();
    contenido[archivo] = texto;
    // Los imports condicionales (`import 'a.dart' if (dart.library.io) 'b.dart'`) también dependen de `b.dart`.
    for (final m in [...directiva.allMatches(texto), ...condicional.allMatches(texto)]) {
      final destino = _resolver(m.group(1)!, archivo, paquete);
      if (destino != null) usadoPor.putIfAbsent(destino, () => {}).add(archivo);
    }
  }
  // `part of` va al revés: cambiar un `.g.dart` afecta a su biblioteca.
  for (final archivo in dart) {
    final m = RegExp(r'''^\s*part\s+of\s+['"]([^'"]+)['"]''', multiLine: true).firstMatch(contenido[archivo]!);
    if (m != null) {
      final lib = _resolver(m.group(1)!, archivo, paquete);
      if (lib != null) usadoPor.putIfAbsent(archivo, () => {}).add(lib);
    }
  }

  final pendientes = <String>[];
  for (final c in cambiados) {
    if (c.endsWith('.dart') && (c.startsWith('lib/') || c.startsWith('test/'))) {
      pendientes.add(c);
    } else if (c.startsWith('test/fixtures/') || c.startsWith('assets/') || c.startsWith('fonts/')) {
      // Se cargan por ruta, no por import: van los tests (y helpers) que los nombran.
      final nombre = c.split('/').last;
      final quienes = dart.where((a) => contenido[a]!.contains(nombre)).toList();
      if (quienes.isEmpty) return null;
      pendientes.addAll(quienes);
    }
  }

  final vistos = <String>{};
  while (pendientes.isNotEmpty) {
    final a = pendientes.removeLast();
    if (!vistos.add(a)) continue;
    pendientes.addAll(usadoPor[a] ?? const {});
  }
  return vistos.where((a) => a.startsWith('test/') && a.endsWith('_test.dart') && File(a).existsSync()).toList()..sort();
}

String? _resolver(String uri, String desde, String paquete) {
  if (uri.startsWith('package:$paquete/')) return 'lib/${uri.substring('package:$paquete/'.length)}';
  if (uri.startsWith('package:') || uri.startsWith('dart:')) return null;
  final partes = [...desde.split('/')..removeLast(), ...uri.split('/')];
  final limpio = <String>[];
  for (final p in partes) {
    if (p == '..') {
      if (limpio.isNotEmpty) limpio.removeLast();
    } else if (p != '.') {
      limpio.add(p);
    }
  }
  return limpio.join('/');
}

Future<int> _flutterTest(List<String> tests, List<String> extra) async {
  final args = ['test', '--exclude-tags', 'bench', ...extra, ...tests];
  final p = await Process.start(Platform.isWindows ? 'flutter.bat' : 'flutter', args, mode: ProcessStartMode.inheritStdio);
  return p.exitCode;
}

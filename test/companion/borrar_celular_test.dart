import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/borrar_celular.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';

class _Carpetas extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  _Carpetas(this.documentos, this.soporte);
  final String documentos;
  final String soporte;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentos;

  @override
  Future<String?> getApplicationSupportPath() async => soporte;
}

/// "Cerrar sesión y borrar este celular" (El dueño, 2026-10-10): queda como recién instalado.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('borra la base, la cuenta y las preferencias (con la base abierta)', () async {
    final raiz = await Directory.systemTemp.createTemp('borrar_celular_');
    addTearDown(() => raiz.delete(recursive: true));
    final documentos = await Directory('${raiz.path}/documentos').create();
    final soporte = await Directory('${raiz.path}/soporte').create();
    PathProviderPlatform.instance = _Carpetas(documentos.path, soporte.path);

    final base = File('${documentos.path}/la_plazoleta.sqlite')..writeAsStringSync('x');
    final wal = File('${documentos.path}/la_plazoleta.sqlite-wal')..writeAsStringSync('x');
    final otro = File('${documentos.path}/ticket.pdf')..writeAsStringSync('x');
    final cuenta = File('${soporte.path}/cuenta_nube.json')..writeAsStringSync('{"token":"t"}');
    await Directory('${soporte.path}/logs').create();
    SharedPreferences.setMockInitialValues({'usuario_id': 3, 'modo_uso': 'celular'});
    final db = baseDeTest();
    usarBaseLocalDeTest(db);

    await borrarTodoDelCelular();

    expect(base.existsSync(), isFalse);
    expect(wal.existsSync(), isFalse);
    expect(otro.existsSync(), isTrue, reason: 'solo la base, no cualquier archivo de documentos');
    expect(cuenta.existsSync(), isFalse);
    expect(soporte.listSync(), isEmpty);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });
}

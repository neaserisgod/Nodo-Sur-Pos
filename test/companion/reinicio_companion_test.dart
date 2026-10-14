// Cambiar de negocio sin cerrar la app (El dueño, 2026-10-14): todo lo de la cuenta anterior se frena y se olvida, y la base no
// se puede abrir mientras se mueven los archivos.

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/companion/app_ns.dart';
import 'package:la_plazoleta/companion/base_local.dart';
import 'package:la_plazoleta/companion/borrar_celular.dart';
import 'package:la_plazoleta/companion/bot_celular.dart';
import 'package:la_plazoleta/companion/configurar/asistente_negocio.dart' show PasoNegocio;
import 'package:la_plazoleta/companion/configurar/negocio_nuevo.dart';
import 'package:la_plazoleta/companion/reinicio_companion.dart';
import 'package:la_plazoleta/domain/marca.dart';
import 'package:la_plazoleta/servicios/marca_actual.dart';
import 'package:la_plazoleta/servicios/turnos_bot_nube.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/base_para_tests.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    raizCompanion.value = const EstadoRaizCompanion();
    usarBaseLocalDeTest(baseDeTest());
  });

  test('frenar todo deja la base cerrada y bloqueada: lo que llega tarde falla en vez de abrir una base nueva', () async {
    await frenarLoQueEscribe();
    expect(baseLocalCompanion, throwsA(isA<BaseLocalBloqueada>()));
    desbloquearBaseLocal();
    usarBaseLocalDeTest(baseDeTest());
    expect(baseLocalCompanion(), isNotNull);
  });

  test('olvida lo que la cuenta anterior dejó en memoria', () {
    marcaActual.value = const MarcaNegocio(nombreComercio: 'Almacén de Ana');
    sinConexionGlobalNs.value = true;
    pasosPendientesNegocio.value = {PasoNegocio.values.first};
    turnosBotSinCargar.value = const ['turno'];
    olvidarLoDeLaCuenta();
    expect(marcaActual.value.nombreComercio, const MarcaNegocio().nombreComercio);
    expect(sinConexionGlobalNs.value, isFalse);
    expect(pasosPendientesNegocio.value, isEmpty);
    expect(turnosBotSinCargar.value, isEmpty);
    expect(estadoBotCelular.value, isNull);
  });

  test('vuelve a empezar sin cerrar: durante el cambio no hay app ni base; después, otra app y la base abierta', () async {
    bool? cambiandoAlTraer;
    Object? baseAlTraer;
    await volverAEmpezar(
      esperarCuadro: () async {},
      terminar: () async {
        cambiandoAlTraer = raizCompanion.value.cambiando;
        try {
          baseLocalCompanion();
        } catch (e) {
          baseAlTraer = e;
        }
        return null;
      },
    );
    expect(cambiandoAlTraer, isTrue);
    expect(baseAlTraer, isA<BaseLocalBloqueada>(), reason: 'se trae con la base cerrada');
    expect(raizCompanion.value.generacion, 1);
    expect(raizCompanion.value.cambiando, isFalse);
    expect(raizCompanion.value.cambioTrabado, isNull);
    usarBaseLocalDeTest(baseDeTest());
    expect(baseLocalCompanion(), isNotNull);
  });

  test('si no se puede traer el negocio, muestra el cambio trabado y la base sigue cerrada', () async {
    await volverAEmpezar(esperarCuadro: () async {}, terminar: () async => StateError('disco lleno'));
    expect(raizCompanion.value.generacion, 1);
    expect(raizCompanion.value.cambioTrabado, isA<StateError>());
    expect(baseLocalCompanion, throwsA(isA<BaseLocalBloqueada>()));
  });
}

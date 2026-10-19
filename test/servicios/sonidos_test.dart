// Los sonidos de la app (`servicios/sonidos.dart`): suenan solo cargados y prendidos, un mismo sonido no se repite en ráfaga, y
// apagarlos queda guardado.

import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/servicios/avisos_bot.dart';
import 'package:la_plazoleta/servicios/sonidos.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReproductorDePrueba implements ReproductorSonidos {
  final preparados = <Sonido>[];
  final tocados = <Sonido>[];
  bool falla = false;

  @override
  Future<void> preparar(Sonido s) async {
    if (falla) throw Exception('sin audio');
    preparados.add(s);
  }

  @override
  Future<void> tocar(Sonido s) async => tocados.add(s);
}

void main() {
  late DateTime ahora;
  late Sonidos s;
  late ReproductorDePrueba r;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ahora = DateTime(2026, 10, 18, 12);
    s = Sonidos(ahora: () => ahora);
    r = ReproductorDePrueba();
  });

  test('antes de cargarlos no suena nada (un test que abre el cobro no toca el audio)', () {
    s.sonar(Sonido.pago);
    expect(r.tocados, isEmpty);
  });

  test('cargados, quedan los dos en memoria y suenan', () async {
    await s.cargar(reproductor: r);
    expect(r.preparados, Sonido.values);
    s.sonar(Sonido.pago);
    s.sonar(Sonido.aviso);
    await Future<void>.delayed(Duration.zero);
    expect(r.tocados, [Sonido.pago, Sonido.aviso]);
  });

  test('el mismo sonido en ráfaga suena una vez; pasado el respiro, otra vez', () async {
    await s.cargar(reproductor: r);
    s.sonar(Sonido.aviso);
    ahora = ahora.add(const Duration(milliseconds: 400));
    s.sonar(Sonido.aviso);
    await Future<void>.delayed(Duration.zero);
    expect(r.tocados, [Sonido.aviso]);
    ahora = ahora.add(Sonidos.separacionMinima);
    s.sonar(Sonido.aviso);
    await Future<void>.delayed(Duration.zero);
    expect(r.tocados, [Sonido.aviso, Sonido.aviso]);
  });

  test('apagados no suenan, y queda guardado para la próxima vez', () async {
    await s.cargar(reproductor: r);
    await s.guardarActivos(false);
    s.sonar(Sonido.pago);
    await Future<void>.delayed(Duration.zero);
    expect(r.tocados, isEmpty);
    final otra = Sonidos(ahora: () => ahora);
    await otra.cargar(reproductor: r);
    expect(otra.activos.value, isFalse);
  });

  test('al prenderlos suena el de pago, para escuchar cómo es', () async {
    SharedPreferences.setMockInitialValues({'sonidos.activos': false});
    await s.cargar(reproductor: r);
    await s.guardarActivos(true);
    await Future<void>.delayed(Duration.zero);
    expect(r.tocados, [Sonido.pago]);
  });

  test('un equipo sin audio sigue andando, mudo', () async {
    r.falla = true;
    await s.cargar(reproductor: r);
    expect(() => s.sonar(Sonido.pago), returnsNormally);
    expect(r.tocados, isEmpty);
  });

  test('un pedido nuevo del bot suena a aviso en el equipo que recibe el aviso en vivo', () async {
    await sonidos.cargar(reproductor: r);
    avisarPedidoBot(7);
    await Future<void>.delayed(Duration.zero);
    expect(r.tocados, [Sonido.aviso]);
  });
}

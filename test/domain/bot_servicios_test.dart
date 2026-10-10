// La configuración del bot de un negocio de servicios sale de los datos del negocio (El dueño, 2026-10-10: "no tiene que haber una
// sección específica para bot"): servicios, horario de atención y seña, en el formato del `config.json` del bot.
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/bot_whatsapp.dart';
import 'package:la_plazoleta/domain/turnos.dart';

void main() {
  const semi = ServicioParaBot(gid: 'g-semi', nombre: 'Semipermanente', duracionMinutos: 60, precioCentavos: 1800000, senaCentavos: 540000);
  const retiro = ServicioParaBot(gid: 'g-retiro', nombre: 'Retiro', duracionMinutos: 30, precioCentavos: 600050, senaCentavos: 0);
  final anterior = <String, dynamic>{
    'numero_actual': '5492944111111',
    'numero_duena': '5492944222222',
    'pausa_minutos': 60,
    'servicios': [
      {'id': 4, 'nombre': 'Retiro viejo', 'duracion_min': 30, 'precio': 5000, 'sena': 0, 'catalogo_id': 'g-retiro'},
    ],
    'senas': {'vencimiento_horas': 3},
  };

  Map<String, dynamic> armar({String alias = 'caro.unas', String titular = 'Carolina Pérez', List<ServicioParaBot> servicios = const [semi, retiro], bool conLink = false}) =>
      configBotConServicios(anterior, servicios: servicios, horario: HorarioAtencion.porDefecto, pasoMinutos: 15, aliasSena: alias, titularSena: titular, cobroConLink: conLink);

  test('los servicios en pesos enteros, y cada uno conserva su número de menú', () {
    final c = armar();
    final lista = (c['servicios'] as List).cast<Map<String, dynamic>>();
    final r = lista.firstWhere((s) => s['catalogo_id'] == 'g-retiro');
    expect(r['id'], 4, reason: 'ya tenía el 4');
    expect(r['nombre'], 'Retiro');
    expect(r['precio'], 6001, reason: 'hacia arriba al peso');
    final s = lista.firstWhere((s) => s['catalogo_id'] == 'g-semi');
    expect(s['id'], 5, reason: 'el nuevo toma el siguiente');
    expect(s['precio'], 18000);
    expect(s['sena'], 5400);
    expect(s['duracion_min'], 60);
  });

  test('el horario, el paso y la seña del negocio; lo demás (números, pausa) queda como estaba', () {
    final c = armar();
    expect(c['horarios'], HorarioAtencion.porDefecto.toJson());
    expect((c['turnos'] as Map)['intervalo_slot_min'], 15);
    expect(c['senas'], {'vencimiento_horas': 3, 'habilitadas': true, 'alias_mp': 'caro.unas', 'titular': 'Carolina Pérez', 'cobro': 'alias'});
    expect(c['numero_actual'], '5492944111111');
    expect(c['pausa_minutos'], 60);
  });

  test('sin alias o titular no se pide seña (el bot no tendría a dónde mandar a transferir)', () {
    final c = armar(alias: '');
    expect((c['senas'] as Map)['habilitadas'], isFalse);
    expect((c['servicios'] as List).every((s) => (s as Map)['sena'] == 0), isTrue);
  });

  test('sin servicios no cambia nada (el bot necesita al menos uno)', () {
    expect(armar(servicios: const []), same(anterior));
  });

  test('Nodo Sur Servicios: la seña va con el link de Mercado Pago y media hora para pagar, aunque no haya alias', () {
    final c = armar(alias: '', titular: '', conLink: true);
    final senas = c['senas'] as Map;
    expect(senas['cobro'], 'mp');
    expect(senas['habilitadas'], isTrue);
    expect(senas['vencimiento_horas'], 0.5);
    expect((c['servicios'] as List).first['sena'], 5400);
    final sinLink = armar();
    expect((sinLink['senas'] as Map)['cobro'], 'alias');
    expect((sinLink['senas'] as Map)['vencimiento_horas'], 3);
  });
}

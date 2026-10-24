// La comanda de un pedido de gastronomía en la terminal Point (El dueño, 2026-10-24: "cuando un pedido se confirma como tal,
// debe imprimir la comanda"): sale al quedar "por hacer", una vez por equipo, y lleva lo que la cocina necesita.
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/comanda.dart';
import 'package:la_plazoleta/domain/pedido_gastronomico.dart';

void main() {
  final ahora = DateTime(2026, 10, 24, 21, 0);

  group('qué comandas salen', () {
    PedidoParaComanda p(String gid, EstadoPedido estado, {Duration hace = Duration.zero}) =>
        (gid: gid, estado: estado, momento: ahora.subtract(hace));

    test('solo lo confirmado (por hacer): ni lo que espera al local o el pago, ni lo que ya salió de la cocina', () {
      final salen = comandasPorImprimir([
        for (final e in EstadoPedido.values) p(e.clave, e),
      ], impresas: {}, ahora: ahora);
      expect(salen, [EstadoPedido.porHacer.clave]);
    });

    test('lo ya impreso en este equipo no se repite', () {
      expect(comandasPorImprimir([p('a', EstadoPedido.porHacer), p('b', EstadoPedido.porHacer)], impresas: {'a'}, ahora: ahora), ['b']);
    });

    test('lo confirmado con la comandera apagada sale al volver, dentro de un turno; lo más viejo no', () {
      final salen = comandasPorImprimir([
        p('reciente', EstadoPedido.porHacer, hace: const Duration(hours: 11)),
        p('viejo', EstadoPedido.porHacer, hace: const Duration(hours: 13)),
      ], impresas: {}, ahora: ahora);
      expect(salen, ['reciente']);
    });

    test('lo impreso se olvida a los tres días', () {
      final impresas = {
        'ayer': ahora.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
        'semana': ahora.subtract(const Duration(days: 7)).millisecondsSinceEpoch,
      };
      expect(podarComandas(impresas, ahora: ahora).keys, ['ayer']);
    });
  });

  group('el texto', () {
    const milanesa = LineaPedido(gid: 'm', nombre: 'Milanesa napolitana', cantidad: 2, precioCentavos: 900000);
    const papas = LineaPedido(gid: 'p', nombre: 'Papas', gramos: 500, precioCentavos: 600000);

    DatosComanda datos({
      FormaEntrega forma = FormaEntrega.retiro,
      bool pagado = false,
      bool programado = false,
      String? nota,
      String? direccion,
      String? zona,
    }) => DatosComanda(
          numero: 'K7-P0042',
          canal: CanalPedido.whatsapp,
          forma: forma,
          nombreCliente: 'Juan',
          telefono: '2944123456',
          lineas: const [milanesa, papas],
          fecha: DateTime(2026, 10, 24, 20, 5),
          horaEstimada: DateTime(2026, 10, 24, 20, 45),
          programado: programado,
          pagado: pagado,
          nota: nota,
          direccion: direccion,
          zona: zona,
          totalCentavos: 2100000,
        );

    test('número, retiro, hora, lo pedido (por unidad y por peso) y lo que falta cobrar', () {
      final t = contenidoComandaPosnetMp(datos(), encabezadoNegocio: 'Groove\nMitre 123');
      expect(t, contains('{s}Groove{/s}'));
      expect(t, isNot(contains('Mitre')));
      expect(t, contains('{w}COMANDA K7-P0042{/w}'));
      expect(t, contains('RETIRA EN EL LOCAL'));
      expect(t, contains('WhatsApp · entró 24/10 20:05'));
      expect(t, contains('Para las 20:45'));
      expect(t, contains('{w}2 x Milanesa napolitana{/w}'));
      expect(t, contains('{w}500 g Papas{/w}'));
      expect(t, contains(r'A COBRAR $21.000'));
      expect(t, isNot(contains(r'$9.000')), reason: 'la cocina no necesita los precios');
    });

    test('envío con dirección y zona; pagado no pide cobrar', () {
      final t = contenidoComandaPosnetMp(datos(forma: FormaEntrega.cadetePropio, pagado: true, direccion: 'Moreno 50', zona: 'Centro'));
      expect(t, contains('ENVIO'));
      expect(t, contains('Moreno 50 (Centro)'));
      expect(t, contains('PAGADO'));
      expect(t, isNot(contains('A COBRAR')));
    });

    test('programado: el día y la hora bien a la vista', () {
      expect(contenidoComandaPosnetMp(datos(programado: true)), contains('{w}PROGRAMADO 24/10 20:45{/w}'));
    });

    test('lo que escribió una persona no rompe los tags de la terminal', () {
      final t = contenidoComandaPosnetMp(datos(nota: 'sin sal {b}\nbien cocida'));
      expect(t, contains('{b}NOTA:{/b} sin sal b bien cocida{br}'));
    });

    test('el mismo pedido da siempre el mismo texto (el reintento es el mismo para Mercado Pago)', () {
      expect(contenidoComandaPosnetMp(datos()), contenidoComandaPosnetMp(datos()));
    });
  });
}

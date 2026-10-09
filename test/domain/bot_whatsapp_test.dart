// Bot de WhatsApp (`domain/bot_whatsapp.dart`, plan en `docs/PLAN-BOT.md`): el catálogo que se le publica, los pedidos que toma,
// el estado y la configuración que se le carga desde la app.
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/bot_whatsapp.dart';

ProductoParaBot _p(String nombre, {String? gid = 'g', bool activo = true, bool pesable = false, bool promo = false, int? precio = 1000, int? porKilo, int stock = 3, int? gramos}) =>
    ProductoParaBot(
      globalId: gid,
      nombre: nombre,
      activo: activo,
      esPesable: pesable,
      esPromo: promo,
      precioCentavos: precio,
      precioPorKiloCentavos: porKilo,
      stock: stock,
      stockGramos: gramos,
    );

void main() {
  group('catálogo para el bot', () {
    test('lo justo: gid, nombre, precio y si hay; nada de costos; ordenado por nombre', () {
      final c = catalogoParaBot([_p('Yerba', gid: 'g-y', precio: 520000, stock: 2), _p('Coca', gid: 'g-c', precio: 350000, stock: 0)]);
      expect(c.map((x) => x.toJson()).toList(), [
        {'gid': 'g-c', 'nombre': 'Coca', 'precioCentavos': 350000, 'hay': false},
        {'gid': 'g-y', 'nombre': 'Yerba', 'precioCentavos': 520000, 'hay': true},
      ]);
    });

    test('un pesable va con el precio por kilo y lo dice; "hay" según los gramos', () {
      final c = catalogoParaBot([_p('Queso barra', pesable: true, precio: null, porKilo: 1200000, gramos: 800), _p('Salame', gid: 'g2', pesable: true, porKilo: 900000, gramos: 0)]);
      expect(c.first.nombre, 'Queso barra (por kg)');
      expect(c.first.precioCentavos, 1200000);
      expect(c.first.hay, isTrue);
      expect(c.last.hay, isFalse);
    });

    test('quedan afuera: inactivos, promos, sin global_id, sin precio o sin nombre', () {
      expect(
        catalogoParaBot([
          _p('Viejo', activo: false),
          _p('Combo', promo: true),
          _p('Sin sync', gid: null),
          _p('Sin precio', precio: null),
          _p('Gratis', precio: 0),
          _p('   '),
          _p('Pesable sin precio', pesable: true, porKilo: null, gramos: 100),
        ]),
        isEmpty,
      );
    });
  });

  group('pedidos', () {
    final json = {
      'id': 7,
      'pedidoId': 'wa-abc',
      'estado': 'por_confirmar',
      'cliente': {'nombre': 'Sofi', 'telefono': '5492944555555'},
      'items': [
        {'gid': 'g-y', 'nombre': 'Yerba', 'cantidad': 2, 'precioCentavos': 520000},
        {'nombre': 'Algo sin gid', 'cantidad': 1},
      ],
      'nota': 'Paso a las 19',
      'creado': 1700000000000,
      'actualizado': 1700000000123,
    };

    test('se lee lo que manda el sitio', () {
      final p = pedidoBotDesdeJson(json)!;
      expect(p.id, 7);
      expect(p.estado, EstadoPedidoBot.porConfirmar);
      expect(p.clienteNombre, 'Sofi');
      expect(p.items.first.gid, 'g-y');
      expect(p.items.last.gid, isNull);
      expect(p.totalOrientativoCentavos, 1040000);
      expect(p.actualizado, 1700000000123);
      expect(nombreEncargueDePedido(p), 'Sofi (WhatsApp)');
    });

    test('lo que no tiene la forma esperada se descarta en vez de romper', () {
      expect(pedidoBotDesdeJson({...json, 'estado': 'otro'}), isNull);
      expect(pedidoBotDesdeJson({...json, 'cliente': 'Sofi'}), isNull);
      expect(pedidoBotDesdeJson({...json, 'items': [{'nombre': 'x'}]}), isNull);
    });
  });

  group('aceptar un pedido: del catálogo del bot a lo que se aparta', () {
    ProductoDelPedido prod(int id, String gid, String nombre, {bool pesable = false, bool activo = true, int stock = 10, int? gramos}) =>
        ProductoDelPedido(id: id, globalId: gid, nombre: nombre, esPesable: pesable, activo: activo, stock: stock, stockGramos: gramos);
    PedidoBot pedido(List<ItemPedidoBot> items) => PedidoBot(
      id: 1,
      estado: EstadoPedidoBot.porConfirmar,
      clienteNombre: 'Sofi',
      clienteTelefono: '5492944555555',
      items: items,
      creado: DateTime(2026, 10, 9),
      actualizado: 1,
    );

    test('cada producto vuelve por su global_id, con la cantidad pedida', () {
      final r = apartadosDePedido(
        pedido(const [ItemPedidoBot(gid: 'g-y', nombre: 'Yerba', cantidad: 2), ItemPedidoBot(gid: 'g-c', nombre: 'Coca', cantidad: 1)]),
        [prod(5, 'g-y', 'Yerba'), prod(9, 'g-c', 'Coca')],
      );
      expect(r.faltan, isEmpty);
      expect(r.lineas, [(productoId: 5, cantidad: 2, gramos: null), (productoId: 9, cantidad: 1, gramos: null)]);
    });

    test('un pesable va por kilo (el bot lo ofrece "por kg"): 2 son 2000 g', () {
      final r = apartadosDePedido(
        pedido(const [ItemPedidoBot(gid: 'g-q', nombre: 'Queso (por kg)', cantidad: 2)]),
        [prod(3, 'g-q', 'Queso', pesable: true, gramos: 2500)],
      );
      expect(r.faltan, isEmpty);
      expect(r.lineas, [(productoId: 3, cantidad: null, gramos: 2000)]);
    });

    test('sin stock no se aparta nada y dice qué falta (Regla 8)', () {
      final r = apartadosDePedido(
        pedido(const [
          ItemPedidoBot(gid: 'g-y', nombre: 'Yerba', cantidad: 3),
          ItemPedidoBot(gid: 'g-c', nombre: 'Coca', cantidad: 1),
          ItemPedidoBot(gid: 'g-q', nombre: 'Queso (por kg)', cantidad: 1),
        ]),
        [prod(5, 'g-y', 'Yerba', stock: 1), prod(9, 'g-c', 'Coca'), prod(3, 'g-q', 'Queso', pesable: true, gramos: 400)],
      );
      expect(r.lineas, isEmpty);
      expect(r.faltan, ['Yerba: piden 3, quedan 1', 'Queso: piden 1 kg, quedan 400 g']);
    });

    test('stock en cero o negativo cuenta como que no hay', () {
      final r = apartadosDePedido(pedido(const [ItemPedidoBot(gid: 'g-y', nombre: 'Yerba', cantidad: 1)]), [prod(5, 'g-y', 'Yerba', stock: -2)]);
      expect(r.faltan, ['Yerba: piden 1, no queda']);
    });

    test('lo que ya no está (borrado, dado de baja o sin global_id) se nombra como lo pidió el bot', () {
      final r = apartadosDePedido(
        pedido(const [
          ItemPedidoBot(gid: 'g-x', nombre: 'Galletitas', cantidad: 1),
          ItemPedidoBot(nombre: 'Sin gid', cantidad: 1),
          ItemPedidoBot(gid: 'g-b', nombre: 'De baja', cantidad: 1),
        ]),
        [prod(2, 'g-b', 'De baja', activo: false)],
      );
      expect(r.lineas, isEmpty);
      expect(r.faltan, ['Galletitas: ya no está en el catálogo', 'Sin gid: ya no está en el catálogo', 'De baja: ya no está en el catálogo']);
    });

    test('el mismo producto dos veces se junta en una línea y se controla el total', () {
      final r = apartadosDePedido(
        pedido(const [ItemPedidoBot(gid: 'g-y', nombre: 'Yerba', cantidad: 2), ItemPedidoBot(gid: 'g-y', nombre: 'Yerba', cantidad: 2)]),
        [prod(5, 'g-y', 'Yerba', stock: 3)],
      );
      expect(r.lineas, isEmpty);
      expect(r.faltan, ['Yerba: piden 4, quedan 3']);
    });
  });

  group('estado del bot', () {
    test('sin el plan, no hay bot', () {
      expect(estadoBotDesdeJson({'tieneBot': false}).tieneBot, isFalse);
    });

    test('anda si dio señales en las últimas dos horas; si no, sin señal; sin bots vinculados, sin bot', () {
      final ahora = DateTime(2026, 10, 9, 12);
      final s = (ahora.subtract(const Duration(minutes: 30)).millisecondsSinceEpoch ~/ 1000);
      final e = estadoBotDesdeJson({'tieneBot': true, 'puedeConfigurar': true, 'version': 2, 'bots': [{'nombre': 'Bot', 'ultimaSenal': s}]});
      expect(e.puedeConfigurar, isTrue);
      expect(e.version, 2);
      expect(saludDelBot(e, ahora), SaludBot.anda);
      expect(saludDelBot(e, ahora.add(const Duration(hours: 3))), SaludBot.sinSenal);
      expect(saludDelBot(estadoBotDesdeJson({'tieneBot': true, 'bots': []}), ahora), SaludBot.sinBot);
    });
  });

  group('configuración', () {
    test('los números como los escribe cualquiera pasan al formato de WhatsApp (la misma regla que el bot)', () {
      for (final n in ['2944 111111', '02944-111111', '+54 9 2944 111111', '542944111111', '5492944111111']) {
        expect(numeroWhatsApp(n), '5492944111111', reason: n);
      }
      expect(numeroWhatsApp('111111'), isNull);
      expect(numeroWhatsApp(''), isNull);
    });

    final buena = ConfigBotEditable.porDefecto.copiar(numeroBot: '2944 111111', numeroAvisos: '2944 222222', direccion: 'Mitre 150');

    test('una configuración completa se puede guardar', () {
      expect(problemasConfigBot(buena, nombreNegocio: 'La Plazoleta', rubro: 'almacen'), isEmpty);
    });

    test('lo que el bot rechazaría no se deja guardar', () {
      expect(problemasConfigBot(buena, nombreNegocio: 'La Plazoleta', rubro: ''), contains(contains('rubro')));
      expect(problemasConfigBot(buena.copiar(numeroAvisos: '2944 111111'), nombreNegocio: 'X', rubro: 'almacen'), contains(contains('otro que el del bot')));
      expect(problemasConfigBot(buena.copiar(numeroBot: '123'), nombreNegocio: 'X', rubro: 'almacen'), contains(contains('número del bot')));
      final alReves = {...buena.horarios, 'lunes': (desde: '20:00', hasta: '09:00')};
      expect(problemasConfigBot(buena.copiar(horarios: alReves), nombreNegocio: 'X', rubro: 'almacen'), contains(contains('cierra antes de abrir')));
      final cerrado = {for (final d in diasBot) d: null as FranjaBot?};
      expect(problemasConfigBot(buena.copiar(horarios: cerrado), nombreNegocio: 'X', rubro: 'almacen'), contains(contains('al menos un día')));
      expect(problemasConfigBot(buena.copiar(pausaMinutos: 1), nombreNegocio: 'X', rubro: 'almacen'), contains(contains('pausa')));
    });

    test('lo que se guarda tiene la forma del config.json del bot y conserva lo que la app no edita', () {
      final anterior = {
        'negocio': {'nombre': 'Viejo', 'rubro': 'kiosco', 'ubicacion_maps': 'https://maps'},
        'textos': {'quien_atiende': 'Juli'},
        'numero_soporte': '5492944999999',
      };
      final g = configBotParaGuardar(buena, nombreNegocio: ' La Plazoleta ', rubro: 'almacen', anterior: anterior);
      expect(g['negocio'], {'nombre': 'La Plazoleta', 'rubro': 'almacen', 'direccion': 'Mitre 150', 'ubicacion_maps': 'https://maps'});
      expect(g['numero_actual'], '5492944111111');
      expect(g['numero_duena'], '5492944222222');
      expect(g['numero_soporte'], '5492944999999', reason: 'lo que ya tenía se conserva');
      expect(g['textos'], {'quien_atiende': 'Juli'});
      expect((g['horarios'] as Map)['domingo'], isNull);
      expect((g['horarios'] as Map)['lunes'], {'desde': '09:00', 'hasta': '20:00'});
      expect(g['pausa_minutos'], 60);
      expect(configBotParaGuardar(buena, nombreNegocio: 'X', rubro: 'almacen')['numero_soporte'], numeroSoporteNodoSur);
    });

    test('ida y vuelta: lo guardado se vuelve a leer igual', () {
      final g = configBotParaGuardar(buena.copiar(pausaMinutos: 30), nombreNegocio: 'X', rubro: 'almacen');
      final leida = configBotDesdeJson(g);
      expect(leida.numeroBot, '5492944111111');
      expect(leida.direccion, 'Mitre 150');
      expect(leida.pausaMinutos, 30);
      expect(leida.horarios, buena.horarios);
      expect(configBotDesdeJson(null).pausaMinutos, 60);
    });
  });

  test('el comando de instalar anda en un Termux recién instalado: primero instala curl', () {
    // Primera instalación real (2026-10-09): Termux nuevo no trae curl y el comando fallaba con "curl: command not found".
    expect(comandoInstalarBot, startsWith('pkg install -y curl && curl -fsSL '));
    expect(comandoInstalarBot, endsWith('/neaserisgod/botdemo/main/instalar.sh | bash'));
  });
}

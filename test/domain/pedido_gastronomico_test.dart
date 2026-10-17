// Pedidos de un local gastronómico (`REGLAS-NEGOCIO.md` §22, `docs/PLAN-GASTRONOMIA.md`, El dueño, 2026-10-16): mostrador y
// WhatsApp en la misma lista, el local confirma (con la opción de que entren solos), la cocina puede ir con demora o pausarse,
// y la entrega es retiro, cadete propio o un servicio de reparto, las tres opcionales.
import 'package:flutter_test/flutter_test.dart';
import 'package:la_plazoleta/domain/pedido_gastronomico.dart';
import 'package:la_plazoleta/domain/turnos.dart' show HorarioAtencion;

void main() {
  const zonaCentro = ZonaEnvio(nombre: 'Centro', costoCentavos: 150000, demoraExtraMin: 15);
  const zonaKm8 = ZonaEnvio(nombre: 'Km 8', costoCentavos: 300000, demoraExtraMin: 30);
  const todo = ConfigPedidos(
    retiro: true,
    cadetePropio: true,
    servicioReparto: true,
    zonas: [zonaCentro, zonaKm8],
  );

  group('estado inicial', () {
    test('lo que carga el local (mostrador, teléfono) entra directo a "por hacer"', () {
      for (final canal in [CanalPedido.mostrador, CanalPedido.telefono]) {
        expect(estadoInicial(canal: canal, config: todo, pagaAdelantado: false), EstadoPedido.porHacer);
      }
    });

    test('lo que llega por WhatsApp espera que el local lo confirme', () {
      expect(estadoInicial(canal: CanalPedido.whatsapp, config: todo, pagaAdelantado: false), EstadoPedido.porConfirmar);
    });

    test('con la confirmación automática prendida entra solo', () {
      final auto = todo.copyWith(confirmacionAutomatica: true);
      expect(estadoInicial(canal: CanalPedido.whatsapp, config: auto, pagaAdelantado: false), EstadoPedido.porHacer);
    });

    test('si paga adelantado, primero espera el pago', () {
      expect(estadoInicial(canal: CanalPedido.whatsapp, config: todo, pagaAdelantado: true), EstadoPedido.esperandoPago);
    });

    test('al llegar el pago sigue como si recién entrara', () {
      expect(estadoAlPagar(todo), EstadoPedido.porConfirmar);
      expect(estadoAlPagar(todo.copyWith(confirmacionAutomatica: true)), EstadoPedido.porHacer);
    });
  });

  group('siguientes estados', () {
    test('por confirmar se acepta o se rechaza', () {
      expect(siguientesEstados(EstadoPedido.porConfirmar, FormaEntrega.retiro), [EstadoPedido.porHacer, EstadoPedido.rechazado]);
    });

    test('un retiro pasa de listo a entregado, sin "en camino"', () {
      expect(siguientesEstados(EstadoPedido.listo, FormaEntrega.retiro), [EstadoPedido.entregado]);
    });

    test('un envío pasa de listo a en camino, y de ahí a entregado', () {
      for (final forma in [FormaEntrega.cadetePropio, FormaEntrega.servicioReparto]) {
        expect(siguientesEstados(EstadoPedido.listo, forma), [EstadoPedido.enCamino]);
        expect(siguientesEstados(EstadoPedido.enCamino, forma), [EstadoPedido.entregado]);
      }
    });

    test('lo terminado no sigue', () {
      for (final e in [EstadoPedido.entregado, EstadoPedido.rechazado, EstadoPedido.cancelado]) {
        expect(siguientesEstados(e, FormaEntrega.retiro), isEmpty);
        expect(e.abierto, isFalse);
      }
    });

    test('se puede cancelar hasta que sale del local', () {
      expect(sePuedeCancelar(EstadoPedido.porHacer), isTrue);
      expect(sePuedeCancelar(EstadoPedido.listo), isTrue);
      expect(sePuedeCancelar(EstadoPedido.enCamino), isFalse);
      expect(sePuedeCancelar(EstadoPedido.entregado), isFalse);
    });

    test('las claves no cambian (se guardan y viajan por la sync)', () {
      for (final e in EstadoPedido.values) {
        expect(EstadoPedido.desdeClave(e.clave), e);
      }
      expect(EstadoPedido.desdeClave('ALGO_RARO'), EstadoPedido.porConfirmar);
    });
  });

  group('cocina', () {
    test('normal y con demora toman pedidos con su tiempo; pausada no', () {
      expect(todo.minutosDePreparacion(EstadoCocina.normal), 30);
      expect(todo.minutosDePreparacion(EstadoCocina.demorada), 60);
      expect(todo.minutosDePreparacion(EstadoCocina.pausada), isNull);
    });

    test('la hora estimada de un envío suma la demora de la zona', () {
      final ahora = DateTime(2026, 10, 16, 20);
      expect(
        horaEstimada(ahora: ahora, cocina: EstadoCocina.normal, config: todo, forma: FormaEntrega.retiro),
        DateTime(2026, 10, 16, 20, 30),
      );
      expect(
        horaEstimada(ahora: ahora, cocina: EstadoCocina.demorada, config: todo, forma: FormaEntrega.cadetePropio, zona: zonaKm8),
        DateTime(2026, 10, 16, 21, 30),
      );
      expect(horaEstimada(ahora: ahora, cocina: EstadoCocina.pausada, config: todo, forma: FormaEntrega.retiro), isNull);
    });
  });

  group('entrega', () {
    test('solo se ofrece lo que el local prendió', () {
      const soloRetiro = ConfigPedidos(retiro: true);
      expect(soloRetiro.formasDisponibles, [FormaEntrega.retiro]);
      const soloEnvio = ConfigPedidos(retiro: false, servicioReparto: true, zonas: [zonaCentro]);
      expect(soloEnvio.formasDisponibles, [FormaEntrega.servicioReparto]);
    });

    test('un envío sin zonas cargadas no se puede ofrecer', () {
      const sinZonas = ConfigPedidos(retiro: true, cadetePropio: true);
      expect(sinZonas.formasDisponibles, [FormaEntrega.retiro]);
    });

    test('el retiro no cobra envío; el envío cobra el de la zona', () {
      expect(costoEnvioCentavos(FormaEntrega.retiro, zonaCentro), 0);
      expect(costoEnvioCentavos(FormaEntrega.cadetePropio, zonaCentro), 150000);
      expect(costoEnvioCentavos(FormaEntrega.servicioReparto, zonaKm8), 300000);
    });

    test('un envío necesita dirección y zona; un retiro no', () {
      expect(faltaParaEntrega(FormaEntrega.retiro), isEmpty);
      expect(faltaParaEntrega(FormaEntrega.cadetePropio), containsAll(['dirección', 'zona']));
      expect(faltaParaEntrega(FormaEntrega.cadetePropio, direccion: 'Mitre 100', zona: zonaCentro), isEmpty);
      expect(faltaParaEntrega(FormaEntrega.servicioReparto, direccion: '  ', zona: zonaCentro), ['dirección']);
    });
  });

  group('configuración guardada', () {
    test('ida y vuelta por JSON', () {
      final config = todo.copyWith(confirmacionAutomatica: true, pago: ModoPagoPedido.aElegir, minutosNormal: 25, minutosDemorada: 50, catalogoWhatsapp: true);
      final leida = ConfigPedidos.desdeJson(config.toJson());
      expect(leida.toJson(), config.toJson());
      expect(leida.catalogoWhatsapp, isTrue);
    });

    test('un JSON roto o vacío da la configuración de arranque: solo retiro, pago al entregar, confirma el local', () {
      for (final crudo in [null, 'basura', <String, Object?>{}]) {
        final c = ConfigPedidos.desdeJson(crudo);
        expect(c.formasDisponibles, [FormaEntrega.retiro]);
        expect(c.pago, ModoPagoPedido.alEntregar);
        expect(c.confirmacionAutomatica, isFalse);
      }
    });

    test('una zona rota se descarta y no frena al resto', () {
      final c = ConfigPedidos.desdeJson({
        'cadetePropio': true,
        'zonas': [
          {'nombre': 'Centro', 'costoCentavos': 150000, 'demoraExtraMin': 15},
          {'nombre': '', 'costoCentavos': 1},
          {'nombre': 'Negativa', 'costoCentavos': -5},
          'basura',
        ],
      });
      expect(c.zonas.map((z) => z.nombre), ['Centro']);
    });
  });

  group('aviso al cliente', () {
    test('listo para retirar, y salió para un envío', () {
      expect(mensajeAlCliente(estado: EstadoPedido.listo, forma: FormaEntrega.retiro, local: 'Rotisería Doña Ana', numero: 'A3-0042'),
          contains('listo para retirar'));
      expect(mensajeAlCliente(estado: EstadoPedido.enCamino, forma: FormaEntrega.cadetePropio, local: 'Rotisería Doña Ana', numero: 'A3-0042'),
          contains('salió'));
    });

    test('los estados que no le importan al cliente no mandan nada', () {
      expect(mensajeAlCliente(estado: EstadoPedido.porHacer, forma: FormaEntrega.retiro, local: 'X', numero: '1'), isNotNull);
      expect(mensajeAlCliente(estado: EstadoPedido.listo, forma: FormaEntrega.cadetePropio, local: 'X', numero: '1'), isNull);
      expect(mensajeAlCliente(estado: EstadoPedido.entregado, forma: FormaEntrega.retiro, local: 'X', numero: '1'), isNull);
    });
  });

  group('líneas', () {
    test('por unidad y por peso, cada una por su helper', () {
      const milanesa = LineaPedido(gid: 'p1', nombre: 'Milanesa', cantidad: 2, precioCentavos: 650000);
      const ensalada = LineaPedido(gid: 'p2', nombre: 'Ensalada rusa', gramos: 250, precioCentavos: 1200000);
      expect(milanesa.subtotalCentavos, 1300000);
      expect(ensalada.subtotalCentavos, 300000);
      expect(totalPedidoCentavos([milanesa, ensalada], costoEnvioCentavos: 150000), 1750000);
    });

    test('ida y vuelta por JSON, y lo roto se descarta', () {
      const linea = LineaPedido(gid: 'p1', nombre: 'Tarta', cantidad: 1, precioCentavos: 900000);
      expect(LineaPedido.desdeJson(linea.toJson())!.toJson(), linea.toJson());
      for (final roto in [
        null,
        {'gid': 'p1', 'nombre': 'X', 'precioCentavos': 1},
        {'gid': 'p1', 'nombre': 'X', 'cantidad': 1, 'gramos': 100, 'precioCentavos': 1},
        {'gid': 'p1', 'nombre': 'X', 'cantidad': 0, 'precioCentavos': 1},
        {'gid': '', 'nombre': 'X', 'cantidad': 1, 'precioCentavos': 1},
        {'gid': 'p1', 'nombre': 'X', 'cantidad': 1, 'precioCentavos': -1},
      ]) {
        expect(LineaPedido.desdeJson(roto), isNull, reason: '$roto');
      }
    });
  });

  group('fuera de hora se programa', () {
    // Viernes 16 de octubre de 2026. Abre de 11 a 15 y de lunes a sábado; el domingo cerrado.
    const horario = HorarioAtencion({
      1: (desdeMin: 660, hastaMin: 900),
      2: (desdeMin: 660, hastaMin: 900),
      3: (desdeMin: 660, hastaMin: 900),
      4: (desdeMin: 660, hastaMin: 900),
      5: (desdeMin: 660, hastaMin: 900),
      6: (desdeMin: 660, hastaMin: 900),
      7: null,
    });

    test('abierto: sale a la hora de siempre', () {
      final r = cuandoSale(ahora: DateTime(2026, 10, 16, 12), cocina: EstadoCocina.normal, config: todo, forma: FormaEntrega.retiro, horario: horario)!;
      expect(r.hora, DateTime(2026, 10, 16, 12, 30));
      expect(r.programado, isFalse);
    });

    test('antes de abrir: para cuando abre', () {
      final r = cuandoSale(ahora: DateTime(2026, 10, 16, 9), cocina: EstadoCocina.normal, config: todo, forma: FormaEntrega.retiro, horario: horario)!;
      expect(r.hora, DateTime(2026, 10, 16, 11, 30));
      expect(r.programado, isTrue);
    });

    test('el sábado a la noche: para el lunes, porque el domingo está cerrado, con la demora de la zona', () {
      final r = cuandoSale(
          ahora: DateTime(2026, 10, 17, 22), cocina: EstadoCocina.normal, config: todo, forma: FormaEntrega.cadetePropio, zona: zonaCentro, horario: horario)!;
      expect(r.hora, DateTime(2026, 10, 19, 11, 45));
      expect(r.programado, isTrue);
    });

    test('pausada no sale, y un horario sin días abiertos no frena', () {
      expect(cuandoSale(ahora: DateTime(2026, 10, 16, 12), cocina: EstadoCocina.pausada, config: todo, forma: FormaEntrega.retiro, horario: horario), isNull);
      const cerrado = HorarioAtencion({1: null, 2: null, 3: null, 4: null, 5: null, 6: null, 7: null});
      final r = cuandoSale(ahora: DateTime(2026, 10, 16, 3), cocina: EstadoCocina.normal, config: todo, forma: FormaEntrega.retiro, horario: cerrado)!;
      expect(r.programado, isFalse);
    });
  });
}


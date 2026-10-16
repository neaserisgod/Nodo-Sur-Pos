// Pedidos de un local gastronómico: rotisería, comida para llevar (`REGLAS-NEGOCIO.md` §22, `docs/PLAN-GASTRONOMIA.md`,
// El dueño, 2026-10-16). Funciones puras: sin base ni pantalla. Las usan la lista de pedidos de la app y, por el sitio, el
// bot de WhatsApp: lo que el bot le promete al cliente (formas de entrega, hora, si se toman pedidos) sale de acá.
//
// Decisiones del dueño:
//  * Llegue por donde llegue (mostrador, teléfono, WhatsApp), el pedido cae en la misma lista.
//  * El local confirma lo que llega de afuera, con la opción de que entre solo: "para que un pedido se confirme solo deben
//    haber muchísimas variables que estén ok, ya sea retrasos, stock, personal, se rompió una máquina".
//  * Por eso mismo la cocina tiene un estado (normal, con demora, pausada) que el bot respeta.
//  * La entrega no es obligatoria: retiro, cadete propio y servicio de reparto (una cadetería de afuera), cada una opcional.
//  * Cómo se paga lo elige cada local: al entregar, adelantado, o que elija el cliente.

/// Por dónde llegó el pedido. Las claves se guardan en la base y viajan por la sync: no se renombran nunca.
enum CanalPedido {
  mostrador('MOSTRADOR'),
  telefono('TELEFONO'),
  whatsapp('WHATSAPP');

  const CanalPedido(this.clave);
  final String clave;

  static CanalPedido desdeClave(String clave) =>
      CanalPedido.values.firstWhere((c) => c.clave == clave, orElse: () => CanalPedido.mostrador);

  /// Lo cargó alguien del local: ya está confirmado por definición.
  bool get loCargaElLocal => this == mostrador || this == telefono;

  String get etiqueta => switch (this) {
        mostrador => 'Mostrador',
        telefono => 'Teléfono',
        whatsapp => 'WhatsApp',
      };
}

/// Cómo llega el pedido al cliente. Claves fijas, como [CanalPedido].
enum FormaEntrega {
  retiro('RETIRO'),

  /// El cadete del local.
  cadetePropio('CADETE'),

  /// Una cadetería o servicio de reparto de afuera.
  servicioReparto('REPARTO');

  const FormaEntrega(this.clave);
  final String clave;

  static FormaEntrega desdeClave(String clave) =>
      FormaEntrega.values.firstWhere((f) => f.clave == clave, orElse: () => FormaEntrega.retiro);

  bool get esEnvio => this != retiro;

  String get etiqueta => switch (this) {
        retiro => 'Retira en el local',
        cadetePropio => 'Envío (cadete propio)',
        servicioReparto => 'Envío (servicio de reparto)',
      };
}

/// Estado de un pedido. Claves fijas, como [CanalPedido].
enum EstadoPedido {
  /// Eligió pagar adelantado y todavía no llegó el pago: no se cocina nada.
  esperandoPago('ESPERANDO_PAGO'),

  /// Llegó de afuera y el local todavía no lo aceptó.
  porConfirmar('POR_CONFIRMAR'),
  porHacer('POR_HACER'),
  listo('LISTO'),

  /// Salió con el cadete o el servicio de reparto.
  enCamino('EN_CAMINO'),
  entregado('ENTREGADO'),

  /// El local no lo aceptó.
  rechazado('RECHAZADO'),

  /// Se aceptó y después se cayó (el cliente no lo quiso, no hubo con qué hacerlo).
  cancelado('CANCELADO');

  const EstadoPedido(this.clave);
  final String clave;

  static EstadoPedido desdeClave(String clave) =>
      EstadoPedido.values.firstWhere((e) => e.clave == clave, orElse: () => EstadoPedido.porConfirmar);

  /// Sigue en la lista de trabajo.
  bool get abierto => this != entregado && this != rechazado && this != cancelado;

  String get etiqueta => switch (this) {
        esperandoPago => 'Esperando el pago',
        porConfirmar => 'Por confirmar',
        porHacer => 'Por hacer',
        listo => 'Listo',
        enCamino => 'En camino',
        entregado => 'Entregado',
        rechazado => 'Rechazado',
        cancelado => 'Cancelado',
      };
}

/// Cómo está la cocina ahora. Lo cambia el local con un toque y el bot lo respeta: con demora avisa el tiempo nuevo; pausada
/// no toma pedidos.
enum EstadoCocina {
  normal('NORMAL'),
  demorada('DEMORADA'),
  pausada('PAUSADA');

  const EstadoCocina(this.clave);
  final String clave;

  static EstadoCocina desdeClave(String clave) =>
      EstadoCocina.values.firstWhere((e) => e.clave == clave, orElse: () => EstadoCocina.normal);
}

/// Cómo cobra el local los pedidos para retirar o enviar.
enum ModoPagoPedido {
  /// Al retirar, o al recibir el envío.
  alEntregar('AL_ENTREGAR'),

  /// Por Mercado Pago antes de cocinar.
  adelantado('ADELANTADO'),

  /// El cliente elige.
  aElegir('A_ELEGIR');

  const ModoPagoPedido(this.clave);
  final String clave;

  static ModoPagoPedido desdeClave(String clave) =>
      ModoPagoPedido.values.firstWhere((m) => m.clave == clave, orElse: () => ModoPagoPedido.alEntregar);
}

/// Una zona de envío: lo que cuesta mandar hasta ahí y cuánto tarda de más.
class ZonaEnvio {
  const ZonaEnvio({required this.nombre, required this.costoCentavos, this.demoraExtraMin = 0});

  final String nombre;
  final int costoCentavos;
  final int demoraExtraMin;

  Map<String, Object?> toJson() => {'nombre': nombre, 'costoCentavos': costoCentavos, 'demoraExtraMin': demoraExtraMin};

  /// Null si no se entiende: sin nombre, o con un costo o una demora negativos.
  static ZonaEnvio? desdeJson(Object? crudo) {
    if (crudo is! Map) return null;
    final nombre = crudo['nombre'], costo = crudo['costoCentavos'], demora = crudo['demoraExtraMin'] ?? 0;
    if (nombre is! String || nombre.trim().isEmpty || costo is! num || demora is! num) return null;
    if (costo < 0 || demora < 0) return null;
    return ZonaEnvio(nombre: nombre.trim(), costoCentavos: costo.toInt(), demoraExtraMin: demora.toInt());
  }
}

/// Cómo trabaja el local los pedidos. Se guarda como JSON en la configuración del negocio y lo baja el bot.
class ConfigPedidos {
  const ConfigPedidos({
    this.retiro = true,
    this.cadetePropio = false,
    this.servicioReparto = false,
    this.zonas = const [],
    this.pago = ModoPagoPedido.alEntregar,
    this.confirmacionAutomatica = false,
    this.minutosNormal = 30,
    this.minutosDemorada = 60,
  });

  final bool retiro;
  final bool cadetePropio;
  final bool servicioReparto;

  /// Las mismas para el cadete propio y el servicio de reparto: lo que se le cobra al cliente depende de adónde va, no de quién
  /// lo lleva.
  final List<ZonaEnvio> zonas;
  final ModoPagoPedido pago;
  final bool confirmacionAutomatica;

  /// Cuánto tarda un pedido en estar listo, con la cocina normal y con demora.
  final int minutosNormal;
  final int minutosDemorada;

  /// Las formas que se le ofrecen al cliente. Un envío sin zonas no se ofrece: no habría cómo cobrarlo.
  List<FormaEntrega> get formasDisponibles => [
        if (retiro) FormaEntrega.retiro,
        if (cadetePropio && zonas.isNotEmpty) FormaEntrega.cadetePropio,
        if (servicioReparto && zonas.isNotEmpty) FormaEntrega.servicioReparto,
      ];

  /// Null si la cocina está pausada: no se toman pedidos.
  int? minutosDePreparacion(EstadoCocina cocina) => switch (cocina) {
        EstadoCocina.normal => minutosNormal,
        EstadoCocina.demorada => minutosDemorada,
        EstadoCocina.pausada => null,
      };

  ConfigPedidos copyWith({
    bool? retiro,
    bool? cadetePropio,
    bool? servicioReparto,
    List<ZonaEnvio>? zonas,
    ModoPagoPedido? pago,
    bool? confirmacionAutomatica,
    int? minutosNormal,
    int? minutosDemorada,
  }) =>
      ConfigPedidos(
        retiro: retiro ?? this.retiro,
        cadetePropio: cadetePropio ?? this.cadetePropio,
        servicioReparto: servicioReparto ?? this.servicioReparto,
        zonas: zonas ?? this.zonas,
        pago: pago ?? this.pago,
        confirmacionAutomatica: confirmacionAutomatica ?? this.confirmacionAutomatica,
        minutosNormal: minutosNormal ?? this.minutosNormal,
        minutosDemorada: minutosDemorada ?? this.minutosDemorada,
      );

  Map<String, Object?> toJson() => {
        'retiro': retiro,
        'cadetePropio': cadetePropio,
        'servicioReparto': servicioReparto,
        'zonas': [for (final z in zonas) z.toJson()],
        'pago': pago.clave,
        'confirmacionAutomatica': confirmacionAutomatica,
        'minutosNormal': minutosNormal,
        'minutosDemorada': minutosDemorada,
      };

  /// Lo que no se entiende queda con el valor de arranque (solo retiro, pago al entregar, confirma el local): una
  /// configuración rota nunca puede dejar al local recibiendo pedidos que no pidió.
  factory ConfigPedidos.desdeJson(Object? crudo) {
    if (crudo is! Map) return const ConfigPedidos();
    bool siNo(String clave, bool porDefecto) => crudo[clave] is bool ? crudo[clave] as bool : porDefecto;
    int minutos(String clave, int porDefecto) {
      final v = crudo[clave];
      return v is num && v > 0 ? v.toInt() : porDefecto;
    }

    final zonas = crudo['zonas'];
    return ConfigPedidos(
      retiro: siNo('retiro', true),
      cadetePropio: siNo('cadetePropio', false),
      servicioReparto: siNo('servicioReparto', false),
      zonas: [
        if (zonas is List)
          for (final z in zonas) ?ZonaEnvio.desdeJson(z),
      ],
      pago: crudo['pago'] is String ? ModoPagoPedido.desdeClave(crudo['pago'] as String) : ModoPagoPedido.alEntregar,
      confirmacionAutomatica: siNo('confirmacionAutomatica', false),
      minutosNormal: minutos('minutosNormal', 30),
      minutosDemorada: minutos('minutosDemorada', 60),
    );
  }
}

/// Con qué estado entra un pedido nuevo. Lo que carga el local ya está confirmado; lo de afuera espera el pago si lo pagó
/// adelantado, y después la confirmación del local (salvo que entre solo).
EstadoPedido estadoInicial({required CanalPedido canal, required ConfigPedidos config, required bool pagaAdelantado}) {
  if (canal.loCargaElLocal) return EstadoPedido.porHacer;
  if (pagaAdelantado) return EstadoPedido.esperandoPago;
  return estadoAlPagar(config);
}

/// Llegó el pago adelantado (o no había que esperarlo): sigue como si recién entrara.
EstadoPedido estadoAlPagar(ConfigPedidos config) =>
    config.confirmacionAutomatica ? EstadoPedido.porHacer : EstadoPedido.porConfirmar;

/// A qué estados puede pasar un pedido con el botón principal de la lista. Cancelar va aparte ([sePuedeCancelar]).
List<EstadoPedido> siguientesEstados(EstadoPedido estado, FormaEntrega forma) => switch (estado) {
      EstadoPedido.esperandoPago => const [],
      EstadoPedido.porConfirmar => const [EstadoPedido.porHacer, EstadoPedido.rechazado],
      EstadoPedido.porHacer => const [EstadoPedido.listo],
      EstadoPedido.listo => forma.esEnvio ? const [EstadoPedido.enCamino] : const [EstadoPedido.entregado],
      EstadoPedido.enCamino => const [EstadoPedido.entregado],
      EstadoPedido.entregado || EstadoPedido.rechazado || EstadoPedido.cancelado => const [],
    };

/// Hasta que sale del local se puede cancelar. Uno en camino ya no: se entrega o vuelve, y eso lo resuelve una persona.
bool sePuedeCancelar(EstadoPedido estado) =>
    estado == EstadoPedido.esperandoPago || estado == EstadoPedido.porConfirmar || estado == EstadoPedido.porHacer || estado == EstadoPedido.listo;

/// Cuándo va a estar (o llegar) el pedido. Null si la cocina está pausada.
DateTime? horaEstimada({
  required DateTime ahora,
  required EstadoCocina cocina,
  required ConfigPedidos config,
  required FormaEntrega forma,
  ZonaEnvio? zona,
}) {
  final minutos = config.minutosDePreparacion(cocina);
  if (minutos == null) return null;
  final extra = forma.esEnvio ? (zona?.demoraExtraMin ?? 0) : 0;
  return ahora.add(Duration(minutes: minutos + extra));
}

/// Lo que se le cobra al cliente por el envío. El retiro no cobra.
int costoEnvioCentavos(FormaEntrega forma, ZonaEnvio? zona) => forma.esEnvio ? (zona?.costoCentavos ?? 0) : 0;

/// Lo que falta para poder tomar el pedido con esa forma de entrega (vacío = completo).
List<String> faltaParaEntrega(FormaEntrega forma, {String? direccion, ZonaEnvio? zona}) => [
      if (forma.esEnvio && (direccion == null || direccion.trim().isEmpty)) 'dirección',
      if (forma.esEnvio && zona == null) 'zona',
    ];

/// El WhatsApp que le llega al cliente cuando el pedido cambia. Null si ese cambio no le importa: un envío listo todavía no
/// salió (se avisa al salir), y uno entregado ya lo tiene en la mano.
String? mensajeAlCliente({required EstadoPedido estado, required FormaEntrega forma, required String local, required String numero}) =>
    switch (estado) {
      EstadoPedido.porHacer => '¡Confirmamos tu pedido $numero! 🙌 Te avisamos por acá cuando esté ${forma.esEnvio ? 'en camino' : 'listo'}.',
      EstadoPedido.listo when !forma.esEnvio => '¡Tu pedido $numero está listo para retirar en $local! 🍽️',
      EstadoPedido.enCamino => '¡Tu pedido $numero salió! 🛵 Ya va para tu casa.',
      EstadoPedido.rechazado => 'Perdón, en $local no podemos tomar tu pedido $numero ahora 😔 Escribinos y te ayudamos.',
      EstadoPedido.cancelado => 'Tu pedido $numero en $local quedó cancelado. Cualquier duda, escribinos.',
      _ => null,
    };

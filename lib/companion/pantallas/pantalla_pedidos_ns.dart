// Pedidos de un local gastronómico (`REGLAS-NEGOCIO.md` §22, `docs/PLAN-GASTRONOMIA.md`, etapa 4): en una rotisería reemplaza
// al Inicio y es donde abre la app. Arriba, el estado de la cocina con un toque (el bot lo respeta); abajo, la lista de trabajo
// por estado, del más viejo al más nuevo, con el botón del paso que sigue en cada pedido. El "+" toma un pedido del mostrador.
//
// Trabaja sobre la base del celular, como la Agenda. Las reglas son de `domain/pedido_gastronomico.dart`, por
// `data/repositorio_pedidos_gastronomia.dart`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/database.dart';
import '../../data/repositorio_configuracion.dart' show configuracionNegocioActual;
import '../../data/repositorio_pedidos_gastronomia.dart';
import '../../domain/pedido_gastronomico.dart';
import '../../domain/pedido_whatsapp.dart' show normalizarWhatsapp, urlWhatsapp;
import '../../servicios/registro_errores.dart' show registrarSiNoEsDeRed;
import '../app_ns.dart';
import '../base_local.dart';
import '../cambios_companion.dart';
import '../emparejamiento.dart';
import '../kit/kit_ns.dart';
import '../mensaje_error.dart';
import 'pantalla_config_pedidos_ns.dart';

String _hora(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// El texto del botón que lleva al pedido a [estado].
String _textoPaso(EstadoPedido estado) => switch (estado) {
      EstadoPedido.porHacer => 'Aceptar',
      EstadoPedido.rechazado => 'Rechazar',
      EstadoPedido.listo => 'Está listo',
      EstadoPedido.enCamino => 'Salió',
      EstadoPedido.entregado => 'Entregado',
      _ => estado.etiqueta,
    };

/// En qué orden se ven los grupos: primero lo que espera una decisión, después la cocina, al final lo que ya salió.
const _ordenDeGrupos = [
  EstadoPedido.porConfirmar,
  EstadoPedido.esperandoPago,
  EstadoPedido.porHacer,
  EstadoPedido.listo,
  EstadoPedido.enCamino,
];

class PantallaPedidosNs extends StatefulWidget {
  /// [db], [usuarioId] y [ahora] son para tests.
  const PantallaPedidosNs({super.key, this.db, this.usuarioId, this.ahora});

  final AppDatabase? db;
  final int? usuarioId;
  final DateTime? ahora;

  @override
  State<PantallaPedidosNs> createState() => _PantallaPedidosNsState();
}

class _PantallaPedidosNsState extends State<PantallaPedidosNs> {
  late final AppDatabase _db = widget.db ?? baseLocalCompanion();
  List<PedidoGastronomia>? _pedidos;
  EstadoCocina _cocina = EstadoCocina.normal;
  ConfigPedidos _config = const ConfigPedidos();
  String _local = '';
  int? _usuarioId;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _usuarioId = widget.usuarioId;
    if (_usuarioId == null) {
      leerUsuario().then((u) {
        if (mounted) setState(() => _usuarioId = u?.id);
      });
    }
    _sub = avisosCambiosCompanion.listen((_) => _recargar());
    _recargar();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _recargar() async {
    try {
      final pedidos = await pedidosAbiertos(_db);
      final cocina = await estadoCocinaActual(_db);
      final config = await configPedidosActual(_db);
      final local = (await configuracionNegocioActual(_db)).nombreComercio;
      if (!mounted) return;
      setState(() {
        _pedidos = pedidos;
        _cocina = cocina;
        _config = config;
        _local = local;
      });
    } catch (e, st) {
      unawaited(registrarSiNoEsDeRed('Leer los pedidos', e, st));
      if (!mounted) return;
      setState(() => _pedidos ??= const []);
      mostrarAvisoNs(context, 'No se pudieron leer los pedidos: ${mensajeDeError(e)}', largo: true);
    }
  }

  Future<void> _cambiarCocina(EstadoCocina estado) async {
    setState(() => _cocina = estado);
    await cambiarEstadoCocina(_db, estado);
    if (!mounted) return;
    mostrarAvisoNs(context, switch (estado) {
      EstadoCocina.normal => 'Cocina normal: el bot dice ${_config.minutosNormal} minutos.',
      EstadoCocina.demorada => 'Con demora: el bot dice ${_config.minutosDemorada} minutos.',
      EstadoCocina.pausada => 'Pausada: el bot no toma pedidos. El mostrador sigue.',
    });
  }

  /// Cobrar: arma la venta con lo del pedido y abre Cobrar (efectivo, QR, mixto, Point, como cualquier venta).
  Future<void> _cobrar(PedidoGastronomia pedido) async {
    final app = AppNs.maybeOf(context);
    if (app == null) return;
    final problema = await app.cobrarPedido(pedido.id);
    if (problema != null && mounted) mostrarAvisoNs(context, problema, largo: true);
  }

  Future<void> _avanzar(PedidoGastronomia pedido, EstadoPedido nuevo) async {
    try {
      await avanzarPedido(_db, pedido.id, nuevo);
    } on PasoDePedidoInvalido {
      if (mounted) mostrarAvisoNs(context, 'Ese pedido ya cambió. Se actualiza la lista.');
    }
    await _recargar();
    if (!mounted) return;
    final forma = FormaEntrega.desdeClave(pedido.formaEntrega);
    final mensaje = mensajeAlCliente(estado: nuevo, forma: forma, local: _nombreLocal, numero: pedido.numero);
    // Al cliente se le avisa por WhatsApp con un toque (el que lo manda es quien aprieta enviar): sin teléfono no hay a quién.
    if (mensaje != null && pedido.telefono != null && pedido.canal != CanalPedido.whatsapp.clave) {
      await _ofrecerAviso(pedido, mensaje);
    }
  }

  String get _nombreLocal => _local.trim().isEmpty ? 'el local' : _local.trim();

  Future<void> _ofrecerAviso(PedidoGastronomia pedido, String mensaje) async {
    final numero = normalizarWhatsapp(pedido.telefono ?? '');
    if (numero == null) return;
    final avisar = await mostrarHojaNs<bool>(
      context,
      builder: (ctx) => HojaNs(
        titulo: '¿Le avisás a ${pedido.nombreCliente}?',
        texto: mensaje,
        botones: [
          BotonNs.primario(ctx, 'Avisar por WhatsApp', () => Navigator.pop(ctx, true)),
          const SizedBox(height: 10),
          BotonNs.secundario(ctx, 'Ahora no', () => Navigator.pop(ctx, false)),
        ],
      ),
    );
    if (avisar == true) await launchUrl(urlWhatsapp(numero, mensaje), mode: LaunchMode.externalApplication);
  }

  Future<void> _verPedido(PedidoGastronomia pedido) async {
    final estado = EstadoPedido.desdeClave(pedido.estado);
    final lineas = lineasDe(pedido);
    final accion = await mostrarHojaNs<String>(
      context,
      builder: (ctx) {
        final ns = ctx.ns;
        return HojaNs(
          titulo: '${pedido.numero} · ${pedido.nombreCliente}',
          texto: [
            FormaEntrega.desdeClave(pedido.formaEntrega).etiqueta,
            if (pedido.direccion != null) '${pedido.direccion} (${pedido.zona})',
            if (pedido.telefono != null) 'Tel. ${pedido.telefono}',
            if (pedido.nota != null && pedido.nota!.trim().isNotEmpty) 'Nota: ${pedido.nota}',
          ].join('\n'),
          bloques: [
            for (final l in lineas)
              FilaClaveValorNs(clave: '${l.cantidad ?? '${l.gramos} g'} × ${l.nombre}', valor: plataNs(l.subtotalCentavos)),
            if (pedido.costoEnvioCentavos > 0) FilaClaveValorNs(clave: 'Envío', valor: plataNs(pedido.costoEnvioCentavos)),
            FilaClaveValorNs(
              clave: 'Total',
              valor: plataNs(totalPedidoCentavos(lineas, costoEnvioCentavos: pedido.costoEnvioCentavos)),
              tamanioValor: 22,
              sinLinea: true,
            ),
            if (pedido.pagaAdelantado)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(pedido.pagado ? 'Pagado por Mercado Pago' : 'Esperando el pago por Mercado Pago',
                    style: estiloNs(14, peso: FontWeight.w600, color: pedido.pagado ? ns.g : ns.w)),
              ),
          ],
          botones: [
            if (pedido.telefono != null) ...[
              BotonNs.secundario(ctx, 'Escribirle por WhatsApp', () => Navigator.pop(ctx, 'whatsapp'), icono: IconoNs.celular),
              const SizedBox(height: 10),
            ],
            if (sePuedeCancelar(estado)) BotonNs.secundario(ctx, 'Cancelar el pedido', () => Navigator.pop(ctx, 'cancelar')),
          ],
        );
      },
    );
    if (!mounted) return;
    if (accion == 'cancelar') await _avanzar(pedido, EstadoPedido.cancelado);
    if (accion == 'whatsapp') {
      final numero = normalizarWhatsapp(pedido.telefono ?? '');
      if (numero != null) await launchUrl(urlWhatsapp(numero, 'Hola ${pedido.nombreCliente}, te escribimos de $_nombreLocal por tu pedido ${pedido.numero}.'), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _configurar() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PantallaConfigPedidosNs(db: widget.db)));
    await _recargar();
  }

  Future<void> _nuevoPedido() async {
    final usuarioId = _usuarioId;
    if (usuarioId == null) return;
    final carta = await cartaDelLocal(_db);
    if (!mounted) return;
    if (carta.isEmpty) {
      mostrarAvisoNs(context, 'Primero cargá tu carta: los platos con su precio.', largo: true);
      return;
    }
    final creado = await mostrarHojaNs<bool>(
      context,
      builder: (ctx) => _HojaNuevoPedido(db: _db, carta: carta, config: _config, usuarioId: usuarioId, ahora: widget.ahora),
    );
    if (creado == true) await _recargar();
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final pedidos = _pedidos;
    final porEstado = <EstadoPedido, List<PedidoGastronomia>>{};
    for (final p in pedidos ?? const <PedidoGastronomia>[]) {
      (porEstado[EstadoPedido.desdeClave(p.estado)] ??= []).add(p);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, BarraInferiorNs.espacioReservado - 8),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pedidos', style: estiloNs(15, peso: FontWeight.w600, color: ns.mute)),
                  const SizedBox(height: 2),
                  Text(
                    pedidos == null ? '…' : pedidos.isEmpty ? 'Nada pendiente' : '${pedidos.length} abiertos',
                    style: tituloNs(40, track: -0.055, color: ns.ink),
                  ),
                ],
              ),
            ),
            BotonCircularNs(
              key: const Key('pedidos_configurar'),
              icono: IconoNs.ajustes,
              etiqueta: 'Configurar pedidos',
              onTap: _configurar,
              tamanio: 52,
            ),
            const SizedBox(width: 10),
            BotonCircularNs(
              key: const Key('pedidos_nuevo'),
              icono: IconoNs.masMas,
              etiqueta: 'Nuevo pedido',
              onTap: _nuevoPedido,
              tamanio: 52,
              fondo: ns.prim,
              colorIcono: TokensNs.blanco,
            ),
          ],
        ),
        const SizedBox(height: 18),
        const SeccionNs('La cocina'),
        const SizedBox(height: 8),
        SegmentoNs(
          key: const Key('pedidos_cocina'),
          opciones: const ['Normal', 'Con demora', 'Pausada'],
          indice: EstadoCocina.values.indexOf(_cocina),
          onCambio: (i) => _cambiarCocina(EstadoCocina.values[i]),
        ),
        const SizedBox(height: 8),
        InfoNs(
          switch (_cocina) {
            EstadoCocina.normal => 'El bot dice que está en ${_config.minutosNormal} minutos.',
            EstadoCocina.demorada => 'El bot avisa la demora: ${_config.minutosDemorada} minutos.',
            EstadoCocina.pausada => 'El bot no toma pedidos. El mostrador sigue.',
          },
          tono: switch (_cocina) {
            EstadoCocina.normal => TonoNs.good,
            EstadoCocina.demorada => TonoNs.warn,
            EstadoCocina.pausada => TonoNs.bad,
          },
        ),
        if (pedidos != null && pedidos.isEmpty) ...[
          const SizedBox(height: 28),
          Text('Cuando entre un pedido, por el mostrador o por WhatsApp, aparece acá.', style: estiloNs(16, color: ns.mute)),
        ],
        for (final estado in _ordenDeGrupos)
          if (porEstado[estado] case final grupo?) ...[
            const SizedBox(height: 24),
            SeccionNs(estado.etiqueta, derecha: Text('${grupo.length}', style: estiloNs(14, peso: FontWeight.w600, color: ns.mute))),
            const SizedBox(height: 10),
            for (final p in grupo) ...[
              _TarjetaPedido(
                pedido: p,
                onVer: () => _verPedido(p),
                onPaso: (nuevo) => _avanzar(p, nuevo),
                onCobrar: () => _cobrar(p),
              ),
              const SizedBox(height: 10),
            ],
          ],
      ],
    );
  }
}

class _TarjetaPedido extends StatelessWidget {
  const _TarjetaPedido({required this.pedido, required this.onVer, required this.onPaso, required this.onCobrar});

  final PedidoGastronomia pedido;
  final VoidCallback onVer;
  final ValueChanged<EstadoPedido> onPaso;
  final VoidCallback onCobrar;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final estado = EstadoPedido.desdeClave(pedido.estado);
    final forma = FormaEntrega.desdeClave(pedido.formaEntrega);
    final lineas = lineasDe(pedido);
    final pasos = siguientesEstados(estado, forma);
    // Se cobra lo que ya se aceptó y todavía no tiene venta. Un retiro listo se cobra cuando lo vienen a buscar: "Cobrar" va
    // primero (y lo deja entregado); "Entregado" queda para el que ya pagó por otro lado.
    final cobrable = pedido.ventaId == null && (estado == EstadoPedido.porHacer || estado == EstadoPedido.listo || estado == EstadoPedido.enCamino);
    final botones = <(String, VoidCallback)>[
      if (cobrable && !forma.esEnvio && estado == EstadoPedido.listo) ('Cobrar', onCobrar),
      for (final p in pasos) (_textoPaso(p), () => onPaso(p)),
      if (cobrable && !(!forma.esEnvio && estado == EstadoPedido.listo)) ('Cobrar', onCobrar),
    ];
    final resumen = lineas.map((l) => '${l.cantidad ?? '${l.gramos} g'} ${l.nombre}').join(' · ');
    return PresionNs(
      key: ValueKey('pedido-${pedido.id}'),
      onTap: onVer,
      etiqueta: 'Pedido ${pedido.numero} de ${pedido.nombreCliente}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(pedido.nombreCliente, maxLines: 1, overflow: TextOverflow.ellipsis, style: estiloNs(18, peso: FontWeight.w600, color: ns.ink))),
                if (pedido.horaEstimada != null)
                  Text(_hora(pedido.horaEstimada!), style: estiloNs(18, peso: FontWeight.w600, color: ns.ink, tabular: true)),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${pedido.numero} · ${CanalPedido.desdeClave(pedido.canal).etiqueta} · ${forma.etiqueta}${pedido.zona == null ? '' : ' · ${pedido.zona}'}',
              style: estiloNs(13, peso: FontWeight.w500, color: ns.mute),
            ),
            const SizedBox(height: 8),
            Text(resumen, maxLines: 2, overflow: TextOverflow.ellipsis, style: estiloNs(15, color: ns.ink)),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  plataNs(totalPedidoCentavos(lineas, costoEnvioCentavos: pedido.costoEnvioCentavos)),
                  style: estiloNs(15, peso: FontWeight.w600, color: ns.ink, tabular: true),
                ),
                if (pedido.ventaId != null || pedido.pagado) ...[
                  const SizedBox(width: 8),
                  Text('· Cobrado', style: estiloNs(14, peso: FontWeight.w600, color: ns.g)),
                ],
              ],
            ),
            if (botones.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  for (var i = 0; i < botones.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: i == 0
                          ? BotonNs.primario(context, botones[i].$1, botones[i].$2, alto: 48, tamanio: 15)
                          : BotonNs.secundario(context, botones[i].$1, botones[i].$2, alto: 48, tamanio: 15),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tomar un pedido del mostrador (o del teléfono): quién es, qué lleva y cómo se lo lleva.
class _HojaNuevoPedido extends StatefulWidget {
  const _HojaNuevoPedido({required this.db, required this.carta, required this.config, required this.usuarioId, this.ahora});

  final AppDatabase db;
  final List<Producto> carta;
  final ConfigPedidos config;
  final int usuarioId;
  final DateTime? ahora;

  @override
  State<_HojaNuevoPedido> createState() => _HojaNuevoPedidoState();
}

class _HojaNuevoPedidoState extends State<_HojaNuevoPedido> {
  final _nombre = TextEditingController();
  final _telefono = TextEditingController();
  final _direccion = TextEditingController();
  final Map<int, int> _cantidades = {};
  bool _porTelefono = false;
  late FormaEntrega _forma = widget.config.formasDisponibles.isEmpty ? FormaEntrega.retiro : widget.config.formasDisponibles.first;
  ZonaEnvio? _zona;
  bool _guardando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _telefono.dispose();
    _direccion.dispose();
    super.dispose();
  }

  List<LineaPedido> get _lineas => [
        for (final p in widget.carta)
          if ((_cantidades[p.id] ?? 0) > 0)
            LineaPedido(gid: p.globalId!, nombre: p.nombre, cantidad: _cantidades[p.id], precioCentavos: p.precioCentavos!),
      ];

  void _sumar(Producto p, int delta) {
    setState(() {
      final n = (_cantidades[p.id] ?? 0) + delta;
      if (n <= 0) {
        _cantidades.remove(p.id);
      } else {
        _cantidades[p.id] = n;
      }
    });
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      await crearPedido(
        widget.db,
        canal: _porTelefono ? CanalPedido.telefono : CanalPedido.mostrador,
        nombreCliente: _nombre.text,
        telefono: _telefono.text.trim().isEmpty ? null : _telefono.text.trim(),
        formaEntrega: _forma,
        direccion: _direccion.text,
        zona: _forma.esEnvio ? _zona : null,
        lineas: _lineas,
        usuarioId: widget.usuarioId,
        ahora: widget.ahora,
      );
      if (mounted) Navigator.pop(context, true);
    } on PedidoIncompleto catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      mostrarAvisoNs(context, e.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final lineas = _lineas;
    final envio = costoEnvioCentavos(_forma, _zona);
    final formas = widget.config.formasDisponibles;
    return HojaNs(
      titulo: 'Nuevo pedido',
      bloques: [
        SegmentoNs(
          key: const Key('nuevo_pedido_canal'),
          opciones: const ['Mostrador', 'Teléfono'],
          indice: _porTelefono ? 1 : 0,
          onCambio: (i) => setState(() => _porTelefono = i == 1),
        ),
        const SizedBox(height: 12),
        CampoNs(key: const Key('nuevo_pedido_nombre'), etiqueta: 'Nombre', controller: _nombre, placeholder: 'A nombre de quién'),
        const SizedBox(height: 10),
        CampoNs(
          key: const Key('nuevo_pedido_telefono'),
          etiqueta: 'Teléfono (para avisarle por WhatsApp)',
          controller: _telefono,
          placeholder: 'Opcional',
          teclado: TextInputType.phone,
        ),
        if (formas.length > 1) ...[
          const SizedBox(height: 14),
          FilaChipsNs(
            chips: [
              for (final f in formas) ChipNs(texto: f.etiqueta, activo: f == _forma, onTap: () => setState(() => _forma = f)),
            ],
          ),
        ],
        if (_forma.esEnvio) ...[
          const SizedBox(height: 10),
          CampoNs(key: const Key('nuevo_pedido_direccion'), etiqueta: 'Dirección', controller: _direccion),
          const SizedBox(height: 10),
          FilaChipsNs(
            chips: [
              for (final z in widget.config.zonas)
                ChipNs(texto: '${z.nombre} · ${plataNs(z.costoCentavos)}', activo: z.nombre == _zona?.nombre, onTap: () => setState(() => _zona = z)),
            ],
          ),
        ],
        const SizedBox(height: 18),
        const SeccionNs('Qué lleva'),
        const SizedBox(height: 8),
        for (final p in widget.carta)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.nombre, style: estiloNs(16, peso: FontWeight.w500, color: ns.ink)),
                      Text(plataNs(p.precioCentavos!), style: estiloNs(14, color: ns.mute, tabular: true)),
                    ],
                  ),
                ),
                StepperNs(
                  key: ValueKey('nuevo_pedido_plato_${p.id}'),
                  cantidad: '${_cantidades[p.id] ?? 0}',
                  onMenos: (_cantidades[p.id] ?? 0) > 0 ? () => _sumar(p, -1) : null,
                  onMas: () => _sumar(p, 1),
                ),
              ],
            ),
          ),
      ],
      botones: [
        BotonNs.primario(
          context,
          lineas.isEmpty ? 'Elegí qué lleva' : 'Tomar pedido · ${plataNs(totalPedidoCentavos(lineas, costoEnvioCentavos: envio))}',
          _guardando || lineas.isEmpty ? null : _guardar,
          habilitado: !_guardando && lineas.isNotEmpty,
        ),
      ],
    );
  }
}

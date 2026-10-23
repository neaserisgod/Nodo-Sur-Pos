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
import '../../servicios/pedidos_bot_nube.dart' show pedidosBotSinCargar;
import '../../servicios/registro_errores.dart' show registrarSiNoEsDeRed;
import '../app_ns.dart';
import '../base_local.dart';
import '../cambios_companion.dart';
import '../emparejamiento.dart';
import '../configurar/pendientes_en_inicio.dart';
import '../kit/kit_ns.dart';
import '../mensaje_error.dart';
import 'pantalla_config_pedidos_ns.dart';

const _diasCortos = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

/// "hoy", "mañana" o el día de la semana, para un pedido programado.
String _diaCorto(DateTime d) {
  final hoy = DateTime.now();
  final dif = DateTime(d.year, d.month, d.day).difference(DateTime(hoy.year, hoy.month, hoy.day)).inDays;
  return dif == 0 ? 'hoy' : dif == 1 ? 'mañana' : _diasCortos[d.weekday - 1];
}

String _hora(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// El texto del botón que lleva al pedido a [estado].
String _textoPaso(EstadoPedido estado) => switch (estado) {
      EstadoPedido.porHacer => 'Aceptar',
      EstadoPedido.rechazado => 'Rechazar',
      EstadoPedido.listo => 'Listo',
      EstadoPedido.enCamino => 'Salió',
      EstadoPedido.entregado => 'Entregado',
      _ => estado.etiqueta,
    };

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

  /// El filtro elegido; null: el primero que tenga pedidos.
  EstadoPedido? _filtro;

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
    pedidosBotSinCargar.addListener(_alCambiarSinCargar);
    _recargar();
  }

  void _alCambiarSinCargar() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    pedidosBotSinCargar.removeListener(_alCambiarSinCargar);
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
      pedidosPorAceptarNs.value = pedidos.where((p) => p.estado == EstadoPedido.porConfirmar.clave).length;
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

  /// "Llegó el pago": la transferencia ya está, el pedido sigue como si recién entrara.
  Future<void> _llegoElPago(PedidoGastronomia pedido) async {
    await registrarPagoAdelantado(_db, pedido.id);
    await _recargar();
    if (mounted) mostrarAvisoNs(context, 'Pago anotado: el pedido ${pedido.numero} sigue');
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
                child: Text(pedido.pagado ? 'Pagado por adelantado' : 'Paga por adelantado: fijate que haya llegado',
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

  DateTime get _ahora => widget.ahora ?? DateTime.now();

  /// Minutos hasta la hora prometida (negativo: atrasado).
  int? _faltan(PedidoGastronomia p) => p.horaEstimada?.difference(_ahora).inMinutes;

  Future<void> _hojaCocina() async {
    await mostrarHojaNs<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setHoja) => HojaNs(
          titulo: 'La cocina',
          texto: 'El bot le dice al cliente cuánto tarda, según esto.',
          bloques: [
            SegmentoNs(
              key: const Key('pedidos_cocina'),
              opciones: const ['Normal', 'Con demora', 'Pausada'],
              indice: EstadoCocina.values.indexOf(_cocina),
              onCambio: (i) async {
                await _cambiarCocina(EstadoCocina.values[i]);
                setHoja(() {});
              },
            ),
            const SizedBox(height: 10),
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
          ],
          botones: [BotonNs.primario(ctx, 'Listo', () => Navigator.pop(ctx))],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final pedidos = _pedidos;
    final porEstado = <EstadoPedido, List<PedidoGastronomia>>{};
    for (final p in pedidos ?? const <PedidoGastronomia>[]) {
      (porEstado[EstadoPedido.desdeClave(p.estado)] ??= []).add(p);
    }
    for (final g in porEstado.values) {
      g.sort((a, b) => (a.horaEstimada ?? _ahora).compareTo(b.horaEstimada ?? _ahora));
    }
    // El filtro arranca en lo primero que pide atención; si el elegido se vacía, se queda (muestra que no hay nada).
    final filtro =
        _filtro ?? _filtros.map((f) => f.$1).firstWhere((e) => (porEstado[e] ?? const []).isNotEmpty, orElse: () => EstadoPedido.porConfirmar);
    final enCocina = porEstado[EstadoPedido.porHacer] ?? const <PedidoGastronomia>[];
    final atrasados = enCocina.where((p) => !p.programado && (_faltan(p) ?? 0) < 0).length;
    final lista = porEstado[filtro] ?? const <PedidoGastronomia>[];
    // Lo mismo en el celular y en la compu: la cabecera, el tablero y los avisos.
    final cabecera = <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_cocina == EstadoCocina.demorada ? _config.minutosDemorada : _config.minutosNormal} min por pedido',
                      style: estiloNs(14, peso: FontWeight.w500, color: ns.mute),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('Pedidos', style: tituloNs(40, track: -0.055, color: ns.ink)),
                    ),
                  ],
                ),
              ),
              _BotonCocina(estado: _cocina, onTap: _hojaCocina),
              const SizedBox(width: 8),
              BotonCircularNs(
                key: const Key('pedidos_nuevo'),
                icono: IconoNs.masMas,
                etiqueta: 'Nuevo pedido',
                onTap: _nuevoPedido,
                tamanio: 48,
                fondo: ns.acento,
                colorIcono: ns.onAcento,
              ),
              const SizedBox(width: 8),
              BotonCircularNs(
                key: const Key('pedidos_configurar'),
                icono: IconoNs.ajustes,
                etiqueta: 'Configurar pedidos',
                onTap: _configurar,
                tamanio: 48,
              ),
            ],
          ),
        ),
        // Un local gastronómico arranca acá: los pasos de "Configurá tu negocio" dejados para después se recuerdan acá (como en la
        // Agenda de servicios).
        const PendientesEnInicio(margenLateral: 0),
        const SizedBox(height: 14),
    ];
    final tablero = // Tablero en mosaicos (mock v5): lo que sale ahora, cuántos esperan que alguien los acepte y cuántos hay en la cocina.
        SizedBox(
          height: 240,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: _SaleAhora(
                  pedido: enCocina.where((p) => !p.programado).firstOrNull,
                  faltan: _faltan,
                  onVer: _verPedido,
                  onFiltrar: () => setState(() => _filtro = EstadoPedido.porHacer),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _Mosaico(
                        key: const Key('pedidos_mosaico_nuevos'),
                        rotulo: 'Nuevos',
                        cifra: (porEstado[EstadoPedido.porConfirmar] ?? const []).length,
                        pie: 'para aceptar',
                        fondo: ns.acento,
                        color: ns.onAcento,
                        onTap: () => setState(() => _filtro = EstadoPedido.porConfirmar),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _Mosaico(
                        rotulo: 'En la cocina',
                        cifra: enCocina.length,
                        pie: atrasados == 0 ? 'todo en hora' : '$atrasados ${atrasados == 1 ? 'atrasado' : 'atrasados'}',
                        colorPie: atrasados == 0 ? null : ns.b,
                        fondo: ns.s,
                        color: ns.ink,
                        onTap: () => setState(() => _filtro = EstadoPedido.porHacer),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
    final avisos = <Widget>[
        if (_cocina == EstadoCocina.pausada) ...[
          const SizedBox(height: 10),
          const InfoNs('Cocina pausada: el bot no toma pedidos. El mostrador sigue.', tono: TonoNs.bad, peso: FontWeight.w600),
        ],
        // Pedidos del bot que no se pudieron poner acá: se dice por qué y se reintentan solos (`pedidos_bot_nube.dart`).
        for (final motivo in pedidosBotSinCargar.value.take(3)) ...[
          const SizedBox(height: 10),
          InfoNs(motivo, tono: TonoNs.warn, icono: IconoNs.alerta),
        ],
    ];
    Widget tarjeta(PedidoGastronomia p) => _TarjetaPedido(
          pedido: p,
          faltan: _faltan(p),
          onVer: () => _verPedido(p),
          onPaso: (nuevo) => _avanzar(p, nuevo),
          onCobrar: () => _cobrar(p),
          onPago: () => _llegoElPago(p),
        );
    // En la compu (menú lateral): cada estado en su columna, uno al lado del otro, como un tablero de cocina. Se ve todo sin
    // cambiar de filtro. En camino y sin pagar aparecen solo si hay alguno.
    if (ConMenuLateralNs.de(context)) {
      final columnas = [
        for (final (estado, texto) in _filtros)
          if (_columnaFija(estado) || (porEstado[estado] ?? const []).isNotEmpty) (estado, texto),
      ];
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...cabecera,
            // Tablero en mosaicos (mock v5): lo que sale ahora, cuántos esperan que alguien los acepte y cuántos hay en la cocina.
            SizedBox(height: 180, child: tablero.child),
            ...avisos,
            const SizedBox(height: 16),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, (estado, texto)) in columnas.indexed) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(
                      child: _Columna(
                        key: ValueKey('pedidos_columna_${estado.clave}'),
                        titulo: texto,
                        pedidos: porEstado[estado] ?? const [],
                        vacio: _vacio(estado),
                        tarjeta: tarjeta,
                        cargando: pedidos == null,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, BarraInferiorNs.espacioReservado - 8),
      children: [
        ...cabecera,
        // Tablero en mosaicos (mock v5): lo que sale ahora, cuántos esperan que alguien los acepte y cuántos hay en la cocina.
        tablero,
        ...avisos,
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              for (final (estado, texto) in _filtros) ...[
                _Filtro(
                  key: ValueKey('pedidos_filtro_${estado.clave}'),
                  texto: texto,
                  cuenta: (porEstado[estado] ?? const []).length,
                  activo: estado == filtro,
                  onTap: () => setState(() => _filtro = estado),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (pedidos != null && lista.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 36, 8, 0),
            child: Column(
              children: [
                Text(
                  _vacio(filtro).$1,
                  textAlign: TextAlign.center,
                  style: tituloNs(26, track: -0.04, color: ns.ink),
                ),
                const SizedBox(height: 6),
                Text(
                  _vacio(filtro).$2,
                  textAlign: TextAlign.center,
                  style: estiloNs(15, color: ns.mute),
                ),
              ],
            ),
          ),
        for (final p in lista) ...[tarjeta(p), const SizedBox(height: 8)],
      ],
    );
  }
}

/// Los filtros de la lista, en el orden en que se trabaja.
const _filtros = [
  (EstadoPedido.porConfirmar, 'Nuevos'),
  (EstadoPedido.porHacer, 'Cocina'),
  (EstadoPedido.listo, 'Listos'),
  (EstadoPedido.enCamino, 'En camino'),
  (EstadoPedido.esperandoPago, 'Sin pagar'),
];

(String, String) _vacio(EstadoPedido filtro) => switch (filtro) {
  EstadoPedido.porConfirmar => ('Nada nuevo.', 'Cuando entre un pedido, por el mostrador o por WhatsApp, aparece acá.'),
  EstadoPedido.porHacer => ('Cocina al día.', 'No hay nada por hacer.'),
  EstadoPedido.listo => ('Nada esperando.', 'Los pedidos listos aparecen acá.'),
  EstadoPedido.enCamino => ('Nadie en la calle.', 'Los envíos que salieron aparecen acá.'),
  _ => ('Todo pagado.', 'Los que pagan con link esperan acá hasta que se acredita.'),
};

/// Las columnas que la compu muestra siempre, aunque estén vacías: lo que se trabaja en cada turno.
bool _columnaFija(EstadoPedido e) => e == EstadoPedido.porConfirmar || e == EstadoPedido.porHacer || e == EstadoPedido.listo;

/// Una columna del tablero de la compu: el estado, cuántos hay y sus pedidos, con su propio scroll.
class _Columna extends StatelessWidget {
  const _Columna({super.key, required this.titulo, required this.pedidos, required this.vacio, required this.tarjeta, required this.cargando});

  final String titulo;
  final List<PedidoGastronomia> pedidos;
  final (String, String) vacio;
  final Widget Function(PedidoGastronomia) tarjeta;
  final bool cargando;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
          child: Row(
            children: [
              Expanded(child: Text(titulo, style: tituloNs(22, track: -0.04, color: ns.ink))),
              Text('${pedidos.length}', style: estiloNs(15, peso: FontWeight.w700, color: ns.mute)),
            ],
          ),
        ),
        Expanded(
          child: pedidos.isEmpty
              ? (cargando
                  ? const SizedBox.shrink()
                  : Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(border: Border.all(color: ns.s2), borderRadius: BorderRadius.circular(22)),
                      alignment: Alignment.topLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(vacio.$1, style: estiloNs(15, peso: FontWeight.w600, color: ns.ink)),
                          const SizedBox(height: 4),
                          Text(vacio.$2, style: estiloNs(14, color: ns.mute)),
                        ],
                      ),
                    ))
              : ListView.separated(
                  itemCount: pedidos.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => tarjeta(pedidos[i]),
                ),
        ),
      ],
    );
  }
}

/// Los pedidos por aceptar, para el globo de la pestaña Pedidos.
final ValueNotifier<int> pedidosPorAceptarNs = ValueNotifier(0);

class _BotonCocina extends StatelessWidget {
  const _BotonCocina({required this.estado, required this.onTap});

  final EstadoCocina estado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final pausada = estado == EstadoCocina.pausada;
    return PresionNs(
      key: const Key('pedidos_boton_cocina'),
      onTap: onTap,
      etiqueta: switch (estado) {
        EstadoCocina.normal => 'Cocina normal',
        EstadoCocina.demorada => 'Cocina con demora',
        EstadoCocina.pausada => 'Cocina pausada',
      },
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: pausada ? ns.b : ns.s, shape: BoxShape.circle),
        child: pausada
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 2; i++) ...[
                    if (i == 1) const SizedBox(width: 5),
                    Container(
                      width: 4,
                      height: 14,
                      decoration: BoxDecoration(color: TokensNs.blanco, borderRadius: BorderRadius.circular(2)),
                    ),
                  ],
                ],
              )
            : Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(color: estado == EstadoCocina.normal ? ns.g : ns.acento, shape: BoxShape.circle),
              ),
      ),
    );
  }
}

class _Mosaico extends StatelessWidget {
  const _Mosaico({
    super.key,
    required this.rotulo,
    required this.cifra,
    required this.pie,
    required this.fondo,
    required this.color,
    required this.onTap,
    this.colorPie,
  });

  final String rotulo;
  final int cifra;
  final String pie;
  final Color fondo;
  final Color color;
  final Color? colorPie;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PresionNs(
      onTap: onTap,
      etiqueta: '$rotulo: $cifra $pie',
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
        decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(28)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              rotulo,
              style: estiloNs(14, peso: FontWeight.w600, color: color.withValues(alpha: 0.8)),
            ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('$cifra', style: tituloNs(36, track: -0.05, color: color)),
              ),
            ),
            Text(
              pie,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: estiloNs(13, peso: colorPie == null ? FontWeight.w500 : FontWeight.w600, color: colorPie ?? color.withValues(alpha: 0.8)),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Sale ahora": el próximo pedido que tiene que salir de la cocina, como una actividad en vivo.
class _SaleAhora extends StatelessWidget {
  const _SaleAhora({required this.pedido, required this.faltan, required this.onVer, required this.onFiltrar});

  final PedidoGastronomia? pedido;
  final int? Function(PedidoGastronomia) faltan;
  final ValueChanged<PedidoGastronomia> onVer;
  final VoidCallback onFiltrar;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final p = pedido;
    const texto = TokensNs.blanco;
    final suave = TokensNs.blanco.withValues(alpha: 0.65);
    final min = p == null ? null : faltan(p);
    final tarde = min != null && min < 0;
    return PresionNs(
      key: const Key('pedidos_sale_ahora'),
      onTap: p == null ? onFiltrar : () => onVer(p),
      etiqueta: p == null ? 'Cocina al día' : 'Sale ahora: ${p.nombreCliente}',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: ns.oscuro ? ns.s2 : ns.hero, borderRadius: BorderRadius.circular(28)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: p == null ? ns.g : (tarde ? ns.b : ns.acento), shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    p == null ? 'Cocina al día' : (tarde ? 'Atrasado' : 'Sale ahora'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: estiloNs(14, peso: FontWeight.w600, color: suave),
                  ),
                ),
              ],
            ),
            if (p == null)
              Text('Nada por hacer.', style: estiloNs(15, color: suave))
            else ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: min == null ? '—' : '${min.abs()}',
                            style: tituloNs(56, track: -0.05, color: tarde ? ns.b : texto),
                          ),
                          TextSpan(
                            text: ' min',
                            style: tituloNs(22, track: -0.03, color: tarde ? ns.b : texto),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Text(tarde ? 'de atraso' : (p.horaEstimada == null ? '' : 'para las ${_hora(p.horaEstimada!)}'), style: estiloNs(13, color: suave)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${p.nombreCliente} · ${p.numero}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: estiloNs(15, peso: FontWeight.w600, color: texto),
                  ),
                  Text(
                    lineasDe(p).map((l) => '${l.cantidad ?? '${l.gramos} g'} ${l.nombre}').join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: estiloNs(13, color: suave),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Filtro extends StatelessWidget {
  const _Filtro({super.key, required this.texto, required this.cuenta, required this.activo, required this.onTap});

  final String texto;
  final int cuenta;
  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return PresionNs(
      onTap: onTap,
      etiqueta: '$texto, $cuenta',
      child: AnimatedContainer(
        duration: sinMovimiento(context) ? Duration.zero : const Duration(milliseconds: 200),
        height: 40,
        padding: const EdgeInsets.fromLTRB(15, 0, 10, 0),
        decoration: BoxDecoration(color: activo ? ns.prim : ns.s, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              texto,
              style: estiloNs(15, peso: FontWeight.w600, color: activo ? ns.onPrim : ns.mute),
            ),
            const SizedBox(width: 7),
            Container(
              constraints: const BoxConstraints(minWidth: 20),
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: activo ? ns.acento : ns.paper, borderRadius: BorderRadius.circular(10)),
              child: Text(
                '$cuenta',
                style: estiloNs(13, peso: FontWeight.w600, color: activo ? ns.onAcento : ns.ink, tabular: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TarjetaPedido extends StatelessWidget {
  const _TarjetaPedido({required this.pedido, required this.faltan, required this.onVer, required this.onPaso, required this.onCobrar, required this.onPago});

  final PedidoGastronomia pedido;
  final int? faltan;
  final VoidCallback onVer;
  final ValueChanged<EstadoPedido> onPaso;
  final VoidCallback onCobrar;

  /// Llegó el pago adelantado (una transferencia que el local ya vio).
  final VoidCallback onPago;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final estado = EstadoPedido.desdeClave(pedido.estado);
    final forma = FormaEntrega.desdeClave(pedido.formaEntrega);
    final lineas = lineasDe(pedido);
    final pasos = siguientesEstados(estado, forma);
    // Se cobra lo que ya se aceptó y todavía no tiene venta. Un retiro listo se cobra cuando lo vienen a buscar: "Cobrar" va
    // primero (y lo deja entregado); "Entregado" queda para el que ya pagó por otro lado.
    final cobrado = pedido.ventaId != null || pedido.pagado;
    final cobrable = pedido.ventaId == null && (estado == EstadoPedido.porHacer || estado == EstadoPedido.listo || estado == EstadoPedido.enCamino);
    // Un botón principal por pedido; el resto, secundarios. Rechazar va como texto, para no tocarlo sin querer.
    final principal = <(String, VoidCallback)>[
      if (estado == EstadoPedido.esperandoPago) ('Llegó el pago', onPago),
      if (cobrable && !forma.esEnvio && estado == EstadoPedido.listo) ('Cobrar', onCobrar),
      for (final p in pasos)
        if (p != EstadoPedido.rechazado) (_textoPaso(p), () => onPaso(p)),
      if (cobrable && !(!forma.esEnvio && estado == EstadoPedido.listo)) ('Cobrar', onCobrar),
    ];
    final rechazar = pasos.contains(EstadoPedido.rechazado);
    final (subHora, colorSub) = switch (estado) {
      EstadoPedido.porConfirmar => ('Nuevo', ns.w),
      EstadoPedido.enCamino => ('En la calle', ns.mute),
      EstadoPedido.esperandoPago => ('Sin pagar', ns.w),
      _ when pedido.programado && pedido.horaEstimada != null => (_diaCorto(pedido.horaEstimada!), ns.w),
      _ when faltan == null => ('', ns.mute),
      _ when faltan! < 0 => ('${-faltan!} min tarde', ns.b),
      _ => ('en $faltan min', ns.mute),
    };
    final meta = [CanalPedido.desdeClave(pedido.canal).etiqueta, forma.esEnvio ? 'Envío a ${pedido.zona ?? ''}'.trim() : 'Retira'].join(' · ');
    return PresionNs(
      key: ValueKey('pedido-${pedido.id}'),
      onTap: onVer,
      etiqueta: 'Pedido ${pedido.numero} de ${pedido.nombreCliente}',
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pedido.nombreCliente,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: estiloNs(19, peso: FontWeight.w600, color: ns.ink),
                      ),
                      const SizedBox(height: 3),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${pedido.numero} · $meta'),
                            if (cobrado)
                              TextSpan(
                                text: pedido.pagado && pedido.ventaId == null ? ' · Pagado' : ' · Cobrado',
                                style: TextStyle(color: ns.g, fontWeight: FontWeight.w600),
                              ),
                          ],
                        ),
                        style: estiloNs(14, color: ns.mute),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (pedido.horaEstimada != null) Text(_hora(pedido.horaEstimada!), style: tituloNs(26, track: -0.04, color: ns.ink)),
                    if (subHora.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subHora,
                        style: estiloNs(13, peso: FontWeight.w600, color: colorSub),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // La comanda: cada plato en su renglón, con la cantidad bien visible.
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(color: ns.paper, borderRadius: BorderRadius.circular(18)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final l in lineas)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          SizedBox(
                            width: 34,
                            child: Text(l.cantidad != null ? '${l.cantidad}' : '${l.gramos} g', style: tituloNs(18, track: -0.02, color: ns.ink)),
                          ),
                          Expanded(
                            child: Text(l.nombre, style: estiloNs(16, color: ns.ink)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (pedido.nota != null && pedido.nota!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                pedido.nota!.trim(),
                style: estiloNs(14, peso: FontWeight.w600, color: ns.w),
              ),
            ],
            if (estado == EstadoPedido.esperandoPago) ...[
              const SizedBox(height: 10),
              Text('Se cocina cuando llegue el pago. Si ya lo viste, tocá "Llegó el pago".', style: estiloNs(14, color: ns.mute)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    plataNs(totalPedidoCentavos(lineas, costoEnvioCentavos: pedido.costoEnvioCentavos)),
                    style: tituloNs(21, track: -0.03, color: ns.ink),
                  ),
                ),
                if (rechazar)
                  BotonNs(
                    texto: 'Rechazar',
                    onTap: () => onPaso(EstadoPedido.rechazado),
                    alto: 48,
                    tamanio: 15,
                    fondo: Colors.transparent,
                    color: ns.mute,
                    rellenar: false,
                    paddingH: 10,
                  ),
                for (var i = 0; i < principal.length; i++) ...[
                  const SizedBox(width: 6),
                  i == 0
                      ? (estado == EstadoPedido.porConfirmar
                            ? BotonNs(
                                texto: principal[i].$1,
                                onTap: principal[i].$2,
                                alto: 48,
                                tamanio: 16,
                                fondo: ns.acento,
                                color: ns.onAcento,
                                rellenar: false,
                                paddingH: 22,
                              )
                            : BotonNs(
                                texto: principal[i].$1,
                                onTap: principal[i].$2,
                                alto: 48,
                                tamanio: 16,
                                fondo: ns.prim,
                                color: ns.onPrim,
                                rellenar: false,
                                paddingH: 22,
                              ))
                      : BotonNs(
                          texto: principal[i].$1,
                          onTap: principal[i].$2,
                          alto: 48,
                          tamanio: 16,
                          fondo: ns.paper,
                          color: ns.ink,
                          rellenar: false,
                          paddingH: 18,
                        ),
                ],
              ],
            ),
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

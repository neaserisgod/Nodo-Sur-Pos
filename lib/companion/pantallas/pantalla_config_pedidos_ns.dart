// Más › Configuración › Pedidos, o el engranaje de Pedidos (`REGLAS-NEGOCIO.md` §22): cómo trabaja el local los pedidos. Qué
// entregas tiene (retiro, cadete propio, servicio de reparto, todas opcionales), las zonas de envío con su costo y su demora,
// cómo se cobra, cuánto tarda la cocina normal y con demora, y si lo de WhatsApp entra solo. El bot lo toma de acá.

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/repositorio_pedidos_gastronomia.dart';
import '../../domain/dinero.dart' show parsearARS;
import '../../domain/pedido_gastronomico.dart';
import '../base_local.dart';
import '../kit/kit_ns.dart';
import '../mensaje_error.dart';

class PantallaConfigPedidosNs extends StatefulWidget {
  /// [db] es para tests.
  const PantallaConfigPedidosNs({super.key, this.db});
  final AppDatabase? db;

  @override
  State<PantallaConfigPedidosNs> createState() => _PantallaConfigPedidosNsState();
}

class _ZonaEditable {
  _ZonaEditable([ZonaEnvio? z])
      : nombre = TextEditingController(text: z?.nombre ?? ''),
        costo = TextEditingController(text: z == null ? '' : '${z.costoCentavos ~/ 100}'),
        demora = TextEditingController(text: z == null ? '' : '${z.demoraExtraMin}');
  final TextEditingController nombre;
  final TextEditingController costo;
  final TextEditingController demora;

  void dispose() {
    nombre.dispose();
    costo.dispose();
    demora.dispose();
  }
}

class _PantallaConfigPedidosNsState extends State<PantallaConfigPedidosNs> {
  late final AppDatabase _db = widget.db ?? baseLocalCompanion();
  bool _cargada = false;
  bool _retiro = true;
  bool _cadete = false;
  bool _reparto = false;
  bool _automatica = false;
  bool _catalogo = false;
  ModoPagoPedido _pago = ModoPagoPedido.alEntregar;
  final _normal = TextEditingController();
  final _demorada = TextEditingController();
  final List<_ZonaEditable> _zonas = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    configPedidosActual(_db).then(_mostrar, onError: (Object e) {
      if (!mounted) return;
      _mostrar(const ConfigPedidos());
      setState(() => _error = 'No se pudo leer la configuración: ${mensajeDeError(e)}');
    });
  }

  void _mostrar(ConfigPedidos c) {
    if (!mounted) return;
    setState(() {
      _cargada = true;
      _retiro = c.retiro;
      _cadete = c.cadetePropio;
      _reparto = c.servicioReparto;
      _automatica = c.confirmacionAutomatica;
      _catalogo = c.catalogoWhatsapp;
      _pago = c.pago;
      _normal.text = '${c.minutosNormal}';
      _demorada.text = '${c.minutosDemorada}';
      _zonas.addAll([for (final z in c.zonas) _ZonaEditable(z)]);
    });
  }

  @override
  void dispose() {
    _normal.dispose();
    _demorada.dispose();
    for (final z in _zonas) {
      z.dispose();
    }
    super.dispose();
  }

  bool get _hayEnvio => _cadete || _reparto;

  Future<void> _guardar() async {
    if (!_retiro && !_hayEnvio) return setState(() => _error = 'Prendé al menos una forma de entrega.');
    final normal = int.tryParse(_normal.text.trim()), demorada = int.tryParse(_demorada.text.trim());
    if (normal == null || normal <= 0 || demorada == null || demorada <= 0) {
      return setState(() => _error = 'Los minutos de la cocina van en números: por ejemplo 30 y 60.');
    }
    final zonas = <ZonaEnvio>[];
    for (final z in _zonas) {
      final nombre = z.nombre.text.trim();
      if (nombre.isEmpty && z.costo.text.trim().isEmpty) continue; // una fila vacía se descarta
      if (nombre.isEmpty) return setState(() => _error = 'A una zona le falta el nombre.');
      int costo;
      try {
        costo = parsearARS(z.costo.text.trim());
      } on FormatException {
        return setState(() => _error = 'El costo de envío de "$nombre" va en pesos: por ejemplo 1500.');
      }
      if (costo < 0) return setState(() => _error = 'El costo de envío de "$nombre" no puede ser negativo.');
      final demora = z.demora.text.trim().isEmpty ? 0 : int.tryParse(z.demora.text.trim());
      if (demora == null || demora < 0) return setState(() => _error = 'La demora de "$nombre" va en minutos.');
      zonas.add(ZonaEnvio(nombre: nombre, costoCentavos: costo, demoraExtraMin: demora));
    }
    if (_hayEnvio && zonas.isEmpty) return setState(() => _error = 'Para hacer envíos cargá al menos una zona con su costo.');
    try {
      await guardarConfigPedidos(
        _db,
        ConfigPedidos(
          retiro: _retiro,
          cadetePropio: _cadete,
          servicioReparto: _reparto,
          zonas: zonas,
          pago: _pago,
          confirmacionAutomatica: _automatica,
          catalogoWhatsapp: _catalogo,
          minutosNormal: normal,
          minutosDemorada: demorada,
        ),
      );
      if (!mounted) return;
      mostrarAvisoNs(context, 'Pedidos guardado');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo guardar: ${mensajeDeError(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Scaffold(
      backgroundColor: ns.paper,
      body: SafeArea(
        child: !_cargada
            ? const Padding(padding: EdgeInsets.all(margenNs), child: EsqueletoListaNs())
            : ListView(
                padding: const EdgeInsets.fromLTRB(margenNs, 8, margenNs, 32),
                children: [
                  CabeceraSubNs(titulo: 'Pedidos', onVolver: () => Navigator.of(context).pop()),
                  const SizedBox(height: 8),
                  Text('Lo usan la lista de pedidos y el bot de WhatsApp.', style: estiloNs(15, color: ns.mute)),
                  const SizedBox(height: 18),
                  const SeccionNs('Cómo se entrega'),
                  const SizedBox(height: 8),
                  InterruptorNs(
                    key: const Key('pedidos_retiro'),
                    etiqueta: 'Retiro en el local',
                    encendido: _retiro,
                    onCambio: (v) => setState(() => _retiro = v),
                  ),
                  const SizedBox(height: 8),
                  InterruptorNs(
                    key: const Key('pedidos_cadete'),
                    etiqueta: 'Envío con cadete propio',
                    encendido: _cadete,
                    onCambio: (v) => setState(() => _cadete = v),
                  ),
                  const SizedBox(height: 8),
                  InterruptorNs(
                    key: const Key('pedidos_reparto'),
                    etiqueta: 'Envío con servicio de reparto',
                    descripcion: 'Una cadetería o mensajería de afuera',
                    encendido: _reparto,
                    onCambio: (v) => setState(() => _reparto = v),
                  ),
                  if (_hayEnvio) ...[
                    const SizedBox(height: 22),
                    const SeccionNs('Zonas de envío'),
                    const SizedBox(height: 6),
                    Text('Lo que se le cobra al cliente por llevarlo y cuánto tarda de más. Valen para los dos envíos.',
                        style: estiloNs(14, color: ns.mute)),
                    const SizedBox(height: 10),
                    for (var i = 0; i < _zonas.length; i++) ...[
                      Row(
                        children: [
                          Expanded(flex: 3, child: CampoNs(key: ValueKey('zona-nombre-$i'), etiqueta: 'Zona', controller: _zonas[i].nombre, placeholder: 'Centro')),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: CampoNs(key: ValueKey('zona-costo-$i'), etiqueta: 'Envío \$', controller: _zonas[i].costo, placeholder: '1500', teclado: TextInputType.number, formatos: soloDigitosNs),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: CampoNs(key: ValueKey('zona-demora-$i'), etiqueta: '+ min', controller: _zonas[i].demora, placeholder: '15', teclado: TextInputType.number, formatos: soloDigitosNs),
                          ),
                          const SizedBox(width: 6),
                          BotonCircularNs(
                            icono: IconoNs.papelera,
                            etiqueta: 'Sacar la zona',
                            tamanio: 40,
                            tamanioIcono: 18,
                            onTap: () => setState(() => _zonas.removeAt(i).dispose()),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    BotonNs.secundario(context, '+ Agregar zona', () => setState(() => _zonas.add(_ZonaEditable())), alto: 48, tamanio: 15),
                  ],
                  const SizedBox(height: 22),
                  const SeccionNs('Cómo se cobra'),
                  const SizedBox(height: 8),
                  SegmentoNs(
                    key: const Key('pedidos_pago'),
                    opciones: const ['Al entregar', 'Adelantado', 'Que elija'],
                    indice: ModoPagoPedido.values.indexOf(_pago),
                    onCambio: (i) => setState(() => _pago = ModoPagoPedido.values[i]),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    switch (_pago) {
                      ModoPagoPedido.alEntregar => 'Se cobra al retirar, o al recibir el envío.',
                      ModoPagoPedido.adelantado => 'El bot manda el link de Mercado Pago y el pedido entra cuando pagan.',
                      ModoPagoPedido.aElegir => 'El cliente elige si paga ahora por Mercado Pago o al recibir.',
                    },
                    style: estiloNs(14, color: ns.mute),
                  ),
                  const SizedBox(height: 22),
                  const SeccionNs('Cuánto tarda la cocina'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: CampoNs(key: const Key('pedidos_min_normal'), etiqueta: 'Normal (min)', controller: _normal, teclado: TextInputType.number, formatos: soloDigitosNs)),
                      const SizedBox(width: 10),
                      Expanded(child: CampoNs(key: const Key('pedidos_min_demora'), etiqueta: 'Con demora (min)', controller: _demorada, teclado: TextInputType.number, formatos: soloDigitosNs)),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const SeccionNs('Pedidos de WhatsApp'),
                  const SizedBox(height: 8),
                  InterruptorNs(
                    key: const Key('pedidos_automatica'),
                    etiqueta: 'Entran solos',
                    descripcion: _automatica ? 'Van directo a "por hacer".' : 'Esperan que alguien del local los acepte.',
                    encendido: _automatica,
                    onCambio: (v) => setState(() => _automatica = v),
                  ),
                  const SizedBox(height: 10),
                  InterruptorNs(
                    key: const Key('pedidos_catalogo'),
                    etiqueta: 'Tengo catálogo de WhatsApp Business',
                    descripcion: _catalogo
                        ? 'El bot manda el link de tu catálogo y toma los pedidos del carrito. Los platos los cargás vos en WhatsApp Business, con el mismo nombre que en la carta.'
                        : 'El bot manda la carta escrita.',
                    encendido: _catalogo,
                    onCambio: (v) => setState(() => _catalogo = v),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
                  ],
                  const SizedBox(height: 18),
                  BotonNs.primario(context, 'Guardar', _guardar, icono: IconoNs.tilde),
                ],
              ),
      ),
    );
  }
}

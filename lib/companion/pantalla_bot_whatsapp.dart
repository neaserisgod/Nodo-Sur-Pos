// Bot de WhatsApp (Más › Negocio; `docs/PLAN-BOT.md`, El dueño, 2026-10-09): si anda, su configuración y cómo instalarlo en un
// celular. Solo aparece si el negocio tiene un plan con bot. Cualquiera ve si anda; la configuración y la instalación, solo el
// dueño o un encargado (el sitio decide quién, `puedeConfigurar`).
//
// El nombre y el rubro NO se cargan acá: salen de Configuración (Regla 3, un solo lugar para cada dato). Lo que se guarda pasa
// por las mismas reglas que el bot al arrancar (`problemasConfigBot`): si el bot la rechazara seguiría con la anterior y el
// cambio no se vería nunca.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/bot_whatsapp.dart';
import '../domain/plantillas_rubro.dart';
import '../servicios/acceso_bot.dart';
import 'cliente_companion.dart' show ConfiguracionNegocioCompanion;
import 'kit/kit_ns.dart';
import 'mensaje_error.dart';
import 'servicio_companion.dart';

class PantallaBotWhatsApp extends StatefulWidget {
  const PantallaBotWhatsApp({super.key, required this.acceso, required this.servicio, this.alElegirRubro, this.ahora});

  final AccesoBot acceso;
  final ServicioCompanion servicio;

  /// Abre Configuración › Tu negocio para elegir el rubro. Null = solo se avisa.
  final VoidCallback? alElegirRubro;
  final DateTime Function()? ahora;

  @override
  State<PantallaBotWhatsApp> createState() => _PantallaBotWhatsAppState();
}

/// Cuánto se calla el bot en un chat cuando contesta una persona (minutos).
const _pausas = [15, 30, 60, 120, 240];

const _nombresDia = {
  'lunes': 'Lunes',
  'martes': 'Martes',
  'miercoles': 'Miércoles',
  'jueves': 'Jueves',
  'viernes': 'Viernes',
  'sabado': 'Sábado',
  'domingo': 'Domingo',
};

class _PantallaBotWhatsAppState extends State<PantallaBotWhatsApp> {
  bool _cargando = true;
  String? _errorCarga;
  EstadoBot? _estado;
  ConfiguracionNegocioCompanion? _negocio;
  Map<String, dynamic>? _anterior;

  final _numeroBot = TextEditingController();
  final _numeroAvisos = TextEditingController();
  final _direccion = TextEditingController();
  final Map<String, ({TextEditingController desde, TextEditingController hasta})> _horas = {};
  final Map<String, bool> _abierto = {};
  int _pausa = ConfigBotEditable.porDefecto.pausaMinutos;

  List<String> _problemas = const [];
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _numeroBot.dispose();
    _numeroAvisos.dispose();
    _direccion.dispose();
    for (final h in _horas.values) {
      h.desde.dispose();
      h.hasta.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final estado = await widget.acceso.estado();
      ConfiguracionNegocioCompanion? negocio;
      Map<String, dynamic>? anterior;
      if (estado != null && estado.tieneBot && estado.puedeConfigurar) {
        negocio = await widget.servicio.configuracionNegocio();
        anterior = (await widget.acceso.config()).config;
      }
      _llenar(configBotDesdeJson(anterior));
      if (mounted) {
        setState(() {
          _estado = estado;
          _negocio = negocio;
          _anterior = anterior;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _errorCarga = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _llenar(ConfigBotEditable c) {
    _numeroBot.text = c.numeroBot.isEmpty ? '' : _legible(c.numeroBot);
    _numeroAvisos.text = c.numeroAvisos.isEmpty ? '' : _legible(c.numeroAvisos);
    _direccion.text = c.direccion;
    for (final d in diasBot) {
      final f = c.horarios[d];
      final porDefecto = ConfigBotEditable.porDefecto.horarios[d] ?? (desde: '09:00', hasta: '13:00');
      _horas[d] = (desde: TextEditingController(text: f?.desde ?? porDefecto.desde), hasta: TextEditingController(text: f?.hasta ?? porDefecto.hasta));
      _abierto[d] = f != null;
    }
    _pausa = c.pausaMinutos;
  }

  /// "5492944123456" → "2944 123456": como lo escribe cualquiera (se vuelve a normalizar al guardar).
  static String _legible(String n) => n.startsWith('549') && n.length == 13 ? '${n.substring(3, 7)} ${n.substring(7)}' : n;

  ConfigBotEditable get _editada => ConfigBotEditable(
    numeroBot: _numeroBot.text,
    numeroAvisos: _numeroAvisos.text,
    direccion: _direccion.text,
    horarios: {
      for (final d in diasBot) d: _abierto[d] == true ? (desde: _horas[d]!.desde.text.trim(), hasta: _horas[d]!.hasta.text.trim()) : null,
    },
    pausaMinutos: _pausa,
  );

  Future<void> _guardar() async {
    final negocio = _negocio;
    if (negocio == null) return;
    final c = _editada;
    final problemas = problemasConfigBot(c, nombreNegocio: negocio.nombreComercio, rubro: negocio.rubro);
    setState(() => _problemas = problemas);
    if (problemas.isNotEmpty) return;
    setState(() => _guardando = true);
    try {
      final config = configBotParaGuardar(c, nombreNegocio: negocio.nombreComercio, rubro: negocio.rubro!, anterior: _anterior);
      await widget.acceso.guardarConfig(config);
      _anterior = config;
      if (mounted) mostrarAvisoNs(context, 'Guardado. El bot lo toma solo, sin reiniciarlo.');
    } catch (e) {
      if (mounted) setState(() => _problemas = [mensajeDeError(e)]);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _copiarComando() async {
    await Clipboard.setData(const ClipboardData(text: comandoInstalarBot));
    if (mounted) mostrarAvisoNs(context, 'Comando copiado. Pegalo en Termux.');
  }

  Widget _seccion(String texto) => Padding(padding: const EdgeInsets.only(top: 22, bottom: 10), child: SeccionNs(texto));

  Widget _salud(EstadoBot e) {
    final ahora = (widget.ahora ?? DateTime.now)();
    final ultima = e.bots.map((b) => b.ultimaSenal).whereType<DateTime>().fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    String hora(DateTime t) => '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return switch (saludDelBot(e, ahora)) {
      SaludBot.anda => InfoNs('Andando. Última señal: ${hora(ultima!)}.', key: const Key('bot_salud'), tono: TonoNs.good),
      SaludBot.sinSenal => InfoNs(
        'Sin señal desde ${hora(ultima!)}. Revisá que el celular del bot esté prendido, con internet y con Termux abierto.',
        key: const Key('bot_salud'),
        tono: TonoNs.warn,
      ),
      SaludBot.sinBot => const InfoNs('Todavía no hay un bot instalado. Abajo están los pasos.', key: Key('bot_salud')),
    };
  }

  Widget _dia(String d) {
    final ns = context.ns;
    final abierto = _abierto[d] == true;
    return Padding(
      key: Key('bot_dia_$d'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InterruptorNs(
            etiqueta: _nombresDia[d]!,
            descripcion: abierto ? null : 'Cerrado',
            encendido: abierto,
            onCambio: (v) => setState(() {
              _abierto[d] = v;
              _problemas = const [];
            }),
          ),
          if (abierto)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(child: CampoNs(etiqueta: 'Abre', controller: _horas[d]!.desde, placeholder: '09:00', teclado: TextInputType.datetime)),
                  const SizedBox(width: 8),
                  Expanded(child: CampoNs(etiqueta: 'Cierra', controller: _horas[d]!.hasta, placeholder: '20:00', teclado: TextInputType.datetime)),
                ],
              ),
            ),
          if (!abierto) Divider(height: 1, color: ns.s2),
        ],
      ),
    );
  }

  List<Widget> _configuracion() {
    final negocio = _negocio!;
    final rubro = negocio.rubro == null ? null : PlantillaRubro.desdeClave(negocio.rubro!);
    return [
      _seccion('El negocio'),
      InfoNs(
        '${negocio.nombreComercio.trim().isEmpty ? 'Sin nombre' : negocio.nombreComercio.trim()} · ${rubro?.nombre ?? 'Rubro sin elegir'}',
        key: const Key('bot_negocio'),
      ),
      if (rubro == null) ...[
        const SizedBox(height: 8),
        const InfoNs('El bot atiende según el rubro: elegilo en Configuración › Tu negocio.', tono: TonoNs.warn),
        if (widget.alElegirRubro != null) ...[
          const SizedBox(height: 8),
          KeyedSubtree(key: const Key('bot_elegir_rubro'), child: BotonNs.secundario(context, 'Elegir el rubro', widget.alElegirRubro)),
        ],
      ],
      if (negocio.nombreComercio.trim().isEmpty) ...[
        const SizedBox(height: 8),
        const InfoNs('El bot se presenta con el nombre del comercio: cargalo en Configuración de la PC.', tono: TonoNs.warn),
      ],
      _seccion('Números'),
      KeyedSubtree(
        key: const Key('bot_numero'),
        child: CampoNs(etiqueta: 'WhatsApp del bot (el del local)', controller: _numeroBot, placeholder: 'Ej: 2944 123456', teclado: TextInputType.phone),
      ),
      const SizedBox(height: 10),
      KeyedSubtree(
        key: const Key('bot_avisos'),
        child: CampoNs(etiqueta: 'Tu WhatsApp, para los avisos', controller: _numeroAvisos, placeholder: 'Otro número que el del bot', teclado: TextInputType.phone),
      ),
      const SizedBox(height: 10),
      KeyedSubtree(
        key: const Key('bot_direccion'),
        child: CampoNs(etiqueta: 'Dirección (para "¿dónde están?")', controller: _direccion, placeholder: 'Ej: Mitre 123'),
      ),
      _seccion('Horarios'),
      for (final d in diasBot) _dia(d),
      _seccion('Cuando contestás vos'),
      Text('El bot se calla en ese chat durante:', style: estiloNs(14, color: context.ns.mute)),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final m in {..._pausas, _pausa}.toList()..sort())
            ChipNs(key: Key('bot_pausa_$m'), texto: m < 60 ? '$m min' : (m % 60 == 0 ? '${m ~/ 60} h' : '$m min'), activo: _pausa == m, onTap: () => setState(() => _pausa = m)),
        ],
      ),
      if (_problemas.isNotEmpty) ...[
        const SizedBox(height: 14),
        for (final p in _problemas)
          Padding(padding: const EdgeInsets.only(bottom: 6), child: InfoNs(p, tono: TonoNs.bad, icono: IconoNs.alertaCirculo)),
      ],
      const SizedBox(height: 12),
      KeyedSubtree(
        key: const Key('bot_guardar'),
        child: BotonNs.primario(context, _guardando ? 'Guardando…' : 'Guardar', _guardando ? null : _guardar, habilitado: !_guardando),
      ),
    ];
  }

  List<Widget> _instalar() {
    final ns = context.ns;
    const pasos = [
      'En el celular que va a quedar con el bot, instalá Termux, Termux:Boot y Termux:API desde F-Droid. Abrí Termux:Boot una vez.',
      'En Termux, pegá el comando de abajo y tocá Enter.',
      'Se abre el navegador: entrá con tu cuenta de Google y elegí el negocio.',
      'Aparece un código. En el celular con el WhatsApp del local: Dispositivos vinculados › Vincular con el número de teléfono, y escribilo.',
      'Listo: queda andando y arranca solo al prender el celular. Para que Android no lo cierre: Ajustes › Apps › Termux › Batería › Sin restricciones.',
    ];
    return [
      _seccion('Instalar el bot en un celular'),
      for (var i = 0; i < pasos.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 26, child: Text('${i + 1}.', style: estiloNs(15, peso: FontWeight.w600, color: ns.ink))),
              Expanded(child: Text(pasos[i], style: estiloNs(15, color: ns.ink))),
            ],
          ),
        ),
      Container(
        key: const Key('bot_comando'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(18)),
        child: SelectableText(comandoInstalarBot, style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: ns.ink)),
      ),
      const SizedBox(height: 10),
      KeyedSubtree(key: const Key('bot_copiar'), child: BotonNs.secundario(context, 'Copiar el comando', _copiarComando)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final e = _estado;
    return PaginaNs(
      titulo: 'Bot de WhatsApp',
      cuerpo: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                if (_errorCarga != null)
                  InfoNs(_errorCarga!, key: const Key('bot_error'), tono: TonoNs.bad)
                else if (e == null)
                  const InfoNs('Para ver el bot, vinculá este celular a la cuenta del negocio (Más › Cuenta).')
                else if (!e.tieneBot)
                  const InfoNs('El negocio no tiene un plan con el bot de WhatsApp.')
                else ...[
                  _salud(e),
                  if (e.puedeConfigurar) ...[..._configuracion(), ..._instalar()] else ...[
                    const SizedBox(height: 12),
                    const InfoNs('La configuración y la instalación las hace el dueño o un encargado.'),
                  ],
                ],
                const SizedBox(height: 16),
              ],
            ),
    );
  }
}

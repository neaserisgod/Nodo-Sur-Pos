// "En este celular" dentro de Bot de WhatsApp, en Nodo Sur Servicios (El dueño, 2026-10-10, `docs/PLAN-APP-SERVICIOS.md`): el bot
// corre adentro de la app, sin Termux. Acá se enciende y se apaga, se ve si está conectado y, la primera vez, el código para
// vincularlo con el WhatsApp del local. Lo que pasa después ya no depende de esta pantalla: Android lo mantiene andando.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/bot_en_celular.dart';
import '../../servicios/bot_en_celular.dart';
import '../kit/kit_ns.dart';

class SeccionBotEnCelularNs extends StatefulWidget {
  const SeccionBotEnCelularNs({super.key, required this.bot, required this.numeroBot, this.ahora});

  final BotEnCelular bot;

  /// El WhatsApp del local, ya normalizado (`5492944…`). Null si falta o está mal escrito.
  final String? numeroBot;
  final DateTime Function()? ahora;

  @override
  State<SeccionBotEnCelularNs> createState() => _SeccionBotEnCelularNsState();
}

class _SeccionBotEnCelularNsState extends State<SeccionBotEnCelularNs> {
  bool _encendido = false;
  EstadoBotLocal? _estado;
  bool _sinRestricciones = true;
  bool _trabajando = false;
  String? _error;
  bool _verRegistro = false;
  List<String> _registro = const [];
  Timer? _vuelta;

  @override
  void initState() {
    super.initState();
    unawaited(_leer());
    // Mientras se mira la pantalla: el código aparece y el estado cambia solos.
    _vuelta = Timer.periodic(const Duration(seconds: 2), (_) => _leer());
  }

  @override
  void dispose() {
    _vuelta?.cancel();
    super.dispose();
  }

  Future<void> _leer() async {
    final encendido = await widget.bot.encendido();
    final estado = await widget.bot.leerEstado();
    final sinRestricciones = await widget.bot.sinRestriccionesDeBateria();
    final registro = _verRegistro ? await widget.bot.ultimasLineas() : _registro;
    if (!mounted) return;
    setState(() {
      _encendido = encendido;
      _estado = estado;
      _sinRestricciones = sinRestricciones;
      _registro = registro;
    });
  }

  Future<void> _hacer(Future<String?> Function() accion) async {
    setState(() {
      _trabajando = true;
      _error = null;
    });
    final problema = await accion();
    if (!mounted) return;
    setState(() {
      _trabajando = false;
      _error = problema;
    });
    await _leer();
  }

  Future<void> _encender() async {
    final numero = widget.numeroBot;
    if (numero == null) {
      setState(() => _error = 'Cargá arriba el WhatsApp del local y guardá: es el número que va a atender el bot.');
      return;
    }
    await _hacer(() => widget.bot.encender(numero: numero));
  }

  Future<void> _apagar() async {
    final seguro = await mostrarHojaNs<bool>(
      context,
      builder: (ctx) => HojaNs(
        titulo: '¿Apagar el bot?',
        texto: 'Deja de contestar los mensajes hasta que lo vuelvas a encender. La vinculación con WhatsApp queda guardada.',
        botones: [
          BotonNs.primario(ctx, 'Apagar', () => Navigator.of(ctx).pop(true)),
          BotonNs.secundario(ctx, 'Volver', () => Navigator.of(ctx).pop(false)),
        ],
      ),
    );
    if (seguro != true) return;
    await _hacer(() async {
      await widget.bot.apagar();
      return null;
    });
  }

  Future<void> _vincularDeNuevo() async {
    final numero = widget.numeroBot;
    if (numero == null) {
      setState(() => _error = 'Cargá arriba el WhatsApp del local y guardá.');
      return;
    }
    await _hacer(() => widget.bot.vincularDeNuevo(numero: numero));
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final ahora = (widget.ahora ?? DateTime.now)();
    final fase = faseDelBot(encendido: _encendido, estado: _estado);
    final (tono, icono) = switch (fase) {
      FaseBot.conectado => (TonoNs.good, IconoNs.tilde),
      FaseBot.apagado => (TonoNs.neutro, IconoNs.celular),
      FaseBot.conectando => (TonoNs.info, IconoNs.reloj),
      FaseBot.vincular || FaseBot.desvinculado => (TonoNs.warn, IconoNs.alertaCirculo),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.only(top: 22, bottom: 10), child: SeccionNs('En este celular')),
        InfoNs(textoDelBot(fase, _estado, ahora), key: const Key('bot_celular_estado'), tono: tono, icono: icono),
        if (fase == FaseBot.vincular && _estado?.codigo != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(22)),
            child: Column(
              children: [
                Text('Código para vincular', style: estiloNs(14, color: ns.mute)),
                const SizedBox(height: 6),
                SelectableText(
                  codigoLegible(_estado!.codigo!),
                  key: const Key('bot_celular_codigo'),
                  style: estiloNs(34, peso: FontWeight.w700, color: ns.ink).copyWith(letterSpacing: 3),
                ),
                const SizedBox(height: 8),
                Text(
                  'En el celular con el WhatsApp del local: Ajustes › Dispositivos vinculados › Vincular un dispositivo › '
                  'Vincular con el número de teléfono, y escribí este código. Si vence, aparece uno nuevo acá solo.',
                  textAlign: TextAlign.center,
                  style: estiloNs(14, color: ns.ink),
                ),
                const SizedBox(height: 10),
                BotonNs.secundario(context, 'Copiar el código', () {
                  Clipboard.setData(ClipboardData(text: _estado!.codigo!));
                  mostrarAvisoNs(context, 'Código copiado');
                }, alto: 44),
              ],
            ),
          ),
        ],
        if (!_sinRestricciones && _encendido) ...[
          const SizedBox(height: 10),
          const InfoNs(
            'Para que Android no frene al bot con la pantalla apagada, dejá que la app corra sin restricciones de batería.',
            tono: TonoNs.warn,
            icono: IconoNs.alertaCirculo,
          ),
          const SizedBox(height: 8),
          KeyedSubtree(
            key: const Key('bot_celular_bateria'),
            child: BotonNs.secundario(context, 'Permitir en segundo plano', () async {
              await widget.bot.pedirSinRestriccionesDeBateria();
              await Future<void>.delayed(const Duration(seconds: 2));
              await _leer();
            }),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          InfoNs(_error!, key: const Key('bot_celular_error'), tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
        ],
        const SizedBox(height: 12),
        if (!_encendido)
          KeyedSubtree(
            key: const Key('bot_celular_encender'),
            child: BotonNs.primario(context, _trabajando ? 'Encendiendo…' : 'Encender el bot', _trabajando ? null : _encender, habilitado: !_trabajando),
          )
        else ...[
          if (fase == FaseBot.desvinculado)
            KeyedSubtree(
              key: const Key('bot_celular_revincular'),
              child: BotonNs.primario(context, 'Vincular de nuevo', _trabajando ? null : _vincularDeNuevo, habilitado: !_trabajando),
            ),
          if (fase == FaseBot.desvinculado) const SizedBox(height: 8),
          KeyedSubtree(
            key: const Key('bot_celular_apagar'),
            child: BotonNs.secundario(context, 'Apagar el bot', _trabajando ? null : _apagar),
          ),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed: () async {
            setState(() => _verRegistro = !_verRegistro);
            await _leer();
          },
          child: Text(_verRegistro ? 'Ocultar el registro' : 'Ver el registro del bot', style: estiloNs(14, color: ns.mute)),
        ),
        if (_verRegistro)
          Container(
            constraints: const BoxConstraints(maxHeight: 320),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(18)),
            child: _registro.isEmpty
                ? Text('Todavía no escribió nada.', style: estiloNs(13, color: ns.mute))
                : ListView.builder(
                    shrinkWrap: true,
                    reverse: true,
                    itemCount: _registro.length,
                    itemBuilder: (_, i) => Text(
                      _registro[_registro.length - 1 - i],
                      style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: ns.ink),
                    ),
                  ),
          ),
      ],
    );
  }
}

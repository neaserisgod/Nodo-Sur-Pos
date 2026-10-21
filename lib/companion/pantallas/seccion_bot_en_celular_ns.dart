// "En este celular" dentro de Bot de WhatsApp, en Nodo Sur Servicios (El dueño, 2026-10-10, `docs/PLAN-APP-SERVICIOS.md`): el bot
// corre adentro de la app, sin Termux. Acá se enciende y se apaga, se ve si está conectado y, la primera vez, el código para
// vincularlo con el WhatsApp del local. Lo que pasa después ya no depende de esta pantalla: Android lo mantiene andando. En
// Windows (2026-10-15) es la misma sección, "En esta compu", y lo mantiene el supervisor (`bot_en_pc.dart`). En la compu se
// vincula con el QR (El dueño, 2026-10-20: "si estoy en desktop me des el qr para escanear"): se escanea con el celular del
// local, sin cargar el número. En el celular sigue el código, porque no se puede escanear la propia pantalla.
// "Control del bot" (El dueño, 2026-10-21: "unos botoncitos para controlar un poco más el bot: desvincular, vincular, con
// distintos números"): reiniciar sin desvincular, desvincular, y vincular con otro número (o con otro WhatsApp, en la compu).
// Un bot atiende un número a la vez: cambiar de número suelta el anterior.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../domain/bot_en_celular.dart';
import '../../domain/bot_whatsapp.dart' show numeroWhatsApp;
import '../../edicion.dart';
import '../../servicios/bot_en_celular.dart';
import '../kit/kit_ns.dart';

class SeccionBotEnCelularNs extends StatefulWidget {
  const SeccionBotEnCelularNs({super.key, required this.bot, required this.numeroBot, this.ahora, this.enLaCompu, this.cambiarNumero});

  final BotEnCelular bot;

  /// El WhatsApp del local, ya normalizado (`5492944…`). Null si falta o está mal escrito.
  final String? numeroBot;
  final DateTime Function()? ahora;

  /// Si corre en la compu (vincula con el QR). Null: lo que diga la edición instalada. Para las pruebas, que no corren en Windows.
  final bool? enLaCompu;

  /// Guarda otro WhatsApp del local en la configuración (true si quedó). Sin esto, "Vincular otro número" usa el número nuevo
  /// solo para vincular.
  final Future<bool> Function(String numero)? cambiarNumero;

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

  /// Con qué número se pide el código. En la compu ninguno: se vincula con el QR.
  String? get _numeroParaVincular => _enLaCompu ? '' : widget.numeroBot;

  bool get _enLaCompu => widget.enLaCompu ?? esEscritorioAparte;

  Future<void> _encender() async {
    final numero = _numeroParaVincular;
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

  Future<bool> _confirmar(String titulo, String texto, String si) async =>
      await mostrarHojaNs<bool>(
        context,
        builder: (ctx) => HojaNs(
          titulo: titulo,
          texto: texto,
          botones: [
            BotonNs.primario(ctx, si, () => Navigator.of(ctx).pop(true)),
            BotonNs.secundario(ctx, 'Volver', () => Navigator.of(ctx).pop(false)),
          ],
        ),
      ) ==
      true;

  Future<void> _reiniciar() async {
    final numero = _numeroParaVincular;
    if (numero == null) {
      setState(() => _error = 'Cargá arriba el WhatsApp del local y guardá.');
      return;
    }
    await _hacer(() => widget.bot.reiniciar(numero: numero));
  }

  Future<void> _desvincular() async {
    if (!await _confirmar(
      '¿Desvincular de WhatsApp?',
      'El bot se apaga y deja de atender. Para volver a usarlo hay que vincularlo de nuevo. Acordate de borrarlo también en '
          'WhatsApp › Dispositivos vinculados.',
      'Desvincular',
    )) {
      return;
    }
    await _hacer(() async {
      await widget.bot.desvincular();
      return null;
    });
    if (mounted && _error == null) mostrarAvisoNs(context, 'Desvinculado. Para usarlo, encendelo y vinculalo de nuevo.');
  }

  /// En la compu no hace falta el número (se escanea el QR con el WhatsApp que se quiera); en el celular se pide.
  Future<void> _vincularOtro() async {
    if (_enLaCompu) {
      if (!await _confirmar('¿Vincular otro WhatsApp?', 'Se suelta el actual y aparece un QR nuevo para escanear con el otro.', 'Vincular otro')) return;
      await _hacer(() => widget.bot.vincularDeNuevo(numero: ''));
      return;
    }
    final numero = await mostrarHojaNs<String>(context, builder: (_) => const _HojaOtroNumero());
    if (numero == null || !mounted) return;
    final cambiar = widget.cambiarNumero;
    if (cambiar != null && !await cambiar(numero)) {
      setState(() => _error = 'No se pudo guardar el número nuevo: revisá la configuración de arriba.');
      return;
    }
    await _hacer(() => widget.bot.vincularDeNuevo(numero: numero));
  }

  Future<void> _copiarRegistro() async {
    final lineas = await widget.bot.ultimasLineas(400);
    if (!mounted) return;
    if (lineas.isEmpty) {
      mostrarAvisoNs(context, 'El registro está vacío');
      return;
    }
    await Clipboard.setData(ClipboardData(text: lineas.join('\n')));
    if (mounted) mostrarAvisoNs(context, 'Registro copiado: pegalo en WhatsApp o donde quieras');
  }

  Future<void> _vincularDeNuevo() async {
    final numero = _numeroParaVincular;
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
      FaseBot.apagado => (TonoNs.neutro, _enLaCompu ? IconoNs.computadora : IconoNs.celular),
      FaseBot.conectando => (TonoNs.info, IconoNs.reloj),
      FaseBot.vincular || FaseBot.desvinculado => (TonoNs.warn, IconoNs.alertaCirculo),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.only(top: 22, bottom: 10), child: SeccionNs(_enLaCompu ? 'En esta compu' : 'En este celular')),
        InfoNs(textoDelBot(fase, _estado, ahora), key: const Key('bot_celular_estado'), tono: tono, icono: icono),
        if (!_enLaCompu && widget.numeroBot != null && _encendido) ...[
          const SizedBox(height: 6),
          Text('WhatsApp del bot: ${_numeroLegible(widget.numeroBot!)}', key: const Key('bot_celular_numero'), textAlign: TextAlign.center, style: estiloNs(14, color: ns.mute)),
        ],
        if (fase == FaseBot.vincular && _enLaCompu && _estado?.qr != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(22)),
            child: Column(
              children: [
                Text('Escaneá con el WhatsApp del local', style: estiloNs(14, color: ns.mute)),
                const SizedBox(height: 12),
                // Fondo blanco siempre: con el tema oscuro, un QR claro sobre oscuro muchos celulares no lo leen.
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: QrImageView(key: const Key('bot_celular_qr'), data: _estado!.qr!, size: 240, padding: EdgeInsets.zero, backgroundColor: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(
                  'En el celular con el WhatsApp del local: Ajustes › Dispositivos vinculados › Vincular un dispositivo, y apuntá la '
                  'cámara a este código. WhatsApp lo cambia cada tanto: se actualiza acá solo.',
                  textAlign: TextAlign.center,
                  style: estiloNs(14, color: ns.ink),
                ),
              ],
            ),
          ),
        ],
        if (fase == FaseBot.vincular && !_enLaCompu && _estado?.codigo != null) ...[
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
        Padding(padding: const EdgeInsets.only(top: 22, bottom: 10), child: SeccionNs('Control del bot')),
        if (_encendido) ...[
          KeyedSubtree(
            key: const Key('bot_celular_reiniciar'),
            child: BotonNs.secundario(context, _trabajando ? 'Un momento…' : 'Reiniciar (sin desvincular)', _trabajando ? null : _reiniciar),
          ),
          const SizedBox(height: 8),
        ],
        KeyedSubtree(
          key: const Key('bot_celular_otro_numero'),
          child: BotonNs.secundario(context, _enLaCompu ? 'Vincular otro WhatsApp' : 'Vincular otro número', _trabajando ? null : _vincularOtro),
        ),
        const SizedBox(height: 8),
        KeyedSubtree(
          key: const Key('bot_celular_desvincular'),
          child: BotonNs.secundario(context, 'Desvincular de WhatsApp', _trabajando ? null : _desvincular),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () async {
            setState(() => _verRegistro = !_verRegistro);
            await _leer();
          },
          child: Text(_verRegistro ? 'Ocultar el registro' : 'Ver el registro del bot', style: estiloNs(14, color: ns.mute)),
        ),
        if (_verRegistro) ...[
          // Para mandárselo a quien da soporte (El dueño, 2026-10-21): más líneas que las que se ven.
          KeyedSubtree(
            key: const Key('bot_celular_copiar_registro'),
            child: BotonNs.secundario(context, 'Copiar el registro', _copiarRegistro, alto: 44, tamanio: 15),
          ),
          const SizedBox(height: 8),
        ],
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

/// "2944 50-7225" para leerlo; si no tiene la forma de siempre, tal cual.
String _numeroLegible(String n) => n.startsWith('549') && n.length == 13 ? '${n.substring(3, 7)} ${n.substring(7, 9)}-${n.substring(9)}' : n;

/// Pide el número nuevo, como se escribe siempre ("2944 123456"). Devuelve el número normalizado, o null si se canceló.
class _HojaOtroNumero extends StatefulWidget {
  const _HojaOtroNumero();

  @override
  State<_HojaOtroNumero> createState() => _HojaOtroNumeroState();
}

class _HojaOtroNumeroState extends State<_HojaOtroNumero> {
  final _numero = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _numero.dispose();
    super.dispose();
  }

  void _listo() {
    final n = numeroWhatsApp(_numero.text);
    if (n == null) {
      setState(() => _error = 'Ese número no parece de WhatsApp. Escribilo con la característica: 2944 123456.');
      return;
    }
    Navigator.of(context).pop(n);
  }

  @override
  Widget build(BuildContext context) {
    return HojaNs(
      titulo: 'Vincular otro número',
      texto: 'El bot suelta el WhatsApp de ahora y te da un código para vincular el nuevo. Atiende un número a la vez.',
      bloques: [
        CampoNs(etiqueta: 'WhatsApp nuevo del local', controller: _numero, placeholder: 'Ej: 2944 123456', teclado: TextInputType.phone, autofoco: true, onSubmit: (_) => _listo()),
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad),
      ],
      botones: [
        BotonNs.primario(context, 'Vincular este número', _listo),
        BotonNs.secundario(context, 'Volver', () => Navigator.of(context).pop()),
      ],
    );
  }
}

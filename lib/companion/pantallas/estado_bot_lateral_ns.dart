// El estado del bot de WhatsApp al pie del menú lateral, en la compu (mock de escritorio aprobado por el dueño el 2026-10-15):
// "Bot conectado · corre en esta compu · último mensaje hace 4 min". Solo donde el bot corre adentro de la app.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/bot_en_celular.dart';
import '../../servicios/bot_en_celular.dart';
import '../kit/kit_ns.dart';

class EstadoBotLateralNs extends StatefulWidget {
  const EstadoBotLateralNs({super.key, required this.bot, this.cada = const Duration(seconds: 15)});

  final BotEnCelular bot;
  final Duration cada;

  @override
  State<EstadoBotLateralNs> createState() => _EstadoBotLateralNsState();
}

class _EstadoBotLateralNsState extends State<EstadoBotLateralNs> {
  Timer? _timer;
  bool _encendido = false;
  EstadoBotLocal? _estado;

  @override
  void initState() {
    super.initState();
    _leer();
    _timer = Timer.periodic(widget.cada, (_) => _leer());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _leer() async {
    final encendido = await widget.bot.encendido();
    final estado = encendido ? await widget.bot.leerEstado() : null;
    if (mounted) {
      setState(() {
        _encendido = encendido;
        _estado = estado;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final fase = faseDelBot(encendido: _encendido, estado: _estado);
    final color = switch (fase) {
      FaseBot.conectado => ns.g,
      FaseBot.apagado => ns.mute,
      FaseBot.conectando => ns.i,
      FaseBot.vincular || FaseBot.desvinculado => ns.w,
    };
    return Semantics(
      container: true,
      label: 'Bot de WhatsApp',
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text('Bot de WhatsApp', maxLines: 1, overflow: TextOverflow.ellipsis, style: estiloNs(13.5, peso: FontWeight.w600, color: ns.ink))),
              ],
            ),
            const SizedBox(height: 4),
            Text(textoDelBot(fase, _estado, DateTime.now()), key: const Key('bot_lateral_estado'), style: estiloNs(13, altura: 1.3, color: ns.mute)),
          ],
        ),
      ),
    );
  }
}

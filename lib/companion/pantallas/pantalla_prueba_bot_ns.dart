// Prueba (El dueño, 2026-10-10): ¿anda el bot de WhatsApp adentro de la app, sin Termux? Arranca el Node empaquetado con un
// script que prueba Node, SQLite, internet, Baileys y la conexión con WhatsApp, y muestra lo que va pasando. Con un número, pide
// el código para vincular ese WhatsApp (se escribe en Dispositivos vinculados del celular del negocio).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../servicios/bot_en_celular.dart';
import '../kit/kit_ns.dart';

class PantallaPruebaBotNs extends StatefulWidget {
  const PantallaPruebaBotNs({super.key});

  @override
  State<PantallaPruebaBotNs> createState() => _PantallaPruebaBotNsState();
}

class _PantallaPruebaBotNsState extends State<PantallaPruebaBotNs> {
  final _bot = BotEnCelular();
  final _numero = TextEditingController();
  final _lineas = <String>[];
  StreamSubscription<String>? _sub;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sub = _bot.lineas.listen((l) {
      if (mounted) setState(() => _lineas.add(l));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _bot.detener();
    _numero.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    setState(() {
      _error = null;
      _lineas.clear();
    });
    final problema = await _bot.iniciar(numero: _numero.text);
    if (mounted) setState(() => _error = problema);
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Scaffold(
      backgroundColor: ns.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(margenNs, 8, margenNs, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CabeceraSubNs(titulo: 'Probar el bot acá', onVolver: () => Navigator.of(context).pop()),
              const SizedBox(height: 8),
              Text(
                'Prueba si el bot de WhatsApp puede correr adentro de esta app, sin Termux. Con un número, pide el código para vincularlo.',
                style: estiloNs(14, color: ns.mute),
              ),
              const SizedBox(height: 12),
              CampoNs(etiqueta: 'Número (opcional)', controller: _numero, placeholder: '5492944123456', teclado: TextInputType.phone),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: BotonNs.primario(context, 'Probar', _iniciar, alto: 52, tamanio: 16)),
                  const SizedBox(width: 10),
                  Expanded(child: BotonNs.secundario(context, 'Detener', _bot.detener, alto: 52)),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(18)),
                  child: ListView.builder(
                    itemCount: _lineas.length,
                    itemBuilder: (_, i) => SelectableText(
                      _lineas[i],
                      style: estiloNs(12.5, color: _lineas[i].contains('ERROR') ? ns.b : ns.ink, altura: 1.35),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

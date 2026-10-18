// Bienvenida de Nodo Gastro (mock v5, docs/mock-gastro/NodoGastro.html): tres pantallas con lo que la hace distinta antes de
// entrar con la cuenta. La de almacén (`pantalla_bienvenida.dart`) cuenta cosas de almacén (proveedores, stock con la cámara);
// esta cuenta el bot que atiende solo, la cocina que frena al bot y la caja que cierra sola. Se avanza con "Siguiente", como la
// otra (El dueño, 2026-10-03), y "Ya tengo cuenta" la saltea.

import 'package:flutter/material.dart';

import '../kit/kit_ns.dart';

class BienvenidaGastro extends StatefulWidget {
  const BienvenidaGastro({super.key, required this.alTerminar, this.pasoInicial = 0});

  /// "Empezar" en la última pantalla, o "Ya tengo cuenta" en cualquiera.
  final void Function(BuildContext context) alTerminar;

  /// Solo para tests y capturas: en qué pantalla arranca.
  @visibleForTesting
  final int pasoInicial;

  @override
  State<BienvenidaGastro> createState() => _BienvenidaGastroState();
}

class _BienvenidaGastroState extends State<BienvenidaGastro> {
  late int _paso = widget.pasoInicial;

  static const _textos = [
    ('Tu WhatsApp', 'atiende solo.', 'Contesta al toque, manda la carta y te deja el pedido listo para cocinar.'),
    ('La cocina', 'manda.', 'Si se llena, tocás "Con demora" o "Pausada" y el bot avisa la demora real o deja de tomar pedidos.'),
    ('La caja', 'cierra sola.', 'Efectivo, QR y Point en un lugar. Al final del día contás el cajón y listo.'),
  ];

  void _siguiente() {
    if (_paso == _textos.length - 1) {
      widget.alTerminar(context);
      return;
    }
    setState(() => _paso++);
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final (arriba, abajo, bajada) = _textos[_paso];
    final ultimo = _paso == _textos.length - 1;
    return Scaffold(
      backgroundColor: ns.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const MarcaGastro(tamanio: 28),
                  const SizedBox(width: 9),
                  Expanded(child: Text('Nodo Gastro', maxLines: 1, overflow: TextOverflow.ellipsis, style: tituloNs(18, track: -0.03, color: ns.ink))),
                  BotonNs(
                    key: const Key('bienvenida-saltar'),
                    texto: 'Ya tengo cuenta',
                    onTap: () => widget.alTerminar(context),
                    alto: 44,
                    tamanio: 15,
                    fondo: Colors.transparent,
                    color: ns.mute,
                    rellenar: false,
                    paddingH: 6,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: AnimatedSwitcher(
                  duration: sinMovimiento(context) ? Duration.zero : const Duration(milliseconds: 350),
                  child: Column(
                    key: ValueKey(_paso),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(32)),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: SizedBox(width: 320, child: [const _EscenaBot(), const _EscenaCocina(), const _EscenaCaja()][_paso]),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: '$arriba\n'),
                          TextSpan(text: abajo, style: TextStyle(color: ns.acento)),
                        ]),
                        style: tituloNs(40, track: -0.055, altura: 0.98, color: ns.ink),
                      ),
                      const SizedBox(height: 12),
                      Text(bajada, style: estiloNs(17, altura: 1.4, color: ns.mute)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _textos.length; i++)
                    AnimatedContainer(
                      duration: sinMovimiento(context) ? Duration.zero : const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _paso ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(color: i == _paso ? ns.ink : ns.s2, borderRadius: BorderRadius.circular(4)),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              BotonNs.primario(context, ultimo ? 'Empezar' : 'Siguiente', _siguiente, alto: 56).conClave(const Key('bienvenida-siguiente')),
            ],
          ),
        ),
      ),
    );
  }
}

/// La marca de Nodo Gastro: un cuadrado naranja con la N, como en el sitio.
class MarcaGastro extends StatelessWidget {
  const MarcaGastro({super.key, this.tamanio = 28});

  final double tamanio;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Container(
      width: tamanio,
      height: tamanio,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: ns.acento, borderRadius: BorderRadius.circular(tamanio * 0.32)),
      child: Text('N', style: tituloNs(tamanio * 0.62, track: 0, color: ns.onAcento)),
    );
  }
}

extension on Widget {
  Widget conClave(Key clave) => KeyedSubtree(key: clave, child: this);
}

class _Burbuja extends StatelessWidget {
  const _Burbuja(this.texto, this.pie, {this.cliente = false});

  final String texto;
  final String pie;
  final bool cliente;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final color = cliente ? ns.onAcento : ns.ink;
    return Align(
      alignment: cliente ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: cliente ? ns.acento : ns.paper,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(cliente ? 20 : 6),
            bottomRight: Radius.circular(cliente ? 6 : 20),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(texto, style: estiloNs(15, altura: 1.3, color: color)),
            const SizedBox(height: 2),
            Text(pie, style: estiloNs(12, color: color.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }
}

class _EscenaBot extends StatelessWidget {
  const _EscenaBot();

  @override
  Widget build(BuildContext context) => const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Burbuja('¡Hola! ¿Hacen envíos? Quiero un pollo con papas', '21:01', cliente: true),
          _Burbuja('¡Hola! Sí, al Centro sale \$ 1.500. Pollo al spiedo y papas grandes: \$ 21.500 con envío. ¿A qué dirección?', '21:01 · el bot'),
          _Burbuja('Mitre 340, 2° B', '21:02', cliente: true),
          _Burbuja('Listo, llega 21:40. Te aviso cuando sale.', '21:02 · el bot'),
        ],
      );
}

class _Tablero extends StatelessWidget {
  const _Tablero({required this.rotulo, required this.cifra, required this.pie, this.barra});

  final String rotulo;
  final String cifra;
  final String pie;
  final double? barra;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final suave = TokensNs.blanco.withValues(alpha: 0.65);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: ns.oscuro ? ns.s2 : ns.hero, borderRadius: BorderRadius.circular(28)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: ns.acento, shape: BoxShape.circle)),
            const SizedBox(width: 7),
            Text(rotulo, style: estiloNs(14, peso: FontWeight.w600, color: suave)),
          ]),
          const SizedBox(height: 10),
          Text(cifra, style: tituloNs(44, track: -0.05, color: TokensNs.blanco)),
          const SizedBox(height: 4),
          Text(pie, style: estiloNs(13, color: suave)),
          if (barra != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: barra, minHeight: 6, color: ns.acento, backgroundColor: TokensNs.blanco.withValues(alpha: 0.2)),
            ),
          ],
        ],
      ),
    );
  }
}

class _EscenaCocina extends StatelessWidget {
  const _EscenaCocina();

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Tablero(rotulo: 'Sale ahora', cifra: '6 min', pie: 'Ezequiel R. · 2 pizzas', barra: 0.8),
          const SizedBox(height: 10),
          IgnorePointer(child: SegmentoNs(opciones: const ['Normal', 'Con demora', 'Pausada'], indice: 1, onCambio: (_) {})),
          const SizedBox(height: 10),
          const _Burbuja('Estamos con mucha demanda: tu pedido sale en 60 minutos. ¿Lo confirmo?', '21:05 · el bot'),
        ],
      );
}

class _EscenaCaja extends StatelessWidget {
  const _EscenaCaja();

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    Widget chico(String rotulo, String cifra) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(color: ns.paper, borderRadius: BorderRadius.circular(22)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rotulo, style: estiloNs(13, peso: FontWeight.w600, color: ns.mute)),
                const SizedBox(height: 2),
                Text(cifra, style: estiloNs(19, peso: FontWeight.w600, color: ns.ink, tabular: true)),
              ],
            ),
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Tablero(rotulo: 'Vendido hoy', cifra: '\$ 257.400', pie: '23 ventas · el bot trajo el 62 %'),
        const SizedBox(height: 8),
        Row(children: [chico('Efectivo', '\$ 86.400'), const SizedBox(width: 8), chico('Mercado Pago', '\$ 171.000')]),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              Expanded(child: Text('Contaste el cajón', style: estiloNs(16, color: ns.ink))),
              Text('Cuadró', style: estiloNs(16, peso: FontWeight.w600, color: ns.g)),
            ],
          ),
        ),
      ],
    );
  }
}

// "¿Cómo usás el sistema?" — la primera pantalla de una instalación nueva, y a la que se vuelve desde Más para cambiar de
// modo (mock 01 y 01b). Es solo la elección: qué pasa después (emparejar con la PC, o dejar el celular solo y ofrecer
// vincular la cuenta) lo resuelve `flujo_modo_uso.dart`.

import 'package:flutter/material.dart';

import 'kit/kit_ns.dart';
import 'modo_uso.dart';

class PantallaElegirModo extends StatelessWidget {
  const PantallaElegirModo({super.key, required this.alElegir, this.actual});

  /// Se llama con el modo tocado y el contexto de esta pantalla (para navegar desde ahí).
  final void Function(BuildContext context, ModoUso modo) alElegir;

  /// El modo en uso hoy, si ya hay uno (cuando se llega desde Más): se marca y la pantalla tiene "volver".
  final ModoUso? actual;

  @override
  Widget build(BuildContext context) {
    final cambiando = actual != null;
    return PaginaArranqueNs(
      titulo: cambiando ? 'Modo de uso' : '¿Cómo vas a usar el sistema?',
      bajada: cambiando ? 'Cambiá cómo se usa este celular.' : 'Elegí una opción para empezar.',
      alVolver: cambiando ? () => Navigator.of(context).maybePop() : null,
      cuerpo: [
        OpcionNs(
          key: const Key('modo-pc-y-celular'),
          titulo: 'Tengo PC y celular',
          detalle: 'El celular se conecta a la PC. Si la PC se apaga o queda fuera del wifi, sigue funcionando por internet.',
          marcada: actual == ModoUso.pcYCelular,
          derecha: actual == ModoUso.pcYCelular ? 'Actual' : null,
          onTap: () => alElegir(context, ModoUso.pcYCelular),
        ),
        OpcionNs(
          key: const Key('modo-solo-celular'),
          titulo: 'Solo uso el celular',
          detalle: 'El celular es el sistema. Podés guardar y sincronizar tus datos con tu cuenta de Nodo Sur.',
          marcada: actual == ModoUso.soloCelular,
          derecha: actual == ModoUso.soloCelular ? 'Actual' : null,
          onTap: () => alElegir(context, ModoUso.soloCelular),
        ),
        const InfoNs('Lo podés cambiar después, desde Gestión.'),
      ],
    );
  }
}

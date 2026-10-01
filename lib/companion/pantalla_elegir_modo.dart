// "¿Cómo usás el sistema?" — la primera pantalla de una instalación nueva, y a la que se vuelve desde Gestión para
// cambiar de modo. Es solo la elección: qué pasa después (emparejar con la PC, o dejar el celular solo y ofrecer
// vincular la cuenta) lo resuelve `flujo_modo_uso.dart`.

import 'package:flutter/material.dart';

import '../servicios/marca_actual.dart';
import '../ui/tema/iconos.dart';
import '../ui/tema/tokens.dart';
import 'modo_uso.dart';
import 'tema/chip_icono.dart';
import 'tema/presionable.dart';
import 'tema/superficie.dart';
import 'tema/tema_companion.dart';

class PantallaElegirModo extends StatelessWidget {
  const PantallaElegirModo({super.key, required this.alElegir, this.actual});

  /// Se llama con el modo tocado y el contexto de esta pantalla (para navegar desde ahí).
  final void Function(BuildContext context, ModoUso modo) alElegir;

  /// El modo en uso hoy, si ya hay uno (cuando se llega desde Gestión): se marca y la pantalla tiene "volver".
  final ModoUso? actual;

  @override
  Widget build(BuildContext context) {
    final cambiando = actual != null;
    return Scaffold(
      appBar: cambiando ? AppBar(title: const Text('Modo de uso')) : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(EspacioCompanion.lg),
          children: [
            if (!cambiando) ...[
              const SizedBox(height: EspacioCompanion.xxl),
              Center(child: ChipIcono(icono: IconosPlazoleta.storefrontRounded, color: context.colores.acento, tamanio: 72, tamanioIcono: 36)),
              const SizedBox(height: EspacioCompanion.lg),
              Text(
                marcaActual.value.nombre,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: EspacioCompanion.xs),
              Text(
                '¿Cómo vas a usar el sistema?',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: EspacioCompanion.xl),
            ],
            _OpcionModo(
              clave: const Key('modo-pc-y-celular'),
              icono: IconosPlazoleta.computer,
              titulo: 'Tengo PC y celular',
              detalle:
                  'El celular se conecta a la PC. Si la PC se apaga o queda fuera del wifi, sigue funcionando por internet.',
              marcado: actual == ModoUso.pcYCelular,
              onTap: () => alElegir(context, ModoUso.pcYCelular),
            ),
            const SizedBox(height: EspacioCompanion.md),
            _OpcionModo(
              clave: const Key('modo-solo-celular'),
              icono: IconosPlazoleta.smartphone,
              titulo: 'Solo uso el celular',
              detalle:
                  'El celular es el sistema. Podés guardar y sincronizar tus datos con tu cuenta de Nodo Sur.',
              marcado: actual == ModoUso.soloCelular,
              onTap: () => alElegir(context, ModoUso.soloCelular),
            ),
            const SizedBox(height: EspacioCompanion.xl),
            Text(
              'Lo podés cambiar después, desde Gestión.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _OpcionModo extends StatelessWidget {
  const _OpcionModo({
    required this.clave,
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.marcado,
    required this.onTap,
  });

  final Key clave;
  final IconData icono;
  final String titulo;
  final String detalle;
  final bool marcado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Superficie(
      key: clave,
      padding: EdgeInsets.zero,
      child: Presionable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(EspacioCompanion.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ChipIcono(icono: icono, color: colores.acento, tamanio: 52, tamanioIcono: 26),
              const SizedBox(width: EspacioCompanion.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(titulo, style: Theme.of(context).textTheme.titleMedium)),
                        if (marcado) Icon(IconosPlazoleta.check, color: colores.acento, size: 20),
                      ],
                    ),
                    const SizedBox(height: EspacioCompanion.xs),
                    Text(detalle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

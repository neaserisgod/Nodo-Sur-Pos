// "¿Cómo usás el sistema?" — la primera pantalla de una instalación nueva, y a la que se vuelve desde Gestión para
// cambiar de modo. Es solo la elección: qué pasa después (emparejar con la PC, o dejar el celular solo y ofrecer
// vincular la cuenta) lo resuelve `flujo_modo_uso.dart`.

import 'package:flutter/material.dart';

import '../domain/marca.dart';
import '../servicios/marca_actual.dart';
import '../ui/tema/iconos.dart';
import '../ui/tema/tokens.dart';
import 'modo_uso.dart';
import 'tema/piezas_companion.dart';
import 'tema/presionable.dart';
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
      appBar: cambiando ? AppBar(scrolledUnderElevation: 0) : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: Espaciado.xxl),
          children: [
            if (cambiando)
              const EncabezadoCompanion(
                rotulo: 'Gestión',
                titulo: 'Modo de uso',
                bajada: 'Cambiá cómo se usa este celular.',
              )
            else
              ValueListenableBuilder<MarcaNegocio>(
                valueListenable: marcaActual,
                builder: (context, marca, _) => EncabezadoCompanion(
                  rotulo: marca.nombre,
                  titulo: '¿Cómo vas a usar el sistema?',
                  bajada: 'Elegí una opción para empezar.',
                  particulas: true,
                  padding: const EdgeInsets.fromLTRB(Espaciado.xl, Espaciado.xxl, Espaciado.xl, Espaciado.xl),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Espaciado.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _OpcionModo(
                    clave: const Key('modo-pc-y-celular'),
                    icono: IconosPlazoleta.computer,
                    titulo: 'Tengo PC y celular',
                    detalle:
                        'El celular se conecta a la PC. Si la PC se apaga o queda fuera del wifi, sigue funcionando por internet.',
                    marcado: actual == ModoUso.pcYCelular,
                    onTap: () => alElegir(context, ModoUso.pcYCelular),
                  ),
                  const SizedBox(height: Espaciado.md),
                  _OpcionModo(
                    clave: const Key('modo-solo-celular'),
                    icono: IconosPlazoleta.smartphone,
                    titulo: 'Solo uso el celular',
                    detalle:
                        'El celular es el sistema. Podés guardar y sincronizar tus datos con tu cuenta de Nodo Sur.',
                    marcado: actual == ModoUso.soloCelular,
                    onTap: () => alElegir(context, ModoUso.soloCelular),
                  ),
                  const SizedBox(height: Espaciado.xl),
                  Text(
                    'Lo podés cambiar después, desde Gestión.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bloque gris con círculo de ícono, título y detalle: el mismo lenguaje que `FilaElegible` (elegir usuario).
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
    final textTheme = Theme.of(context).textTheme;
    return Presionable(
      key: clave,
      radio: radioSuperficieCompanion,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(EspacioCompanion.lg),
        decoration: BoxDecoration(
          color: colores.fondoBloque,
          borderRadius: BorderRadius.circular(radioSuperficieCompanion),
          border: marcado ? Border.all(color: colores.textoPrimario, width: 1.5) : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: colores.fondo, shape: BoxShape.circle),
              child: Icon(icono, color: colores.textoPrimario, size: 24),
            ),
            const SizedBox(width: EspacioCompanion.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: textTheme.titleMedium),
                  const SizedBox(height: EspacioCompanion.xs),
                  Text(detalle, style: textTheme.bodySmall),
                ],
              ),
            ),
            if (marcado) ...[
              const SizedBox(width: EspacioCompanion.sm),
              Icon(IconosPlazoleta.check, color: colores.textoPrimario, size: 22),
            ],
          ],
        ),
      ),
    );
  }
}

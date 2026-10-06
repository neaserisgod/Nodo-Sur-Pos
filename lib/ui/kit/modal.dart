// Modal del mock v4 (`.modal`, `.mhead`, `.mbody`, `.mfoot`, `.mscr`): blanco, radio 48, sombra grande, al centro sobre
// un velo con desenfoque. Entra desde abajo y un poco más chico (22 px, 0,96) en 320 ms con `--ease`.

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'ic.dart';
import 'mov.dart';
import 'paleta.dart';
import 'piezas.dart';
import 'texto.dart';

/// Ancho del modal: normal 760, `.w` 1060, `.n` 620.
enum AnchoModal { normal, ancho, angosto }

double _ancho(AnchoModal a) => switch (a) {
      AnchoModal.normal => 760,
      AnchoModal.ancho => 1060,
      AnchoModal.angosto => 620,
    };

/// Abre un modal del mock. [descartable]: tocar afuera o Esc lo cierran (los que no se pueden saltear, como abrir la
/// caja, pasan `false`).
Future<T?> mostrarModalMock<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool descartable = true,
  bool raiz = true,
  RouteSettings? settings,
}) {
  final p = context.p;
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: raiz,
    barrierDismissible: descartable,
    barrierLabel: 'Cerrar',
    barrierColor: Colors.transparent,
    routeSettings: settings,
    transitionDuration: hayMovimiento(context) ? ms(320) : Duration.zero,
    pageBuilder: (context, a1, a2) => builder(context),
    transitionBuilder: (context, animacion, _, hijo) {
      final k = curvaEase.transform(animacion.value);
      final op = Curves.linear.transform((animacion.value / (250 / 320)).clamp(0.0, 1.0));
      return Stack(
        children: [
          // `.mscr`: velo + desenfoque de 6 px.
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: op,
                child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6), child: ColoredBox(color: p.scrim)),
              ),
            ),
          ),
          Opacity(
            opacity: op,
            child: Transform.translate(
              offset: Offset(0, 22 * (1 - k)),
              child: Transform.scale(scale: .96 + .04 * k, child: hijo),
            ),
          ),
        ],
      );
    },
  );
}

/// El contenido de un modal: cabecera (título 38 + subtítulo + cruz), cuerpo que scrollea y pie.
class ModalMock extends StatelessWidget {
  const ModalMock({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.subtituloWidget,
    required this.cuerpo,
    this.pie,
    this.pieEnFila = false,
    this.ancho = AnchoModal.normal,
    this.sinCerrar = false,
    this.onCerrar,
    this.espacioCuerpo = 14,
  });

  final String titulo;
  final String? subtitulo;
  final Widget? subtituloWidget;
  final List<Widget> cuerpo;

  /// `.mfoot`: botones apilados (o en fila con [pieEnFila], todos del mismo ancho).
  final List<Widget>? pie;
  final bool pieEnFila;
  final AnchoModal ancho;

  /// Sin la cruz (`nox` del mock): modales que se resuelven con sus botones.
  final bool sinCerrar;
  final VoidCallback? onCerrar;
  final double espacioCuerpo;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final alto = MediaQuery.sizeOf(context).height;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(50),
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            width: _ancho(ancho),
            constraints: BoxConstraints(maxHeight: alto - 100),
            decoration: BoxDecoration(
              color: p.papel,
              borderRadius: BorderRadius.circular(48),
              boxShadow: const [BoxShadow(color: Color(0x590D1017), blurRadius: 100, offset: Offset(0, 40))],
            ),
            child: DefaultTextStyle(
              style: estilo(16, 400, color: p.tinta),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(40, 36, 40, 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(titulo, style: Tipos.h2(p.tinta, tamanio: 38)),
                              if (subtituloWidget != null)
                                Padding(padding: const EdgeInsets.only(top: 8), child: subtituloWidget!)
                              else if (subtitulo != null && subtitulo!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(subtitulo!, style: estilo(17, 400, color: p.mute, alto: 1.4)),
                                ),
                            ],
                          ),
                        ),
                        if (!sinCerrar) ...[
                          const SizedBox(width: 16),
                          BotonCirculo(
                            key: const Key('modal_cerrar'),
                            icono: Ic.x,
                            etiqueta: 'Cerrar',
                            tamanioIcono: 20,
                            grosor: 2.4,
                            girarAlPasar: true,
                            onTap: onCerrar ?? () => Navigator.of(context).maybePop(),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(40, 14, 40, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, w) in cuerpo.indexed) ...[if (i > 0) SizedBox(height: espacioCuerpo), w],
                        ],
                      ),
                    ),
                  ),
                  if (pie != null && pie!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(40, 16, 40, 36),
                      child: pieEnFila
                          ? Row(children: [
                              for (final (i, w) in pie!.indexed) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: w)],
                            ])
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final (i, w) in pie!.indexed) ...[if (i > 0) const SizedBox(height: 10), w],
                              ],
                            ),
                    )
                  else
                    const SizedBox(height: 26),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

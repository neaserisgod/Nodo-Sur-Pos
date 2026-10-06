// Campanita del mock v4 (`.ci` con la insignia roja `.bd` y el panel `.popn`), hecha desde cero. Está en la barra de
// todas las pantallas. Trae el arqueo sugerido cada 2 horas (si el módulo de turnos está prendido y la pantalla sabe de
// la caja) y los avisos de Mercado Pago (cobro sin venta, contracargo, reclamo: solo avisan, cada uno con "Visto").
//
// El arqueo es opcional (El dueño, 2026-09-28): el botón está siempre; a las 2 horas la tarjeta pasa a ámbar y cuenta
// en la insignia.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/avisos_mp.dart';
import '../../domain/modulos.dart';
import '../../servicios/avisos_mp_servicio.dart';
import '../../servicios/modulos_activos.dart';
import '../../servicios/nube.dart' show nubeApp;
import '../kit/kit.dart';

class BotonNotificaciones extends StatefulWidget {
  const BotonNotificaciones({super.key, this.hayArqueoVencido = false, this.onHacerArqueo});

  final bool hayArqueoVencido;

  /// Null en las pantallas que no saben de la caja abierta: ahí la campanita muestra solo los avisos de Mercado Pago.
  final VoidCallback? onHacerArqueo;

  @override
  State<BotonNotificaciones> createState() => _BotonNotificacionesState();
}

class _BotonNotificacionesState extends State<BotonNotificaciones> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  static final _sinAvisos = ValueNotifier<List<AvisoParaMostrar>>(const []);

  void _alternar() => setState(() => _portal.isShowing ? _portal.hide() : _portal.show());
  void _cerrar() {
    if (_portal.isShowing) setState(_portal.hide);
  }

  @override
  Widget build(BuildContext context) {
    final servicio = nubeApp?.avisosMp;
    return ValueListenableBuilder<ModulosNegocio>(
      valueListenable: modulosActuales,
      builder: (context, modulos, _) => ValueListenableBuilder<List<AvisoParaMostrar>>(
        valueListenable: servicio?.pendientes ?? _sinAvisos,
        builder: (context, avisos, _) => _construir(context, avisos, servicio, modulos.estaActivo(Modulo.turnos)),
      ),
    );
  }

  Widget _construir(BuildContext context, List<AvisoParaMostrar> avisos, ServicioAvisosMp? servicio, bool hayTurnos) {
    final conArqueo = widget.onHacerArqueo != null && hayTurnos;
    final arqueoPendiente = conArqueo && widget.hayArqueoVencido;
    final cuenta = avisos.length + (arqueoPendiente ? 1 : 0);
    return TapRegion(
      groupId: _link,
      onTapOutside: (_) => _cerrar(),
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          // El panel queda alineado con la tuerca (el mock lo pone a 130 px del borde derecho).
          offset: const Offset(54, 17),
          child: Align(
            alignment: Alignment.topRight,
            child: TapRegion(
              groupId: _link,
              child: CallbackShortcuts(
                bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cerrar},
                child: FocusScope(
                  autofocus: true,
                  child: Aparecer.arriba(
                    duracion: ms(260),
                    child: _Panel(
                      avisos: avisos,
                      cuenta: cuenta,
                      conArqueo: conArqueo,
                      arqueoPendiente: arqueoPendiente,
                      onArqueo: () {
                        _cerrar();
                        widget.onHacerArqueo!();
                      },
                      onVisto: servicio == null ? null : (a) => servicio.marcarVisto(a.aviso),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        child: CompositedTransformTarget(
          link: _link,
          child: BotonCirculo(
            icono: Ic.bell,
            etiqueta: 'Notificaciones',
            tamanioIcono: 21,
            activo: _portal.isShowing,
            insignia: cuenta,
            onTap: _alternar,
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.avisos,
    required this.cuenta,
    required this.conArqueo,
    required this.arqueoPendiente,
    required this.onArqueo,
    required this.onVisto,
  });

  final List<AvisoParaMostrar> avisos;
  final int cuenta;
  final bool conArqueo;
  final bool arqueoPendiente;
  final VoidCallback onArqueo;
  final void Function(AvisoParaMostrar)? onVisto;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final hijos = <Widget>[
      if (conArqueo)
        Tarjeta(
          tono: arqueoPendiente ? TonoMock.w : null,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                arqueoPendiente ? 'Pasaron 2 horas desde el último arqueo' : (avisos.isEmpty ? 'Sin novedades por ahora' : 'Arqueo'),
                style: estilo(17, 600, color: arqueoPendiente ? p.w : p.tinta),
              ),
              if (!arqueoPendiente) ...[
                const SizedBox(height: 3),
                Text('Contar la caja es opcional. Lo que cuentes queda precargado en el cierre.', style: estilo(14, 400, color: p.mute)),
              ],
              const SizedBox(height: 12),
              Btn('Hacer arqueo', variante: VarBtn.dark, tam: TamBtn.sm, onTap: onArqueo),
            ],
          ),
        ),
      for (final a in avisos)
        Tarjeta(
          key: ValueKey('aviso_mp_${a.aviso.idServidor}'),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Ibox(Ic.mp, chico: true, color: p.azul),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.titulo, style: estilo(17, 600, color: p.tinta)),
                    const SizedBox(height: 3),
                    Text(a.texto, style: estilo(14, 400, color: p.mute)),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Btn('Visto', variante: VarBtn.ton, sobreGris: true, tam: TamBtn.xs, onTap: onVisto == null ? null : () => onVisto!(a)),
            ],
          ),
        ),
    ];
    return Container(
      width: 520,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height - 160),
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: p.papel,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: p.pelo),
        boxShadow: const [BoxShadow(color: Color(0x400D1017), blurRadius: 80, offset: Offset(0, 30))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Notificaciones', style: Tipos.h3(p.tinta))),
                Etiqueta(cuenta == 1 ? '1 pendiente' : '$cuenta pendientes'),
              ],
            ),
            const SizedBox(height: 12),
            if (hijos.isEmpty)
              const Vacio(texto: 'Sin novedades por ahora')
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [for (final (i, h) in hijos.indexed) ...[if (i > 0) const SizedBox(height: 12), h]],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

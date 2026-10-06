// Campanita de notificaciones, en la navbar de TODAS las pantallas (rediseño v4). Antes vivía dentro de `pantalla_venta.dart`.

import 'package:flutter/material.dart';

import '../../domain/avisos_mp.dart';
import '../../domain/modulos.dart';
import '../../servicios/avisos_mp_servicio.dart';
import '../../servicios/modulos_activos.dart';
import '../../servicios/nube.dart' show nubeApp;
import '../comun/botones.dart';
import '../tema/iconos.dart';
import '../tema/superficie.dart';
import '../tema/tema.dart';
import '../tema/tokens.dart';

/// Campanita de notificaciones (El dueño, tercera pasada: *"NO QUIERO QUE
/// APAREZCA EL COSO DEL ARQUEO OCUPANDO TODO, DEBEMOS TENER UN APARTADO
/// NOTIFICACIONES"*) — reemplaza al banner de ancho completo
/// (`_AvisoArqueoIntermedio`, hasta acá) que empujaba todo lo de abajo
/// cada vez que pasaban 2hs sin arqueo. El aviso sigue siendo sugerencia,
/// no bloqueo (El dueño, 2026-09-15): se puede seguir vendiendo con el panel
/// cerrado; desaparece solo cuando se hace el arqueo
/// (`_hacerArqueoIntermedio` recarga `arqueoIntermedioVencido`) o cambia de
/// sesión.
///
/// Mismo mecanismo que el dropdown de resultados de búsqueda
/// (`columna_busqueda.dart::BarraBusquedaVenta`): `CompositedTransformTarget`
/// + `OverlayPortal` + `CompositedTransformFollower`, acá anclado a un
/// ícono en vez de a un campo, con `UnconstrainedBox` para que el panel se
/// mida por su contenido (mismo bug ya resuelto ahí). Queda como el único
/// lugar de avisos que no son parte del flujo de vender — no solo para el
/// arqueo, una base para sumar más el día que haga falta.
class BotonNotificaciones extends StatefulWidget {
  const BotonNotificaciones({
    super.key,
    this.hayArqueoVencido = false,
    this.onHacerArqueo,
  });

  final bool hayArqueoVencido;

  /// Null en las pantallas que no saben de la caja abierta (Inicio, Proveedores…): ahí la campanita muestra solo los avisos
  /// de Mercado Pago y no ofrece el arqueo.
  final VoidCallback? onHacerArqueo;

  @override
  State<BotonNotificaciones> createState() => _BotonNotificacionesState();
}

class _BotonNotificacionesState extends State<BotonNotificaciones> {
  final _link = LayerLink();
  final _overlayController = OverlayPortalController();
  bool _abierto = false;

  // Avisos de Mercado Pago (etapa D, El dueño 2026-10-04): cobro que entró sin venta, contracargos y reclamos. Solo avisan, y
  // solo en la PC (en los tests y en el celular no hay servicio y la lista queda vacía).
  static final _sinAvisos = ValueNotifier<List<AvisoParaMostrar>>(const []);

  @override
  void initState() {
    super.initState();
    _overlayController.show();
  }

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final servicio = nubeApp?.avisosMp;
    return ValueListenableBuilder<List<AvisoParaMostrar>>(
      valueListenable: servicio?.pendientes ?? _sinAvisos,
      builder: (context, avisos, _) => _construir(context, colores, avisos, servicio),
    );
  }

  Widget _construir(BuildContext context, ColoresPlazoleta colores, List<AvisoParaMostrar> avisos, ServicioAvisosMp? servicio) {
    final hayPendiente = widget.hayArqueoVencido || avisos.isNotEmpty;

    return OverlayPortal(
      controller: _overlayController,
      overlayChildBuilder: (context) {
        if (!_abierto) return const SizedBox.shrink();
        return CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, Espaciado.sm),
          child: UnconstrainedBox(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: 320,
              child: Superficie(
                relleno: colores.fondoBloque,
                // Arqueo opcional (El dueño, 2026-09-28: "que los arqueos
                // durante el turno dejen de ser obligatorios"): el botón está
                // siempre, y a las 2hs solo se prende el punto — el aviso
                // suave que eligió, sin panel ni banner que insista.
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final a in avisos) ...[
                          _AvisoMpEnPanel(aviso: a, onVisto: servicio == null ? null : () => servicio.marcarVisto(a.aviso)),
                          const SizedBox(height: Espaciado.md),
                        ],
                        if (widget.onHacerArqueo != null)
                        SiModulo(
                          Modulo.turnos,
                          hijo: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.hayArqueoVencido
                                    ? 'Pasaron 2 horas desde el último arqueo.'
                                    : (avisos.isEmpty ? 'Sin novedades por ahora.' : 'Arqueo'),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: Espaciado.xs),
                              Text(
                                'Contar la caja es opcional. Lo que cuentes queda '
                                'precargado en el cierre.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: Espaciado.md),
                              BotonSecundario(
                                texto: 'Hacer arqueo',
                                onPressed: () {
                                  setState(() => _abierto = false);
                                  widget.onHacerArqueo!();
                                },
                              ),
                            ],
                          ),
                        ),
                        if (avisos.isEmpty && (widget.onHacerArqueo == null || !modulosActuales.value.estaActivo(Modulo.turnos)))
                          Text('Sin novedades por ahora.', style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: CompositedTransformTarget(
        link: _link,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Tooltip(
              message: 'Notificaciones',
              child: Semantics(
                button: true,
                label: hayPendiente ? 'Notificaciones: hay un aviso pendiente' : 'Notificaciones',
                excludeSemantics: true,
                onTap: () => setState(() => _abierto = !_abierto),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(radioControlEscritorio),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(radioControlEscritorio),
                    onTap: () => setState(() => _abierto = !_abierto),
                    child: SizedBox(
                      width: Medidas.alturaControl,
                      height: Medidas.alturaControl,
                      child: IconoPlz(
                        IconosPlazoleta.notificationsOutlined,
                        size: 20,
                        color: colores.textoSecundario,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (hayPendiente)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colores.acento,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Un aviso de Mercado Pago dentro del panel de la campanita: qué pasó, con qué venta se cruzó y "Visto" para sacarlo.
class _AvisoMpEnPanel extends StatelessWidget {
  const _AvisoMpEnPanel({required this.aviso, required this.onVisto});

  final AvisoParaMostrar aviso;
  final VoidCallback? onVisto;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: ValueKey('aviso_mp_${aviso.aviso.idServidor}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(aviso.titulo, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: Espaciado.xs),
        Text(aviso.texto, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: Espaciado.sm),
        BotonSecundario(texto: 'Visto', onPressed: onVisto),
      ],
    );
  }
}

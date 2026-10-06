// "Caja ▾" del mock v4 (`.cajabtn` y `.cajapop`), hecho desde cero: a la izquierda de la barra, el estado de la caja con
// su punto de color ("Caja · Ana", "Caja cerrada", "Caja de ayer sin cerrar") y, al tocarlo, un menú flotante de 380 px
// con todo lo que se hace con la caja. El menú sube 18 px al aparecer (`up`, 220 ms) y se cierra con Esc o tocando
// afuera.
//
// Es de presentación: no sabe de la base ni de los diálogos. Quien lo arma le pasa el estado y las acciones con su
// `onTap` (`acciones_caja.dart`).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../kit/kit.dart';

enum EstadoCajaNavbar { abierta, cerrada, deAyerSinCerrar }

/// Una fila del menú de caja.
class AccionMenuCaja {
  const AccionMenuCaja({
    required this.clave,
    required this.etiqueta,
    required this.icono,
    required this.onTap,
    this.nota,
    this.atajo,
    this.peligro = false,
    this.separadorAntes = false,
  });

  /// Estable, para las llaves de los tests (`Key('menu_caja_$clave')`).
  final String clave;
  final String etiqueta;
  final Ic icono;

  /// Null: la fila se ve apagada y no hace nada.
  final VoidCallback? onTap;

  /// Marca chica a la derecha en ámbar ("pendiente").
  final String? nota;

  /// Atajo impreso a la derecha ("Alt+I").
  final String? atajo;

  /// En rojo (cerrar la caja).
  final bool peligro;
  final bool separadorAntes;
}

class BotonCaja extends StatefulWidget {
  const BotonCaja({super.key, required this.estado, required this.acciones, this.nombre, this.detalle});

  final EstadoCajaNavbar estado;

  /// Quién tiene la caja ("Caja · Ana"). Sin nombre: "Caja abierta".
  final String? nombre;

  /// Cuándo se abrió ("desde 8:02"), para la cabecera del menú.
  final String? detalle;
  final List<AccionMenuCaja> acciones;

  @override
  State<BotonCaja> createState() => _BotonCajaState();
}

class _BotonCajaState extends State<BotonCaja> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  String get _etiqueta => switch (widget.estado) {
        EstadoCajaNavbar.abierta => widget.nombre == null || widget.nombre!.isEmpty ? 'Caja abierta' : 'Caja · ${widget.nombre}',
        EstadoCajaNavbar.cerrada => 'Caja cerrada',
        EstadoCajaNavbar.deAyerSinCerrar => 'Caja de ayer sin cerrar',
      };

  String get _cabecera {
    final quien = widget.nombre == null || widget.nombre!.isEmpty ? '' : ' · ${widget.nombre}';
    final desde = widget.detalle == null ? '' : ' · ${widget.detalle}';
    return switch (widget.estado) {
      EstadoCajaNavbar.abierta => 'Caja abierta$quien$desde',
      EstadoCajaNavbar.cerrada => 'Caja cerrada',
      EstadoCajaNavbar.deAyerSinCerrar => 'Sesión de ayer sin cerrar$desde',
    };
  }

  void _alternar() => setState(() => _portal.isShowing ? _portal.hide() : _portal.show());

  void _cerrar() {
    if (_portal.isShowing) setState(_portal.hide);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final abierto = _portal.isShowing;
    final colorPunto = switch (widget.estado) {
      EstadoCajaNavbar.abierta => p.efe,
      EstadoCajaNavbar.cerrada => p.soft,
      EstadoCajaNavbar.deAyerSinCerrar => p.w,
    };
    return TapRegion(
      groupId: _link,
      onTapOutside: (_) => _cerrar(),
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 17),
          child: Align(
            alignment: Alignment.topLeft,
            child: TapRegion(
              groupId: _link,
              child: CallbackShortcuts(
                bindings: {const SingleActivator(LogicalKeyboardKey.escape): _cerrar},
                child: FocusScope(
                  autofocus: true,
                  child: Aparecer.arriba(child: _Menu(cabecera: _cabecera, colorPunto: colorPunto, acciones: widget.acciones, alElegir: _cerrar)),
                ),
              ),
            ),
          ),
        ),
        child: CompositedTransformTarget(
          link: _link,
          child: AlPasar(
            builder: (encima) => Tocable(
              key: const Key('boton_caja'),
              onTap: _alternar,
              radio: 23,
              etiqueta: 'Caja: $_etiqueta',
              seleccionado: abierto,
              tooltip: 'Arqueo, turno, gasto, ingreso, cerrar caja',
              child: AnimatedContainer(
                duration: ms(200),
                height: 46,
                padding: const EdgeInsets.fromLTRB(14, 0, 16, 0),
                decoration: BoxDecoration(color: encima || abierto ? p.s2 : p.s, borderRadius: BorderRadius.circular(999)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: colorPunto,
                        shape: BoxShape.circle,
                        boxShadow: widget.estado == EstadoCajaNavbar.abierta
                            ? [BoxShadow(color: p.efe.withValues(alpha: .22), spreadRadius: 4)]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(_etiqueta, maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo(15, 600, color: p.tinta)),
                    ),
                    const SizedBox(width: 10),
                    Icono(Ic.chevd, size: 14, color: p.tinta, grosor: 2.6),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({required this.cabecera, required this.colorPunto, required this.acciones, required this.alElegir});

  final String cabecera;
  final Color colorPunto;
  final List<AccionMenuCaja> acciones;
  final VoidCallback alElegir;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      width: 380,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.papel,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: p.pelo),
        boxShadow: const [BoxShadow(color: Color(0x400D1017), blurRadius: 80, offset: Offset(0, 30))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                children: [
                  Container(width: 9, height: 9, decoration: BoxDecoration(color: colorPunto, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(cabecera, style: estilo(14, 600, color: p.mute))),
                ],
              ),
            ),
            for (final a in acciones) ...[
              if (a.separadorAntes) Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Divider(height: 1, thickness: 1, color: p.pelo)),
              _FilaMenu(accion: a, alElegir: alElegir),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilaMenu extends StatelessWidget {
  const _FilaMenu({required this.accion, required this.alElegir});
  final AccionMenuCaja accion;
  final VoidCallback alElegir;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final activa = accion.onTap != null;
    final color = !activa ? p.soft : (accion.peligro ? p.b : p.tinta);
    final colorIcono = !activa ? p.soft : (accion.peligro ? p.b : p.mute);
    return AlPasar(
      builder: (encima) => Tocable(
        key: Key('menu_caja_${accion.clave}'),
        onTap: !activa
            ? null
            : () {
                alElegir();
                accion.onTap!();
              },
        radio: 22,
        child: AnimatedContainer(
          duration: ms(150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(color: encima && activa ? p.s : p.s.withValues(alpha: 0), borderRadius: BorderRadius.circular(22)),
          child: Row(
            children: [
              Icono(accion.icono, size: 22, color: colorIcono, grosor: 1.9),
              const SizedBox(width: 14),
              Expanded(child: Text(accion.etiqueta, style: estilo(17, 500, color: color))),
              if (accion.nota != null) Text(accion.nota!, style: estilo(12.5, 600, color: p.w)),
              if (accion.atajo != null) Text(accion.atajo!, style: estilo(12.5, 600, color: p.soft)),
            ],
          ),
        ),
      ),
    );
  }
}

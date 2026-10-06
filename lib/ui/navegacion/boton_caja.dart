// Botón "Caja ▾" de la navbar (rediseño v4, 2026-10-05): a la izquierda de la barra, con el estado de la caja a la vista
// ("Caja abierta", "Caja cerrada", "Caja de ayer sin cerrar") y, al tocarlo, un menú con todo lo que se hace con la caja:
// arqueo, cambio de turno, gasto, ingreso y cerrar (o abrir). Reemplaza a los dos íconos sueltos del extremo derecho
// ("Cambiar de turno" y "Cerrar caja"), que solo estaban en Venta y no se entendían sin el tooltip.
//
// Es un widget de presentación: no sabe de la base ni de los diálogos. Quien lo arma (`PantallaVenta`) le pasa el estado y
// la lista de acciones, ya con su `onTap`. Usa `MenuAnchor` de Flutter: se cierra con Esc o tocando afuera y se maneja con
// el teclado sin código propio.

import 'package:flutter/material.dart';

import '../tema/acentos.dart';
import '../tema/iconos.dart';
import '../tema/presionable.dart';
import '../tema/tokens.dart';

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
  final IconData icono;

  /// Null: la fila se ve apagada y no hace nada (ej. no hay caja abierta).
  final VoidCallback? onTap;

  /// Marca chica a la derecha ("pendiente").
  final String? nota;

  /// Atajo de teclado impreso a la derecha ("Alt+I").
  final String? atajo;

  /// Se pinta con el color de error (cerrar la caja).
  final bool peligro;
  final bool separadorAntes;
}

class BotonCaja extends StatelessWidget {
  const BotonCaja({super.key, required this.estado, required this.acciones, this.detalle});

  final EstadoCajaNavbar estado;

  /// Línea de arriba del menú ("desde las 8:02"). Opcional.
  final String? detalle;
  final List<AccionMenuCaja> acciones;

  /// Lo que dice el botón. Corto a propósito: la columna de la izquierda de la navbar no es ancha (en una ventana de
  /// 1366 px, "Caja de ayer sin cerrar" no entra); el detalle completo va en la cabecera del menú.
  String get _etiqueta => switch (estado) {
    EstadoCajaNavbar.abierta => 'Caja abierta',
    EstadoCajaNavbar.cerrada => 'Caja cerrada',
    EstadoCajaNavbar.deAyerSinCerrar => 'Caja de ayer',
  };

  String get _titularMenu => switch (estado) {
    EstadoCajaNavbar.abierta => 'Caja abierta',
    EstadoCajaNavbar.cerrada => 'Caja cerrada',
    EstadoCajaNavbar.deAyerSinCerrar => 'Caja de ayer sin cerrar',
  };

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final acentos = context.acentosPlazoleta;
    final colorPunto = switch (estado) {
      EstadoCajaNavbar.abierta => acentos.ganancia,
      EstadoCajaNavbar.cerrada => colores.textoTenue,
      EstadoCajaNavbar.deAyerSinCerrar => acentos.alerta,
    };
    final estilo = Theme.of(context).textTheme.bodyMedium!;
    return MenuAnchor(
      alignmentOffset: const Offset(0, Espaciado.sm),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colores.fondo),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(12),
        shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.28)),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(Espaciado.sm)),
        minimumSize: const WidgetStatePropertyAll(Size(300, 0)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
      ),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Espaciado.md, Espaciado.sm, Espaciado.md, Espaciado.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Punto(color: colorPunto, tamanio: 9),
              const SizedBox(width: Espaciado.sm),
              Text(
                detalle == null ? _titularMenu : '$_titularMenu · $detalle',
                style: estilo.copyWith(color: colores.textoSecundario, fontSize: 13, fontWeight: Pesos.fuerte),
              ),
            ],
          ),
        ),
        for (final a in acciones) ...[
          if (a.separadorAntes) Divider(height: Espaciado.md, indent: Espaciado.sm, endIndent: Espaciado.sm, color: colores.borde),
          _FilaMenu(accion: a),
        ],
      ],
      builder: (context, controlador, _) => Semantics(
        button: true,
        label: 'Caja: $_etiqueta',
        excludeSemantics: true,
        onTap: () => controlador.isOpen ? controlador.close() : controlador.open(),
        child: Presionable(
          key: const Key('boton_caja'),
          radio: 999,
          color: colores.fondoBloque,
          onTap: () => controlador.isOpen ? controlador.close() : controlador.open(),
          child: Container(
            height: Medidas.alturaControl,
            padding: const EdgeInsets.only(left: Espaciado.md, right: Espaciado.md),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Punto(color: colorPunto),
                const SizedBox(width: Espaciado.sm),
                Flexible(
                  child: Text(
                    _etiqueta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: estilo.copyWith(fontWeight: Pesos.fuerte, color: colores.textoPrimario, letterSpacing: -0.16),
                  ),
                ),
                const SizedBox(width: Espaciado.xs),
                IconoPlz(IconosPlazoleta.expandMore, size: 18, color: colores.textoSecundario),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Punto extends StatelessWidget {
  const _Punto({required this.color, this.tamanio = 8});

  final Color color;
  final double tamanio;

  @override
  Widget build(BuildContext context) =>
      Container(width: tamanio, height: tamanio, decoration: BoxDecoration(shape: BoxShape.circle, color: color));
}

class _FilaMenu extends StatelessWidget {
  const _FilaMenu({required this.accion});

  final AccionMenuCaja accion;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final acentos = context.acentosPlazoleta;
    final activa = accion.onTap != null;
    final color = !activa ? colores.textoTenue : (accion.peligro ? colores.error : colores.textoPrimario);
    final estilo = Theme.of(context).textTheme.bodyLarge!;
    return MenuItemButton(
      key: Key('menu_caja_${accion.clave}'),
      onPressed: accion.onTap,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(300, 46)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: Espaciado.md)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
        overlayColor: WidgetStatePropertyAll(colores.fondoBloque),
      ),
      child: SizedBox(
        width: 276,
        child: Row(
        children: [
          IconoPlz(accion.icono, size: 22, color: !activa ? colores.textoTenue : (accion.peligro ? colores.error : colores.textoSecundario)),
          const SizedBox(width: Espaciado.md),
          Expanded(child: Text(accion.etiqueta, style: estilo.copyWith(color: color, fontWeight: Pesos.medium))),
          if (accion.nota != null)
            Text(accion.nota!, style: estilo.copyWith(fontSize: 12.5, fontWeight: Pesos.fuerte, color: acentos.alerta)),
          if (accion.atajo != null)
            Text(accion.atajo!, style: estilo.copyWith(fontSize: 12.5, fontWeight: Pesos.fuerte, color: colores.textoTenue)),
        ],
      ),
      ),
    );
  }
}

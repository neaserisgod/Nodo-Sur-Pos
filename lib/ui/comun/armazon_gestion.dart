// El armazón único de toda pantalla de gestión (paso 1 del kit, el dueño):
// navbar superior + encabezado + contenido, con el padding de pantalla ya
// resuelto. Toda pantalla de gestión empieza por acá — la pantalla de venta
// no, sigue con su propio manejo (`NavbarSuperior` armada a mano, mismo
// motivo que antes con `BarraLateral`).

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../navegacion/busqueda_contextual.dart';
import '../navegacion/envoltura_con_navbar_superior.dart';
import '../tema/tokens.dart';
import 'encabezado_pantalla.dart';

class PantallaGestion extends StatelessWidget {
  const PantallaGestion({
    super.key,
    required this.db,
    required this.claveActiva,
    required this.usuarioId,
    this.sesionCajaId,
    required this.titulo,
    this.subtitulo,
    this.accion,
    this.busqueda,
    required this.child,
  });

  final AppDatabase db;
  final String claveActiva;
  final int usuarioId;
  final int? sesionCajaId;
  final String titulo;

  /// Línea de contexto arriba del contenido ("Hoy · sábado 26 de
  /// septiembre"); ver `EncabezadoPantalla`.
  final String? subtitulo;

  /// Acción opcional a la derecha del título (ej. "+ Nuevo").
  final Widget? accion;

  /// Qué busca el campo de arriba en esta pantalla (ver
  /// `busqueda_contextual.dart`); null = buscar productos para vender.
  final BusquedaContextual? busqueda;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: EnvolturaConNavbarSuperior(
          db: db,
          claveActiva: claveActiva,
          usuarioId: usuarioId,
          sesionCajaId: sesionCajaId,
          busqueda: busqueda,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Espaciado.xxl, Espaciado.lg, Espaciado.xxl, Espaciado.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EncabezadoPantalla(titulo: titulo, subtitulo: subtitulo, accion: accion),
                const SizedBox(height: Espaciado.lg),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

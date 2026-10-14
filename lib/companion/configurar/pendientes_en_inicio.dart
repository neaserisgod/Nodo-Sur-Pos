// La tarjeta "Te faltan N pasos" en Inicio (y en la Agenda, que es el inicio de un negocio de servicios), mientras el dueño no termine "Configurá tu negocio". No ocupa lugar cuando
// no falta nada (que es siempre, salvo en un negocio nuevo con pasos dejados para después).

import 'package:flutter/material.dart';

import '../kit/kit_ns.dart';
import 'asistente_negocio.dart';
import 'flujo_negocio.dart';
import 'negocio_nuevo.dart';

class PendientesEnInicio extends StatefulWidget {
  const PendientesEnInicio({super.key, this.margenLateral = margenNs});

  /// La Agenda ya tiene su propio margen.
  final double margenLateral;

  @override
  State<PendientesEnInicio> createState() => _PendientesEnInicioState();
}

class _PendientesEnInicioState extends State<PendientesEnInicio> {
  @override
  void initState() {
    super.initState();
    leerPasosPendientes();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<PasoNegocio>>(
      valueListenable: pasosPendientesNegocio,
      builder: (context, pendientes, _) {
        if (pendientes.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.fromLTRB(widget.margenLateral, 14, widget.margenLateral, 0),
          child: TarjetaConfiguracionPendiente(
            key: const Key('inicio-pendientes'),
            pendientes: pendientes,
            alSeguir: () => abrirAsistenteNegocio(
              context,
              paso: PasoNegocio.values.firstWhere(pendientes.contains),
              desdeInicio: true,
            ),
          ),
        );
      },
    );
  }
}

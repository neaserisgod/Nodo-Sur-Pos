// La tarjeta "Te faltan N pasos" en Inicio, mientras el dueño no termine "Configurá tu negocio". No ocupa lugar cuando
// no falta nada (que es siempre, salvo en un negocio nuevo con pasos dejados para después).

import 'package:flutter/material.dart';

import '../../ui/tema/tokens.dart';
import 'asistente_negocio.dart';
import 'flujo_negocio.dart';
import 'negocio_nuevo.dart';

class PendientesEnInicio extends StatefulWidget {
  const PendientesEnInicio({super.key});

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
          padding: const EdgeInsets.fromLTRB(Espaciado.lg, Espaciado.lg, Espaciado.lg, 0),
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

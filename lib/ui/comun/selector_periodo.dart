// Selector de período (fase 13): "vendido" y "ganancia" no se fijan a un
// período fijo — este selector, siempre en el mismo lugar (arriba de la
// lista, regla 5 del principio de fatiga visual, `DISENO.md`), decide desde
// cuándo se cuenta. Compartido entre Proveedores y Productos — un solo
// widget, no una copia por pantalla.

import 'package:flutter/material.dart';

import '../../domain/periodo.dart';
import '../tema/tema.dart';

const Map<PeriodoResumen, String> etiquetasPeriodo = {
  PeriodoResumen.hoy: 'Hoy',
  PeriodoResumen.semana: 'Semana',
  PeriodoResumen.mes: 'Mes',
  PeriodoResumen.desdeUltimoPago: 'Desde el último pago',
};

class SelectorPeriodo extends StatelessWidget {
  const SelectorPeriodo({
    super.key,
    required this.valor,
    required this.onChanged,
  });

  final PeriodoResumen valor;
  final ValueChanged<PeriodoResumen> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<PeriodoResumen>(
        value: valor,
        isExpanded: true,
        borderRadius: BorderRadius.circular(radioControlEscritorio),
        items: [
          for (final entry in etiquetasPeriodo.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

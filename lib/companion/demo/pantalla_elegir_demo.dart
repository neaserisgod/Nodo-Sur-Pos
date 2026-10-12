// La primera pantalla de la demo (horsepos.com/demo/): qué negocio de ejemplo ver. Al elegir, se arma con todo cargado y se
// entra directo a la app, como el dueño (El dueño, 2026-10-12: "varios para elegir").

import 'package:flutter/material.dart';

import '../../servicios/registro_errores.dart';
import '../base_local.dart';
import '../emparejamiento.dart';
import '../kit/kit_ns.dart';
import '../pantalla_menu_companion.dart';
import 'semilla_demo.dart';

class PantallaElegirDemo extends StatefulWidget {
  const PantallaElegirDemo({super.key});

  @override
  State<PantallaElegirDemo> createState() => _PantallaElegirDemoState();
}

class _PantallaElegirDemoState extends State<PantallaElegirDemo> {
  NegocioDemo? _armando;
  String? _error;

  Future<void> _elegir(NegocioDemo negocio) async {
    if (_armando != null) return;
    setState(() {
      _armando = negocio;
      _error = null;
    });
    try {
      final duenio = await sembrarNegocioDemo(baseLocalCompanion(), negocio);
      await guardarUsuario(duenio);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute<void>(builder: (_) => const PantallaMenuCompanion()), (_) => false);
    } catch (e, pila) {
      registrarError('Armar la demo', e, pila);
      // Una base a medio armar no sirve: se vuelve a cargar la página para empezar de cero.
      if (mounted) {
        setState(() {
          _armando = null;
          _error = 'No se pudo armar el negocio de ejemplo. Recargá la página y probá de nuevo.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final armando = _armando;
    return PaginaArranqueNs(
      titulo: '¿Qué negocio querés ver?',
      bajada: 'Es una demo con datos de ejemplo. Dá turnos, cobrá y mirá la caja: nada es real y se borra al cerrar.',
      cuerpo: [
        for (final n in NegocioDemo.todos)
          OpcionNs(
            key: Key('demo-${n.rubro.clave}'),
            titulo: n.rubro.nombre,
            detalle: '${n.nombre} · ${n.rubro.descripcion}',
            marcada: armando == n,
            derecha: armando == n ? 'Armando…' : null,
            onTap: () => _elegir(n),
          ),
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad) else const InfoNs('Entrás como el dueño: ves todo lo que ve el dueño.'),
      ],
    );
  }
}

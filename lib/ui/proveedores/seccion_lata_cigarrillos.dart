// Panel de solo lectura de la lata de cigarrillos, para Distribuidora de Cigarrillos en
// Proveedores (El dueño, 2026-09-25). Reemplaza a Separar/Pagar, que para SC
// quedaban siempre en $0 sin explicar por qué: sus líneas no pasan por la
// reposición genérica (Regla 6 — la lata ya reserva el costo aparte, al
// cerrar caja), así que acá se muestra lo que sí existe para cigarrillos.

import 'package:flutter/material.dart';

import '../../domain/dinero.dart';
import '../comun/fila_dato.dart';
import '../tema/tokens.dart';
import 'proveedores_controlador.dart';

class SeccionLataCigarrillos extends StatefulWidget {
  const SeccionLataCigarrillos({super.key, required this.controlador});

  final ProveedoresControlador controlador;

  @override
  State<SeccionLataCigarrillos> createState() => _SeccionLataCigarrillosState();
}

class _SeccionLataCigarrillosState extends State<SeccionLataCigarrillos> {
  late final _datos = widget.controlador.datosLata();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _datos,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox(height: Medidas.alturaControl);
        }
        final d = snapshot.data;
        final secundario = TextStyle(color: context.colores.textoSecundario);
        if (d == null) {
          return Text(
            'Sin caja abierta: no hay números de hoy.',
            style: secundario,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilaDato(
              etiqueta: 'Saldo de la lata',
              valor: formatearARS(d.saldoLataCentavos),
              enfasis: true,
            ),
            const SizedBox(height: Espaciado.sm),
            FilaDato(
              etiqueta: 'Vendido hoy en cigarrillos',
              valor: formatearARS(d.vendidoHoyCentavos),
            ),
            const SizedBox(height: Espaciado.sm),
            FilaDato(
              etiqueta: 'Pendiente de cierres anteriores',
              valor: formatearARS(d.pendienteArrastradoCentavos),
            ),
            const SizedBox(height: Espaciado.sm),
            Text(
              'El saldo no incluye lo que se separa al cerrar la caja de hoy.',
              style: secundario,
            ),
          ],
        );
      },
    );
  }
}

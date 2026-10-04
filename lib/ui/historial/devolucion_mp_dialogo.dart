// Después de anular una venta cobrada con la Point: "¿Devolver $X al cliente por Mercado Pago?" (etapa B, el dueño
// 2026-10-04: preguntar cada vez). Solo aparece si la venta se cobró con la Point y quien vinculó este equipo puede devolver
// (`puedeOfrecerDevolucion`); si no, no se pregunta nada y todo sigue como antes. La usan la PC y el celular.

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../domain/dinero.dart';
import '../../servicios/cuenta_nube.dart';
import '../../servicios/devolucion_mp.dart';
import '../../servicios/nube.dart' show nubeApp;
import '../comun/botones.dart';
import '../comun/modal.dart';

/// En la PC: la orden está en [db] y la cuenta es la de la app (`nubeApp`).
Future<void> ofrecerDevolucionMp(BuildContext context, AppDatabase db, int ventaId, {AlmacenCuenta? almacen, ClienteNube? cliente}) async {
  final cobro = await cobroPointDeVenta(db, ventaId);
  if (!context.mounted) return;
  await ofrecerDevolucionDeCobro(context, cobro, almacen: almacen ?? nubeApp?.almacen, cliente: cliente ?? nubeApp?.cliente, db: db);
}

/// La pregunta, con el estilo de cada lado: la PC usa su `Modal`; el celular pasa su hoja ([preguntar]).
typedef PreguntarDevolucion = Future<bool?> Function(BuildContext context, String monto);

Future<bool?> _preguntarEnPc(BuildContext context, String monto) => mostrarModal<bool>(
  context,
  builder: (context) => Modal(
    titulo: '¿Devolver por Mercado Pago?',
    contenido: Text('Esta venta se cobró con la terminal ($monto). ¿Devolvérselo al cliente por Mercado Pago?'),
    botones: [
      BotonSecundario(texto: 'No', onPressed: () => Navigator.of(context).pop(false)),
      BotonPrimario(texto: 'Sí, devolver $monto', onPressed: () => Navigator.of(context).pop(true)),
    ],
  ),
);

Future<void> ofrecerDevolucionDeCobro(
  BuildContext context,
  CobroPoint? cobro, {
  required AlmacenCuenta? almacen,
  required ClienteNube? cliente,
  AppDatabase? db,
  PreguntarDevolucion preguntar = _preguntarEnPc,
}) async {
  if (!await puedeOfrecerDevolucion(cobro, almacen: almacen, cliente: cliente) || !context.mounted) return;
  final monto = formatearARS(cobro!.montoCentavos);
  final devolver = await preguntar(context, monto);
  if (devolver != true || !context.mounted) return;
  final r = await devolverPorMp(cobro, almacen: almacen!, cliente: cliente!, db: db);
  if (!context.mounted) return;
  final texto = switch (r.resultado) {
    ResultadoDevolucionMp.devuelta => 'Listo: se le devolvieron $monto al cliente por Mercado Pago.',
    ResultadoDevolucionMp.yaDevuelta => 'Ese cobro ya estaba devuelto en Mercado Pago.',
    _ => 'No se pudo devolver: ${r.mensaje ?? 'error desconocido'}. Podés hacerlo desde la app de Mercado Pago.',
  };
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
}

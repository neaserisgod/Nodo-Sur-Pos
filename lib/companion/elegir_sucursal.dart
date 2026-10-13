// En qué negocio y sucursal entra este celular, al entrar con Google desde la app. Antes se elegía en la página /vincular/
// del sitio; sin navegador, se pregunta acá con las mismas opciones que daba el sitio, más "Crear un negocio nuevo": una misma
// cuenta puede tener varios negocios (El dueño, 2026-10-13: un almacén, una barbería, un emprendimiento de belleza…), cada uno
// con su plan.

import 'package:flutter/material.dart';

import '../domain/cuentas_del_celular.dart' show sucursalPrincipal;
import '../servicios/cuenta_nube.dart' show SucursalParaElegir;
import 'kit/kit_ns.dart';

/// Lo que eligió la persona.
sealed class EleccionDeNegocio {
  const EleccionDeNegocio();
}

class EligioSucursal extends EleccionDeNegocio {
  const EligioSucursal(this.opcion);
  final SucursalParaElegir opcion;
}

class CrearNegocio extends EleccionDeNegocio {
  const CrearNegocio(this.nombre);
  final String nombre;
}

/// Null si cierra la hoja sin elegir.
Future<EleccionDeNegocio?> elegirNegocio(BuildContext context, List<SucursalParaElegir> opciones) async {
  final porNegocio = <int, int>{};
  for (final o in opciones) {
    porNegocio[o.negocio] = (porNegocio[o.negocio] ?? 0) + 1;
  }
  // La sucursal solo se nombra si el negocio tiene más de una (casi todos tienen solo la principal).
  String texto(SucursalParaElegir o) =>
      porNegocio[o.negocio]! > 1 && o.nombreSucursal != sucursalPrincipal ? '${o.nombreNegocio} · ${o.nombreSucursal}' : o.nombreNegocio;
  final eleccion = await mostrarHojaNs<Object>(
    context,
    builder: (ctx) => HojaNs(
      titulo: opciones.isEmpty ? 'Creá tu negocio' : '¿En qué negocio entrás?',
      texto: opciones.isEmpty
          ? 'Todavía no tenés un negocio propio con esta cuenta.'
          : 'Cada negocio tiene sus propios datos en este celular, y su propio plan.',
      // Los negocios van en los bloques, que se deslizan: con muchos, los botones de abajo no se van de la pantalla.
      bloques: [
        for (final o in opciones)
          KeyedSubtree(
            key: Key('negocio_${o.negocio}_${o.sucursal}'),
            child: BotonNs.secundario(ctx, texto(o), () => Navigator.of(ctx).pop(o)),
          ),
      ],
      botones: [
        KeyedSubtree(
          key: const Key('crear_negocio'),
          child: BotonNs.primario(ctx, 'Crear un negocio nuevo', () => Navigator.of(ctx).pop(#crear)),
        ),
        BotonNs.secundario(ctx, 'Cancelar', () => Navigator.of(ctx).pop()),
      ],
    ),
  );
  if (eleccion is SucursalParaElegir) return EligioSucursal(eleccion);
  if (eleccion == #crear && context.mounted) {
    final nombre = await _pedirNombre(context);
    return nombre == null ? null : CrearNegocio(nombre);
  }
  return null;
}

Future<String?> _pedirNombre(BuildContext context) {
  final control = TextEditingController();
  return mostrarHojaNs<String>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, refrescar) {
        final valido = control.text.trim().length >= 2;
        void crear() => Navigator.of(ctx).pop(control.text.trim());
        return HojaNs(
          titulo: 'Nombre del negocio',
          texto: 'Arranca vacío y paga su propio plan. Lo podés cambiar después.',
          bloques: [
            TextField(
              key: const Key('nombre_negocio'),
              controller: control,
              autofocus: true,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Ej.: Barbería del Centro'),
              onChanged: (_) => refrescar(() {}),
              onSubmitted: (_) => valido ? crear() : null,
            ),
          ],
          botones: [
            BotonNs.primario(ctx, 'Crear', valido ? crear : null, habilitado: valido),
            BotonNs.secundario(ctx, 'Cancelar', () => Navigator.of(ctx).pop()),
          ],
        );
      },
    ),
  );
}

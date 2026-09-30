// Porcentaje de ganancia por proveedor (El dueño, 2026-09-29: "simplificar el
// sistema de precios: un selector de porcentaje por proveedor + redondeo
// para arriba a la próxima centena, exceptuando los cigarros").
//
// Elegir el porcentaje solo lo guarda; los precios no cambian hasta tocar
// "Aplicar a los precios", que primero muestra cuántos cambian y de a cuánto.
// Después de aplicarlo, cada vez que cambia el costo de un producto de este
// proveedor su precio se recalcula solo — salvo los marcados con precio fijo y
// los cigarrillos (`lib/data/repositorio_productos.dart`).

import 'package:flutter/material.dart';

import '../../data/repositorio_productos.dart' show CambioDePrecioPropuesto;
import '../../domain/dinero.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/modal.dart';
import '../comun/tarjetas.dart';
import '../tema/tokens.dart';
import 'proveedores_controlador.dart';

/// Porcentajes a un toque, en basis points. El resto se carga con "Otro".
const _atajos = [2000, 3000, 4000, 5000, 7000, 10000];

String _porcentajeTexto(int bp) =>
    '${bp % 100 == 0 ? bp ~/ 100 : (bp / 100).toStringAsFixed(1)}%';

/// Pide un porcentaje cualquiera ("Otro %"): devuelve basis points o null si se
/// cancela. Lo usan el selector del proveedor y el creador de promos.
Future<int?> pedirOtroPorcentaje(BuildContext context, {int? actualBp}) =>
    mostrarModal<int>(
      context,
      builder: (_) => _DialogoOtroPorcentaje(actualBp: actualBp),
    );

class SelectorPorcentajeProveedor extends StatelessWidget {
  const SelectorPorcentajeProveedor({super.key, required this.controlador});

  final ProveedoresControlador controlador;

  Future<void> _otro(BuildContext context) async {
    final bp = await pedirOtroPorcentaje(
      context,
      actualBp: controlador.seleccionado?.markupBp,
    );
    if (bp != null) await controlador.guardarPorcentaje(bp);
  }

  Future<void> _aplicar(BuildContext context) async {
    final cambios = await controlador.cambiosPropuestos();
    if (!context.mounted) return;
    final confirmar = await mostrarModal<bool>(
      context,
      builder: (_) => _DialogoAplicar(
        proveedor: controlador.seleccionado!.nombre,
        bp: controlador.seleccionado!.markupBp!,
        cambios: cambios,
      ),
    );
    if (confirmar == true) await controlador.aplicarPorcentaje();
  }

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final bp = controlador.seleccionado?.markupBp;
    final esAtajo = bp == null || _atajos.contains(bp);

    return Wrap(
      spacing: Espaciado.md,
      runSpacing: Espaciado.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Ganancia sobre el costo',
          style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.medium),
        ),
        GrupoPildoras<int?>(
          opciones: [
            (null, 'Sin %'),
            for (final a in _atajos) (a, _porcentajeTexto(a)),
            if (!esAtajo) (bp, _porcentajeTexto(bp)),
          ],
          elegida: bp,
          onElegir: controlador.guardarPorcentaje,
        ),
        BotonSecundario(texto: 'Otro %', onPressed: () => _otro(context)),
        if (bp != null)
          BotonPrimario(
            texto: 'Aplicar a los precios',
            onPressed: () => _aplicar(context),
          )
        else
          Text(
            'Sin porcentaje: los precios se cargan a mano.',
            style: textTheme.bodySmall?.copyWith(
              color: colores.textoSecundario,
            ),
          ),
      ],
    );
  }
}

class _DialogoOtroPorcentaje extends StatefulWidget {
  const _DialogoOtroPorcentaje({required this.actualBp});

  final int? actualBp;

  @override
  State<_DialogoOtroPorcentaje> createState() => _DialogoOtroPorcentajeState();
}

class _DialogoOtroPorcentajeState extends State<_DialogoOtroPorcentaje> {
  late final _ctrl = TextEditingController(
    text: widget.actualBp == null
        ? ''
        : (widget.actualBp! / 100).toString().replaceAll(RegExp(r'\.0$'), ''),
  );
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _confirmar() {
    // Mismo truco que el descuento: "35" → 3500 centésimas = 35,00%.
    final int bp;
    try {
      bp = parsearARS(_ctrl.text);
    } on FormatException {
      setState(() => _error = 'Escribí un porcentaje, por ejemplo 35');
      return;
    }
    if (bp <= 0 || bp > 100000) {
      setState(() => _error = 'El porcentaje tiene que estar entre 0 y 1000');
      return;
    }
    Navigator.of(context).pop(bp);
  }

  @override
  Widget build(BuildContext context) {
    return Modal(
      titulo: 'Otro porcentaje',
      subtitulo: 'Ganancia sobre el costo',
      ancho: 480,
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CampoPlata(
            key: const Key('campo_otro_porcentaje'),
            controller: _ctrl,
            etiqueta: 'Porcentaje (%)',
            autofocus: true,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _confirmar(),
          ),
          if (_error != null) ...[
            const SizedBox(height: Espaciado.sm),
            Text(_error!, style: TextStyle(color: context.colores.error)),
          ],
        ],
      ),
      botones: [
        BotonSecundario(
          texto: 'Cancelar',
          onPressed: () => Navigator.of(context).pop(),
        ),
        BotonPrimario(texto: 'Guardar', onPressed: _confirmar),
      ],
    );
  }
}

class _DialogoAplicar extends StatelessWidget {
  const _DialogoAplicar({
    required this.proveedor,
    required this.bp,
    required this.cambios,
  });

  final String proveedor;
  final int bp;
  final List<CambioDePrecioPropuesto> cambios;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colores = context.colores;
    const muestra = 6;
    return Modal(
      titulo: 'Aplicar ${_porcentajeTexto(bp)} a $proveedor',
      subtitulo:
          'Costo + ${_porcentajeTexto(bp)}, redondeado hacia arriba a la próxima centena',
      ancho: 620,
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cambios.isEmpty)
            Text(
              'Ningún precio cambia: los productos con costo ya están al precio que da el porcentaje, '
              'o tienen el precio fijo. Los cigarrillos nunca se tocan.',
              style: textTheme.bodyMedium,
            )
          else ...[
            Text(
              cambios.length == 1
                  ? 'Cambia el precio de 1 producto:'
                  : 'Cambian los precios de ${cambios.length} productos:',
              style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.medium),
            ),
            const SizedBox(height: Espaciado.sm),
            for (final c in cambios.take(muestra))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.producto.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      c.precioActualCentavos == null
                          ? 'sin precio'
                          : formatearARS(c.precioActualCentavos!),
                      style: textTheme.bodySmall
                          ?.copyWith(color: colores.textoSecundario)
                          .tabular,
                    ),
                    const SizedBox(width: Espaciado.sm),
                    const Icon(Icons.arrow_forward, size: 14),
                    const SizedBox(width: Espaciado.sm),
                    Text(
                      formatearARS(c.precioNuevoCentavos),
                      style: textTheme.bodyMedium
                          ?.copyWith(fontWeight: Pesos.fuerte)
                          .tabular,
                    ),
                  ],
                ),
              ),
            if (cambios.length > muestra)
              Padding(
                padding: const EdgeInsets.only(top: Espaciado.xs),
                child: Text(
                  'y ${cambios.length - muestra} más…',
                  style: textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: Espaciado.md),
            BloqueSuave(
              child: Text(
                'Los productos con precio fijo, los cigarrillos y los que no tienen costo no se tocan. '
                'Cada cambio queda en el historial de precios.',
                style: textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
      botones: [
        BotonSecundario(
          texto: 'Cancelar',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        BotonPrimario(
          texto: cambios.isEmpty ? 'Entendido' : 'Aplicar',
          onPressed: () => Navigator.of(context).pop(cambios.isNotEmpty),
        ),
      ],
    );
  }
}

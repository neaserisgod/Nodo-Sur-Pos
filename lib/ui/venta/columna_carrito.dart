// Columna central: el carrito, en un único bloque bento. Una línea por
// producto, la última agregada resaltada con el acento, el nombre en rojo
// si el stock quedó en 0 o negativo.
//
// Fase 13 (principio rector, `DISENO.md`): el padding ajustado y la fila
// angosta que tenía esta columna eran una regla escrita para 720px de alto
// (hardware 2008) — ya no queda una excepción documentada al padding
// estándar de `Bloque`. Con 1080px de sobra, cada fila usa el mismo aire
// que cualquier otra lista de la app, y su contenido (nombre → cantidad →
// plata) tiene un ancho máximo (`Medidas.anchoFilaCarrito`) en vez de
// estirarse hasta el borde de una columna que hoy sobra en ancho: apretar
// cuando no hace falta es exactamente lo que cansa la vista.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/dinero.dart';
import '../../domain/venta.dart';
import '../comun/aviso_superior.dart';
import '../tema/tokens.dart';
import 'dialogo_editar_cantidad.dart';
import 'columna_busqueda.dart' show TeclaAtajo;
import 'tacto_venta.dart';
import 'cancelar_venta_con_deshacer.dart';
import 'venta_controlador.dart';
import '../tema/iconos.dart';
import '../tema/acentos.dart';
import '../tema/movimiento.dart';

class ColumnaCarrito extends StatelessWidget {
  const ColumnaCarrito({
    super.key,
    this.ventaConfirmada,
    this.totalConfirmadoCentavos,
    required this.onImprimir,
  });

  /// Id y total de la última venta cobrada en esta pantalla (bug real: cobrar no daba ninguna señal de que la venta había entrado).
  /// Mientras el carrito siga vacío, ocupa el lugar del texto de "empezá la venta" — deja de mostrarse solo, sin timer, en cuanto
  /// entra la primera línea de la venta siguiente.
  final int? ventaConfirmada;
  final int? totalConfirmadoCentavos;

  /// Imprimir aparece acá, junto al acuse, mientras hay algo reciente para imprimir.
  final VoidCallback onImprimir;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<VentaControlador>();

    // Las pestañas y el carrito viven adentro del panel gris de la derecha (`CuerpoVenta`): acá no hay fondo propio.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _BarraVentasAbiertas(),
        const SizedBox(height: 14),
        Expanded(
          child: c.carrito.isEmpty
              ? Center(
                  child: _EstadoVacio(
                    ventaId: ventaConfirmada,
                    totalCentavos: totalConfirmadoCentavos,
                    onImprimir: onImprimir,
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  itemCount: c.carrito.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 6),
                  // Con la clave por producto, sacar una línea del medio no hace re-entrar a las de abajo.
                  findItemIndexCallback: (clave) {
                    for (var i = 0; i < c.carrito.length; i++) {
                      if (_claveLinea(c.carrito[i], i) == clave) return i;
                    }
                    return null;
                  },
                  itemBuilder: (context, index) {
                    final linea = c.carrito[index];
                    return Entrada(
                      key: _claveLinea(linea, index),
                      desplazamiento: 8,
                      child: _LineaCarrito(
                        linea: linea,
                        index: index,
                        esUltima: index == c.indiceUltimaLinea,
                        stockNegativo: _stockQuedaEnCeroONegativo(context, linea),
                        descripcionCantidad: _descripcionCantidad(linea),
                        alEditar: () => linea is LineaVentaPorUnidad
                            ? _editarCantidad(context, index, linea)
                            : _editarGramos(context, index, linea as LineaVentaPesable),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Una línea por producto (sumar el mismo producto sube la cantidad); "Varios" puede repetirse, así que su clave
  /// lleva también la posición.
  ValueKey<String> _claveLinea(LineaVenta linea, int index) =>
      ValueKey('linea-${linea.productoId}${linea.esVarios ? '-$index' : ''}');

  String _descripcionCantidad(LineaVenta linea) {
    return switch (linea) {
      LineaVentaPorUnidad u => 'x${u.cantidad}',
      LineaVentaPesable p => '${p.gramos} g',
    };
  }

  Future<void> _editarCantidad(
    BuildContext context,
    int index,
    LineaVentaPorUnidad linea,
  ) async {
    final nuevaCantidad = await mostrarDialogoEditarCantidad(
      context,
      titulo: 'Cantidad',
      valorActual: linea.cantidad,
      linea: linea,
    );
    if (nuevaCantidad == null) return;
    if (!context.mounted) return;
    context.read<VentaControlador>().editarCantidadExacta(index, nuevaCantidad);
  }

  Future<void> _editarGramos(
    BuildContext context,
    int index,
    LineaVentaPesable linea,
  ) async {
    final nuevosGramos = await mostrarDialogoEditarCantidad(
      context,
      titulo: 'Gramos',
      valorActual: linea.gramos,
      linea: linea,
    );
    if (nuevosGramos == null) return;
    if (!context.mounted) return;
    context.read<VentaControlador>().editarGramosExacto(index, nuevosGramos);
  }

  // El stock ya descontado por esta línea todavía no existe hasta cobrar:
  // esto es una previsualización con el stock actual del catálogo, no el
  // definitivo. Alcanza para la advertencia visual de Regla 8.
  bool _stockQuedaEnCeroONegativo(BuildContext context, LineaVenta linea) {
    final c = context.read<VentaControlador>();
    final producto = c.productoPorId(linea.productoId);
    // "Varios" no tiene stock en el sentido de Regla 8 (Regla 5: nunca lo
    // descuenta) — sin esto, cualquier línea de "Varios" se pintaba en rojo
    // como si tuviera un problema de stock que no existe.
    if (producto == null || producto.esVarios) return false;
    if (linea is LineaVentaPesable) {
      return (producto.stockGramos ?? 0) - linea.gramos <= 0;
    }
    final unidad = linea as LineaVentaPorUnidad;
    return producto.stock - unidad.cantidad <= 0;
  }
}

/// Una línea del carrito (`.cl` del mock): tarjeta blanca de radio 28 con el nombre y el precio unitario, el stepper en cápsula, el
/// subtotal y el tacho. La última agregada lleva un aro azul. Los pesables también tienen stepper (de a 50 g).
class _LineaCarrito extends StatelessWidget {
  const _LineaCarrito({
    required this.linea,
    required this.index,
    required this.esUltima,
    required this.stockNegativo,
    required this.descripcionCantidad,
    required this.alEditar,
  });

  final LineaVenta linea;
  final int index;
  final bool esUltima;
  final bool stockNegativo;
  final String descripcionCantidad;
  final VoidCallback alEditar;

  static const _pasoGramos = 50;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final c = context.read<VentaControlador>();
    final porUnidad = linea is LineaVentaPorUnidad;
    final unitario = switch (linea) {
      LineaVentaPorUnidad u => '${formatearARS(u.precioUnitarioCentavos)} c/u',
      LineaVentaPesable p => '${formatearARS(p.precioPorKiloCentavos)} el kilo',
    };
    return Pulso(
      valor: descripcionCantidad,
      escala: 1.015,
      alineacion: Alignment.centerLeft,
      child: AnimatedContainer(
        duration: Animaciones.media,
        curve: Animaciones.curva,
        padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
        decoration: BoxDecoration(
          color: colores.fondo,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: esUltima ? azulMarca : Colors.transparent, width: 2),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    linea.nombreProducto,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium?.copyWith(
                      fontSize: 17,
                      fontWeight: Pesos.intermedio,
                      height: 1.2,
                      color: stockNegativo ? colores.error : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(unitario, style: TextStyle(fontSize: 13, color: colores.textoTenue).tabular),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _EscalonCantidad(
              texto: descripcionCantidad.startsWith('x') ? descripcionCantidad.substring(1) : descripcionCantidad,
              onMenos: () => porUnidad
                  ? c.ajustarCantidad(index, -1)
                  : c.editarGramosExacto(index, (linea as LineaVentaPesable).gramos - _pasoGramos),
              onMas: () => porUnidad
                  ? c.ajustarCantidad(index, 1)
                  : c.editarGramosExacto(index, (linea as LineaVentaPesable).gramos + _pasoGramos),
              onDobleTap: alEditar,
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 96,
              child: Text(
                formatearARS(linea.subtotalCentavos),
                textAlign: TextAlign.right,
                style: textTheme.titleMedium?.copyWith(fontSize: 19, fontWeight: Pesos.medium).tabular,
              ),
            ),
            const SizedBox(width: 12),
            _IconoAccion(
              icono: IconosPlazoleta.deleteOutline,
              etiqueta: 'Quitar ${linea.nombreProducto}',
              onTap: () {
                c.eliminarLinea(index);
                // Un toque saca la línea sin confirmar, así que se puede deshacer desde el aviso de arriba (no tapa el cobro).
                mostrarAviso(
                  context,
                  'Quitaste ${linea.nombreProducto}',
                  textoAccion: 'Deshacer',
                  alAccionar: () => c.restaurarLinea(index, linea),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// El tacho (`.rm` del mock): círculo de 36 px, gris; al pasar el mouse se tiñe de rojo.
class _IconoAccion extends StatefulWidget {
  const _IconoAccion({required this.icono, required this.etiqueta, required this.onTap});

  final IconData icono;
  final String etiqueta;
  final VoidCallback onTap;

  @override
  State<_IconoAccion> createState() => _IconoAccionState();
}

class _IconoAccionState extends State<_IconoAccion> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return MouseRegion(
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: SuperficieTactil(
        etiqueta: widget.etiqueta,
        tamanoMinimo: 48,
        borderRadius: BorderRadius.circular(999),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Animaciones.corta,
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _encima ? Color.alphaBlend(colores.error.withValues(alpha: 0.14), colores.fondo) : Colors.transparent,
          ),
          child: IconoPlz(widget.icono, size: 19, color: _encima ? colores.error : colores.textoTenue),
        ),
      ),
    );
  }
}

/// Stepper de cantidad (`.stp` del mock): cápsula gris con "−", el número (doble clic para tipear el valor exacto) y "+".
class _EscalonCantidad extends StatelessWidget {
  const _EscalonCantidad({required this.texto, required this.onMenos, required this.onMas, required this.onDobleTap});

  final String texto;
  final VoidCallback onMenos;
  final VoidCallback onMas;
  final VoidCallback onDobleTap;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: colores.fondoBloque, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _celda(context, IconosPlazoleta.remove, 'Restar uno', onMenos),
          GestureDetector(
            onDoubleTap: onDobleTap,
            child: Container(
              constraints: const BoxConstraints(minWidth: 54),
              alignment: Alignment.center,
              child: Text(texto, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 16, fontWeight: Pesos.medium).tabular),
            ),
          ),
          _celda(context, IconosPlazoleta.add, 'Sumar uno', onMas),
        ],
      ),
    );
  }

  Widget _celda(BuildContext context, IconData icono, String etiqueta, VoidCallback onTap) {
    return SuperficieTactil(
      etiqueta: etiqueta,
      tamanoMinimo: 48,
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: SizedBox(width: 34, height: 34, child: IconoPlz(icono, size: 14, color: context.colores.textoPrimario)),
    );
  }
}

/// Carrito vacío (`.empty` del mock): el ícono de escanear dentro de un aro azul que late y el texto. Con una venta ya cobrada, en
/// cambio, el acuse "Venta #N cobrada" con el botón de imprimir.
class _EstadoVacio extends StatelessWidget {
  const _EstadoVacio({required this.ventaId, required this.totalCentavos, required this.onImprimir});

  final int? ventaId;
  final int? totalCentavos;
  final VoidCallback onImprimir;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colores = context.colores;
    if (ventaId == null || totalCentavos == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _AroPulsante(),
          const SizedBox(height: 14),
          Text(
            'Escaneá un código o buscá un producto\npara empezar la venta',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(fontSize: 19, color: colores.textoSecundario, height: 1.4),
          ),
        ],
      );
    }
    // Cada cobro entra con un tilde y un zoom leve: confirma que salió, sin frenar la venta siguiente (el campo ya tiene el foco y
    // se puede seguir escaneando mientras dura).
    final ganancia = context.acentosPlazoleta.ganancia;
    return Entrada(
      key: ValueKey('cobrada-$ventaId'),
      escala: 0.92,
      desplazamiento: 0,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(color: ganancia.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: IconoPlz(IconosPlazoleta.check, size: 15, color: ganancia),
          ),
          const SizedBox(width: Espaciado.sm),
          Flexible(
            child: Text(
              'Venta #$ventaId cobrada · ${formatearARS(totalCentavos!)}',
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium!.copyWith(color: colores.textoSecundario).tabular,
            ),
          ),
          const SizedBox(width: Espaciado.sm),
          Tooltip(
            message: 'Imprimir ticket',
            child: SuperficieTactil(
              borderRadius: BorderRadius.circular(999),
              onTap: onImprimir,
              child: Padding(
                padding: const EdgeInsets.all(Espaciado.xs),
                child: IconoPlz(IconosPlazoleta.printOutlined, size: 24, color: colores.textoSecundario),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// El aro azul que late alrededor del ícono de escanear (`.ringp` del mock), 1,8 s en bucle.
class _AroPulsante extends StatefulWidget {
  const _AroPulsante();

  @override
  State<_AroPulsante> createState() => _AroPulsanteState();
}

class _AroPulsanteState extends State<_AroPulsante> with SingleTickerProviderStateMixin {
  late final AnimationController _reloj = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  bool _arrancado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_arrancado) return;
    _arrancado = true;
    if (!MediaQuery.disableAnimationsOf(context)) _reloj.repeat();
  }

  @override
  void dispose() {
    _reloj.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return SizedBox(
      width: 96,
      height: 96,
      child: AnimatedBuilder(
        animation: _reloj,
        builder: (context, _) {
          final t = Curves.easeOut.transform(_reloj.value);
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 96 * (0.85 + 0.25 * t),
                height: 96 * (0.85 + 0.25 * t),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: azulMarca.withValues(alpha: 0.35 * (1 - t)), width: 3),
                ),
              ),
              IconoPlz(IconosPlazoleta.qrCode2Outlined, size: 44, color: colores.textoSecundario),
            ],
          );
        },
      ),
    );
  }
}

/// Pestañas de ventas abiertas (`.vtab` del mock): texto gris con el número de líneas; la elegida es una pastilla blanca con una
/// sombrita. "+ Nueva · Alt+N" abre una venta nueva sin perder la actual.
class _BarraVentasAbiertas extends StatelessWidget {
  const _BarraVentasAbiertas();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<VentaControlador>();
    final resumen = c.resumenPestanas;
    final puedeAbrirOtra = c.carrito.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < resumen.length; i++) ...[
                    _PildoraVenta(
                      titulo: 'Venta ${i + 1}',
                      lineas: resumen[i].lineas,
                      seleccionada: i == c.pestanaActiva,
                      puedeCerrar: resumen.length > 1,
                      onTap: () => c.cambiarAPestana(i),
                      onCerrar: () => cancelarVentaConDeshacer(context, c),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Tooltip(
            message: 'Nueva venta (Alt+N)',
            child: _BotonNuevaVenta(activo: puedeAbrirOtra, onTap: c.nuevaVenta),
          ),
        ],
      ),
    );
  }
}

class _PildoraVenta extends StatelessWidget {
  const _PildoraVenta({
    required this.titulo,
    required this.lineas,
    required this.seleccionada,
    required this.puedeCerrar,
    required this.onTap,
    required this.onCerrar,
  });

  final String titulo;
  final int lineas;
  final bool seleccionada;
  final bool puedeCerrar;
  final VoidCallback onTap;
  final VoidCallback onCerrar;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: AnimatedContainer(
        duration: Animaciones.corta,
        curve: Animaciones.curva,
        height: 42,
        decoration: BoxDecoration(
          color: seleccionada ? colores.fondo : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: seleccionada ? [BoxShadow(color: const Color(0xFF0D1017).withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 2))] : null,
        ),
        child: SuperficieTactil(
          etiqueta: titulo,
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.only(left: 18, right: puedeCerrar ? 6 : 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titulo,
                  style: TextStyle(fontSize: 15, fontWeight: Pesos.medium, color: seleccionada ? colores.textoPrimario : colores.textoSecundario),
                ),
                if (lineas > 0) ...[
                  const SizedBox(width: 8),
                  Text('$lineas', style: TextStyle(fontSize: 15, fontWeight: Pesos.intermedio, color: colores.textoSecundario)),
                ],
                if (puedeCerrar) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Cerrar $titulo',
                    child: Semantics(
                      button: true,
                      label: 'Cerrar $titulo',
                      excludeSemantics: true,
                      onTap: onCerrar,
                      child: InkResponse(
                        onTap: onCerrar,
                        radius: 18,
                        child: SizedBox(
                          width: 28,
                          height: 42,
                          child: IconoPlz(IconosPlazoleta.close, size: 12, color: colores.textoTenue),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BotonNuevaVenta extends StatelessWidget {
  const _BotonNuevaVenta({required this.activo, required this.onTap});

  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return SuperficieTactil(
      etiqueta: 'Nueva venta',
      borderRadius: BorderRadius.circular(999),
      onTap: activo ? onTap : null,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconoPlz(IconosPlazoleta.add, size: 16, color: activo ? colores.textoSecundario : colores.textoTenue),
            const SizedBox(width: 6),
            Text('Nueva', style: TextStyle(fontSize: 15, fontWeight: Pesos.medium, color: activo ? colores.textoSecundario : colores.textoTenue)),
            const SizedBox(width: 8),
            TeclaAtajo(texto: 'Alt+N', color: colores.textoSecundario),
          ],
        ),
      ),
    );
  }
}

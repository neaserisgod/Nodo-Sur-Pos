// Asistente (Ctrl+K) — rediseño v4 (El dueño, 2026-10-06: "buscador de acciones, sin pregunta libre a la IA").
// Una paleta que salta a donde se quiera sin recorrer menús: se escribe "pagar", "arqueo", "historial" o el nombre de un
// producto y Enter. No usa IA ni internet: filtra una lista fija de acciones y pantallas y busca productos en el catálogo.
//
// - Acciones: las mismas del menú "Caja ▾" (`LanzadorCaja`), según el estado de la caja, más "Pagar proveedor".
// - Ir a: las secciones visibles de la navbar y Configuración.
// - Productos: elegir uno lleva a Venta con el nombre ya escrito (igual que la lupa de las otras pantallas).
//
// Lo abre Ctrl+K desde cualquier pantalla y el botón "Asistente" de la navbar.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/busqueda_productos.dart';
import '../../data/database.dart';
import '../../data/repositorio_productos.dart' show sinServiciosNiInsumos;
import '../../domain/modulos.dart';
import '../../domain/normalizacion_texto.dart';
import '../../servicios/modulos_activos.dart';
import '../tema/iconos.dart';
import '../tema/movimiento.dart';
import '../tema/tokens.dart';
import 'acciones_caja.dart';
import 'navegacion_gestion.dart';

/// Una fila del asistente.
class ItemAsistente {
  const ItemAsistente({
    required this.grupo,
    required this.titulo,
    required this.icono,
    required this.alElegir,
    this.atajo,
    this.subtitulo,
    this.palabras = '',
  });

  final String grupo;
  final String titulo;
  final IconData icono;
  final VoidCallback alElegir;
  final String? atajo;
  final String? subtitulo;

  /// Palabras extra por las que se la puede encontrar ("plata", "turno", "contar"…).
  final String palabras;
}

/// Los ítems que coinciden con [texto] (sin importar mayúsculas ni acentos), en el orden dado. Sin texto, todos.
List<ItemAsistente> filtrarItemsAsistente(List<ItemAsistente> items, String texto) {
  final q = normalizarTexto(texto.trim());
  if (q.isEmpty) return items;
  final palabras = q.split(RegExp(r'\s+'));
  return [
    for (final i in items)
      if (palabras.every((p) => normalizarTexto('${i.titulo} ${i.palabras} ${i.grupo}').contains(p))) i,
  ];
}

/// Abre el asistente. [irA] navega a una sección por su clave; [alElegirProducto] recibe el nombre elegido (la pantalla
/// decide a dónde ir con él: siempre Venta). [alTerminarAccion] corre después de cualquier acción de caja (para que Venta
/// recargue su estado).
Future<void> abrirAsistente(
  BuildContext context, {
  required AppDatabase db,
  required SesionCaja? sesion,
  required Future<void> Function(String clave) irA,
  required ValueChanged<String> alElegirProducto,
  Future<void> Function()? alTerminarAccion,
}) async {
  final secciones = await itemsNavGestion(db);
  if (!context.mounted) return;
  final catalogo = await (db.select(db.productos)..where(sinServiciosNiInsumos)).get();
  if (!context.mounted) return;
  final lanzador = LanzadorCaja(db);
  final hayTurnos = moduloActivo(Modulo.turnos);
  final deOtroDia = sesion != null && sesionEsDeOtroDia(sesion);

  ItemAsistente accion(String titulo, IconData icono, Future<void> Function() hacer, {String? atajo, String palabras = ''}) =>
      ItemAsistente(
        grupo: 'Acciones',
        titulo: titulo,
        icono: icono,
        atajo: atajo,
        palabras: palabras,
        alElegir: () async {
          await hacer();
          if (alTerminarAccion != null) await alTerminarAccion();
        },
      );

  final items = <ItemAsistente>[
    if (sesion == null)
      accion('Abrir caja', IconosPlazoleta.paymentsOutlined, () => lanzador.abrir(context), palabras: 'apertura empezar turno')
    else if (deOtroDia)
      accion('Cerrar caja', IconosPlazoleta.lockOutline, () => lanzador.cerrar(context, sesion), palabras: 'cierre terminar dia ayer')
    else ...[
      accion('Pagar proveedor', IconosPlazoleta.localShippingOutlined, () => lanzador.pagarProveedor(context, sesion), atajo: 'Alt+P', palabras: 'deuda pago plata'),
      if (hayTurnos) accion('Hacer arqueo', IconosPlazoleta.history, () => lanzador.arqueo(context, sesion), palabras: 'contar caja efectivo'),
      if (hayTurnos) accion('Cambiar de turno', IconosPlazoleta.swapHoriz, () => lanzador.turno(context, sesion), palabras: 'empleado entra sale'),
      accion('Gasto rápido', IconosPlazoleta.addCircleOutline, () => lanzador.gasto(context, sesion), atajo: '-', palabras: 'sale plata flete bolsas'),
      accion('Ingreso rápido', IconosPlazoleta.addCircleOutline, () => lanzador.ingreso(context, sesion), atajo: 'Alt+I', palabras: 'entra plata cambio aporte'),
      accion('Cerrar caja', IconosPlazoleta.lockOutline, () => lanzador.cerrar(context, sesion), palabras: 'cierre terminar dia'),
    ],
    for (final s in secciones)
      ItemAsistente(
        grupo: 'Ir a',
        titulo: s.etiqueta,
        icono: IconosPlazoleta.chevronRight,
        alElegir: () => irA(s.clave),
      ),
  ];

  await showDialog<void>(
    context: context,
    barrierColor: const Color(0x99808080),
    builder: (_) => _DialogoAsistente(items: items, catalogo: catalogo, alElegirProducto: alElegirProducto),
  );
}

class _DialogoAsistente extends StatefulWidget {
  const _DialogoAsistente({required this.items, required this.catalogo, required this.alElegirProducto});

  final List<ItemAsistente> items;
  final List<Producto> catalogo;
  final ValueChanged<String> alElegirProducto;

  @override
  State<_DialogoAsistente> createState() => _DialogoAsistenteState();
}

class _DialogoAsistenteState extends State<_DialogoAsistente> {
  final _ctrl = TextEditingController();
  final _foco = FocusNode();
  int _indice = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    _foco.dispose();
    super.dispose();
  }

  /// Acciones y pantallas que coinciden, y después hasta cinco productos.
  List<ItemAsistente> get _visibles {
    final base = filtrarItemsAsistente(widget.items, _ctrl.text);
    final texto = _ctrl.text.trim();
    if (texto.isEmpty) return base.where((i) => i.grupo == 'Acciones').toList();
    final productos = buscarProductos(catalogo: widget.catalogo, textoBuscado: texto).take(5).map(
          (p) => ItemAsistente(
            grupo: 'Productos',
            titulo: p.nombre,
            icono: IconosPlazoleta.inventory2Outlined,
            subtitulo: 'Enter lo busca en Venta',
            alElegir: () => widget.alElegirProducto(p.nombre),
          ),
        );
    return [...base, ...productos];
  }

  void _elegir(ItemAsistente i) {
    // Se cierra primero y recién después corre: la acción abre su propio diálogo encima de la pantalla, no de esta paleta.
    Navigator.of(context).pop();
    i.alElegir();
  }

  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final n = _visibles.length;
    if (n == 0) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _indice = (_indice + 1) % n);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _indice = (_indice - 1 + n) % n);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final visibles = _visibles;
    final indice = visibles.isEmpty ? 0 : _indice.clamp(0, visibles.length - 1);
    String? grupoAnterior;
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(Espaciado.xl, 90, Espaciado.xl, Espaciado.xl),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Entrada(
        escala: 0.98,
        desplazamiento: -6,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colores.fondo,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 60, offset: const Offset(0, 20))],
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Padding(
                padding: const EdgeInsets.all(Espaciado.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Focus(
                      onKeyEvent: _tecla,
                      child: TextField(
                        key: const Key('asistente_campo'),
                        controller: _ctrl,
                        focusNode: _foco,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) => setState(() => _indice = 0),
                        onSubmitted: (_) {
                          if (visibles.isNotEmpty) _elegir(visibles[indice]);
                        },
                        style: textTheme.titleLarge,
                        decoration: InputDecoration(
                          hintText: 'Pagar proveedor, arqueo, un producto…',
                          prefixIcon: IconoPlz(IconosPlazoleta.search, size: 22, color: colores.textoSecundario),
                        ),
                      ),
                    ),
                    const SizedBox(height: Espaciado.sm),
                    if (visibles.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(Espaciado.lg),
                        child: Text('Sin coincidencias', style: textTheme.bodyMedium),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 460),
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (var i = 0; i < visibles.length; i++) ...[
                              if (visibles[i].grupo != grupoAnterior)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(Espaciado.md, Espaciado.md, Espaciado.md, Espaciado.xs),
                                  child: Text(
                                    (grupoAnterior = visibles[i].grupo).toUpperCase(),
                                    style: textTheme.labelSmall?.copyWith(color: colores.textoTenue, fontWeight: Pesos.fuerte, letterSpacing: 0.8),
                                  ),
                                ),
                              _FilaAsistente(item: visibles[i], marcada: i == indice, onTap: () => _elegir(visibles[i])),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilaAsistente extends StatelessWidget {
  const _FilaAsistente({required this.item, required this.marcada, required this.onTap});

  final ItemAsistente item;
  final bool marcada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: marcada ? colores.fondoBloque : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        key: Key('asistente_${item.grupo}_${item.titulo}'),
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Espaciado.md, vertical: Espaciado.md),
          child: Row(
            children: [
              IconoPlz(item.icono, size: 22, color: colores.textoSecundario),
              const SizedBox(width: Espaciado.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.titulo, style: textTheme.titleMedium),
                    if (item.subtitulo != null) Text(item.subtitulo!, style: textTheme.bodySmall),
                  ],
                ),
              ),
              if (item.atajo != null)
                Text(item.atajo!, style: textTheme.bodySmall?.copyWith(color: colores.textoTenue, fontWeight: Pesos.fuerte)),
            ],
          ),
        ),
      ),
    );
  }
}

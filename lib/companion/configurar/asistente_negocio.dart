// "Configurá tu negocio": lo que ve el dueño de un negocio nuevo después de entrar, para dejar el celular listo para
// vender. Tres pasos (El dueño, 2026-10-03): nombre y rubro, un primer producto escaneado que sirve de práctica de
// cómo se carga cualquier producto, y los atajos a horsepos.com/negocio para Mercado Pago y el equipo. Cada paso se
// puede dejar para después: lo que falte queda como recordatorio en Inicio.
//
// Solo la vista y el orden de los pasos. Guardar (nombre del comercio, plantilla del rubro, el producto) lo hace quien
// la abre, por los callbacks.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/dinero.dart';
import '../../domain/plantillas_rubro.dart';
import '../../ui/tema/tokens.dart';
import '../bienvenida/aparecer.dart';
import '../bienvenida/marca_nodo_sur.dart';
import '../tema/tema_companion.dart';

enum PasoNegocio { negocio, producto, cobros }

/// El producto que se cargó en la práctica.
class ProductoDePrueba {
  const ProductoDePrueba({required this.codigo, required this.nombre, required this.precioCentavos, required this.categoria, required this.stock});
  final String codigo;
  final String nombre;
  final int precioCentavos;
  final String? categoria;
  final int stock;
}

class AsistenteNegocio extends StatefulWidget {
  const AsistenteNegocio({
    super.key,
    required this.alGuardarNegocio,
    required this.alEscanear,
    required this.alGuardarProducto,
    required this.alAbrirWeb,
    required this.alTerminar,
    this.alCompletarPaso,
    this.pasoInicial = PasoNegocio.negocio,
    this.nombreInicial = '',
    this.rubroInicial,
    this.categoriasExistentes = const [],
  });

  /// Cada paso hecho (no salteado con "Después"), en el momento: si la app se cierra a mitad del asistente, lo
  /// hecho no vuelve a quedar pendiente.
  final void Function(PasoNegocio paso)? alCompletarPaso;

  /// Las categorías que ya tiene la base, para el primer producto cuando se llega sin elegir rubro en esta pasada
  /// (por ejemplo, retomando desde Inicio).
  final List<String> categoriasExistentes;

  /// Guarda el nombre del comercio y aplica la plantilla del rubro.
  final Future<void> Function(String nombre, PlantillaRubro rubro) alGuardarNegocio;

  /// Abre la cámara sobre [context]; devuelve el código leído o null si se canceló.
  final Future<String?> Function(BuildContext context) alEscanear;

  final Future<void> Function(ProductoDePrueba producto) alGuardarProducto;

  /// Abre horsepos.com/negocio en el navegador (Mercado Pago o el equipo).
  final void Function(String seccion) alAbrirWeb;

  /// Fin del asistente, con los pasos que quedaron sin hacer.
  final void Function(BuildContext context, Set<PasoNegocio> pendientes) alTerminar;

  final PasoNegocio pasoInicial;
  final String nombreInicial;
  final PlantillaRubro? rubroInicial;

  @override
  State<AsistenteNegocio> createState() => _AsistenteNegocioState();
}

class _AsistenteNegocioState extends State<AsistenteNegocio> {
  late PasoNegocio _paso = widget.pasoInicial;
  final _pendientes = <PasoNegocio>{};
  bool _adelante = true;

  late final _nombreCtrl = TextEditingController(text: widget.nombreInicial);
  late PlantillaRubro? _rubro = widget.rubroInicial;
  bool _guardando = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    super.dispose();
  }

  void _seguir({required bool hecho}) {
    if (!hecho) _pendientes.add(_paso);
    if (hecho) {
      _pendientes.remove(_paso);
      widget.alCompletarPaso?.call(_paso);
    }
    final i = _paso.index;
    if (i == PasoNegocio.values.length - 1) {
      widget.alTerminar(context, _pendientes);
      return;
    }
    setState(() {
      _adelante = true;
      _paso = PasoNegocio.values[i + 1];
    });
  }

  Future<void> _guardarNegocio() async {
    setState(() => _guardando = true);
    await widget.alGuardarNegocio(_nombreCtrl.text.trim(), _rubro!);
    if (!mounted) return;
    setState(() => _guardando = false);
    _seguir(hecho: true);
  }

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Espaciado.xl, Espaciado.md, Espaciado.sm, 0),
              child: Row(
                children: [
                  Text('Paso ${_paso.index + 1} de ${PasoNegocio.values.length}', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(width: Espaciado.md),
                  Expanded(child: _Progreso(paso: _paso.index, total: PasoNegocio.values.length)),
                  TextButton(
                    key: const Key('asistente-despues'),
                    onPressed: _guardando ? null : () => _seguir(hecho: false),
                    style: TextButton.styleFrom(foregroundColor: colores.textoSecundario),
                    child: const Text('Después'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 450),
                switchInCurve: const Cubic(0.05, 0.7, 0.1, 1),
                switchOutCurve: const Cubic(0.3, 0, 0.8, 0.15),
                // Eje compartido de Material: lo nuevo entra desde la derecha y lo anterior se va hacia la izquierda.
                transitionBuilder: (hijo, animacion) {
                  final entrando = hijo.key == ValueKey(_paso);
                  final desde = (entrando ? 40.0 : -40.0) * (_adelante ? 1 : -1);
                  return FadeTransition(
                    opacity: animacion,
                    child: AnimatedBuilder(
                      animation: animacion,
                      child: hijo,
                      builder: (context, h) => Transform.translate(offset: Offset(desde * (1 - animacion.value), 0), child: h),
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey(_paso),
                  child: switch (_paso) {
                    PasoNegocio.negocio => _PasoNegocio(
                        nombreCtrl: _nombreCtrl,
                        rubro: _rubro,
                        guardando: _guardando,
                        alElegirRubro: (r) => setState(() => _rubro = r),
                        alCambiarNombre: () => setState(() {}),
                        alSeguir: _guardarNegocio,
                      ),
                    PasoNegocio.producto => _PasoProducto(
                        categorias: _rubro != null ? [for (final c in _rubro!.categorias) c.nombre] : widget.categoriasExistentes,
                        alEscanear: widget.alEscanear,
                        alGuardar: widget.alGuardarProducto,
                        alSeguir: () => _seguir(hecho: true),
                      ),
                    PasoNegocio.cobros => _PasoCobros(alAbrirWeb: widget.alAbrirWeb, alTerminar: () => _seguir(hecho: true)),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Progreso extends StatelessWidget {
  const _Progreso({required this.paso, required this.total});
  final int paso;
  final int total;

  @override
  Widget build(BuildContext context) {
    final tinta = context.colores.textoPrimario;
    return Row(
      children: [
        for (var i = 0; i < total; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: i <= paso ? 1 : 0),
                  duration: const Duration(milliseconds: 500),
                  curve: const Cubic(0.2, 0, 0, 1),
                  builder: (context, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 4,
                    color: tinta,
                    backgroundColor: tinta.withValues(alpha: 0.12),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Estructura común de cada paso: título grande, bajada, contenido que scrollea y el botón principal abajo.
class _Marco extends StatelessWidget {
  const _Marco({required this.titulo, required this.bajada, required this.contenido, required this.boton});
  final String titulo;
  final String bajada;
  final List<Widget> contenido;
  final Widget boton;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Espaciado.xl, Espaciado.xl, Espaciado.xl, Espaciado.xl),
            children: [
              Aparecer(orden: 0, child: Text(titulo, style: textTheme.headlineLarge)),
              const SizedBox(height: Espaciado.sm),
              Aparecer(orden: 1, child: Text(bajada, style: textTheme.bodyLarge?.copyWith(color: context.colores.textoSecundario))),
              const SizedBox(height: Espaciado.xl),
              for (var i = 0; i < contenido.length; i++) Aparecer(orden: 2 + i, child: contenido[i]),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Espaciado.xl, 0, Espaciado.xl, Espaciado.xl),
          child: SizedBox(height: alturaControlCompanion, child: boton),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Paso 1 · Nombre y rubro

class _PasoNegocio extends StatelessWidget {
  const _PasoNegocio({
    required this.nombreCtrl,
    required this.rubro,
    required this.guardando,
    required this.alElegirRubro,
    required this.alCambiarNombre,
    required this.alSeguir,
  });

  final TextEditingController nombreCtrl;
  final PlantillaRubro? rubro;
  final bool guardando;
  final ValueChanged<PlantillaRubro> alElegirRubro;
  final VoidCallback alCambiarNombre;
  final VoidCallback alSeguir;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colores = context.colores;
    final listo = nombreCtrl.text.trim().isNotEmpty && rubro != null;
    return _Marco(
      titulo: 'Contanos de tu negocio',
      bajada: 'Con esto armamos la app a tu medida. Todo se puede cambiar después.',
      contenido: [
        Text('Nombre del comercio', style: textTheme.titleMedium),
        const SizedBox(height: Espaciado.sm),
        TextField(
          key: const Key('asistente-nombre'),
          controller: nombreCtrl,
          onChanged: (_) => alCambiarNombre(),
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Ej.: Almacén Don Pepe'),
        ),
        Padding(
          padding: const EdgeInsets.only(top: Espaciado.xs, left: Espaciado.xs),
          child: Text('Sale en los tickets y arriba de la app.', style: textTheme.bodySmall),
        ),
        const SizedBox(height: Espaciado.xl),
        Text('¿Qué rubro es?', style: textTheme.titleMedium),
        const SizedBox(height: Espaciado.md),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: Espaciado.md,
          crossAxisSpacing: Espaciado.md,
          childAspectRatio: 1.12,
          children: [
            for (final r in PlantillaRubro.todas)
              _TarjetaRubro(rubro: r, elegido: rubro == r, onTap: () => alElegirRubro(r)),
          ],
        ),
        const SizedBox(height: Espaciado.lg),
        AnimatedSize(
          duration: const Duration(milliseconds: 350),
          curve: const Cubic(0.2, 0, 0, 1),
          alignment: Alignment.topCenter,
          child: rubro == null
              ? const SizedBox(width: double.infinity)
              : Container(
                  key: ValueKey(rubro!.clave),
                  width: double.infinity,
                  padding: const EdgeInsets.all(Espaciado.lg),
                  decoration: BoxDecoration(color: colores.fondoBloque, borderRadius: BorderRadius.circular(radioSuperficieCompanion)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rubro!.categorias.isEmpty ? 'Arrancás sin categorías: las armás vos.' : 'Te dejamos estas categorías para empezar:',
                        style: textTheme.bodySmall,
                      ),
                      if (rubro!.categorias.isNotEmpty) ...[
                        const SizedBox(height: Espaciado.md),
                        Wrap(
                          spacing: Espaciado.sm,
                          runSpacing: Espaciado.sm,
                          children: [
                            for (var i = 0; i < rubro!.categorias.length; i++)
                              _Escalonado(
                                key: ValueKey('${rubro!.clave}-$i'),
                                retraso: i * 40,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(color: colores.fondo, borderRadius: BorderRadius.circular(999)),
                                  child: Text(rubro!.categorias[i].nombre, style: textTheme.labelMedium?.copyWith(color: colores.textoPrimario)),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
      boton: FilledButton(
        key: const Key('asistente-seguir'),
        onPressed: listo && !guardando ? alSeguir : null,
        child: guardando
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
            : const Text('Siguiente'),
      ),
    );
  }
}

class _TarjetaRubro extends StatelessWidget {
  const _TarjetaRubro({required this.rubro, required this.elegido, required this.onTap});
  final PlantillaRubro rubro;
  final bool elegido;
  final VoidCallback onTap;

  static const _iconos = {'kiosco': Icons.storefront_outlined, 'almacen': Icons.shopping_basket_outlined, 'fiambreria': Icons.restaurant_outlined, 'otro': Icons.tune_rounded};

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: colores.fondoBloque,
      borderRadius: BorderRadius.circular(radioSuperficieCompanion),
      child: InkWell(
        key: Key('rubro-${rubro.clave}'),
        borderRadius: BorderRadius.circular(radioSuperficieCompanion),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(Espaciado.md + 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radioSuperficieCompanion),
            border: Border.all(color: elegido ? colores.textoPrimario : Colors.transparent, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: elegido ? colores.textoPrimario : colores.fondo, shape: BoxShape.circle),
                    child: Icon(_iconos[rubro.clave], size: 20, color: elegido ? colores.fondo : colores.textoPrimario),
                  ),
                  const Spacer(),
                  AnimatedOpacity(
                    opacity: elegido ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.check_circle_rounded, size: 22, color: colores.textoPrimario),
                  ),
                ],
              ),
              const Spacer(),
              Text(rubro.nombre, style: textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(rubro.descripcion, maxLines: 2, overflow: TextOverflow.ellipsis, style: textTheme.labelSmall?.copyWith(height: 1.3)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aparece con un pequeño retraso (los chips de categorías, uno tras otro).
class _Escalonado extends StatefulWidget {
  const _Escalonado({super.key, required this.retraso, required this.child});
  final int retraso;
  final Widget child;
  @override
  State<_Escalonado> createState() => _EscalonadoState();
}

class _EscalonadoState extends State<_Escalonado> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.retraso + 350));
  late final _k = CurvedAnimation(parent: _c, curve: Interval(widget.retraso / (widget.retraso + 350), 1, curve: const Cubic(0.05, 0.7, 0.1, 1)));
  bool _ya = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ya) return;
    _ya = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _k, child: ScaleTransition(scale: Tween(begin: 0.8, end: 1.0).animate(_k), child: widget.child));
}

// ---------------------------------------------------------------------------------------------------------------------
// Paso 2 · El primer producto, como práctica

enum _EtapaProducto { invitar, completar, listo }

class _PasoProducto extends StatefulWidget {
  const _PasoProducto({required this.categorias, required this.alEscanear, required this.alGuardar, required this.alSeguir});
  final List<String> categorias;
  final Future<String?> Function(BuildContext context) alEscanear;
  final Future<void> Function(ProductoDePrueba producto) alGuardar;
  final VoidCallback alSeguir;

  @override
  State<_PasoProducto> createState() => _PasoProductoState();
}

class _PasoProductoState extends State<_PasoProducto> {
  var _etapa = _EtapaProducto.invitar;
  String? _codigo;
  final _nombre = TextEditingController();
  final _precio = TextEditingController();
  String? _categoria;
  int _stock = 1;
  bool _trabajando = false;
  ProductoDePrueba? _producto;

  @override
  void dispose() {
    _nombre.dispose();
    _precio.dispose();
    super.dispose();
  }

  int get _precioCentavos => (int.tryParse(_precio.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0) * 100;

  Future<void> _escanear() async {
    setState(() => _trabajando = true);
    final codigo = await widget.alEscanear(context);
    if (!mounted) return;
    setState(() {
      _trabajando = false;
      if (codigo != null) {
        _codigo = codigo;
        _etapa = _EtapaProducto.completar;
      }
    });
  }

  Future<void> _guardar() async {
    setState(() => _trabajando = true);
    final p = ProductoDePrueba(codigo: _codigo!, nombre: _nombre.text.trim(), precioCentavos: _precioCentavos, categoria: _categoria, stock: _stock);
    await widget.alGuardar(p);
    if (!mounted) return;
    setState(() {
      _trabajando = false;
      _producto = p;
      _etapa = _EtapaProducto.listo;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: const Cubic(0.05, 0.7, 0.1, 1),
      child: KeyedSubtree(
        key: ValueKey(_etapa),
        child: switch (_etapa) {
          _EtapaProducto.invitar => _invitar(context),
          _EtapaProducto.completar => _completar(context),
          _EtapaProducto.listo => _listo(context),
        },
      ),
    );
  }

  Widget _invitar(BuildContext context) => _Marco(
        titulo: 'Cargá tu primer producto',
        bajada: 'Agarrá algo que tengas a mano y escaneá su código. Así se carga cualquier producto.',
        contenido: [
          const _VisorAnimado(),
          const SizedBox(height: Espaciado.xl),
          const _PasoGuia(numero: 1, texto: 'Escaneás el código de barras.'),
          const _PasoGuia(numero: 2, texto: 'Le ponés nombre y precio.'),
          const _PasoGuia(numero: 3, texto: 'Desde ahí ya lo podés vender.'),
        ],
        boton: FilledButton.icon(
          key: const Key('asistente-escanear'),
          onPressed: _trabajando ? null : _escanear,
          icon: _trabajando
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
              : const Icon(Icons.qr_code_scanner_rounded),
          label: Text(_trabajando ? 'Buscando el código…' : 'Escanear'),
        ),
      );

  Widget _completar(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final listo = _nombre.text.trim().isNotEmpty && _precioCentavos > 0;
    return _Marco(
      titulo: 'Es nuevo: completalo',
      bajada: 'Con nombre y precio alcanza. El resto lo podés sumar cuando quieras.',
      contenido: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg, vertical: Espaciado.md),
          decoration: BoxDecoration(color: colores.fondoBloque, borderRadius: BorderRadius.circular(999)),
          child: Row(
            children: [
              const Icon(Icons.qr_code_2_rounded, size: 20),
              const SizedBox(width: Espaciado.sm),
              Text(_codigo!, style: textTheme.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              const Spacer(),
              Text('Código leído', style: textTheme.labelMedium),
            ],
          ),
        ),
        const SizedBox(height: Espaciado.lg),
        Text('Nombre', style: textTheme.titleSmall),
        const SizedBox(height: Espaciado.sm),
        TextField(
          key: const Key('producto-nombre'),
          controller: _nombre,
          onChanged: (_) => setState(() {}),
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Ej.: Yerba 1 kg'),
        ),
        const SizedBox(height: Espaciado.lg),
        Text('Precio de venta', style: textTheme.titleSmall),
        const SizedBox(height: Espaciado.sm),
        TextField(
          key: const Key('producto-precio'),
          controller: _precio,
          onChanged: (_) => setState(() {}),
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '0', prefixText: r'$ '),
        ),
        const SizedBox(height: Espaciado.lg),
        if (widget.categorias.isNotEmpty) ...[
          Text('Categoría', style: textTheme.titleSmall),
          const SizedBox(height: Espaciado.sm),
          Wrap(
            spacing: Espaciado.sm,
            runSpacing: Espaciado.sm,
            children: [
              for (final c in widget.categorias)
                ChoiceChip(
                  label: Text(c),
                  showCheckmark: false,
                  selectedColor: colores.textoPrimario,
                  backgroundColor: colores.fondoBloque,
                  side: BorderSide.none,
                  labelStyle: TextStyle(color: _categoria == c ? colores.fondo : colores.textoPrimario, fontWeight: FontWeight.w500),
                  selected: _categoria == c,
                  onSelected: (s) => setState(() => _categoria = s ? c : null),
                ),
            ],
          ),
          const SizedBox(height: Espaciado.lg),
        ],
        Row(
          children: [
            Expanded(child: Text('¿Cuántos tenés?', style: textTheme.titleSmall)),
            IconButton.filled(onPressed: _stock > 0 ? () => setState(() => _stock--) : null, style: IconButton.styleFrom(backgroundColor: colores.fondoBloque, foregroundColor: colores.textoPrimario), icon: const Icon(Icons.remove_rounded)),
            SizedBox(width: 44, child: Text('$_stock', textAlign: TextAlign.center, style: textTheme.titleLarge)),
            IconButton.filled(onPressed: () => setState(() => _stock++), style: IconButton.styleFrom(backgroundColor: colores.fondoBloque, foregroundColor: colores.textoPrimario), icon: const Icon(Icons.add_rounded)),
          ],
        ),
      ],
      boton: FilledButton(
        key: const Key('producto-guardar'),
        onPressed: listo && !_trabajando ? _guardar : null,
        child: _trabajando ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)) : const Text('Guardar producto'),
      ),
    );
  }

  Widget _listo(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final p = _producto!;
    return _Marco(
      titulo: '¡Ya lo podés vender!',
      bajada: 'Quedó cargado. Así de rápido se suma cualquier producto.',
      contenido: [
        Container(
          padding: const EdgeInsets.all(Espaciado.lg),
          decoration: BoxDecoration(color: colores.fondoBloque, borderRadius: BorderRadius.circular(radioSuperficieCompanion)),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(color: Color(0xFFE6F4EA), shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: Color(0xFF1E8E3E)),
              ),
              const SizedBox(width: Espaciado.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.nombre, style: textTheme.titleMedium),
                    Text([if (p.categoria != null) p.categoria!, 'Stock ${p.stock}'].join(' · '), style: textTheme.bodySmall),
                  ],
                ),
              ),
              Text(formatearARS(p.precioCentavos), style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        const SizedBox(height: Espaciado.lg),
        const _Consejo(
          icono: Icons.point_of_sale_rounded,
          texto: 'Cuando vendas, escanealo desde Vender y se suma solo al carrito.',
        ),
        const _Consejo(
          icono: Icons.qr_code_scanner_rounded,
          texto: 'El botón de escanear del medio carga productos nuevos o edita los que ya tenés.',
        ),
      ],
      boton: FilledButton(key: const Key('asistente-seguir'), onPressed: widget.alSeguir, child: const Text('Siguiente')),
    );
  }
}

class _PasoGuia extends StatelessWidget {
  const _PasoGuia({required this.numero, required this.texto});
  final int numero;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Padding(
      padding: const EdgeInsets.only(bottom: Espaciado.md),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: colores.textoPrimario, shape: BoxShape.circle),
            child: Center(child: Text('$numero', style: TextStyle(fontFamily: familiaTipografica, color: colores.fondo, fontWeight: FontWeight.w700))),
          ),
          const SizedBox(width: Espaciado.md),
          Expanded(child: Text(texto, style: Theme.of(context).textTheme.bodyLarge)),
        ],
      ),
    );
  }
}

class _Consejo extends StatelessWidget {
  const _Consejo({required this.icono, required this.texto});
  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Espaciado.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, size: 22, color: context.colores.textoSecundario),
            const SizedBox(width: Espaciado.md),
            Expanded(child: Text(texto, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.colores.textoSecundario))),
          ],
        ),
      );
}

/// El visor del escáner de la bienvenida, en loop: esquinas, un código de barras y la línea verde que lo recorre.
class _VisorAnimado extends StatefulWidget {
  const _VisorAnimado();
  @override
  State<_VisorAnimado> createState() => _VisorAnimadoState();
}

class _VisorAnimadoState extends State<_VisorAnimado> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!MediaQuery.disableAnimationsOf(context) && !_c.isAnimating) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        height: 200,
        decoration: BoxDecoration(color: const Color(0xFF121317), borderRadius: BorderRadius.circular(radioSuperficieCompanion + 4)),
        child: AnimatedBuilder(animation: _c, builder: (context, _) => CustomPaint(painter: _PintorVisor(_c.value))),
      );
}

class _PintorVisor extends CustomPainter {
  _PintorVisor(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = Rect.fromCenter(center: c, width: 150, height: 130);
    final esquina = Paint()
      ..color = Colors.white
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const l = 26.0;
    for (final (o, dx, dy) in [(r.topLeft, 1.0, 1.0), (r.topRight, -1.0, 1.0), (r.bottomLeft, 1.0, -1.0), (r.bottomRight, -1.0, -1.0)]) {
      canvas.drawPath(Path()..moveTo(o.dx, o.dy + dy * l)..lineTo(o.dx, o.dy)..lineTo(o.dx + dx * l, o.dy), esquina);
    }
    const anchos = [3, 1, 2, 1, 3, 2, 1, 1, 3, 1, 2, 2, 1, 3, 1, 1, 2, 3, 1, 2];
    final total = anchos.fold<int>(0, (a, b) => a + b) + anchos.length;
    final u = 104 / total;
    var x = c.dx - 52;
    final barra = Paint()..color = Colors.white.withValues(alpha: 0.9);
    for (final a in anchos) {
      canvas.drawRect(Rect.fromLTWH(x, c.dy - 34, a * u, 68), barra);
      x += (a + 1) * u;
    }
    final y = c.dy - 52 + 104 * (0.5 - 0.5 * math.cos(t * 2 * math.pi));
    canvas.drawLine(
      Offset(c.dx - 64, y),
      Offset(c.dx + 64, y),
      Paint()
        ..color = verdeMarca.withValues(alpha: 0.5)
        ..strokeWidth = 10
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawLine(Offset(c.dx - 64, y), Offset(c.dx + 64, y), Paint()
      ..color = verdeMarca
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_PintorVisor viejo) => viejo.t != t;
}

// ---------------------------------------------------------------------------------------------------------------------
// Paso 3 · Mercado Pago y el equipo (se hacen en horsepos.com/negocio)

class _PasoCobros extends StatelessWidget {
  const _PasoCobros({required this.alAbrirWeb, required this.alTerminar});
  final void Function(String seccion) alAbrirWeb;
  final VoidCallback alTerminar;

  @override
  Widget build(BuildContext context) => _Marco(
        titulo: 'Cobros y equipo',
        bajada: 'Las dos cosas se hacen en horsepos.com con tu cuenta. Se abre el navegador y volvés a la app.',
        contenido: [
          _TarjetaWeb(
            clave: 'mercado-pago',
            color: const Color(0xFF3B6CFF),
            icono: Icons.qr_code_rounded,
            titulo: 'Conectá Mercado Pago',
            detalle: 'Cobrá con QR y débito en tu terminal Point. Lo cobrado entra en la caja como Mercado Pago.',
            boton: 'Conectar',
            onTap: () => alAbrirWeb('mercado-pago'),
          ),
          const SizedBox(height: Espaciado.md),
          _TarjetaWeb(
            clave: 'equipo',
            color: const Color(0xFF8A5CF6),
            icono: Icons.group_add_outlined,
            titulo: 'Sumá a tu equipo',
            detalle: 'Invitá a tus empleados por mail. Cada uno entra con su cuenta y lo que hace queda a su nombre.',
            boton: 'Invitar',
            onTap: () => alAbrirWeb('equipo'),
          ),
        ],
        boton: FilledButton(key: const Key('asistente-terminar'), onPressed: alTerminar, child: const Text('Terminar')),
      );
}

class _TarjetaWeb extends StatelessWidget {
  const _TarjetaWeb({
    required this.clave,
    required this.color,
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.boton,
    required this.onTap,
  });
  final String clave;
  final Color color;
  final IconData icono;
  final String titulo;
  final String detalle;
  final String boton;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Espaciado.lg),
      decoration: BoxDecoration(color: colores.fondoBloque, borderRadius: BorderRadius.circular(radioSuperficieCompanion)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: Icon(icono, color: color, size: 22),
              ),
              const SizedBox(width: Espaciado.md),
              Expanded(child: Text(titulo, style: textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: Espaciado.md),
          Text(detalle, style: textTheme.bodySmall),
          const SizedBox(height: Espaciado.md),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: Key('web-$clave'),
              onPressed: onTap,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(boton),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Recordatorio en Inicio

/// La tarjeta de Inicio mientras falte algún paso: qué falta y "Seguir", que vuelve al asistente en el primero pendiente.
class TarjetaConfiguracionPendiente extends StatelessWidget {
  const TarjetaConfiguracionPendiente({super.key, required this.pendientes, required this.alSeguir});
  final Set<PasoNegocio> pendientes;
  final VoidCallback alSeguir;

  static const _nombres = {
    PasoNegocio.negocio: 'Nombre y rubro',
    PasoNegocio.producto: 'Tu primer producto',
    PasoNegocio.cobros: 'Mercado Pago y equipo',
  };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hechos = PasoNegocio.values.length - pendientes.length;
    return Container(
      padding: const EdgeInsets.all(Espaciado.xl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radioSuperficieCompanion + 4),
        gradient: const LinearGradient(colors: [Color(0xFF0A0B10), Color(0xFF1B1F3A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const MarcaNodoSur(tamanio: 28),
              const SizedBox(width: Espaciado.sm),
              Text('$hechos de ${PasoNegocio.values.length} listos', style: textTheme.labelMedium?.copyWith(color: Colors.white70)),
            ],
          ),
          const SizedBox(height: Espaciado.md),
          Text(
            pendientes.length == 1 ? 'Te falta un paso' : 'Te faltan ${pendientes.length} pasos',
            style: textTheme.headlineMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: Espaciado.xs),
          Text(
            [for (final p in PasoNegocio.values) if (pendientes.contains(p)) _nombres[p]!].join(' · '),
            style: textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: Espaciado.lg),
          FilledButton(
            key: const Key('pendiente-seguir'),
            onPressed: alSeguir,
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF121317)),
            child: const Text('Seguir configurando'),
          ),
        ],
      ),
    );
  }
}

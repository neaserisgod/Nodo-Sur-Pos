// "Configurá tu negocio": lo que ve el dueño de un negocio nuevo después de entrar, para dejar el celular listo para
// vender. Tres pasos (El dueño, 2026-10-03): nombre y rubro, un primer producto escaneado que sirve de práctica de
// cómo se carga cualquier producto, y los atajos a horsepos.com/negocio para Mercado Pago y el equipo. Un negocio de
// servicios suma un cuarto, el horario de atención (El dueño, 2026-10-14: sin él, el bot ofrecía turnos en el horario de
// fábrica). Nodo Gastro suma, antes de los cobros, lo que la hace distinta: el bot de WhatsApp y cómo entrega y cobra los
// pedidos (El dueño, 2026-10-18: "el onboarding debe mostrar una breve configuración de las features destacadas como el bot").
// Cada paso se puede dejar para después: lo que falte queda como recordatorio en Inicio (en la Agenda, o en Pedidos).
//
// Solo la vista y el orden de los pasos. Guardar (nombre del comercio, plantilla del rubro, el producto) lo hace quien
// la abre, por los callbacks.


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/dinero.dart' show parsearARS;
import '../../domain/forma_de_trabajo.dart';
import '../../domain/pedido_gastronomico.dart';
import '../../domain/plantillas_rubro.dart';
import '../../domain/turnos.dart';
import '../../edicion.dart';
import '../../servicios/modulos_activos.dart' show modulosActuales;
import '../kit/kit_ns.dart';
import '../mensaje_error.dart';

enum PasoNegocio { negocio, producto, horario, pedidos, cobros }

/// Los pasos de esa forma de trabajar, en orden: el horario de atención es de un negocio de servicios (lo usan la Agenda y el
/// bot) y de un local gastronómico (el bot dice si está abierto y no toma pedidos fuera de hora).
/// Los pedidos y el bot, solo en un local gastronómico.
List<PasoNegocio> pasosDeLaForma(FormaDeTrabajo forma) => [
      for (final p in PasoNegocio.values)
        if ((p != PasoNegocio.horario || forma != FormaDeTrabajo.productos) && (p != PasoNegocio.pedidos || forma == FormaDeTrabajo.gastronomia)) p,
    ];

/// Los pasos del negocio de este equipo.
List<PasoNegocio> pasosDelNegocio() => pasosDeLaForma(modulosActuales.value.forma);

/// El producto que se cargó en la práctica.
class ProductoDePrueba {
  const ProductoDePrueba({required this.codigo, required this.nombre, required this.precioCentavos, required this.categoria, required this.stock});
  final String codigo;
  final String nombre;
  final int precioCentavos;
  final String? categoria;
  final int stock;
}

/// El primer servicio, en un negocio de servicios (en vez del producto con código de barras).
class ServicioDePrueba {
  const ServicioDePrueba({required this.nombre, required this.duracionMinutos, required this.precioCentavos, required this.categoria});
  final String nombre;
  final int duracionMinutos;
  final int precioCentavos;
  final String? categoria;
}

class AsistenteNegocio extends StatefulWidget {
  const AsistenteNegocio({
    super.key,
    required this.alGuardarNegocio,
    required this.alEscanear,
    required this.alGuardarProducto,
    this.alGuardarServicio,
    this.alGuardarHorario,
    this.pedidosIniciales = const ConfigPedidos(),
    this.alGuardarPedidos,
    this.tieneBot,
    this.alAbrirBot,
    this.horarioInicial = HorarioAtencion.porDefecto,
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

  /// El primer servicio, si el rubro es de servicios. Sin esto, ese paso no guarda nada (solo se ve).
  final Future<void> Function(ServicioDePrueba servicio)? alGuardarServicio;

  /// El horario de atención (negocios de servicios). Sin esto, ese paso no guarda nada (solo se ve).
  final Future<void> Function(HorarioAtencion horario)? alGuardarHorario;

  /// Cómo trabaja hoy los pedidos (local gastronómico), para arrancar ese paso.
  final ConfigPedidos pedidosIniciales;

  /// Guarda las entregas, el cobro y si lo de WhatsApp entra solo. Sin esto, ese paso no guarda nada (solo se ve).
  final Future<void> Function(ConfigPedidos config)? alGuardarPedidos;

  /// Si el plan del negocio trae el bot de WhatsApp. Null (o sin esto): no se sabe, se ofrece verlo en la web.
  final Future<bool?> Function()? tieneBot;

  /// Abre la pantalla del bot (encenderlo y vincular el WhatsApp del local). Al volver, el asistente sigue donde estaba.
  final Future<void> Function(BuildContext context)? alAbrirBot;

  /// Lo que ya está guardado, para arrancar el paso del horario.
  final HorarioAtencion horarioInicial;

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
  // Nodo Gastro no elige rubro: es uno solo para toda la gastronomía.
  late PlantillaRubro? _rubro = widget.rubroInicial ?? PlantillaRubro.desdeClave(rubroDeEdicion ?? '');
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
    // El siguiente de los pasos de esta forma de trabajar (el rubro elegido puede sumar o sacar el del horario).
    final siguiente = _pasos.where((p) => p.index > _paso.index).firstOrNull;
    if (siguiente == null) {
      widget.alTerminar(context, _pendientes);
      return;
    }
    setState(() {
      _adelante = true;
      _paso = siguiente;
    });
  }

  List<PasoNegocio> get _pasos => pasosDeLaForma(_rubro?.forma ?? modulosActuales.value.forma);

  Future<void> _guardarNegocio() async {
    setState(() => _guardando = true);
    try {
      await widget.alGuardarNegocio(_nombreCtrl.text.trim(), _rubro!);
    } catch (e) {
      // Sin esto, una falla dejaba el paso trabado: el botón y "Después" apagados para siempre.
      if (mounted) {
        setState(() => _guardando = false);
        mostrarAvisoNs(context, 'No se pudo guardar: ${_textoDeError(e)}', largo: true);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _guardando = false);
    _seguir(hecho: true);
  }

  @override
  Widget build(BuildContext context) {
    final pasos = _pasos;
    final cabecera = _CabeceraPaso(
      paso: pasos.indexOf(_paso).clamp(0, pasos.length - 1),
      total: pasos.length,
      alDespues: _guardando ? null : () => _seguir(hecho: false),
    );
    return AnimatedSwitcher(
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
              cabecera: cabecera,
              nombreCtrl: _nombreCtrl,
              rubro: _rubro,
              guardando: _guardando,
              alElegirRubro: (r) => setState(() => _rubro = r),
              alCambiarNombre: () => setState(() {}),
              alSeguir: _guardarNegocio,
            ),
          // Un plato se carga como un servicio: nombre, precio y lo que tarda (que suma la mano de obra), sin stock (§22).
          PasoNegocio.producto when (_rubro?.forma ?? modulosActuales.value.forma) != FormaDeTrabajo.productos => _PasoServicio(
              esPlato: (_rubro?.forma ?? modulosActuales.value.forma) == FormaDeTrabajo.gastronomia,
              cabecera: cabecera,
              categorias: _rubro != null ? [for (final c in _rubro!.categorias) c.nombre] : widget.categoriasExistentes,
              alGuardar: widget.alGuardarServicio ?? (_) async {},
              alSeguir: () => _seguir(hecho: true),
            ),
          PasoNegocio.producto => _PasoProducto(
              cabecera: cabecera,
              categorias: _rubro != null ? [for (final c in _rubro!.categorias) c.nombre] : widget.categoriasExistentes,
              alEscanear: widget.alEscanear,
              alGuardar: widget.alGuardarProducto,
              alSeguir: () => _seguir(hecho: true),
            ),
          PasoNegocio.horario => _PasoHorario(
              cabecera: cabecera,
              inicial: widget.horarioInicial,
              alGuardar: widget.alGuardarHorario ?? (_) async {},
              alSeguir: () => _seguir(hecho: true),
            ),
          PasoNegocio.pedidos => _PasoPedidos(
              cabecera: cabecera,
              inicial: widget.pedidosIniciales,
              alGuardar: widget.alGuardarPedidos ?? (_) async {},
              tieneBot: widget.tieneBot,
              alAbrirBot: widget.alAbrirBot,
              alAbrirWeb: widget.alAbrirWeb,
              alSeguir: () => _seguir(hecho: true),
            ),
          PasoNegocio.cobros => _PasoCobros(cabecera: cabecera, alAbrirWeb: widget.alAbrirWeb, alTerminar: () => _seguir(hecho: true)),
        },
      ),
    );
  }
}

/// "Paso N de 3", las tres barras de avance y "Después" (mock: `steps` + `top`).
class _CabeceraPaso extends StatelessWidget {
  const _CabeceraPaso({required this.paso, required this.total, required this.alDespues});
  final int paso;
  final int total;
  final VoidCallback? alDespues;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Text('Paso ${paso + 1} de $total', style: estiloNs(13, peso: FontWeight.w600, color: ns.mute)),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < total; i++)
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      curve: const Cubic(0.2, 0, 0, 1),
                      height: 5,
                      margin: EdgeInsets.only(right: i == total - 1 ? 0 : 5),
                      decoration: BoxDecoration(color: i <= paso ? ns.ink : ns.s2, borderRadius: BorderRadius.circular(3)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          PresionNs(
            key: const Key('asistente-despues'),
            onTap: alDespues,
            habilitado: alDespues != null,
            etiqueta: 'Después',
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              child: Text('Después', style: estiloNs(15, peso: FontWeight.w600, color: ns.mute)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Paso 1 · Nombre y rubro

class _PasoNegocio extends StatelessWidget {
  const _PasoNegocio({
    required this.cabecera,
    required this.nombreCtrl,
    required this.rubro,
    required this.guardando,
    required this.alElegirRubro,
    required this.alCambiarNombre,
    required this.alSeguir,
  });

  final Widget cabecera;
  final TextEditingController nombreCtrl;
  final PlantillaRubro? rubro;
  final bool guardando;
  final ValueChanged<PlantillaRubro> alElegirRubro;
  final VoidCallback alCambiarNombre;
  final VoidCallback alSeguir;

  @override
  Widget build(BuildContext context) {
    final listo = nombreCtrl.text.trim().isNotEmpty && rubro != null;
    final categorias = rubro?.categorias ?? const [];
    return PaginaArranqueNs(
      cabecera: cabecera,
      titulo: 'Contanos de tu negocio',
      tituloChico: true,
      bajada: 'Con esto armamos la app a tu medida. Todo se puede cambiar después.',
      cuerpo: [
        KeyedSubtree(
          key: const Key('asistente-nombre'),
          child: CampoNs(
            etiqueta: 'Nombre del comercio',
            controller: nombreCtrl,
            placeholder: switch (edicionActual) {
              Edicion.servicios => 'Ej.: Nails Sofi',
              Edicion.gastronomia => 'Ej.: Rotisería Doña Ana',
              Edicion.almacen => 'Ej.: Almacén Don Pepe',
            },
            onChanged: (_) => alCambiarNombre(),
          ),
        ),
        const InfoNs('Sale en los tickets y arriba de la app.'),
        // Nodo Gastro: un solo rubro, ya elegido (El dueño, 2026-10-18: "el selector está demás"). Se dice qué categorías trae.
        if (esEdicionGastronomia && rubro != null)
          InfoNs('Te dejamos estas categorías para tu carta: ${categorias.map((c) => c.nombre).join(', ')}. Las cambiás cuando quieras.', tono: TonoNs.good),
        // En dos grupos (`docs/PLAN-SERVICIOS.md`, etapa 1): el rubro decide si la app es de productos o de servicios. Lo
        // que trae el rubro elegido se cuenta debajo de su grupo, a la vista: con siete rubros, al final de la lista
        // quedaba fuera de la pantalla.
        // Nodo Sur Servicios es solo para turnos: no ofrece los rubros de productos.
        if (!esEdicionGastronomia)
        for (final (titulo, rubros) in [
          if (!esEdicionAparte) ('Vendés productos', PlantillaRubro.deForma(FormaDeTrabajo.productos)),
          (esEdicionServicios ? 'Tu rubro' : 'Das servicios', PlantillaRubro.deForma(FormaDeTrabajo.servicios)),
          // "Otro" es de productos: en una edición aparte llevaba al primer producto con código de barras y sacaba el horario que
          // usa el bot. Ahí no se ofrece, igual que en Configuración › Tu negocio.
          if (!esEdicionAparte) ('¿Ninguno?', const [PlantillaRubro.otro]),
        ]) ...[
          SeccionNs(titulo),
          for (final r in rubros)
            KeyedSubtree(
              key: Key('rubro-${r.clave}'),
              child: OpcionNs(titulo: r.nombre, detalle: r.descripcion, derecha: rubro == r ? 'Elegido' : null, marcada: rubro == r, onTap: () => alElegirRubro(r)),
            ),
          if (rubro != null && rubros.contains(rubro))
            InfoNs(
              categorias.isEmpty ? 'Arrancás sin categorías: las armás vos.' : 'Te dejamos estas categorías para empezar: ${categorias.map((c) => c.nombre).join(', ')}.',
              tono: TonoNs.good,
            ),
        ],
      ],
      botones: [
        KeyedSubtree(key: const Key('asistente-seguir'), child: BotonNs.primario(context, 'Siguiente', listo && !guardando ? alSeguir : null, habilitado: listo && !guardando)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Paso 2 · El primer producto, como práctica

enum _EtapaProducto { invitar, completar, listo }

class _PasoProducto extends StatefulWidget {
  const _PasoProducto({required this.cabecera, required this.categorias, required this.alEscanear, required this.alGuardar, required this.alSeguir});
  final Widget cabecera;
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
    try {
      await widget.alGuardar(p);
    } catch (e) {
      if (mounted) {
        setState(() => _trabajando = false);
        mostrarAvisoNs(context, 'No se pudo guardar: ${_textoDeError(e)}', largo: true);
      }
      return;
    }
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

  Widget _invitar(BuildContext context) => PaginaArranqueNs(
        cabecera: widget.cabecera,
        titulo: 'Cargá tu primer producto',
        tituloChico: true,
        bajada: 'Agarrá algo que tengas a mano y escaneá su código. Así se carga cualquier producto.',
        cuerpo: const [
          InfoNs('1 · Escaneás el código de barras.'),
          InfoNs('2 · Le ponés nombre y precio.'),
          InfoNs('3 · Desde ahí ya lo podés vender.'),
        ],
        botones: [
          KeyedSubtree(
            key: const Key('asistente-escanear'),
            child: BotonNs.primario(context, _trabajando ? 'Buscando el código…' : 'Escanear', _trabajando ? null : _escanear, habilitado: !_trabajando),
          ),
        ],
      );

  Widget _completar(BuildContext context) {
    final ns = context.ns;
    final listo = _nombre.text.trim().isNotEmpty && _precioCentavos > 0;
    return PaginaArranqueNs(
      cabecera: widget.cabecera,
      titulo: 'Es nuevo: completalo',
      tituloChico: true,
      bajada: 'Con nombre y precio alcanza. El resto lo podés sumar cuando quieras.',
      cuerpo: [
        FilaClaveValorNs(clave: 'Código leído', valor: _codigo!, sinLinea: true),
        KeyedSubtree(
          key: const Key('producto-nombre'),
          child: CampoNs(etiqueta: 'Nombre', controller: _nombre, placeholder: 'Ej.: Yerba 1 kg', onChanged: (_) => setState(() {})),
        ),
        KeyedSubtree(
          key: const Key('producto-precio'),
          child: CampoNs(
            etiqueta: 'Precio de venta',
            controller: _precio,
            placeholder: r'$ 0',
            grande: true,
            teclado: TextInputType.number,
            formatos: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (widget.categorias.isNotEmpty) ...[
          const SeccionNs('Categoría'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in widget.categorias) ChipNs(texto: c, activo: _categoria == c, onTap: () => setState(() => _categoria = c)),
            ],
          ),
        ],
        Row(
          children: [
            Expanded(child: Text('¿Cuántos tenés?', style: estiloNs(17, peso: FontWeight.w500, color: ns.ink))),
            StepperNs(
              cantidad: '$_stock',
              onMenos: _stock > 1 ? () => setState(() => _stock--) : null,
              onMas: () => setState(() => _stock++),
            ),
          ],
        ),
      ],
      botones: [
        KeyedSubtree(
          key: const Key('producto-guardar'),
          child: BotonNs.primario(context, 'Guardar producto', listo && !_trabajando ? _guardar : null, habilitado: listo && !_trabajando),
        ),
      ],
    );
  }

  Widget _listo(BuildContext context) {
    final p = _producto!;
    return PaginaArranqueNs(
      cabecera: widget.cabecera,
      titulo: '¡Ya lo podés vender!',
      tituloChico: true,
      bajada: 'Quedó cargado. Así de rápido se suma cualquier producto.',
      cuerpo: [
        HeroHojaNs(rotulo: 'Producto cargado', cifra: p.nombre, apoyo: '${p.categoria != null ? '${p.categoria} · ' : ''}Stock ${p.stock}'),
        const InfoNs('Cuando vendas, escanealo desde Vender y se suma solo al carrito.'),
        const InfoNs('Desde Productos, el botón de escanear carga productos nuevos o edita los que ya tenés.'),
      ],
      botones: [KeyedSubtree(key: const Key('asistente-seguir'), child: BotonNs.primario(context, 'Siguiente', widget.alSeguir))],
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Paso 2 en un negocio de servicios · El primer servicio (sin código de barras ni stock: nombre, duración y precio)

class _PasoServicio extends StatefulWidget {
  const _PasoServicio({required this.cabecera, required this.categorias, required this.alGuardar, required this.alSeguir, this.esPlato = false});

  /// Nodo Gastro: el primer plato de la carta en vez del primer servicio.
  final bool esPlato;
  final Widget cabecera;
  final List<String> categorias;
  final Future<void> Function(ServicioDePrueba servicio) alGuardar;
  final VoidCallback alSeguir;

  @override
  State<_PasoServicio> createState() => _PasoServicioState();
}

class _PasoServicioState extends State<_PasoServicio> {
  final _nombre = TextEditingController();
  final _duracion = TextEditingController(text: '30');
  final _precio = TextEditingController();
  String? _categoria;
  bool _trabajando = false;
  ServicioDePrueba? _guardado;

  @override
  void dispose() {
    _nombre.dispose();
    _duracion.dispose();
    _precio.dispose();
    super.dispose();
  }

  int get _precioCentavos => (int.tryParse(_precio.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0) * 100;
  int get _minutos => int.tryParse(_duracion.text) ?? 0;

  Future<void> _guardar() async {
    setState(() => _trabajando = true);
    final s = ServicioDePrueba(nombre: _nombre.text.trim(), duracionMinutos: _minutos, precioCentavos: _precioCentavos, categoria: _categoria);
    try {
      await widget.alGuardar(s);
    } catch (e) {
      if (mounted) {
        setState(() => _trabajando = false);
        mostrarAvisoNs(context, 'No se pudo guardar: ${_textoDeError(e)}', largo: true);
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _trabajando = false;
      _guardado = s;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _guardado;
    if (s != null) {
      return PaginaArranqueNs(
        cabecera: widget.cabecera,
        titulo: '¡Listo, ya está cargado!',
        tituloChico: true,
        bajada: widget.esPlato ? 'Así se suma cualquier plato, desde la pestaña Carta.' : 'Así se suma cualquier servicio, desde la pestaña Servicios.',
        cuerpo: [
          HeroHojaNs(rotulo: widget.esPlato ? 'Plato cargado' : 'Servicio cargado', cifra: s.nombre, apoyo: '${s.categoria != null ? '${s.categoria} · ' : ''}${s.duracionMinutos} min'),
          InfoNs(widget.esPlato
              ? 'En Carta › Insumos cargás lo que lleva (carne, pan rallado, aceite) y la app te dice cuánto te cuesta cada plato y a cuánto conviene venderlo.'
              : 'En Servicios › Insumos cargás lo que usa (tintura, guantes, shampoo) y la app te dice cuánto te cuesta cada servicio y a cuánto conviene cobrarlo.'),
        ],
        botones: [KeyedSubtree(key: const Key('asistente-seguir'), child: BotonNs.primario(context, 'Siguiente', widget.alSeguir))],
      );
    }
    final listo = _nombre.text.trim().isNotEmpty && _precioCentavos > 0 && _minutos > 0;
    return PaginaArranqueNs(
      cabecera: widget.cabecera,
      titulo: widget.esPlato ? 'Cargá tu primer plato' : 'Cargá tu primer servicio',
      tituloChico: true,
      bajada: widget.esPlato
          ? 'Con nombre, cuánto tarda en salir y el precio alcanza. Lo que lleva lo sumás después.'
          : 'Con nombre, cuánto dura y el precio alcanza. Lo que usa cada vez lo sumás después.',
      cuerpo: [
        KeyedSubtree(
          key: const Key('servicio-nombre'),
          child: CampoNs(etiqueta: 'Nombre', controller: _nombre, placeholder: widget.esPlato ? 'Ej.: Milanesa con papas' : 'Ej.: Corte de dama', onChanged: (_) => setState(() {})),
        ),
        KeyedSubtree(
          key: const Key('servicio-duracion'),
          child: CampoNs(
            etiqueta: widget.esPlato ? 'Cuánto tarda en salir (min)' : 'Cuánto dura (min)',
            controller: _duracion,
            teclado: TextInputType.number,
            formatos: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
          ),
        ),
        KeyedSubtree(
          key: const Key('servicio-precio'),
          child: CampoNs(
            etiqueta: 'Precio',
            controller: _precio,
            placeholder: r'$ 0',
            grande: true,
            teclado: TextInputType.number,
            formatos: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (widget.categorias.isNotEmpty) ...[
          const SeccionNs('Categoría'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in widget.categorias) ChipNs(texto: c, activo: _categoria == c, onTap: () => setState(() => _categoria = c)),
            ],
          ),
        ],
      ],
      botones: [
        KeyedSubtree(
          key: const Key('servicio-guardar'),
          child: BotonNs.primario(context, 'Guardar servicio', listo && !_trabajando ? _guardar : null, habilitado: listo && !_trabajando),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Paso 3 · Mercado Pago y el equipo (se hacen en horsepos.com/negocio)

// ---------------------------------------------------------------------------------------------------------------------
// Paso 3 (servicios) · El horario de atención

class _PasoHorario extends StatefulWidget {
  const _PasoHorario({required this.cabecera, required this.inicial, required this.alGuardar, required this.alSeguir});
  final Widget cabecera;
  final HorarioAtencion inicial;
  final Future<void> Function(HorarioAtencion horario) alGuardar;
  final VoidCallback alSeguir;

  @override
  State<_PasoHorario> createState() => _PasoHorarioState();
}

class _PasoHorarioState extends State<_PasoHorario> {
  static const _dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  // Un mismo horario para los días elegidos: lo común en un local chico. Un día distinto se ajusta en Configuración.
  late final Set<int> _abiertos = {for (var d = 1; d <= 7; d++) if (widget.inicial.dias[d] != null) d};
  late final FranjaAtencion _primera = widget.inicial.dias.values.whereType<FranjaAtencion>().firstOrNull ?? (desdeMin: 540, hastaMin: 1200);
  late final _abre = TextEditingController(text: horaDeMinutos(_primera.desdeMin));
  late final _cierra = TextEditingController(text: horaDeMinutos(_primera.hastaMin));
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _abre.dispose();
    _cierra.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final desde = minutosDeHora(_abre.text), hasta = minutosDeHora(_cierra.text);
    if (_abiertos.isEmpty) return setState(() => _error = 'Elegí al menos un día');
    if (desde == null || hasta == null) return setState(() => _error = 'El horario va como 09:00');
    if (desde >= hasta) return setState(() => _error = 'Cierra antes de abrir');
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.alGuardar(HorarioAtencion({for (var d = 1; d <= 7; d++) d: _abiertos.contains(d) ? (desdeMin: desde, hastaMin: hasta) : null}));
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo guardar: ${_textoDeError(e)}');
      return;
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
    widget.alSeguir();
  }

  @override
  Widget build(BuildContext context) => PaginaArranqueNs(
        cabecera: widget.cabecera,
        titulo: '¿Cuándo atendés?',
        tituloChico: true,
        bajada: esEdicionGastronomia
            ? 'El bot de WhatsApp toma pedidos en este horario: lo que llega fuera de hora queda programado. Si algún día es distinto, '
                'lo cambiás en Configuración › Horario y transferencias.'
            : 'La Agenda y el bot de WhatsApp solo ofrecen turnos en este horario. Si algún día es distinto, lo cambiás en '
                'Configuración › Agenda y seña.',
        cuerpo: [
          const SeccionNs('Días'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var d = 1; d <= 7; d++)
                ChipNs(
                  key: ValueKey('horario-dia-$d'),
                  texto: _dias[d - 1],
                  activo: _abiertos.contains(d),
                  onTap: () => setState(() => _abiertos.contains(d) ? _abiertos.remove(d) : _abiertos.add(d)),
                ),
            ],
          ),
          const SeccionNs('Horario'),
          Row(
            children: [
              Expanded(child: CampoNs(key: const Key('horario-abre'), etiqueta: 'Abre', controller: _abre, placeholder: '09:00', teclado: TextInputType.datetime)),
              const SizedBox(width: 10),
              Expanded(child: CampoNs(key: const Key('horario-cierra'), etiqueta: 'Cierra', controller: _cierra, placeholder: '20:00', teclado: TextInputType.datetime)),
            ],
          ),
          if (_error != null) InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
        ],
        botones: [
          KeyedSubtree(
            key: const Key('asistente-guardar-horario'),
            child: BotonNs.primario(context, _guardando ? 'Guardando…' : 'Guardar horario', _guardando ? null : _guardar, habilitado: !_guardando),
          ),
        ],
      );
}

// ---------------------------------------------------------------------------------------------------------------------
// Nodo Gastro · lo más rompedor, configurado en corto (El dueño, 2026-10-18: "las funciones deberían ser las más rompedoras"):
// el bot que atiende solo, el catálogo de WhatsApp que copia la carta, cobrar antes de cocinar y la cocina que frena al bot. Las
// entregas van al final: el bot las necesita, pero no son lo que lo hace distinto.

class _PasoPedidos extends StatefulWidget {
  const _PasoPedidos({
    required this.cabecera,
    required this.inicial,
    required this.alGuardar,
    required this.tieneBot,
    required this.alAbrirBot,
    required this.alAbrirWeb,
    required this.alSeguir,
  });
  final Widget cabecera;
  final ConfigPedidos inicial;
  final Future<void> Function(ConfigPedidos config) alGuardar;
  final Future<bool?> Function()? tieneBot;
  final Future<void> Function(BuildContext context)? alAbrirBot;
  final void Function(String seccion) alAbrirWeb;
  final VoidCallback alSeguir;

  @override
  State<_PasoPedidos> createState() => _PasoPedidosState();
}

class _PasoPedidosState extends State<_PasoPedidos> {
  late bool _retiro = widget.inicial.retiro;
  late bool _cadete = widget.inicial.cadetePropio;
  late bool _reparto = widget.inicial.servicioReparto;
  late ModoPagoPedido _pago = widget.inicial.pago;
  late bool _entranSolos = widget.inicial.confirmacionAutomatica;
  late bool _catalogo = widget.inicial.catalogoWhatsapp;
  final _zona = TextEditingController();
  final _costoZona = TextEditingController();

  /// Null mientras se pregunta (o si no se pudo saber).
  bool? _conBot;
  bool _preguntandoBot = true;
  bool _guardando = false;
  String? _error;

  /// Un envío necesita al menos una zona con su costo: sin eso no se ofrece (`ConfigPedidos.formasDisponibles`).
  bool get _pideZona => (_cadete || _reparto) && widget.inicial.zonas.isEmpty;

  @override
  void initState() {
    super.initState();
    _preguntarBot();
  }

  Future<void> _preguntarBot() async {
    bool? con;
    try {
      con = await widget.tieneBot?.call();
    } catch (_) {
      // Sin red: se ofrece verlo en la web, que es lo mismo que no tenerlo todavía.
    }
    if (mounted) {
      setState(() {
        _conBot = con;
        _preguntandoBot = false;
      });
    }
  }

  @override
  void dispose() {
    _zona.dispose();
    _costoZona.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_retiro && !_cadete && !_reparto) return setState(() => _error = 'Elegí al menos una forma de entregar');
    var zonas = widget.inicial.zonas;
    if (_pideZona) {
      int? costo;
      try {
        costo = parsearARS(_costoZona.text.trim());
      } on FormatException {
        costo = null;
      }
      if (_zona.text.trim().isEmpty || costo == null || costo < 0) return setState(() => _error = 'Poné una zona y lo que cobrás el envío');
      zonas = [ZonaEnvio(nombre: _zona.text.trim(), costoCentavos: costo)];
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    final i = widget.inicial;
    try {
      await widget.alGuardar(ConfigPedidos(
        retiro: _retiro,
        cadetePropio: _cadete,
        servicioReparto: _reparto,
        zonas: zonas,
        pago: _pago,
        confirmacionAutomatica: _entranSolos,
        minutosNormal: i.minutosNormal,
        minutosDemorada: i.minutosDemorada,
        catalogoWhatsapp: _catalogo,
      ));
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo guardar: ${_textoDeError(e)}');
      return;
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
    widget.alSeguir();
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return PaginaArranqueNs(
      cabecera: widget.cabecera,
      titulo: 'Lo que ningún otro sistema hace',
      tituloChico: true,
      bajada: 'Tu local atiende, cobra y se organiza solo. Lo dejás andando ahora; lo ajustás cuando quieras en Configuración › Pedidos.',
      cuerpo: [
        // 1. El bot: contesta al toque, que es justo lo que le falta a un local que pierde pedidos por no llegar a contestar.
        const SeccionNs('Tu WhatsApp atiende solo'),
        KeyedSubtree(
          key: const Key('asistente-bot'),
          child: _preguntandoBot
              ? const InfoNs('Fijándonos si tu plan trae el bot…')
              : OpcionNs(
                  titulo: 'Bot de WhatsApp',
                  detalle: 'Contesta al toque a cualquier hora, manda la carta, toma el pedido con la dirección y te lo deja en Pedidos '
                      'listo para cocinar. ${_conBot == true && widget.alAbrirBot != null ? 'Lo vinculás con el WhatsApp del local.' : 'Viene con el plan Sistema + Bot.'}',
                  derecha: _conBot == true && widget.alAbrirBot != null ? 'Encender' : 'Ver planes',
                  derechaComoBoton: true,
                  onTap: () => _conBot == true && widget.alAbrirBot != null ? widget.alAbrirBot!(context) : widget.alAbrirWeb('bot'),
                ),
        ),
        // 2. El catálogo de WhatsApp Business, espejo de la carta: el cliente arma el carrito y el bot lo toma.
        const SeccionNs('Te piden desde tu catálogo de WhatsApp'),
        InterruptorNs(
          key: const Key('asistente-catalogo'),
          etiqueta: 'Tengo WhatsApp Business con catálogo',
          descripcion: _catalogo
              ? 'El bot le copia tu carta (precios y lo que se acabó) y toma el carrito que arma el cliente.'
              : 'El bot manda la carta escrita. Si armás el catálogo después, lo prendés en Configuración › Pedidos.',
          encendido: _catalogo,
          onCambio: (v) => setState(() => _catalogo = v),
        ),
        // 3. Cobrar antes de cocinar: el pedido entra recién pagado, sin plantones.
        const SeccionNs('Cobrás antes de cocinar'),
        SegmentoNs(
          key: const Key('asistente-pago'),
          opciones: const ['Al entregar', 'Adelantado', 'Que elija'],
          indice: ModoPagoPedido.values.indexOf(_pago),
          onCambio: (i) => setState(() => _pago = ModoPagoPedido.values[i]),
        ),
        Text(
          switch (_pago) {
            ModoPagoPedido.alEntregar => 'Se cobra al retirar, o al recibir el envío.',
            ModoPagoPedido.adelantado => 'El bot manda el link de Mercado Pago y el pedido te entra recién pagado. Nadie te deja un pedido colgado.',
            ModoPagoPedido.aElegir => 'El cliente elige si paga ahora por Mercado Pago o al recibir.',
          },
          style: estiloNs(14, color: ns.mute),
        ),
        if (_pago != ModoPagoPedido.alEntregar) const InfoNs('Para el link, conectá Mercado Pago en el paso que sigue.'),
        // 4. La cocina manda: el bot no promete lo que la cocina no puede sacar.
        const SeccionNs('La cocina manda'),
        const InfoNs('Si se llena, en Pedidos tocás "Con demora" o "Pausada": el bot avisa la demora real o deja de tomar pedidos. '
            'El mostrador sigue igual.'),
        InterruptorNs(
          key: const Key('asistente-entran-solos'),
          etiqueta: 'Los pedidos de WhatsApp entran solos a la cocina',
          descripcion: _entranSolos ? 'Van directo a "por hacer".' : 'Esperan que alguien del local los acepte.',
          encendido: _entranSolos,
          onCambio: (v) => setState(() => _entranSolos = v),
        ),
        const SeccionNs('Y cómo entregás'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChipNs(key: const Key('asistente-retiro'), texto: 'Retiran en el local', activo: _retiro, onTap: () => setState(() => _retiro = !_retiro)),
            ChipNs(key: const Key('asistente-cadete'), texto: 'Cadete propio', activo: _cadete, onTap: () => setState(() => _cadete = !_cadete)),
            ChipNs(key: const Key('asistente-reparto'), texto: 'Servicio de reparto', activo: _reparto, onTap: () => setState(() => _reparto = !_reparto)),
          ],
        ),
        if (_pideZona) ...[
          Row(
            children: [
              Expanded(child: CampoNs(key: const Key('asistente-zona'), etiqueta: 'Zona de envío', controller: _zona, placeholder: 'Centro')),
              const SizedBox(width: 10),
              Expanded(
                child: CampoNs(key: const Key('asistente-costo-zona'), etiqueta: 'Cuánto cobrás', controller: _costoZona, placeholder: r'$ 1500', teclado: TextInputType.number, formatos: soloDigitosNs),
              ),
            ],
          ),
          const InfoNs('Una zona para empezar. Las demás, con su costo y su demora, en Configuración › Pedidos.'),
        ],
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
      ],
      botones: [
        KeyedSubtree(
          key: const Key('asistente-guardar-pedidos'),
          child: BotonNs.primario(context, _guardando ? 'Guardando…' : 'Dejarlo andando', _guardando ? null : _guardar, habilitado: !_guardando),
        ),
      ],
    );
  }
}

class _PasoCobros extends StatelessWidget {
  const _PasoCobros({required this.cabecera, required this.alAbrirWeb, required this.alTerminar});
  final Widget cabecera;
  final void Function(String seccion) alAbrirWeb;
  final VoidCallback alTerminar;

  @override
  Widget build(BuildContext context) => PaginaArranqueNs(
        cabecera: cabecera,
        titulo: esEdicionServicios ? 'Cobros' : 'Cobros y equipo',
        tituloChico: true,
        bajada: esEdicionServicios
            ? 'Se conecta en horsepos.com con tu cuenta. Se abre el navegador y volvés a la app.'
            : 'Las dos cosas se hacen en horsepos.com con tu cuenta. Se abre el navegador y volvés a la app.',
        cuerpo: [
          KeyedSubtree(
            key: const Key('web-mercado-pago'),
            child: OpcionNs(
              titulo: 'Conectá Mercado Pago',
              detalle: esEdicionServicios
                  ? 'Las señas se cobran solas con un link que manda el bot, y en el local cobrás con un QR en la pantalla del celular.'
                  : esEdicionGastronomia
                      ? 'El bot manda el link de pago de los pedidos, y en el local cobrás con QR o con tu terminal Point.'
                      : 'Cobrá con QR y débito en tu terminal Point. Lo cobrado entra en la caja como Mercado Pago.',
              derecha: 'Conectar',
              derechaComoBoton: true,
              onTap: () => alAbrirWeb('mercado-pago'),
            ),
          ),
          // Nodo Sur Servicios es de una sola persona (sin varios usuarios, `docs/PLAN-APP-SERVICIOS.md`).
          if (!esEdicionServicios) KeyedSubtree(
            key: const Key('web-equipo'),
            child: OpcionNs(
              titulo: 'Sumá a tu equipo',
              detalle: 'Invitá a tus empleados por mail. Cada uno entra con su cuenta y lo que hace queda a su nombre.',
              derecha: 'Invitar',
              derechaComoBoton: true,
              onTap: () => alAbrirWeb('equipo'),
            ),
          ),
        ],
        botones: [KeyedSubtree(key: const Key('asistente-terminar'), child: BotonNs.primario(context, 'Terminar', alTerminar))],
      );
}

// ---------------------------------------------------------------------------------------------------------------------
// Recordatorio en Inicio

/// La tarjeta de Inicio mientras falte algún paso: qué falta y "Seguir configurando", que vuelve al asistente en el primero pendiente.
class TarjetaConfiguracionPendiente extends StatelessWidget {
  const TarjetaConfiguracionPendiente({super.key, required this.pendientes, required this.alSeguir});
  final Set<PasoNegocio> pendientes;
  final VoidCallback alSeguir;

  static Map<PasoNegocio, String> get _nombres => {
        PasoNegocio.negocio: 'Nombre y rubro',
        PasoNegocio.producto: switch (modulosActuales.value.forma) {
          FormaDeTrabajo.servicios => 'Tu primer servicio',
          FormaDeTrabajo.gastronomia => 'Tu primer plato',
          FormaDeTrabajo.productos => 'Tu primer producto',
        },
        PasoNegocio.horario: 'Horario de atención',
        PasoNegocio.pedidos: 'Bot, catálogo y cobro adelantado',
        PasoNegocio.cobros: esEdicionServicios ? 'Mercado Pago' : 'Mercado Pago y equipo',
      };

  @override
  Widget build(BuildContext context) {
    final pasos = pasosDelNegocio();
    final hechos = pasos.length - pendientes.where(pasos.contains).length;
    const blanco = TokensNs.blanco;
    return HeroNs(
      radio: 34,
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
      ancho: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$hechos de ${pasos.length} listos', style: estiloNs(14, peso: FontWeight.w500, color: const Color(0xC7FFFFFF))),
          const SizedBox(height: 4),
          Text(
            pendientes.length == 1 ? 'Te falta un paso' : 'Te faltan ${pendientes.length} pasos',
            style: tituloNs(30, track: -0.04, altura: 1.1, color: blanco),
          ),
          const SizedBox(height: 4),
          Text(
            [for (final p in PasoNegocio.values) if (pendientes.contains(p)) _nombres[p]!].join(' · '),
            style: estiloNs(16, altura: 1.4, color: const Color(0xCCFFFFFF)),
          ),
          const SizedBox(height: 16),
          PresionNs(
            key: const Key('pendiente-seguir'),
            onTap: alSeguir,
            etiqueta: 'Seguir configurando',
            child: Container(
              height: 62,
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: blanco, borderRadius: BorderRadius.circular(999)),
              child: Text('Seguir configurando', style: estiloNs(17, peso: FontWeight.w600, color: const Color(0xFF111111))),
            ),
          ),
        ],
      ),
    );
  }
}

/// Una validación (`ArgumentError`) trae su propio texto; lo demás, el de siempre.
String _textoDeError(Object e) => e is ArgumentError ? '${e.message}' : mensajeDeError(e);

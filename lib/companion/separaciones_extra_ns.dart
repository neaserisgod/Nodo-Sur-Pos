// Lo que la solapa Caja › Separar del celular no tenía de Separaciones de la PC (El dueño, 2026-10-07: "seguí con separaciones"):
// "Retirar plata" (la ganancia sin revisar de cada proveedor: retener como colchón o retirar, Regla 13) y "Vendido sin costo" (ver qué
// se vendió sin costo y cargárselo ahí mismo). Las cuentas y reglas son las de la PC: `SeparacionesControlador` (retener, retirar,
// sugerencia por medio, estado del mes), `evaluarRetiro`/`motivoParaNoRetirar` y `cargarCostoProducto`; acá solo se dibuja.

import 'package:flutter/material.dart';

import '../data/repositorio_productos.dart' show cargarCostoProducto;
import '../data/repositorio_reposicion.dart' show VendidoSinCosto, vendidoSinCostoDesde;
import '../domain/dinero.dart';
import '../domain/rentabilidad.dart';
import '../ui/separaciones/separaciones_controlador.dart';
import 'kit/kit_ns.dart';

/// "Retirar plata": la ganancia sin revisar de cada proveedor; elegir uno abre su ganancia (retener o retirar).
Future<void> mostrarRetirarPlataNs(BuildContext context, SeparacionesControlador c) async {
  final pendientes = c.gananciaSinRevisar.values.where((g) => g.gananciaCentavos > 0).toList()
    ..sort((a, b) => b.gananciaCentavos.compareTo(a.gananciaCentavos));
  final ns = context.ns;
  final proveedorId = await mostrarHojaNs<int>(
    context,
    builder: (ctx) => HojaNs(
      titulo: 'Retirar plata',
      texto: 'La ganancia se retira por proveedor: elegí de cuál. Lo que no se retira se puede retener como colchón. Todo queda anotado.',
      bloques: [
        if (pendientes.isEmpty) const InfoNs('No hay ganancia sin revisar.'),
        for (final g in pendientes)
          PresionNs(
            onTap: () => Navigator.of(ctx).pop(g.proveedor.id),
            etiqueta: g.proveedor.nombre,
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
              decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(22)),
              child: Row(
                children: [
                  Expanded(child: Text(g.proveedor.nombre, style: estiloNs(16, peso: FontWeight.w500, color: ns.ink))),
                  Text(plataNs(g.gananciaCentavos), style: estiloNs(16, peso: FontWeight.w600, color: ns.g)),
                  const SizedBox(width: 6),
                  IconoNsWidget(IconoNs.chevron, tamanio: 16, color: ns.mute, grosor: 2.2),
                ],
              ),
            ),
          ),
      ],
    ),
  );
  if (proveedorId != null && context.mounted) await mostrarGananciaProveedorNs(context, c, proveedorId);
}

/// La ganancia sin revisar de un proveedor: retenerla como colchón o retirarla.
Future<void> mostrarGananciaProveedorNs(BuildContext context, SeparacionesControlador c, int proveedorId) async {
  final g = c.gananciaSinRevisar[proveedorId];
  if (g == null) return;
  final ganancia = g.gananciaCentavos;
  final desde = g.proveedor.gananciaRevisadaFecha;
  final sinCaja = c.sesionCajaId == null;
  final habilitado = !sinCaja && ganancia > 0;
  final accion = await mostrarHojaNs<String>(
    context,
    builder: (ctx) => HojaNs(
      titulo: 'Ganancia — ${g.proveedor.nombre}',
      texto: desde == null
          ? 'Precio de venta menos costo, desde siempre (nunca se revisó).'
          : 'Precio de venta menos costo, desde el ${desde.day.toString().padLeft(2, '0')}/${desde.month.toString().padLeft(2, '0')}, la última vez que se retuvo o retiró.',
      bloques: [
        FilaClaveValorNs(clave: 'Ganancia sin revisar', valor: plataNs(ganancia), tamanioValor: 26, colorValor: ctx.ns.g),
        FilaClaveValorNs(clave: 'Vendido sin revisar', valor: plataNs(g.vendidoCentavos), tamanioValor: 16),
        FilaClaveValorNs(clave: 'Costo de lo vendido', valor: plataNs(g.vendidoCentavos - ganancia), tamanioValor: 16, sinLinea: true),
        if (sinCaja) const InfoNs('Para retener o retirar hace falta la caja abierta.', tono: TonoNs.warn),
      ],
      botones: [
        BotonNs.primario(ctx, 'Retirar ganancia', habilitado ? () => Navigator.of(ctx).pop('retirar') : null, habilitado: habilitado),
        BotonNs.secundario(ctx, 'Retener como colchón', habilitado ? () => Navigator.of(ctx).pop('retener') : null),
      ],
    ),
  );
  if (!context.mounted) return;
  if (accion == 'retener') {
    await c.retenerComoColchon(proveedorId, ganancia);
    if (context.mounted) mostrarAvisoNs(context, 'Ganancia de ${g.proveedor.nombre} retenida como colchón');
  } else if (accion == 'retirar') {
    final sugerencia = await c.sugerenciaRetiro(proveedorId);
    if (!context.mounted) return;
    final retiro = await mostrarHojaNs<({int efectivo, int virtual})>(
      context,
      builder: (_) => _HojaRetirar(
        c: c,
        nombre: g.proveedor.nombre,
        gananciaCentavos: ganancia,
        efectivoSugerido: sugerencia.efectivoCentavos,
        virtualSugerido: sugerencia.virtualCentavos,
      ),
    );
    if (retiro == null) return;
    await c.retirarGanancia(proveedorId, gananciaCentavos: ganancia, efectivoCentavos: retiro.efectivo, virtualCentavos: retiro.virtual);
    if (context.mounted) mostrarAvisoNs(context, 'Retiraste ${plataNs(retiro.efectivo + retiro.virtual)} de ${g.proveedor.nombre}');
  }
}

/// Cuánto se retira de cada medio, prellenado según cómo se cobraron las ventas (editable). Si pasa de lo retirable del mes, avisa y
/// pide confirmar, como la PC (El dueño, 2026-10-01).
class _HojaRetirar extends StatefulWidget {
  const _HojaRetirar({required this.c, required this.nombre, required this.gananciaCentavos, required this.efectivoSugerido, required this.virtualSugerido});
  final SeparacionesControlador c;
  final String nombre;
  final int gananciaCentavos;
  final int efectivoSugerido;
  final int virtualSugerido;

  @override
  State<_HojaRetirar> createState() => _HojaRetirarState();
}

class _HojaRetirarState extends State<_HojaRetirar> {
  late final _efectivo = TextEditingController(text: _sinSigno(widget.efectivoSugerido));
  late final _virtual = TextEditingController(text: _sinSigno(widget.virtualSugerido));
  String? _error;
  EvaluacionDeRetiro? _exceso;
  EstadoDeResultados? _estado;

  static String _sinSigno(int centavos) => centavos == 0 ? '' : formatearARS(centavos, conSigno: false);

  @override
  void dispose() {
    _efectivo.dispose();
    _virtual.dispose();
    super.dispose();
  }

  int? _leer(TextEditingController c) {
    try {
      return parsearARS(c.text.trim().isEmpty ? '0' : c.text);
    } on FormatException {
      return null;
    }
  }

  Future<void> _confirmar({bool igual = false}) async {
    final efectivo = _leer(_efectivo);
    final virtual = _leer(_virtual);
    if (efectivo == null || virtual == null) {
      setState(() => _error = 'Revisá los montos');
      return;
    }
    final motivo = motivoParaNoRetirar(efectivoCentavos: efectivo, virtualCentavos: virtual, gananciaCentavos: widget.gananciaCentavos);
    if (motivo != null) {
      setState(() => _error = motivo);
      return;
    }
    // La ganancia bruta no es plata libre (faltan los gastos): se retira igual si el dueño lo decide, pero avisando.
    if (!igual && efectivo + virtual > 0) {
      final estado = await widget.c.estadoDelMes();
      final evaluacion = evaluarRetiro(montoCentavos: efectivo + virtual, estado: estado);
      if (evaluacion.requiereConfirmacion) {
        if (mounted) {
          setState(() {
            _exceso = evaluacion;
            _estado = estado;
          });
        }
        return;
      }
    }
    if (mounted) Navigator.of(context).pop((efectivo: efectivo, virtual: virtual));
  }

  @override
  Widget build(BuildContext context) {
    final retiro = (_leer(_efectivo) ?? 0) + (_leer(_virtual) ?? 0);
    final colchon = widget.gananciaCentavos - retiro;
    final exceso = _exceso;
    final estado = _estado;
    return HojaNs(
      titulo: 'Retirar — ${widget.nombre}',
      texto: 'Ganancia disponible ${plataNs(widget.gananciaCentavos)}. Calculado según cómo se cobraron las ventas: se puede corregir.',
      bloques: [
        CampoNs(etiqueta: 'Efectivo', controller: _efectivo, placeholder: r'$ 0', teclado: TextInputType.number, formatos: soloDigitosNs,
            onChanged: (_) => setState(() => _error = _exceso = null)),
        CampoNs(etiqueta: 'Mercado Pago', controller: _virtual, placeholder: r'$ 0', teclado: TextInputType.number, formatos: soloDigitosNs,
            onChanged: (_) => setState(() => _error = _exceso = null)),
        InfoNs(colchon > 0
            ? 'Se retiran ${plataNs(retiro)}. Los ${plataNs(colchon)} que quedan pasan a colchón.'
            : 'Se retiran ${plataNs(retiro)}: la ganancia de ${widget.nombre} queda revisada.'),
        if (exceso != null && estado != null) ...[
          const InfoNs('Estás retirando más de lo que el negocio ganó, después de pagar los gastos del mes.', tono: TonoNs.bad, icono: IconoNs.alerta),
          FilaClaveValorNs(clave: 'Ganancia bruta del mes', valor: plataNs(estado.gananciaBrutaCentavos), tamanioValor: 15),
          FilaClaveValorNs(clave: 'Gastos fijos y variables', valor: '− ${plataNs(estado.gastosFijosCentavos + estado.gastosVariablesCentavos)}', tamanioValor: 15),
          FilaClaveValorNs(clave: 'Ya retirado este mes', valor: '− ${plataNs(estado.retirosDelMesCentavos)}', tamanioValor: 15),
          FilaClaveValorNs(clave: 'Retirable hoy', valor: plataNs(exceso.retirableCentavos), tamanioValor: 17),
          FilaClaveValorNs(clave: 'Te pasás por', valor: plataNs(exceso.excedeCentavos), tamanioValor: 17, colorValor: context.ns.b, sinLinea: true),
        ],
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
      ],
      botones: [
        if (exceso == null)
          BotonNs.primario(context, 'Retirar', () => _confirmar())
        else
          BotonNs.peligroSolido(context, 'Retirar igual', () => _confirmar(igual: true)),
      ],
    );
  }
}

/// Qué se vendió sin costo cargado desde [desde] (de un solo proveedor si viene [soloProveedor]), con un campo para cargarle el costo
/// ahí mismo. "Varios" se lista sin campo: no tiene costo nunca. Mismo criterio que el diálogo de la PC: no se inventa un costo.
Future<void> mostrarSinCostoNs(
  BuildContext context,
  SeparacionesControlador c, {
  required DateTime desde,
  required String periodo,
  String? soloProveedor,
}) async {
  final guardo = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => _PantallaSinCosto(c: c, desde: desde, periodo: periodo, soloProveedor: soloProveedor)),
  );
  if (guardo == true) await c.cargarTodo();
}

class _PantallaSinCosto extends StatefulWidget {
  const _PantallaSinCosto({required this.c, required this.desde, required this.periodo, this.soloProveedor});
  final SeparacionesControlador c;
  final DateTime desde;
  final String periodo;
  final String? soloProveedor;

  @override
  State<_PantallaSinCosto> createState() => _PantallaSinCostoState();
}

class _PantallaSinCostoState extends State<_PantallaSinCosto> {
  List<VendidoSinCosto>? _lista;
  Set<int> _varios = {};
  final Map<int, TextEditingController> _campos = {};
  String? _error;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final c in _campos.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    final db = widget.c.db;
    final todos = await vendidoSinCostoDesde(db, widget.desde);
    final lista = [for (final v in todos) if (widget.soloProveedor == null || v.proveedor == widget.soloProveedor) v];
    final varios = await (db.select(db.productos)..where((p) => p.esVarios.equals(true))).get();
    if (!mounted) return;
    setState(() {
      _lista = lista;
      _varios = {for (final p in varios) p.id};
      for (final v in lista) {
        if (v.productoId != null && !_varios.contains(v.productoId)) _campos.putIfAbsent(v.productoId!, TextEditingController.new);
      }
    });
  }

  Future<void> _guardar() async {
    final aGuardar = <int, int>{};
    for (final MapEntry(key: id, value: ctrl) in _campos.entries) {
      if (ctrl.text.trim().isEmpty) continue;
      try {
        final costo = parsearARS(ctrl.text);
        if (costo <= 0) throw const FormatException();
        aGuardar[id] = costo;
      } on FormatException {
        setState(() => _error = 'Revisá los costos: hay uno que no es un monto');
        return;
      }
    }
    if (aGuardar.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    for (final MapEntry(key: id, value: costo) in aGuardar.entries) {
      await cargarCostoProducto(widget.c.db, productoId: id, costoCentavos: costo, usuarioId: widget.c.usuarioId);
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
    mostrarAvisoNs(context, aGuardar.length == 1 ? 'Costo guardado' : '${aGuardar.length} costos guardados');
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final lista = _lista;
    return PaginaNs(
      titulo: widget.soloProveedor == null ? 'Vendido sin costo' : '${widget.soloProveedor}: sin costo',
      cuerpo: lista == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                Text('Vendido ${widget.periodo}. Sin costo no se sabe cuánto separar: por ahora cuenta todo como ganancia.',
                    style: estiloNs(15, altura: 1.4, color: ns.mute)),
                const SizedBox(height: 12),
                if (lista.isEmpty) const InfoNs('No hay nada vendido sin costo.'),
                for (final v in lista)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(24)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(v.producto, maxLines: 2, overflow: TextOverflow.ellipsis, style: estiloNs(16, peso: FontWeight.w500, color: ns.ink)),
                        Text('${v.proveedor ?? 'Sin proveedor'} · ${v.gramos > 0 ? '${v.gramos} g' : '${v.cantidad} u.'} · vendido ${plataNs(v.vendidoCentavos)}',
                            style: estiloNs(13, color: ns.mute)),
                        const SizedBox(height: 8),
                        if (_campos[v.productoId] == null)
                          Text(_varios.contains(v.productoId) ? 'Varios: sin costo' : 'Sin producto en el catálogo', style: estiloNs(13, color: ns.mute))
                        else
                          CampoNs(
                            etiqueta: v.esPesable ? 'Costo por kilo' : 'Costo',
                            controller: _campos[v.productoId]!,
                            placeholder: r'$ 0',
                            teclado: const TextInputType.numberWithOptions(decimal: true),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
      botones: [
        if (_error != null) InfoNs(_error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo),
        if (_campos.isNotEmpty) BotonNs.primario(context, _guardando ? 'Guardando…' : 'Guardar costos', _guardando ? null : _guardar, habilitado: !_guardando),
      ],
    );
  }
}

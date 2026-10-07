// Cargar factura en el celular (El dueño, 2026-10-07: "que las funciones del sistema desktop estén disponibles para el apk, reutilizando la
// lógica; empezá por la lectura de facturas por IA"). Es el mismo flujo que Proveedores › "Leer una factura" de la PC — leer con la IA,
// vincular, bultos, aplicar y deshacer viven en `servicios/flujo_factura.dart` —, con la cámara del celular y una tarjeta por línea en
// vez de la tabla.
//
// Trabaja SIEMPRE contra la base propia del celular, aunque la PC esté en el wifi (El dueño: "independizar la apk de desktop"): la sync
// (v61) lleva a la PC la deuda, el stock, el costo, la factura aplicada y lo aprendido. La clave de la IA es la de este celular
// (Configuración › Asistente IA).

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/database.dart';
import '../domain/dinero.dart';
import '../domain/vinculo_factura.dart';
import '../servicios/flujo_factura.dart';
import '../servicios/gemini.dart';
import 'base_local.dart';
import 'emparejamiento.dart';
import 'kit/kit_ns.dart';
import 'mensaje_error.dart';
import 'pantalla_formulario_producto.dart';
import 'puerto_local.dart';

class PantallaCargarFactura extends StatefulWidget {
  /// [db], [usuarioId] y [flujo] son para tests; en la app se usa la base del celular y el usuario elegido.
  const PantallaCargarFactura({super.key, this.db, this.usuarioId, this.flujo});

  final AppDatabase? db;
  final int? usuarioId;
  final FlujoFactura? flujo;

  @override
  State<PantallaCargarFactura> createState() => _PantallaCargarFacturaState();
}

class _PantallaCargarFacturaState extends State<PantallaCargarFactura> {
  late final AppDatabase _db = widget.db ?? baseLocalCompanion();
  late final FlujoFactura _flujo = (widget.flujo ?? FlujoFactura(db: _db))..addListener(_redibujar);
  int? _usuarioId;

  @override
  void initState() {
    super.initState();
    _usuarioId = widget.usuarioId;
    if (_usuarioId == null) {
      leerUsuario().then((u) {
        if (mounted) setState(() => _usuarioId = u?.id);
      });
    }
  }

  void _redibujar() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _flujo.removeListener(_redibujar);
    if (widget.flujo == null) _flujo.dispose();
    super.dispose();
  }

  /// Una foto por vez: una factura larga son varias fotos, y se suman.
  Future<void> _sacarFoto() async {
    try {
      final foto = await ImagePicker().pickImage(source: ImageSource.camera);
      if (foto == null) return;
      await _flujo.agregarArchivo(foto.name, await foto.readAsBytes());
    } catch (e) {
      if (mounted) mostrarAvisoNs(context, 'No se pudo usar la cámara: ${mensajeDeError(e)}');
    }
  }

  Future<void> _elegirArchivos() async {
    final archivos = await openFiles(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Fotos y PDF', extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic', 'pdf'], mimeTypes: ['image/*', 'application/pdf']),
      ],
    );
    for (final f in archivos) {
      await _flujo.agregarArchivo(f.name, await f.readAsBytes());
    }
  }

  Future<void> _aplicar(EstadoFactura e) async {
    final usuarioId = _usuarioId;
    if (usuarioId == null) {
      mostrarAvisoNs(context, 'Falta elegir usuario');
      return;
    }
    final control = e.n.control;
    if (control != null && e.hayQueConfirmar && _flujo.lineasParaAplicar(e) != null) {
      final seguir = await mostrarHojaNs<bool>(
        context,
        builder: (ctx) => HojaNs(
          titulo: 'La factura no cierra',
          texto: 'Lo leído tiene ${formatearARS(control.diferenciaCentavos.abs())} de diferencia con el total impreso: puede haber algo mal '
              'leído. Si aplicás igual, la deuda se carga por el total impreso.',
          botones: [
            BotonNs.primario(ctx, 'Aplicar igual', () => Navigator.of(ctx).pop(true)),
            BotonNs.secundario(ctx, 'Revisar', () => Navigator.of(ctx).pop(false)),
          ],
        ),
      );
      if (seguir != true || !mounted) return;
    }
    if (await _flujo.aplicar(e, usuarioId: usuarioId) && mounted) mostrarAvisoNs(context, 'Factura aplicada');
  }

  Future<void> _deshacer(EstadoFactura e) async {
    final usuarioId = _usuarioId;
    if (usuarioId == null) return;
    final aviso = await _flujo.deshacer(e, usuarioId: usuarioId);
    if (aviso != null && mounted) mostrarAvisoNs(context, aviso);
  }

  /// El producto de la línea: una hoja con buscador entre los productos ofrecidos y "Crear producto" para lo que no está.
  Future<void> _elegirProducto(EstadoFactura e, int linea) async {
    final elegido = await mostrarHojaNs<_EleccionProducto>(
      context,
      builder: (ctx) => _HojaElegirProducto(
        descripcion: e.n.lineas[linea].descripcion,
        candidatos: e.candidatos,
        catalogo: _flujo.catalogo,
        elegido: e.producto[linea],
      ),
    );
    if (elegido == null || !mounted) return;
    switch (elegido) {
      case _Ninguno():
        await _flujo.elegirProducto(e, linea, null);
      case _Producto(:final id):
        await _flujo.elegirProducto(e, linea, id);
      case _Crear():
        await _crearProducto(e, linea);
    }
  }

  /// Alta con el formulario de siempre del celular, precargado con lo leído, en la base del celular (la sync lo lleva a la PC).
  Future<void> _crearProducto(EstadoFactura e, int linea) async {
    final usuarioId = _usuarioId;
    if (usuarioId == null) return;
    final puerto = PuertoLocal(_db);
    final proveedores = await puerto.proveedores();
    final categorias = await puerto.categorias();
    if (!mounted) return;
    final datos = _flujo.datosParaCrear(e, linea);
    int? nuevo;
    await mostrarFormularioProducto(
      context,
      cliente: puerto,
      usuarioId: usuarioId,
      proveedores: proveedores,
      categorias: categorias,
      desdeFactura: ProductoNuevoDesdeFactura(
        nombre: datos.nombre,
        codigoBarras: datos.codigoBarras,
        costoCentavos: datos.costoCentavos,
        proveedorId: e.proveedor?.id,
        mejorarNombre: _flujo.mejorarNombre(e, linea),
        alCrear: (id) => nuevo = id,
      ),
    );
    if (nuevo != null) await _flujo.productoCreado(e, linea, nuevo!);
  }

  Future<void> _elegirProveedor(EstadoFactura e) async {
    final opciones = [...e.delCuit, ..._flujo.proveedores.where((p) => !e.delCuit.any((d) => d.id == p.id))];
    final id = await mostrarHojaNs<int>(
      context,
      builder: (ctx) => HojaNs(
        titulo: '¿De qué proveedor es?',
        texto: e.n.leida.proveedorNombre == null ? null : 'La factura dice: ${e.n.leida.proveedorNombre}',
        bloques: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final p in opciones) ChipNs(texto: p.nombre, activo: e.proveedor?.id == p.id, onTap: () => Navigator.of(ctx).pop(p.id))],
          ),
        ],
      ),
    );
    if (id != null) await _flujo.elegirProveedor(e, id);
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final resultado = _flujo.resultado;
    return PaginaNs(
      titulo: 'Cargar factura',
      cuerpo: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (!ClaveGemini.configurada)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: InfoNs('Para leer facturas cargá la clave de la IA en Más › Configuración › Asistente IA.', tono: TonoNs.warn, icono: IconoNs.alerta),
            ),
          Text('Sacale una foto a cada hoja (o elegí fotos o un PDF). La IA la lee y vos revisás antes de aplicar: stock, costo y deuda.',
              style: estiloNs(15, altura: 1.4, color: ns.mute)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: BotonNs.secundario(context, 'Sacar foto', _flujo.leyendo ? null : _sacarFoto, icono: IconoNs.camara)),
              const SizedBox(width: 8),
              Expanded(child: BotonNs.secundario(context, 'Fotos o PDF', _flujo.leyendo ? null : _elegirArchivos, icono: IconoNs.descarga)),
            ],
          ),
          for (final (i, nombre) in _flujo.nombres.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(child: Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: estiloNs(14, color: ns.ink))),
                  BotonCircularNs(icono: IconoNs.cerrar, onTap: () => _flujo.quitarArchivo(i), etiqueta: 'Quitar $nombre', tamanioIcono: 16),
                ],
              ),
            ),
          if (_flujo.error != null) ...[const SizedBox(height: 10), InfoNs(_flujo.error!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo)],
          if (resultado != null) ...[
            const SizedBox(height: 12),
            Text('Leído con ${resultado.modelo}', style: estiloNs(13, color: ns.mute)),
            for (final a in resultado.lectura.advertencias) Text(a, style: estiloNs(13, color: ns.mute)),
            if (_flujo.facturas.isEmpty) const InfoNs('No encontré ninguna factura en lo que mandaste.'),
            for (final (i, e) in _flujo.facturas.indexed)
              _TarjetaFactura(
                indice: i,
                total: _flujo.facturas.length,
                e: e,
                flujo: _flujo,
                nombres: {for (final c in _flujo.catalogo) c.id: c.nombre},
                onProveedor: () => _elegirProveedor(e),
                onProducto: (linea) => _elegirProducto(e, linea),
                onAplicar: () => _aplicar(e),
                onDeshacer: () => _deshacer(e),
              ),
          ],
          const SizedBox(height: 12),
        ],
      ),
      botones: [
        BotonNs.primario(context, _flujo.leyendo ? 'Leyendo…' : 'Leer con IA', _flujo.puedeLeer ? _flujo.leer : null, habilitado: _flujo.puedeLeer),
      ],
    );
  }
}

class _TarjetaFactura extends StatelessWidget {
  const _TarjetaFactura({
    required this.indice,
    required this.total,
    required this.e,
    required this.flujo,
    required this.nombres,
    required this.onProveedor,
    required this.onProducto,
    required this.onAplicar,
    required this.onDeshacer,
  });

  final int indice;
  final int total;
  final EstadoFactura e;
  final FlujoFactura flujo;
  final Map<int, String> nombres;
  final VoidCallback onProveedor;
  final void Function(int linea) onProducto;
  final VoidCallback onAplicar;
  final VoidCallback onDeshacer;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final f = e.n.leida;
    final control = e.n.control;
    final costos = flujo.costosDe(e)?.$2;
    final resumen = resumenDeVinculos(e.propuestas, e.producto);
    final aplicada = e.facturaAplicadaId != null;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (total > 1) Text('Factura ${indice + 1} de $total', style: estiloNs(13, peso: FontWeight.w600, color: ns.mute)),
          Row(
            children: [
              Expanded(
                child: Text(e.proveedor?.nombre ?? f.proveedorNombre ?? 'Proveedor sin reconocer',
                    style: estiloNs(22, peso: FontWeight.w500, track: -0.02, color: ns.ink)),
              ),
              if (!aplicada) BotonNs(texto: e.proveedor == null ? 'Elegir' : 'Cambiar', onTap: onProveedor, alto: 40, tamanio: 14, fondo: ns.paper, color: ns.ink, rellenar: false, paddingH: 16),
            ],
          ),
          Text(
            [if (f.tipo != null) 'Tipo ${f.tipo}', if (f.numero != null) 'N° ${f.numero}', if (f.fecha != null) '${f.fecha!.day}/${f.fecha!.month}/${f.fecha!.year}', if (f.condicionPago == 'cuenta_corriente') 'Cuenta corriente', if (f.condicionPago == 'contado') 'Contado'].join(' · '),
            style: estiloNs(14, color: ns.mute),
          ),
          if (e.proveedor == null) ...[const SizedBox(height: 8), const InfoNs('Elegí el proveedor: el CUIT de la factura no está cargado en ninguno.', tono: TonoNs.warn)],
          const SizedBox(height: 10),
          FilaClaveValorNs(clave: 'Total impreso', valor: f.pie.totalCentavos == null ? '—' : formatearARS(f.pie.totalCentavos!), tamanioValor: 22),
          if (control != null)
            InfoNs(
              e.n.cierra ? 'Cierra con el total impreso' : 'No cierra: ${formatearARS(control.diferenciaCentavos.abs())} de diferencia. Revisá lo leído.',
              tono: e.n.cierra ? TonoNs.good : TonoNs.bad,
              icono: e.n.cierra ? IconoNs.tilde : IconoNs.alerta,
            ),
          const SizedBox(height: 8),
          Text(
            'Reconocí ${resumen[EstadoDeVinculo.seguro]! + resumen[EstadoDeVinculo.aConfirmar]!} de ${e.n.lineas.length}: '
            '${resumen[EstadoDeVinculo.seguro]} seguras, ${resumen[EstadoDeVinculo.aConfirmar]} para confirmar, ${resumen[EstadoDeVinculo.sinVincular]} sin vincular.',
            style: estiloNs(14, color: ns.mute),
          ),
          if (e.consultandoIa) Text('La IA está buscando los que faltan…', style: estiloNs(14, color: ns.mute)),
          if (e.avisoIa != null) Text(e.avisoIa!, style: estiloNs(13, color: ns.w)),
          if (e.avisoAprendido != null) Text(e.avisoAprendido!, style: estiloNs(13, color: ns.g)),
          for (var i = 0; i < e.n.lineas.length; i++)
            _Linea(
              key: ValueKey('linea-$indice-$i-${e.version}'),
              e: e,
              i: i,
              flujo: flujo,
              nombreProducto: i < e.producto.length && e.producto[i] != null ? nombres[e.producto[i]] : null,
              costoUnitario: costos == null || i >= costos.length ? null : costos[i].costoUnitarioCentavos,
              unidades: costos == null ? null : flujo.costosDe(e)!.$1.lineas[i].unidades,
              onProducto: aplicada ? null : () => onProducto(i),
              bloqueada: aplicada,
            ),
          const SizedBox(height: 12),
          if (!aplicada) ...[
            InterruptorNs(
              etiqueta: 'Sumar al stock',
              descripcion: e.sumarStock ? 'Las unidades entran al stock de cada producto' : 'Solo costo y deuda, el stock no se toca',
              encendido: e.sumarStock,
              onCambio: (v) => flujo.sumarStock(e, v),
            ),
            const SizedBox(height: 8),
            if (e.proveedor != null) BotonNs.secundario(context, 'Aprender estos vínculos', () => flujo.aprender(e), alto: 48, tamanio: 15),
            const SizedBox(height: 8),
            if (e.errorAplicar != null) ...[InfoNs(e.errorAplicar!, tono: TonoNs.bad, icono: IconoNs.alertaCirculo), const SizedBox(height: 8)],
            BotonNs.primario(context, e.aplicando ? 'Aplicando…' : 'Aplicar factura', e.aplicando ? null : onAplicar, habilitado: !e.aplicando),
          ] else ...[
            InfoNs(e.resumenAplicada ?? 'Aplicada', tono: TonoNs.good, icono: IconoNs.tilde),
            const SizedBox(height: 8),
            if (e.errorAplicar != null) ...[InfoNs(e.errorAplicar!, tono: TonoNs.bad), const SizedBox(height: 8)],
            BotonNs.peligroSuave(context, 'Deshacer factura', onDeshacer),
          ],
        ],
      ),
    );
  }
}

/// Una línea de la factura: lo que dice, con qué producto tuyo va, cuántas unidades entran por cantidad y el costo por unidad que queda.
class _Linea extends StatelessWidget {
  const _Linea({
    super.key,
    required this.e,
    required this.i,
    required this.flujo,
    required this.nombreProducto,
    required this.costoUnitario,
    required this.unidades,
    required this.onProducto,
    required this.bloqueada,
  });

  final EstadoFactura e;
  final int i;
  final FlujoFactura flujo;
  final String? nombreProducto;
  final int? costoUnitario;
  final int? unidades;
  final VoidCallback? onProducto;
  final bool bloqueada;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final l = e.n.lineas[i];
    final estado = i < e.propuestas.length ? estadoDeVinculo(e.propuestas[i], i < e.producto.length ? e.producto[i] : null) : EstadoDeVinculo.sinVincular;
    final noVa = i < e.noVa.length && e.noVa[i];
    final (color, fondo) = switch (estado) {
      EstadoDeVinculo.seguro => (ns.g, ns.gbg),
      EstadoDeVinculo.aConfirmar => (ns.w, ns.wbg),
      EstadoDeVinculo.sinVincular => (ns.b, ns.bbg),
    };
    final multiplicador = i < e.multiplicador.length ? e.multiplicador[i] : 1;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: ns.paper, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.descripcion, style: estiloNs(15, peso: FontWeight.w600, color: noVa ? ns.mute : ns.ink)),
          Text('${_cantidad(l.cantidad)} × ${l.precioUnitarioCentavos == null ? '—' : formatearARS(l.precioUnitarioCentavos!)}${l.codigo == null ? '' : ' · cód. ${l.codigo}'}',
              style: estiloNs(13, color: ns.mute)),
          const SizedBox(height: 8),
          if (!noVa)
            PresionNs(
              onTap: onProducto,
              etiqueta: 'Elegir producto',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(999)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(nombreProducto ?? 'Sin vincular · tocá para elegir o crear',
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: estiloNs(15, peso: FontWeight.w500, color: color)),
                    ),
                    if (!bloqueada) IconoNsWidget(IconoNs.chevron, tamanio: 16, color: color, grosor: 2.2),
                  ],
                ),
              ),
            ),
          if (!noVa && !bloqueada) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text('×', style: estiloNs(16, color: ns.mute)),
                const SizedBox(width: 6),
                BotonCircularNs(icono: IconoNs.menos, onTap: () => flujo.cambiarUnidades(e, i, multiplicador - 1), etiqueta: 'Menos unidades por cantidad', tamanioIcono: 16),
                SizedBox(width: 36, child: Text('$multiplicador', textAlign: TextAlign.center, style: estiloNs(17, peso: FontWeight.w600, color: ns.ink))),
                BotonCircularNs(icono: IconoNs.masMas, onTap: () => flujo.cambiarUnidades(e, i, multiplicador + 1), etiqueta: 'Más unidades por cantidad', tamanioIcono: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (unidades != null) Text('$unidades unid.', maxLines: 1, overflow: TextOverflow.ellipsis, style: estiloNs(13, color: ns.mute)),
                      Text(costoUnitario == null ? '—' : '${formatearARS(costoUnitario!)} c/u',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: estiloNs(16, peso: FontWeight.w600, color: ns.ink)),
                    ],
                  ),
                ),
              ],
            ),
          ],
          if (e.motivoUnidades[i] != null && !noVa) ...[const SizedBox(height: 6), Text(e.motivoUnidades[i]!, style: estiloNs(13, altura: 1.3, color: ns.w))],
          if (e.avisosPrecio[i] != null && !noVa) ...[const SizedBox(height: 6), Text(e.avisosPrecio[i]!, style: estiloNs(13, altura: 1.3, color: ns.b))],
          if (!bloqueada)
            Row(
              children: [
                Expanded(child: Text('No es del local (solo entra en la deuda)', style: estiloNs(13, color: ns.mute))),
                Switch(value: noVa, onChanged: (v) => flujo.marcarNoVa(e, i, v)),
              ],
            ),
        ],
      ),
    );
  }
}

sealed class _EleccionProducto {
  const _EleccionProducto();
}

class _Ninguno extends _EleccionProducto {
  const _Ninguno();
}

class _Producto extends _EleccionProducto {
  const _Producto(this.id);
  final int id;
}

class _Crear extends _EleccionProducto {
  const _Crear();
}

/// Elegir el producto de una línea: arranca con los ofrecidos (los del proveedor y las alternativas) y, al escribir, busca en todo el
/// catálogo.
class _HojaElegirProducto extends StatefulWidget {
  const _HojaElegirProducto({required this.descripcion, required this.candidatos, required this.catalogo, required this.elegido});
  final String descripcion;
  final List<ProductoCandidato> candidatos;
  final List<ProductoCandidato> catalogo;
  final int? elegido;

  @override
  State<_HojaElegirProducto> createState() => _HojaElegirProductoState();
}

class _HojaElegirProductoState extends State<_HojaElegirProducto> {
  final _buscar = TextEditingController();

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final texto = claveDeDescripcion(_buscar.text);
    final lista = texto.isEmpty
        ? widget.candidatos
        : [for (final c in widget.catalogo) if (claveDeDescripcion(c.nombre).contains(texto)) c];
    return HojaNs(
      titulo: 'Tu producto',
      texto: 'En la factura: ${widget.descripcion}',
      bloques: [
        CampoNs(etiqueta: 'Buscar', controller: _buscar, placeholder: 'Nombre del producto', onChanged: (_) => setState(() {})),
        for (final c in lista.take(60))
          ChipNs(texto: c.nombre, activo: c.id == widget.elegido, onTap: () => Navigator.of(context).pop(_Producto(c.id))),
        if (lista.isEmpty) Text('Sin coincidencias', style: estiloNs(14, color: ns.mute)),
      ],
      botones: [
        BotonNs.primario(context, 'Crear producto nuevo', () => Navigator.of(context).pop(const _Crear())),
        if (widget.elegido != null) BotonNs.secundario(context, 'Dejar sin vincular', () => Navigator.of(context).pop(const _Ninguno())),
      ],
    );
  }
}

/// "4" y no "4.0"; "1,5" con coma si la factura trae decimales.
String _cantidad(double? c) => c == null ? '—' : c == c.roundToDouble() ? '${c.round()}' : '$c'.replaceAll('.', ',');

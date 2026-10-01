// "Configuración" en la companion (El dueño, 2026-09-19: "que se puedan
// modificar las reglas del negocio... desde el celular") — el contenido
// real de la pantalla "Configuración" del escritorio, no toda la lista de
// CLAUDE.md: recargo de cigarrillos, redondeo, producto de vuelto, markup
// por categoría, medios de pago (renombrar/activar) y usuarios (alta/
// renombrar/activar). Proveedores, categorías nuevas y gastos fijos quedan
// afuera a propósito — son pantallas grandes aparte, con su propia tarea
// futura.
//
// Funciona con o sin PC emparejada (El dueño: "que funcione también sin la
// PC") — `configuracion_negocio_tabla`/`medios_de_pago` ya sincronizan
// (migración v32→v33), así que `ServicioCompanionOffline` no necesita
// ninguna política especial acá, a diferencia de abrir/cerrar caja.
//
// Mismo criterio del resto de la companion: hoja de vidrio para cada
// edición chica, nunca una pantalla nueva para un formulario de un par de
// campos.

import 'package:flutter/material.dart';

import '../domain/dinero.dart';
import '../ui/comun/campo_texto.dart';
import '../ui/tema/tokens.dart';
import 'aviso_modo_local.dart';
import 'base_local.dart';
import 'cliente_companion.dart';
import 'debounce.dart';
import 'emparejamiento.dart';
import 'mensaje_error.dart';
import 'puerto_local.dart';
import 'seleccion_servicio.dart';
import 'servicio_companion.dart';
import 'servicio_companion_offline.dart';
import 'tema/esqueleto_companion.dart';
import 'tema/estado_error_companion.dart';
import 'tema/fila_dato_companion.dart';
import 'tema/hoja_vidrio.dart';
import 'tema/presionable.dart';
import '../ui/tema/iconos.dart';

class PantallaConfiguracionCompanion extends StatefulWidget {
  const PantallaConfiguracionCompanion({super.key});

  @override
  State<PantallaConfiguracionCompanion> createState() => _PantallaConfiguracionCompanionState();
}

class _PantallaConfiguracionCompanionState extends State<PantallaConfiguracionCompanion> {
  ServicioCompanion? _servicio;
  bool _pcEmparejada = false;

  ConfiguracionNegocioCompanion? _config;
  List<CategoriaCompanion> _categorias = [];
  List<MedioDePagoCompanion> _mediosPago = [];
  List<UsuarioCompanion> _usuarios = [];

  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final conexion = await leerConexion();
      final servicio = conexion == null
          ? ServicioCompanionOffline(PuertoLocal(baseLocalCompanion()))
          : await resolverServicioCompanion(conexion);
      final resultados = await Future.wait([
        servicio.configuracionNegocio(),
        servicio.categorias(),
        servicio.mediosDePago(),
        servicio.usuarios(),
      ]);
      if (mounted) {
        setState(() {
          _servicio = servicio;
          _pcEmparejada = conexion != null;
          _config = resultados[0] as ConfiguracionNegocioCompanion;
          _categorias = resultados[1] as List<CategoriaCompanion>;
          _mediosPago = resultados[2] as List<MedioDePagoCompanion>;
          _usuarios = resultados[3] as List<UsuarioCompanion>;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: SafeArea(
        child: _cargando
            ? const EsqueletoLista()
            : _error != null
            ? EstadoErrorCompanion(mensaje: _error!, onReintentar: _cargar)
            : _contenido(context),
      ),
    );
  }

  Widget _contenido(BuildContext context) {
    final config = _config!;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.only(bottom: Espaciado.xxl),
        children: [
          AvisoModoLocal(servicio: _servicio, pcEmparejada: _pcEmparejada),
          _tituloSeccion(context, 'Recargo de cigarrillos'),
          FilaDatoCompanion(
            etiqueta: 'Primer atado / adicional / suelto',
            valor:
                '${formatearARS(config.recargoPrimerAtadoCentavos)} / '
                '${formatearARS(config.recargoAtadoAdicionalCentavos)} / '
                '${formatearARS(config.recargoSueltoCentavos)}',
            onTap: _editarRecargo,
          ),
          _tituloSeccion(context, 'Caja'),
          FilaDatoCompanion(
            etiqueta: 'Redondeo en efectivo',
            valor: formatearARS(config.pasoRedondeoCentavos),
            onTap: _editarRedondeo,
          ),
          FilaDatoCompanion(
            etiqueta: 'Producto de vuelto',
            valor: config.productoVueltoId == null ? 'Sin configurar' : 'Configurado',
            onTap: _elegirProductoVuelto,
          ),
          _tituloSeccion(context, 'Categorías (ganancia de referencia)'),
          for (final c in _categorias)
            FilaDatoCompanion(
              etiqueta: c.nombre,
              valor: '${c.markupDefaultBp ~/ 100}%',
              onTap: () => _editarMarkup(c),
            ),
          _tituloSeccion(context, 'Medios de pago'),
          for (final m in _mediosPago)
            FilaDatoCompanion(
              etiqueta: m.nombre,
              valor: m.activo ? 'Activo' : 'Inactivo',
              destacado: !m.activo,
              onTap: () => _editarMedioPago(m),
            ),
          _tituloSeccion(context, 'Usuarios'),
          for (final u in _usuarios)
            FilaDatoCompanion(
              etiqueta: u.nombre,
              valor: u.activo ? 'Activo' : 'Inactivo',
              destacado: !u.activo,
              onTap: () => _editarUsuario(u),
            ),
          Padding(
            padding: const EdgeInsets.all(Espaciado.lg),
            child: OutlinedButton.icon(
              onPressed: _agregarUsuario,
              icon: const Icon(IconosPlazoleta.add),
              label: const Text('Agregar usuario'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tituloSeccion(BuildContext context, String texto) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Espaciado.lg, Espaciado.xl, Espaciado.lg, Espaciado.sm),
      child: Text(texto, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Future<void> _editarRecargo() async {
    final config = _config!;
    final guardado = await mostrarHojaVidrio<bool>(
      context,
      builder: (_) => _HojaRecargoCigarrillos(servicio: _servicio!, config: config),
    );
    if (guardado == true) await _cargar();
  }

  Future<void> _editarRedondeo() async {
    final config = _config!;
    final ctrl = TextEditingController(
      text: formatearARS(config.pasoRedondeoCentavos, conSigno: false),
    );
    final guardado = await mostrarHojaVidrio<bool>(
      context,
      builder: (context) => _HojaUnMonto(
        titulo: 'Redondeo en efectivo',
        controller: ctrl,
        onGuardar: (monto) => _servicio!.actualizarPasoRedondeo(monto),
      ),
    );
    if (guardado == true) await _cargar();
  }

  Future<void> _elegirProductoVuelto() async {
    final elegido = await mostrarHojaVidrio<ProductoCompanion?>(
      context,
      builder: (_) => _HojaElegirProductoVuelto(servicio: _servicio!),
    );
    if (elegido == null) return;
    await _servicio!.actualizarProductoVuelto(elegido.id == 0 ? null : elegido.id);
    await _cargar();
  }

  Future<void> _editarMarkup(CategoriaCompanion categoria) async {
    final ctrl = TextEditingController(text: (categoria.markupDefaultBp ~/ 100).toString());
    final guardado = await mostrarHojaVidrio<bool>(
      context,
      builder: (context) => _HojaTextoSimple(
        titulo: categoria.nombre,
        etiqueta: 'Ganancia de referencia sobre el precio (%)',
        controller: ctrl,
        keyboardType: TextInputType.number,
        onGuardar: (texto) async {
          final pct = int.tryParse(texto.trim());
          if (pct == null || pct < 0 || pct >= 100) throw const FormatException('Escribí un número entero, de 0 a 99');
          await _servicio!.actualizarMarkupCategoria(categoria.id, pct * 100);
        },
      ),
    );
    if (guardado == true) await _cargar();
  }

  Future<void> _editarMedioPago(MedioDePagoCompanion medio) async {
    final guardado = await mostrarHojaVidrio<bool>(
      context,
      builder: (_) => _HojaMedioPago(servicio: _servicio!, medio: medio),
    );
    if (guardado == true) await _cargar();
  }

  Future<void> _editarUsuario(UsuarioCompanion usuario) async {
    final guardado = await mostrarHojaVidrio<bool>(
      context,
      builder: (_) => _HojaUsuario(servicio: _servicio!, usuario: usuario),
    );
    if (guardado == true) await _cargar();
  }

  Future<void> _agregarUsuario() async {
    final ctrl = TextEditingController();
    final guardado = await mostrarHojaVidrio<bool>(
      context,
      builder: (context) => _HojaTextoSimple(
        titulo: 'Agregar usuario',
        etiqueta: 'Nombre',
        controller: ctrl,
        onGuardar: (texto) async {
          if (texto.trim().isEmpty) throw const FormatException('Escribí un nombre');
          await _servicio!.crearUsuarioNuevo(texto.trim());
        },
      ),
    );
    if (guardado == true) await _cargar();
  }
}

/// Molde compartido por las hojas de edición de acá abajo: título, un
/// mensaje de error si `onGuardar` tira, y el botón "Guardar" con su
/// spinner mientras corre.
class _HojaAccion extends StatefulWidget {
  const _HojaAccion({required this.titulo, required this.child, required this.onGuardar});

  final String titulo;
  final Widget child;
  final Future<void> Function() onGuardar;

  @override
  State<_HojaAccion> createState() => _HojaAccionState();
}

class _HojaAccionState extends State<_HojaAccion> {
  bool _guardando = false;
  String? _error;

  Future<void> _guardar() async {
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.onGuardar();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = e is FormatException ? e.message : mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.titulo, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: Espaciado.lg),
        widget.child,
        if (_error != null) ...[
          const SizedBox(height: Espaciado.sm),
          Text(_error!, style: TextStyle(color: context.colores.error)),
        ],
        const SizedBox(height: Espaciado.lg),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

class _HojaUnMonto extends StatelessWidget {
  const _HojaUnMonto({required this.titulo, required this.controller, required this.onGuardar});

  final String titulo;
  final TextEditingController controller;
  final Future<void> Function(int montoCentavos) onGuardar;

  @override
  Widget build(BuildContext context) {
    return _HojaAccion(
      titulo: titulo,
      onGuardar: () async {
        final int monto;
        try {
          monto = parsearARS(controller.text);
        } on FormatException {
          throw const FormatException('Monto inválido');
        }
        await onGuardar(monto);
      },
      child: CampoPlata(controller: controller, autofocus: true, etiqueta: 'Monto'),
    );
  }
}

class _HojaTextoSimple extends StatelessWidget {
  const _HojaTextoSimple({
    required this.titulo,
    required this.etiqueta,
    required this.controller,
    required this.onGuardar,
    this.keyboardType,
  });

  final String titulo;
  final String etiqueta;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final Future<void> Function(String texto) onGuardar;

  @override
  Widget build(BuildContext context) {
    return _HojaAccion(
      titulo: titulo,
      onGuardar: () => onGuardar(controller.text),
      child: CampoTexto(
        controller: controller,
        autofocus: true,
        etiqueta: etiqueta,
        keyboardType: keyboardType,
      ),
    );
  }
}

class _HojaRecargoCigarrillos extends StatefulWidget {
  const _HojaRecargoCigarrillos({required this.servicio, required this.config});

  final ServicioCompanion servicio;
  final ConfiguracionNegocioCompanion config;

  @override
  State<_HojaRecargoCigarrillos> createState() => _HojaRecargoCigarrillosState();
}

class _HojaRecargoCigarrillosState extends State<_HojaRecargoCigarrillos> {
  late final _primerAtadoCtrl = TextEditingController(
    text: formatearARS(widget.config.recargoPrimerAtadoCentavos, conSigno: false),
  );
  late final _atadoAdicionalCtrl = TextEditingController(
    text: formatearARS(widget.config.recargoAtadoAdicionalCentavos, conSigno: false),
  );
  late final _sueltoCtrl = TextEditingController(
    text: formatearARS(widget.config.recargoSueltoCentavos, conSigno: false),
  );

  @override
  void dispose() {
    _primerAtadoCtrl.dispose();
    _atadoAdicionalCtrl.dispose();
    _sueltoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _HojaAccion(
      titulo: 'Recargo de cigarrillos',
      onGuardar: () async {
        final int primerAtado, atadoAdicional, suelto;
        try {
          primerAtado = parsearARS(_primerAtadoCtrl.text);
          atadoAdicional = parsearARS(_atadoAdicionalCtrl.text);
          suelto = parsearARS(_sueltoCtrl.text);
        } on FormatException {
          throw const FormatException('Revisá los montos');
        }
        await widget.servicio.actualizarRecargoCigarrillos(
          primerAtadoCentavos: primerAtado,
          atadoAdicionalCentavos: atadoAdicional,
          sueltoCentavos: suelto,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CampoPlata(controller: _primerAtadoCtrl, autofocus: true, etiqueta: 'Primer atado'),
          const SizedBox(height: Espaciado.md),
          CampoPlata(controller: _atadoAdicionalCtrl, etiqueta: 'Atado adicional'),
          const SizedBox(height: Espaciado.md),
          CampoPlata(controller: _sueltoCtrl, etiqueta: 'Cigarrillo suelto'),
        ],
      ),
    );
  }
}

class _HojaMedioPago extends StatefulWidget {
  const _HojaMedioPago({required this.servicio, required this.medio});

  final ServicioCompanion servicio;
  final MedioDePagoCompanion medio;

  @override
  State<_HojaMedioPago> createState() => _HojaMedioPagoState();
}

class _HojaMedioPagoState extends State<_HojaMedioPago> {
  late final _nombreCtrl = TextEditingController(text: widget.medio.nombre);
  late bool _activo = widget.medio.activo;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _HojaAccion(
      titulo: widget.medio.nombre,
      onGuardar: () async {
        if (_nombreCtrl.text.trim().isEmpty) throw const FormatException('Escribí un nombre');
        if (_nombreCtrl.text.trim() != widget.medio.nombre) {
          await widget.servicio.renombrarMedioPago(widget.medio.id, _nombreCtrl.text.trim());
        }
        if (_activo != widget.medio.activo) {
          await widget.servicio.alternarActivoMedioPago(widget.medio.id, _activo);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CampoTexto(controller: _nombreCtrl, autofocus: true, etiqueta: 'Nombre'),
          const SizedBox(height: Espaciado.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Activo'),
            value: _activo,
            onChanged: (v) => setState(() => _activo = v),
          ),
        ],
      ),
    );
  }
}

class _HojaUsuario extends StatefulWidget {
  const _HojaUsuario({required this.servicio, required this.usuario});

  final ServicioCompanion servicio;
  final UsuarioCompanion usuario;

  @override
  State<_HojaUsuario> createState() => _HojaUsuarioState();
}

class _HojaUsuarioState extends State<_HojaUsuario> {
  late final _nombreCtrl = TextEditingController(text: widget.usuario.nombre);
  late bool _activo = widget.usuario.activo;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _HojaAccion(
      titulo: widget.usuario.nombre,
      onGuardar: () async {
        if (_nombreCtrl.text.trim().isEmpty) throw const FormatException('Escribí un nombre');
        if (_nombreCtrl.text.trim() != widget.usuario.nombre) {
          await widget.servicio.renombrarUsuarioExistente(widget.usuario.id, _nombreCtrl.text.trim());
        }
        if (_activo != widget.usuario.activo) {
          await widget.servicio.alternarActivoUsuarioExistente(widget.usuario.id, _activo);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CampoTexto(controller: _nombreCtrl, autofocus: true, etiqueta: 'Nombre'),
          const SizedBox(height: Espaciado.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Activo'),
            value: _activo,
            onChanged: (v) => setState(() => _activo = v),
          ),
        ],
      ),
    );
  }
}

/// Buscador chico para elegir el producto del botón de vuelto — mismo
/// criterio que `_HojaElegirProveedor` de `pantalla_precios.dart`, pero con
/// búsqueda en vivo (el catálogo entero no se trae de una). Devuelve un
/// `ProductoCompanion` con `id == 0` para "Sin configurar" (limpiar el
/// producto elegido) — nunca null, eso significa "se canceló sin elegir".
class _HojaElegirProductoVuelto extends StatefulWidget {
  const _HojaElegirProductoVuelto({required this.servicio});

  final ServicioCompanion servicio;

  @override
  State<_HojaElegirProductoVuelto> createState() => _HojaElegirProductoVueltoState();
}

class _HojaElegirProductoVueltoState extends State<_HojaElegirProductoVuelto> {
  final _busquedaCtrl = TextEditingController();
  final _debouncer = Debouncer();
  List<ProductoCompanion> _resultados = [];
  bool _buscando = false;

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  void _alCambiarTexto(String texto) {
    if (texto.trim().isEmpty) {
      setState(() => _resultados = []);
      return;
    }
    _debouncer.ejecutar(() => _buscar(texto));
  }

  Future<void> _buscar(String texto) async {
    setState(() => _buscando = true);
    try {
      final resultados = await widget.servicio.productos(busqueda: texto);
      if (mounted && _busquedaCtrl.text == texto) setState(() => _resultados = resultados);
    } catch (_) {
      // Silencioso: mismo criterio que el resto de los buscadores chicos.
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Producto de vuelto', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: Espaciado.md),
        CampoTexto(
          controller: _busquedaCtrl,
          autofocus: true,
          etiqueta: 'Buscar producto',
          onChanged: _alCambiarTexto,
        ),
        const SizedBox(height: Espaciado.sm),
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            const ProductoCompanion(id: 0, nombre: '', esPesable: false, activo: true, stock: 0),
          ),
          child: const Text('Quitar producto de vuelto'),
        ),
        if (_buscando) const LinearProgressIndicator(),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _resultados.length,
            itemBuilder: (context, i) {
              final p = _resultados[i];
              return Presionable(
                onTap: () => Navigator.of(context).pop(p),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Espaciado.sm),
                  child: Text(p.nombre, style: Theme.of(context).textTheme.titleMedium),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

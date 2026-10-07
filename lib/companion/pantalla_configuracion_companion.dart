// "Configuración" en la companion (El dueño, 2026-09-19: "que se puedan
// modificar las reglas del negocio... desde el celular") — el contenido
// real de la pantalla "Configuración" del escritorio, no toda la lista de
// CLAUDE.md: recargo de cigarrillos, redondeo, producto de vuelto, markup
// por categoría, medios de pago (renombrar/activar) y usuarios (alta/
// renombrar/activar). Proveedores, categorías nuevas y gastos fijos quedan
// afuera a propósito — son pantallas grandes aparte, con su propia tarea
// futura.
//
// Mock completo del celular (2026-10-02): se edita en la misma página y un
// solo "Guardar" aplica lo cambiado. Nada se escribe hasta tocarlo, y lo
// pendiente se ve en su lugar (sobre lo ya guardado) aunque una hoja de
// renombrar recargue la pantalla. Cada cambio usa el mismo método de servicio
// de antes, así que las validaciones y el rastro no cambian.
//
// Funciona con o sin PC emparejada (El dueño: "que funcione también sin la
// PC") — `configuracion_negocio_tabla`/`medios_de_pago` ya sincronizan
// (migración v32→v33), así que `ServicioCompanionOffline` no necesita
// ninguna política especial acá, a diferencia de abrir/cerrar caja.

import 'package:flutter/material.dart';

import '../domain/dinero.dart';
import '../servicios/gemini.dart';
import '../ui/comun/campo_texto.dart';
import '../ui/tema/tokens.dart';
import 'aviso_modo_local.dart';
import 'base_local.dart';
import 'cliente_companion.dart';
import 'kit/kit_ns.dart';
import 'debounce.dart';
import 'emparejamiento.dart';
import 'mensaje_error.dart';
import 'navegacion.dart';
import 'puerto_local.dart';
import 'seleccion_servicio.dart';
import 'servicio_companion.dart';
import 'servicio_companion_offline.dart';
import 'tema/hoja_vidrio.dart';
import 'tema/presionable.dart';
import 'tema/error_en_linea.dart';

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

  /// Nombre del producto de vuelto ya guardado (la configuración solo trae su id).
  String? _nombreVueltoGuardado;

  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  // ---- Cambios pendientes: viven por encima de lo guardado ----
  int? _pasoPendiente;
  ({int? id, String? nombre})? _vueltoPendiente;
  final Map<int, bool> _mediosPendientes = {};
  final Map<int, bool> _usuariosPendientes = {};
  final Map<int, int> _markupPendiente = {};

  final _primerAtadoCtrl = TextEditingController();
  final _atadoAdicionalCtrl = TextEditingController();
  final _sueltoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // La clave de la IA del negocio pudo cambiar desde otro equipo.
    ClaveGemini.refrescarCuenta().then((_) {
      if (mounted) setState(() {});
    });
    for (final c in [_primerAtadoCtrl, _atadoAdicionalCtrl, _sueltoCtrl]) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
    _cargar();
  }

  @override
  void dispose() {
    _primerAtadoCtrl.dispose();
    _atadoAdicionalCtrl.dispose();
    _sueltoCtrl.dispose();
    super.dispose();
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
      final config = resultados[0] as ConfiguracionNegocioCompanion;
      String? nombreVuelto;
      if (config.productoVueltoId != null) {
        final productos = await servicio.productos();
        nombreVuelto = productos.where((p) => p.id == config.productoVueltoId).firstOrNull?.nombre;
      }
      if (mounted) {
        // Los campos de recargo solo se pisan si no hay nada tipeado a medias.
        final recargoSinCambios = !_recargoCambio;
        setState(() {
          _servicio = servicio;
          _pcEmparejada = conexion != null;
          _config = config;
          _categorias = resultados[1] as List<CategoriaCompanion>;
          _mediosPago = resultados[2] as List<MedioDePagoCompanion>;
          _usuarios = resultados[3] as List<UsuarioCompanion>;
          _nombreVueltoGuardado = nombreVuelto;
        });
        if (recargoSinCambios || _primerAtadoCtrl.text.isEmpty) _cargarCamposRecargo(config);
      }
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _cargarCamposRecargo(ConfiguracionNegocioCompanion c) {
    _primerAtadoCtrl.text = formatearARS(c.recargoPrimerAtadoCentavos, conSigno: false);
    _atadoAdicionalCtrl.text = formatearARS(c.recargoAtadoAdicionalCentavos, conSigno: false);
    _sueltoCtrl.text = formatearARS(c.recargoSueltoCentavos, conSigno: false);
  }

  // ---- Valores efectivos (pendiente sobre guardado) y qué cambió ----

  int get _paso => _pasoPendiente ?? _config!.pasoRedondeoCentavos;

  bool _medioActivo(MedioDePagoCompanion m) => _mediosPendientes[m.id] ?? m.activo;
  bool _usuarioActivo(UsuarioCompanion u) => _usuariosPendientes[u.id] ?? u.activo;
  int _markup(CategoriaCompanion c) => _markupPendiente[c.id] ?? c.markupDefaultBp ~/ 100;

  /// Los tres montos del recargo, o null si alguno no se entiende todavía.
  ({int primer, int adicional, int suelto})? get _recargoTipeado {
    try {
      return (
        primer: parsearARS(_primerAtadoCtrl.text),
        adicional: parsearARS(_atadoAdicionalCtrl.text),
        suelto: parsearARS(_sueltoCtrl.text),
      );
    } on FormatException {
      return null;
    }
  }

  bool get _recargoCambio {
    final c = _config;
    if (c == null) return false;
    final t = _recargoTipeado;
    if (t == null) return true; // algo escrito que no se entiende cuenta como cambio
    return t.primer != c.recargoPrimerAtadoCentavos || t.adicional != c.recargoAtadoAdicionalCentavos || t.suelto != c.recargoSueltoCentavos;
  }

  bool get _vueltoCambio => _vueltoPendiente != null && _vueltoPendiente!.id != _config?.productoVueltoId;

  bool get _hayCambios {
    final c = _config;
    if (c == null) return false;
    return (_pasoPendiente != null && _pasoPendiente != c.pasoRedondeoCentavos) ||
        _recargoCambio ||
        _vueltoCambio ||
        _mediosPago.any((m) => _medioActivo(m) != m.activo) ||
        _usuarios.any((u) => _usuarioActivo(u) != u.activo) ||
        _categorias.any((x) => _markup(x) != x.markupDefaultBp ~/ 100);
  }

  /// Aplica solo lo que cambió, con los mismos métodos de servicio de siempre.
  /// Un error en una parte no frena las demás: se informan todas juntas y lo
  /// que falló queda pendiente para reintentar.
  Future<void> _guardar() async {
    final servicio = _servicio!;
    final config = _config!;
    setState(() {
      _guardando = true;
      _error = null;
    });
    final errores = <String>[];
    Future<void> intentar(String que, Future<void> Function() accion, VoidCallback alOk) async {
      try {
        await accion();
        alOk();
      } on FormatException catch (e) {
        errores.add('$que: ${e.message}');
      } catch (e) {
        errores.add('$que: ${mensajeDeError(e)}');
      }
    }

    if (_pasoPendiente != null && _pasoPendiente != config.pasoRedondeoCentavos) {
      await intentar('Redondeo', () => servicio.actualizarPasoRedondeo(_pasoPendiente!), () => _pasoPendiente = null);
    }
    if (_recargoCambio) {
      final t = _recargoTipeado;
      if (t == null) {
        errores.add('Recargo de cigarrillos: revisá los montos');
      } else {
        await intentar(
          'Recargo de cigarrillos',
          () => servicio.actualizarRecargoCigarrillos(primerAtadoCentavos: t.primer, atadoAdicionalCentavos: t.adicional, sueltoCentavos: t.suelto),
          () {},
        );
      }
    }
    if (_vueltoCambio) {
      await intentar('Producto de vuelto', () => servicio.actualizarProductoVuelto(_vueltoPendiente!.id), () => _vueltoPendiente = null);
    }
    for (final m in _mediosPago.where((m) => _medioActivo(m) != m.activo)) {
      await intentar(m.nombre, () => servicio.alternarActivoMedioPago(m.id, _medioActivo(m)), () => _mediosPendientes.remove(m.id));
    }
    for (final x in _categorias.where((x) => _markup(x) != x.markupDefaultBp ~/ 100)) {
      await intentar(x.nombre, () => servicio.actualizarMarkupCategoria(x.id, _markup(x) * 100), () => _markupPendiente.remove(x.id));
    }
    for (final u in _usuarios.where((u) => _usuarioActivo(u) != u.activo)) {
      await intentar(u.nombre, () => servicio.alternarActivoUsuarioExistente(u.id, _usuarioActivo(u)), () => _usuariosPendientes.remove(u.id));
    }

    if (!mounted) return;
    setState(() => _guardando = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(errores.isEmpty ? 'Configuración guardada' : 'No se pudo guardar todo — ${errores.join('; ')}')),
    );
    // Recarga lo guardado para que lo pendiente que ya coincide deje de contar como cambio.
    await _cargar();
  }

  Future<void> _volver() async {
    if (!_hayCambios || await confirmarSalirSinGuardar(context)) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  // ---- Interfaz ----

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _volver();
      },
      child: Scaffold(
        backgroundColor: ns.paper,
        body: SafeArea(
          child: PantallaEntradaNs(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CabeceraSubNs(titulo: 'Configuración', tamanio: 32, onVolver: _volver),
                  const SizedBox(height: 14),
                  Expanded(
                    child: _cargando && _config == null
                        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                        : _error != null && _config == null
                        ? Column(children: [InfoNs(_error!, tono: TonoNs.bad), const SizedBox(height: 10), BotonNs.secundario(context, 'Reintentar', _cargar)])
                        : _contenido(context),
                  ),
                  const SizedBox(height: 14),
                  if (_error != null && _config != null) ...[InfoNs(_error!, tono: TonoNs.bad), const SizedBox(height: 10)],
                  _pie(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "Guardar configuración" (60): apagado hasta que haya algo para guardar.
  Widget _pie(BuildContext context) {
    final ns = context.ns;
    final activo = _hayCambios && !_guardando;
    return BotonNs(
      texto: _guardando ? 'Guardando…' : 'Guardar configuración',
      onTap: activo ? _guardar : null,
      alto: 60,
      tamanio: 17,
      fondo: activo ? ns.prim : ns.s,
      color: activo ? TokensNs.blanco : ns.mute,
      habilitado: activo,
    );
  }

  Widget _seccion(String texto) => Padding(padding: const EdgeInsets.only(top: 22, bottom: 10), child: SeccionNs(texto));

  Widget _contenido(BuildContext context) {
    final ns = context.ns;
    final paso = _paso;
    // Un paso que no es de los tres habituales (ej. $200) se muestra como una
    // opción más, elegida, para no esconder lo que ya hay configurado.
    final pasosHabituales = [0, 5000, 10000];
    final opcionesPaso = [...pasosHabituales, if (!pasosHabituales.contains(paso)) paso]..sort();
    return RefreshIndicator(
      onRefresh: _cargar,
      color: ns.ink,
      backgroundColor: ns.paper,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          AvisoModoLocal(servicio: _servicio, pcEmparejada: _pcEmparejada),
          // Las secciones del mock (docs/03 D5).
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SeccionNs('Cobro'),
                const SizedBox(height: 10),
                Text('Redondear el efectivo', style: estiloNs(14, peso: FontWeight.w600, color: ns.mute)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final o in opcionesPaso) ChipNs(texto: o == 0 ? 'Sin redondeo' : plataNs(o), activo: paso == o, onTap: () => setState(() => _pasoPendiente = o)),
                    ChipNs(texto: 'Otro…', activo: false, onTap: _otroRedondeo),
                  ],
                ),
              ],
            ),
          ),
          _seccion('Recargo de cigarrillos'),
          _campoMonto(_primerAtadoCtrl, 'Primer atado'),
          _campoMonto(_atadoAdicionalCtrl, 'Atado adicional'),
          _campoMonto(_sueltoCtrl, 'Cigarrillo suelto'),
          _seccion('Producto para dar de vuelto'),
          _filaVuelto(context),
          _seccion('Formas de cobro que aceptás'),
          for (final m in _mediosPago)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onLongPress: () => _renombrarMedio(m),
                child: InterruptorNs(etiqueta: m.nombre, descripcion: _medioActivo(m) ? 'Activo' : 'Inactivo', encendido: _medioActivo(m), onCambio: (v) => setState(() => v == m.activo ? _mediosPendientes.remove(m.id) : _mediosPendientes[m.id] = v)),
              ),
            ),
          _seccion('Ganancia que esperás por categoría'),
          Text('Sobre el precio de venta', style: estiloNs(14, color: ns.mute)),
          const SizedBox(height: 10),
          for (final c in _categorias)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FilaPorcentaje(nombre: c.nombre, porcentaje: _markup(c), onMenos: () => _cambiarMarkup(c, -5), onMas: () => _cambiarMarkup(c, 5)),
            ),
          _seccion('Quiénes usan la app'),
          for (final u in _usuarios)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onLongPress: () => _renombrarUsuario(u),
                child: InterruptorNs(etiqueta: u.nombre, descripcion: _usuarioActivo(u) ? 'Activo' : 'Inactivo', encendido: _usuarioActivo(u), onCambio: (v) => setState(() => v == u.activo ? _usuariosPendientes.remove(u.id) : _usuariosPendientes[u.id] = v)),
              ),
            ),
          const SizedBox(height: 2),
          BotonNs.secundario(context, '+ Agregar usuario', _agregarUsuario),
          _seccion('Asistente IA'),
          _filaClaveIa(context),
          if (ClaveGemini.configurada) ...[
            const SizedBox(height: 8),
            _filaModeloIa(context),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// Un monto en pesos con su etiqueta; se interpreta con `parsearARS` al guardar (acepta "1.200" y "1200,50").
  Widget _campoMonto(TextEditingController ctrl, String etiqueta) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: CampoNs(etiqueta: etiqueta, controller: ctrl, placeholder: '\$ 0', teclado: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {})),
  );

  /// "Producto para dar de vuelto": nombre, "Se usa cuando falta cambio" y Quitar/Elegir.
  Widget _filaVuelto(BuildContext context) {
    final ns = context.ns;
    final pend = _vueltoPendiente;
    final id = pend != null ? pend.id : _config!.productoVueltoId;
    final nombre = pend != null ? pend.nombre : _nombreVueltoGuardado;
    final configurado = id != null;
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.fromLTRB(22, 10, 12, 10),
      decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(configurado ? (nombre ?? 'Producto configurado') : 'Sin configurar', style: estiloNs(17, peso: FontWeight.w500, track: -0.02, color: ns.ink)),
                Text(configurado ? 'Se usa cuando falta cambio' : 'Elegí un producto', style: estiloNs(14, color: ns.mute)),
              ],
            ),
          ),
          BotonNs(
            texto: configurado ? 'Quitar' : 'Elegir',
            onTap: configurado ? () => setState(() => _vueltoPendiente = (id: null, nombre: null)) : _elegirProductoVuelto,
            alto: 44,
            tamanio: 14,
            fondo: ns.paper,
            color: ns.ink,
            rellenar: false,
            paddingH: 18,
          ),
        ],
      ),
    );
  }

  /// La clave de Google (Gemini): la del negocio, guardada en la cuenta (El dueño, 2026-10-07: "la clave es por cuenta"), o una de
  /// este celular si no está vinculado. Mismo guardado y mismas pruebas que la PC (`probarYGuardarClave`); un empleado con la clave del
  /// negocio no tiene nada que cargar.
  Widget _filaClaveIa(BuildContext context) {
    final ns = context.ns;
    final configurada = ClaveGemini.configurada;
    final puedeCargar = !ClaveGemini.enCuenta || ClaveGemini.puedeCambiarEnCuenta;
    final detalle = ClaveGemini.enCuenta
        ? (ClaveGemini.puedeCambiarEnCuenta ? 'Clave del negocio: la usan todos tus equipos' : 'Usa la clave del negocio (la carga el dueño)')
        : configurada
            ? 'Clave cargada en este celular'
            : ClaveGemini.puedeCambiarEnCuenta
                ? 'Sin clave: cargala una vez y la usan todos tus equipos'
                : 'Sin clave — es gratis en aistudio.google.com/apikey';
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.fromLTRB(22, 10, 12, 10),
      decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('IA de Google (Gemini)', style: estiloNs(17, peso: FontWeight.w500, track: -0.02, color: ns.ink)),
                Text(detalle, style: estiloNs(14, color: ns.mute)),
              ],
            ),
          ),
          if (puedeCargar)
            BotonNs(
              texto: configurada ? 'Cambiar' : 'Cargar',
              onTap: _cargarClaveIa,
              alto: 44,
              tamanio: 14,
              fondo: ns.paper,
              color: ns.ink,
              rellenar: false,
              paddingH: 18,
            ),
        ],
      ),
    );
  }

  /// Con qué modelo de Google consulta este celular (por defecto el más barato). Se guarda al elegir; la clave no se toca.
  Widget _filaModeloIa(BuildContext context) {
    final ns = context.ns;
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.fromLTRB(22, 10, 12, 10),
      decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Modelo de la IA', style: estiloNs(17, peso: FontWeight.w500, track: -0.02, color: ns.ink)),
                Text(ClaveGemini.modelo ?? modeloGeminiPorDefecto, style: estiloNs(14, color: ns.mute)),
              ],
            ),
          ),
          BotonNs(texto: 'Elegir', onTap: _elegirModeloIa, alto: 44, tamanio: 14, fondo: ns.paper, color: ns.ink, rellenar: false, paddingH: 18),
        ],
      ),
    );
  }

  Future<void> _elegirModeloIa() async {
    await mostrarHojaVidrio<bool>(context, builder: (_) => const _HojaModeloIa());
    if (mounted) setState(() {});
  }

  Future<void> _cargarClaveIa() async {
    final ctrl = TextEditingController(text: ClaveGemini.valor ?? '');
    await mostrarHojaVidrio<bool>(
      context,
      builder: (context) => _HojaAccion(
        titulo: 'Clave de la IA de Google',
        onGuardar: () async {
          final motivo = await probarYGuardarClave(ctrl.text);
          // `_HojaAccion` muestra el motivo y deja la hoja abierta; la clave rota no se guarda.
          if (motivo != null) throw FormatException(motivo);
        },
        child: CampoTexto(controller: ctrl, autofocus: true, etiqueta: 'Clave de API', obscureText: true),
      ),
    );
    ctrl.dispose();
    if (mounted) setState(() {});
  }

  void _cambiarMarkup(CategoriaCompanion c, int delta) {
    final nuevo = (_markup(c) + delta).clamp(0, 99);
    setState(() => nuevo == c.markupDefaultBp ~/ 100 ? _markupPendiente.remove(c.id) : _markupPendiente[c.id] = nuevo);
  }

  Future<void> _otroRedondeo() async {
    final ctrl = TextEditingController(text: formatearARS(_paso, conSigno: false));
    await mostrarHojaVidrio<bool>(
      context,
      builder: (context) => _HojaUnMonto(
        titulo: 'Redondeo en efectivo',
        controller: ctrl,
        onGuardar: (monto) async {
          if (mounted) setState(() => _pasoPendiente = monto);
        },
      ),
    );
    ctrl.dispose();
  }

  Future<void> _elegirProductoVuelto() async {
    final elegido = await mostrarHojaVidrio<ProductoCompanion?>(
      context,
      builder: (_) => _HojaElegirProductoVuelto(servicio: _servicio!),
    );
    if (elegido == null) return;
    setState(() => _vueltoPendiente = elegido.id == 0 ? (id: null, nombre: null) : (id: elegido.id, nombre: elegido.nombre));
  }

  /// Renombrar sí se aplica al momento: es una edición de nombre, no un ajuste de reglas.
  Future<void> _renombrarMedio(MedioDePagoCompanion medio) async {
    final guardado = await mostrarHojaVidrio<bool>(
      context,
      builder: (_) => _HojaMedioPago(servicio: _servicio!, medio: medio),
    );
    if (guardado == true) await _cargar();
  }

  Future<void> _renombrarUsuario(UsuarioCompanion usuario) async {
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
    ctrl.dispose();
    if (guardado == true) await _cargar();
  }
}

/// Una categoría con su ganancia de referencia y un stepper de a 5 puntos (docs/03 D5).
class _FilaPorcentaje extends StatelessWidget {
  const _FilaPorcentaje({required this.nombre, required this.porcentaje, required this.onMenos, required this.onMas});

  final String nombre;
  final int porcentaje;
  final VoidCallback onMenos;
  final VoidCallback onMas;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
      decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(28)),
      child: Row(
        children: [
          Expanded(child: Text(nombre, style: estiloNs(16, peso: FontWeight.w500, track: -0.02, color: ns.ink))),
          StepperNs(cantidad: '$porcentaje %', onMenos: onMenos, onMas: onMas, anchoCantidad: 52, tamanioCantidad: 14),
        ],
      ),
    );
  }
}

/// Molde compartido por las hojas de edición de acá abajo: título, un
/// mensaje de error si `onGuardar` tira, y el botón "Guardar" con su
/// spinner mientras corre.
class _HojaModeloIa extends StatelessWidget {
  const _HojaModeloIa();

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final actual = ClaveGemini.modelo ?? modeloGeminiPorDefecto;
    final modelos = [if (!modelosGemini.contains(actual)) actual, ...modelosGemini];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Modelo de la IA', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: Espaciado.md),
        for (final m in modelos)
          ListTile(
            key: ValueKey('modelo_ia_$m'),
            title: Text(m, style: estiloNs(16, peso: m == actual ? FontWeight.w600 : FontWeight.w400, color: ns.ink)),
            subtitle: Text(etiquetaDeModelo(m).substring(m.length).replaceFirst(' — ', ''), style: estiloNs(13, color: ns.mute)),
            trailing: m == actual ? Icon(Icons.check, color: ns.ink) : null,
            onTap: () async {
              await ClaveGemini.elegirModelo(m);
              if (context.mounted) Navigator.of(context).pop(true);
            },
          ),
      ],
    );
  }
}

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
          ErrorEnLinea(_error!),
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
  });

  final String titulo;
  final String etiqueta;
  final TextEditingController controller;
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

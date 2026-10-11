// Cierres reales (El dueño, 2026-09-13: "en la app debo poder ver los cierres
// por mas que este fuera del local y con la app desktop cerrada"). Distinta
// de "Historial de ventas": acá se ve un cierre por sesión de caja (arqueo
// completo: efectivo/MP/lata contado vs. esperado), no venta por venta —
// pero comparten pantalla como dos pestañas de "Historial" (El dueño,
// 2026-09-18: "reacomodación de absolutamente todos los elementos" — las
// dos son formas de mirar para atrás, no dos ideas separadas). Este widget
// ya NO trae su propio `Scaffold`/`AppBar`: `PantallaHistorialVentas` lo
// aloja como el body de su segunda pestaña.
//
// Sin PC emparejada (El dueño, 2026-09-18: "no debería tener que escanear ya,
// es innecesario") se calcula en vivo contra la base local sincronizada por
// Supabase (`PuertoLocal`), no distinto de tenerla contra la PC — los
// cierres son parte de las 14 tablas que ya sincroniza Supabase. La caché
// en disco (`cache_cierres.dart`) queda como último recurso de verdad
// (celular recién instalado que ni siquiera terminó su primer sync).
//
// Antes de esto, esta pantalla mostraba lo último cacheado apenas
// `leerConexion()` daba null, aunque el celular tuviera datos sincronizados
// más frescos que esa caché vieja — ya no hace falta ese atajo.

import 'dart:async';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter/material.dart';

import '../data/pdf_dia_completo.dart';
import '../data/repositorio_conciliacion_mp.dart';
import '../domain/conciliacion_mp.dart';
import '../servicios/conciliacion_mp_nube.dart';
import '../servicios/modulos_activos.dart' show esNegocioDeServicios;
import 'pantallas/seccion_mp_real_ns.dart';
import 'sync_nube_companion.dart';
import '../ui/tema/tokens.dart';
import 'cambios_companion.dart';
import 'base_local.dart';
import 'cache_cierres.dart';
import 'kit/kit_ns.dart';
import 'cliente_companion.dart' show ClienteCompanion, ResumenCierreCompanion, SesionCerradaCompanion;
import 'emparejamiento.dart';
import 'mensaje_error.dart';
import 'puerto_local.dart';
import 'seccion_extra_cierre_companion.dart';
import 'seleccion_servicio.dart';
import 'servicio_companion.dart';
import 'tema/app_bar_companion.dart';
import 'servicio_companion_offline.dart';
import 'tema/esqueleto_companion.dart';
import '../ui/comun/estado_error.dart';
import '../ui/comun/estado_vacio.dart';
import '../ui/tema/iconos.dart';

class PantallaCierres extends StatefulWidget {
  const PantallaCierres({super.key});

  @override
  State<PantallaCierres> createState() => _PantallaCierresState();
}

class _PantallaCierresState extends State<PantallaCierres> {
  List<SesionCerradaCompanion> _cierres = [];
  DateTime? _fechaCache;
  bool _sinConexion = false;
  bool _cargando = true;
  String? _error;

  /// Guardado para que las filas puedan pedir el detalle completo al
  /// tocarlas (El dueño, 2026-09-19: rework de "Cierres" con el desglose por
  /// proveedor) — antes cada `_cargar()` resolvía su propio `servicio`
  /// local, sin guardarlo, porque nada más lo necesitaba.
  ServicioCompanion? _servicio;

  /// El dueño, 2026-09-18: "no hay nada que actualice la app cuando se
  /// sincronizó" — repite la carga sola apenas la sync trae algo nuevo.
  /// El dueño, 2026-09-19: "las pantallas se refrescan en cada sync, cosa que
  /// me gustaría que se disimule más" — con el nudge de baja latencia de
  /// `sincronizacion_supabase.dart` esto pasa mucho más seguido, así que el
  /// refresco automático es [silencioso]: no tapa la lista ya visible con
  /// el spinner, y una falla transitoria durante ese refresco cae al
  /// caché sin gritar error (se reintenta solo en la próxima sync). Un
  /// refresco explícito (pull-to-refresh) sigue mostrando ambos como
  /// siempre.
  StreamSubscription<void>? _subCambiosSync;

  @override
  void initState() {
    super.initState();
    _cargar();
    _subCambiosSync = avisosCambiosCompanion.listen(
      (_) => _cargar(silencioso: true),
    );
  }

  @override
  void dispose() {
    _subCambiosSync?.cancel();
    super.dispose();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }
    try {
      final conexion = await leerConexion();
      final servicio = conexion == null
          ? ServicioCompanionOffline(PuertoLocal(baseLocalCompanion()))
          : await resolverServicioCompanion(conexion);
      final cierres = await servicio.sesionesCerradas();
      await guardarCierresEnCache(cierres);
      if (mounted) {
        setState(() {
          _cierres = cierres;
          _servicio = servicio;
          _sinConexion = false;
          _fechaCache = null;
        });
      }
    } catch (e) {
      if (silencioso) return;
      final cache = await leerCierresDeCache();
      if (!mounted) return;
      if (cache != null) {
        setState(() {
          _cierres = cache.cierres;
          _sinConexion = true;
          _fechaCache = cache.fecha;
        });
      } else {
        setState(() => _error = mensajeDeError(e));
      }
    } finally {
      if (mounted && !silencioso) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _cargando
        ? const EsqueletoLista()
        : _error != null
        ? EstadoError(mensaje: _error!, onReintentar: _cargar)
        : _cierres.isEmpty
        ? const EstadoVacio(
            mensaje: 'Sin cierres todavía',
            icono: IconosPlazoleta.pointOfSaleOutlined,
          )
        : RefreshIndicator(
            onRefresh: _cargar,
            child: Column(
              children: [
                if (_sinConexion) _avisoSinConexion(context),
                Expanded(child: _lista(context)),
              ],
            ),
          );
  }

  Widget _avisoSinConexion(BuildContext context) {
    final colores = context.colores;
    return Container(
      width: double.infinity,
      color: colores.fondoBloque,
      padding: const EdgeInsets.symmetric(
        horizontal: Espaciado.lg,
        vertical: Espaciado.sm,
      ),
      child: Row(
        children: [
          Icon(IconosPlazoleta.cloudOff, size: 18, color: colores.textoSecundario),
          const SizedBox(width: Espaciado.sm),
          Expanded(
            child: Text(
              'Sin conexión — mostrando lo guardado el ${_fechaHora(_fechaCache!)}',
              style: TextStyle(color: colores.textoSecundario),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lista(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(margenNs, 14, margenNs, 24),
      itemCount: _cierres.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _FilaCierre(cierre: _cierres[i], servicio: _servicio),
    );
  }
}

class _FilaCierre extends StatefulWidget {
  const _FilaCierre({required this.cierre, required this.servicio});

  final ServicioCompanion? servicio;

  final SesionCerradaCompanion cierre;

  @override
  State<_FilaCierre> createState() => _FilaCierreState();
}

class _FilaCierreState extends State<_FilaCierre> {
  /// Ya no expande inline (El dueño, 2026-09-19: rework de "Cierres" con el
  /// desglose por proveedor) — tocar la fila abre una hoja con el detalle
  /// completo (`_abrirDetalle`), que además trae lo que esta fila nunca
  /// tuvo: cigarrillos, redondeo, vendido sin costo, reserva de fijos, nota
  /// y a separar por proveedor.
  Future<void> _abrirDetalle() async {
    await mostrarHojaNs<void>(
      context,
      builder: (context) => _DetalleCierreCompanion(
        cierre: widget.cierre,
        servicio: widget.servicio,
      ),
    );
  }

  /// Una fila como en el mock (36): "03/10/2026 21:40 · Ana", lo vendido y a la derecha la mayor diferencia
  /// ("Cuadró", "−$ 400", "+$ 150").
  @override
  Widget build(BuildContext context) {
    final c = widget.cierre;
    final dif = [c.diferenciaCentavos, c.mpDiferenciaCentavos, c.lataDiferenciaCentavos].whereType<int>();
    final peor = dif.isEmpty ? 0 : dif.reduce((a, b) => a.abs() > b.abs() ? a : b);
    return FilaProductoNs(
      nombre: '${_fecha(c.fechaCierre ?? c.fechaApertura)} · ${c.nombreEmpleado}',
      detalle: 'Vendido ${plataNs(c.totalVendidoCentavos)}',
      valor: dif.isEmpty ? '' : _diferenciaTexto(peor),
      onTap: _abrirDetalle,
    );
  }
}

/// `Cuadró` / `−$ 400` / `+$ 150` (la diferencia más grande del cierre).
String _diferenciaTexto(int d) => d == 0 ? 'Cuadró' : '${d > 0 ? '+' : '−'}${plataNs(d.abs())}';

/// Detalle completo de un cierre, en una hoja de vidrio (El dueño, 2026-09-19:
/// rework de "Cierres" con el desglose por proveedor) — las tres cajas
/// aparecen de una (ya vienen en [cierre], sin esperar red); el resto
/// (cigarrillos/redondeo/vendido sin costo/reserva/nota/por proveedor) se
/// pide aparte con `detalleCierre` y se muestra apenas llega, sin bloquear
/// lo que ya se puede ver.
class _DetalleCierreCompanion extends StatefulWidget {
  const _DetalleCierreCompanion({required this.cierre, required this.servicio});

  final SesionCerradaCompanion cierre;
  final ServicioCompanion? servicio;

  @override
  State<_DetalleCierreCompanion> createState() => _DetalleCierreCompanionState();
}

class _DetalleCierreCompanionState extends State<_DetalleCierreCompanion> {
  ResumenCierreCompanion? _resumen;
  String? _error;
  bool _exportando = false;
  String? _errorExportar;

  /// El PDF se arma contra la base de este celular, que siempre tiene una copia
  /// sincronizada (con o sin la PC a la vista). Sin PC el id del día es el
  /// local; con la PC conectada es el de la PC, y se busca el mismo día en la
  /// copia del celular por su hora de apertura.
  Future<int?> _sesionLocalId() async {
    final db = baseLocalCompanion();
    final porId = await (db.select(db.sesionesDeCaja)..where((x) => x.id.equals(widget.cierre.sesionId))).getSingleOrNull();
    if (widget.servicio is! ClienteCompanion && porId != null) return porId.id;
    final porFecha = await (db.select(db.sesionesDeCaja)
          ..where((x) => x.fechaApertura.equals(widget.cierre.fechaApertura)))
        .get();
    return porFecha.isEmpty ? null : porFecha.first.id;
  }

  /// Los cobros reales de Mercado Pago del día, con la cuenta de Nodo Sur del celular, contra la copia local del día.
  Future<ConciliacionMp> _cargarMpReal() async {
    final sesionId = await _sesionLocalId();
    if (sesionId == null) throw 'este día todavía no llegó a tu celular; esperá a que sincronice';
    final sync = await syncNubeDelCelular();
    return conciliarMpDeSesion(baseLocalCompanion(), sesionId, leerCobrosMpDeCuenta(sync.almacen, sync.cliente));
  }

  /// Arma el PDF del día completo y lo abre: desde el visor de Android se
  /// manda por WhatsApp, mail o Drive (El dueño, 2026-10-03).
  Future<void> _exportarDia() async {
    setState(() {
      _exportando = true;
      _errorExportar = null;
    });
    try {
      final sesionId = await _sesionLocalId();
      if (sesionId == null) {
        setState(() => _errorExportar = 'Este día todavía no llegó a tu celular: esperá a que sincronice y probá de nuevo.');
        return;
      }
      final carpeta = await getTemporaryDirectory();
      final ruta = await guardarPdfDiaCompleto(
        baseLocalCompanion(),
        sesionId: sesionId,
        carpetaDestino: carpeta.path,
      );
      final r = await OpenFilex.open(ruta);
      if (r.type != ResultType.done && mounted) {
        setState(() => _errorExportar = 'El PDF se armó pero no hay una app para abrirlo (${r.message}).');
      }
    } catch (e) {
      if (mounted) setState(() => _errorExportar = 'No se pudo exportar el día: ${mensajeDeError(e)}');
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final servicio = widget.servicio;
    if (servicio == null) return;
    try {
      final resumen = await servicio.detalleCierre(widget.cierre.sesionId);
      if (mounted) setState(() => _resumen = resumen);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  Widget _filaCaja(String nombre, int? contado, int? esperado, int? diferencia) {
    if (contado == null && esperado == null) return const SizedBox.shrink();
    return FilaProductoNs(
      nombre: nombre,
      detalle: 'Contado ${plataNs(contado ?? 0)} · Esperado ${plataNs(esperado ?? 0)}',
      valor: diferencia == null ? '—' : (diferencia == 0 ? '=' : _diferenciaTexto(diferencia)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cierre;
    return HojaNs(
      titulo: _fecha(c.fechaCierre ?? c.fechaApertura),
      texto: 'Cerró ${c.nombreEmpleado}',
      bloques: [
        _filaCaja('Efectivo', c.efectivoContadoCentavos, c.efectivoEsperadoCentavos, c.diferenciaCentavos),
        _filaCaja('Mercado Pago', c.mpContadoCentavos, c.mpEsperadoCentavos, c.mpDiferenciaCentavos),
        if (!esNegocioDeServicios()) _filaCaja('Lata', c.lataContadoCentavos, c.lataFinalCentavos, c.lataDiferenciaCentavos),
        BotonNs.secundario(context, _exportando ? 'Armando el PDF…' : 'Exportar el día completo (PDF)', _exportando ? null : _exportarDia, alto: 52),
        if (_errorExportar != null) InfoNs(_errorExportar!, tono: TonoNs.bad),
        SeccionMpRealNs(cargar: _cargarMpReal, mpEsperadoCentavos: c.mpEsperadoCentavos ?? 0, mpContadoCentavos: c.mpContadoCentavos),
        if (_resumen != null)
          SeccionExtraCierreCompanion(resumen: _resumen!)
        else if (_error != null)
          InfoNs(_error!, tono: TonoNs.bad)
        else
          const Padding(padding: EdgeInsets.all(14), child: Center(child: SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5)))),
      ],
      botones: [BotonNs.secundario(context, 'Cerrar', () => Navigator.of(context).pop())],
    );
  }
}

/// "Cierres anteriores" como página completa (docs/03 D2).
class PaginaCierresAnteriores extends StatelessWidget {
  const PaginaCierresAnteriores({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.ns.paper,
    appBar: const AppBarCompanion(titulo: 'Cierres anteriores'),
    body: const SafeArea(child: PantallaCierres()),
  );
}

String _fecha(DateTime f) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(f.day)}/${dos(f.month)}/${f.year} ${dos(f.hour)}:${dos(f.minute)}';
}

String _fechaHora(DateTime f) => _fecha(f);

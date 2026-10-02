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

import 'package:flutter/material.dart';

import '../domain/dinero.dart';
import '../ui/tema/tokens.dart';
import 'cambios_companion.dart';
import 'base_local.dart';
import 'cache_cierres.dart';
import 'cliente_companion.dart' show ResumenCierreCompanion, SesionCerradaCompanion;
import 'emparejamiento.dart';
import 'mensaje_error.dart';
import 'navbar_companion.dart';
import 'puerto_local.dart';
import 'seccion_extra_cierre_companion.dart';
import 'seleccion_servicio.dart';
import 'servicio_companion.dart';
import 'servicio_companion_offline.dart';
import 'tema/esqueleto_companion.dart';
import '../ui/comun/estado_error.dart';
import '../ui/comun/estado_vacio.dart';
import 'tema/hoja_vidrio.dart';
import 'tema/presionable.dart';
import 'tema/superficie.dart';
import '../ui/tema/iconos.dart';
import 'tema/error_en_linea.dart';

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
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        Espaciado.lg,
        Espaciado.lg,
        Espaciado.lg,
        Espaciado.lg + NavbarCompanion.espacioReservado,
      ),
      itemCount: _cierres.length,
      itemBuilder: (context, i) {
        final c = _cierres[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: Espaciado.sm),
          child: _FilaCierre(cierre: c, servicio: _servicio),
        );
      },
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
    await mostrarHojaVidrio<void>(
      context,
      builder: (context) => _DetalleCierreCompanion(
        cierre: widget.cierre,
        servicio: widget.servicio,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cierre;
    final colores = context.colores;
    return Superficie(
      padding: EdgeInsets.zero,
      child: Presionable(
        onTap: _abrirDetalle,
        child: Padding(
          padding: const EdgeInsets.all(Bento.paddingBloque),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _fecha(c.fechaCierre ?? c.fechaApertura),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      c.nombreEmpleado,
                      style: TextStyle(color: colores.textoSecundario),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatearARS(c.totalVendidoCentavos),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  _chipDiferencia(context, c),
                ],
              ),
              Icon(IconosPlazoleta.chevronRight, color: colores.textoSecundario),
            ],
          ),
        ),
      ),
    );
  }

  /// Suma máxima diferencia en valor absoluto entre las tres cajas, para un
  /// solo indicador rápido en la fila colapsada (el desglose completo por
  /// caja aparece recién al expandir).
  Widget _chipDiferencia(BuildContext context, SesionCerradaCompanion c) {
    final diferencias = [
      c.diferenciaCentavos,
      c.mpDiferenciaCentavos,
      c.lataDiferenciaCentavos,
    ].whereType<int>();
    if (diferencias.isEmpty) return const SizedBox.shrink();
    final peor = diferencias.reduce((a, b) => a.abs() > b.abs() ? a : b);
    if (peor == 0) {
      return Text(
        'Cuadró',
        style: TextStyle(
          color: context.colores.textoSecundario,
          fontSize: TamanioTexto.etiqueta,
        ),
      );
    }
    return Text(
      peor > 0 ? '+${formatearARS(peor)}' : '-${formatearARS(-peor)}',
      style: TextStyle(color: context.colores.error, fontSize: TamanioTexto.etiqueta),
    );
  }
}

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

  @override
  Widget build(BuildContext context) {
    final c = widget.cierre;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_fecha(c.fechaCierre ?? c.fechaApertura), style: Theme.of(context).textTheme.titleLarge),
          Text(c.nombreEmpleado, style: TextStyle(color: context.colores.textoSecundario)),
          const SizedBox(height: Espaciado.lg),
          _filaCaja(context, 'Efectivo', c.efectivoContadoCentavos, c.efectivoEsperadoCentavos, c.diferenciaCentavos),
          _filaCaja(context, 'Mercado Pago', c.mpContadoCentavos, c.mpEsperadoCentavos, c.mpDiferenciaCentavos),
          _filaCaja(context, 'Lata', c.lataContadoCentavos, c.lataFinalCentavos, c.lataDiferenciaCentavos),
          const SizedBox(height: Espaciado.lg),
          if (_resumen != null) ...[
            const Divider(),
            const SizedBox(height: Espaciado.sm),
            SeccionExtraCierreCompanion(resumen: _resumen!),
          ] else if (_error != null)
            ErrorEnLinea(_error!)
          else
            const Center(
              child: Padding(
                padding: EdgeInsets.all(Espaciado.lg),
                child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
        ],
      ),
    );
  }
}

Widget _filaCaja(
  BuildContext context,
  String etiqueta,
  int? contado,
  int? esperado,
  int? diferencia,
) {
  if (contado == null && esperado == null) return const SizedBox.shrink();
  final colores = context.colores;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: Espaciado.xs),
    child: Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(etiqueta, style: TextStyle(color: colores.textoSecundario)),
        ),
        Expanded(
          child: Text(
            'Contado ${formatearARS(contado ?? 0)}',
            style: const TextStyle(fontSize: TamanioTexto.etiqueta),
          ),
        ),
        Expanded(
          child: Text(
            'Esperado ${formatearARS(esperado ?? 0)}',
            style: const TextStyle(fontSize: TamanioTexto.etiqueta),
          ),
        ),
        SizedBox(
          width: 70,
          child: Text(
            diferencia == null
                ? '—'
                : diferencia == 0
                ? '='
                : diferencia > 0
                ? '+${formatearARS(diferencia)}'
                : '-${formatearARS(-diferencia)}',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: diferencia == null || diferencia == 0 ? colores.textoSecundario : colores.error,
              fontWeight: Pesos.medium,
            ),
          ),
        ),
      ],
    ),
  );
}

String _fecha(DateTime f) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(f.day)}/${dos(f.month)}/${f.year} ${dos(f.hour)}:${dos(f.minute)}';
}

String _fechaHora(DateTime f) => _fecha(f);

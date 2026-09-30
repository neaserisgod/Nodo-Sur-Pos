// Estado de "Separaciones" — rediseño sobre el mock de el dueño (2026-09-26):
// tarjetas de caja arriba (Efectivo / Mercado Pago / Total: cobrado, a
// separar, te queda), una tarjeta por proveedor con un tilde para marcarla
// separada, y una tarjeta de progreso. Dos vistas: "Qué separar" (siempre
// del día) y "Lo vendido" (hoy / semana / mes).
//
// No calcula nada propio: `separacionesDelDia`, `cobradoDelDia`,
// `disponibleParaSepararAhora` y `ajustarSeparacionesADisponible`
// (`repositorio_reposicion.dart`) arman los números; `separarDelDia` y
// `desmarcarDelDia` los escriben.

import 'package:flutter/widgets.dart';

import '../../data/database.dart';
import '../../data/repositorio_reposicion.dart';
import '../../domain/ajuste_a_disponible.dart';
import '../../domain/periodo.dart';
import '../navegacion/busqueda_contextual.dart' show coincideBusqueda;

enum VistaSeparaciones { queSeparar, loVendido }

/// Lo que muestra una tarjeta de proveedor en "Qué separar".
class TarjetaSeparacion {
  final SeparacionDelDia fila;

  /// Tildada: lo de hoy ya está separado.
  final bool separada;

  /// Lo que dice la tarjeta: lo separado hoy si está tildada, lo que falta
  /// (ya ajustado a la plata de cada caja) si no.
  final int efectivoCentavos;
  final int mpCentavos;

  const TarjetaSeparacion({
    required this.fila,
    required this.separada,
    required this.efectivoCentavos,
    required this.mpCentavos,
  });

  int get proveedorId => fila.proveedor!.id;
  int get totalCentavos => efectivoCentavos + mpCentavos;

  /// Tildada pero ya pagada: no se puede destildar.
  bool get bloqueada => separada && !fila.puedeDesmarcar;
}

class SeparacionesControlador extends ChangeNotifier {
  SeparacionesControlador(
    this.db, {
    required this.usuarioId,
    required this.sesionCajaId,
  });

  final AppDatabase db;
  final int usuarioId;

  /// Null sin caja abierta: no hay "plata de ahora" para ajustar — se puede
  /// separar igual (no mueve ninguna caja), con la división según cómo se
  /// cobró.
  final int? sesionCajaId;

  bool cargando = true;
  VistaSeparaciones vista = VistaSeparaciones.queSeparar;

  /// Solo para "Lo vendido" — "Qué separar" es siempre del día.
  PeriodoResumen periodo = PeriodoResumen.hoy;

  List<SeparacionDelDia> _hoy = [];

  /// Ganancia sin revisar por proveedor (desde su `gananciaRevisadaFecha`,
  /// Regla 13) — lo que se retiene como colchón o se retira. Es un corte
  /// propio de cada proveedor, independiente del período de "Lo vendido".
  Map<int, GananciaPendienteProveedor> gananciaSinRevisar = {};
  List<SeparacionDelDia> _periodo = [];
  DisponibleParaSeparar? disponible;
  ResultadoAjuste<int> ajuste = const ResultadoAjuste(
    partes: {},
    corridoAMpCentavos: 0,
    faltanteCentavos: 0,
  );
  ({int efectivoCentavos, int mpCentavos, int cigarrillosCentavos}) cobrado = (
    efectivoCentavos: 0,
    mpCentavos: 0,
    cigarrillosCentavos: 0,
  );

  /// Buscador de arriba (contextual, 2026-09-28): filtra qué proveedores se
  /// ven. No cambia las cuentas (lo que falta separar sigue siendo de todos).
  String busqueda = '';

  void buscar(String texto) {
    busqueda = texto;
    notifyListeners();
  }

  bool _coincide(SeparacionDelDia f) => coincideBusqueda(f.nombre, busqueda);

  List<TarjetaSeparacion> get tarjetasVisibles => [for (final t in tarjetas) if (_coincide(t.fila)) t];
  List<SeparacionDelDia> get vendidosVisibles => [for (final f in vendidos) if (_coincide(f)) f];

  /// Proveedores con una acción en curso — un doble clic no separa dos veces.
  final Set<int> procesando = {};

  // ─── Qué separar ──────────────────────────────────────────────────────

  /// Una tarjeta por proveedor con algo de hoy (por separar o ya separado),
  /// de mayor a menor.
  List<TarjetaSeparacion> get tarjetas {
    final lista = [
      for (final f in _hoy)
        if (f.proveedor != null &&
            (f.faltaSepararCentavos > 0 || f.separadoHoyCentavos > 0))
          _tarjeta(f),
    ]..sort((a, b) => b.totalCentavos.compareTo(a.totalCentavos));
    return lista;
  }

  TarjetaSeparacion _tarjeta(SeparacionDelDia f) {
    if (f.separadaHoy) {
      return TarjetaSeparacion(
        fila: f,
        separada: true,
        efectivoCentavos: f.separadoHoyCentavos - f.separadoHoyMpCentavos,
        mpCentavos: f.separadoHoyMpCentavos,
      );
    }
    final p = _falta(f);
    return TarjetaSeparacion(
      fila: f,
      separada: false,
      efectivoCentavos: p.efectivoCentavos,
      mpCentavos: p.mpCentavos,
    );
  }

  /// Lo de hoy entero por caja: lo ya separado hoy + lo que falta.
  int get separarEfectivoCentavos => _hoy.fold(
    0,
    (a, f) =>
        a +
        (f.separadoHoyCentavos - f.separadoHoyMpCentavos) +
        _falta(f).efectivoCentavos,
  );
  int get separarMpCentavos => _hoy.fold(
    0,
    (a, f) => a + f.separadoHoyMpCentavos + _falta(f).mpCentavos,
  );

  ParteSeparacion _falta(SeparacionDelDia f) =>
      (f.proveedor == null ? null : ajuste.partes[f.proveedor!.id]) ??
      const ParteSeparacion(efectivoCentavos: 0, mpCentavos: 0);

  /// Lo que queda en cada caja después de separar: del efectivo, además, lo
  /// que se lleva la lata al cierre (los cigarrillos de hoy, Regla 6).
  int get quedaEfectivoCentavos =>
      cobrado.efectivoCentavos -
      cobrado.cigarrillosCentavos -
      separarEfectivoCentavos;
  int get quedaMpCentavos => cobrado.mpCentavos - separarMpCentavos;

  int get faltaEfectivoCentavos =>
      ajuste.partes.values.fold(0, (a, p) => a + p.efectivoCentavos);
  int get faltaMpCentavos =>
      ajuste.partes.values.fold(0, (a, p) => a + p.mpCentavos);

  int get cantidadSeparadas => tarjetas.where((t) => t.separada).length;
  bool get hayPorSeparar =>
      tarjetas.any((t) => !t.separada && t.totalCentavos > 0);
  bool get hayParaDesmarcar => tarjetas.any((t) => t.separada && !t.bloqueada);

  int get vendidoSinCostoHoyCentavos =>
      _hoy.fold(0, (a, f) => a + f.vendidoSinCostoCentavos);

  // ─── Lo vendido ───────────────────────────────────────────────────────

  List<SeparacionDelDia> get vendidos => [
    for (final f in (periodo == PeriodoResumen.hoy ? _hoy : _periodo))
      if (f.vendidoCentavos != 0) f,
  ]..sort((a, b) => b.vendidoCentavos.compareTo(a.vendidoCentavos));

  int get vendidoCentavos => vendidos.fold(0, (a, f) => a + f.vendidoCentavos);
  int get costoCentavos => vendidos.fold(0, (a, f) => a + f.costoCentavos);
  int get gananciaCentavos =>
      vendidos.fold(0, (a, f) => a + f.gananciaCentavos);
  int get vendidoSinCostoCentavos =>
      vendidos.fold(0, (a, f) => a + f.vendidoSinCostoCentavos);

  DateTime get inicioDeHoy =>
      inicioDePeriodo(PeriodoResumen.hoy, DateTime.now())!;
  DateTime get inicioDelPeriodo => inicioDePeriodo(periodo, DateTime.now())!;

  /// Para títulos: "hoy", "esta semana", "este mes".
  String get nombrePeriodo => switch (periodo) {
    PeriodoResumen.semana => 'esta semana',
    PeriodoResumen.mes => 'este mes',
    _ => 'hoy',
  };

  // ─── Acciones ─────────────────────────────────────────────────────────

  Future<void> cargarTodo() async {
    _hoy = await separacionesDelDia(db);
    final sesion = sesionCajaId;
    disponible = sesion == null
        ? null
        : await disponibleParaSepararAhora(db, sesion);
    ajuste = ajustarSeparacionesADisponible(_hoy, disponible);
    cobrado = await cobradoDelDia(db);
    gananciaSinRevisar = {
      for (final g in await gananciaPendienteDeProveedores(db))
        g.proveedor.id: g,
    };
    if (periodo != PeriodoResumen.hoy) {
      _periodo = await separacionesDelDia(
        db,
        desde: inicioDePeriodo(periodo, DateTime.now()),
      );
    }
    cargando = false;
    if (!_descartado) notifyListeners();
  }

  void cambiarVista(VistaSeparaciones nueva) {
    vista = nueva;
    notifyListeners();
  }

  Future<void> cambiarPeriodo(PeriodoResumen nuevo) async {
    periodo = nuevo;
    await cargarTodo();
  }

  /// Tildar separa lo de hoy (con la división ajustada); destildar lo
  /// deshace. Una tarjeta ya pagada no se destilda.
  Future<void> alternar(TarjetaSeparacion t) async {
    if (t.bloqueada) return;
    await _conProcesando([t.proveedorId], () async {
      if (t.separada) {
        await desmarcarDelDia(db, proveedorId: t.proveedorId);
      } else {
        await separarDelDia(
          db,
          proveedorId: t.proveedorId,
          montoMpCentavos: t.mpCentavos,
        );
      }
    });
  }

  /// El reparto se toma una sola vez antes de empezar: separar uno no debe
  /// cambiar lo que le toca al siguiente.
  Future<void> marcarTodo() async {
    final plan = [
      for (final t in tarjetas)
        if (!t.separada && t.totalCentavos > 0) t,
    ];
    await _conProcesando(plan.map((t) => t.proveedorId), () async {
      for (final t in plan) {
        await separarDelDia(
          db,
          proveedorId: t.proveedorId,
          montoMpCentavos: t.mpCentavos,
        );
      }
    });
  }

  Future<void> desmarcarTodo() async {
    final plan = [
      for (final t in tarjetas)
        if (t.separada && !t.bloqueada) t.proveedorId,
    ];
    await _conProcesando(plan, () async {
      for (final id in plan) {
        await desmarcarDelDia(db, proveedorId: id);
      }
    });
  }

  Future<void> _conProcesando(
    Iterable<int> ids,
    Future<void> Function() accion,
  ) async {
    final lista = ids.toList();
    procesando.addAll(lista);
    notifyListeners();
    try {
      await accion();
    } finally {
      procesando.removeAll(lista);
      await cargarTodo();
    }
  }

  // ─── Ganancia (antes en Reportes, 2026-09-26) ─────────────────────────

  /// Retiene toda la ganancia sin revisar como colchón (no retira nada) y
  /// cierra la revisión de ese período.
  Future<void> retenerComoColchon(int proveedorId, int gananciaCentavos) async {
    final sesion = sesionCajaId;
    if (sesion == null) return;
    await _conProcesando([proveedorId], () async {
      await revisarGananciaProveedor(
        db,
        proveedorId: proveedorId,
        sesionCajaId: sesion,
        usuarioId: usuarioId,
        gananciaCentavos: gananciaCentavos,
      );
    });
  }

  /// Punto de partida del diálogo de retiro: de qué medio sale, según cómo
  /// se cobró lo que generó esa ganancia — la pantalla lo deja editable.
  Future<({int efectivoCentavos, int virtualCentavos})> sugerenciaRetiro(
    int proveedorId,
  ) {
    final proveedor = gananciaSinRevisar[proveedorId]!.proveedor;
    return gananciaPorMedioDesde(db, proveedor);
  }

  /// Retira [efectivoCentavos] + [virtualCentavos]; lo que no se retira de
  /// [gananciaCentavos] queda como colchón.
  Future<void> retirarGanancia(
    int proveedorId, {
    required int gananciaCentavos,
    required int efectivoCentavos,
    required int virtualCentavos,
  }) async {
    final sesion = sesionCajaId;
    if (sesion == null) return;
    await _conProcesando([proveedorId], () async {
      await revisarGananciaProveedor(
        db,
        proveedorId: proveedorId,
        sesionCajaId: sesion,
        usuarioId: usuarioId,
        gananciaCentavos: gananciaCentavos,
        retiroEfectivoCentavos: efectivoCentavos,
        retiroMercadoPagoCentavos: virtualCentavos,
      );
    });
  }

  bool _descartado = false;

  @override
  void dispose() {
    _descartado = true;
    super.dispose();
  }
}

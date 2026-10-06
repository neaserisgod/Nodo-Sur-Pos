// Historial — ventas, movimientos y cierres de caja, hecho desde cero como el mock v4 (`SCR.historial`, 2026-10-06):
// arriba a la derecha "Cargar día histórico" y las tres pestañas; debajo del título, la fila de filtros de la pestaña
// (período, medio o tipo) con el buscador grande a la derecha; y el contenido de la pestaña.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../domain/modulos.dart';
import '../../servicios/modulos_activos.dart';
import '../carga_historica/pantalla_carga_historica.dart';
import '../comun/armazon_gestion.dart';
import '../kit/kit.dart';
import '../navegacion/refresco_por_celular.dart';
import 'historial_controlador.dart';
import 'pantalla_detalle_dia.dart';
import 'periodo_historial.dart';
import 'tab_historial_movimientos.dart';
import 'tab_historial_ventas.dart';
import 'vista_cierres.dart';

enum _Vista { ventas, movimientos, cierres }

class PantallaHistorial extends StatefulWidget {
  const PantallaHistorial({super.key, required this.db, required this.usuarioId, this.pestanaInicial});

  final AppDatabase db;
  final int usuarioId;

  /// Con qué pestaña abre ('movimientos', 'cierres'); null = ventas. La usan los mega-menús de la barra.
  final String? pestanaInicial;

  @override
  State<PantallaHistorial> createState() => _PantallaHistorialState();
}

class _PantallaHistorialState extends State<PantallaHistorial> with RefrescoPorCelular {
  @override
  void alCambiarDesdeElCelular() => _c.cargarTodo();

  late final HistorialControlador _c;
  late _Vista _vista = switch (widget.pestanaInicial) {
    'movimientos' => _Vista.movimientos,
    'cierres' => _Vista.cierres,
    _ => _Vista.ventas,
  };

  /// El buscador de la fila de filtros: lo que busca depende de la pestaña (y se vacía al cambiar de pestaña).
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _c = HistorialControlador(widget.db);
    _c.cargarTodo();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _irACargaHistorica() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => PantallaCargaHistorica(db: widget.db, usuarioId: widget.usuarioId)),
    );
    await _c.cargarTodo();
  }

  Future<void> _irADetalle(int sesionId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => PantallaDetalleDia(db: widget.db, sesionId: sesionId, usuarioId: widget.usuarioId)),
    );
    await _c.cargarTodo();
  }

  Widget _buscador() => BuscadorPagina(
    key: ValueKey('buscador_$_vista'),
    campoKey: const Key('busqueda_contextual'),
    alto: 52,
    pista: switch (_vista) {
      _Vista.ventas => 'Buscar por producto o número…',
      _Vista.cierres => 'Buscar un día o un empleado…',
      _Vista.movimientos => 'Buscar un motivo, proveedor o empleado…',
    },
    onCambio: (t) => setState(() => _busqueda = t),
  );

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<HistorialControlador>.value(
      value: _c,
      child: Consumer<HistorialControlador>(
        // Prender o apagar la carga histórica en Configuración muestra u oculta su botón sin salir de la pantalla.
        builder: (context, c, _) => ValueListenableBuilder(
          valueListenable: modulosActuales,
          builder: (context, _, _) => PantallaGestion(
            db: widget.db,
            claveActiva: 'historial',
            usuarioId: widget.usuarioId,
            titulo: 'Historial',
            subtitulo: switch (_vista) {
              _Vista.ventas => 'Las ventas, una por una',
              _Vista.cierres => 'Cada cierre de caja y cómo cuadró',
              _Vista.movimientos => 'Gastos, ingresos, pagos y retiros de la caja',
            },
            acciones: [
              if (moduloActivo(Modulo.cargaHistorica))
                Btn('Cargar día histórico', variante: VarBtn.ton, onTap: _irACargaHistorica),
              Seg<_Vista>(
                opciones: const [(_Vista.ventas, 'Ventas'), (_Vista.movimientos, 'Movimientos'), (_Vista.cierres, 'Cierres')],
                valor: _vista,
                onCambio: (v) => setState(() {
                  _vista = v;
                  _busqueda = '';
                }),
              ),
            ],
            child: switch (_vista) {
              _Vista.ventas => TabHistorialVentas(db: widget.db, usuarioId: widget.usuarioId, busqueda: _busqueda, buscador: _buscador()),
              _Vista.movimientos => TabHistorialMovimientos(db: widget.db, busqueda: _busqueda, buscador: _buscador()),
              _Vista.cierres => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilaFiltrosHistorial(buscador: _buscador()),
                  const SizedBox(height: 16),
                  Expanded(
                    child: c.cargando
                        ? const SizedBox.shrink()
                        : VistaCierres(dias: c.dias, alAbrirDia: _irADetalle, busqueda: _busqueda),
                  ),
                ],
              ),
            },
          ),
        ),
      ),
    );
  }
}

/// La fila de filtros del mock (`#hpers`): chips del período, una rayita, los chips de la pestaña, y el buscador de
/// 420 a la derecha.
class FilaFiltrosHistorial extends StatelessWidget {
  const FilaFiltrosHistorial({super.key, this.periodo, this.onPeriodo, this.chips = const [], required this.buscador});

  final PeriodoHistorial? periodo;
  final ValueChanged<PeriodoHistorial>? onPeriodo;
  final List<Widget> chips;
  final Widget buscador;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final ancho = MediaQuery.sizeOf(context).width;
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (periodo != null)
                  for (final x in PeriodoHistorial.values) ...[
                    ChipMock(x.etiqueta, elegido: x == periodo, onTap: () => onPeriodo?.call(x)),
                    const SizedBox(width: 8),
                  ],
                if (periodo != null && chips.isNotEmpty) ...[
                  Container(width: 1, height: 26, color: p.linea, margin: const EdgeInsets.symmetric(horizontal: 6)),
                  const SizedBox(width: 8),
                ],
                for (final c in chips) ...[c, const SizedBox(width: 8)],
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(width: ancho >= 1700 ? 420 : 300, child: buscador),
      ],
    );
  }
}

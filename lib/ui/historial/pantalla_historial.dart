// Historial — ventas y cierres de caja (2026-09-26: la lista de ventas
// filtrable vino de Reportes; los dos son "historial", no hacía falta un
// apartado por cada uno).
//
// "Lenguaje de diseño" (El dueño, 2026-09-26, mocks `HistorialVentas.dc.html`
// y `HistorialCierres.dc.html`): las dos vistas se eligen con pastillas
// arriba a la derecha, como Separaciones, y cada una es lista a la
// izquierda + detalle a la derecha.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../navegacion/busqueda_contextual.dart';
import '../navegacion/refresco_por_celular.dart';
import '../../domain/modulos.dart';
import '../../servicios/modulos_activos.dart';
import '../../data/database.dart';
import '../carga_historica/pantalla_carga_historica.dart';
import '../comun/armazon_gestion.dart';
import '../comun/botones.dart';
import '../comun/tarjetas.dart';
import '../tema/tokens.dart';
import 'historial_controlador.dart';
import 'pantalla_detalle_dia.dart';
import 'tab_historial_movimientos.dart';
import 'tab_historial_ventas.dart';
import 'vista_cierres.dart';
import '../tema/esqueleto.dart';

enum _Vista { ventas, cierres, movimientos }

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

  /// Buscador de arriba (contextual): lo que busca depende de la pestaña.
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
      MaterialPageRoute(
        builder: (context) => PantallaDetalleDia(db: widget.db, sesionId: sesionId, usuarioId: widget.usuarioId),
      ),
    );
    await _c.cargarTodo();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<HistorialControlador>.value(
      value: _c,
      child: Consumer<HistorialControlador>(
        builder: (context, c, _) {
          return PantallaGestion(
            db: widget.db,
            claveActiva: 'historial',
            usuarioId: widget.usuarioId,
            titulo: 'Historial',
            busqueda: BusquedaContextual(
              pista: switch (_vista) {
                _Vista.ventas => 'Buscar N° de venta o producto…',
                _Vista.cierres => 'Buscar un día o un empleado…',
                _Vista.movimientos => 'Buscar un motivo, proveedor o empleado…',
              },
              alCambiar: (t) => setState(() => _busqueda = t),
            ),
            subtitulo: switch (_vista) {
              _Vista.ventas => 'Las ventas, una por una',
              _Vista.cierres => 'Cada cierre de caja y cómo cuadró',
              _Vista.movimientos => 'Gastos, ingresos, pagos y retiros de la caja',
            },
            accion: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GrupoPildoras<_Vista>(
                  opciones: const [(_Vista.ventas, 'Ventas'), (_Vista.cierres, 'Cierres de caja'), (_Vista.movimientos, 'Movimientos')],
                  elegida: _vista,
                  oscura: true,
                  onElegir: (v) => setState(() => _vista = v),
                ),
                const SizedBox(width: Espaciado.md),
                SiModulo(Modulo.cargaHistorica, hijo: BotonSecundario(texto: 'Cargar día histórico', onPressed: _irACargaHistorica)),
              ],
            ),
            child: switch (_vista) {
              _Vista.ventas => TabHistorialVentas(db: widget.db, usuarioId: widget.usuarioId, busqueda: _busqueda),
              _Vista.cierres =>
                c.cargando ? const EsqueletoLista() : VistaCierres(dias: c.dias, alAbrirDia: _irADetalle, busqueda: _busqueda),
              _Vista.movimientos => TabHistorialMovimientos(db: widget.db, busqueda: _busqueda),
            },
          );
        },
      ),
    );
  }
}

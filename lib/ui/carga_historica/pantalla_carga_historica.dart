// Carga histórica producto por producto (reemplaza a la de planilla, fase
// 9) — ver `carga_historica_controlador.dart`. Mismo espíritu que la
// pantalla de venta (buscar → carrito → cobrar) pero deliberadamente más
// simple: fecha elegida una sola vez, sin atajos de teclado, medios de pago
// como mock.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../domain/dinero.dart';
import '../../domain/medio_pago.dart';
import '../../domain/venta.dart';
import '../comun/armazon_gestion.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/fechas.dart';
import '../comun/tarjetas.dart';
import '../tema/acentos.dart';
import '../tema/presionable.dart';
import '../tema/superficie.dart';
import '../tema/tokens.dart';
import '../venta/dialogo_editar_cantidad.dart';
import '../venta/dialogo_mixto.dart';
import '../venta/dialogo_monto_varios.dart';
import 'carga_historica_controlador.dart';
import '../tema/iconos.dart';

class PantallaCargaHistorica extends StatefulWidget {
  const PantallaCargaHistorica({
    super.key,
    required this.db,
    required this.usuarioId,
  });

  final AppDatabase db;
  final int usuarioId;

  @override
  State<PantallaCargaHistorica> createState() => _PantallaCargaHistoricaState();
}

class _PantallaCargaHistoricaState extends State<PantallaCargaHistorica> {
  late final CargaHistoricaControlador _c;
  final _fechaCtrl = TextEditingController();
  final _horaCtrl = TextEditingController(text: '12:00');

  @override
  void initState() {
    super.initState();
    _c = CargaHistoricaControlador(widget.db, usuarioId: widget.usuarioId);
    _c.cargarTodo().then((_) {
      if (mounted) _c.focoCampoPrincipal.requestFocus();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _fechaCtrl.dispose();
    _horaCtrl.dispose();
    super.dispose();
  }

  void _confirmarFecha() {
    final dia = _parsearFecha(_fechaCtrl.text);
    final hora = _parsearHora(_horaCtrl.text);
    if (dia == null || hora == null) return;
    _c.elegirFecha(DateTime(dia.year, dia.month, dia.day, hora.$1, hora.$2));
    _c.focoCampoPrincipal.requestFocus();
  }

  Future<void> _guardarDia() async {
    final sesionId = await _c.guardarDia();
    if (sesionId != null && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CargaHistoricaControlador>.value(
      value: _c,
      child: Consumer<CargaHistoricaControlador>(
        builder: (context, c, _) {
          return PantallaGestion(
            db: widget.db,
            claveActiva: 'historial',
            usuarioId: widget.usuarioId,
            titulo: 'Carga histórica',
            accion: c.fecha == null
                ? null
                : BotonPrimario(
                    texto: c.guardando
                        ? 'Guardando...'
                        : 'Guardar día (${c.ventasCargadas.length})',
                    onPressed: c.guardando ? null : _guardarDia,
                  ),
            child: c.cargando
                ? const SizedBox.shrink()
                : c.fecha == null
                ? _SelectorFecha(
                    fechaCtrl: _fechaCtrl,
                    horaCtrl: _horaCtrl,
                    ultimoDiaCargado: c.ultimoDiaCargado,
                    diasConCaja: c.diasConCaja,
                    error: c.error,
                    onConfirmar: _confirmarFecha,
                  )
                : _Carga(controlador: c, fecha: c.fecha!),
          );
        },
      ),
    );
  }
}

DateTime? _parsearFecha(String texto) {
  final partes = texto.split('/');
  if (partes.length != 3) return null;
  final dia = int.tryParse(partes[0]);
  final mes = int.tryParse(partes[1]);
  final anio = int.tryParse(partes[2]);
  if (dia == null || mes == null || anio == null) return null;
  return DateTime(anio, mes, dia);
}

/// (hora, minuto), o null si el texto no tiene la forma "HH:MM".
(int, int)? _parsearHora(String texto) {
  final partes = texto.split(':');
  if (partes.length != 2) return null;
  final h = int.tryParse(partes[0]);
  final m = int.tryParse(partes[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
  return (h, m);
}

String _fechaCorta(DateTime f) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(f.day)}/${dos(f.month)}/${f.year}';
}

// "Lenguaje de diseño" (mock `CargaHistorica`): a la izquierda, el
// calendario del mes con qué días ya tienen caja y cuáles faltan; a la
// derecha, el día elegido. Tocar un día llena la fecha — también se puede
// tipear, para ir rápido con el teclado.
class _SelectorFecha extends StatefulWidget {
  const _SelectorFecha({
    required this.fechaCtrl,
    required this.horaCtrl,
    required this.ultimoDiaCargado,
    required this.diasConCaja,
    required this.error,
    required this.onConfirmar,
  });

  final TextEditingController fechaCtrl;
  final TextEditingController horaCtrl;
  final DateTime? ultimoDiaCargado;
  final Set<DateTime> diasConCaja;
  final String? error;
  final VoidCallback onConfirmar;

  @override
  State<_SelectorFecha> createState() => _SelectorFechaState();
}

class _SelectorFechaState extends State<_SelectorFecha> {
  late DateTime _mes;

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    _mes = DateTime(hoy.year, hoy.month);
    widget.fechaCtrl.addListener(_alCambiarFecha);
  }

  @override
  void dispose() {
    widget.fechaCtrl.removeListener(_alCambiarFecha);
    super.dispose();
  }

  void _alCambiarFecha() {
    final f = _parsearFecha(widget.fechaCtrl.text);
    setState(() {
      if (f != null) _mes = DateTime(f.year, f.month);
    });
  }

  void _elegir(DateTime dia) => widget.fechaCtrl.text = _fechaCorta(dia);

  @override
  Widget build(BuildContext context) {
    final elegido = _parsearFecha(widget.fechaCtrl.text);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ActionChip(
              avatar: const Icon(IconosPlazoleta.arrowBackRounded, size: 18),
              label: const Text('Historial'),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: Espaciado.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Carga histórica', style: textTheme.headlineMedium),
                  Text(
                    'Pasá al sistema las ventas que anotaste en el cuaderno, día por día.',
                    style: textTheme.bodyMedium?.copyWith(color: context.colores.textoSecundario),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Espaciado.lg),
        Expanded(child: SingleChildScrollView(child: _cuerpo(elegido))),
      ],
    );
  }

  Widget _cuerpo(DateTime? elegido) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Calendario(
                mes: _mes,
                elegido: elegido,
                diasConCaja: widget.diasConCaja,
                onElegir: _elegir,
                onMes: (m) => setState(() => _mes = m),
              ),
              const SizedBox(height: Espaciado.md),
              _AvanceDelMes(mes: _mes, diasConCaja: widget.diasConCaja),
            ],
          ),
        ),
        const SizedBox(width: Espaciado.lg),
        Expanded(child: _PanelDia(estado: this, elegido: elegido)),
      ],
    );
  }
}

enum _EstadoDia { cargado, falta, futuro }

_EstadoDia _estadoDe(DateTime dia, Set<DateTime> diasConCaja) {
  final hoy = DateTime.now();
  if (diasConCaja.contains(dia)) return _EstadoDia.cargado;
  if (!dia.isBefore(DateTime(hoy.year, hoy.month, hoy.day))) return _EstadoDia.futuro;
  return _EstadoDia.falta;
}

class _PanelDia extends StatelessWidget {
  const _PanelDia({required this.estado, required this.elegido});

  final _SelectorFechaState estado;
  final DateTime? elegido;

  @override
  Widget build(BuildContext context) {
    final w = estado.widget;
    final textTheme = Theme.of(context).textTheme;
    final colores = context.colores;
    final dia = elegido;
    final estadoDia = dia == null ? null : _estadoDe(dia, w.diasConCaja);
    return Superficie(
      padding: const EdgeInsets.all(Espaciado.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  dia == null ? 'Elegí un día' : _capitalizar(fechaLarga(dia)),
                  style: textTheme.headlineSmall?.copyWith(fontWeight: Pesos.fuerte),
                ),
              ),
              if (estadoDia == _EstadoDia.cargado) const Insignia(texto: 'Ya tiene caja', tono: Tono.ganancia),
              if (estadoDia == _EstadoDia.falta) const Insignia(texto: 'Falta cargar', tono: Tono.alerta),
            ],
          ),
          const SizedBox(height: Espaciado.sm),
          Text(
            'Se elige una sola vez — después se agregan los productos vendidos ese día con el carrito.',
            style: textTheme.bodyMedium?.copyWith(color: colores.textoSecundario),
          ),
          if (w.ultimoDiaCargado != null) ...[
            const SizedBox(height: Espaciado.xs),
            Text(
              'Último día cargado: ${_fechaCorta(w.ultimoDiaCargado!)}. Cargá los días en orden, del más viejo al más nuevo.',
              style: textTheme.bodyMedium?.copyWith(color: colores.textoSecundario),
            ),
          ],
          const SizedBox(height: Espaciado.lg),
          Row(
            children: [
              Expanded(
                child: CampoTexto(
                  key: const Key('campo_fecha_carga_historica'),
                  controller: w.fechaCtrl,
                  etiqueta: 'Fecha (DD/MM/AAAA)',
                  autofocus: true,
                  onSubmitted: (_) => w.onConfirmar(),
                ),
              ),
              const SizedBox(width: Espaciado.md),
              SizedBox(
                width: 160,
                child: CampoTexto(
                  key: const Key('campo_hora_carga_historica'),
                  controller: w.horaCtrl,
                  etiqueta: 'Hora (HH:MM)',
                  onSubmitted: (_) => w.onConfirmar(),
                ),
              ),
            ],
          ),
          if (w.error != null) ...[
            const SizedBox(height: Espaciado.sm),
            Text(w.error!, style: TextStyle(color: colores.error)),
          ],
          const SizedBox(height: Espaciado.lg),
          Align(
            alignment: Alignment.centerRight,
            child: BotonPrimario(texto: 'Empezar a cargar', onPressed: w.onConfirmar),
          ),
        ],
      ),
    );
  }
}

String _capitalizar(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class _Calendario extends StatelessWidget {
  const _Calendario({
    required this.mes,
    required this.elegido,
    required this.diasConCaja,
    required this.onElegir,
    required this.onMes,
  });

  final DateTime mes;
  final DateTime? elegido;
  final Set<DateTime> diasConCaja;
  final ValueChanged<DateTime> onElegir;
  final ValueChanged<DateTime> onMes;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colores = context.colores;
    final acentos = context.acentosPlazoleta;
    final diasDelMes = DateUtils.getDaysInMonth(mes.year, mes.month);
    final vacios = DateTime(mes.year, mes.month).weekday - 1;
    return Superficie(
      padding: const EdgeInsets.all(Espaciado.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_capitalizar(meses[mes.month - 1])} ${mes.year}',
                  style: textTheme.titleLarge?.copyWith(fontWeight: Pesos.fuerte),
                ),
              ),
              IconButton(
                tooltip: 'Mes anterior',
                icon: const Icon(IconosPlazoleta.chevronLeft),
                onPressed: () => onMes(DateTime(mes.year, mes.month - 1)),
              ),
              IconButton(
                tooltip: 'Mes siguiente',
                icon: const Icon(IconosPlazoleta.chevronRight),
                onPressed: () => onMes(DateTime(mes.year, mes.month + 1)),
              ),
            ],
          ),
          const SizedBox(height: Espaciado.md),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 1.25,
            children: [
              for (final l in ['L', 'M', 'X', 'J', 'V', 'S', 'D'])
                Center(child: Text(l, style: textTheme.labelMedium?.copyWith(color: colores.textoSecundario, fontWeight: Pesos.fuerte))),
              for (var i = 0; i < vacios; i++) const SizedBox.shrink(),
              for (var d = 1; d <= diasDelMes; d++)
                Builder(
                  builder: (context) {
                    final dia = DateTime(mes.year, mes.month, d);
                    final esElegido = elegido != null && DateUtils.isSameDay(elegido, dia);
                    final estado = _estadoDe(dia, diasConCaja);
                    final fondo = esElegido
                        ? colores.acento
                        : switch (estado) {
                            _EstadoDia.cargado => acentos.gananciaSuave,
                            _EstadoDia.falta => acentos.alertaSuave,
                            _EstadoDia.futuro => Colors.transparent,
                          };
                    return Presionable(
                      radio: 14,
                      color: fondo,
                      onTap: estado == _EstadoDia.futuro && !DateUtils.isSameDay(dia, DateTime.now()) ? null : () => onElegir(dia),
                      child: Center(
                        child: Text(
                          '$d',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: Pesos.fuerte,
                            color: esElegido
                                ? acentos.textoSobreColor
                                : estado == _EstadoDia.futuro
                                    ? colores.textoSecundario
                                    : null,
                          ).tabular,
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: Espaciado.md),
          Wrap(
            spacing: Espaciado.lg,
            runSpacing: Espaciado.sm,
            children: [
              _Referencia(color: acentos.gananciaSuave, texto: 'Cargado'),
              _Referencia(color: acentos.alertaSuave, texto: 'Falta cargar'),
              _Referencia(color: colores.acento, texto: 'Elegido'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Referencia extends StatelessWidget {
  const _Referencia({required this.color, required this.texto});

  final Color color;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: 14, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5))),
        const SizedBox(width: Espaciado.sm),
        Text(texto, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _AvanceDelMes extends StatelessWidget {
  const _AvanceDelMes({required this.mes, required this.diasConCaja});

  final DateTime mes;
  final Set<DateTime> diasConCaja;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final acentos = context.acentosPlazoleta;
    final hoy = DateTime.now();
    final dias = [
      for (var d = 1; d <= DateUtils.getDaysInMonth(mes.year, mes.month); d++)
        if (DateTime(mes.year, mes.month, d).isBefore(DateTime(hoy.year, hoy.month, hoy.day))) DateTime(mes.year, mes.month, d),
    ];
    final cargados = dias.where(diasConCaja.contains).length;
    return Superficie(
      padding: const EdgeInsets.symmetric(horizontal: Espaciado.xl, vertical: Espaciado.lg),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Días cargados este mes', style: textTheme.labelLarge),
                Text('$cargados de ${dias.length}', style: textTheme.headlineSmall?.copyWith(fontWeight: Pesos.fuerte).tabular),
              ],
            ),
          ),
          SizedBox(
            width: 160,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                minHeight: 10,
                value: dias.isEmpty ? 0 : cargados / dias.length,
                backgroundColor: context.colores.fondo,
                valueColor: AlwaysStoppedAnimation(acentos.ganancia),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Carga extends StatelessWidget {
  const _Carga({required this.controlador, required this.fecha});

  final CargaHistoricaControlador controlador;
  final DateTime fecha;

  Future<void> _agregarProducto(BuildContext context, Producto producto) async {
    if (producto.esVarios) {
      final monto = await mostrarDialogoMontoVarios(context);
      if (monto != null) {
        controlador.agregarProducto(producto, montoVariosCentavos: monto);
      }
    } else {
      controlador.agregarProducto(producto);
    }
    controlador.focoCampoPrincipal.requestFocus();
  }

  Future<void> _abrirMixto(BuildContext context) async {
    if (controlador.carrito.isEmpty) return;
    controlador.elegirMedio(ComposicionPago.mixto);
    final total = controlador.resultado!.totalCentavos;
    final confirmado = await mostrarDialogoMixto(context, totalCentavos: total);
    if (confirmado != null) controlador.confirmarMixto(confirmado.monto);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cargando el ${_fechaCorta(fecha)}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: Espaciado.md),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 320,
                child: _ColumnaBusqueda(
                  controlador: controlador,
                  onAgregar: (p) => _agregarProducto(context, p),
                ),
              ),
              const SizedBox(width: Espaciado.md),
              Expanded(child: _ColumnaCarrito(controlador: controlador)),
              const SizedBox(width: Espaciado.md),
              SizedBox(
                width: 320,
                child: _ColumnaCobro(
                  controlador: controlador,
                  onMixto: () => _abrirMixto(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ColumnaBusqueda extends StatelessWidget {
  const _ColumnaBusqueda({required this.controlador, required this.onAgregar});

  final CargaHistoricaControlador controlador;
  final ValueChanged<Producto> onAgregar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Superficie(
          child: TextField(
            // Key propia: desde que `EnvolturaConNavbarSuperior` suma su
            // propia `BarraBusquedaGlobal` en la franja superior de TODA
            // pantalla de gestión (El dueño, tercera pasada de venta: "quiero
            // que la barra de busqueda este en todos lados"), esta pantalla
            // ya no tiene el único `TextField` del árbol — `find.byType(
            // TextField).first` dejó de ser inequívoco.
            key: const Key('campo_busqueda_carga_historica'),
            controller: controlador.campoTexto,
            focusNode: controlador.focoCampoPrincipal,
            decoration: const InputDecoration(
              labelText: 'Buscar producto (código, nombre, o "200 queso")',
            ),
            onSubmitted: (_) {
              if (controlador.coincidencias.isNotEmpty) {
                onAgregar(controlador.coincidencias.first);
              }
            },
          ),
        ),
        if (controlador.avisoBusqueda != null)
          Padding(
            padding: const EdgeInsets.only(top: Espaciado.xs),
            child: Text(
              controlador.avisoBusqueda!,
              style: TextStyle(color: context.colores.error),
            ),
          ),
        const SizedBox(height: Espaciado.sm),
        if (controlador.coincidencias.isNotEmpty)
          Expanded(
            child: Superficie(
              child: Material(
                type: MaterialType.transparency,
                child: ListView.builder(
                  itemCount: controlador.coincidencias.length,
                  itemBuilder: (context, i) {
                    final p = controlador.coincidencias[i];
                    return ListTile(
                      dense: true,
                      title: Text(p.nombre),
                      trailing: Text(
                        p.esVarios
                            ? '—'
                            : p.esPesable
                            ? '${formatearARS(p.precioPorKiloCentavos ?? 0)}/kg'
                            : formatearARS(p.precioCentavos ?? 0),
                      ),
                      onTap: () => onAgregar(p),
                    );
                  },
                ),
              ),
            ),
          )
        else if (controlador.mostrarSinCoincidencias)
          Expanded(
            child: Center(
              child: Text(
                'Sin productos que coincidan. Cargalo primero en Productos.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.colores.textoSecundario),
              ),
            ),
          )
        else
          const Spacer(),
      ],
    );
  }
}

class _ColumnaCarrito extends StatelessWidget {
  const _ColumnaCarrito({required this.controlador});

  final CargaHistoricaControlador controlador;

  @override
  Widget build(BuildContext context) {
    if (controlador.carrito.isEmpty) {
      return Superficie(
        child: Center(
          child: Text(
            'Carrito vacío — buscá un producto a la izquierda.',
            style: TextStyle(color: context.colores.textoSecundario),
          ),
        ),
      );
    }
    return Superficie(
      child: Material(
        type: MaterialType.transparency,
        child: ListView.builder(
          itemCount: controlador.carrito.length,
          itemBuilder: (context, i) {
            final linea = controlador.carrito[i];
            final esUnidad = linea is LineaVentaPorUnidad;
            final valorActual = switch (linea) {
              LineaVentaPorUnidad(:final cantidad) => cantidad,
              LineaVentaPesable(:final gramos) => gramos,
            };
            return ListTile(
              dense: true,
              title: Text(linea.nombreProducto),
              subtitle: Text(esUnidad ? 'x$valorActual' : '$valorActual g'),
              onTap: () async {
                final nuevo = await mostrarDialogoEditarCantidad(
                  context,
                  titulo: esUnidad ? 'Cantidad' : 'Gramos',
                  valorActual: valorActual,
                  linea: linea,
                );
                if (nuevo == null) return;
                if (esUnidad) {
                  controlador.editarCantidadExacta(i, nuevo);
                } else {
                  controlador.editarGramosExacto(i, nuevo);
                }
              },
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(formatearARS(linea.subtotalCentavos)),
                  IconButton(
                    icon: const Icon(IconosPlazoleta.deleteOutline, size: 18),
                    onPressed: () => controlador.eliminarLinea(i),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ColumnaCobro extends StatelessWidget {
  const _ColumnaCobro({required this.controlador, required this.onMixto});

  final CargaHistoricaControlador controlador;
  final VoidCallback onMixto;

  @override
  Widget build(BuildContext context) {
    final resultado = controlador.resultado;
    final totalActual =
        resultado?.totalCentavos ?? controlador.subtotalCentavos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Superficie(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Medio de pago (solo etiqueta, no cobra de verdad)',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: Espaciado.sm),
              Row(
                children: [
                  Expanded(
                    child: _BotonMedio(
                      texto: 'Efectivo',
                      seleccionado:
                          controlador.medioElegido == ComposicionPago.efectivo,
                      onPressed: () =>
                          controlador.elegirMedio(ComposicionPago.efectivo),
                    ),
                  ),
                  const SizedBox(width: Espaciado.xs),
                  Expanded(
                    child: _BotonMedio(
                      texto: 'Mercado Pago',
                      seleccionado:
                          controlador.medioElegido == ComposicionPago.virtual,
                      onPressed: () =>
                          controlador.elegirMedio(ComposicionPago.virtual),
                    ),
                  ),
                  const SizedBox(width: Espaciado.xs),
                  Expanded(
                    child: _BotonMedio(
                      texto: 'Mixto',
                      seleccionado:
                          controlador.medioElegido == ComposicionPago.mixto,
                      onPressed: onMixto,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Espaciado.md),
              Text(
                'Total: ${formatearARS(totalActual)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: Espaciado.sm),
              BotonPrimario(
                texto: 'Agregar venta',
                onPressed: controlador.carrito.isEmpty
                    ? null
                    : () => controlador.agregarVentaALaTanda(),
              ),
              if (controlador.error != null) ...[
                const SizedBox(height: Espaciado.sm),
                Text(
                  controlador.error!,
                  style: TextStyle(color: context.colores.error),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Espaciado.md),
        Expanded(
          child: Superficie(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ventas cargadas — total ${formatearARS(controlador.totalTandaCentavos)}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: Espaciado.sm),
                Expanded(
                  child: controlador.ventasCargadas.isEmpty
                      ? Center(
                          child: Text(
                            'Todavía no agregaste ninguna venta.',
                            style: TextStyle(
                              color: context.colores.textoSecundario,
                            ),
                          ),
                        )
                      : Material(
                          type: MaterialType.transparency,
                          child: ListView.builder(
                            itemCount: controlador.ventasCargadas.length,
                            itemBuilder: (context, i) {
                              final v = controlador.ventasCargadas[i];
                              return ListTile(
                                dense: true,
                                title: Text(v.descripcion),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(formatearARS(v.totalCentavos)),
                                    IconButton(
                                      icon: const Icon(IconosPlazoleta.close, size: 16),
                                      onPressed: () =>
                                          controlador.quitarVentaDeLaTanda(i),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BotonMedio extends StatelessWidget {
  const _BotonMedio({
    required this.texto,
    required this.seleccionado,
    required this.onPressed,
  });

  final String texto;
  final bool seleccionado;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return seleccionado
        ? BotonPrimario(texto: texto, onPressed: onPressed)
        : BotonSecundario(texto: texto, onPressed: onPressed);
  }
}

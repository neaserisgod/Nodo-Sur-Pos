// "Separaciones" — rediseño sobre el mock de Bruno (2026-09-26, después de
// una tabla de ocho columnas que "se ve nefasto, tenés que mover mucho la
// cabeza para leerlo"). Todo se lee de arriba a abajo dentro de una
// tarjeta, nunca a lo ancho de la pantalla:
//
// - Arriba, tres tarjetas de caja: Efectivo, Mercado Pago y Total — cobrado
//   hoy, cuánto separar (grande) y cuánto te queda.
// - Una tarjeta por proveedor, de mayor a menor: cuánto separar y de qué
//   caja (dos chips). El tilde la marca separada (queda apagada, borde de
//   acento); destildarla lo deshace.
// - Al final, una tarjeta de progreso: cuántos van, cuánto falta por caja,
//   "Marcar todo" / "Desmarcar todo".
//
// "Lo vendido" muestra, con el mismo esquema, vendido / costo / ganancia de
// hoy, la semana o el mes. Sin "Pagar" a propósito (Bruno: "innecesario")
// — pagar sigue en Proveedores → Avanzado.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/repositorio_reposicion.dart' show SeparacionDelDia;
import '../../domain/dinero.dart';
import '../../domain/modulos.dart';
import '../../servicios/modulos_activos.dart';
import '../../domain/periodo.dart';
import '../comun/armazon_gestion.dart';
import '../navegacion/busqueda_contextual.dart';
import '../navegacion/refresco_por_celular.dart';
import '../comun/tarjetas.dart';
import '../comun/estado_vacio.dart';
import '../navegacion/route_observer.dart';
import '../tema/acentos.dart';
import '../tema/iconos.dart';
import '../tema/presionable.dart';
import '../tema/tema.dart';
import '../tema/tokens.dart';
import 'dialogo_ganancia_proveedor.dart';
import 'dialogo_sin_costo.dart';
import 'separaciones_controlador.dart';

/// Cada cuánto se recarga sola mientras está abierta — las ventas y cambios
/// que llegan del celular por la sincronización no avisan a las pantallas
/// del escritorio (Bruno, 2026-09-26: "como si tuviese que abrir y cerrar
/// para que aparezca"). La base es chica: recargar cuesta nada.
const _intervaloRecarga = Duration(seconds: 15);

const double _anchoMaximoTarjeta = 340;
const double _altoTarjeta = 232;

class PantallaSeparaciones extends StatefulWidget {
  const PantallaSeparaciones({
    super.key,
    required this.db,
    required this.usuarioId,
    required this.sesionCajaId,
  });

  final AppDatabase db;
  final int usuarioId;
  final int? sesionCajaId;

  @override
  State<PantallaSeparaciones> createState() => _PantallaSeparacionesState();
}

class _PantallaSeparacionesState extends State<PantallaSeparaciones>
    with RouteAware, RefrescoPorCelular {
  @override
  void alCambiarDesdeElCelular() => _c.cargarTodo();

  late final _c = SeparacionesControlador(
    widget.db,
    usuarioId: widget.usuarioId,
    sesionCajaId: widget.sesionCajaId,
  )..cargarTodo();
  late final Timer _recarga = Timer.periodic(
    _intervaloRecarga,
    (_) => _c.cargarTodo(),
  );

  @override
  void initState() {
    super.initState();
    _recarga; // arranca el timer
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ruta = ModalRoute.of(context);
    if (ruta is PageRoute<dynamic>) routeObserver.subscribe(this, ruta);
  }

  /// Volver desde otra pantalla (ej. Proveedores, después de cargar un costo)
  /// recarga en el momento, sin esperar el timer.
  @override
  void didPopNext() => _c.cargarTodo();

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _recarga.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SeparacionesControlador>.value(
      value: _c,
      child: Consumer<SeparacionesControlador>(
        builder: (context, c, _) => PantallaGestion(
          db: widget.db,
          claveActiva: 'separaciones',
          usuarioId: widget.usuarioId,
          sesionCajaId: widget.sesionCajaId,
          titulo: 'Separaciones',
          busqueda: BusquedaContextual(pista: 'Buscar un proveedor…', alCambiar: c.buscar),
          subtitulo: _subtitulo(c),
          accion: _Selectores(controlador: c),
          child: c.cargando
              ? const SizedBox.shrink()
              : c.vista == VistaSeparaciones.queSeparar
              ? const _VistaQueSeparar()
              : const _VistaLoVendido(),
        ),
      ),
    );
  }
}

String _plata(int centavos) => formatearARS(centavos);

const _dias = [
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo',
];
const _meses = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

String _fechaLarga(DateTime f) =>
    '${_dias[f.weekday - 1]} ${f.day} de ${_meses[f.month - 1]}';

String _subtitulo(SeparacionesControlador c) {
  final hoy = DateTime.now();
  if (c.vista == VistaSeparaciones.queSeparar ||
      c.periodo == PeriodoResumen.hoy) {
    return 'Hoy · ${_fechaLarga(hoy)}';
  }
  final inicio = inicioDePeriodo(c.periodo, hoy)!;
  return c.periodo == PeriodoResumen.semana
      ? 'Esta semana · desde el ${_fechaLarga(inicio)}'
      : 'Este mes · ${_meses[hoy.month - 1]}';
}

// ─── Selectores (arriba a la derecha) ──────────────────────────────────────

class _Selectores extends StatelessWidget {
  const _Selectores({required this.controlador});

  final SeparacionesControlador controlador;

  @override
  Widget build(BuildContext context) {
    final c = controlador;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GrupoPildoras<VistaSeparaciones>(
          opciones: const [
            (VistaSeparaciones.queSeparar, 'Qué separar'),
            (VistaSeparaciones.loVendido, 'Lo vendido'),
          ],
          elegida: c.vista,
          oscura: true,
          onElegir: c.cambiarVista,
        ),
        if (c.vista == VistaSeparaciones.loVendido) ...[
          const SizedBox(width: Espaciado.md),
          GrupoPildoras<PeriodoResumen>(
            opciones: const [
              (PeriodoResumen.hoy, 'Hoy'),
              (PeriodoResumen.semana, 'Semana'),
              (PeriodoResumen.mes, 'Mes'),
            ],
            elegida: c.periodo,
            oscura: false,
            onElegir: c.cambiarPeriodo,
          ),
        ],
      ],
    );
  }
}

// ─── Qué separar ───────────────────────────────────────────────────────────

class _VistaQueSeparar extends StatelessWidget {
  const _VistaQueSeparar();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SeparacionesControlador>();
    final acentos = context.acentosPlazoleta;
    final tarjetas = c.tarjetasVisibles;
    final avisos = [
      if (c.ajuste.corridoAMpCentavos > 0)
        'No alcanza el efectivo del cajón: ${_plata(c.ajuste.corridoAMpCentavos)} se separan de Mercado Pago.',
      if (c.ajuste.corridoAMpCentavos < 0)
        'No alcanza Mercado Pago: ${_plata(-c.ajuste.corridoAMpCentavos)} se separan del cajón.',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _TarjetaCaja(
                titulo: 'Efectivo',
                colorPunto: acentos.dinero,
                cobrado: c.cobrado.efectivoCentavos,
                separar: c.separarEfectivoCentavos,
                queda: c.quedaEfectivoCentavos,
                lata: c.cobrado.cigarrillosCentavos,
              ),
            ),
            const SizedBox(width: Espaciado.md),
            Expanded(
              child: _TarjetaCaja(
                titulo: 'Mercado Pago',
                colorPunto: acentos.qr,
                cobrado: c.cobrado.mpCentavos,
                separar: c.separarMpCentavos,
                queda: c.quedaMpCentavos,
              ),
            ),
            const SizedBox(width: Espaciado.md),
            Expanded(
              child: _TarjetaCaja(
                titulo: 'Total',
                cobrado: c.cobrado.efectivoCentavos + c.cobrado.mpCentavos,
                separar: c.separarEfectivoCentavos + c.separarMpCentavos,
                queda: c.quedaEfectivoCentavos + c.quedaMpCentavos,
                lata: c.cobrado.cigarrillosCentavos,
                invertida: true,
              ),
            ),
          ],
        ),
        for (final aviso in avisos) ...[
          const SizedBox(height: Espaciado.sm),
          Text(
            aviso,
            style: TextStyle(
              color: context.colores.textoSecundario,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (c.vendidoSinCostoHoyCentavos > 0) ...[
          const SizedBox(height: Espaciado.sm),
          _AvisoSinCosto(
            claveTocable: const Key('aviso_sin_costo'),
            texto:
                'Hoy se vendieron ${_plata(c.vendidoSinCostoHoyCentavos)} sin costo cargado: no entran acá.',
            onTap: () => mostrarDialogoSinCosto(
              context,
              usuarioId: c.usuarioId,
              alGuardar: c.cargarTodo,
              db: c.db,
              desde: c.inicioDeHoy,
              periodo: 'hoy',
            ),
          ),
        ],
        if (c.ajuste.faltanteCentavos > 0) ...[
          const SizedBox(height: Espaciado.sm),
          Text(
            'No alcanza entre las dos cajas: faltan ${_plata(c.ajuste.faltanteCentavos)}.',
            key: const Key('aviso_faltante'),
            style: TextStyle(
              color: context.colores.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: Espaciado.md),
        Expanded(
          child: tarjetas.isEmpty
              ? EstadoVacio(mensaje: c.busqueda.isEmpty ? 'Hoy no hay nada para separar' : 'Ningún proveedor coincide con "${c.busqueda}"')
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: _anchoMaximoTarjeta,
                    mainAxisExtent: _altoTarjeta,
                    mainAxisSpacing: Espaciado.md,
                    crossAxisSpacing: Espaciado.md,
                  ),
                  itemCount: tarjetas.length + 1,
                  itemBuilder: (context, i) => i == tarjetas.length
                      ? const _TarjetaProgreso()
                      : _TarjetaProveedor(tarjeta: tarjetas[i]),
                ),
        ),
      ],
    );
  }
}

/// Aviso de lo vendido sin costo, con "Ver cuáles" — abre la lista de
/// productos (`dialogo_sin_costo.dart`).
class _AvisoSinCosto extends StatelessWidget {
  const _AvisoSinCosto({
    this.claveTocable,
    required this.texto,
    required this.onTap,
    this.chico = false,
  });

  /// Va en lo que se toca (el texto), no en el renglón entero — el renglón
  /// ocupa todo el ancho y tocarlo al medio no abre nada.
  final Key? claveTocable;
  final String texto;
  final VoidCallback onTap;

  /// La versión de una línea dentro de una tarjeta.
  final bool chico;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final base =
        (chico
                ? Theme.of(context).textTheme.bodySmall
                : Theme.of(context).textTheme.bodyMedium)
            ?.copyWith(
              color: colores.textoSecundario,
              fontWeight: chico ? null : FontWeight.w600,
            );
    return Align(
      alignment: Alignment.centerLeft,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: claveTocable,
          onTap: onTap,
          child: Text.rich(
            TextSpan(
              text: '$texto ',
              style: base,
              children: [
                TextSpan(
                  text: 'Ver cuáles',
                  style: base?.copyWith(
                    color: colores.acento,
                    fontWeight: FontWeight.w400,
                    decoration: TextDecoration.underline,
                    decorationColor: colores.acento,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta de caja de arriba: cobrado a la derecha del título, cuánto
/// separar en una caja destacada, y cuánto te queda abajo.
class _TarjetaCaja extends StatelessWidget {
  const _TarjetaCaja({
    required this.titulo,
    required this.cobrado,
    required this.separar,
    required this.queda,
    this.colorPunto,
    this.lata = 0,
    this.invertida = false,
  });

  final String titulo;
  final Color? colorPunto;
  final int cobrado;
  final int separar;
  final int queda;

  /// Lo que se lleva la lata al cierre — se resta de "te queda" del
  /// efectivo; se muestra para que la cuenta cierre a la vista.
  final int lata;

  /// La del total: la caja destacada en el color inverso.
  final bool invertida;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final fondoCaja = invertida
        ? colores.textoPrimario
        : (colorPunto ?? colores.acento).withValues(alpha: 0.12);
    final textoCaja = invertida ? colores.fondo : colores.textoPrimario;

    return Container(
      padding: const EdgeInsets.all(Espaciado.lg),
      decoration: BoxDecoration(
        color: colores.fondoBloque,
        borderRadius: BorderRadius.circular(radioSuperficieEscritorio),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: colorPunto ?? colores.textoPrimario,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: Espaciado.sm),
              Expanded(
                child: Text(
                  titulo,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                'Cobrado ',
                style: textTheme.bodyMedium?.copyWith(
                  color: colores.textoSecundario,
                ),
              ),
              Text(
                _plata(cobrado),
                style: textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)
                    .tabular,
              ),
            ],
          ),
          const SizedBox(height: Espaciado.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Espaciado.lg,
              vertical: Espaciado.md,
            ),
            decoration: BoxDecoration(
              color: fondoCaja,
              borderRadius: BorderRadius.circular(radioControlEscritorio),
            ),
            child: Row(
              children: [
                Text(
                  'Separar',
                  style: textTheme.bodyMedium?.copyWith(
                    color: textoCaja,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: Espaciado.md),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      _plata(separar),
                      style: textTheme.headlineMedium
                          ?.copyWith(
                            color: textoCaja,
                            fontWeight: FontWeight.w800,
                          )
                          .tabular,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Espaciado.md),
          // Siempre ocupa su lugar (invisible si no hay lata), para que las
          // tres tarjetas de caja midan lo mismo.
          Visibility(
            visible: lata > 0,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: Row(
              children: [
                Text(
                  'Se lleva la lata',
                  style: textTheme.bodySmall?.copyWith(
                    color: colores.textoSecundario,
                  ),
                ),
                const Spacer(),
                Text(
                  '− ${_plata(lata)}',
                  style: textTheme.bodySmall
                      ?.copyWith(color: colores.textoSecundario)
                      .tabular,
                ),
              ],
            ),
          ),
          Row(
            children: [
              Text(
                'Te queda',
                style: textTheme.bodyMedium?.copyWith(
                  color: colores.textoSecundario,
                ),
              ),
              const Spacer(),
              Text(
                _plata(queda),
                style: textTheme.titleLarge
                    ?.copyWith(
                      color: queda < 0 ? colores.error : context.acentosPlazoleta.ganancia,
                      fontWeight: FontWeight.w800,
                    )
                    .tabular,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Un proveedor: nombre y tilde arriba, cuánto separar, y de qué caja.
class _TarjetaProveedor extends StatelessWidget {
  const _TarjetaProveedor({required this.tarjeta});

  final TarjetaSeparacion tarjeta;

  @override
  Widget build(BuildContext context) {
    final c = context.read<SeparacionesControlador>();
    final procesando = context.select<SeparacionesControlador, bool>(
      (c) => c.procesando.contains(tarjeta.proveedorId),
    );
    final colores = context.colores;
    final acentos = context.acentosPlazoleta;
    final textTheme = Theme.of(context).textTheme;
    final t = tarjeta;
    final apagada = t.separada;
    final colorTexto = apagada ? colores.textoTenue : colores.textoPrimario;
    final yaSeparadoAntes = !t.separada && t.fila.separadoHoyCentavos > 0;

    return Container(
      decoration: BoxDecoration(
        color: apagada
            ? colores.fondoBloque.withValues(alpha: 0.55)
            : colores.fondoBloque,
        borderRadius: BorderRadius.circular(radioSuperficieEscritorio),
        // Separada: borde verde de "hecho", como en el mock; sin separar,
        // tarjeta plana sin borde (lenguaje de 2026-09-26).
        border: apagada ? Border.all(color: context.acentosPlazoleta.ganancia.withValues(alpha: 0.8), width: 2) : null,
      ),
      child: Presionable(
        radio: radioSuperficieEscritorio,
        onTap: procesando || t.bloqueada ? null : () => c.alternar(t),
        child: Padding(
          padding: const EdgeInsets.all(Espaciado.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      t.fila.nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorTexto,
                      ),
                    ),
                  ),
                  const SizedBox(width: Espaciado.sm),
                  _Tilde(marcado: t.separada, bloqueado: t.bloqueada),
                ],
              ),
              const SizedBox(height: Espaciado.sm),
              Text(
                t.bloqueada
                    ? 'Separado — ya pagado'
                    : (t.separada ? 'Separado' : 'A separar'),
                style: textTheme.bodySmall?.copyWith(
                  color: colores.textoSecundario,
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _plata(t.totalCentavos),
                  style: textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800, color: colorTexto)
                      .tabular,
                ),
              ),
              if (yaSeparadoAntes)
                Text(
                  'Ya separado hoy ${_plata(t.fila.separadoHoyCentavos)}',
                  style: textTheme.bodySmall?.copyWith(
                    color: colores.textoSecundario,
                  ),
                ),
              const Spacer(),
              _Chip(
                etiqueta: 'Efectivo',
                color: acentos.dinero,
                monto: t.efectivoCentavos,
                apagado: apagada,
              ),
              const SizedBox(height: Espaciado.xs),
              _Chip(
                etiqueta: 'Mercado Pago',
                color: acentos.qr,
                monto: t.mpCentavos,
                apagado: apagada,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tilde extends StatelessWidget {
  const _Tilde({required this.marcado, required this.bloqueado});

  final bool marcado;
  final bool bloqueado;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: marcado
            ? context.acentosPlazoleta.ganancia.withValues(alpha: bloqueado ? 0.45 : 1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: marcado ? Colors.transparent : colores.textoTenue,
          width: 2,
        ),
      ),
      child: marcado
          ? Icon(IconosPlazoleta.check, size: 24, color: context.acentosPlazoleta.textoSobreColor)
          : null,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.etiqueta,
    required this.color,
    required this.monto,
    this.apagado = false,
  });

  final String etiqueta;
  final Color color;
  final int monto;
  final bool apagado;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Espaciado.md,
        vertical: Espaciado.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: apagado ? 0.06 : 0.13),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color.withValues(alpha: apagado ? 0.5 : 1),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: Espaciado.sm),
          Expanded(
            child: Text(
              etiqueta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(
                color: apagado ? colores.textoTenue : colores.textoSecundario,
              ),
            ),
          ),
          const SizedBox(width: Espaciado.sm),
          _MontoQueSeAchica(
            texto: _plata(monto),
            estilo: textTheme.titleSmall
                ?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: apagado ? colores.textoTenue : colores.textoPrimario,
                )
                .tabular,
          ),
        ],
      ),
    );
  }
}

/// Un monto que se achica antes que cortarse o desbordar, si la tarjeta es
/// angosta o el número es muy largo — nunca un "$1.2…" truncado.
class _MontoQueSeAchica extends StatelessWidget {
  const _MontoQueSeAchica({required this.texto, required this.estilo});

  final String texto;
  final TextStyle? estilo;

  @override
  Widget build(BuildContext context) => Flexible(
    flex: 0,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Text(texto, style: estilo),
    ),
  );
}

/// Última tarjeta: cuántos van, cuánto falta por caja, y marcar/desmarcar
/// todo.
class _TarjetaProgreso extends StatelessWidget {
  const _TarjetaProgreso();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SeparacionesControlador>();
    final colores = context.colores;
    final acentos = context.acentosPlazoleta;
    final textTheme = Theme.of(context).textTheme;
    final total = c.tarjetas.length;
    final hechas = c.cantidadSeparadas;
    final fondo = colores.textoPrimario;
    final texto = colores.fondo;

    Widget fila(String etiqueta, Color punto, int monto) => Padding(
      padding: const EdgeInsets.only(top: Espaciado.xs),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: punto, shape: BoxShape.circle),
          ),
          const SizedBox(width: Espaciado.sm),
          Expanded(
            child: Text(
              etiqueta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(color: texto),
            ),
          ),
          const SizedBox(width: Espaciado.sm),
          _MontoQueSeAchica(
            texto: _plata(monto),
            estilo: textTheme.titleMedium
                ?.copyWith(color: texto, fontWeight: FontWeight.w800)
                .tabular,
          ),
        ],
      ),
    );

    Widget boton(
      String etiqueta,
      VoidCallback? onTap, {
      required bool relleno,
    }) => Expanded(
      child: Presionable(
        radio: radioControlEscritorio,
        onTap: onTap,
        color: relleno && onTap != null ? texto : Colors.transparent,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radioControlEscritorio),
            border: Border.all(
              color: texto.withValues(alpha: onTap == null ? 0.25 : 0.6),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: Espaciado.sm),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              etiqueta,
              style: textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: onTap == null
                    ? texto.withValues(alpha: 0.4)
                    : (relleno ? fondo : texto),
              ),
            ),
          ),
        ),
      ),
    );

    final libre = c.procesando.isEmpty;
    return Container(
      padding: const EdgeInsets.all(Espaciado.lg),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(radioSuperficieEscritorio),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$hechas de $total separados',
            key: const Key('progreso_separados'),
            style: textTheme.titleMedium?.copyWith(
              color: texto,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: Espaciado.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : hechas / total,
              minHeight: 8,
              backgroundColor: texto.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(acentos.ganancia),
            ),
          ),
          const SizedBox(height: Espaciado.md),
          Text(
            'Falta separar',
            style: textTheme.bodySmall?.copyWith(
              color: texto.withValues(alpha: 0.7),
            ),
          ),
          fila('Efectivo', acentos.dinero, c.faltaEfectivoCentavos),
          fila('Mercado Pago', acentos.qr, c.faltaMpCentavos),
          const Spacer(),
          Row(
            children: [
              boton(
                'Marcar todo',
                libre && c.hayPorSeparar ? c.marcarTodo : null,
                relleno: true,
              ),
              const SizedBox(width: Espaciado.sm),
              boton(
                'Desmarcar todo',
                libre && c.hayParaDesmarcar ? c.desmarcarTodo : null,
                relleno: false,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Lo vendido ────────────────────────────────────────────────────────────

class _VistaLoVendido extends StatelessWidget {
  const _VistaLoVendido();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<SeparacionesControlador>();
    final acentos = context.acentosPlazoleta;
    final vendidos = c.vendidosVisibles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _TarjetaCifra(
                titulo: 'Vendido',
                monto: c.vendidoCentavos,
                colorPunto: acentos.qr,
              ),
            ),
            const SizedBox(width: Espaciado.md),
            Expanded(
              child: _TarjetaCifra(
                titulo: 'Reposición (costo)',
                monto: c.costoCentavos,
                colorPunto: acentos.dinero,
              ),
            ),
            const SizedBox(width: Espaciado.md),
            Expanded(
              child: _TarjetaCifra(
                titulo: 'Ganancia',
                monto: c.gananciaCentavos,
                invertida: true,
              ),
            ),
          ],
        ),
        if (c.vendidoSinCostoCentavos > 0) ...[
          const SizedBox(height: Espaciado.sm),
          _AvisoSinCosto(
            claveTocable: const Key('aviso_sin_costo'),
            texto:
                'Vendido incluye ${_plata(c.vendidoSinCostoCentavos)} sin costo cargado: '
                'no suma a la reposición ni a la ganancia.',
            onTap: () => mostrarDialogoSinCosto(
              context,
              usuarioId: c.usuarioId,
              alGuardar: c.cargarTodo,
              db: c.db,
              desde: c.inicioDelPeriodo,
              periodo: c.nombrePeriodo,
            ),
          ),
        ],
        const SizedBox(height: Espaciado.md),
        Expanded(
          child: vendidos.isEmpty
              ? EstadoVacio(mensaje: c.busqueda.isEmpty ? 'No hay ventas en este período' : 'Ningún proveedor coincide con "${c.busqueda}"')
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: _anchoMaximoTarjeta,
                    mainAxisExtent: _altoTarjeta,
                    mainAxisSpacing: Espaciado.md,
                    crossAxisSpacing: Espaciado.md,
                  ),
                  itemCount: vendidos.length,
                  itemBuilder: (context, i) =>
                      _TarjetaVendido(fila: vendidos[i]),
                ),
        ),
      ],
    );
  }
}

class _TarjetaCifra extends StatelessWidget {
  const _TarjetaCifra({
    required this.titulo,
    required this.monto,
    this.colorPunto,
    this.invertida = false,
  });

  final String titulo;
  final int monto;
  final Color? colorPunto;
  final bool invertida;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final texto = invertida ? colores.fondo : colores.textoPrimario;
    return Container(
      padding: const EdgeInsets.all(Espaciado.lg),
      decoration: BoxDecoration(
        color: invertida ? colores.textoPrimario : colores.fondoBloque,
        borderRadius: BorderRadius.circular(radioSuperficieEscritorio),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: colorPunto ?? colores.acento,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: Espaciado.sm),
              Text(
                titulo,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: texto,
                ),
              ),
            ],
          ),
          const SizedBox(height: Espaciado.md),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _plata(monto),
              style: textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800, color: texto)
                  .tabular,
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaVendido extends StatelessWidget {
  const _TarjetaVendido({required this.fila});

  final SeparacionDelDia fila;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final acentos = context.acentosPlazoleta;
    final textTheme = Theme.of(context).textTheme;
    final f = fila;
    final proveedor = f.proveedor;
    // Tocar la tarjeta abre la ganancia de ese proveedor para retenerla o
    // retirarla (antes en Reportes). "Sin proveedor" no tiene a quién.
    return Container(
      decoration: BoxDecoration(
        color: colores.fondoBloque,
        borderRadius: BorderRadius.circular(radioSuperficieEscritorio),
      ),
      child: Presionable(
        radio: radioSuperficieEscritorio,
        onTap: proveedor == null || !moduloActivo(Modulo.retiroGanancias)
            ? null
            : () => mostrarDialogoGananciaProveedor(
                context,
                controlador: context.read<SeparacionesControlador>(),
                proveedorId: proveedor.id,
              ),
        child: Padding(
          padding: const EdgeInsets.all(Espaciado.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                f.nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Espaciado.sm),
              Text(
                'Vendido',
                style: textTheme.bodySmall?.copyWith(
                  color: colores.textoSecundario,
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _plata(f.vendidoCentavos),
                  style: textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800)
                      .tabular,
                ),
              ),
              if (f.vendidoSinCostoCentavos > 0)
                Builder(
                  builder: (context) {
                    final c = context.read<SeparacionesControlador>();
                    return _AvisoSinCosto(
                      texto:
                          'incluye ${_plata(f.vendidoSinCostoCentavos)} sin costo',
                      chico: true,
                      onTap: () => mostrarDialogoSinCosto(
                        context,
                        usuarioId: c.usuarioId,
                        alGuardar: c.cargarTodo,
                        db: c.db,
                        desde: c.inicioDelPeriodo,
                        periodo: c.nombrePeriodo,
                        soloProveedor: f.proveedor?.nombre,
                      ),
                    );
                  },
                ),
              const Spacer(),
              _Chip(
                etiqueta: 'Costo',
                color: acentos.dinero,
                monto: f.costoCentavos,
              ),
              const SizedBox(height: Espaciado.xs),
              _Chip(
                etiqueta: 'Ganancia',
                color: acentos.ganancia,
                monto: f.gananciaCentavos,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

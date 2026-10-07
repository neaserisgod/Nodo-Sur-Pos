// Cierre de caja, hecho desde cero como el mock v4 (`SCR.cierre` / `drawCierre`, 2026-10-06): pantalla completa sin la
// barra de navegación (`nonav`), en dos pasos y un final.
//
// - Paso 1: "¿Cuánta plata hay en cada caja?". Se cuentan a ciegas, juntas, las tres cajas: efectivo, Mercado Pago y la
//   lata (con el módulo de caja aparte). Ni un número esperado existe todavía en el árbol de widgets (Regla 10 — no
//   alcanza con taparlos). Los chips "Cuadra justo / $ 250.000" del mock son datos de demostración y no están: sugerir
//   el esperado rompería contar a ciegas. Lo que sí está es la precarga del último arqueo (cuando esa caja no se movió).
// - Paso 2: la diferencia del cajón en grande, Mercado Pago, la lata y el redondeo, de qué sale lo que tendría que haber,
//   y a la derecha lo que dice Mercado Pago y qué separar por proveedor. Para corregir lo contado se vuelve al paso 1
//   ("Volver a contar"), con lo escrito tal cual.
// - Cerrada: la tilde, lo vendido y ganado, y seguir (o reabrir).
//
// Antes era un `Modal` encima de la venta (fase de turnos, 2026-09-12); el mock v4 del dueño (2026-10-05) es más nuevo
// y lo vuelve pantalla completa. Se abre con [abrirCierre].

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/repositorio_arqueo_intermedio.dart' show ArqueoDelTurno;
import '../../data/repositorio_carga_historica.dart' show ResumenDiaHistorico;
import '../../data/repositorio_cierre.dart' show ResumenCierre;
import '../../data/repositorio_conciliacion_mp.dart' show LeerCobrosMp;
import '../../domain/modulos.dart';
import '../../servicios/modulos_activos.dart';
import '../comun/fechas.dart';
import '../kit/kit.dart';
import '../separaciones/dialogo_sin_costo.dart';
import 'cierre_controlador.dart';
import 'dialogo_faltante.dart';
import 'dialogo_reabrir_sesion.dart';
import 'saldo_mp_vista.dart';
import 'seccion_mp_real.dart';

/// Abre el cierre como pantalla completa (sin barra), con un fundido. Lo usan los cuatro lugares que cierran la caja:
/// "Caja ▾", Venta (cerrar y cambiar de turno, y la sesión de un día anterior) y cerrar la ventana con la caja abierta.
Future<void> abrirCierre(BuildContext context, {required WidgetBuilder builder}) {
  final animar = hayMovimiento(context);
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      settings: const RouteSettings(name: 'cierre'),
      transitionDuration: animar ? ms(260) : Duration.zero,
      reverseTransitionDuration: animar ? ms(200) : Duration.zero,
      pageBuilder: (context, _, _) => builder(context),
      transitionsBuilder: (context, animacion, _, hijo) =>
          FadeTransition(opacity: CurvedAnimation(parent: animacion, curve: curvaEase), child: hijo),
    ),
  );
}

class PantallaCierre extends StatefulWidget {
  const PantallaCierre({
    super.key,
    required this.db,
    required this.sesionId,
    required this.usuarioId,
    this.onFinalizado,
    this.textoBotonFinal = 'Volver a Venta',
    this.textoVolver = 'Volver',
    this.leerCobrosMp,
  });

  /// Solo para tests: de dónde salen los cobros reales de Mercado Pago (por defecto, la cuenta de Nodo Sur de la PC).
  final LeerCobrosMp? leerCobrosMp;

  final AppDatabase db;
  final int sesionId;
  final int usuarioId;

  /// Se llama cuando ya no hay nada más que hacer acá (cerró sin reabrir). Si es null, la pantalla vuelve con `pop` —
  /// ver `pantalla_venta.dart` para el cierre voluntario y el cambio de turno.
  final VoidCallback? onFinalizado;

  /// Texto del botón principal de la caja cerrada — "Volver a Venta" para un cierre normal, "Abrir para el que entra"
  /// en un cambio de turno, "Cerrar el sistema" al cerrar la ventana.
  final String textoBotonFinal;

  /// El botón de arriba a la derecha de los pasos 1 y 2, que sale sin cerrar: "Volver a Venta" si se vino de Venta
  /// (como el mock), "Volver" si se vino de otra pantalla.
  final String textoVolver;

  @override
  State<PantallaCierre> createState() => _PantallaCierreState();
}

class _PantallaCierreState extends State<PantallaCierre> {
  late final CierreControlador _c;

  @override
  void initState() {
    super.initState();
    _c = CierreControlador(widget.db, sesionId: widget.sesionId, leerCobrosMp: widget.leerCobrosMp);
    _c.cargar();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _terminar() {
    if (widget.onFinalizado != null) {
      widget.onFinalizado!();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final m = margenLateral(MediaQuery.sizeOf(context).width);
    return ChangeNotifierProvider<CierreControlador>.value(
      value: _c,
      child: Scaffold(
        backgroundColor: p.papel,
        body: SafeArea(
          child: DefaultTextStyle(
            style: estilo(16, 400, color: p.tinta),
            child: Consumer<CierreControlador>(
              builder: (context, c, _) {
                if (c.sesion == null) return const SizedBox.shrink();
                final cerrada = c.fase == FaseCierre.cerrado;
                return CallbackShortcuts(
                  // Esc sale sin cerrar, como el modal de antes. Cerrada ya no hay a dónde "salir": está el botón final.
                  bindings: {
                    if (!cerrada) const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
                  },
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(m, 36, m, 26),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Arriba(c: c, textoVolver: widget.textoVolver),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: hayMovimiento(context) ? ms(260) : Duration.zero,
                            switchInCurve: curvaEase,
                            // El default centra al hijo: el paso 1 tiene que arrancar arriba, como en el mock.
                            layoutBuilder: (actual, anteriores) => Stack(fit: StackFit.expand, children: [...anteriores, ?actual]),
                            child: KeyedSubtree(
                              key: ValueKey(c.fase),
                              child: switch (c.fase) {
                                FaseCierre.conteo => _PasoConteo(c: c),
                                FaseCierre.revisado => _PasoRevisado(c: c, usuarioId: widget.usuarioId),
                                FaseCierre.cerrado => _Cerrada(c: c, textoBotonFinal: widget.textoBotonFinal, onTerminar: _terminar),
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Ancho máximo del contenido del cierre en el mock (`max-width:1240px`).
const _anchoMaximo = 1240.0;

/// Arriba a la derecha: "Paso N de 2" y salir sin cerrar.
class _Arriba extends StatelessWidget {
  const _Arriba({required this.c, required this.textoVolver});
  final CierreControlador c;
  final String textoVolver;

  @override
  Widget build(BuildContext context) {
    if (c.fase == FaseCierre.cerrado) return const SizedBox(height: 44);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _anchoMaximo),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Etiqueta('Paso ${c.fase == FaseCierre.conteo ? 1 : 2} de 2'),
            const SizedBox(width: 10),
            Btn(textoVolver, variante: VarBtn.ton, tam: TamBtn.sm, icono: Ic.back, onTap: () => Navigator.of(context).maybePop()),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── paso 1: contar ─────────────────────────────

/// Paso 1. Solo lo que se cuenta: ni un número esperado, de diferencia o de separación existe en el árbol (Regla 10).
class _PasoConteo extends StatelessWidget {
  const _PasoConteo({required this.c});
  final CierreControlador c;

  Future<void> _confirmar() async {
    if (!c.conteoCompleto || c.ventasAbiertas > 0) return;
    await c.confirmarConteo();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final alto = MediaQuery.sizeOf(context).height;
    final lata = moduloActivo(Modulo.cajaAparte);
    final ultimo = c.arqueos.isEmpty ? null : c.arqueos.last;
    final nota = estilo(14, 400, color: p.mute, alto: 1.45);

    final izquierda = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('¿Cuánta plata hay en cada caja?', style: Tipos.h1(p.tinta, tamanio: 46)),
        const SizedBox(height: 16),
        Text(
          'Contá billetes y monedas del cajón${lata ? ' (cigarrillos incluidos)' : ''} y lo que dice la app de Mercado '
          'Pago. Recién después te mostramos lo que tendría que haber.',
          style: estilo(18, 400, color: p.mute, alto: 1.5),
        ),
        const SizedBox(height: 16),
        Nota(
          icono: Ic.lock,
          texto: '${lata ? 'La diferencia y la separación de cigarrillos se ven' : 'La diferencia se ve'} al confirmar. Si '
              'se termina tarde, el día queda abierto y se cuenta a la mañana siguiente.',
        ),
        if (c.arqueos.isNotEmpty) ...[
          const SizedBox(height: 16),
          _TarjetaArqueos(arqueos: c.arqueos),
        ],
      ],
    );

    final derecha = ListenableBuilder(
      listenable: Listenable.merge([c.efectivoContadoCtrl, c.mpContadoCtrl, c.lataContadoCtrl]),
      builder: (context, _) {
        final habilitado = c.conteoCompleto && c.ventasAbiertas == 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (c.ventasAbiertas > 0) ...[
              _NotaVentasAbiertas(c: c),
              const SizedBox(height: 12),
            ],
            Campo(
              key: const Key('campo_efectivo_contado'),
              etiqueta: 'Efectivo contado (cajón)',
              controller: c.efectivoContadoCtrl,
              grande: true,
              autofocus: true,
              pista: r'$ 0',
              teclado: TextInputType.number,
              textInputAction: TextInputAction.next,
            ),
            if (ultimo != null) ...[
              const SizedBox(height: 8),
              Text(
                c.efectivoPrecargado
                    ? 'Precargado con el arqueo de las ${horaCorta(ultimo.fecha)} (${ultimo.usuario}): desde entonces no '
                        'entró ni salió plata del cajón.'
                    : 'Después del arqueo de las ${horaCorta(ultimo.fecha)} se movió plata del cajón: contalo de nuevo.',
                style: nota,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Campo(
                    key: const Key('campo_mp_contado'),
                    etiqueta: 'Mercado Pago contado (según la app)',
                    controller: c.mpContadoCtrl,
                    pista: r'$ 0',
                    teclado: TextInputType.number,
                    textInputAction: lata ? TextInputAction.next : TextInputAction.done,
                    onSubmitted: lata ? null : (_) => _confirmar(),
                    derecha: BotonSaldoMp(c: c),
                  ),
                ),
                if (lata) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Campo(
                      key: const Key('campo_lata_contada'),
                      etiqueta: 'Lata de cigarrillos contada',
                      controller: c.lataContadoCtrl,
                      pista: r'$ 0',
                      teclado: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _confirmar(),
                    ),
                  ),
                ],
              ],
            ),
            // Mismo criterio que el efectivo (El dueño, 2026-10-04): lo del arqueo se precarga solo si MP no se movió.
            if (ultimo != null) ...[
              const SizedBox(height: 8),
              Text(
                c.mpPrecargado
                    ? 'Mercado Pago, precargado con el arqueo de las ${horaCorta(ultimo.fecha)}: desde entonces no se movió.'
                    : 'Después del arqueo de las ${horaCorta(ultimo.fecha)} entró o salió plata por Mercado Pago: mirá el '
                        'saldo de nuevo.',
                style: nota,
              ),
            ],
            if (c.traerSaldoMp != null && (c.pidiendoSaldo || c.errorSaldo != null || c.saldoMp != null)) ...[
              const SizedBox(height: 8),
              EstadoSaldoMp(c: c),
            ],
            if (c.error != null) ...[
              const SizedBox(height: 8),
              Text(c.error!, style: estilo(15, 500, color: p.b)),
            ],
            const SizedBox(height: 12),
            Btn(
              'Confirmar conteo',
              variante: VarBtn.blue,
              tam: TamBtn.lg,
              ancho: true,
              onTap: habilitado ? _confirmar : null,
            ),
          ],
        );
      },
    );

    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _anchoMaximo),
          child: Padding(
            // 90 en el mock (1920×1040); en una ventana baja ese aire empujaría el botón fuera de vista.
            padding: EdgeInsets.only(top: alto >= 900 ? 90 : 24, bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(width: 440, child: izquierda),
                const SizedBox(width: 56),
                Expanded(child: derecha),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Hay N ventas abiertas con productos": se cobran o se descartan antes de cerrar (El dueño, 2026-09-29).
class _NotaVentasAbiertas extends StatelessWidget {
  const _NotaVentasAbiertas({required this.c});
  final CierreControlador c;

  @override
  Widget build(BuildContext context) {
    final n = c.ventasAbiertas;
    return Nota(
      tono: TonoMock.w,
      child: Row(
        children: [
          Expanded(
            child: Text(
              n == 1
                  ? 'Hay 1 venta abierta con productos: se cobra o se descarta antes de cerrar.'
                  : 'Hay $n ventas abiertas con productos: se cobran o se descartan antes de cerrar.',
            ),
          ),
          const SizedBox(width: 16),
          Btn('Descartar', variante: VarBtn.dark, tam: TamBtn.xs, onTap: c.descartarVentasAbiertasYRecargar),
        ],
      ),
    );
  }
}

/// "Arqueos del turno": hora · Efectivo · MP · Lata, lo que se contó en cada arqueo.
class _TarjetaArqueos extends StatelessWidget {
  const _TarjetaArqueos({required this.arqueos});
  final List<ArqueoDelTurno> arqueos;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final lata = moduloActivo(Modulo.cajaAparte);
    Widget caja(String etiqueta, int monto) => Text.rich(
          TextSpan(children: [
            TextSpan(text: '$etiqueta '),
            TextSpan(text: pesos(monto), style: estilo(14.5, 600, color: p.tinta, num: true)),
          ]),
          style: estilo(14.5, 400, color: p.tinta),
        );
    return Tarjeta(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Sec('Arqueos del turno'),
          const SizedBox(height: 6),
          for (final (i, a) in arqueos.indexed)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(border: i > 0 ? Border(top: BorderSide(color: p.pelo)) : null),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${horaCorta(a.fecha)} · ${a.usuario}', maxLines: 1, overflow: TextOverflow.ellipsis, style: estilo(14.5, 400, color: p.mute)),
                  ),
                  Wrap(
                    spacing: 16,
                    children: [
                      caja('Efectivo', a.efectivoContadoCentavos),
                      caja('MP', a.mpContadoCentavos),
                      if (lata) caja('Lata', a.lataContadoCentavos),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────────── paso 2: comparar ─────────────────────────────

/// Tono y texto de una diferencia: cero verde, faltante rojo, sobrante amarillo (sobrar también es un descuadre, Regla
/// 10, pero no es lo mismo que faltar).
(TonoMock, String) _tonoDiferencia(int d) =>
    d == 0 ? (TonoMock.g, 'Cuadró justo') : (d < 0 ? (TonoMock.b, 'Faltan ${pesos(-d)}') : (TonoMock.w, 'Sobran ${pesos(d)}'));

class _PasoRevisado extends StatelessWidget {
  const _PasoRevisado({required this.c, required this.usuarioId});
  final CierreControlador c;
  final int usuarioId;

  /// Con faltantes sin explicar no se cierra de una: se avisa qué pasa si no se anotan. Nunca se traba — "no sé" es
  /// una respuesta válida y la diferencia queda como siempre.
  Future<void> _cerrar(BuildContext context) async {
    final sinExplicar = c.faltantes.values.fold(0, (a, m) => a + m);
    if (sinExplicar > 0) {
      final cerrarIgual = await mostrarModalMock<bool>(
        context,
        builder: (context) => ModalMock(
          titulo: 'Quedan ${pesos(sinExplicar)} sin explicar',
          subtitulo: 'Si no anotás a dónde fueron, Equilibrio los sigue contando como ganancia que tenés.',
          cuerpo: const [],
          pie: [
            Btn('Anotar a dónde fueron', variante: VarBtn.blue, tam: TamBtn.lg, ancho: true, onTap: () => Navigator.of(context).pop(false)),
            Btn('No sé, cerrar igual', key: const Key('cerrar_sin_explicar'), variante: VarBtn.out, ancho: true, onTap: () => Navigator.of(context).pop(true)),
          ],
        ),
      );
      if (cerrarIgual != true) return;
    }
    await c.cerrar(usuarioId: usuarioId);
  }

  @override
  Widget build(BuildContext context) {
    final r = c.resumen;
    if (r == null) return const SizedBox.shrink();
    final p = context.p;
    final dia = c.resumenDia;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _anchoMaximo),
        child: Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(right: 4),
                  child: _ColumnaDiferencias(c: c, r: r, usuarioId: usuarioId),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(right: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Tarjeta(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SeccionMpReal(
                                    cargar: c.cargarMpReal,
                                    mpEsperadoCentavos: r.mpEsperadoCentavos,
                                    mpContadoCentavos: r.mpDiferenciaCentavos == null ? null : r.mpEsperadoCentavos + r.mpDiferenciaCentavos!,
                                  ),
                                  if (c.diferenciasSaldo?.hayDiferencias ?? false) ...[
                                    const SizedBox(height: 12),
                                    DiferenciasSaldoMpVista(c: c),
                                  ],
                                  const SizedBox(height: 10),
                                  Text('Esto nunca frena el cierre: solo avisa lo que no cierra.', style: estilo(13.5, 400, color: p.mute)),
                                ],
                              ),
                            ),
                            if (dia != null && (dia.porProveedor.isNotEmpty || dia.productosSinDatos.isNotEmpty)) ...[
                              const SizedBox(height: 14),
                              _TarjetaProveedores(dia: dia),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (c.ventasAbiertas > 0) ...[
                      const SizedBox(height: 12),
                      _NotaVentasAbiertas(c: c),
                    ],
                    if (c.error != null) ...[
                      const SizedBox(height: 12),
                      Text(c.error!, style: estilo(15, 500, color: p.b)),
                    ],
                    const SizedBox(height: 12),
                    Btn('Cerrar caja', variante: VarBtn.blue, tam: TamBtn.lg, ancho: true, onTap: () => _cerrar(context)),
                    const SizedBox(height: 12),
                    Btn('Volver a contar', variante: VarBtn.out, ancho: true, onTap: c.volverAContar),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La columna izquierda del paso 2: la diferencia del cajón en grande, las otras dos cajas y el redondeo, y de qué sale
/// cada esperado renglón por renglón (así la diferencia se entiende sin hacer cuentas).
class _ColumnaDiferencias extends StatelessWidget {
  const _ColumnaDiferencias({required this.c, required this.r, required this.usuarioId});
  final CierreControlador c;
  final ResumenCierre r;
  final int usuarioId;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final lata = moduloActivo(Modulo.cajaAparte);
    final d = r.diferenciaCentavos;
    final (tono, textoTono) = _tonoDiferencia(d);
    final de = r.desgloseEfectivo;
    final dm = r.desgloseMp;
    final sep = r.separacionCigarrillos;
    final sinCosto = c.resumenDia?.productosSinDatos.where((x) => x.sinCosto).length ?? 0;
    final reserva = r.reservaDiariaFijosCentavos;
    final mpDif = r.mpDiferenciaCentavos;
    final lataDif = r.lataDiferenciaCentavos;
    final chico = estilo(12.5, 400, color: p.mute, alto: 1.4);

    Widget cifra(String titulo, String valor, Widget pie) => Tarjeta(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: estilo(13.5, 600, color: p.mute)),
              const SizedBox(height: 6),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(valor, style: Tipos.fig(p.tinta, tamanio: 28))),
              const SizedBox(height: 6),
              pie,
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          d == 0 ? 'Cuadró el cajón' : (d < 0 ? 'Faltan ${pesos(-d)} en el cajón' : 'Sobran ${pesos(d)} en el cajón'),
          style: Tipos.h1(p.tinta, tamanio: 40),
        ),
        const SizedBox(height: 14),
        BloqueHero(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Diferencia del cajón', style: estilo(14, 600, color: p.heroSub)),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(pesosConSigno(d), key: const Key('cierre_diferencia_cajon'), style: Tipos.fig(p.sobreHero, tamanio: 60)),
              ),
              const SizedBox(height: 10),
              Etiqueta(textoTono, tono: tono),
            ],
          ),
        ),
        if (c.faltantes.isNotEmpty) ...[
          const SizedBox(height: 14),
          _TarjetaFaltantes(c: c, usuarioId: usuarioId),
        ],
        const SizedBox(height: 14),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: cifra(
                  'Mercado Pago',
                  mpDif == null ? '—' : pesosConSigno(mpDif),
                  Text('Suele ser la comisión de MP', style: chico),
                ),
              ),
              if (lata) ...[
                const SizedBox(width: 14),
                Expanded(
                  child: cifra(
                    'Lata de cigarrillos',
                    lataDif == null ? '—' : pesosConSigno(lataDif),
                    lataDif == null
                        ? const SizedBox.shrink()
                        : Align(alignment: Alignment.centerLeft, child: Etiqueta(_tonoDiferencia(lataDif).$2, tono: _tonoDiferencia(lataDif).$1)),
                  ),
                ),
              ],
              const SizedBox(width: 14),
              Expanded(child: cifra('Redondeo de hoy', pesos(r.redondeoAcumuladoCentavos), Text('Informativo, no es descuadre', style: chico))),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Lista(filas: [
          Kv('Debería haber en el cajón', pesos(r.efectivoEsperadoCentavos)),
          Kv('Contaste', pesos(r.efectivoEsperadoCentavos + d)),
          if (de != null) ...[
            Kv('Fondo inicial', pesos(de.fondo)),
            Kv(de.redondeo != 0 ? '+ Ventas en efectivo (con ${pesos(de.redondeo)} de redondeo)' : '+ Ventas en efectivo', pesos(de.ventas)),
            if (de.gastos != 0) Kv('− Gastos, pagos y retiros', pesos(de.gastos)),
            if (de.ingresos != 0) Kv('+ Ingresos', pesos(de.ingresos)),
          ],
          // "A separar", no "Separado" (bug real, el dueño: "dice como si ya se hubiese hecho"): es lo que falta mover.
          if (lata) Kv('A separar a la lata (cigarrillos)', pesos(sep.separadoCentavos)),
          Kv('Reserva de fijos del día', reserva == null ? 'Sin fijos cargados' : pesos(reserva)),
          Kv(
            'Vendido sin costo cargado',
            pesos(r.vendidoSinCostoCentavos),
            valorWidget: r.vendidoSinCostoCentavos == 0
                ? null
                : Btn(
                    sinCosto == 1 ? '1 producto' : '$sinCosto productos',
                    key: const Key('cierre_ver_sin_costo'),
                    variante: VarBtn.ton,
                    tam: TamBtn.xs,
                    sobreGris: true,
                    onTap: () => mostrarDialogoSinCosto(
                      context,
                      db: c.db,
                      desde: c.sesion!.fechaApertura,
                      periodo: 'en este turno',
                      usuarioId: usuarioId,
                      alGuardar: () => c.confirmarConteo(),
                    ),
                  ),
          ),
        ]),
        if (lata && sep.esSeparacionParcial) ...[
          const SizedBox(height: 14),
          Nota(
            tono: TonoMock.w,
            texto: 'No alcanzó el efectivo contado: quedan ${pesos(sep.pendienteCentavos)} pendientes, se arrastran al '
                'próximo cierre (sea el próximo turno de hoy o el de mañana).',
          ),
        ],
        const SizedBox(height: 14),
        const Sec('Mercado Pago'),
        const SizedBox(height: 8),
        Lista(filas: [
          if (dm != null) ...[
            Kv('Saldo al abrir', pesos(dm.inicial), key: const Key('mp_desglose_inicial')),
            Kv('+ Cobrado por MP (${dm.ventas} ${dm.ventas == 1 ? 'venta' : 'ventas'})', pesos(dm.cobros), key: const Key('mp_desglose_cobros')),
            if (dm.gastos != 0) Kv('− Gastos y pagos con MP', pesos(dm.gastos)),
            if (dm.ingresos != 0) Kv('+ Ingresos por MP', pesos(dm.ingresos)),
          ],
          Kv('Debería haber en Mercado Pago', pesos(r.mpEsperadoCentavos)),
          if (mpDif != null) Kv('Contaste', pesos(r.mpEsperadoCentavos + mpDif)),
        ]),
        if (dm != null && dm.inicial != 0) ...[
          const SizedBox(height: 8),
          Text(
            'El saldo al abrir es lo último contado. Lo que salió de Mercado Pago sin pasar por la app (una transferencia a '
            'tu cuenta, un proveedor pagado por transferencia) no está restado acá.',
            style: estilo(13.5, 400, color: p.mute, alto: 1.45),
          ),
        ],
        if (lata) ...[
          const SizedBox(height: 14),
          const Sec('Lata de cigarrillos'),
          const SizedBox(height: 8),
          Lista(filas: [
            Kv('Debería haber en la lata', pesos(r.lataFinalCentavos), key: const Key('lata_esperada')),
            if (lataDif != null) Kv('Contaste', pesos(r.lataFinalCentavos + lataDif)),
          ]),
        ],
        if (c.ordenesCobroSinResolver.isNotEmpty) ...[
          const SizedBox(height: 14),
          _NotaCobrosSinResolver(ordenes: c.ordenesCobroSinResolver),
        ],
        if (c.arqueos.isNotEmpty) ...[
          const SizedBox(height: 14),
          _TarjetaArqueos(arqueos: c.arqueos),
        ],
        const SizedBox(height: 14),
        Campo(
          key: const Key('campo_nota'),
          etiqueta: 'Nota (opcional)',
          controller: c.notaCtrl,
          pista: 'Ej: faltó cambio, se cobró un fiado…',
        ),
      ],
    );
  }
}

/// Fase 12: nunca bloquea el cierre — solo avisa que hay cobros por QR/Débito que no llegaron a confirmarse (se agotó
/// el tiempo de espera sin que la API dijera nada). La duda se resuelve mirando la cuenta de Mercado Pago.
class _NotaCobrosSinResolver extends StatelessWidget {
  const _NotaCobrosSinResolver({required this.ordenes});
  final List<OrdenCobroPendiente> ordenes;

  @override
  Widget build(BuildContext context) {
    final total = ordenes.fold<int>(0, (suma, o) => suma + o.montoCentavos);
    return Nota(
      tono: TonoMock.w,
      icono: Ic.warn,
      texto: '${ordenes.length == 1 ? 'Un cobro' : '${ordenes.length} cobros'} por QR/Débito sin confirmar, por '
          '${pesos(total)}: revisá la cuenta de Mercado Pago antes de dar por cerrado ese monto.',
    );
  }
}

/// "A separar por proveedor" (El dueño: "faltan datos importantes" en el cierre): cuánto separarle a cada uno, la
/// ganancia que queda sin revisar, y qué se vendió sin proveedor o sin costo (no entra en ningún renglón).
class _TarjetaProveedores extends StatelessWidget {
  const _TarjetaProveedores({required this.dia});
  final ResumenDiaHistorico dia;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final ganancia = dia.porProveedor.fold<int>(0, (a, x) => a + x.gananciaCentavos);
    Widget fila(String nombre, String detalle, int monto) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: nombre),
                    if (detalle.isNotEmpty) TextSpan(text: '  $detalle', style: estilo(13.5, 400, color: p.mute)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: estilo(15, 400, color: p.tinta),
                ),
              ),
              const SizedBox(width: 12),
              Text(pesos(monto), style: estilo(15, 600, color: p.tinta, num: true)),
            ],
          ),
        );
    return Tarjeta(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (dia.porProveedor.isNotEmpty) ...[
            Row(
              children: [
                const Expanded(child: Sec('A separar por proveedor')),
                const SizedBox(width: 10),
                Etiqueta('Ganancia sin revisar ${pesos(ganancia)}', tono: TonoMock.w),
              ],
            ),
            const SizedBox(height: 6),
            for (final x in dia.porProveedor) fila(x.nombreProveedor, '', x.costoRealCentavos),
          ],
          if (dia.productosSinDatos.isNotEmpty) ...[
            Container(
              margin: EdgeInsets.only(top: dia.porProveedor.isEmpty ? 0 : 8),
              padding: EdgeInsets.only(top: dia.porProveedor.isEmpty ? 0 : 10),
              decoration: BoxDecoration(border: dia.porProveedor.isEmpty ? null : Border(top: BorderSide(color: p.pelo))),
              child: const Sec('Vendido sin proveedor o costo'),
            ),
            const SizedBox(height: 4),
            Text('Completalo para números más claros: no se sabe a quién ni cuánto separarle.', style: estilo(13.5, 400, color: p.mute)),
            const SizedBox(height: 4),
            for (final x in dia.productosSinDatos)
              fila(x.nombreProducto, [if (x.sinProveedor) 'sin proveedor', if (x.sinCosto) 'sin costo'].join(' · '), x.vendidoCentavos),
          ],
        ],
      ),
    );
  }
}

// ───────────────────────────── caja cerrada ─────────────────────────────

class _Cerrada extends StatelessWidget {
  const _Cerrada({required this.c, required this.textoBotonFinal, required this.onTerminar});
  final CierreControlador c;
  final String textoBotonFinal;
  final VoidCallback onTerminar;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final r = c.resumen;
    final det = c.detalleCerrado;
    final lata = moduloActivo(Modulo.cajaAparte);
    String? lead;
    if (det != null) {
      final tickets = det.ventas.where((v) => !v.anulada).length;
      lead = 'Vendiste ${pesos(det.vendidoCentavos)} en $tickets ${tickets == 1 ? 'ticket' : 'tickets'} y ganaste '
          '${pesos(det.gananciaCentavos)}'
          '${det.vendidoSinCostoCentavos > 0 ? ' (sin contar ${pesos(det.vendidoSinCostoCentavos)} vendidos sin costo)' : ''}.';
      if (c.respaldoHechoA != null) lead += ' La copia de seguridad se hizo a las ${horaCorta(c.respaldoHechoA!)}.';
    }
    Kv dif(String clave, int d, {Key? key}) {
      final (tono, _) = _tonoDiferencia(d);
      return Kv(clave, pesosConSigno(d), key: key, colorValor: tono.colores(p).$2);
    }

    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: MediaQuery.sizeOf(context).height >= 900 ? 60 : 12),
              Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(color: p.gbg, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: TildeDibujada(color: p.g, tamanio: 72, grosor: 2.4),
              ),
              const SizedBox(height: 18),
              Text('Caja cerrada', textAlign: TextAlign.center, style: Tipos.h1(p.tinta, tamanio: 56)),
              if (lead != null) ...[
                const SizedBox(height: 18),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Text(lead, textAlign: TextAlign.center, style: estilo(19, 400, color: p.mute, alto: 1.5)),
                ),
              ],
              // Lo que hay que mover de plata ahora que cerró, y cómo quedó cada caja.
              if (r != null) ...[
                const SizedBox(height: 22),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Lista(filas: [
                    dif('Diferencia del cajón', r.diferenciaCentavos, key: const Key('cerrada_diferencia_cajon')),
                    if (r.mpDiferenciaCentavos != null) dif('Diferencia de Mercado Pago', r.mpDiferenciaCentavos!),
                    if (lata) ...[
                      Kv('Separado a la lata en este cierre', pesos(r.separacionCigarrillos.separadoCentavos)),
                      if (r.separacionCigarrillos.esSeparacionParcial)
                        Kv('No alcanzó: queda para el próximo cierre', pesos(r.separacionCigarrillos.pendienteCentavos)),
                      Kv('Lata al cierre', pesos(r.lataFinalCentavos)),
                      if (r.lataDiferenciaCentavos != null) dif('Diferencia de la lata', r.lataDiferenciaCentavos!),
                    ],
                  ]),
                ),
              ],
              for (final error in [?c.ultimoRespaldoError, ?c.ultimoPlanillaError]) ...[
                const SizedBox(height: 12),
                ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: Nota(tono: TonoMock.b, icono: Ic.warn, texto: error)),
              ],
              if (c.ordenesCobroSinResolver.isNotEmpty) ...[
                const SizedBox(height: 12),
                ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: _NotaCobrosSinResolver(ordenes: c.ordenesCobroSinResolver)),
              ],
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  Btn(textoBotonFinal, variante: VarBtn.dark, tam: TamBtn.lg, onTap: onTerminar),
                  if (c.puedeReabrir)
                    Btn('Reabrir caja', variante: VarBtn.ton, tam: TamBtn.lg, onTap: () => mostrarDialogoReabrirSesion(context, c)),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Los faltantes del cierre que todavía no se explicaron, uno por caja, con el botón para decir a dónde fueron.
class _TarjetaFaltantes extends StatelessWidget {
  const _TarjetaFaltantes({required this.c, required this.usuarioId});
  final CierreControlador c;
  final int usuarioId;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Tarjeta(
      key: const Key('cierre_faltantes'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('¿A dónde fue esta plata?', style: estilo(17, 600, color: p.tinta)),
          const SizedBox(height: 4),
          Text(
            'Lo que salió sin anotar (un proveedor, la luz, un gasto tuyo) Equilibrio lo sigue contando como ganancia.',
            style: estilo(13.5, 400, color: p.mute, alto: 1.4),
          ),
          for (final MapEntry(key: caja, value: monto) in c.faltantes.entries) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: Text('Faltan ${pesos(monto)} en ${nombreCaja(caja)}', style: estilo(15.5, 500, color: p.tinta))),
                Btn(
                  'Anotar',
                  key: Key('faltante_${caja.name}'),
                  variante: VarBtn.ton,
                  tam: TamBtn.sm,
                  sobreGris: true,
                  onTap: () => mostrarDialogoFaltante(context, c: c, caja: caja, faltanteCentavos: monto, usuarioId: usuarioId),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// Modal de cierre de caja. Tres vistas, una por fase de CierreControlador —
// la fase `conteo` literalmente no arma los widgets de diferencia/separación
// (Regla 1 y 2: ocultos hasta confirmar, no solo deshabilitados).
//
// Fase 13: primera pantalla de gestión (además de venta y Proveedores) en
// recibir el sistema de diseño completo. Usa los dos patrones de
// composición en secuencia, tal como lo describe `DISENO.md` ("Cierre de
// caja usa los dos patrones, en secuencia"): Patrón A mientras se cuenta
// (Regla 10, nada más en pantalla), Patrón B una vez revelado el resumen.
//
// Fase de turnos por usuario (2026-09-12, el dueño: "una pantalla entera pierde
// mucha info"): pasó de `Scaffold` + `Navigator.push` a `Modal`, el mismo
// diálogo que usa el resto de la app — se abre encima de la pantalla de
// venta en vez de navegar a otro lado. El contenido de cada fase no cambió,
// solo dónde vive: los botones de cada fase pasan al pie común de `Modal`
// (fijo, no se scrollea con el resto) y la fase "revisado" usa
// `Medidas.anchoModalCierre` porque su layout de dos columnas no entra en el
// ancho de formulario de siempre.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/modulos.dart';
import '../../servicios/modulos_activos.dart';
import '../../data/database.dart';
import '../../data/repositorio_carga_historica.dart' show ResumenDiaHistorico;
import '../../data/repositorio_cierre.dart' show ResumenCierre;
import '../../data/repositorio_conciliacion_mp.dart' show LeerCobrosMp;
import '../../domain/dinero.dart';
import '../tema/acentos.dart';
import '../comun/fechas.dart';
import '../comun/tarjetas.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/fila_dato.dart';
import '../comun/modal.dart';
import '../tema/superficie.dart';
import '../tema/tema.dart';
import '../tema/tokens.dart';
import 'arqueos_del_turno.dart';
import 'cierre_controlador.dart';
import 'dialogo_reabrir_sesion.dart';
import 'seccion_mp_real.dart';

class PantallaCierre extends StatefulWidget {
  const PantallaCierre({
    super.key,
    required this.db,
    required this.sesionId,
    required this.usuarioId,
    this.onFinalizado,
    this.textoBotonFinal = 'Volver a la venta',
    this.leerCobrosMp,
  });

  /// Solo para tests: de dónde salen los cobros reales de Mercado Pago (por defecto, la cuenta de Nodo Sur de la PC).
  final LeerCobrosMp? leerCobrosMp;

  final AppDatabase db;
  final int sesionId;
  final int usuarioId;

  /// Se llama cuando ya no hay nada más que hacer acá (cerró sin reabrir, o
  /// reabrió). Si es null, la pantalla asume que la trajo `mostrarModal` y
  /// usa `pop` en su lugar — ver `pantalla_venta.dart` para el cierre
  /// voluntario y el cambio de turno vs. `main.dart` para el forzado
  /// (Regla 5).
  final VoidCallback? onFinalizado;

  /// Texto del botón que termina la fase "cerrado" — "Volver a la venta"
  /// para un cierre normal, distinto para un cambio de turno (ese caso
  /// encadena directo a abrir la hoja del que entra, no "vuelve" a nada).
  final String textoBotonFinal;

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
    return ChangeNotifierProvider<CierreControlador>.value(
      value: _c,
      child: Consumer<CierreControlador>(
        builder: (context, c, _) {
          if (c.sesion == null) return const SizedBox.shrink();
          return switch (c.fase) {
            FaseCierre.conteo => Modal(
              titulo: 'Cierre de caja',
              contenido: _ContenidoConteo(c: c),
              botones: [
                BotonPrimario(
                  texto: 'Confirmar conteo',
                  onPressed: c.confirmarConteo,
                ),
              ],
            ),
            FaseCierre.revisado => Modal(
              titulo: 'Cierre de caja',
              ancho: Medidas.anchoModalCierre,
              alturaMaxima: MediaQuery.of(context).size.height * 0.85,
              contenido: _ContenidoRevisado(c: c),
              botones: [
                BotonSecundario(texto: 'Cancelar', onPressed: () => Navigator.of(context).maybePop()),
                if (c.ventasAbiertas > 0)
                  BotonSecundario(
                    texto: c.ventasAbiertas == 1
                        ? 'Descartar la venta abierta'
                        : 'Descartar ${c.ventasAbiertas} ventas abiertas',
                    onPressed: c.descartarVentasAbiertasYRecargar,
                  ),
                BotonPrimario(
                  texto: 'Cerrar caja',
                  onPressed: () => c.cerrar(usuarioId: widget.usuarioId),
                ),
              ],
            ),
            FaseCierre.cerrado => Modal(
              titulo: 'Caja cerrada',
              // Antes sin `alturaMaxima` ni scroll propio en `_ContenidoCerrado`
              // — inofensivo mientras esta fase mostraba pocas líneas fijas,
              // pero el desglose por proveedor puede sumar tantas filas como
              // proveedores vendieron algo ese día: sin techo, el modal se
              // estira más alto que la pantalla en vez de scrollear.
              ancho: Medidas.anchoModalCierre,
              alturaMaxima: MediaQuery.of(context).size.height * 0.85,
              contenido: _ContenidoCerrado(c: c),
              botones: [
                if (c.puedeReabrir)
                  BotonSecundario(
                    texto: 'Reabrir',
                    onPressed: () => mostrarDialogoReabrirSesion(context, c),
                  ),
                BotonPrimario(
                  texto: widget.textoBotonFinal,
                  onPressed: _terminar,
                ),
              ],
            ),
          };
        },
      ),
    );
  }
}

/// Fase 1 (Patrón A — Formulario): solo se ve esto. Ni un número de
/// esperado, ni de diferencia, ni de separación existe todavía en el árbol
/// de widgets.
class _ContenidoConteo extends StatelessWidget {
  const _ContenidoConteo({required this.c});
  final CierreControlador c;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Contá todo el efectivo del cajón, cigarrillos incluidos, '
          'y anotalo acá. Recién después se ve cuánto tendría que haber.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: Espaciado.lg),
        CampoPlata(
          key: const Key('campo_efectivo_contado'),
          controller: c.efectivoContadoCtrl,
          autofocus: true,
          etiqueta: 'Efectivo contado',
          onSubmitted: (_) => c.confirmarConteo(),
        ),
        if (c.precargadoDe case final a?) ...[
          const SizedBox(height: Espaciado.sm),
          Text(
            'Precargado con el arqueo de las ${horaCorta(a.fecha)} (${a.usuario}). '
            'Si vendiste o sacaste plata después, corregilo antes de confirmar.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.colores.textoSecundario),
          ),
        ],
        if (c.error != null) ...[
          const SizedBox(height: Espaciado.sm),
          Text(c.error!, style: TextStyle(color: context.colores.error)),
        ],
      ],
    );
  }
}

/// Fase 2 — revisado. Distribución del mock `CierreCaja` ("Lenguaje de
/// diseño", 2026-09-28): a la izquierda, en naranja, de qué sale lo que
/// tendría que haber en el cajón, renglón por renglón; a la derecha, lo
/// contado en grande y la diferencia en su color (verde cuadra, rojo falta,
/// marrón sobra). Lo que el mock no trae y el negocio sí exige queda: se
/// llega acá recién después de contar a ciegas (fase 1, Regla 10), Mercado
/// Pago SÍ se arquea (Regla 10) y la lata de cigarrillos tiene su propio
/// bloque (Regla 6). Arriba, los tres totales para mover billetes (El dueño:
/// "que sume efectivo, que sume solo MP y que sume cigarros").
class _ContenidoRevisado extends StatelessWidget {
  const _ContenidoRevisado({required this.c});
  final CierreControlador c;

  @override
  Widget build(BuildContext context) {
    final r = c.resumen!;
    final acentos = context.acentosPlazoleta;
    final sesion = c.sesion!;
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Turno abierto el ${fechaLarga(sesion.fechaApertura)} a las ${horaCorta(sesion.fechaApertura)}',
            style: textTheme.bodyMedium?.copyWith(color: context.colores.textoSecundario),
          ),
          const SizedBox(height: Espaciado.md),
          _TresTotalesGrandes(r: r),
          const SizedBox(height: Espaciado.lg),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _DeberiaHaber(r: r)),
                const SizedBox(width: Espaciado.lg),
                Expanded(child: _Contado(c: c, r: r)),
              ],
            ),
          ),
          const SizedBox(height: Espaciado.lg),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Superficie(
                    relleno: acentos.qr.withValues(alpha: 0.08),
                    child: _BloqueMercadoPago(c: c, r: r),
                  ),
                ),
                if (moduloActivo(Modulo.cajaAparte)) ...[
                  const SizedBox(width: Espaciado.lg),
                  Expanded(
                    child: Superficie(
                      relleno: context.colores.fondo,
                      child: _BloqueCigarrillos(c: c, r: r),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Espaciado.lg),
          Superficie(
            child: SeccionMpReal(
              cargar: c.cargarMpReal,
              mpEsperadoCentavos: r.mpEsperadoCentavos,
              mpContadoCentavos: r.mpDiferenciaCentavos == null ? null : r.mpEsperadoCentavos + r.mpDiferenciaCentavos!,
            ),
          ),
          const SizedBox(height: Espaciado.lg),
          _ResumenDelDia(c: c, r: r),
          if (c.arqueos.isNotEmpty) ...[
            const SizedBox(height: Espaciado.md),
            ArqueosDelTurno(arqueos: c.arqueos),
          ],
          // Bug real (El dueño: "faltan datos importantes" en el cierre): a quién
          // separarle y qué productos vendidos no tienen costo cargado.
          if (c.resumenDia case final dia?
              when dia.porProveedor.isNotEmpty ||
                  dia.productosSinDatos.isNotEmpty) ...[
            const SizedBox(height: Espaciado.md),
            Superficie(child: _BloqueProveedores(dia: dia)),
          ],
          if (c.error != null) ...[
            const SizedBox(height: Espaciado.md),
            Text(c.error!, style: TextStyle(color: context.colores.error)),
          ],
        ],
      ),
    );
  }
}

/// Color de una diferencia de arqueo: cero verde, faltante rojo, sobrante
/// marrón — sobrar también es un descuadre (Regla 10), pero no es lo mismo
/// que faltar.
({Color texto, Color fondo}) _coloresDiferencia(BuildContext context, int diferencia) {
  final a = context.acentosPlazoleta;
  if (diferencia == 0) return (texto: a.ganancia, fondo: a.gananciaSuave);
  if (diferencia < 0) return (texto: context.colores.error, fondo: context.colores.error.withValues(alpha: 0.10));
  return (texto: a.alerta, fondo: a.alertaSuave);
}

class _Renglon extends StatelessWidget {
  const _Renglon({required this.signo, required this.etiqueta, required this.monto});

  final String signo;
  final String etiqueta;
  final int monto;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Espaciado.xs),
      child: Row(
        children: [
          SizedBox(width: 24, child: Text(signo, style: textTheme.titleMedium)),
          Expanded(child: Text(etiqueta, style: textTheme.bodyMedium?.copyWith(fontWeight: Pesos.medium))),
          Text(formatearARS(monto), style: textTheme.titleMedium?.copyWith(fontWeight: Pesos.fuerte).tabular),
        ],
      ),
    );
  }
}

class _DeberiaHaber extends StatelessWidget {
  const _DeberiaHaber({required this.r});
  final ResumenCierre r;

  @override
  Widget build(BuildContext context) {
    final acentos = context.acentosPlazoleta;
    final textTheme = Theme.of(context).textTheme;
    final d = r.desgloseEfectivo;
    final tinta = Color.lerp(acentos.dinero, context.colores.textoPrimario, 0.35);
    return Superficie(
      relleno: acentos.dinero.withValues(alpha: 0.09),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Efectivo · lo que tiene que haber en el cajón',
            style: textTheme.bodyMedium?.copyWith(color: tinta, fontWeight: Pesos.fuerte),
          ),
          const SizedBox(height: Espaciado.sm),
          if (d != null) ...[
            _Renglon(signo: '', etiqueta: 'Fondo inicial', monto: d.fondo),
            _Renglon(signo: '+', etiqueta: d.redondeo != 0 ? 'Ventas en efectivo (incl. redondeo ${formatearARS(d.redondeo)})' : 'Ventas en efectivo', monto: d.ventas),
            if (d.gastos != 0) _Renglon(signo: '−', etiqueta: 'Gastos, pagos y retiros', monto: d.gastos),
            if (d.ingresos != 0) _Renglon(signo: '+', etiqueta: 'Ingresos', monto: d.ingresos),
            const Divider(),
          ],
          Row(
            children: [
              Expanded(
                child: Text('Debería haber', style: textTheme.titleMedium?.copyWith(fontWeight: Pesos.fuerte)),
              ),
              Text(formatearARS(r.efectivoEsperadoCentavos), style: textTheme.headlineMedium?.tabular),
            ],
          ),
          if (moduloActivo(Modulo.cajaAparte))
            Text(
              'Los cigarrillos cobrados en efectivo están adentro: se separan a la lata después.',
              style: textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _Contado extends StatelessWidget {
  const _Contado({required this.c, required this.r});
  final CierreControlador c;
  final ResumenCierre r;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final d = r.diferenciaCentavos;
    final col = _coloresDiferencia(context, d);
    final estado = d == 0 ? 'Cuadra justo' : (d < 0 ? 'Faltan en el cajón' : 'Sobran en el cajón');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CampoPlata(
          key: const Key('campo_efectivo_contado_revisado'),
          controller: c.efectivoContadoCtrl,
          etiqueta: 'Contaste en el cajón (se puede corregir)',
        ),
        const SizedBox(height: Espaciado.md),
        Expanded(
          child: Superficie(
            relleno: col.fondo,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Diferencia · $estado', style: textTheme.bodyMedium?.copyWith(color: col.texto, fontWeight: Pesos.fuerte)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(formatearARS(d.abs()), style: textTheme.displayLarge?.copyWith(color: col.texto).tabular),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BloqueMercadoPago extends StatelessWidget {
  const _BloqueMercadoPago({required this.c, required this.r});
  final CierreControlador c;
  final ResumenCierre r;

  @override
  Widget build(BuildContext context) {
    final acentos = context.acentosPlazoleta;
    final textTheme = Theme.of(context).textTheme;
    final mpDiferencia = r.mpDiferenciaCentavos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            PuntoColor(color: acentos.qr),
            const SizedBox(width: Espaciado.sm),
            Expanded(child: Text('Mercado Pago', style: textTheme.titleMedium?.copyWith(fontWeight: Pesos.fuerte))),
            Text('Esperado ${formatearARS(r.mpEsperadoCentavos)}', style: textTheme.bodyMedium?.tabular),
          ],
        ),
        const SizedBox(height: Espaciado.md),
        CampoPlata(
          key: const Key('campo_mp_contado'),
          controller: c.mpContadoCtrl,
          etiqueta: 'MP contado (según la app de Mercado Pago)',
          sobreElFondo: true,
        ),
        // Oculta hasta escribir lo contado, igual que el efectivo.
        if (mpDiferencia != null) ...[
          const SizedBox(height: Espaciado.sm),
          FilaDato(
            etiqueta: 'Diferencia',
            valor: formatearARS(mpDiferencia),
            enfasis: true,
            color: mpDiferencia == 0 ? null : _coloresDiferencia(context, mpDiferencia).texto,
          ),
          Text(
            'Casi nunca da cero: es la comisión que Mercado Pago descuenta, no un descuadre.',
            style: textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _BloqueCigarrillos extends StatelessWidget {
  const _BloqueCigarrillos({required this.c, required this.r});

  final CierreControlador c;
  final ResumenCierre r;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final lataDiferencia = r.lataDiferenciaCentavos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Cigarrillos · a la lata', style: textTheme.titleMedium?.copyWith(fontWeight: Pesos.fuerte)),
        const SizedBox(height: Espaciado.sm),
        // "A separar", no "Separado" (bug real, el dueño: "dice como si ya se
        // hubiese hecho") — es la acción pendiente, no un hecho consumado.
        FilaDato(
          etiqueta: 'A separar a la lata',
          valor: formatearARS(r.separacionCigarrillos.separadoCentavos),
          enfasis: true,
        ),
        if (r.separacionCigarrillos.esSeparacionParcial)
          Text(
            'No alcanzó el efectivo contado: quedan '
            '${formatearARS(r.separacionCigarrillos.pendienteCentavos)} pendientes, '
            'se arrastran al próximo cierre (sea el próximo turno de hoy o el de mañana).',
            style: textTheme.bodySmall,
          ),
        const SizedBox(height: Espaciado.sm),
        CampoPlata(
          key: const Key('campo_lata_contada'),
          controller: c.lataContadoCtrl,
          etiqueta: 'Lata contada',
          sobreElFondo: true,
        ),
        if (lataDiferencia != null) ...[
          const SizedBox(height: Espaciado.sm),
          FilaDato(etiqueta: 'Lata esperada', valor: formatearARS(r.lataFinalCentavos)),
          FilaDato(
            etiqueta: 'Diferencia',
            valor: formatearARS(lataDiferencia),
            enfasis: true,
            color: lataDiferencia == 0 ? null : _coloresDiferencia(context, lataDiferencia).texto,
          ),
        ],
      ],
    );
  }
}

class _ResumenDelDia extends StatelessWidget {
  const _ResumenDelDia({required this.c, required this.r});
  final CierreControlador c;
  final ResumenCierre r;

  @override
  Widget build(BuildContext context) {
    final reserva = r.reservaDiariaFijosCentavos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: CajaCifra(etiqueta: 'Redondeo acumulado', valor: formatearARS(r.redondeoAcumuladoCentavos))),
            const SizedBox(width: Espaciado.md),
            Expanded(
              child: CajaCifra(
                etiqueta: 'Vendido sin costo cargado',
                valor: formatearARS(r.vendidoSinCostoCentavos),
                tono: r.vendidoSinCostoCentavos > 0 ? Tono.alerta : null,
              ),
            ),
            const SizedBox(width: Espaciado.md),
            Expanded(
              child: CajaCifra(
                etiqueta: 'Reserva diaria de fijos',
                valor: reserva == null ? 'Sin fijos cargados' : formatearARS(reserva),
              ),
            ),
          ],
        ),
        if (c.ordenesCobroSinResolver.isNotEmpty) ...[
          const SizedBox(height: Espaciado.md),
          _AvisoCobrosSinResolver(ordenes: c.ordenesCobroSinResolver),
        ],
        const SizedBox(height: Espaciado.md),
        CampoTexto(
          key: const Key('campo_nota'),
          controller: c.notaCtrl,
          etiqueta: 'Nota (opcional)',
          pista: 'Ej: faltó cambio, se cobró un fiado…',
        ),
      ],
    );
  }
}

/// Fase 12: nunca bloquea el cierre — solo avisa que hay cobros por QR/Débito
/// que no llegaron a confirmarse (se agotó el tiempo de espera del diálogo
/// sin que la API dijera nada). La duda se resuelve mirando la cuenta de
/// Mercado Pago, no reteniendo la caja.
class _AvisoCobrosSinResolver extends StatelessWidget {
  const _AvisoCobrosSinResolver({required this.ordenes});
  final List<OrdenCobroPendiente> ordenes;

  @override
  Widget build(BuildContext context) {
    final total = ordenes.fold<int>(0, (suma, o) => suma + o.montoCentavos);
    return Container(
      padding: const EdgeInsets.all(Espaciado.md),
      decoration: BoxDecoration(
        color: context.colores.fondo,
        borderRadius: BorderRadius.circular(radioControlEscritorio),
      ),
      child: Text(
        '${ordenes.length == 1 ? "Un cobro" : "${ordenes.length} cobros"} por QR/Débito sin '
        'confirmar, por ${formatearARS(total)}: revisá la cuenta de Mercado Pago antes de dar '
        'por cerrado ese monto.',
        style: TextStyle(color: context.colores.textoSecundario),
      ),
    );
  }
}

/// El desglose por proveedor y qué productos no tienen costo cargado — la
/// misma información que ya mostraba la companion en su cierre
/// (`SeccionExtraCierreCompanion`, `resumenDiaHistorico`), agregada acá
/// porque el escritorio nunca la pedía (El dueño: "faltan datos importantes"
/// en el cierre). A diferencia de la companion, sin check por proveedor —
/// acá no hace falta: El dueño separa la plata mirando esta misma pantalla,
/// contra el papel, no de a poco caminando por el local.
class _BloqueProveedores extends StatelessWidget {
  const _BloqueProveedores({required this.dia});
  final ResumenDiaHistorico dia;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (dia.porProveedor.isNotEmpty) ...[
          Text('A separar por proveedor', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Espaciado.sm),
          for (final p in dia.porProveedor)
            Padding(
              padding: const EdgeInsets.only(bottom: Espaciado.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.nombreProveedor),
                        Text(
                          'Ganancia sin revisar: ${formatearARS(p.gananciaCentavos)}',
                          style: TextStyle(color: colores.textoSecundario, fontSize: TamanioTexto.etiqueta),
                        ),
                      ],
                    ),
                  ),
                  Text(formatearARS(p.costoRealCentavos), style: Theme.of(context).textTheme.titleMedium?.tabular),
                ],
              ),
            ),
        ],
        if (dia.productosSinDatos.isNotEmpty) ...[
          if (dia.porProveedor.isNotEmpty) const SizedBox(height: Espaciado.lg),
          Text(
            'Vendido sin proveedor o costo — completalo para números más claros',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: Espaciado.sm),
          for (final p in dia.productosSinDatos)
            Padding(
              padding: const EdgeInsets.only(bottom: Espaciado.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.nombreProducto),
                        Text(
                          [if (p.sinProveedor) 'sin proveedor', if (p.sinCosto) 'sin costo'].join(' · '),
                          style: TextStyle(color: colores.textoSecundario, fontSize: TamanioTexto.etiqueta),
                        ),
                      ],
                    ),
                  ),
                  Text(formatearARS(p.vendidoCentavos), style: TextStyle(color: colores.textoPrimario).tabular),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _ContenidoCerrado extends StatelessWidget {
  const _ContenidoCerrado({required this.c});
  final CierreControlador c;

  @override
  Widget build(BuildContext context) {
    final r = c.resumen!;
    final mpDiferencia = r.mpDiferenciaCentavos;
    return SingleChildScrollView(
      child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilaDato(
          etiqueta: 'Diferencia',
          valor: formatearARS(r.diferenciaCentavos),
          color: r.diferenciaCentavos == 0 ? null : context.colores.error,
        ),
        // La acción de este cierre (cuánto se separó recién) antes que el
        // saldo acumulado de la lata — mismo criterio que en la fase
        // "revisado": lo que hay que haber movido de plata primero, el
        // total resultante después.
        if (moduloActivo(Modulo.cajaAparte)) ...[
          FilaDato(
            etiqueta: 'Separado a la lata en este cierre',
            valor: formatearARS(r.separacionCigarrillos.separadoCentavos),
            enfasis: true,
          ),
          FilaDato(
            etiqueta: 'Lata al cierre',
            valor: formatearARS(r.lataFinalCentavos),
          ),
        ],
        if (moduloActivo(Modulo.cajaAparte) && r.separacionCigarrillos.esSeparacionParcial)
          FilaDato(
            etiqueta: 'De eso, no alcanzó y quedó pendiente para el próximo cierre',
            valor: formatearARS(r.separacionCigarrillos.pendienteCentavos),
          ),
        if (moduloActivo(Modulo.cajaAparte) && r.lataDiferenciaCentavos != null)
          FilaDato(
            etiqueta: 'Diferencia lata',
            valor: formatearARS(r.lataDiferenciaCentavos!),
            color: r.lataDiferenciaCentavos == 0 ? null : context.colores.error,
          ),
        if (mpDiferencia != null)
          FilaDato(
            etiqueta: 'Diferencia MP',
            valor: formatearARS(mpDiferencia),
            color: mpDiferencia == 0 ? null : context.colores.error,
          ),
        const SizedBox(height: Espaciado.md),
        Superficie(
          child: SeccionMpReal(
            cargar: c.cargarMpReal,
            mpEsperadoCentavos: r.mpEsperadoCentavos,
            mpContadoCentavos: r.mpDiferenciaCentavos == null ? null : r.mpEsperadoCentavos + r.mpDiferenciaCentavos!,
          ),
        ),
        if (c.ultimoRespaldoError != null) ...[
          const SizedBox(height: Espaciado.md),
          Text(
            c.ultimoRespaldoError!,
            style: TextStyle(color: context.colores.error),
          ),
        ],
        if (c.ultimoPlanillaError != null) ...[
          const SizedBox(height: Espaciado.md),
          Text(
            c.ultimoPlanillaError!,
            style: TextStyle(color: context.colores.error),
          ),
        ],
        if (c.ordenesCobroSinResolver.isNotEmpty) ...[
          const SizedBox(height: Espaciado.md),
          _AvisoCobrosSinResolver(ordenes: c.ordenesCobroSinResolver),
        ],
        if (c.arqueos.isNotEmpty) ...[
          const SizedBox(height: Espaciado.md),
          ArqueosDelTurno(arqueos: c.arqueos),
        ],
        if (c.resumenDia case final dia?
            when dia.porProveedor.isNotEmpty ||
                dia.productosSinDatos.isNotEmpty) ...[
          const SizedBox(height: Espaciado.md),
          Superficie(child: _BloqueProveedores(dia: dia)),
        ],
      ],
      ),
    );
  }
}

/// Los tres números que el dueño mira para mover billetes, textual: "que sume
/// efectivo, que sume solo MP y que sume cigarros sin el recargo, así yo
/// solo tengo que contar y pasar plata". Van arriba de todo, grandes y
/// separados, antes de la diferencia y del resto del resumen — no es la
/// misma jerarquía visual que el resto de la pantalla a propósito.
class _TresTotalesGrandes extends StatelessWidget {
  const _TresTotalesGrandes({required this.r});
  final ResumenCierre r;

  @override
  Widget build(BuildContext context) {
    final acentos = context.acentosPlazoleta;
    return Row(
      children: [
        Expanded(child: FilaMedio(color: acentos.dinero, etiqueta: 'Efectivo del día', monto: formatearARS(r.efectivoEsperadoCentavos))),
        const SizedBox(width: Espaciado.md),
        Expanded(child: FilaMedio(color: acentos.qr, etiqueta: 'Mercado Pago del día', monto: formatearARS(r.mpEsperadoCentavos))),
        if (moduloActivo(Modulo.cajaAparte)) ...[
          const SizedBox(width: Espaciado.md),
          Expanded(
            child: FilaMedio(
              color: context.colores.textoSecundario,
              etiqueta: 'A la lata de cigarrillos',
              monto: formatearARS(r.separacionCigarrillos.separadoCentavos),
            ),
          ),
        ],
      ],
    );
  }
}

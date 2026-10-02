// Pestaña "Inicio" de la navbar — banda de actualización, el CTA de "Vender"
// (la acción del mostrador, con su propio peso visual, y que además
// comunica el estado de la caja — ver `_CtaVender`) y dos accesos
// secundarios (Consultar precio, Movimiento de caja). Reacomodada (El dueño,
// 2026-09-18): "Conteo de stock" se mudó a Gestión (tarea de inventario, no
// algo que se abra a mitad de una venta); "Gasto rápido" e "Ingreso rápido"
// se fusionaron en "Movimiento de caja" (`pantalla_movimiento_caja.dart`).

import 'package:flutter/material.dart';

import '../domain/dinero.dart';
import '../domain/venta.dart';
import '../ui/comun/campo_texto.dart';
import '../ui/tema/tokens.dart';
import 'aviso_modo_local.dart';
import 'base_local.dart';
import 'pantalla_separaciones_companion.dart';
import 'tablero_companion.dart';
import 'cliente_companion.dart';
import 'mensaje_error.dart';
import 'navbar_companion.dart';
import 'pantalla_consultar_precio.dart';
import 'pantalla_movimiento_caja.dart';
import 'servicio_companion.dart';
import 'tema/chip_icono.dart';
import 'tema/colores_companion.dart';
import 'tema/hoja_vidrio.dart';
import 'tema/piezas_companion.dart';
import 'tema/presionable.dart';
import 'tema/superficie.dart';
import 'tema/tema_companion.dart';
import '../ui/tema/iconos.dart';
import '../domain/marca.dart';
import '../servicios/marca_actual.dart';
import 'tema/error_en_linea.dart';

class PantallaInicioCompanion extends StatelessWidget {
  const PantallaInicioCompanion({
    super.key,
    required this.nombreUsuario,
    required this.usuarioId,
    required this.sesion,
    required this.estadoCaja,
    required this.arqueoIntermedioVencido,
    required this.onHacerArqueoIntermedio,
    required this.navegando,
    required this.irA,
    required this.onAbrirMovimientoCaja,
    required this.onSincronizar,
    required this.carrito,
    required this.onVender,
    required this.servicio,
    required this.pcEmparejada,
    required this.actualizacionSinConexion,
  });

  final String? nombreUsuario;
  final int? usuarioId;
  final SesionCompanion? sesion;

  /// Para la franja de "modo local" (El dueño, 2026-09-17: hoy la app no
  /// avisaba en ningún lado que había caído al fallback offline — solo se
  /// notaba al intentar algo que ese modo no soporta, o con un error
  /// genérico). Se muestra en el lugar donde el usuario aterriza siempre al
  /// abrir la companion.
  final ServicioCompanion? servicio;

  /// Si hay una PC emparejada — sin esto, `AvisoModoLocal` aparecería
  /// siempre que no hay PC, aunque nunca se haya emparejado ninguna (su modo
  /// normal desde que el emparejamiento se volvió opcional, 2026-09-18).
  final bool pcEmparejada;

  /// El dueño, 2026-09-19: "no me salió la actualización" — el chequeo de
  /// actualización habla SIEMPRE directo con la PC (nunca cae al fallback
  /// offline del resto de la companion), así que una IP/token guardados
  /// viejos lo hacía fallar en silencio sin ninguna pista. Este aviso es
  /// puntual: solo aparece cuando ESTE chequeo específico no pudo alcanzar
  /// una PC que sí está emparejada — no reabre el diagnóstico general que
  /// El dueño pidió sacar (2026-09-07/18).
  final bool actualizacionSinConexion;

  /// Null mientras carga o si la caja está cerrada (el endpoint no tiene
  /// nada que resumir sin una sesión abierta). Trae el desglose de hoy
  /// para [_resumenVentasHoy].
  final EstadoCajaCompanion? estadoCaja;

  /// Aviso no bloqueante (El dueño, 2026-09-15) — true si pasaron 2hs desde el
  /// último arqueo. A diferencia de la pantalla de solo lectura "¿cómo
  /// vamos?" (accesible desde "Más" — Inicio dejó de tener su propio acceso
  /// al sacarse la tarjeta de estado de caja, 2026-09-19), esto abre el
  /// conteo real de dos fases. Se
  /// muestra como un ícono de notificación chico junto al saludo (El dueño,
  /// 2026-09-18: el `MaterialBanner` de ancho completo "está como pegote")
  /// — no como una franja que empuja el resto de la pantalla hacia abajo.
  final bool arqueoIntermedioVencido;
  final VoidCallback onHacerArqueoIntermedio;
  final bool navegando;
  final Future<void> Function(WidgetBuilder builder) irA;

  /// Abre "Movimiento de caja" — fusión de gasto/ingreso rápido (El dueño,
  /// 2026-09-18), con el tipo inicial ya elegido según de dónde se lo abra.
  final void Function(TipoMovimientoCaja tipo) onAbrirMovimientoCaja;

  /// El carrito (misma lista mutable que sostiene `PantallaMenuCompanion`)
  /// — solo para mostrar el contador en el acceso "Vender" (El dueño,
  /// 2026-09-17: el carrito dejó de ser el botón central, ahora vive acá).
  final List<LineaVenta> carrito;
  final VoidCallback onVender;

  /// Sincroniza con la PC (fase 2, "companion sin depender del escritorio")
  /// — el ÚNICO disparador que hay (El dueño, 2026-09-17: "que sea
  /// instantáneo" tiró abajo el disparo automático que había antes en cada
  /// arranque de la app: competía por el mismo acceso serializado a SQLite
  /// que cualquier otra consulta y volvía lenta a toda la companion).
  /// `CustomScrollView` en vez del `Column` que había antes: `RefreshIndicator`
  /// necesita un scrollable de verdad para reconocer el arrastre, y
  /// `SliverFillRemaining` preserva el centrado vertical de los accesos
  /// diarios que ya tenía este diseño (El dueño, 2026-09-13: "no me gusta cómo
  /// se ve el inicio" — ver el comentario de más abajo).
  final Future<void> Function() onSincronizar;

  @override
  Widget build(BuildContext context) {
    // Sin AppBar: el saludo pasa a ser parte del cuerpo, grande — una barra
    // fija con un título chico ("Hola, X") es el patrón menos aprovechado
    // de toda la pantalla (El dueño, 2026-09-18: "pensalo como una app
    // moderna"), la mayoría de las apps con una pantalla de inicio real
    // integran el saludo al contenido en vez de encerrarlo en una franja.
    // "Lenguaje de diseño" (El dueño, 2026-09-26, mock `MovilDashboard`):
    // fondo plano (sin las manchas de color del vidrio de antes) y, debajo
    // de vender y los accesos, el tablero del día (`TableroCompanion`), que
    // se relee solo cuando llegan datos nuevos.
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: onSincronizar,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _saludo(context)),
              SliverToBoxAdapter(
                child: AvisoModoLocal(servicio: servicio, pcEmparejada: pcEmparejada),
              ),
              if (actualizacionSinConexion) SliverToBoxAdapter(child: _avisoActualizacionSinConexion(context)),
              SliverToBoxAdapter(child: _accesosDiarios(context)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Espaciado.lg, 0, Espaciado.lg, Espaciado.lg),
                  // Sin `key` que cambie: rearmarlo desde cero con cada chequeo
                  // de la caja lo dejaba vacío un instante y hacía saltar la
                  // pantalla. Se relee solo con cada aviso de datos nuevos.
                  child: TableroCompanion(
                    db: baseLocalCompanion(),
                    alTocarSeparar: () => irA((_) => PantallaSeparacionesCompanion(db: baseLocalCompanion(), usuarioId: usuarioId ?? 0)),
                  ),
                ),
              ),
              // Espacio para que la navbar flotante no tape lo último
              // (`extendBody: true` en `PantallaMenuCompanion`).
              const SliverToBoxAdapter(child: SizedBox(height: NavbarCompanion.espacioReservado)),
            ],
          ),
        ),
      ),
    );
  }

  /// Mismo lenguaje visual que `AvisoModoLocal` (tarjeta con tinte, ícono +
  /// texto) pero para un caso distinto: acá SÍ hay una PC emparejada, solo
  /// que el chequeo de actualización puntual no pudo alcanzarla — sugiere
  /// el arreglo real (re-emparejar) en vez de dejarlo en silencio.
  Widget _avisoActualizacionSinConexion(BuildContext context) {
    final colores = context.colores;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Espaciado.lg, Espaciado.lg, Espaciado.lg, 0),
      child: Superficie(
        relleno: colores.textoTenue.withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg, vertical: Espaciado.md),
        child: Row(
          children: [
            Icon(IconosPlazoleta.systemUpdateAlt, size: 20, color: colores.textoSecundario),
            const SizedBox(width: Espaciado.sm),
            Expanded(
              child: Text(
                'No se pudo conectar con la PC para buscar actualizaciones — si sigue pasando, desconectá y volvé a escanear el QR.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colores.textoSecundario),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// El aviso de arqueo vencido (El dueño, 2026-09-15: "una sugerencia, no
  /// bloqueante"; 2026-09-18: el `MaterialBanner` de ancho completo "está
  /// como pegote") pasa a ser una campanita con punto junto al saludo — se
  /// nota sin empujar el resto de la pantalla hacia abajo.
  Widget _saludo(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Espaciado.xl, Espaciado.xl, Espaciado.xl, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ValueListenableBuilder<MarcaNegocio>(
              valueListenable: marcaActual,
              builder: (context, marca, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EtiquetaSeccion(marca.nombre),
                  const SizedBox(height: Espaciado.sm),
                  Text(
                    nombreUsuario == null ? 'Inicio' : 'Hola, $nombreUsuario',
                    style: textTheme.headlineLarge,
                  ),
                ],
              ),
            ),
          ),
          if (sesion?.abierta ?? false) _campanitaArqueo(context),
        ],
      ),
    );
  }

  Widget _campanitaArqueo(BuildContext context) {
    final colores = context.colores;
    return Presionable(
      radio: 999,
      etiqueta: arqueoIntermedioVencido ? 'Hacer arqueo (vencido)' : 'Hacer arqueo',
      onTap: onHacerArqueoIntermedio,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: colores.fondoBloque, shape: BoxShape.circle),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Icon(IconosPlazoleta.notificationsOutlined, color: colores.textoPrimario, size: 24),
            if (arqueoIntermedioVencido)
              Positioned(
                top: 11,
                right: 12,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: colores.error, shape: BoxShape.circle, border: Border.all(color: colores.fondoBloque, width: 2)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirCajaRapida(BuildContext context) async {
    final s = sesion;
    if (servicio == null || usuarioId == null || s == null) return;
    final abierta = await mostrarHojaVidrio<bool>(
      context,
      builder: (_) => _HojaAbrirCaja(
        servicio: servicio!,
        usuarioId: usuarioId!,
        fondoInicialSugeridoCentavos: s.fondoInicialSugeridoCentavos,
        lataQueSeArrastraCentavos: s.lataQueSeArrastraCentavos,
      ),
    );
    if (abierta == true) onVender();
  }

  /// Reacomodado (El dueño, 2026-09-18: "reacomodación de absolutamente todos
  /// los elementos... no cambios de skin"): "Vender" es LA acción del
  /// mostrador — antes competía en igualdad de condiciones con otros cuatro
  /// accesos en una grilla pareja, como si "vender" y "consultar un precio"
  /// pesaran lo mismo. Ahora es un CTA de ancho completo, arriba de todo; el
  /// resto (Consultar precio, Movimiento de caja) queda en una fila
  /// secundaria más chica. "Conteo de stock" se mudó a Gestión (es una
  /// tarea de fondo de inventario, no algo que se abra en medio de una
  /// venta) y "Gasto"/"Ingreso rápido" se fusionaron en "Movimiento de
  /// caja" — dos pantallas casi idénticas para una sola idea.
  Widget _accesosDiarios(BuildContext context) {
    final acentos = context.acentos;
    final cerrada = sesion != null && !sesion!.abierta;
    return Padding(
      padding: const EdgeInsets.all(Espaciado.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _CtaVender(
            contador: carrito.length,
            cerrada: cerrada,
            onTap: navegando ? null : (cerrada ? () => _abrirCajaRapida(context) : onVender),
          ),
          const SizedBox(height: Espaciado.md),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Tile(
                    icono: IconosPlazoleta.priceCheckOutlined,
                    color: acentos.debito,
                    titulo: 'Consultar precio',
                    onTap: navegando ? null : () => irA((_) => const PantallaConsultarPrecio()),
                  ),
                ),
                const SizedBox(width: Espaciado.md),
                Expanded(
                  child: _Tile(
                    icono: IconosPlazoleta.accountBalanceWalletOutlined,
                    color: acentos.mixto,
                    titulo: 'Movimiento de caja',
                    onTap: navegando ? null : () => onAbrirMovimientoCaja(TipoMovimientoCaja.gasto),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CtaVender extends StatelessWidget {
  const _CtaVender({required this.contador, required this.cerrada, required this.onTap});

  final int contador;
  final bool cerrada;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final subtitulo = cerrada
        ? 'Tocá para abrirla'
        : contador > 0
        ? '$contador producto(s) en el carrito'
        : 'Buscar y cobrar';
    if (cerrada) {
      return Presionable(
        radio: radioSuperficieCompanion + 4,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(Espaciado.xl),
          decoration: BoxDecoration(color: colores.fondoBloque, borderRadius: BorderRadius.circular(radioSuperficieCompanion + 4)),
          child: Row(
            children: [
              Icon(IconosPlazoleta.lockOutline, color: colores.textoSecundario, size: 28),
              const SizedBox(width: Espaciado.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Caja cerrada', style: textTheme.titleLarge),
                    Text(subtitulo, style: textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(IconosPlazoleta.lockOpenOutlined, color: colores.textoSecundario),
            ],
          ),
        ),
      );
    }
    return BloqueHero(
      onTap: onTap,
      minAlto: 196,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
            child: Text('Caja abierta', style: textTheme.labelMedium?.copyWith(color: Colors.white)),
          ),
          const SizedBox(height: Espaciado.xl),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Vender', style: textTheme.displayLarge?.copyWith(color: Colors.white)),
                    Text(subtitulo, style: textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.72))),
                  ],
                ),
              ),
              const BotonFlecha(tamanio: 56),
            ],
          ),
        ],
      ),
    );
  }
}

class _HojaAbrirCaja extends StatefulWidget {
  const _HojaAbrirCaja({
    required this.servicio,
    required this.usuarioId,
    required this.fondoInicialSugeridoCentavos,
    required this.lataQueSeArrastraCentavos,
  });

  final ServicioCompanion servicio;
  final int usuarioId;
  final int? fondoInicialSugeridoCentavos;
  final int? lataQueSeArrastraCentavos;

  @override
  State<_HojaAbrirCaja> createState() => _HojaAbrirCajaState();
}

class _HojaAbrirCajaState extends State<_HojaAbrirCaja> {
  final _fondoInicialCtrl = TextEditingController();
  bool _abriendo = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.fondoInicialSugeridoCentavos != null) {
      _fondoInicialCtrl.text = formatearARS(widget.fondoInicialSugeridoCentavos!, conSigno: false);
    }
  }

  @override
  void dispose() {
    _fondoInicialCtrl.dispose();
    super.dispose();
  }

  Future<void> _abrirCaja() async {
    final int fondoInicial;
    try {
      fondoInicial = _fondoInicialCtrl.text.trim().isEmpty ? 0 : parsearARS(_fondoInicialCtrl.text);
    } on FormatException {
      setState(() => _error = 'Fondo inicial inválido');
      return;
    }
    setState(() {
      _abriendo = true;
      _error = null;
    });
    try {
      await widget.servicio.abrirSesion(usuarioId: widget.usuarioId, fondoInicialCentavos: fondoInicial);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _abriendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Abrir caja', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: Espaciado.sm),
        const Text('No hay caja abierta en la PC ahora mismo.'),
        const SizedBox(height: Espaciado.md),
        CampoPlata(controller: _fondoInicialCtrl, etiqueta: 'Fondo inicial (caja normal)'),
        if (widget.lataQueSeArrastraCentavos != null) ...[
          const SizedBox(height: Espaciado.sm),
          Text(
            'Lata de cigarrillos: se arrastra sola, ya tiene '
            '${formatearARS(widget.lataQueSeArrastraCentavos!)} de antes — no hace falta contarla ahora.',
            style: TextStyle(color: context.colores.textoSecundario),
          ),
        ],
        if (_error != null) ...[const SizedBox(height: Espaciado.md), ErrorEnLinea(_error!)],
        const SizedBox(height: Espaciado.lg),
        FilledButton(
          onPressed: _abriendo ? null : _abrirCaja,
          child: _abriendo
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Abrir caja y vender'),
        ),
      ],
    );
  }
}

/// Tarjeta chica de acceso secundario.
class _Tile extends StatelessWidget {
  const _Tile({required this.icono, required this.color, required this.titulo, required this.onTap});

  final IconData icono;

  final Color color;
  final String titulo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Superficie(
      padding: EdgeInsets.zero,
      child: Presionable(
        radio: radioSuperficieCompanion,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Espaciado.xl - 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ChipIcono(icono: icono, color: color, tamanio: 48, tamanioIcono: 22),
              const SizedBox(height: Espaciado.xl),
              Text(titulo, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

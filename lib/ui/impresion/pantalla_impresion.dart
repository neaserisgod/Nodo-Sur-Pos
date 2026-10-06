// Impresión y posnet — desde 2026-09-26 es una sección de Configuración,
// no un apartado propio del menú (mismo motivo que Respaldo). Solo el
// contenido, sin barra de navegación — lo monta `pantalla_configuracion.dart`.
//
// Con el kit del mock v4 (`cfgBody('impresion')`, 2026-10-06): a la izquierda la terminal, el token, la carpeta de PDF y
// reimprimir una venta; a la derecha (360) cómo sale el ticket. El mock suponía una impresora USB: acá imprime la
// terminal Point, así que esa fila no está.

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../domain/dinero.dart';
import '../../domain/marca.dart';
import '../../domain/ticket.dart';
import '../../servicios/marca_actual.dart';
import '../kit/kit.dart';
import 'impresion_controlador.dart';

class ContenidoImpresion extends StatefulWidget {
  const ContenidoImpresion({super.key, required this.db, required this.usuarioId});

  final AppDatabase db;
  final int usuarioId;

  @override
  State<ContenidoImpresion> createState() => _ContenidoImpresionState();
}

class _ContenidoImpresionState extends State<ContenidoImpresion> {
  late final ImpresionControlador _c;
  late final TextEditingController _tokenCtrl;
  late final TextEditingController _terminalCtrl;
  late final TextEditingController _terminalCobroCtrl;
  final _busquedaNumeroCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _c = ImpresionControlador(widget.db);
    _tokenCtrl = TextEditingController();
    _terminalCtrl = TextEditingController();
    _terminalCobroCtrl = TextEditingController();
    _c.cargarTodo().then((_) {
      _tokenCtrl.text = _c.mpAccessToken ?? '';
      _terminalCtrl.text = _c.mpTerminalId ?? '';
      _terminalCobroCtrl.text = _c.mpTerminalCobroId ?? '';
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _tokenCtrl.dispose();
    _terminalCtrl.dispose();
    _terminalCobroCtrl.dispose();
    _busquedaNumeroCtrl.dispose();
    super.dispose();
  }

  Future<void> _elegirCarpeta() async {
    final ruta = await getDirectoryPath();
    if (ruta != null) await _c.guardarCarpetaTickets(ruta);
  }

  // Antes "Guardar PDF" quedaba deshabilitado sin ningún aviso si la
  // carpeta no estaba configurada — bug real reportado por el dueño: "doy a
  // imprimir y no sale nada de seleccionar". La primera vez que hace falta,
  // se pregunta acá mismo, en vez de mandar a la sección de más arriba.
  Future<void> _guardarPdf(int ventaId) async {
    if (_c.carpetaTickets == null) {
      final ruta = await getDirectoryPath();
      if (ruta == null) return;
      await _c.guardarCarpetaTickets(ruta);
    }
    await _c.guardarPdf(ventaId);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ImpresionControlador>.value(
      value: _c,
      child: Consumer<ImpresionControlador>(
        builder: (context, c, _) {
          if (c.cargando) return const SizedBox.shrink();
          final izquierda = _ColumnaConfig(
            c: c,
            tokenCtrl: _tokenCtrl,
            terminalCtrl: _terminalCtrl,
            terminalCobroCtrl: _terminalCobroCtrl,
            numeroCtrl: _busquedaNumeroCtrl,
            onElegirCarpeta: _elegirCarpeta,
            onGuardarPdf: _guardarPdf,
          );
          return LayoutBuilder(
            builder: (context, lim) => lim.maxWidth >= 860
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Expanded(child: izquierda), const SizedBox(width: 20), SizedBox(width: 360, child: _AsiSale(c: c))],
                  )
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [izquierda, const SizedBox(height: 20), _AsiSale(c: c)]),
          );
        },
      ),
    );
  }
}

class _ColumnaConfig extends StatelessWidget {
  const _ColumnaConfig({
    required this.c,
    required this.tokenCtrl,
    required this.terminalCtrl,
    required this.terminalCobroCtrl,
    required this.numeroCtrl,
    required this.onElegirCarpeta,
    required this.onGuardarPdf,
  });

  final ImpresionControlador c;
  final TextEditingController tokenCtrl;
  final TextEditingController terminalCtrl;
  final TextEditingController terminalCobroCtrl;
  final TextEditingController numeroCtrl;
  final VoidCallback onElegirCarpeta;
  final ValueChanged<int> onGuardarPdf;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final gap = const SizedBox(height: 12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tarjeta(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
          child: Row(
            children: [
              Ibox(Ic.mp, chico: true, fondo: p.papel, color: c.posnetConfigurado ? p.g : p.mute),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Terminal Point', style: estilo(17, 600, color: p.tinta)),
                    Text(
                      c.posnetConfigurado
                          ? 'Se puede cobrar con QR y tarjeta, e imprimir el ticket en la terminal.'
                          : 'Cargá el Access Token y la terminal, o usá la cuenta de Nodo Sur.',
                      style: estilo(14, 400, color: p.mute),
                    ),
                  ],
                ),
              ),
              c.posnetConfigurado ? const Etiqueta('Configurada', tono: TonoMock.g) : const Etiqueta('Sin configurar', tono: TonoMock.w),
            ],
          ),
        ),
        gap,
        Lista(filas: [
          Kv(
            'Carpeta de PDF',
            '',
            valorWidget: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Text(
                    // "Sin carpeta configurada" es un dato incompleto, no un error.
                    c.carpetaTickets ?? 'Sin carpeta configurada',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: estilo(16, 600, color: c.carpetaTickets == null ? p.mute : p.tinta),
                  ),
                ),
                const SizedBox(width: 10),
                Btn('Elegir', variante: VarBtn.ton, tam: TamBtn.xs, sobreGris: true, onTap: onElegirCarpeta),
              ],
            ),
          ),
          Interruptor(
            key: const Key('switch_usar_nodo_sur'),
            titulo: 'Cobrar e imprimir por Nodo Sur',
            detalle: 'Usa el Mercado Pago que el negocio conectó en horsepos.com/negocio, sin el access token de este equipo. '
                'Apagado, todo sigue como siempre. Sirve para probar sin borrar el token.',
            valor: c.usarNodoSur,
            onCambio: c.cambiarUsarNodoSur,
          ),
        ]),
        gap,
        Campo(
          key: const Key('campo_mp_token'),
          etiqueta: 'Access Token de Mercado Pago (Enter guarda)',
          controller: tokenCtrl,
          obscuro: true,
          onSubmitted: c.guardarAccessToken,
        ),
        gap,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Campo(key: const Key('campo_mp_terminal'), etiqueta: 'Terminal que imprime', controller: terminalCtrl, onSubmitted: c.guardarTerminalId),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Campo(
                key: const Key('campo_mp_terminal_cobro'),
                etiqueta: 'Terminal ID (cobro)',
                controller: terminalCobroCtrl,
                onSubmitted: c.guardarTerminalCobroId,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // El dueño tiene dos posnets: uno de cobro manual (no lo toca la app) y otro "del sistema", que puede ser el mismo
        // que imprime o uno distinto. Formato distinto al de impresión aunque sea LA MISMA terminal física (TRAMPAS.md,
        // "terminal_id de Mercado Pago: el mismo posnet necesita DOS formatos"): la Orders API de cobro pide MODELO__SERIAL.
        Text(
          'Cobro: formato "MODELO__SERIAL" (ej. NEWLAND_N950__N950NCC503383252), no el serial solo — distinto del de impresión '
          'aunque sea la misma terminal.',
          style: estilo(13, 400, color: p.mute, alto: 1.4),
        ),
        gap,
        Lista(filas: [
          Interruptor(
            key: const Key('switch_ticket_al_cobrar'),
            titulo: 'Imprimir el ticket en la terminal al cobrar con ella',
            detalle: 'Apenas se aprueba un cobro por QR o tarjeta, la terminal imprime el ticket (también lo que cobra el celular '
                'por esta PC). Si no sale, la venta igual queda cobrada.',
            valor: c.ticketAlCobrar,
            onCambio: c.cambiarTicketAlCobrar,
          ),
        ]),
        const SizedBox(height: 18),
        const Sec('Reimprimir una venta'),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Campo(
                key: const Key('campo_numero_venta'),
                etiqueta: 'N° de venta',
                controller: numeroCtrl,
                pista: 'Ej: 1184',
                teclado: TextInputType.number,
                onSubmitted: (valor) => c.buscar(numero: int.tryParse(valor)),
              ),
            ),
            const SizedBox(width: 8),
            Btn('Buscar', variante: VarBtn.ton, onTap: () => c.buscar(numero: int.tryParse(numeroCtrl.text))),
            const SizedBox(width: 8),
            Btn('Ver últimas', variante: VarBtn.ton, onTap: () {
              numeroCtrl.clear();
              c.buscar();
            }),
          ],
        ),
        if (c.resultados.isNotEmpty) ...[
          gap,
          Lista(filas: [
            for (final venta in c.resultados)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Venta #${venta.id}', style: estilo(17, 600, color: p.tinta)),
                          Text(_formatearFecha(venta.fecha), style: estilo(14, 400, color: p.mute, num: true)),
                        ],
                      ),
                    ),
                    Btn(
                      'Enviar a posnet',
                      variante: VarBtn.ton,
                      tam: TamBtn.xs,
                      sobreGris: true,
                      onTap: c.posnetConfigurado && !c.procesando ? () => c.reimprimirEnPosnet(venta.id) : null,
                    ),
                    const SizedBox(width: 8),
                    Btn('Guardar PDF', variante: VarBtn.ton, tam: TamBtn.xs, sobreGris: true, onTap: c.procesando ? null : () => onGuardarPdf(venta.id)),
                  ],
                ),
              ),
          ]),
        ],
        if (c.mensaje != null) ...[
          gap,
          Text(c.mensaje!, style: estilo(15, 500, color: c.mensaje!.startsWith('Error') ? p.b : p.mute)),
        ],
      ],
    );
  }
}

String _formatearFecha(DateTime fecha) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(fecha.day)}/${dos(fecha.month)}/${fecha.year} ${dos(fecha.hour)}:${dos(fecha.minute)}';
}

/// Vista previa del ticket con una venta de ejemplo, armada con el mismo orden que `contenidoTicketPosnetMp`
/// (encabezado, fecha, renglones, total, saludo) — si cambia el formato del posnet, cambia acá también. Va en blanco y
/// letra de máquina, como el papel, en claro y en oscuro.
class _AsiSale extends StatelessWidget {
  const _AsiSale({required this.c});

  final ImpresionControlador c;

  static final _ejemplo = construirTicket(
    fecha: DateTime(2026, 9, 26, 16, 52),
    vendedor: 'Vendedor',
    lineas: const [
      LineaTicket(nombreProducto: 'Cerveza lata', cantidad: 2, subtotalCentavos: 420000),
      LineaTicket(nombreProducto: 'Gaseosa cola', cantidad: 1, subtotalCentavos: 290000),
      LineaTicket(nombreProducto: 'Pan francés', cantidad: 1, gramos: 500, subtotalCentavos: 260000),
    ],
    desglose: const DesgloseTicket(redondeoCentavos: 30000),
  );

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final t = _ejemplo;
    const tinta = Color(0xFF121317);
    const mono = TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Consolas', 'Courier New'], fontSize: 13, height: 1.6, color: tinta);
    String dos(int n) => n.toString().padLeft(2, '0');
    Widget renglon(String izq, String der, {bool fuerte = false}) => Row(
      children: [
        Expanded(child: Text(izq, style: fuerte ? mono.copyWith(fontWeight: FontWeight.w700) : mono)),
        Text(der, style: fuerte ? mono.copyWith(fontWeight: FontWeight.w700) : mono),
      ],
    );
    Widget corte() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text('- ' * 40, maxLines: 1, overflow: TextOverflow.clip, style: mono.copyWith(color: const Color(0xFFAAAAAA))),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: p.linea, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ValueListenableBuilder<MarcaNegocio>(
                valueListenable: marcaActual,
                builder: (context, marca, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, l) in marca.encabezadoTicketEfectivo.split('\n').indexed)
                      Text(l, textAlign: TextAlign.center, style: i == 0 ? mono.copyWith(fontSize: 15, fontWeight: FontWeight.w700) : mono),
                  ],
                ),
              ),
              Text(
                '${dos(t.fecha.day)}/${dos(t.fecha.month)}/${t.fecha.year} ${dos(t.fecha.hour)}:${dos(t.fecha.minute)}',
                textAlign: TextAlign.center,
                style: mono,
              ),
              corte(),
              for (final l in t.lineas)
                renglon('${l.gramos != null ? '${l.gramos} g' : '${l.cantidad} ×'} ${l.nombreProducto}', formatearARS(l.subtotalCentavos, separado: true)),
              corte(),
              if (t.desglose.redondeoCentavos > 0) renglon('Redondeo', '+${formatearARS(t.desglose.redondeoCentavos, separado: true)}'),
              renglon('TOTAL', formatearARS(t.totalCentavos, separado: true), fuerte: true),
              const SizedBox(height: 10),
              const Text('Gracias por su compra', textAlign: TextAlign.center, style: mono),
              const SizedBox(height: 6),
              Text('Vista previa del ticket', textAlign: TextAlign.center, style: mono.copyWith(color: const Color(0xFF6B7080))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Btn(
          'Imprimir prueba',
          key: const Key('boton_ticket_prueba'),
          variante: VarBtn.ton,
          ancho: true,
          onTap: c.posnetConfigurado && !c.procesando ? c.ticketDePrueba : null,
        ),
        if (!c.posnetConfigurado) ...[
          const SizedBox(height: 6),
          Text('Cargá el Access Token y la terminal para probar.', textAlign: TextAlign.center, style: estilo(13.5, 400, color: p.mute)),
        ],
      ],
    );
  }
}

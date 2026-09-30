// Impresión y posnet — desde 2026-09-26 es una sección de Configuración,
// no un apartado propio del menú (mismo motivo que Respaldo). Solo el
// contenido, sin barra de navegación — lo monta `pantalla_configuracion.dart`.

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../domain/dinero.dart';
import '../../domain/ticket.dart';
import '../comun/botones.dart';
import '../comun/campo_texto.dart';
import '../comun/estado_vacio.dart';
import '../comun/tarjetas.dart';
import '../tema/superficie.dart';
import '../tema/tema.dart';
import '../tema/tokens.dart';
import 'impresion_controlador.dart';
import '../../domain/marca.dart';
import '../../servicios/marca_actual.dart';

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
  // carpeta no estaba configurada — bug real reportado por Bruno: "doy a
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
          return c.cargando
              ? const SizedBox.shrink()
              // "Lenguaje de diseño" (mock `ConfigImpresion`): a la
              // izquierda lo que se configura una vez; a la derecha, cómo
              // sale el ticket de verdad (mismo formato que manda el posnet)
              // con la prueba al pie. El mock suponía una impresora USB con
              // ancho de papel, cajón y mensaje al pie: acá imprime la
              // terminal Point y el encabezado es fijo en el código
              // (CLAUDE.md), así que esas opciones no existen.
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ListView(
                        children: [
                          _ColumnaConfig(
                            c: c,
                            tokenCtrl: _tokenCtrl,
                            terminalCtrl: _terminalCtrl,
                            terminalCobroCtrl: _terminalCobroCtrl,
                            onElegirCarpeta: _elegirCarpeta,
                          ),
                          const SizedBox(height: Espaciado.md),
                          _ColumnaBusqueda(c: c, numeroCtrl: _busquedaNumeroCtrl, onGuardarPdf: _guardarPdf),
                        ],
                      ),
                    ),
                    const SizedBox(width: Espaciado.md),
                    SizedBox(
                      width: 380,
                      child: SingleChildScrollView(child: _AsiSale(c: c)),
                    ),
                  ],
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
    required this.onElegirCarpeta,
  });

  final ImpresionControlador c;
  final TextEditingController tokenCtrl;
  final TextEditingController terminalCtrl;
  final TextEditingController terminalCobroCtrl;
  final VoidCallback onElegirCarpeta;

  @override
  Widget build(BuildContext context) {
    return Superficie(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Terminal que imprime', style: Theme.of(context).textTheme.titleMedium)),
              c.posnetConfigurado
                  ? const Insignia(texto: 'Configurada', tono: Tono.ganancia)
                  : const Insignia(texto: 'Sin configurar', tono: Tono.alerta),
            ],
          ),
          const SizedBox(height: Espaciado.lg),
          CampoTexto(
            key: const Key('campo_mp_token'),
            controller: tokenCtrl,
            etiqueta: 'Access Token de MercadoPago',
            obscureText: true,
            onSubmitted: c.guardarAccessToken,
          ),
          const SizedBox(height: Espaciado.md),
          CampoTexto(
            key: const Key('campo_mp_terminal'),
            controller: terminalCtrl,
            etiqueta: 'Terminal ID',
            onSubmitted: c.guardarTerminalId,
          ),
          const SizedBox(height: Espaciado.xl),
          Text('Terminal que cobra (fase 12)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Espaciado.sm),
          Text(
            // Bruno tiene dos posnets físicos separados: uno de cobro
            // manual (no lo toca la app) y otro "del sistema", que puede
            // ser el mismo que imprime o uno distinto — por eso es un
            // campo aparte. Formato distinto al de arriba, aunque sea LA
            // MISMA terminal física (TRAMPAS.md, "terminal_id de Mercado
            // Pago: el mismo posnet necesita DOS formatos"): acá va
            // "MODELO__SERIAL" (ej. "NEWLAND_N950__N950NCC503383252"), no
            // el serial solo — la Orders API de cobro lo exige así.
            'Formato "MODELO__SERIAL" (ej. NEWLAND_N950__N950NCC503383252), '
            'no el serial solo — distinto del campo de arriba aunque sea la '
            'misma terminal.',
            style: TextStyle(color: context.colores.textoSecundario, fontSize: 12),
          ),
          const SizedBox(height: Espaciado.md),
          CampoTexto(
            key: const Key('campo_mp_terminal_cobro'),
            controller: terminalCobroCtrl,
            etiqueta: 'Terminal ID (cobro)',
            onSubmitted: c.guardarTerminalCobroId,
          ),
          const SizedBox(height: Espaciado.xl),
          Text('Carpeta de tickets (PDF)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Espaciado.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  // "Sin carpeta configurada" es un dato incompleto, no un
                  // error — mismo criterio que un fijo sin cargar en
                  // Equilibrio: textoSecundario, sin color de estado.
                  c.carpetaTickets ?? 'Sin carpeta configurada',
                  style: c.carpetaTickets == null ? TextStyle(color: context.colores.textoSecundario) : null,
                ),
              ),
              BotonSecundario(texto: 'Elegir', onPressed: onElegirCarpeta),
            ],
          ),
          if (c.mensaje != null) ...[
            const SizedBox(height: Espaciado.lg),
            Text(
              c.mensaje!,
              style: TextStyle(color: c.mensaje!.startsWith('Error') ? context.colores.error : context.colores.textoSecundario),
            ),
          ],
        ],
      ),
    );
  }
}

class _ColumnaBusqueda extends StatelessWidget {
  const _ColumnaBusqueda({required this.c, required this.numeroCtrl, required this.onGuardarPdf});

  final ImpresionControlador c;
  final TextEditingController numeroCtrl;
  final ValueChanged<int> onGuardarPdf;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Superficie(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Reimprimir una venta', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: Espaciado.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 160,
                    child: CampoTexto(
                      key: const Key('campo_numero_venta'),
                      controller: numeroCtrl,
                      etiqueta: 'N° de venta',
                      onSubmitted: (valor) {
                        final numero = int.tryParse(valor);
                        c.buscar(numero: numero);
                      },
                    ),
                  ),
                  const SizedBox(width: Espaciado.md),
                  BotonSecundario(
                    texto: 'Ver últimas',
                    onPressed: () {
                      numeroCtrl.clear();
                      c.buscar();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: Espaciado.md),
        Superficie(
          child: c.resultados.isEmpty
              ? const EstadoVacio(mensaje: 'Sin resultados')
              : Column(
                  children: [
                    for (var i = 0; i < c.resultados.length; i++)
                      Builder(
                        builder: (context) {
                          final venta = c.resultados[i];
                          // `ListTile`, no `Row` (a diferencia de otras filas de
                          // dos botones del kit): su `trailing` reserva un ancho
                          // acotado para el `Wrap` de botones y el título nunca
                          // fuerza un overflow cuando la columna es angosta.
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('Venta #${venta.id}'),
                            subtitle: Text(_formatearFecha(venta.fecha)),
                            trailing: Wrap(
                              spacing: Espaciado.sm,
                              runSpacing: Espaciado.sm,
                              children: [
                                BotonSecundario(
                                  texto: 'Enviar a posnet',
                                  onPressed: c.posnetConfigurado && !c.procesando ? () => c.reimprimirEnPosnet(venta.id) : null,
                                ),
                                BotonSecundario(texto: 'Guardar PDF', onPressed: c.procesando ? null : () => onGuardarPdf(venta.id)),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

String _formatearFecha(DateTime fecha) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(fecha.day)}/${dos(fecha.month)}/${fecha.year} ${dos(fecha.hour)}:${dos(fecha.minute)}';
}

/// Vista previa del ticket con una venta de ejemplo, armada con el mismo
/// orden que `contenidoTicketPosnetMp` (encabezado, fecha, renglones,
/// total, saludo) — si cambia el formato del posnet, cambia acá también.
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
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final t = _ejemplo;
    String dos(int n) => n.toString().padLeft(2, '0');
    final fuerte = textTheme.titleMedium?.copyWith(fontWeight: Pesos.fuerte);
    Widget renglon(String izq, String der, {bool destacado = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(izq, style: destacado ? fuerte : null)),
          Text(der, style: (destacado ? fuerte : textTheme.bodyMedium)?.tabular),
        ],
      ),
    );
    return TarjetaSeccion(
      titulo: 'Así sale',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(Espaciado.lg),
            decoration: BoxDecoration(color: colores.fondo, borderRadius: BorderRadius.circular(radioControlEscritorio)),
            child: DefaultTextStyle.merge(
              style: textTheme.bodyMedium,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ValueListenableBuilder<MarcaNegocio>(
                    valueListenable: marcaActual,
                    builder: (context, marca, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final l in marca.encabezadoTicketEfectivo.split('\n'))
                          Text(
                            l,
                            textAlign: TextAlign.center,
                            style: textTheme.titleSmall?.copyWith(fontWeight: Pesos.fuerte),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Espaciado.xs),
                  Text(
                    '${dos(t.fecha.day)}/${dos(t.fecha.month)}/${t.fecha.year} ${dos(t.fecha.hour)}:${dos(t.fecha.minute)}',
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall,
                  ),
                  const Divider(),
                  for (final l in t.lineas)
                    renglon(
                      '${l.nombreProducto} (${l.gramos != null ? '${l.gramos}g' : 'x${l.cantidad}'})',
                      formatearARS(l.subtotalCentavos),
                    ),
                  if (t.desglose.redondeoCentavos > 0) renglon('Redondeo', formatearARS(t.desglose.redondeoCentavos)),
                  const Divider(),
                  renglon('TOTAL', formatearARS(t.totalCentavos), destacado: true),
                  const SizedBox(height: Espaciado.sm),
                  const Text('Gracias por su compra', textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
          const SizedBox(height: Espaciado.md),
          BotonPrimario(texto: 'Ticket de prueba', onPressed: c.posnetConfigurado && !c.procesando ? c.ticketDePrueba : null),
          if (!c.posnetConfigurado) ...[
            const SizedBox(height: Espaciado.xs),
            Text('Cargá el Access Token y la terminal para probar.', style: textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

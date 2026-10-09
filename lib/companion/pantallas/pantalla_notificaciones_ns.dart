// Notificaciones, tal cual el mock (docs/03 C4): una tarjeta por pendiente
// real (separar, sin stock, versión nueva) más "Todo al día" cuando no queda
// ninguno, y la sección "Antes".

import 'package:flutter/material.dart';

import '../app_ns.dart';
import '../cliente_companion.dart' show SesionCerradaCompanion;
import '../funciones_ns.dart' show AccionFuncion;
import '../kit/kit_ns.dart';
import '../sync_nube_companion.dart' show avisosMpCompanion;

class PantallaNotificacionesNs extends StatelessWidget {
  const PantallaNotificacionesNs({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppNs.of(context);
    final ns = context.ns;
    return Scaffold(
      backgroundColor: ns.paper,
      body: SafeArea(
        child: PantallaEntradaNs(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CabeceraSubNs(titulo: 'Notificaciones', onVolver: () => Navigator.of(context).maybePop()),
                const SizedBox(height: 14),
                Expanded(
                  child: ListenableBuilder(
                    listenable: app.pendientes,
                    builder: (context, _) => _Contenido(app: app, pend: app.pendientes.value),
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

class _Contenido extends StatelessWidget {
  const _Contenido({required this.app, required this.pend});
  final ControladorAppNs app;
  final PendientesNs pend;

  void _ir(BuildContext context, VoidCallback accion) {
    Navigator.of(context).pop();
    accion();
  }

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    final filas = <Widget>[];
    if (pend.haySeparar) {
      filas.add(_Pendiente(
        fondo: ns.wbg,
        color: ns.w,
        icono: IconoNs.billetera,
        titulo: 'Separar para proveedores',
        detalle: '${pend.proveedoresSeparados} de ${pend.proveedoresTotal} separados',
        derecha: plataNs(pend.faltaSepararCentavos),
        onTap: () => _ir(context, () {
          app.segmentoCaja.value = 1;
          app.irAPestania(PestaniaNs.caja);
        }),
      ));
    }
    if (pend.arqueoVencido) {
      filas.add(_Pendiente(
        fondo: ns.wbg,
        color: ns.w,
        icono: IconoNs.calculadora,
        titulo: 'Contá la caja',
        detalle: 'Pasaron ${duracionTextoNs(pend.minutosDesdeConteo)} desde el último conteo. Es opcional: lo que cuentes queda para el cierre.',
        onTap: () => _ir(context, () => app.ejecutarFuncion(AccionFuncion.contarCaja)),
      ));
    }
    if (pend.sinStock > 0) {
      filas.add(_Pendiente(
        fondo: ns.bbg,
        color: ns.b,
        icono: IconoNs.producto,
        titulo: pend.sinStock == 1 ? '1 producto sin stock' : '${pend.sinStock} productos sin stock',
        detalle: 'Tocá para contarlos y reponer',
        onTap: () => _ir(context, () => app.abrirConteo(soloSinStock: true)),
      ));
    }
    if (pend.hayActualizacion) {
      filas.add(_Pendiente(
        fondo: ns.ibg,
        color: ns.i,
        icono: IconoNs.descarga,
        titulo: 'Hay una versión nueva',
        detalle: 'Actualizá cuando no estés vendiendo',
        onTap: () => app.abrirActualizacion(),
      ));
    }
    final avisos = avisosMpCompanion;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        // Avisos de Mercado Pago (solo sin la PC, ver `_iniciarAvisosMp` del menú): solo avisan, "Visto" los saca.
        if (avisos != null)
          ValueListenableBuilder(
            valueListenable: avisos.pendientes,
            builder: (context, lista, _) => lista.isEmpty
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SeccionNs('Mercado Pago'),
                      const SizedBox(height: 10),
                      for (final a in lista) ...[
                        Container(
                          padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
                          decoration: BoxDecoration(color: ns.wbg, borderRadius: BorderRadius.circular(26)),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(a.titulo, style: estiloNs(16, peso: FontWeight.w600, color: ns.w)),
                                    const SizedBox(height: 2),
                                    Text(a.texto, style: estiloNs(13, altura: 1.35, color: ns.w)),
                                  ],
                                ),
                              ),
                              BotonNs(texto: 'Visto', onTap: () => avisos.marcarVisto(a.aviso), alto: 40, tamanio: 14, fondo: ns.paper, color: ns.ink, rellenar: false, paddingH: 16),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
        const SeccionNs('Pendientes'),
        const SizedBox(height: 10),
        for (var i = 0; i < filas.length; i++) ...[EntradaNs(retraso: Duration(milliseconds: 70 * i), child: filas[i]), const SizedBox(height: 10)],
        if (filas.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(color: ns.gbg, borderRadius: BorderRadius.circular(26)),
            child: Text('Todo al día: no hay nada pendiente.', style: estiloNs(15, peso: FontWeight.w600, color: ns.g)),
          ),
        const SizedBox(height: 10),
        const SeccionNs('Antes'),
        const SizedBox(height: 10),
        _Antes(app: app),
      ],
    );
  }
}

class _Pendiente extends StatelessWidget {
  const _Pendiente({required this.fondo, required this.color, required this.icono, required this.titulo, required this.detalle, required this.onTap, this.derecha});

  final Color fondo;
  final Color color;
  final IconoNs icono;
  final String titulo;
  final String detalle;
  final String? derecha;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return PresionNs(
      onTap: onTap,
      etiqueta: titulo,
      child: Container(
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(28)),
        child: Row(
          children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: ns.paper, shape: BoxShape.circle), alignment: Alignment.center, child: IconoNsWidget(icono, tamanio: 22, color: color)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(titulo, style: estiloNs(16, peso: FontWeight.w600, track: -0.02, altura: 1.2, color: color)),
                  const SizedBox(height: 2),
                  Opacity(opacity: 0.85, child: Text(detalle, style: estiloNs(13, altura: 1.3, color: color))),
                ],
              ),
            ),
            if (derecha != null) ...[const SizedBox(width: 10), Text(derecha!, style: estiloNs(17, peso: FontWeight.w600, color: color, tabular: true))],
            const SizedBox(width: 6),
            IconoNsWidget(IconoNs.chevron, tamanio: 18, color: color, grosor: 2.2),
          ],
        ),
      ),
    );
  }
}

/// "Antes": el último cierre guardado y el estado de la conexión, con datos reales.
class _Antes extends StatefulWidget {
  const _Antes({required this.app});
  final ControladorAppNs app;

  @override
  State<_Antes> createState() => _AntesState();
}

class _AntesState extends State<_Antes> {
  SesionCerradaCompanion? _cierre;
  bool _cargado = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final lista = await widget.app.servicio?.sesionesCerradas(limite: 1);
      if (mounted) setState(() => _cierre = (lista == null || lista.isEmpty) ? null : lista.first);
    } catch (_) {
      // Sin cierre que mostrar: no es un error.
    }
    if (mounted) setState(() => _cargado = true);
  }

  static const _dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
  static const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

  String _fecha(DateTime d) => '${_dias[d.weekday - 1]} ${d.day} ${_meses[d.month - 1]}';

  @override
  Widget build(BuildContext context) {
    final c = _cierre;
    final sinConexion = widget.app.sinConexion;
    final filas = <(String, String)>[
      if (c != null)
        (
          'Cierre guardado',
          '${_fecha(c.fechaCierre ?? c.fechaApertura)} · ${(c.diferenciaCentavos ?? 0) == 0 && (c.mpDiferenciaCentavos ?? 0) == 0 && (c.lataDiferenciaCentavos ?? 0) == 0 ? 'sin diferencias' : 'con diferencias'}',
        ),
      if (widget.app.pcEmparejada) (sinConexion ? 'Sin conexión con la PC' : 'Sincronizado con la PC', sinConexion ? 'Usás los datos del celular' : 'Todo al día'),
    ];
    if (!_cargado || filas.isEmpty) return const SizedBox.shrink();
    final ns = context.ns;
    return Column(
      children: [
        for (final f in filas) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(24)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.$1, style: estiloNs(15, peso: FontWeight.w600, color: ns.ink)),
                const SizedBox(height: 2),
                Text(f.$2, style: estiloNs(14, color: ns.mute)),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

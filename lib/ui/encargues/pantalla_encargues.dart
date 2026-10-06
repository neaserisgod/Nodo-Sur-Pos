// Encargues (El dueño, 2026-10-02): lo que un cliente pidió y ya está en el local, apartado hasta que lo retire.
// Apartar saca el stock en el momento; "Entregar" abre una venta con eso cargado; "Cancelar" lo devuelve al stock.
// "Entregar y anotar deuda" (2026-10-03, el fiado se unificó acá): se lo lleva sin pagar y queda una deuda para cobrar
// después, en la sección "Deudas" de esta misma pantalla.
// Las reglas viven en `repositorio_encargues.dart`; esta pantalla solo las muestra y las dispara.

// Rediseño v4 (2026-10-06), desde cero como el mock (`SCR.encargues`): tres bloques arriba (apartados, deudas por
// cobrar, señas cobradas), y dos listas lado a lado — los apartados con Entregar / Cancelar, y las deudas con Cobrar.
// El buscador de la barra se fue con el mock: con una o dos docenas de filas, la búsqueda sobraba.

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/repositorio_encargues.dart';
import '../../data/repositorio_pendientes.dart' show PendienteYaResueltoException, cobrarDeuda;
import '../../data/repositorio_ventas.dart' show SesionCerradaException;
import '../comun/armazon_gestion.dart';
import '../comun/aviso_superior.dart';
import '../kit/kit.dart';
import '../navegacion/navegacion_gestion.dart';
import '../navegacion/refresco_por_celular.dart';
import 'dialogo_nuevo_encargue.dart';

class PantallaEncargues extends StatefulWidget {
  const PantallaEncargues({super.key, required this.db, required this.usuarioId, this.sesionCajaId});

  final AppDatabase db;
  final int usuarioId;
  final int? sesionCajaId;

  @override
  State<PantallaEncargues> createState() => _PantallaEnarguesState();
}

class _PantallaEnarguesState extends State<PantallaEncargues> with RefrescoPorCelular {
  List<Encargue> _encargues = const [];
  List<Deuda> _deudas = const [];
  bool _cargando = true;

  @override
  void alCambiarDesdeElCelular() => _cargar();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final lista = await listarEnarguesPendientes(widget.db);
    final deudas = await listarDeudas(widget.db);
    if (!mounted) return;
    setState(() {
      _encargues = lista;
      _deudas = deudas;
      _cargando = false;
    });
  }

  Future<void> _nuevo() async {
    final creado = await mostrarDialogoNuevoEncargue(
      context,
      db: widget.db,
      usuarioId: widget.usuarioId,
      sesionCajaId: widget.sesionCajaId,
    );
    if (creado == true) await _cargar();
  }

  Future<void> _entregar(Encargue e) => navegarASeccionDeGestion(
    context,
    'venta',
    db: widget.db,
    usuarioId: widget.usuarioId,
    sesionCajaId: widget.sesionCajaId,
    encarguePendienteId: e.id,
  );

  /// Un aviso con un solo botón ("Entendido").
  Future<void> _avisar(String titulo, String texto) => mostrarModalMock<void>(
    context,
    builder: (context) => ModalMock(
      titulo: titulo,
      ancho: AnchoModal.angosto,
      cuerpo: [Nota(texto: texto, tono: TonoMock.w)],
      pie: [Btn('Entendido', variante: VarBtn.blue, tam: TamBtn.lg, ancho: true, onTap: () => Navigator.of(context).pop())],
    ),
  );

  /// Una confirmación de dos botones: devuelve true si se confirma.
  Future<bool> _confirmar({
    required String titulo,
    required String texto,
    required String si,
    String no = 'Volver',
    bool rojo = false,
  }) async {
    final r = await mostrarModalMock<bool>(
      context,
      builder: (context) => ModalMock(
        titulo: titulo,
        ancho: AnchoModal.angosto,
        cuerpo: [Nota(texto: texto)],
        pie: [
          Btn(si, variante: rojo ? VarBtn.red : VarBtn.blue, tam: TamBtn.lg, ancho: true, onTap: () => Navigator.of(context).pop(true)),
          Btn(no, variante: VarBtn.out, ancho: true, onTap: () => Navigator.of(context).pop(false)),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _cancelar(Encargue e) async {
    final sena = e.senaCentavos;
    if (sena > 0 && widget.sesionCajaId == null) {
      await _avisar(
        'No hay una caja abierta',
        '${e.nombreCliente} dejó ${pesos(sena)} de seña. Para cancelar y devolvérsela hay que abrir la caja.',
      );
      return;
    }
    final confirmado = await _confirmar(
      titulo: '¿Cancelar el encargue de ${e.nombreCliente}?',
      texto: [
        'Lo apartado (${e.resumen}) vuelve al stock.',
        if (sena > 0) 'Se le devuelven ${pesos(sena)} de seña, por ${e.senaEsEfectivo ? 'el cajón' : 'Mercado Pago'}.',
      ].join(' '),
      si: 'Cancelar encargue',
      rojo: true,
    );
    if (!confirmado) return;
    String? aviso;
    try {
      await cancelarEncargue(widget.db, e.id, usuarioId: widget.usuarioId, sesionCajaId: widget.sesionCajaId);
    } on SesionCerradaException {
      aviso = 'La caja ya se cerró: el encargue no se canceló. Abrí la caja de nuevo.';
    }
    await _cargar();
    if (aviso != null && mounted) mostrarAviso(context, aviso);
  }

  Future<void> _entregarADeuda(Encargue e) async {
    final confirmado = await _confirmar(
      titulo: '¿Entregar a ${e.nombreCliente} y anotar la deuda?',
      texto:
          'Se lleva ${e.resumen} sin pagar. Queda anotado en Deudas, a los precios de hoy, para cobrarle después. El stock ya está descontado.',
      si: 'Entregar y anotar',
    );
    if (!confirmado) return;
    await entregarEncargueADeuda(widget.db, e.id, usuarioId: widget.usuarioId);
    await _cargar();
  }

  Future<void> _cobrarDeuda(Deuda d) async {
    final sesionId = widget.sesionCajaId;
    if (sesionId == null) {
      await _avisar('No hay una caja abierta', 'Para cobrar una deuda hay que abrir la caja: el cobro entra como una venta del día.');
      return;
    }
    final efectivo = await mostrarModalMock<bool>(
      context,
      builder: (context) => ModalMock(
        titulo: 'Cobrar a ${d.nombreCliente}',
        subtitulo: '¿Cómo paga los ${pesos(d.montoCentavos)}?',
        ancho: AnchoModal.angosto,
        cuerpo: const [Nota(texto: 'El cobro entra como una venta del día, en la caja que elijas.')],
        pie: [
          Btn('Efectivo', variante: VarBtn.blue, tam: TamBtn.lg, ancho: true, onTap: () => Navigator.of(context).pop(true)),
          Btn('Mercado Pago', variante: VarBtn.out, ancho: true, onTap: () => Navigator.of(context).pop(false)),
        ],
      ),
    );
    if (efectivo == null) return;
    String? aviso;
    try {
      await cobrarDeuda(widget.db, pendienteId: d.id, sesionCajaId: sesionId, usuarioId: widget.usuarioId, efectivo: efectivo);
    } on PendienteYaResueltoException {
      aviso = 'Esa deuda ya estaba cobrada: no se registró otro cobro.';
    } on SesionCerradaException {
      aviso = 'La caja ya se cerró: el cobro no se guardó.';
    }
    await _cargar();
    if (aviso != null && mounted) mostrarAviso(context, aviso);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final porCobrar = _deudas.fold(0, (a, d) => a + d.montoCentavos);
    final senas = _encargues.fold(0, (a, e) => a + e.senaCentavos);
    return PantallaGestion(
      db: widget.db,
      claveActiva: 'encargues',
      usuarioId: widget.usuarioId,
      sesionCajaId: widget.sesionCajaId,
      titulo: 'Encargues',
      subtitulo: 'Lo que ya está en el local y se apartó para un cliente',
      acciones: [Btn('Nuevo encargue', variante: VarBtn.dark, icono: Ic.plus, onTap: _nuevo)],
      child: _cargando
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Aparecer.revelar(
                          child: BloqueHero(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Apartados', style: estilo(14, 600, color: p.heroSub)),
                                const SizedBox(height: 6),
                                NumeroQueCuenta(
                                  valor: _encargues.length,
                                  formato: (v) => '$v',
                                  estilo: estilo(40, 550, color: p.sobreHero, em: -.04, num: true),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Aparecer.revelar(
                          orden: 1,
                          child: _Bloque(titulo: 'Deudas por cobrar', valor: porCobrar, tono: TonoMock.w),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Aparecer.revelar(
                          orden: 2,
                          child: _Bloque(titulo: 'Señas cobradas', valor: senas),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: _encargues.isEmpty && _deudas.isEmpty
                      ? Vacio(key: const Key('encargues_vacio'), texto: 'No hay encargues pendientes.', icono: Ic.cal)
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _Columna(
                                titulo: 'Apartados',
                                vacio: 'Nada apartado ahora.',
                                cantidad: _encargues.length,
                                fila: (i) => _FilaEncargue(
                                  encargue: _encargues[i],
                                  alEntregar: () => _entregar(_encargues[i]),
                                  alAnotarDeuda: () => _entregarADeuda(_encargues[i]),
                                  alCancelar: () => _cancelar(_encargues[i]),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _Columna(
                                titulo: 'Deudas',
                                vacio: 'Nadie debe nada.',
                                cantidad: _deudas.length,
                                fila: (i) => _FilaDeuda(deuda: _deudas[i], alCobrar: () => _cobrarDeuda(_deudas[i])),
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

class _Bloque extends StatelessWidget {
  const _Bloque({required this.titulo, required this.valor, this.tono});
  final String titulo;
  final int valor;
  final TonoMock? tono;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final color = tono == null ? p.tinta : tono!.colores(p).$2;
    return Tarjeta(
      tono: tono,
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: estilo(14, 600, color: tono == null ? p.mute : color)),
          const SizedBox(height: 6),
          NumeroQueCuenta(
            valor: valor,
            formato: pesos,
            estilo: estilo(40, 550, color: color, em: -.04, num: true),
          ),
        ],
      ),
    );
  }
}

/// Una de las dos columnas: el título de sección y la `.list` que ocupa el resto del alto.
class _Columna extends StatelessWidget {
  const _Columna({required this.titulo, required this.vacio, required this.cantidad, required this.fila});

  final String titulo;
  final String vacio;
  final int cantidad;
  final Widget Function(int i) fila;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Sec(titulo),
        const SizedBox(height: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: ColoredBox(
              color: p.s,
              child: cantidad == 0
                  ? Vacio(texto: vacio, icono: null)
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: cantidad,
                      separatorBuilder: (_, _) => ColoredBox(color: p.pelo, child: const SizedBox(height: 1)),
                      itemBuilder: (_, i) => Aparecer.tarjeta(orden: i, child: fila(i)),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

String _inicial(String nombre) => nombre.trim().isEmpty ? '?' : nombre.trim()[0].toUpperCase();

class _FilaEncargue extends StatelessWidget {
  const _FilaEncargue({required this.encargue, required this.alEntregar, required this.alAnotarDeuda, required this.alCancelar});

  final Encargue encargue;
  final VoidCallback alEntregar;
  final VoidCallback alAnotarDeuda;
  final VoidCallback alCancelar;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final e = encargue;
    return Padding(
      key: Key('encargue_${e.id}'),
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
      child: Row(
        children: [
          Avatar(_inicial(e.nombreCliente), fondo: p.papel, diametro: 42),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Encargue de ${e.nombreCliente}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: estilo(17, 550, color: p.tinta),
                ),
                for (final l in e.lineas)
                  Text(
                    l.texto,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: estilo(14, 400, color: p.mute),
                  ),
                Wrap(
                  spacing: 10,
                  children: [
                    Text('desde el ${e.desde.day}/${e.desde.month}', style: estilo(13, 400, color: p.soft)),
                    if (e.senaCentavos > 0) ...[
                      Text(
                        'Seña ${pesos(e.senaCentavos)} · ${e.senaEsEfectivo ? 'efectivo' : 'Mercado Pago'}',
                        key: Key('encargue_sena_${e.id}'),
                        style: estilo(13, 600, color: p.g),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // A 1366 la columna es angosta: los botones bajan de a uno en vez de empujar el nombre.
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width >= 1700 ? 440 : 230),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                Btn('Entregar', tam: TamBtn.sm, variante: VarBtn.blue, onTap: alEntregar),
                if (e.senaCentavos == 0)
                  Btn('Entregar y anotar deuda', tam: TamBtn.sm, variante: VarBtn.ton, sobreGris: true, onTap: alAnotarDeuda),
                Btn('Cancelar', tam: TamBtn.sm, variante: VarBtn.red, onTap: alCancelar),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilaDeuda extends StatelessWidget {
  const _FilaDeuda({required this.deuda, required this.alCobrar});

  final Deuda deuda;
  final VoidCallback alCobrar;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final d = deuda;
    final nombre = d.nombreCliente.isEmpty ? 'Deuda' : d.nombreCliente;
    return Padding(
      key: Key('deuda_${d.id}'),
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
      child: Row(
        children: [
          Avatar(_inicial(nombre), fondo: p.papel, diametro: 42),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: estilo(17, 550, color: p.tinta),
                ),
                if (d.detalle.isNotEmpty)
                  Text(
                    d.detalle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: estilo(14, 400, color: p.mute),
                  ),
                Text('desde el ${d.desde.day}/${d.desde.month}', style: estilo(13, 400, color: p.soft)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(pesos(d.montoCentavos), style: estilo(18, 600, color: p.tinta, num: true)),
          const SizedBox(width: 14),
          Btn(
            'Cobrar',
            tam: TamBtn.sm,
            variante: VarBtn.ton,
            sobreGris: true,
            etiqueta: 'Cobrar ${pesos(d.montoCentavos)} a $nombre',
            onTap: alCobrar,
          ),
        ],
      ),
    );
  }
}

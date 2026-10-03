// Encargues (El dueño, 2026-10-02): lo que un cliente pidió y ya está en el local, apartado hasta que lo retire.
// Apartar saca el stock en el momento; "Entregar" abre una venta con eso cargado; "Cancelar" lo devuelve al stock.
// "Entregar y anotar deuda" (2026-10-03, el fiado se unificó acá): se lo lleva sin pagar y queda una deuda para cobrar
// después, en la sección "Deudas" de esta misma pantalla.
// Las reglas viven en `repositorio_encargues.dart`; esta pantalla solo las muestra y las dispara.

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/repositorio_encargues.dart';
import '../../data/repositorio_pendientes.dart' show cobrarDeuda;
import '../../domain/dinero.dart';
import '../comun/armazon_gestion.dart';
import '../comun/botones.dart';
import '../comun/modal.dart';
import '../comun/tarjetas.dart';
import '../navegacion/busqueda_contextual.dart';
import '../navegacion/navegacion_gestion.dart';
import '../navegacion/refresco_por_celular.dart';
import '../tema/tokens.dart';
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
  String _busqueda = '';

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
    final creado = await mostrarDialogoNuevoEncargue(context, db: widget.db, usuarioId: widget.usuarioId);
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

  Future<void> _cancelar(Encargue e) async {
    final confirmado = await mostrarModal<bool>(
      context,
      builder: (context) => Modal(
        titulo: '¿Cancelar el encargue de ${e.nombreCliente}?',
        contenido: Text('Lo apartado (${e.resumen}) vuelve al stock.'),
        botones: [
          BotonSecundario(texto: 'Volver', onPressed: () => Navigator.of(context).pop(false)),
          BotonPrimario(texto: 'Cancelar encargue', onPressed: () => Navigator.of(context).pop(true)),
        ],
      ),
    );
    if (confirmado != true) return;
    await cancelarEncargue(widget.db, e.id, usuarioId: widget.usuarioId);
    await _cargar();
  }

  Future<void> _entregarADeuda(Encargue e) async {
    final confirmado = await mostrarModal<bool>(
      context,
      builder: (context) => Modal(
        titulo: '¿Entregar a ${e.nombreCliente} y anotar la deuda?',
        contenido: Text(
          'Se lleva ${e.resumen} sin pagar. Queda anotado en Deudas, a los precios de hoy, para cobrarle después. '
          'El stock ya está descontado.',
        ),
        botones: [
          BotonSecundario(texto: 'Volver', onPressed: () => Navigator.of(context).pop(false)),
          BotonPrimario(texto: 'Entregar y anotar', onPressed: () => Navigator.of(context).pop(true)),
        ],
      ),
    );
    if (confirmado != true) return;
    await entregarEncargueADeuda(widget.db, e.id, usuarioId: widget.usuarioId);
    await _cargar();
  }

  Future<void> _cobrarDeuda(Deuda d) async {
    final sesionId = widget.sesionCajaId;
    if (sesionId == null) {
      await mostrarModal<void>(
        context,
        builder: (context) => Modal(
          titulo: 'No hay una caja abierta',
          contenido: const Text('Para cobrar una deuda hay que abrir la caja: el cobro entra como una venta del día.'),
          botones: [BotonPrimario(texto: 'Entendido', onPressed: () => Navigator.of(context).pop())],
        ),
      );
      return;
    }
    // true = efectivo, false = Mercado Pago, null = volvió sin cobrar.
    final efectivo = await mostrarModal<bool>(
      context,
      builder: (context) => Modal(
        titulo: 'Cobrar a ${d.nombreCliente}',
        subtitulo: formatearARS(d.montoCentavos),
        contenido: const Text('¿Cómo paga?'),
        botones: [
          BotonSecundario(texto: 'Volver', onPressed: () => Navigator.of(context).pop()),
          BotonSecundario(texto: 'Mercado Pago', onPressed: () => Navigator.of(context).pop(false)),
          BotonPrimario(texto: 'Efectivo', onPressed: () => Navigator.of(context).pop(true)),
        ],
      ),
    );
    if (efectivo == null) return;
    await cobrarDeuda(widget.db, pendienteId: d.id, sesionCajaId: sesionId, usuarioId: widget.usuarioId, efectivo: efectivo);
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final filtro = _busqueda.toLowerCase();
    final deudasVisibles = filtro.isEmpty
        ? _deudas
        : [
            for (final d in _deudas)
              if (d.nombreCliente.toLowerCase().contains(filtro) || d.detalle.toLowerCase().contains(filtro)) d,
          ];
    final visibles = filtro.isEmpty
        ? _encargues
        : [
            for (final e in _encargues)
              if (e.nombreCliente.toLowerCase().contains(filtro) || e.resumen.toLowerCase().contains(filtro)) e,
          ];
    return PantallaGestion(
      db: widget.db,
      claveActiva: 'encargues',
      usuarioId: widget.usuarioId,
      sesionCajaId: widget.sesionCajaId,
      titulo: 'Encargues',
      subtitulo: 'Lo que ya está en el local y se apartó para un cliente',
      busqueda: BusquedaContextual(pista: 'Buscar un cliente o un producto…', alCambiar: (t) => setState(() => _busqueda = t)),
      accion: BotonPrimario(texto: 'Nuevo encargue', onPressed: _nuevo),
      child: _cargando
          ? const SizedBox.shrink()
          : visibles.isEmpty && deudasVisibles.isEmpty
              ? Center(
                  child: Text(
                    _encargues.isEmpty && _deudas.isEmpty
                        ? 'No hay encargues pendientes.'
                        : 'Ningún encargue ni deuda coincide con la búsqueda.',
                    key: const Key('encargues_vacio'),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: context.colores.textoSecundario),
                  ),
                )
              : ListView(
                  children: [
                    for (final e in visibles) ...[
                      _TarjetaEncargue(
                        encargue: e,
                        alEntregar: () => _entregar(e),
                        alAnotarDeuda: () => _entregarADeuda(e),
                        alCancelar: () => _cancelar(e),
                      ),
                      const SizedBox(height: Espaciado.md),
                    ],
                    if (deudasVisibles.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: Espaciado.md, bottom: Espaciado.md),
                        child: Text('Deudas', style: Theme.of(context).textTheme.titleLarge),
                      ),
                      for (final d in deudasVisibles) ...[
                        _TarjetaDeuda(deuda: d, alCobrar: () => _cobrarDeuda(d)),
                        const SizedBox(height: Espaciado.md),
                      ],
                    ],
                  ],
                ),
    );
  }
}

class _TarjetaEncargue extends StatelessWidget {
  const _TarjetaEncargue({required this.encargue, required this.alEntregar, required this.alAnotarDeuda, required this.alCancelar});

  final Encargue encargue;
  final VoidCallback alEntregar;
  final VoidCallback alAnotarDeuda;
  final VoidCallback alCancelar;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return TarjetaSeccion(
      key: Key('encargue_${encargue.id}'),
      titulo: encargue.nombreCliente,
      insignia: Text('desde el ${encargue.desde.day}/${encargue.desde.month}', style: textTheme.bodySmall),
      accion: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BotonSecundario(texto: 'Cancelar', onPressed: alCancelar),
          const SizedBox(width: Espaciado.sm),
          BotonSecundario(texto: 'Entregar y anotar deuda', onPressed: alAnotarDeuda),
          const SizedBox(width: Espaciado.sm),
          BotonPrimario(texto: 'Entregar', onPressed: alEntregar),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final l in encargue.lineas)
            Padding(padding: const EdgeInsets.only(bottom: Espaciado.xs), child: Text(l.texto, style: textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _TarjetaDeuda extends StatelessWidget {
  const _TarjetaDeuda({required this.deuda, required this.alCobrar});

  final Deuda deuda;
  final VoidCallback alCobrar;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return TarjetaSeccion(
      key: Key('deuda_${deuda.id}'),
      titulo: deuda.nombreCliente.isEmpty ? 'Deuda' : deuda.nombreCliente,
      insignia: Text('desde el ${deuda.desde.day}/${deuda.desde.month}', style: textTheme.bodySmall),
      accion: BotonPrimario(texto: 'Cobrar ${formatearARS(deuda.montoCentavos)}', onPressed: alCobrar),
      child: deuda.detalle.isEmpty ? const SizedBox.shrink() : Text(deuda.detalle, style: textTheme.bodyMedium),
    );
  }
}

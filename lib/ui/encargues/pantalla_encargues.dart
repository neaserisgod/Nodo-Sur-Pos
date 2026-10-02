// Encargues (El dueño, 2026-10-02): lo que un cliente pidió y ya está en el local, apartado hasta que lo retire.
// Apartar saca el stock en el momento; "Entregar" abre una venta con eso cargado; "Cancelar" lo devuelve al stock.
// Las reglas viven en `repositorio_encargues.dart`; esta pantalla solo las muestra y las dispara.

import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/repositorio_encargues.dart';
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
    if (!mounted) return;
    setState(() {
      _encargues = lista;
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

  @override
  Widget build(BuildContext context) {
    final filtro = _busqueda.toLowerCase();
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
          : visibles.isEmpty
              ? Center(
                  child: Text(
                    _encargues.isEmpty ? 'No hay encargues pendientes.' : 'Ningún encargue coincide con la búsqueda.',
                    key: const Key('encargues_vacio'),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: context.colores.textoSecundario),
                  ),
                )
              : ListView.separated(
                  itemCount: visibles.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Espaciado.md),
                  itemBuilder: (context, i) => _TarjetaEncargue(
                    encargue: visibles[i],
                    alEntregar: () => _entregar(visibles[i]),
                    alCancelar: () => _cancelar(visibles[i]),
                  ),
                ),
    );
  }
}

class _TarjetaEncargue extends StatelessWidget {
  const _TarjetaEncargue({required this.encargue, required this.alEntregar, required this.alCancelar});

  final Encargue encargue;
  final VoidCallback alEntregar;
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

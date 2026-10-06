// Respaldo — desde 2026-09-26 es una sección de Configuración, no un
// apartado propio del menú (El dueño: "que apartados podemos resumir, agrupar
// o directamente eliminar"). Se toca una vez cada tanto: no ocupa un lugar
// del menú de todos los días. Este widget es solo el contenido, sin barra
// de navegación — lo monta `pantalla_configuracion.dart`.
//
// Con el kit del mock v4 (`cfgBody('respaldo')`, 2026-10-06): la lista con la carpeta, la última copia y cuántas
// conservar; los botones; "Importar una base"; y las últimas copias, cada una con su "Restaurar".

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/repositorio_respaldo.dart' show ArchivoRespaldo;
import '../kit/kit.dart';
import 'dialogo_confirmar_restaurar.dart';
import 'respaldo_controlador.dart';

class ContenidoRespaldo extends StatefulWidget {
  const ContenidoRespaldo({super.key, required this.db, required this.usuarioId});

  final AppDatabase db;
  final int usuarioId;

  @override
  State<ContenidoRespaldo> createState() => _ContenidoRespaldoState();
}

class _ContenidoRespaldoState extends State<ContenidoRespaldo> {
  late final RespaldoControlador _c;

  @override
  void initState() {
    super.initState();
    _c = RespaldoControlador(widget.db);
    _c.cargarTodo();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _elegirCarpeta() async {
    final ruta = await getDirectoryPath();
    if (ruta != null) await _c.elegirCarpeta(ruta);
  }

  Future<void> _importar() async {
    final elegido = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Base de datos', extensions: ['sqlite', 'db', 'gz']),
      ],
    );
    if (elegido == null) return;
    final lista = await _c.prepararImportacionDeArchivo(elegido.path);
    if (lista == null || !mounted) return;
    final fecha = await elegido.lastModified();
    if (!mounted) return;
    await mostrarDialogoConfirmarRestaurar(
      context,
      db: widget.db,
      archivo: ArchivoRespaldo(ruta: lista.ruta, nombre: elegido.name, fecha: fecha, tamanioBytes: lista.tamanioBytes),
      fechaFormateada: _formatearFecha(fecha),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RespaldoControlador>.value(
      value: _c,
      child: Consumer<RespaldoControlador>(
        builder: (context, c, _) {
          if (c.cargando) return const SizedBox.shrink();
          final p = context.p;
          final ultimo = c.respaldos.isEmpty ? null : c.respaldos.last;
          final horas = ultimo == null ? null : DateTime.now().difference(ultimo.fecha).inHours;
          // "Al día" si hay uno de las últimas 36 h: el respaldo sale al cerrar la caja, así que el de anoche todavía
          // cuenta como al día.
          final estado = switch (horas) {
            null => const Etiqueta('Sin copias', tono: TonoMock.b),
            < 36 => const Etiqueta('Al día', tono: TonoMock.g),
            final h => Etiqueta('Hace ${(h / 24).floor()} días', tono: TonoMock.w),
          };
          final copias = {7, 14, 30, c.cantidadCopias}.toList()..sort();
          final recientes = c.respaldos.reversed.toList(); // más nuevo primero
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Lista(filas: [
                Kv(
                  'Carpeta de copias',
                  '',
                  // Una ruta larga se corta con "…" en vez de empujar la fila.
                  valorWidget: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Text(
                      // Dato incompleto, no un error — mismo criterio que un fijo sin cargar en Equilibrio.
                      c.carpeta ?? 'Sin carpeta configurada',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: estilo(16, 600, color: c.carpeta == null ? p.mute : p.tinta),
                    ),
                  ),
                ),
                Kv(
                  'Última copia',
                  '',
                  valorWidget: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (ultimo != null) ...[
                        Text('${_formatearFecha(ultimo.fecha)} · ${_tamanio(ultimo.tamanioBytes)}', style: estilo(16, 600, color: p.tinta, num: true)),
                        const SizedBox(width: 10),
                      ],
                      estado,
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Copias a conservar', style: estilo(17, 550, color: p.tinta)),
                            Text('Se respalda solo al cerrar la caja de cada día. Las más viejas se borran solas.', style: estilo(14, 400, color: p.mute)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Seg<int>(
                        key: const Key('seg_copias'),
                        opciones: [for (final n in copias) (n, '$n')],
                        valor: c.cantidadCopias,
                        onCambio: c.cambiarCantidadCopias,
                      ),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Btn(
                    c.respaldando ? 'Haciendo la copia…' : 'Hacer copia ahora',
                    key: const Key('boton_respaldar_ahora'),
                    variante: VarBtn.blue,
                    onTap: c.carpeta == null || c.respaldando ? null : c.respaldarAhora,
                  ),
                  Btn('Elegir carpeta', variante: VarBtn.ton, onTap: _elegirCarpeta),
                ],
              ),
              if (c.error != null) ...[const SizedBox(height: 10), Text(c.error!, style: estilo(15, 500, color: p.b))],
              if (c.hayCajaAbierta) ...[
                const SizedBox(height: 14),
                const Nota(tono: TonoMock.w, texto: 'Hay una caja abierta: cerrala para poder restaurar una copia o importar una base.'),
              ],
              const SizedBox(height: 14),
              Tarjeta(
                linea: true,
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Importar una base', style: estilo(17, 600, color: p.tinta)),
                          const SizedBox(height: 2),
                          Text(
                            'Si solo te quedó el archivo de la base (la PC se rompió, o la pasás a otra), elegilo acá: reemplaza TODOS '
                            'los datos actuales y la app se reinicia. Si es de una versión anterior, se actualiza sola al abrirla. '
                            'Sirve el archivo .sqlite o la copia comprimida (.gz) que baja de tu cuenta.',
                            style: estilo(14, 400, color: p.mute, alto: 1.45),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Btn('Importar desde un archivo…', key: const Key('boton_importar_base'), variante: VarBtn.ton, onTap: c.hayCajaAbierta ? null : _importar),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Sec('Últimas copias'),
              const SizedBox(height: 10),
              if (recientes.isEmpty)
                const Nota(texto: 'Todavía no hay copias.')
              else
                Lista(filas: [
                  for (final archivo in recientes)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(child: Text(_formatearFecha(archivo.fecha), style: estilo(17, 500, color: p.tinta, num: true))),
                          Text(_tamanio(archivo.tamanioBytes), style: estilo(15, 400, color: p.mute, num: true)),
                          const SizedBox(width: 14),
                          Btn(
                            'Restaurar',
                            variante: VarBtn.ton,
                            tam: TamBtn.xs,
                            sobreGris: true,
                            onTap: c.hayCajaAbierta
                                ? null
                                : () => mostrarDialogoConfirmarRestaurar(
                                    context,
                                    db: widget.db,
                                    archivo: archivo,
                                    fechaFormateada: _formatearFecha(archivo.fecha),
                                  ),
                          ),
                        ],
                      ),
                    ),
                ]),
            ],
          );
        },
      ),
    );
  }
}

String _tamanio(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';
}

String _formatearFecha(DateTime fecha) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(fecha.day)}/${dos(fecha.month)}/${fecha.year} ${dos(fecha.hour)}:${dos(fecha.minute)}';
}

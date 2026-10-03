// Respaldo — desde 2026-09-26 es una sección de Configuración, no un
// apartado propio del menú (El dueño: "que apartados podemos resumir, agrupar
// o directamente eliminar"). Se toca una vez cada tanto: no ocupa un lugar
// del menú de todos los días. Este widget es solo el contenido, sin barra
// de navegación — lo monta `pantalla_configuracion.dart`.

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/database.dart';
import '../../data/repositorio_respaldo.dart' show ArchivoRespaldo;
import '../comun/botones.dart';
import '../comun/estado_vacio.dart';
import '../comun/tarjetas.dart';
import '../tema/iconos.dart';
import '../tema/tokens.dart';
import 'dialogo_confirmar_restaurar.dart';
import 'respaldo_controlador.dart';
import '../tema/esqueleto.dart';

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

  // "Lenguaje de diseño" (mock `ConfigImpresion` → Respaldo): el estado
  // primero (¿está al día?), el botón de respaldar grande, la carpeta y las
  // copias abajo, y la lista de respaldos al costado con su "Restaurar".
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RespaldoControlador>.value(
      value: _c,
      child: Consumer<RespaldoControlador>(
        builder: (context, c, _) {
          if (c.cargando) return const EsqueletoLista();
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  children: [
                    _Estado(c: c),
                    const SizedBox(height: Espaciado.md),
                    TarjetaSeccion(
                      titulo: 'Dónde se guarda',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  // Dato incompleto, no un error — mismo
                                  // criterio que un fijo sin cargar en
                                  // Equilibrio.
                                  c.carpeta ?? 'Sin carpeta configurada',
                                  style: c.carpeta == null ? TextStyle(color: context.colores.textoSecundario) : null,
                                ),
                              ),
                              BotonSecundario(texto: 'Elegir carpeta', onPressed: _elegirCarpeta),
                            ],
                          ),
                          const SizedBox(height: Espaciado.md),
                          Row(
                            children: [
                              const Expanded(child: Text('Copias a conservar')),
                              SizedBox(
                                width: 80,
                                // `fillColor` explícito: este campo vive
                                // adentro de una tarjeta — sin esto, el
                                // relleno por default del tema
                                // (`fondoBloque`) queda invisible contra
                                // la tarjeta que lo contiene.
                                child: TextFormField(
                                  key: ValueKey(c.cantidadCopias),
                                  initialValue: c.cantidadCopias.toString(),
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  decoration: InputDecoration(fillColor: context.colores.fondo),
                                  onFieldSubmitted: (valor) {
                                    final n = int.tryParse(valor);
                                    if (n != null && n > 0) c.cambiarCantidadCopias(n);
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: Espaciado.sm),
                          Text(
                            'Se respalda solo al cerrar la caja de cada día. Las copias más viejas se borran.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Espaciado.md),
                    TarjetaSeccion(
                      titulo: 'Importar una base',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Si solo te quedó el archivo de la base (la PC se rompió, o la pasás a otra), elegilo acá: reemplaza TODOS los datos '
                            'actuales y la app se reinicia. Si es de una versión anterior, se actualiza sola al abrirla. '
                            'Sirve el archivo .sqlite o la copia comprimida (.gz) que baja de tu cuenta.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: Espaciado.md),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: BotonSecundario(
                              texto: 'Importar desde un archivo…',
                              onPressed: c.hayCajaAbierta ? null : _importar,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Espaciado.md),
              Expanded(
                child: TarjetaSeccion(
                  titulo: 'Últimos respaldos',
                  child: Expanded(
                    child: c.respaldos.isEmpty
                        ? const EstadoVacio(mensaje: 'Todavía no hay respaldos')
                        : ListView.separated(
                            itemCount: c.respaldos.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              // Más nuevo primero en pantalla; la lista del controlador va de viejo a nuevo.
                              final archivo = c.respaldos[c.respaldos.length - 1 - i];
                              final fecha = _formatearFecha(archivo.fecha);
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: Espaciado.sm),
                                child: Row(
                                  children: [
                                    Icon(IconosPlazoleta.backup, color: context.colores.textoSecundario),
                                    const SizedBox(width: Espaciado.md),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(fecha, style: Theme.of(context).textTheme.titleSmall),
                                          Text(_tamanio(archivo.tamanioBytes), style: Theme.of(context).textTheme.bodySmall),
                                        ],
                                      ),
                                    ),
                                    BotonSecundario(
                                      texto: 'Restaurar',
                                      onPressed: c.hayCajaAbierta
                                          ? null
                                          : () => mostrarDialogoConfirmarRestaurar(
                                              context,
                                              db: widget.db,
                                              archivo: archivo,
                                              fechaFormateada: fecha,
                                            ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ),
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

class _Estado extends StatelessWidget {
  const _Estado({required this.c});

  final RespaldoControlador c;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final ultimo = c.respaldos.isEmpty ? null : c.respaldos.last;
    final horas = ultimo == null ? null : DateTime.now().difference(ultimo.fecha).inHours;
    // "Al día" si hay uno de las últimas 36 h: el respaldo sale al cerrar la
    // caja, así que el de anoche todavía cuenta como al día.
    final insignia = switch (horas) {
      null => const Insignia(texto: 'Sin respaldos', tono: Tono.error),
      < 36 => const Insignia(texto: 'Al día', tono: Tono.ganancia),
      final h => Insignia(texto: 'Hace ${(h / 24).floor()} días', tono: Tono.alerta),
    };
    return TarjetaSeccion(
      titulo: 'Respaldo',
      insignia: insignia,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BloqueSuave(
            child: Row(
              children: [
                Icon(IconosPlazoleta.backup, color: context.colores.acento),
                const SizedBox(width: Espaciado.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ultimo == null ? 'Todavía no se hizo ningún respaldo' : 'Último respaldo: ${_formatearFecha(ultimo.fecha)}',
                        style: textTheme.titleSmall,
                      ),
                      if (ultimo != null) Text(_tamanio(ultimo.tamanioBytes), style: textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Espaciado.md),
          BotonPrimario(
            texto: c.respaldando ? 'Respaldando…' : 'Respaldar ahora',
            onPressed: c.carpeta == null || c.respaldando ? null : c.respaldarAhora,
          ),
          if (c.error != null) ...[const SizedBox(height: Espaciado.sm), Text(c.error!, style: TextStyle(color: context.colores.error))],
          if (c.hayCajaAbierta) ...[
            const SizedBox(height: Espaciado.sm),
            Text(
              'Hay una caja abierta: cerrala para poder restaurar un respaldo.',
              style: TextStyle(color: context.colores.textoSecundario),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatearFecha(DateTime fecha) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(fecha.day)}/${dos(fecha.month)}/${fecha.year} ${dos(fecha.hour)}:${dos(fecha.minute)}';
}

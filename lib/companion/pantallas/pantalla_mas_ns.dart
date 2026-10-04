// Más, tal cual el mock (docs/03 B5): la tarjeta del usuario, la apariencia (claro,
// oscuro o automático), NEGOCIO, ESTA APLICACIÓN y "Desconectar de esta PC".
// Lo que la app tiene y el mock no (encargues, pagar a un proveedor, cuenta de
// Nodo Sur, modo de uso) se suma a esas mismas listas con el mismo aspecto.

import 'package:flutter/material.dart';

import '../app_ns.dart';
import '../kit/kit_ns.dart';
import '../modo_uso.dart';
import '../pantalla_carga_historica.dart';
import '../pantalla_configuracion_companion.dart';
import '../pantalla_cuenta_companion.dart';
import '../pantalla_encargues_companion.dart';
import '../pantalla_historial_ventas.dart';
import '../pantalla_pagar_proveedor.dart';
import '../tablero_companion.dart';
import '../base_local.dart';
import '../tema/app_bar_companion.dart';
import 'pantalla_buscador_ns.dart';
import 'pantalla_notificaciones_ns.dart';

class PantallaMasNs extends StatelessWidget {
  const PantallaMasNs({super.key, this.alAbrirEncargues});

  /// Abre "Encargues" con el carrito del menú (para poder entregar uno).
  final VoidCallback? alAbrirEncargues;

  @override
  Widget build(BuildContext context) {
    final app = AppNs.of(context);
    final ns = context.ns;
    return PantallaEntradaNs(
      child: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([app.pendientes, modoTemaNs]),
          builder: (context, _) {
            final pend = app.pendientes.value;
            final nombre = app.nombreUsuario ?? '';
            final indiceTema = switch (modoTemaNs.value) {
              ThemeMode.light => 0,
              ThemeMode.dark => 1,
              ThemeMode.system => 2,
            };
            final soloCelular = app.modoUso == ModoUso.soloCelular || !app.pcEmparejada;
            return ListView(
              padding: const EdgeInsets.fromLTRB(margenNs, 28, margenNs, BarraInferiorNs.espacioReservado - 4),
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Más', style: tituloNs(42, color: ns.ink))),
                    BotonCircularNs(icono: IconoNs.lupa, onTap: () => app.irA((_) => const PantallaBuscadorNs(origen: PestaniaNs.mas)), etiqueta: 'Buscar una función o ajuste', tamanioIcono: 20),
                    const SizedBox(width: 8),
                    BotonCircularNs(icono: IconoNs.campana, onTap: () => app.irA((_) => const PantallaNotificacionesNs()), etiqueta: pend.cantidad == 0 ? 'Notificaciones' : '${pend.cantidad} notificaciones', globo: pend.cantidad),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: ns.s, borderRadius: BorderRadius.circular(999)),
                  child: Row(
                    children: [
                      Container(width: 56, height: 56, decoration: BoxDecoration(color: ns.ibg, shape: BoxShape.circle), alignment: Alignment.center, child: Text(nombre.isEmpty ? '' : nombre[0].toUpperCase(), style: estiloNs(22, peso: FontWeight.w700, color: ns.i))),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: estiloNs(20, peso: FontWeight.w500, color: ns.ink)),
                            Text('Usuario de este turno', style: estiloNs(14, color: ns.mute)),
                          ],
                        ),
                      ),
                      BotonNs(texto: 'Cambiar', onTap: app.cambiarUsuario, alto: 44, tamanio: 14, fondo: ns.paper, color: ns.ink, rellenar: false, paddingH: 18),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const SeccionNs('Apariencia'),
                const SizedBox(height: 12),
                SegmentoNs(
                  opciones: const ['Claro', 'Oscuro', 'Automático'],
                  indice: indiceTema,
                  onCambio: (i) => guardarModoTemaNs(const [ThemeMode.light, ThemeMode.dark, ThemeMode.system][i]),
                ),
                const SizedBox(height: 12),
                const SeccionNs('Negocio'),
                const SizedBox(height: 12),
                ListaAgrupadaNs(
                  filas: [
                    _Fila(icono: IconoNs.ajustes, titulo: 'Configuración', detalle: 'Redondeo, medios de pago, categorías y usuarios', onTap: () => app.irA((_) => const PantallaConfiguracionCompanion())),
                    _Fila(icono: IconoNs.calendario, titulo: 'Cargar días anteriores', detalle: 'Completá ventas de días que no registraste', onTap: () => app.irA((_) => const PantallaCargaHistorica())),
                    _Fila(
                      icono: IconoNs.portapapeles,
                      titulo: 'Historial de ventas',
                      detalle: 'Hoy, ayer, la semana o el mes',
                      onTap: () => app.irA((_) => const Scaffold(appBar: AppBarCompanion(titulo: 'Historial de ventas'), body: SafeArea(child: PantallaHistorialVentas()))),
                    ),
                    _Fila(
                      icono: IconoNs.calendario,
                      titulo: 'Tablero del día',
                      detalle: 'Ventas por hora, más vendidos y stock bajo',
                      onTap: () => app.irA((_) => Scaffold(appBar: const AppBarCompanion(titulo: 'Tablero del día'), body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(margenNs, 0, margenNs, 24), child: TableroCompanion(db: baseLocalCompanion(), alTocarSeparar: () {}))))),
                    ),
                    _Fila(icono: IconoNs.producto, titulo: 'Encargues', detalle: 'Lo apartado para clientes', onTap: alAbrirEncargues ?? () => app.irA((_) => PantallaEncarguesCompanion(servicio: app.servicio!, usuarioId: app.usuarioId ?? 0, sesionCajaId: app.sesion?.id))),
                    _Fila(icono: IconoNs.billetera, titulo: 'Pagar a un proveedor', detalle: 'Copiá el alias y registrá la transferencia', onTap: () => app.irA((_) => const PantallaPagarProveedor())),
                    _Fila(icono: IconoNs.enchufe, titulo: 'Cuenta de Nodo Sur', detalle: 'Sincronización y copias', onTap: () => app.irA((_) => const PantallaCuentaDelCelular())),
                  ],
                ),
                const SizedBox(height: 12),
                const SeccionNs('Esta aplicación'),
                const SizedBox(height: 12),
                ListaAgrupadaNs(
                  filas: [
                    _Fila(
                      icono: IconoNs.enchufe,
                      titulo: 'Conexión con la PC',
                      detalle: soloCelular && !app.pcEmparejada ? 'Funcionando solo en este celular' : (app.sinConexion ? 'Sin conexión · usás los datos del celular' : 'Conectado y sincronizado'),
                      onTap: app.cambiarModo,
                    ),
                    _Fila(
                      icono: IconoNs.descarga,
                      titulo: 'Actualización',
                      detalle: pend.hayActualizacion ? 'Hay una versión nueva' : 'Tenés la última versión',
                      onTap: () => pend.hayActualizacion ? app.abrirActualizacion() : mostrarAvisoNs(context, 'Ya tenés la última versión'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                BotonNs(
                  texto: app.pcEmparejada ? 'Desconectar de esta PC' : 'Emparejar con una PC',
                  onTap: app.cambiarModo,
                  alto: 56,
                  tamanio: 16,
                  fondo: app.pcEmparejada ? ns.bbg : ns.s,
                  color: app.pcEmparejada ? ns.b : ns.ink,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.icono, required this.titulo, required this.detalle, required this.onTap});
  final IconoNs icono;
  final String titulo;
  final String detalle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ns = context.ns;
    return PresionNs(
      onTap: onTap,
      etiqueta: titulo,
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        color: ns.s,
        padding: const EdgeInsets.fromLTRB(14, 12, 20, 12),
        child: Row(
          children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: ns.paper, shape: BoxShape.circle), alignment: Alignment.center, child: IconoNsWidget(icono, tamanio: 20, color: ns.ink)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: estiloNs(17, peso: FontWeight.w500, track: -0.02, color: ns.ink)),
                  const SizedBox(height: 2),
                  Text(detalle, style: estiloNs(14, altura: 1.3, color: ns.mute)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconoNsWidget(IconoNs.chevron, tamanio: 18, color: ns.mute, grosor: 2.2),
          ],
        ),
      ),
    );
  }
}

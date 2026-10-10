// Más, tal cual el mock (docs/03 B5): la tarjeta del usuario, la apariencia (claro,
// oscuro o automático), NEGOCIO, ESTA APLICACIÓN y "Modo: … · Cambiar".

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_ns.dart';
import '../kit/kit_ns.dart';
import '../modo_uso.dart';
import '../pantalla_bot_whatsapp.dart';
import '../pantalla_carga_historica.dart';
import '../pantalla_promos.dart';
import '../pantalla_proveedores.dart';
import '../pantalla_configuracion_companion.dart';
import '../pantalla_cuenta_companion.dart';
import '../pantalla_encargues_companion.dart';
import '../bot_celular.dart' show accesoBotDelCelular, botDelCelular, estadoBotCelular;
import '../pedidos_bot.dart' show RegistroPedidosBotPrefs;
import 'pantalla_buscador_ns.dart';
import 'pantalla_notificaciones_ns.dart';
import 'seccion_bot_en_celular_ns.dart';
import '../../edicion.dart';
import '../../domain/modulos.dart' show Modulo;
import '../../servicios/modulos_activos.dart' show esNegocioDeServicios, moduloActivo;

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
          listenable: Listenable.merge([app.pendientes, modoTemaNs, estadoBotCelular]),
          builder: (context, _) {
            final pend = app.pendientes.value;
            final nombre = app.nombreUsuario ?? '';
            final indiceTema = switch (modoTemaNs.value) {
              ThemeMode.light => 0,
              ThemeMode.dark => 1,
              ThemeMode.system => 2,
            };
            final soloCelular = app.modoUso == ModoUso.soloCelular || !app.pcEmparejada;
            final servicios = esNegocioDeServicios();
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
                // Un negocio de servicios en la app de almacén: se le ofrece pasarse a Nodo Sur Servicios (El dueño, 2026-10-10,
                // `docs/PLAN-APP-SERVICIOS.md`), que trae el bot adentro. Misma cuenta: los datos llegan solos por la sincronización.
                if (!esEdicionServicios && servicios && Platform.isAndroid) ...[
                  Container(
                    key: const Key('mas_pasarse_a_servicios'),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: ns.ibg, borderRadius: BorderRadius.circular(22)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Pasate a Nodo Sur Servicios', style: estiloNs(18, peso: FontWeight.w600, color: ns.ink)),
                        const SizedBox(height: 4),
                        Text(
                          'La app para turnos, más simple, con el bot de WhatsApp adentro (sin Termux). Instalala y entrá con tu misma cuenta: tus turnos, servicios y clientes llegan solos.',
                          style: estiloNs(14, color: ns.ink),
                        ),
                        const SizedBox(height: 10),
                        BotonNs.primario(context, 'Descargarla', () => launchUrl(Uri.parse('https://horsepos.com/descargar/'), mode: LaunchMode.externalApplication), alto: 48, tamanio: 15),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                const SeccionNs('Negocio'),
                const SizedBox(height: 12),
                ListaAgrupadaNs(
                  filas: [
                    _Fila(icono: IconoNs.ajustes, titulo: 'Configuración', detalle: 'Redondeo, medios de pago, categorías y usuarios', onTap: () => app.irA((_) => const PantallaConfiguracionCompanion())),
                    // Nodo Sur Servicios: sin encargues de productos, y proveedores solo si lleva insumos.
                    if (!esEdicionServicios) _Fila(icono: IconoNs.producto, titulo: 'Encargues', detalle: 'Lo apartado para clientes', onTap: alAbrirEncargues ?? () => app.irA((_) => PantallaEncarguesCompanion(servicio: app.servicio!, usuarioId: app.usuarioId ?? 0, sesionCajaId: app.sesion?.id, bot: accesoBotDelCelular, registroBot: RegistroPedidosBotPrefs()))),
                    // Promos y carga histórica son de productos (combos de artículos, planillas con productos): un negocio de
                    // servicios no los usa.
                    if (!servicios) _Fila(icono: IconoNs.porcentaje, titulo: 'Promos', detalle: 'Armá combos y mirá cuáles te sugiere la app', onTap: () => app.irA((_) => const PantallaPromos())),
                    if (!esEdicionServicios || moduloActivo(Modulo.insumos)) _Fila(icono: IconoNs.camion, titulo: 'Proveedores', detalle: servicios ? 'A quién le comprás los insumos, lo que les debés y pagos' : 'Altas, lo que les debés, pagos y facturas', onTap: () => app.irA((_) => const PantallaProveedores())),
                    // El bot en Termux; Nodo Sur Servicios lo trae adentro.
                    if (!esEdicionServicios && estadoBotCelular.value?.tieneBot == true && app.servicio != null)
                      _Fila(
                        icono: IconoNs.celular,
                        titulo: 'Bot de WhatsApp',
                        detalle: 'Si anda, horarios, números e instalarlo',
                        onTap: () => app.irA(
                          (_) => PantallaBotWhatsApp(
                            acceso: accesoBotDelCelular,
                            servicio: app.servicio!,
                            alIrATuNegocio: () => app.irA((_) => const PantallaConfiguracionCompanion()),
                          ),
                        ),
                      ),
                    // Nodo Sur Servicios trae el bot adentro: la misma pantalla, con el bot de este celular en vez de Termux.
                    if (esEdicionServicios && Platform.isAndroid && estadoBotCelular.value?.tieneBot == true && app.servicio != null)
                      _Fila(
                        icono: IconoNs.celular,
                        titulo: 'Bot de WhatsApp',
                        detalle: 'Encenderlo, vincularlo y ver si está atendiendo',
                        onTap: () => app.irA(
                          (_) => PantallaBotWhatsApp(
                            acceso: accesoBotDelCelular,
                            servicio: app.servicio!,
                            alIrATuNegocio: () => app.irA((_) => const PantallaConfiguracionCompanion()),
                            enEsteCelular: (context, numero) => SeccionBotEnCelularNs(bot: botDelCelular, numeroBot: numero),
                          ),
                        ),
                      ),
                    if (!servicios) _Fila(icono: IconoNs.calendario, titulo: 'Carga histórica', detalle: 'Días anteriores: completá ventas que no registraste', onTap: () => app.irA((_) => const PantallaCargaHistorica())),
                  ],
                ),
                const SizedBox(height: 12),
                const SeccionNs('Esta aplicación'),
                const SizedBox(height: 12),
                ListaAgrupadaNs(
                  filas: [
                    _Fila(icono: IconoNs.enchufe, titulo: 'Cuenta', detalle: 'Sincronización: ${soloCelular ? 'solo en este celular' : (app.sinConexion ? 'por internet' : 'con la PC')}', onTap: () => app.irA((_) => const PantallaCuentaDelCelular())),
                    _Fila(
                      icono: IconoNs.descarga,
                      titulo: 'Actualización',
                      detalle: pend.hayActualizacion ? 'Hay una versión nueva · se baja sola' : 'Estás al día',
                      onTap: () => pend.hayActualizacion ? app.abrirActualizacion() : mostrarAvisoNs(context, 'Ya tenés la última versión'),
                    ),
                  ],
                ),
                // Nodo Sur Servicios no tiene PC: es siempre solo celular.
                if (!esEdicionServicios) ...[
                  const SizedBox(height: 8),
                  BotonNs(
                    texto: 'Modo: ${soloCelular ? 'solo celular' : 'PC y celular'} · Cambiar',
                    onTap: app.cambiarModo,
                    alto: 56,
                    tamanio: 16,
                    fondo: ns.bbg,
                    color: ns.b,
                  ),
                ],
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

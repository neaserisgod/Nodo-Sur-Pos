// Pestaña "Gestión" de la navbar — accesos de fondo, no de mostrador: Conteo
// de stock, Carga histórica, Arqueo, cambiar de usuario y desconectar de
// esta PC. "Precios y alta de producto" se mudó de acá a su propia pestaña
// ("Productos", el dueño 2026-09-19: "productos pasa a ser la segunda pantalla
// más importante después de vender" — no tenía sentido que compitiera por
// espacio con conteo/carga histórica si es, en uso real, más importante que
// Historial mismo).
//
// Ocupa el lugar que tenía "Más" en la navbar (`pantalla_mas_companion.dart`,
// eliminada, fusionada acá — El dueño: "gestión poniéndolo donde va más"): con
// "Productos" promovida a pestaña propia, "Gestión" queda con poco contenido
// de por sí, así que absorbe lo que antes era una pestaña aparte con solo
// dos tarjetas y un botón de texto — mismo criterio de fusión que ya se usó
// con Gasto/Ingreso rápido y Cierres/Historial en esta misma sesión.
//
// Rediseñada como grilla de tarjetas de color en vez de una lista de filas
// con flechita (El dueño, 2026-09-18: "pensalo como una app moderna").

import 'package:flutter/material.dart';

import '../ui/tema/tokens.dart';
import 'cliente_companion.dart';
import 'navbar_companion.dart';
import 'pantalla_carga_historica.dart';
import 'pantalla_configuracion_companion.dart';
import 'pantalla_cuenta_companion.dart';
import 'modo_uso.dart';
import 'pantalla_conteo_stock.dart';
import 'tema/colores_companion.dart';
import 'tema/piezas_companion.dart';
import 'tema/tarjeta_accion.dart';
import '../ui/tema/iconos.dart';

class PantallaGestionCompanion extends StatelessWidget {
  const PantallaGestionCompanion({
    super.key,
    required this.navegando,
    required this.irA,
    required this.sesion,
    required this.onAbrirArqueo,
    required this.onCerrarCaja,
    required this.onCambiarUsuario,
    required this.onCambiarModo,
    required this.modoUso,
  });

  final bool navegando;
  final Future<void> Function(WidgetBuilder builder) irA;

  final SesionCompanion? sesion;
  final VoidCallback onAbrirArqueo;

  /// Cerrar caja de verdad (El dueño, 2026-09-19: "que deje cerrar caja desde
  /// el celular") — deshabilitada sin sesión abierta, no hay nada que
  /// cerrar.
  final VoidCallback onCerrarCaja;
  final VoidCallback onCambiarUsuario;
  final VoidCallback onCambiarModo;

  /// El modo en uso, para mostrarlo en el botón de abajo.
  final ModoUso? modoUso;

  @override
  Widget build(BuildContext context) {
    final abierta = sesion?.abierta ?? false;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: Espaciado.lg + NavbarCompanion.espacioReservado),
          children: [
            const EncabezadoCompanion(rotulo: 'Cuenta y caja', titulo: 'Gestión'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Espaciado.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (abierta)
                    BloqueHero(
                      onTap: onCerrarCaja,
                      animar: false,
                      minAlto: 132,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Cerrar caja', style: textTheme.headlineMedium?.copyWith(color: Colors.white)),
                                Text('Contar y cerrar el turno', style: textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.72))),
                              ],
                            ),
                          ),
                          const BotonFlecha(),
                        ],
                      ),
                    ),
                  if (abierta) const SizedBox(height: Espaciado.md),
                  GrillaAcciones(
                    tarjetas: [
                      TarjetaAccion(
                        icono: IconosPlazoleta.inventory2Outlined,
                        color: context.acentos.qr,
                        titulo: 'Conteo de stock',
                        subtitulo: 'Por proveedor',
                        onTap: navegando ? null : () => irA((_) => const PantallaConteoStock()),
                      ),
                      TarjetaAccion(
                        icono: IconosPlazoleta.history,
                        color: context.acentos.debito,
                        titulo: 'Carga histórica',
                        subtitulo: 'Días anteriores',
                        onTap: navegando ? null : () => irA((_) => const PantallaCargaHistorica()),
                      ),
                      TarjetaAccion(
                        icono: IconosPlazoleta.pointOfSaleOutlined,
                        color: context.colores.textoPrimario,
                        titulo: 'Arqueo',
                        subtitulo: abierta ? '¿Cómo vamos?' : 'Caja cerrada',
                        onTap: abierta ? onAbrirArqueo : null,
                      ),
                      if (!abierta)
                        TarjetaAccion(
                          icono: IconosPlazoleta.lockClockOutlined,
                          color: context.acentos.dinero,
                          titulo: 'Cerrar caja',
                          subtitulo: 'Caja cerrada',
                          onTap: null,
                        ),
                      TarjetaAccion(
                        icono: IconosPlazoleta.personOutline,
                        color: context.acentos.mixto,
                        titulo: 'Cambiar usuario',
                        subtitulo: 'Elegir otra persona',
                        onTap: onCambiarUsuario,
                      ),
                      TarjetaAccion(
                        icono: IconosPlazoleta.cloudSync,
                        color: context.acentos.qr,
                        titulo: 'Cuenta',
                        subtitulo: 'Sincronización',
                        onTap: navegando ? null : () => irA((_) => const PantallaCuentaDelCelular()),
                      ),
                      TarjetaAccion(
                        icono: IconosPlazoleta.settingsOutlined,
                        color: context.colores.textoPrimario,
                        titulo: 'Configuración',
                        subtitulo: 'Reglas del negocio',
                        onTap: navegando ? null : () => irA((_) => const PantallaConfiguracionCompanion()),
                      ),
                    ],
                  ),
                  const SizedBox(height: Espaciado.xl),
                  OutlinedButton.icon(
                    onPressed: onCambiarModo,
                    icon: Icon(
                      modoUso == ModoUso.soloCelular ? IconosPlazoleta.smartphone : IconosPlazoleta.computer,
                      size: 18,
                    ),
                    label: Text(modoUso == ModoUso.soloCelular ? 'Modo: solo celular · Cambiar' : 'Modo: PC y celular · Cambiar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

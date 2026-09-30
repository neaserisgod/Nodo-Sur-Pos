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
import 'pantalla_conteo_stock.dart';
import 'tema/colores_companion.dart';
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
    required this.onDesconectar,
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
  final VoidCallback onDesconectar;

  @override
  Widget build(BuildContext context) {
    final abierta = sesion?.abierta ?? false;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Espaciado.lg,
            Espaciado.lg,
            Espaciado.lg,
            Espaciado.lg + NavbarCompanion.espacioReservado,
          ),
          children: [
            Text('Gestión', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: Espaciado.xl),
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
                  onTap: navegando
                      ? null
                      : () => irA((_) => const PantallaCargaHistorica()),
                ),
                TarjetaAccion(
                  icono: IconosPlazoleta.pointOfSaleOutlined,
                  color: context.colores.acento,
                  titulo: 'Arqueo',
                  subtitulo: abierta ? '¿Cómo vamos?' : 'Caja cerrada',
                  onTap: abierta ? onAbrirArqueo : null,
                ),
                TarjetaAccion(
                  icono: IconosPlazoleta.lockClockOutlined,
                  color: context.acentos.dinero,
                  titulo: 'Cerrar caja',
                  subtitulo: abierta ? 'Contar y cerrar' : 'Caja cerrada',
                  onTap: abierta ? onCerrarCaja : null,
                ),
                TarjetaAccion(
                  icono: IconosPlazoleta.personOutline,
                  color: context.acentos.mixto,
                  titulo: 'Cambiar usuario',
                  subtitulo: 'Elegir otra persona',
                  onTap: onCambiarUsuario,
                ),
                TarjetaAccion(
                  icono: IconosPlazoleta.settingsOutlined,
                  color: context.colores.acento,
                  titulo: 'Configuración',
                  subtitulo: 'Reglas del negocio',
                  onTap: navegando
                      ? null
                      : () => irA((_) => const PantallaConfiguracionCompanion()),
                ),
              ],
            ),
            const SizedBox(height: Espaciado.xl),
            Center(
              child: TextButton.icon(
                onPressed: onDesconectar,
                icon: Icon(IconosPlazoleta.linkOff, size: 18, color: context.colores.error),
                label: Text(
                  'Desconectar de esta PC',
                  style: TextStyle(color: context.colores.error),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

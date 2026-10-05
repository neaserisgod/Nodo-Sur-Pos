// Mapa de equivalencias — estética "Google" (El dueño, 2026-09-25: "una
// estética al estilo de Google... ninguna de las otras me cerró"):
// `Icons.x_rounded`, la familia de íconos redondeados que Flutter YA trae
// empaquetada (Material Icons, variante "Rounded" — es literalmente la
// familia que usan los productos de Google) — sin fuente custom, sin
// paquete externo. Reemplaza el intento anterior con `phosphor_flutter`
// (abandonado: la versión publicada no compila con este SDK — `IconData`
// pasó a ser `final class` — y de paso tampoco era la línea visual que
// El dueño terminó pidiendo).
//
// Un solo lugar compartido por escritorio y companion (mismo patrón que
// `tokens.dart`), nombrado por el identificador Material original en
// camelCase — si un ícono no convence en la revisión visual, se corrige
// acá, no en cada uno de los ~135 call sites que lo usaban.

import 'package:flutter/material.dart';

import '../../companion/kit/iconos_ns.dart';

abstract final class IconosPlazoleta {
  static const deleteOutline = Icons.delete_outline_rounded;
  static const delete = Icons.delete_rounded;
  static const add = Icons.add_rounded;
  static const addCircleOutline = Icons.add_circle_outline_rounded;
  static const search = Icons.search_rounded;
  static const searchOff = Icons.search_off_rounded;
  static const pointOfSaleOutlined = Icons.point_of_sale_rounded;
  static const storefrontOutlined = Icons.storefront_rounded;
  static const storefrontRounded = Icons.storefront_rounded;
  static const chevronRight = Icons.chevron_right_rounded;
  static const chevronLeft = Icons.chevron_left_rounded;
  static const arrowForwardIosRounded = Icons.arrow_forward_ios_rounded;
  static const arrowBackRounded = Icons.arrow_back_rounded;
  static const arrowDropDown = Icons.arrow_drop_down_rounded;
  static const expandMore = Icons.expand_more_rounded;
  static const menuOpen = Icons.menu_open_rounded;
  static const menu = Icons.menu_rounded;
  static const paymentsOutlined = Icons.payments_rounded;
  static const inventory2Outlined = Icons.inventory_2_rounded;
  static const check = Icons.check_rounded;
  static const checkCircle = Icons.check_circle_rounded;
  static const checkCircleOutline = Icons.check_circle_outline_rounded;
  static const settingsOutlined = Icons.settings_rounded;
  static const refresh = Icons.refresh_rounded;
  static const receiptLongOutlined = Icons.receipt_long_rounded;
  static const qrCodeScanner = Icons.qr_code_scanner_rounded;
  static const qrCode2Outlined = Icons.qr_code_2_rounded;
  static const qrCode = Icons.qr_code_rounded;
  static const inboxOutlined = Icons.inbox_rounded;
  static const history = Icons.history_rounded;
  static const lockClockOutlined = Icons.lock_clock_rounded;
  static const creditCardOutlined = Icons.credit_card_rounded;
  static const creditCard = Icons.credit_card_rounded;
  static const cloudOff = Icons.cloud_off_rounded;
  static const cloudSync = Icons.cloud_sync_rounded;
  static const computer = Icons.computer_rounded;
  static const smartphone = Icons.smartphone_rounded;
  static const backup = Icons.backup_rounded;
  static const descripcionArchivo = Icons.description_outlined;
  static const shoppingCartOutlined = Icons.shopping_cart_rounded;
  static const shoppingCartCheckout = Icons.shopping_cart_checkout_rounded;
  static const sellOutlined = Icons.sell_outlined;
  static const sellActivo = Icons.sell_rounded;
  static const removeCircleOutline = Icons.remove_circle_outline_rounded;
  static const radioButtonUnchecked = Icons.radio_button_unchecked_rounded;
  static const circleOutlined = Icons.circle_outlined;
  static const printOutlined = Icons.print_rounded;
  static const personOutline = Icons.person_rounded;
  static const lockOutline = Icons.lock_rounded;
  static const lockOpenOutlined = Icons.lock_open_rounded;
  static const localShippingOutlined = Icons.local_shipping_rounded;
  static const errorOutline = Icons.error_outline_rounded;
  static const productionQuantityLimits = Icons.production_quantity_limits_rounded;
  static const editOutlined = Icons.edit_rounded;
  static const edit = Icons.edit_rounded;
  static const editNote = Icons.edit_note_rounded;
  static const close = Icons.close_rounded;
  static const backspace = Icons.backspace_outlined;
  static const clear = Icons.clear_rounded;
  static const callSplit = Icons.call_split_rounded;
  static const callSplitOutlined = Icons.call_split_rounded;
  static const trendingUp = Icons.trending_up_rounded;
  static const timerOutlined = Icons.timer_rounded;
  static const systemUpdateAlt = Icons.system_update_alt_rounded;
  static const swapHoriz = Icons.swap_horiz_rounded;
  static const compareArrowsOutlined = Icons.compare_arrows_rounded;
  static const spaceDashboardOutlined = Icons.space_dashboard_rounded;
  static const saveOutlined = Icons.save_rounded;
  static const remove = Icons.remove_rounded;
  static const priceCheckOutlined = Icons.price_check_rounded;
  static const notificationsOutlined = Icons.notifications_rounded;
  static const listAltOutlined = Icons.list_alt_rounded;
  static const linkOff = Icons.link_off_rounded;
  static const insightsOutlined = Icons.insights_rounded;
  static const helpOutline = Icons.help_outline_rounded;
  static const gMobiledataRounded = Icons.g_mobiledata_rounded;
  static const factCheckOutlined = Icons.fact_check_rounded;
  static const eventOutlined = Icons.event_rounded;
  static const calendarTodayOutlined = Icons.calendar_today_rounded;
  static const cloudUploadOutlined = Icons.cloud_upload_rounded;
  static const assessmentOutlined = Icons.assessment_rounded;
  static const arrowUpward = Icons.arrow_upward_rounded;
  static const arrowDownward = Icons.arrow_downward_rounded;
  static const arrowForwardRounded = Icons.arrow_forward_rounded;
  static const accountBalanceWalletOutlined = Icons.account_balance_wallet_rounded;
}

/// Ícono de la PC: dibuja el trazo del mock (los mismos del celular, `IconoNs`) cuando hay uno equivalente y, si no, el
/// Material de siempre. Se usa en lugar de `Icon(IconosPlazoleta.x)`: así toda la app se ve con un solo juego de íconos
/// sin tocar cada pantalla (2026-10-05, mock Nodo Sur).
class IconoPlz extends StatelessWidget {
  const IconoPlz(this.icono, {super.key, this.size, this.color, this.semanticLabel});

  final IconData icono;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  /// Equivalencias Material → trazo. No es `const` porque `IconData` redefine `==`.
  static final Map<IconData, IconoNs> _trazos = {
    IconosPlazoleta.add: IconoNs.masMas,
    IconosPlazoleta.addCircleOutline: IconoNs.masMas,
    IconosPlazoleta.remove: IconoNs.menos,
    IconosPlazoleta.removeCircleOutline: IconoNs.menos,
    IconosPlazoleta.search: IconoNs.lupa,
    IconosPlazoleta.close: IconoNs.cerrar,
    IconosPlazoleta.clear: IconoNs.cerrar,
    IconosPlazoleta.delete: IconoNs.papelera,
    IconosPlazoleta.deleteOutline: IconoNs.papelera,
    IconosPlazoleta.check: IconoNs.tilde,
    IconosPlazoleta.checkCircle: IconoNs.tilde,
    IconosPlazoleta.checkCircleOutline: IconoNs.tilde,
    IconosPlazoleta.chevronRight: IconoNs.chevron,
    IconosPlazoleta.arrowForwardIosRounded: IconoNs.chevron,
    IconosPlazoleta.chevronLeft: IconoNs.volver,
    IconosPlazoleta.arrowBackRounded: IconoNs.volver,
    IconosPlazoleta.settingsOutlined: IconoNs.ajustes,
    IconosPlazoleta.notificationsOutlined: IconoNs.campana,
    IconosPlazoleta.paymentsOutlined: IconoNs.billetes,
    IconosPlazoleta.creditCard: IconoNs.tarjeta,
    IconosPlazoleta.qrCode: IconoNs.escanear,
    IconosPlazoleta.qrCode2Outlined: IconoNs.escanear,
    IconosPlazoleta.qrCodeScanner: IconoNs.escanear,
    IconosPlazoleta.callSplit: IconoNs.intercambio,
    IconosPlazoleta.swapHoriz: IconoNs.intercambio,
    IconosPlazoleta.compareArrowsOutlined: IconoNs.intercambio,
    IconosPlazoleta.shoppingCartOutlined: IconoNs.carrito,
    IconosPlazoleta.shoppingCartCheckout: IconoNs.carrito,
    IconosPlazoleta.pointOfSaleOutlined: IconoNs.carrito,
    IconosPlazoleta.inventory2Outlined: IconoNs.producto,
    IconosPlazoleta.refresh: IconoNs.reintentar,
    IconosPlazoleta.printOutlined: IconoNs.imprimir,
    IconosPlazoleta.edit: IconoNs.editar,
    IconosPlazoleta.errorOutline: IconoNs.alertaCirculo,
    IconosPlazoleta.lockOutline: IconoNs.candado,
    IconosPlazoleta.computer: IconoNs.computadora,
    IconosPlazoleta.smartphone: IconoNs.celular,
    IconosPlazoleta.cloudOff: IconoNs.sinNube,
    IconosPlazoleta.history: IconoNs.reloj,
    IconosPlazoleta.calendarTodayOutlined: IconoNs.calendario,
    IconosPlazoleta.eventOutlined: IconoNs.calendario,
    IconosPlazoleta.accountBalanceWalletOutlined: IconoNs.billetera,
    IconosPlazoleta.localShippingOutlined: IconoNs.camion,
    IconosPlazoleta.receiptLongOutlined: IconoNs.portapapeles,
    IconosPlazoleta.listAltOutlined: IconoNs.portapapeles,
    IconosPlazoleta.saveOutlined: IconoNs.guardar,
    IconosPlazoleta.sellOutlined: IconoNs.porcentaje,
    IconosPlazoleta.sellActivo: IconoNs.porcentaje,
    IconosPlazoleta.storefrontOutlined: IconoNs.tienda,
  };

  /// Hay trazo equivalente para este ícono (los tests lo usan para buscar el widget).
  static bool tieneTrazo(IconData icono) => _trazos.containsKey(icono);

  @override
  Widget build(BuildContext context) {
    final tamanio = size ?? IconTheme.of(context).size ?? 24;
    final trazo = _trazos[icono];
    if (trazo == null) return Icon(icono, size: tamanio, color: color, semanticLabel: semanticLabel);
    final c = color ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    // El trazo de 2 sobre una grilla de 24 se ve más grueso que un Material de 14-16 px: en tamaños chicos se afina.
    // Igual que `Icon`: la caja es de `tamanio` pero se centra si el padre la fuerza a otro tamaño (botones de 48 px).
    final w = SizedBox(
      width: tamanio,
      height: tamanio,
      child: Center(child: IconoNsWidget(trazo, tamanio: tamanio, color: c, grosor: tamanio <= 18 ? 2.4 : 2)),
    );
    return semanticLabel == null ? w : Semantics(label: semanticLabel, child: w);
  }
}

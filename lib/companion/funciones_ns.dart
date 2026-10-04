// Índice del buscador de funciones y su algoritmo, idénticos al mock
// (docs/06). Es lógica pura: no sabe de pantallas. Cada función lleva una
// [AccionFuncion] que el menú principal traduce a una navegación directa.

import 'kit/iconos_ns.dart';

/// A dónde lleva cada función del índice (docs/06 §3, columna "Acción").
enum AccionFuncion {
  irAVender,
  consultarPrecio,
  productosCatalogo,
  productoNuevo,
  productosEnLote,
  controlarStock,
  productosSinStock,
  cerrarCaja,
  abrirCaja,
  contarCaja,
  gastoIngreso,
  cajaSeparar,
  cajaVentas,
  cierresAnteriores,
  configuracion,
  diasAnteriores,
  cambiarUsuario,
  irAMas,
  actualizar,
  desconectar,
}

class FuncionNs {
  const FuncionNs({required this.seccion, required this.titulo, required this.ruta, required this.claves, required this.icono, required this.accion});

  final int seccion;
  final String titulo;
  final String ruta;
  final String claves;
  final IconoNs icono;
  final AccionFuncion accion;
}

const List<String> seccionesFunciones = ['Vender', 'Productos y stock', 'Caja', 'Configuración y cuenta'];

const List<FuncionNs> indiceFunciones = [
  FuncionNs(seccion: 0, titulo: 'Vender', ruta: 'Vender', claves: 'cobrar venta carrito cliente registrar', icono: IconoNs.carrito, accion: AccionFuncion.irAVender),
  FuncionNs(seccion: 0, titulo: 'Cobrar con efectivo, QR o débito', ruta: 'Vender › Cobrar', claves: 'pago medio mercado pago tarjeta mixto vuelto', icono: IconoNs.billetes, accion: AccionFuncion.irAVender),
  FuncionNs(seccion: 0, titulo: 'Aplicar un descuento', ruta: 'Vender › Carrito', claves: '10 rebaja promo', icono: IconoNs.carrito, accion: AccionFuncion.irAVender),
  FuncionNs(seccion: 0, titulo: 'Imprimir el ticket', ruta: 'Vender › Venta cobrada', claves: 'comprobante impresora recibo', icono: IconoNs.portapapeles, accion: AccionFuncion.irAVender),
  FuncionNs(seccion: 0, titulo: 'Consultar un precio', ruta: 'Inicio › Atajos', claves: 'cuanto cuesta escanear codigo barras', icono: IconoNs.escanear, accion: AccionFuncion.consultarPrecio),
  FuncionNs(seccion: 1, titulo: 'Catálogo de productos', ruta: 'Productos › Catálogo', claves: 'lista buscar proveedor', icono: IconoNs.producto, accion: AccionFuncion.productosCatalogo),
  FuncionNs(seccion: 1, titulo: 'Agregar un producto nuevo', ruta: 'Productos › + Nuevo', claves: 'alta agregar crear cargar', icono: IconoNs.producto, accion: AccionFuncion.productoNuevo),
  FuncionNs(seccion: 1, titulo: 'Cambiar el precio de un producto', ruta: 'Productos › Catálogo › tocar el producto', claves: 'editar modificar aumento costo', icono: IconoNs.producto, accion: AccionFuncion.productosCatalogo),
  FuncionNs(seccion: 1, titulo: 'Subir precios o cargar un pedido de varios productos', ruta: 'Productos › Elegir varios', claves: 'lote masivo aumento porcentaje recibi pedido asignar proveedor', icono: IconoNs.producto, accion: AccionFuncion.productosEnLote),
  FuncionNs(seccion: 1, titulo: 'Controlar el stock', ruta: 'Productos › Controlar stock', claves: 'inventario gondola conteo', icono: IconoNs.portapapeles, accion: AccionFuncion.controlarStock),
  FuncionNs(seccion: 1, titulo: 'Ver productos sin stock', ruta: 'Productos › Controlar stock › Sin stock', claves: 'faltantes reponer agotado', icono: IconoNs.portapapeles, accion: AccionFuncion.productosSinStock),
  FuncionNs(seccion: 2, titulo: 'Cerrar la caja', ruta: 'Caja › Cerrar caja', claves: 'cierre turno contar', icono: IconoNs.billetera, accion: AccionFuncion.cerrarCaja),
  FuncionNs(seccion: 2, titulo: 'Abrir la caja', ruta: 'Caja › Abrir caja', claves: 'fondo inicial arrancar', icono: IconoNs.billetera, accion: AccionFuncion.abrirCaja),
  FuncionNs(seccion: 2, titulo: 'Contar la plata de la caja (sin cerrar)', ruta: 'Caja › Resumen › Contar la caja', claves: 'contar plata cajon diferencia', icono: IconoNs.billetera, accion: AccionFuncion.contarCaja),
  FuncionNs(seccion: 2, titulo: 'Anotar un gasto o un ingreso', ruta: 'Caja › Gasto o ingreso', claves: 'sacar plata retiro compra motivo', icono: IconoNs.intercambio, accion: AccionFuncion.gastoIngreso),
  FuncionNs(seccion: 2, titulo: 'Ver qué separar para cada proveedor', ruta: 'Caja › Separar', claves: 'pagar proveedores apartar', icono: IconoNs.billetera, accion: AccionFuncion.cajaSeparar),
  FuncionNs(seccion: 2, titulo: 'Ver las ventas de hoy', ruta: 'Caja › Ventas', claves: 'historial lista ticket', icono: IconoNs.billetera, accion: AccionFuncion.cajaVentas),
  FuncionNs(seccion: 2, titulo: 'Eliminar una venta', ruta: 'Caja › Ventas › tocar la venta', claves: 'borrar anular error', icono: IconoNs.billetera, accion: AccionFuncion.cajaVentas),
  FuncionNs(seccion: 2, titulo: 'Ver cierres anteriores', ruta: 'Caja › Cierres anteriores', claves: 'ayer dias pasados diferencia', icono: IconoNs.calendario, accion: AccionFuncion.cierresAnteriores),
  FuncionNs(seccion: 3, titulo: 'Redondeo del efectivo', ruta: 'Más › Configuración › Cobro', claves: 'centavos 50 100 vuelto', icono: IconoNs.ajustes, accion: AccionFuncion.configuracion),
  FuncionNs(seccion: 3, titulo: 'Recargo de cigarrillos', ruta: 'Más › Configuración', claves: 'atado suelto precio', icono: IconoNs.ajustes, accion: AccionFuncion.configuracion),
  FuncionNs(seccion: 3, titulo: 'Producto para dar de vuelto', ruta: 'Más › Configuración', claves: 'caramelos cambio chico', icono: IconoNs.ajustes, accion: AccionFuncion.configuracion),
  FuncionNs(seccion: 3, titulo: 'Activar o desactivar formas de cobro', ruta: 'Más › Configuración › Formas de cobro que aceptás', claves: 'efectivo qr debito mixto', icono: IconoNs.ajustes, accion: AccionFuncion.configuracion),
  FuncionNs(seccion: 3, titulo: 'Ganancia de referencia por categoría', ruta: 'Más › Configuración', claves: 'margen porcentaje', icono: IconoNs.ajustes, accion: AccionFuncion.configuracion),
  FuncionNs(seccion: 3, titulo: 'Agregar o desactivar usuarios', ruta: 'Más › Configuración › Quiénes usan la app', claves: 'empleado persona nombre', icono: IconoNs.ajustes, accion: AccionFuncion.configuracion),
  FuncionNs(seccion: 3, titulo: 'Cargar días anteriores', ruta: 'Más › Cargar días anteriores', claves: 'historico ventas pasadas completar', icono: IconoNs.calendario, accion: AccionFuncion.diasAnteriores),
  FuncionNs(seccion: 3, titulo: 'Cambiar de usuario', ruta: 'Más › Cambiar (usuario)', claves: 'turno quien sos salir', icono: IconoNs.ajustes, accion: AccionFuncion.cambiarUsuario),
  FuncionNs(seccion: 3, titulo: 'Estado de la conexión con la PC', ruta: 'Más › Conexión con la PC', claves: 'wifi sin internet sincronizar offline', icono: IconoNs.enchufe, accion: AccionFuncion.irAMas),
  FuncionNs(seccion: 3, titulo: 'Actualizar la aplicación', ruta: 'Más › Actualización', claves: 'version nueva instalar', icono: IconoNs.descarga, accion: AccionFuncion.actualizar),
  FuncionNs(seccion: 3, titulo: 'Desconectar de esta PC', ruta: 'Más › Desconectar de esta PC', claves: 'emparejar qr vincular', icono: IconoNs.enchufe, accion: AccionFuncion.desconectar),
];

/// Sugerencias del estado inicial y de "sin resultados".
const List<String> sugerenciasFunciones = ['Cerrar caja', 'Controlar stock', 'Subir precios', 'Imprimir ticket'];

/// Minúsculas, sin tildes ni diacríticos, sin espacios de más.
String normalizarNs(String texto) {
  const de = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const a = 'aaaaaeeeeiiiiooooouuuunc';
  final b = StringBuffer();
  for (final r in texto.toLowerCase().trim().runes) {
    final c = String.fromCharCode(r);
    final i = de.indexOf(c);
    b.write(i >= 0 ? a[i] : c);
  }
  return b.toString();
}

/// Plurales: "precios" → "precio" (solo si el token tiene más de 3 letras).
String _raiz(String t) => t.length > 3 && t.endsWith('s') ? t.substring(0, t.length - 1) : t;

/// Una función encontrada, con el título de su sección si es la primera del grupo.
class ResultadoFuncion {
  const ResultadoFuncion(this.funcion, {this.encabezado});
  final FuncionNs funcion;
  final String? encabezado;
}

/// Todas las funciones agrupadas por sección (con encabezado en la primera de cada grupo).
List<ResultadoFuncion> todasLasFunciones() {
  final salida = <ResultadoFuncion>[];
  int? anterior;
  for (final f in indiceFunciones) {
    salida.add(ResultadoFuncion(f, encabezado: f.seccion != anterior ? seccionesFunciones[f.seccion] : null));
    anterior = f.seccion;
  }
  return salida;
}

/// Busca funciones: todos los términos tienen que coincidir; ordena por
/// puntaje descendente (a igual puntaje, el orden del índice).
List<FuncionNs> buscarFunciones(String consulta) {
  final tokens = normalizarNs(consulta).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).map(_raiz).toList();
  if (tokens.isEmpty) return const [];
  final puntuadas = <(FuncionNs, int, int)>[];
  for (var i = 0; i < indiceFunciones.length; i++) {
    final f = indiceFunciones[i];
    final lab = normalizarNs(f.titulo);
    final resto = normalizarNs('${f.ruta} ${f.claves} ${seccionesFunciones[f.seccion]}');
    var puntos = 0;
    var coincide = true;
    for (final t in tokens) {
      if (lab.contains(t)) {
        puntos += lab.startsWith(t) ? 4 : 3;
      } else if (resto.contains(t)) {
        puntos += 1;
      } else {
        coincide = false;
        break;
      }
    }
    if (coincide) puntuadas.add((f, puntos, i));
  }
  puntuadas.sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : a.$3.compareTo(b.$3));
  return [for (final p in puntuadas) p.$1];
}

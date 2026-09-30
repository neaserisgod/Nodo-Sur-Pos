// Estado de "Conteo de stock" (Regla 8): recorrer la góndola por proveedor
// y corregir el stock contado, dejando rastro en `movimientos_de_stock`
// igual que el ajuste desde el detalle de producto.
//
// "Lenguaje de diseño" (El dueño, 2026-09-28, mock `ConteoStock`): antes cada
// fila se guardaba sola al salir del campo; ahora se cuenta todo en memoria
// ("Contá lo que hay... Nada cambia hasta que apliques los ajustes") y se
// aplica junto. Así un conteo a medias no deja el stock medio corregido, y
// se ve el resumen (cuántos faltan, cuánto cuesta lo que falta) antes de
// tocar nada.

import 'package:flutter/widgets.dart';

import '../../data/database.dart';
import '../../data/normalizacion_texto.dart';
import '../../data/repositorio_productos.dart';
import '../../domain/pesables.dart';

enum FiltroConteo { todos, sinContar, conDiferencia }

class StockProveedorControlador extends ChangeNotifier {
  StockProveedorControlador(this.db, {required this.usuarioId});

  final AppDatabase db;
  final int usuarioId;

  List<Producto> productos = [];
  List<Categoria> categorias = [];
  List<Proveedor> proveedores = [];

  int? categoriaIdFiltro;
  int? proveedorIdFiltro;
  FiltroConteo filtro = FiltroConteo.todos;
  String busqueda = '';

  /// Lo contado hasta ahora, por producto (unidades, o gramos en pesables).
  /// Sobrevive a cambiar de filtro: se puede contar un proveedor, mirar
  /// otro y volver.
  final Map<int, int> contados = {};

  /// Motivo por default: el uso principal de esta pantalla es el conteo
  /// físico recorriendo la góndola (CLAUDE.md, fase de Regla 8), no una
  /// corrección puntual.
  String motivo = motivosAjusteDeStock.first;

  bool cargando = true;
  bool aplicando = false;

  Future<void> cargarTodo() async {
    categorias = await listarCategorias(db);
    proveedores = await listarProveedores(db);
    await _recargarLista();
    cargando = false;
    notifyListeners();
  }

  Future<void> _recargarLista() async {
    final lista = await listarProductos(
      db,
      categoriaId: categoriaIdFiltro,
      proveedorId: proveedorIdFiltro,
    );
    productos = ordenarAgotadosPrimero(lista.where((p) => !p.esVarios).toList());
  }

  Future<void> filtrarPorCategoria(int? id) async {
    categoriaIdFiltro = id;
    await _recargarLista();
    notifyListeners();
  }

  Future<void> filtrarPorProveedor(int? id) async {
    proveedorIdFiltro = id;
    await _recargarLista();
    notifyListeners();
  }

  void elegirFiltro(FiltroConteo f) {
    filtro = f;
    notifyListeners();
  }

  void buscar(String texto) {
    busqueda = texto;
    notifyListeners();
  }

  void elegirMotivo(String valor) {
    motivo = valor;
    notifyListeners();
  }

  String nombreProveedor(Producto p) =>
      proveedores.where((prov) => prov.id == p.proveedorId).map((prov) => prov.nombre).firstOrNull ?? 'Sin proveedor';

  // ─── Conteo ───────────────────────────────────────────────────────────

  /// Lo que dice el sistema, en la misma unidad en que se cuenta.
  int sistema(Producto p) => p.esPesable ? (p.stockGramos ?? 0) : p.stock;

  int? contado(Producto p) => contados[p.id];

  int? diferencia(Producto p) {
    final c = contados[p.id];
    return c == null ? null : c - sistema(p);
  }

  /// Un toque de "−"/"+": en unidades, de a una; en pesables, de a 100 g.
  /// Sin contar todavía, arranca desde lo que dice el sistema.
  int paso(Producto p) => p.esPesable ? 100 : 1;

  void sumar(Producto p, int veces) {
    final nuevo = (contados[p.id] ?? sistema(p)) + veces * paso(p);
    contados[p.id] = nuevo < 0 ? 0 : nuevo;
    notifyListeners();
  }

  /// null lo vuelve a "sin contar".
  void contar(Producto p, int? valor) {
    if (valor == null) {
      contados.remove(p.id);
    } else {
      contados[p.id] = valor < 0 ? 0 : valor;
    }
    notifyListeners();
  }

  List<Producto> get visibles => [
        for (final p in productos)
          if (_pasaFiltro(p) && coincideTexto(p)) p,
      ];

  bool _pasaFiltro(Producto p) => switch (filtro) {
        FiltroConteo.todos => true,
        FiltroConteo.sinContar => !contados.containsKey(p.id),
        FiltroConteo.conDiferencia => (diferencia(p) ?? 0) != 0,
      };

  bool coincideTexto(Producto p) {
    final q = normalizarTexto(busqueda.trim());
    if (q.isEmpty) return true;
    return normalizarTexto(p.nombre).contains(q) || p.codigoBarras == busqueda.trim();
  }

  // ─── Resumen (tarjetas de arriba) ─────────────────────────────────────

  int get cantidadContados => productos.where((p) => contados.containsKey(p.id)).length;
  int get cantidadSinContar => productos.length - cantidadContados;
  List<Producto> get conDiferencia => [
        for (final p in productos)
          if ((diferencia(p) ?? 0) != 0) p,
      ];

  /// Solo unidades: sumar gramos con unidades no dice nada.
  int get unidadesFaltantes => conDiferencia.where((p) => !p.esPesable && diferencia(p)! < 0).fold(0, (a, p) => a - diferencia(p)!);
  int get unidadesSobrantes => conDiferencia.where((p) => !p.esPesable && diferencia(p)! > 0).fold(0, (a, p) => a + diferencia(p)!);

  /// Lo que falta, a precio de costo (sin costo cargado, no suma).
  int get costoFaltanteCentavos {
    var total = 0;
    for (final p in conDiferencia) {
      final d = diferencia(p)!;
      if (d >= 0) continue;
      if (p.esPesable) {
        // Convención 4: todo subtotal de pesable pasa por su helper.
        if (p.costoPorKiloCentavos != null) total += subtotalPesable(montoPorKiloCentavos: p.costoPorKiloCentavos, gramos: -d);
      } else {
        total += (p.costoCentavos ?? 0) * -d;
      }
    }
    return total;
  }

  /// Aplica todos los ajustes con diferencia, cada uno con su movimiento de
  /// stock. Devuelve cuántos se aplicaron.
  Future<int> aplicarAjustes() async {
    final aAplicar = conDiferencia;
    if (aAplicar.isEmpty) return 0;
    aplicando = true;
    notifyListeners();
    try {
      for (final p in aAplicar) {
        final valor = contados[p.id]!;
        await ajustarStockRapido(
          db,
          productoId: p.id,
          usuarioId: usuarioId,
          stock: p.esPesable ? p.stock : valor,
          stockGramos: p.esPesable ? valor : null,
          motivo: motivo,
        );
      }
      contados.clear();
      await _recargarLista();
    } finally {
      aplicando = false;
      notifyListeners();
    }
    return aAplicar.length;
  }

  /// Ajuste directo de un producto, sin pasar por el conteo.
  Future<void> ajustarStock(Producto producto, {required int stock, int? stockGramos}) async {
    await ajustarStockRapido(
      db,
      productoId: producto.id,
      usuarioId: usuarioId,
      stock: stock,
      stockGramos: stockGramos,
      motivo: motivo,
    );
    await _recargarLista();
    notifyListeners();
  }

  /// Filas para "Bajar planilla": lo que hay que contar, con la columna de
  /// contado vacía para completar en papel.
  List<List<String>> filasPlanilla() => [
        ['Producto', 'Proveedor', 'En el sistema', 'Contado'],
        for (final p in visibles) [p.nombre, nombreProveedor(p), p.esPesable ? '${sistema(p)} g' : '${sistema(p)}', ''],
      ];
}

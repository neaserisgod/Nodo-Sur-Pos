// Lo que el bot de WhatsApp necesita de la base (`docs/PLAN-BOT.md`): los productos para armar su catálogo corto. La regla de
// qué entra y cómo (`catalogoParaBot`) vive en el dominio; acá solo se leen las columnas.

import '../domain/bot_whatsapp.dart';
import 'database.dart';
import 'repositorio_promos.dart' show catalogoConStockDePromos;

Future<List<ProductoParaBot>> productosParaBot(AppDatabase db) async {
  // Con el stock de cada combo ya calculado con el de sus artículos: es su "hay".
  final filas = await catalogoConStockDePromos(db);
  return [
    for (final p in filas)
      ProductoParaBot(
        globalId: p.globalId,
        nombre: p.nombre,
        activo: p.activo,
        esPesable: p.esPesable,
        esPromo: p.esPromo,
        precioCentavos: p.precioCentavos,
        precioPorKiloCentavos: p.precioPorKiloCentavos,
        stock: p.stock,
        stockGramos: p.stockGramos,
        esServicio: p.esServicio,
        esInsumo: p.esInsumo,
        esVarios: p.esVarios,
      ),
  ];
}

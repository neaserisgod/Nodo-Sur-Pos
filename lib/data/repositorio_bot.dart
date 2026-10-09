// Lo que el bot de WhatsApp necesita de la base (`docs/PLAN-BOT.md`): los productos para armar su catálogo corto. La regla de
// qué entra y cómo (`catalogoParaBot`) vive en el dominio; acá solo se leen las columnas.

import '../domain/bot_whatsapp.dart';
import 'database.dart';

Future<List<ProductoParaBot>> productosParaBot(AppDatabase db) async {
  final filas = await db.select(db.productos).get();
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
      ),
  ];
}

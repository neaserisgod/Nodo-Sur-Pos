// Forma de trabajar de un negocio: vende productos (almacén, kiosco, fiambrería) o da servicios con turno (barbería,
// uñas y belleza). Está por arriba de los módulos (`docs/PLAN-SERVICIOS.md`, etapa 1).
//
// Hace falta porque un módulo nuevo nace PRENDIDO en todos los negocios que ya existen (`modulos.dart` guarda los
// apagados): sin esto, la Agenda o los Insumos le aparecerían a un almacén al actualizar. Cada módulo dice para qué
// formas vale, y uno que no vale para la forma del negocio no se muestra ni entra en los cálculos.
//
// No se guarda aparte: sale del rubro (`PlantillaRubro.forma`), que ya está guardado y sincronizado desde la v63. Así no
// puede quedar un negocio con rubro "barbería" y forma "productos", y el bot de WhatsApp la deduce igual
// (`botdemo/src/plantillas.js`, `forma`).

enum FormaDeTrabajo {
  /// Vende productos con stock: la app de siempre. También es la forma de un negocio sin rubro elegido (todos los
  /// anteriores a la v63, como La Plazoleta), para que actualizar no le cambie nada.
  productos,

  /// Da servicios con turno: barbería, uñas y belleza, otros servicios.
  servicios,
}

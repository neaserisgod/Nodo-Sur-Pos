// Módulos opcionales del producto: qué partes de la app usa cada comercio.
//
// La lógica de cada módulo no cambia: un módulo apagado solo deja de
// mostrarse (pantallas, botones, atajos) y de entrar en los cálculos que
// dependen de él. El núcleo — vender, cobrar, stock básico y cierre de caja —
// no es un módulo: está siempre activo.
//
// Se guarda como texto en la base (`modulosDesactivados`, lista separada por
// comas) y se guardan los APAGADOS, no los prendidos, a propósito:
//  * vacío = todo activo, que es como funciona la app hoy;
//  * un módulo nuevo en una versión futura nace activo en los comercios que
//    ya existen, sin migración;
//  * una clave que esta versión no conoce (un celular más nuevo que la PC, o
//    al revés) se ignora en vez de romper.
//
// Por eso mismo cada módulo dice para qué forma de trabajar vale
// (`forma_de_trabajo.dart`): un módulo de servicios (la Agenda, los Insumos)
// nace prendido, pero un almacén no lo ve porque no vale para su forma.

import 'forma_de_trabajo.dart';

/// Las claves se guardan en la base y se sincronizan entre PC y celular:
/// NO se renombran nunca.
enum Modulo {
  /// Caja aparte para un proveedor que cobra solo en efectivo (hoy: la lata
  /// de cigarrillos, su recargo por atado y su arqueo propio).
  cajaAparte('caja_aparte'),

  /// Productos que se venden por peso (gramos), como los fiambres.
  pesables('pesables'),

  /// Promos y combos.
  promos('promos'),

  /// Encargues y deudas de clientes (el fiado se unificó con los encargues, 2026-10-03; la clave interna sigue siendo `fiado`).
  fiado('fiado'),

  /// Retiro de ganancias.
  retiroGanancias('retiro_ganancias'),

  /// Gastos fijos y punto de equilibrio.
  equilibrio('equilibrio'),

  /// Varios usuarios y cambio de turno.
  turnos('turnos'),

  /// Carga histórica de planillas.
  cargaHistorica('carga_historica'),

  /// Comparador de precios contra un sitio externo.
  compararPrecios('comparar_precios'),

  /// Cobro con la terminal de Mercado Pago Point.
  cobroPoint('cobro_point'),

  /// Insumos de los servicios: stock por envase, receta de cada servicio y lo que cuesta (`docs/PLAN-SERVICIOS.md`,
  /// etapa 2). Solo servicios.
  insumos('insumos'),

  /// Sumar la mano de obra (lo que vale la hora de trabajo) al costo de un servicio. Solo servicios.
  manoDeObra('mano_de_obra');

  const Modulo(this.clave);

  /// Nombre y explicación para la pantalla de Configuración.
  String get etiqueta => switch (this) {
    cajaAparte => 'Caja aparte para un proveedor',
    pesables => 'Productos por peso',
    promos => 'Promos y combos',
    fiado => 'Encargues y deudas',
    retiroGanancias => 'Retiro de ganancias',
    equilibrio => 'Gastos fijos y equilibrio',
    turnos => 'Varios usuarios y turnos',
    cargaHistorica => 'Carga histórica',
    compararPrecios => 'Comparador de precios',
    cobroPoint => 'Cobro con Mercado Pago Point',
    insumos => 'Insumos',
    manoDeObra => 'Mano de obra en el costo',
  };

  String get descripcion => switch (this) {
    cajaAparte => 'Un proveedor que cobra solo en efectivo y lleva su propia caja (la lata).',
    pesables => 'Productos que se venden por gramos o kilos, como los fiambres.',
    promos => 'Armar promos y combos con varios productos.',
    fiado => 'Tarjeta de encargues y deudas pendientes en el Inicio.',
    retiroGanancias => 'Revisar, retener o retirar la ganancia de cada proveedor desde Separaciones.',
    equilibrio => 'La vista "Este mes" del Inicio: gastos fijos y cuánto hay que vender para cubrirlos.',
    turnos => 'Más de un usuario y cambio de turno.',
    cargaHistorica => 'Cargar planillas de días anteriores.',
    compararPrecios => 'Comparar tus precios con supermercados de Bariloche (SEPA) y una tienda online de la zona.',
    cobroPoint => 'Cobrar con la terminal de Mercado Pago Point.',
    insumos => 'Lo que usa cada servicio, su costo y para cuántos alcanza.',
    manoDeObra => 'Sumar lo que vale la hora de trabajo al costo de cada servicio.',
  };

  /// Identificador estable que se guarda en la base.
  final String clave;

  /// Para qué formas de trabajar vale. Los de productos son de un comercio que vende con stock: la lata de
  /// cigarrillos, lo que se pesa, las promos (se abren en las líneas de sus artículos, y un servicio tiene que salir en
  /// el ticket como "Corte") y el comparador contra los supermercados. Un módulo nuevo de servicios va solo con
  /// [FormaDeTrabajo.servicios]: así no le aparece a un almacén al actualizar.
  Set<FormaDeTrabajo> get formas => switch (this) {
    cajaAparte || pesables || promos || compararPrecios => const {FormaDeTrabajo.productos},
    fiado || retiroGanancias || equilibrio || turnos || cargaHistorica || cobroPoint => const {FormaDeTrabajo.productos, FormaDeTrabajo.servicios},
    insumos || manoDeObra => const {FormaDeTrabajo.servicios},
  };

  bool valePara(FormaDeTrabajo forma) => formas.contains(forma);

  static Modulo? desdeClave(String clave) {
    for (final modulo in Modulo.values) {
      if (modulo.clave == clave) return modulo;
    }
    return null;
  }
}

/// Qué módulos tiene apagados un comercio, y su forma de trabajar. Inmutable.
class ModulosNegocio {
  const ModulosNegocio(this.desactivados, {this.forma = FormaDeTrabajo.productos});

  /// Todo activo: cómo funciona la app hoy, y lo que se asume mientras la
  /// configuración no se pudo leer (vender nunca puede frenarse por esto).
  static const ModulosNegocio todosActivos = ModulosNegocio({});

  /// Lee el texto guardado en la base. Tolera espacios, mayúsculas, claves
  /// repetidas y claves desconocidas.
  factory ModulosNegocio.desdeTexto(String texto, {FormaDeTrabajo forma = FormaDeTrabajo.productos}) {
    final apagados = <Modulo>{};
    for (final parte in texto.split(',')) {
      final clave = parte.trim().toLowerCase();
      if (clave.isEmpty) continue;
      final modulo = Modulo.desdeClave(clave);
      if (modulo != null) apagados.add(modulo);
    }
    return ModulosNegocio(apagados, forma: forma);
  }

  /// Los apagados a propósito. Puede tener módulos que no valen para [forma]: se conservan, así un negocio que cambia de
  /// rubro y vuelve encuentra todo como lo dejó.
  final Set<Modulo> desactivados;

  final FormaDeTrabajo forma;

  /// Prendido = vale para la forma del negocio y no se apagó a propósito.
  bool estaActivo(Modulo modulo) => modulo.valePara(forma) && !desactivados.contains(modulo);

  /// Los que se pueden prender o apagar en este negocio (la lista de Configuración), en el orden de [Modulo.values].
  List<Modulo> get disponibles => [for (final m in Modulo.values) if (m.valePara(forma)) m];

  /// Copia con [modulo] prendido o apagado.
  ModulosNegocio conModulo(Modulo modulo, {required bool activo}) {
    final nuevos = {...desactivados};
    if (activo) {
      nuevos.remove(modulo);
    } else {
      nuevos.add(modulo);
    }
    return ModulosNegocio(nuevos, forma: forma);
  }

  /// Texto para guardar: siempre en el orden de [Modulo.values], sin
  /// repetidos, así dos dispositivos que apagan lo mismo escriben lo mismo
  /// (la sincronización pisa la fila entera: no conviene que un orden
  /// distinto parezca un cambio).
  String aTexto() => [
        for (final modulo in Modulo.values)
          if (desactivados.contains(modulo)) modulo.clave,
      ].join(',');
}

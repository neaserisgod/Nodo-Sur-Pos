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

  /// Fiado y cuenta corriente de clientes.
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
  cobroPoint('cobro_point');

  const Modulo(this.clave);

  /// Identificador estable que se guarda en la base.
  final String clave;

  static Modulo? desdeClave(String clave) {
    for (final modulo in Modulo.values) {
      if (modulo.clave == clave) return modulo;
    }
    return null;
  }
}

/// Qué módulos tiene apagados un comercio. Inmutable.
class ModulosNegocio {
  const ModulosNegocio(this.desactivados);

  /// Todo activo: cómo funciona la app hoy, y lo que se asume mientras la
  /// configuración no se pudo leer (vender nunca puede frenarse por esto).
  static const ModulosNegocio todosActivos = ModulosNegocio({});

  /// Lee el texto guardado en la base. Tolera espacios, mayúsculas, claves
  /// repetidas y claves desconocidas.
  factory ModulosNegocio.desdeTexto(String texto) {
    final apagados = <Modulo>{};
    for (final parte in texto.split(',')) {
      final clave = parte.trim().toLowerCase();
      if (clave.isEmpty) continue;
      final modulo = Modulo.desdeClave(clave);
      if (modulo != null) apagados.add(modulo);
    }
    return ModulosNegocio(apagados);
  }

  final Set<Modulo> desactivados;

  bool estaActivo(Modulo modulo) => !desactivados.contains(modulo);

  /// Copia con [modulo] prendido o apagado.
  ModulosNegocio conModulo(Modulo modulo, {required bool activo}) {
    final nuevos = {...desactivados};
    if (activo) {
      nuevos.remove(modulo);
    } else {
      nuevos.add(modulo);
    }
    return ModulosNegocio(nuevos);
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

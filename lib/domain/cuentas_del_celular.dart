// Varias cuentas en un mismo celular, sin cerrar ninguna y sin mezclar nada (El dueño, 2026-10-13: "que un dispositivo
// pueda tener múltiples cuentas sin cerrar la otra sesión pero tampoco mezclando cosas").
//
// Una sola cuenta está ACTIVA: su base, su cuenta vinculada, su sync y sus preferencias están donde siempre, así ninguna
// pantalla ni servicio se entera de que existen otras. Las demás quedan GUARDADAS, cada una en su carpeta aparte. Cambiar de
// cuenta es mover la activa a su carpeta y traer la elegida a su lugar. Como nunca hay dos cuentas a la vez en el mismo lugar,
// no hay forma de que una venta, un producto o un token de una caiga en la otra.
//
// Acá vive solo el índice (qué cuentas hay y cuál está activa) y cómo cambia: sin archivos ni Flutter.

/// Las preferencias que son del APARATO y no de una cuenta: no se mueven al cambiar. Todo lo demás (perfil, modo de uso, PC
/// emparejada, id del equipo para la sync, cachés) es de la cuenta.
const preferenciasDelAparato = {'companion_tema', 'actualizaciones_cid'};

bool esPreferenciaDeLaCuenta(String clave) => !preferenciasDelAparato.contains(clave);

/// Una cuenta del celular, para mostrarla en la lista. [id] es el nombre de su carpeta (no cambia nunca).
class CuentaDelCelular {
  const CuentaDelCelular({required this.id, required this.email, this.nombre});

  final String id;

  /// Null si es un celular sin cuenta vinculada (solo con la PC, o "Solo celular" sin vincular).
  final String? email;

  /// El perfil con que se entró (el nombre de la persona en el POS).
  final String? nombre;

  /// Lo que se lee en la lista.
  String get titulo => email ?? nombre ?? 'Sin cuenta';

  Map<String, dynamic> toJson() => {'id': id, if (email != null) 'email': email, if (nombre != null) 'nombre': nombre};

  static CuentaDelCelular desdeJson(Map<String, dynamic> j) =>
      CuentaDelCelular(id: j['id'] as String, email: j['email'] as String?, nombre: j['nombre'] as String?);
}

/// En qué paso quedó un cambio de cuenta. Se anota ANTES de mover nada: si el celular se apaga a la mitad, al abrir se
/// termina (cada paso se puede repetir sin romper nada).
enum PasoCambio { guardando, trayendo }

/// Un cambio de cuenta a medio hacer: guardar la activa como [guardarComo] (null: la activa se descarta, ya se borró) y
/// traer [traer] (null: una cuenta nueva, vacía).
class CambioPendiente {
  const CambioPendiente({required this.guardarComo, required this.traer, required this.paso});

  final String? guardarComo;
  final String? traer;
  final PasoCambio paso;

  CambioPendiente conPaso(PasoCambio p) => CambioPendiente(guardarComo: guardarComo, traer: traer, paso: p);

  Map<String, dynamic> toJson() => {'guardarComo': guardarComo, 'traer': traer, 'paso': paso.name};

  static CambioPendiente desdeJson(Map<String, dynamic> j) => CambioPendiente(
    guardarComo: j['guardarComo'] as String?,
    traer: j['traer'] as String?,
    paso: PasoCambio.values.byName(j['paso'] as String),
  );
}

class IndiceCuentas {
  const IndiceCuentas({this.activa, this.guardadas = const [], this.cambio});

  /// La cuenta que está en uso. Null en un celular que nunca cambió de cuenta (todavía no tiene id) o recién vaciado.
  final CuentaDelCelular? activa;

  /// Las demás, la última usada primero.
  final List<CuentaDelCelular> guardadas;

  final CambioPendiente? cambio;

  static const vacio = IndiceCuentas();

  Map<String, dynamic> toJson() => {
    if (activa != null) 'activa': activa!.toJson(),
    'guardadas': [for (final c in guardadas) c.toJson()],
    if (cambio != null) 'cambio': cambio!.toJson(),
  };

  /// Un índice roto o ausente es "una sola cuenta, sin otras guardadas" (igual que un celular de antes de esto).
  static IndiceCuentas desdeJson(Object? j) {
    if (j is! Map<String, dynamic>) return vacio;
    try {
      return IndiceCuentas(
        activa: j['activa'] is Map<String, dynamic> ? CuentaDelCelular.desdeJson(j['activa']) : null,
        guardadas: [for (final c in (j['guardadas'] as List? ?? const [])) CuentaDelCelular.desdeJson(c as Map<String, dynamic>)],
        cambio: j['cambio'] is Map<String, dynamic> ? CambioPendiente.desdeJson(j['cambio']) : null,
      );
    } catch (_) {
      return vacio;
    }
  }
}

/// El cambio que hay que anotar para pasar de la activa (ya identificada como [actual]) a [destino] (null: agregar una
/// cuenta nueva). Lanza si [destino] no está guardada: nunca se trae algo que no existe.
IndiceCuentas empezarCambio(IndiceCuentas indice, {required CuentaDelCelular actual, required String? destino}) {
  if (destino != null && !indice.guardadas.any((c) => c.id == destino)) {
    throw StateError('No hay ninguna cuenta guardada con id $destino');
  }
  return IndiceCuentas(
    activa: actual,
    guardadas: indice.guardadas,
    cambio: CambioPendiente(guardarComo: actual.id, traer: destino, paso: PasoCambio.guardando),
  );
}

/// La activa se borró ("Cerrar sesión y borrar") y hay otras guardadas: se trae la última usada, sin guardar nada.
IndiceCuentas empezarTraerTrasBorrar(IndiceCuentas indice) => IndiceCuentas(
  guardadas: indice.guardadas,
  cambio: indice.guardadas.isEmpty
      ? null
      : CambioPendiente(guardarComo: null, traer: indice.guardadas.first.id, paso: PasoCambio.trayendo),
);

/// Cómo queda el índice con el cambio ya hecho: la que se guardó pasa primera en la lista (la última usada) y la que se
/// trajo pasa a activa.
IndiceCuentas terminarCambio(IndiceCuentas indice) {
  final cambio = indice.cambio;
  if (cambio == null) return indice;
  final traida = cambio.traer == null ? null : indice.guardadas.where((c) => c.id == cambio.traer).firstOrNull;
  final guardada = cambio.guardarComo == null ? null : indice.activa;
  return IndiceCuentas(
    activa: traida,
    guardadas: [
      ?guardada,
      for (final c in indice.guardadas)
        if (c.id != cambio.traer && c.id != guardada?.id) c,
    ],
  );
}

/// Si la activa (con [email]) ya está guardada con el mismo mail, la guardada sobra: es la misma cuenta dos veces. Devuelve
/// el id de esa repetida, o null.
String? cuentaRepetida(IndiceCuentas indice, String? email) {
  if (email == null) return null;
  final e = email.trim().toLowerCase();
  return indice.guardadas.where((c) => c.email?.trim().toLowerCase() == e).firstOrNull?.id;
}

// Cómo se usa este celular (El dueño, 2026-10-01: "que la app dé a elegir si se tiene una PC, o si solo se usa el
// móvil como sistema"). Se elige una vez, al primer arranque, y se puede cambiar desde Gestión.
//
//  - PC y celular: el celular se conecta a la PC por wifi y, si la PC se apaga, sigue solo por internet
//    (`conmutador_sync.dart`). Es lo que hacía la companion hasta ahora con una PC emparejada.
//  - Solo celular: el celular es el sistema. Trabaja con su propia base y, con una cuenta de Nodo Sur vinculada,
//    sincroniza por internet igual que lo hace la PC.

enum ModoUso {
  pcYCelular('pc'),
  soloCelular('celular');

  const ModoUso(this.clave);

  /// Lo que se guarda en el celular.
  final String clave;

  static ModoUso? desdeClave(String? clave) {
    for (final m in values) {
      if (m.clave == clave) return m;
    }
    return null;
  }
}

/// Qué modo corresponde dado lo que hay guardado. Las instalaciones anteriores a esta pantalla no lo tienen:
///  - con una PC emparejada venían usando "PC y celular";
///  - sin PC pero con un usuario ya elegido venían usando el celular solo (desde 2026-09-18 la companion
///    funciona sin emparejar, "no debería tener que escanear ya");
///  - una instalación nueva no tiene ninguna de las dos: hay que preguntar (devuelve null).
ModoUso? resolverModoUso({
  required ModoUso? guardado,
  required bool tieneConexion,
  required bool tieneUsuario,
}) {
  if (guardado != null) return guardado;
  if (tieneConexion) return ModoUso.pcYCelular;
  if (tieneUsuario) return ModoUso.soloCelular;
  return null;
}

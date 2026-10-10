import 'package:drift/drift.dart';

import 'catalogo.dart';

/// Fila única (siempre `id = 1`) con las reglas de negocio que el dueño pidió
/// poder editar también desde el celular (2026-09-19: "que se puedan
/// modificar las reglas del negocio... desde ahí"). Separada de
/// `ConfiguracionTabla` a propósito: esa tabla mezcla estas reglas con
/// secretos (`companionToken`, credenciales de Mercado Pago) y datos de UI
/// del escritorio (tema, carpeta de respaldo) en la misma fila — el
/// mecanismo de sync (`repositorio_sincronizacion.dart`) hace "última fila
/// gana" sobre la fila ENTERA, así que sincronizar esa tabla tal cual
/// arriesgaría tanto un secreto viajando por Supabase como que un cambio de
/// negocio en el celular pisara sin querer una ruta de carpeta que la PC
/// acababa de cambiar. Esta tabla, angosta y sin nada sensible, sí entra al
/// mecanismo genérico (`tablasSincronizables`) sin ese riesgo.
///
/// `ConfiguracionTabla` sigue existiendo tal cual — esta tabla no la
/// reemplaza, solo le saca estas 5 columnas de encima para el propósito de
/// sync (Regla 3: cada dato vive en un solo lugar, la migración v32→v33 que
/// la crea copia los valores reales, nunca duplica la fuente de verdad).
@DataClassName('ConfiguracionNegocio')
class ConfiguracionNegocioTabla extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Regla 6 — mismos tres montos y mismo default que tenían en
  /// `ConfiguracionTabla`.
  IntColumn get recargoPrimerAtadoCentavos =>
      integer().withDefault(const Constant(30000))();
  IntColumn get recargoAtadoAdicionalCentavos =>
      integer().withDefault(const Constant(10000))();
  IntColumn get recargoSueltoCentavos =>
      integer().withDefault(const Constant(5000))();

  /// Regla 2, paso de redondeo del total en efectivo. Default 100 pesos.
  IntColumn get pasoRedondeoCentavos =>
      integer().withDefault(const Constant(10000))();

  /// Producto del botón fijo de "vuelto" (Alt+C en la venta). A diferencia
  /// de la columna vieja en `ConfiguracionTabla` (sin referencia declarada,
  /// un descuido de la fase 8), esta sí la declara — `productos` ya
  /// sincroniza, así que esta FK necesita la misma traducción por
  /// `global_id` que ya usan `productos.categoria_id`/`proveedor_id`
  /// (`_referenciasCruzadas`, `repositorio_sincronizacion.dart`).
  IntColumn get productoVueltoId =>
      integer().nullable().references(Productos, #id)();

  /// Generalización del producto (fase 1): datos propios de cada comercio.
  /// Las tres columnas nacen vacías — nada las lee todavía con efecto; las
  /// fases siguientes las usan (marca visible, ticket, módulos). Vacío
  /// significa "sin configurar", no "sin nombre a propósito".
  ///
  /// Nombre del comercio: lo que se ve en la ventana, el ticket y el celular.
  TextColumn get nombreComercio => text().withDefault(const Constant(''))();

  /// Encabezado del ticket, una línea por renglón (nombre, dirección…).
  TextColumn get encabezadoTicket => text().withDefault(const Constant(''))();

  /// Módulos apagados, claves separadas por coma (`domain/modulos.dart`).
  /// Vacío = todos activos, que es como funciona la app hoy. Se guardan los
  /// apagados para que un módulo nuevo nazca activo sin migración.
  TextColumn get modulosDesactivados => text().withDefault(const Constant(''))();

  /// Rubro del comercio, la clave de `PlantillaRubro` (`domain/plantillas_rubro.dart`): `almacen`, `kiosco`… Vacío = sin
  /// elegir. Hasta la v63 el rubro solo servía para sembrar categorías y no quedaba guardado en ningún lado; ahora se guarda
  /// porque lo necesita el bot de WhatsApp para saber cómo hablar y qué hacer (El dueño, 2026-10-09, `docs/PLAN-BOT.md`).
  /// Viaja con esta fila por la sync; un equipo sin actualizar la recibe sin esta columna y no la pisa (solo actualiza las
  /// columnas que trae).
  TextColumn get rubro => text().withDefault(const Constant(''))();

  /// Lo que vale una hora de trabajo, para sumar la mano de obra al costo de un servicio (v65; El dueño, 2026-10-09: un
  /// valor por negocio). Null: sin cargar.
  IntColumn get valorHoraCentavos => integer().nullable()();

  // --- Agenda y seña de turnos (v66, `REGLAS-NEGOCIO.md` §21, `domain/turnos.dart`) ---

  /// El horario de atención: uno solo, que usan la Agenda y el bot (§21). JSON con el formato del bot
  /// (`{"lunes": {"desde": "09:00", "hasta": "18:00"}, "domingo": null}`). Null: el de arranque (`HorarioAtencion.porDefecto`).
  TextColumn get horarioAtencion => text().nullable()();

  /// Cada cuántos minutos arrancan los horarios que se ofrecen (§21: 15, cada negocio puede cambiarlo).
  IntColumn get pasoTurnosMinutos => integer().withDefault(const Constant(15))();

  /// `ModoSena.clave`: nunca, algunos servicios (los que piden seña) o todos. Por defecto, algunos.
  TextColumn get senaModo => text().withDefault(const Constant('ALGUNOS'))();
  IntColumn get senaPorcentaje => integer().withDefault(const Constant(30))();

  /// Un monto fijo en vez del porcentaje. Null: va el porcentaje.
  IntColumn get senaMontoFijoCentavos => integer().nullable()();

  /// Si cancelan, la seña se devuelve (true) o se pierde (false, el arranque).
  BoolColumn get senaDevolverAlCancelar => boolean().withDefault(const Constant(false))();

  /// A dónde se transfiere la seña (lo dice el bot): alias de Mercado Pago o CBU, y a nombre de quién.
  TextColumn get aliasSena => text().withDefault(const Constant(''))();
  TextColumn get titularSena => text().withDefault(const Constant(''))();

  /// Identidad de sincronización — ver el comentario de
  /// `Categorias.globalId` (`tables/catalogo.dart`) para el porqué completo.
  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();
  DateTimeColumn get actualizadoEn => dateTime().nullable()();
}

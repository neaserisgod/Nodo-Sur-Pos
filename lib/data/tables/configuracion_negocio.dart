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

  /// Identidad de sincronización — ver el comentario de
  /// `Categorias.globalId` (`tables/catalogo.dart`) para el porqué completo.
  TextColumn get globalId => text().nullable()();
  TextColumn get origenDispositivo => text().nullable()();
  DateTimeColumn get actualizadoEn => dateTime().nullable()();
}

import 'package:drift/drift.dart';

/// Fila única de configuración (siempre `id = 1`). Solo los campos que la
/// fase 3 necesita para calcular un total — el resto de lo configurable que
/// lista CLAUDE.md (fondo fijo, reserva diaria, colchón por proveedor ya
/// vive en `proveedores`, rutas de respaldo...) se agrega cuando exista una
/// pantalla de configuración real (fase 8). Hasta entonces, esta tabla
/// crece de a poco en vez de existir vacía esperando esa fase.
@DataClassName('Configuracion')
class ConfiguracionTabla extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Regla 6, los "tres montos" del recargo de cigarrillos. El de suelto
  /// pasó de 0 a 5000 ($50) el 2026-09-10 (El dueño: "los puchos sueltos
  /// también deben tener recargo por MP, sin eso los cálculos dan mal") —
  /// una base ya existente necesita la migración v23→v24 de `database.dart`
  /// además de este default nuevo, que solo alcanza a una base recién creada.
  IntColumn get recargoPrimerAtadoCentavos =>
      integer().withDefault(const Constant(30000))();
  IntColumn get recargoAtadoAdicionalCentavos =>
      integer().withDefault(const Constant(10000))();
  IntColumn get recargoSueltoCentavos =>
      integer().withDefault(const Constant(5000))();

  /// Regla 2, paso de redondeo del total en efectivo. Default 100 pesos.
  IntColumn get pasoRedondeoCentavos =>
      integer().withDefault(const Constant(10000))();

  /// Vestigial desde la fase 7: existía como valor fijo mientras no había
  /// ninguna pantalla para cargar fijos reales (Regla 12). Ya no se lee —
  /// `repositorio_cierre.dart` calcula la reserva diaria real desde
  /// `gastos_fijos_montos` (`repositorio_equilibrio.dart`). Se deja la
  /// columna en vez de borrarla: la migración que la creó ya salió, y no se
  /// edita (ver cabecera de `database.dart`).
  IntColumn get reservaDiariaFijosCentavos =>
      integer().withDefault(const Constant(7000000))();

  /// Cuánta plata dejar en el cajón para dar vuelto — dato operativo. Hasta
  /// Regla 13 vieja (retiro semanal, eliminada) participaba de esa fórmula;
  /// ya no calcula nada, queda como referencia para saber cuánto efectivo
  /// conviene no llevarse nunca del cajón. Default $150.000.
  IntColumn get fondoFijoCentavos =>
      integer().withDefault(const Constant(15000000))();

  // ─── Fase 10: respaldo e impresión ─────────────────────────────────────

  /// Carpeta local (normalmente sincronizada por Drive/OneDrive) donde se
  /// guardan las copias de la base. Null hasta que se configure a mano —
  /// nunca un default silencioso, porque escribir en una carpeta que el
  /// dueño no eligió no cumple el propósito de tener un respaldo externo.
  TextColumn get rutaRespaldoCarpeta => text().nullable()();

  /// Cuántas copias de respaldo se conservan antes de borrar la más vieja.
  IntColumn get respaldoCantidadCopias =>
      integer().withDefault(const Constant(14))();

  /// Carpeta local donde se guarda el PDF de cada ticket.
  TextColumn get rutaTicketsCarpeta => text().nullable()();

  /// Credenciales de la terminal Point de MercadoPago que imprime el ticket
  /// (Regla: es una acción independiente de cuál terminal cobró la venta).
  TextColumn get mpAccessToken => text().nullable()();
  TextColumn get mpTerminalId => text().nullable()();

  /// Fase 12: la terminal que cobra por QR/Débito — campo separado de
  /// [mpTerminalId] aunque hoy señalen la misma terminal física (El dueño
  /// tiene dos posnets: uno para cobro manual que la app nunca toca, y
  /// este, "el del sistema", que imprime Y cobra).
  TextColumn get mpTerminalCobroId => text().nullable()();

  // ─── Fase 8: configuración centralizada ────────────────────────────────

  /// Vestigial desde que se eliminó el retiro semanal (Regla 13 vieja — la
  /// separación de ganancia pasó a ser diaria, parte del ritual de
  /// apertura). Ya no se lee. Se deja la columna en vez de borrarla, mismo
  /// criterio que `reservaDiariaFijosCentavos` arriba.
  TextColumn get diaRetiroSemanal => text().withDefault(const Constant('domingo'))();

  /// Producto que agrega el botón fijo de "vuelto" en la pantalla de venta
  /// (mismo patrón que el botón de "Varios": siempre visible, agrega 1
  /// unidad al carrito). Null hasta que se configure — sin default, porque
  /// no hay un producto "obvio" que asumir.
  IntColumn get productoVueltoId => integer().nullable()();

  // ─── Fase 11: sistema de diseño ─────────────────────────────────────────

  /// Modo oscuro elegido a mano. Solo se lee cuando [temaAutomatico] está
  /// apagado — con el automático prendido, `oscuroPorHorarioDelLocal`
  /// decide, y esta columna sigue guardando el último valor manual para
  /// volver a él si el dueño apaga el automático.
  BoolColumn get temaOscuro => boolean().withDefault(const Constant(true))();

  /// Tema automático según el horario del local (revisión visual fase 13):
  /// prendido por default — es el comportamiento esperado, no una opción que
  /// haya que activar. El switch de "Modo oscuro" pasa a ser de solo lectura
  /// mientras esto esté prendido (`_SeccionApariencia`).
  BoolColumn get temaAutomatico => boolean().withDefault(const Constant(true))();

  /// Vestigial desde que se eliminó el retiro semanal (Regla 13 vieja): ese
  /// switch decidía si se restaban los fijos pendientes de la fórmula del
  /// retiro. La fórmula entera desapareció — "fijos pendientes este mes" se
  /// sigue mostrando (Regla 13 nueva), pero como dato al lado del total,
  /// nunca como una resta automática. Ya no se lee.
  BoolColumn get retiroDescuentaFijosPendientes => boolean().withDefault(const Constant(false))();

  /// Si la barra lateral de navegación arranca plegada (solo íconos) o
  /// desplegada (íconos + nombre). Plegada por default (2026-09-12, el dueño:
  /// "no quiero 50 botones en cualquier lado") — revierte la corrección de
  /// fase 13 ("desplegada por default", ver DECISIONES.md), que había
  /// ganado por el motivo contrario ("no saber dónde hacer clic"). Los
  /// nombres siguen a un clic de distancia (desplegar es explícito, nunca
  /// automático al pasar el mouse); esta vez gana la superficie despejada.
  /// Se recuerda entre arranques, no se pregunta cada vez.
  BoolColumn get barraLateralPlegada => boolean().withDefault(const Constant(true))();

  /// Período del selector compartido entre Proveedores y Productos (fase
  /// 13) — guarda el nombre de `PeriodoResumen` ('hoy'/'semana'/'mes'/
  /// 'desdeUltimoPago'), un enum y no un booleano porque son cuatro
  /// opciones, no dos. Default 'mes' (El dueño). Se recuerda entre visitas,
  /// mismo criterio que `barraLateralPlegada`.
  TextColumn get periodoResumen => text().withDefault(const Constant('mes'))();

  // ─── Companion app Android (spike 2026-09-07) ──────────────────────────

  /// Token compartido para que el celular se autentique contra el servidor
  /// HTTP local (`lib/servidor/servidor_companion.dart`) — null hasta que se
  /// genera desde Configuración. No es login de usuario (la app sigue "sin
  /// autenticación" para las personas, el dueño/su empleado eligen quién son
  /// de una lista, igual que al abrir caja): es solo la llave que evita que
  /// cualquier otro dispositivo de la misma WiFi pueda pegarle al servidor.
  TextColumn get companionToken => text().nullable()();

  /// Companion Android sin depender del escritorio (2026-09-15): con dos
  /// dispositivos que pueden vender sin verse, un solo cajón físico necesita
  /// un solo dueño fijo para "abrir el día" — el otro dispositivo se suma a
  /// esa apertura al sincronizar en vez de abrir la suya propia (decisión de
  /// El dueño: nunca fusión automática y silenciosa de dos aperturas). Null
  /// significa "todavía no se decidió" — cualquier dispositivo puede abrir
  /// la primera vez, mismo comportamiento que hoy. Valores: `'desktop'` o el
  /// `dispositivoId` estable del celular emparejado (`emparejamiento.dart`).
  TextColumn get dispositivoAperturaDesignadoId => text().nullable()();
}

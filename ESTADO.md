# Estado actual — La Plazoleta

**Fuente de verdad del estado del proyecto EN ESTE MOMENTO**: qué fases
están cerradas, qué falta, métricas que cambian seguido (tests,
`schemaVersion`) y qué hacer a continuación. Este documento se actualiza al
cerrar cada fase o al final de cada sesión de trabajo — si dice algo que
`git log`/el código contradicen, confiar en el código y corregir esto.

Para qué es cada fase y cómo se construye, ver `CLAUDE.md`. Para las reglas
del negocio, `REGLAS-NEGOCIO.md`. Para el sistema de diseño, `DISENO.md`.

---

## Lo último (2026-10-03) — publicado: Windows estable 1.0.0.2127 y Android estable 1.0.0+2128

Resumen para retomar en `CONTEXTO.md`. Todo lo de esta sección está mezclado en `main` y publicado.

- **Auditoría de la caja** (el dueño veía diferencias negativas): se revisó cómo se registra cada ingreso y egreso por
  medio (efectivo, MP, lata) y cómo se calculan el esperado y el resumen. `test/data/conciliacion_caja_test.dart` arma
  120 días al azar (ventas efectivo/QR, editar/anular, gastos, ingresos, pagos a proveedor por las tres vías, retiros) y
  compara con un libro independiente: coincide siempre. Con el PDF de un día real se confirmó a mano que la app suma bien;
  la diferencia era plata que salió sin anotarse (error humano). Arreglos que salieron de la revisión:
  - Abrir caja desde el celular sin MP explícito arrastra el último MP **contado** (antes arrancaba en $0).
  - La sync no reabre una caja ya `CERRADA` con una fila vieja de la apertura que llega tarde (borraba el arqueo);
    reabrir de verdad sigue pasando (`repositorio_sincronizacion.dart`).
  - Cerrar caja desde el aviso de "cerrar la app con la caja abierta" termina en "Cerrar el sistema" (antes "Volver a
    la venta" dejaba la duda de si se había cerrado).
- **Exportar el día completo** desde el celular (Gestión → Cierres → un día → PDF): arqueo de las tres cajas, ventas
  con líneas y pagos (anuladas marcadas), movimientos de caja y arqueos intermedios (`lib/data/pdf_dia_completo.dart`).
  Usa la base del celular; con la PC conectada busca el día por hora de apertura.
- **Mercado Pago según Mercado Pago** en el cierre (PC, al revisar y ya cerrado; celular, en el detalle de cada cierre):
  cobros reales del turno leídos con `GET /api/mp/cobros` del sitio (bruto, devoluciones, comisión, neto), lo
  registrado como MP, diferencia de cobros, cobros sin venta y ventas sin cobro (emparejados por monto, el más cercano
  en el tiempo) y el esperado con comisiones. Nunca frena el cierre. Piezas: `domain/conciliacion_mp.dart`,
  `data/repositorio_conciliacion_mp.dart`, `ClienteNube.cobrosMp`, `servicios/conciliacion_mp_nube.dart`,
  `ui/cierre/seccion_mp_real.dart`. No probado todavía contra la cuenta real en un cierre.
- **Rediseño de navbar y Configuración** (PC y celular): Configuración pasó a un engranaje al final de la navbar; los 15
  apartados de la PC quedaron en 5 grupos (`GrupoConfiguracion` en `configuracion_controlador.dart`) con pastillas por
  sección y menos texto; el celular usa los mismos grupos, "Volver" arriba y solo "Guardar" abajo.
- **Celular**: bienvenida al primer arranque y "Entrar con Google" + "Configurá tu negocio" (PR #46, de otra sesión).
- Antes (02/10): cobro QR/débito por el servidor con el MP del negocio, interruptor "Cobrar e imprimir por Nodo Sur",
  imprimir en la terminal por el servidor (`MODELO__SERIAL`), mensajes de cuenta para empleados, índices de la base y
  "Más vendidos" memorizado, publicar solo con `release:`/`beta:` en el título.

---

## Android: entrar con Google y "Configurá tu negocio" (2026-10-03) — publicado (APK 1.0.0+2127)

- "Entrá con tu cuenta" con un solo botón "Continuar con Google" (`bienvenida/vista_entrar_con_google.dart`).
- El dueño de un negocio nuevo que usa solo el celular sigue, después de "Listo", a "Configurá tu negocio"
  (`configurar/`): nombre y rubro, un primer producto escaneado de práctica, y Mercado Pago y equipo (en la web). Deja la
  base lista para vender (reglas del negocio y categorías del rubro, con `global_id`). Lo salteado queda como tarjeta en
  Inicio. Motivos en `DECISIONES.md`.
- Tests: `test/companion/negocio_nuevo_test.dart` (18) y capturas de cada paso. `test/companion`: 180 verdes.
- No probado en un celular real ni contra la nube real.

## Android: bienvenida al primer arranque (2026-10-03) — publicado (APK 1.0.0+2127)

- Instalación nueva: logo → bienvenida de seis escenas con "Siguiente"/"Saltar" (`lib/companion/bienvenida/`) → elegir modo →
  entrar con la cuenta (o emparejar) → "Listo, {nombre}." → menú. Los celulares en uso no la ven. Detalle en `DECISIONES.md`.
- Tests: `test/companion/bienvenida_test.dart` (7) y capturas de cada escena y de "Listo" en `capturas_companion_test.dart`.
  `test/companion`: 154 verdes.
- No probado en un celular real.

## Android: accesos del Inicio y pagar proveedor (2026-10-02) — publicado

- Inicio del celular: grilla de accesos con **Consultar precio**, **Movimiento de caja**,
  **Pagar proveedor** (nuevo) y **Hacer arqueo** (nuevo, solo con la caja abierta).
- **Pagar proveedor** va por la cuenta corriente de la PC (necesita la PC; ver `DECISIONES.md`,
  "Pagar proveedor: un solo camino"). Se sacó el selector de proveedor del gasto rápido/movimiento
  de caja que había agregado el PR #28. Sin tocar el esquema (`schemaVersion` igual).
- Tests: rutas nuevas del servidor (5) y el aviso sin PC del modo local; los que ya existían, igual.
  Siguen sin cargar los tests que importan `test/capturas/` (no está en el repo).
- No probado en un celular real ni contra la PC real.

---

## Instalador y actualización automática (2026-09-30) — publicado y en uso

La app ya se puede distribuir con instalador (Inno Setup) y actualizarse sola
desde `horsepos.com`. Decisiones y motivos en `DECISIONES.md` ("Instalador y
actualización automática"); las trampas que aparecieron, en `TRAMPAS.md`.

- **Qué hay**: `installer/la_plazoleta.iss`, `tool/crear_instalador.ps1`
  (build + firma + instalador en `dist/`, imprime SHA-256),
  `tool/publicar_release.ps1` (sube build, instala, firma para el
  actualizador y llama a `publicar-release.mjs`; `-DryRun`, `-Notas`,
  `-Rollout`), `tool/generar_claves_actualizacion.ps1`, y
  `tool/_version.ps1` (helpers compartidos). `publicar_actualizacion_desktop.ps1`
  sigue igual y ahora también sube el build (`-SinSubirBuild` lo evita).
- **En la app**: `lib/domain/actualizacion.dart` (reglas puras),
  `lib/servicios/actualizaciones.dart` (cid, detección silenciosa, aviso),
  `lib/servicios/actualizador_nativo.dart` (WinSparkle), aviso en la barra de
  ventana, y Configuración → "Versión y actualizaciones".
- **Probado**: 43 tests nuevos (25 de dominio, 18 de servicio); el instalador en carpeta
  temporal con base falsa (instalar, actualizar con la app abierta, la
  carrera de WinSparkle, sin base, desinstalar, y que la base y
  `C:\LaPlazoleta` real no se tocan); y que la firma DSA de `sign_update`
  verifica contra `dsa_pub.pem` y falla con un byte cambiado.
- **NO probado de punta a punta**: una actualización real de una PC
  instalada contra el feed real (hace falta publicar una versión; ver abajo),
  y que WinSparkle rechace una firma inválida (se probó la firma con
  `openssl`, no el rechazo dentro de WinSparkle). Firma de código real: sin
  certificado todavía, el instalador sale sin firmar y SmartScreen advierte.
- **Clave privada**: `Documents\la_plazoleta_claves\dsa_priv.pem`, FUERA del
  repo. **Hay que respaldarla** (USB + copia en otro lugar): si se pierde,
  ninguna PC instalada puede recibir más actualizaciones, y la única salida
  sería reinstalar a mano con una clave pública nueva.
- **Pendiente a mano (El dueño)**: ver la lista al final de `DECISIONES.md`
  ("Instalador y actualización automática").

---

## Generalización del producto (desde 2026-09-30)

La app deja de ser específica de un solo local y pasa a ser **Nodo Sur POS**,
configurable por cada comercio. Decisiones y motivos: `DECISIONES.md`,
"Generalización del producto". Se hace por fases chicas, cada una en su PR,
con la suite en verde y sin cambiar cómo funciona el local de origen.

- **Fase 1 (capa de configuración) — hecha**: `configuracion_negocio_tabla`
  suma `nombre_comercio`, `encabezado_ticket` y `modulos_desactivados`
  (migración v43 → v44, aditiva, sin tocar filas). `domain/modulos.dart` define
  los 10 módulos opcionales y cómo se guardan. `repositorio_configuracion.dart`
  suma `modulosNegocioActuales`, `configurarModulo`, `configurarNombreComercio`
  y `configurarEncabezadoTicket`. **Nada en la app usa estos datos todavía**:
  el comportamiento es idéntico. Suite: 1271 tests verdes + 4 que no compilan
  por `test/capturas/` (ver `TRAMPAS.md`); `schemaVersion` 44.
- **Fase 2 (datos iniciales por rubro) — hecha**: una base NUEVA ya no trae las
  categorías, los 15 proveedores ni los gastos fijos del local de origen, y el
  usuario inicial se llama "Administrador" (antes, el nombre del dueño). Lo
  estructural sigue sembrándose (cajas, medios de pago, producto "Varios",
  accesos directos, secciones del menú, configuración). `domain/plantillas_rubro.dart`
  define las plantillas (Kiosco, Almacén, Fiambrería, Otro) y
  `repositorio_plantillas.dart` las aplica sin duplicar ni pisar nada; el
  asistente de primer arranque (fase 7) las va a ofrecer. Las bases existentes
  no cambian. Los tests que partían del catálogo viejo lo reciben de
  `test/helpers/base_para_tests.dart` (`baseDeTest()`); los que prueban una base
  nueva usan `AppDatabase(NativeDatabase.memory())` directo. Suite: 1289 tests
  verdes + 4 que no compilan por `test/capturas/`; `schemaVersion` sigue en 44.
- **Fase 3 (marca visible) — hecha**: la ventana, el menú, el login, el celular,
  el PDF y el encabezado del ticket toman el nombre de `configuracion_negocio`
  (`domain/marca.dart`, `servicios/marca_actual.dart`); sin nombre cargado
  muestran "Nodo Sur POS". La dirección del local ya no está escrita en el
  código. Nuevo: Configuración → "Mi comercio" (nombre + encabezado multilínea
  con vista previa) y un aviso de primer arranque (`ui/comun/dialogo_datos_comercio.dart`,
  "Más tarde" lo pospone hasta la próxima apertura). **Falta en la PC de origen**:
  cargar nombre y dirección una vez. El celular muestra "Nodo Sur POS" hasta que
  el companion reciba la marca por sync. Suite: 1315 verdes + 4 que no compilan por
  `test/capturas/`. Sin migración.
- **Fase 4 (proveedor con caja aparte) — hecha**: el código fijo `'SC'` (Distribuidora
  Cigarros) ya no decide nada. `proveedores.caja_aparte` (v45, nace en falso)
  lo reemplaza en los 5 lugares donde se miraba el código (reposición ×3,
  panel "Ver lata", diálogo Avanzado). La migración marca `SC` en las bases que
  lo tenían, sin tocar `actualizado_en`. En Avanzado hay un interruptor "Caja
  aparte (cobra solo en efectivo)"; con él el proveedor cobra en efectivo y
  tiene su panel de lata. Las columnas `esLata`/`lata*` no se renombran.
  Suite: 1322 verdes + 4 que no compilan por `test/capturas/`; `schemaVersion` 45.
- **Fase 5a (módulos activables, primera parte) — hecha**: `servicios/modulos_activos.dart`
  (`modulosActuales`, `seguirModulos`, `moduloActivo`, widget `SiModulo`), alimentado
  desde `main.dart`. Configuración → "Módulos" con un interruptor por módulo. Ya
  se esconden: **Promos**, **Comparador de precios** (menú "Más acciones" de
  Proveedores y la descarga en segundo plano al arrancar) y **Carga histórica**
  (botón de Historial). Todo activo = igual que antes; no se borra ningún dato.
  El celular todavía no sigue los módulos (su pantalla de carga histórica sigue
  visible). Suite: 1329 verdes + 4 que no compilan por `test/capturas/`.
  Faltan: fiado, retiro de ganancias, equilibrio, turnos, Point, pesables y caja aparte.
- **Fase 5b (fiado, retiro de ganancias, equilibrio) — hecha**: sin **Fiado** el
  Inicio no muestra la tarjeta de fiados y encargues; sin **Retiro de ganancias**
  la tarjeta de un proveedor en Separaciones ya no abre el diálogo de ganancia
  (retener/retirar); sin **Equilibrio** el Inicio queda solo con "Hoy" (sin
  "Este mes"). El Inicio reacciona al instante al interruptor. Faltan: turnos,
  Point, pesables y caja aparte.
- **Fase 5c (turnos y Point) — hecha**: sin **Turnos** desaparecen "Cambiar de
  turno" y el aviso de arqueo cada 2 horas de la pantalla de venta (cerrar caja y
  el arqueo del cierre siguen). Sin **Cobro con Point**, QR y Débito se cobran
  directo, sin terminal (el mismo camino que "Cobrar a mano"); la configuración de
  la terminal queda visible en Configuración → Impresión. Faltan: pesables y caja aparte.
- **Fase 5d (pesables y caja aparte) — hecha**: sin **Pesables**, el producto
  nuevo no ofrece "Es pesable" (un producto que ya lo es conserva el interruptor);
  ventas y stock de los pesables existentes no cambian. Sin **Caja aparte** se
  esconden: el bloque de cigarrillos y la lata del cierre y de las hojas de
  apertura/arqueo, la opción "Lata cigarrillos" del movimiento rápido, el
  selector "Cigarrillo" del producto y Configuración → "Recargo de cigarrillos"
  (la pantalla inicial pasa a "Mi comercio"). El cierre y el arqueo dan por buena
  la lata esperada (diferencia 0): no se exige contar lo que no se usa. Los
  datos (caja lata, columnas) siguen; al prender el módulo vuelve todo.
  **Con esto están los 10 módulos.** Suite: ver PR.
- **Fase 8 (sin Firebase ni Supabase) — hecha**: se sacó todo el código de nube de
  terceros (Supabase: sync por internet, login de Google de PC y celular;
  Firebase/Firestore: restos que ya no compilaban), las dependencias
  `supabase_flutter`/`google_sign_in`/`mocktail`, el plugin de Google Services de
  Android y `supabase/schema.sql`. Se mantiene el motor de sincronización
  (`repositorio_sincronizacion.dart`) y la sync por wifi PC↔celular. El celular
  ya no pide login: entra directo a elegir usuario. Se eliminó Configuración →
  "Cuenta de Google" (la cuenta del producto será la de Nodo Sur, aparte).
  **Cambio de comportamiento**: sin la PC al alcance, el celular ya no puede
  cobrar con la terminal Point (las credenciales viajaban por Supabase); avisa
  que se hace conectado a la PC. `flutter analyze lib` queda sin errores. Suite:
  1329 verdes + 4 que no compilan por `test/capturas/`.
- **Fase 9 (documentación y limpieza) — hecha**: `tool/limpiar_datos_personales.py`
  (idempotente; dry-run por defecto) y aplicado: el nombre del dueño, los
  proveedores reales y el cliente recurrente pasan a nombres genéricos en código,
  tests y documentos (308 archivos; los tests y el código cambian juntos).
  `REGLAS-NEGOCIO.md` ahora dice qué módulo activa cada regla, y
  `docs/perfiles/la-plazoleta.md` describe el comercio de origen. Un comercio
  nuevo arranca con el comparador de precios apagado (está armado para la
  ciudad y la tienda online del origen; la base del origen no cambia). Se
  renombraron identificadores con nombre de proveedor (`esCajaAparte`,
  `pagosAProveedorDesdeLataCentavos`). Quedan nombres internos con "Plazoleta"
  a propósito. Suite: 1330 verdes + 4 que no compilan por `test/capturas/`.
- **La generalización del POS está completa** (fases 6 y 7 descartadas).
- **Nube, parte A (app) — hecha**: Configuración → "Cuenta de Nodo Sur". Vincular la
  PC a la cuenta de Google del sitio (navegador + servidor local 127.0.0.1 + PKCE,
  `servicios/cuenta_nube.dart`, `domain/vinculacion.dart`), guardar una copia de la
  base (VACUUM INTO → gzip → hash → `PUT /api/backup`), listar y **restaurar** copias
  de la cuenta (baja, verifica hash y versión de esquema, y reusa la confirmación y el
  reinicio del respaldo local), y desvincular. Las copias salen solas al cerrar caja
  (en segundo plano, una falla no afecta el cierre) y una vez por día mientras la app
  esté abierta; al arrancar la PC avisa al servidor (versión, sistema, id) y renueva su
  token; una cuenta de administrador recibe las versiones beta antes. El token vive en
  `nodosur_cuenta.json` (carpeta de datos de la app), fuera de la base: restaurar no
  lo pisa. Suite: 1375 verdes + 4 que no compilan por `test/capturas/`.
  Falta: probar contra el servidor real con una cuenta (ver PR).
- **Sync por la nube, fase 2 (PC) — hecha, sin probar contra el servidor real**: `servicios/sync_nube.dart` baja
  y sube lotes por `/api/sync` con cada cambio de la base (más un latido de 20 s), sin eco y con "gana el último en
  llegar" (`DECISIONES.md`, "Sync por la nube entre dispositivos"). Se arranca solo con la app, si hay cuenta vinculada.
  Baja solo cuando el servidor avisa (WebSocket a un Durable Object, sin sondeo): hay que **desplegar `NodoSurPage`**
  (agrega el binding `SYNC_HUB` y su migración) y probarlo con dos dispositivos reales — la hibernación y el upgrade
  del WebSocket no se pueden probar sin Cloudflare.
  Falta: un indicador de estado de la sync en la UI de escritorio. Servidor en `NodoSurPage` (rama
  `claude/quirky-noether-pbunw6`).
- **Sync por la nube, fase 3 (celular) — hecha, sin probar en un Android real**: el celular sincroniza con la PC por
  wifi mientras contesta y pasa solo a la nube cuando se apaga (`conmutador_sync.dart`, `sync_nube_companion.dart`);
  las pantallas cambian al servicio local al instante. Gestión → **Cuenta** (`pantalla_cuenta_companion.dart`): modo
  actual, vincular/desvincular, sincronizar ahora. Suite de las áreas tocadas: 331 verdes. Falta: elegir "PC y
  celular" / "solo celular" al primer arranque (fase 4), la estética nueva (fase 5), y probar la vinculación en un
  Android real.
- **Sync por la nube, fase 4 (elegir modo) — hecha, sin probar en un Android real**: pantalla "¿Cómo vas a usar el
  sistema?" al primer arranque (`pantalla_elegir_modo.dart`, `modo_uso.dart`, `flujo_modo_uso.dart`), "PC y celular" o
  "solo celular", cambiable desde Gestión; las instalaciones viejas conservan el modo que ya tenían. Suite de las áreas
  tocadas: 346 verdes. El rediseño de la companion (P41 #23, 2026-10-02) ya está en `main`; la rama de la sync lo mezcló y las pantallas nuevas (Cuenta, Elegir modo) usan sus piezas (`EncabezadoCompanion`, `BloqueHero`, bloques grises).
- **Camino a la primera versión**: `docs/PRIMERA-VERSION.md` (paso a paso: preparar la PC, beta, instalar, probar la cuenta, publicar).
  `tool/publicar_release.ps1` ahora acepta `-Canal beta` (solo la ven las cuentas de administrador). Nuevo: Configuración → Respaldo →
  "Importar una base" (acepta `.sqlite` o `.gz` de una versión actual o anterior, rechaza las más nuevas o ajenas). `.gitignore` ya no
  ignora `test/capturas/` (`/capturas/`). Nuevo `.github/workflows/tests.yml` (análisis y tests en cada PR; sin probar en GitHub todavía
  y en rojo mientras falte `test/capturas/`). Suite: 1387 verdes + 4 que no compilan por `test/capturas/`.
- **Beta desde GitHub**: `.github/workflows/publicar-beta.yml` (manual) compila en Windows, firma y publica en el canal beta; la beta se descarga en horsepos.com/descargar/ con cuenta de administrador (PR del sitio). Secretos y pasos en `docs/PRIMERA-VERSION.md`. Sin probar en GitHub todavía (hace falta cargar los secretos).
- **Copias sin secretos**: la copia de la nube ya no lleva `mp_access_token` ni `companion_token` (vaciados con `secure_delete` + `VACUUM`; el respaldo local sigue completo). Tras restaurar se vuelven a cargar. Documentado en `DECISIONES.md`, `README.md` y `CLAUDE.md`. Suite: 1377 verdes + 4 que no compilan por `test/capturas/`.

---

## Para retomar (cierre de sesión 2026-09-28) — histórico; lo actual está en `CONTEXTO.md`

- **Instalado en la PC del local** (2026-09-28 17:32): todo lo de abajo
  ("En curso: Lenguaje de diseño"), incluida la segunda tanda de mocks.
  Respaldo previo: `Documents\la_plazoleta.sqlite.backup-pre-mocks2-20260928-173235`.
  El celular no necesitó actualización (última APK: 1.0.0+2097, con los arqueos opcionales).
- **Suite**: 1214 tests verdes; `flutter analyze` limpio salvo los restos de
  Firestore de siempre. Esquema v39, sin migraciones nuevas.
- **Decidido por el dueño hoy**: Carga histórica sigue producto por producto
  (no por totales del día con costo estimado, como proponía el mock).
- **Arqueos del turno opcionales** (2026-09-28, después de la instalación de
  las 17:32): el último arqueo precarga el cierre (efectivo y MP, no la
  lata) y todos se listan en el cierre y en Historial. Ver `DECISIONES.md`.
  Instalado en la PC el 2026-09-28 a las 21:33 (respaldo previo:
  `Documents\la_plazoleta.sqlite.backup-pre-arqueos-20260928-213322`); APK
  1.0.0+2097 publicada para el celular.
- **Historial → Movimientos** (2026-09-28): pestaña nueva con gastos,
  ingresos, pagos y retiros uno por uno. `DECISIONES.md`.
- **Revisión de cierres contra la base real** (2026-09-28,
  `tool/revisar_cierres_test.dart`): lo guardado coincide con recalcularlo,
  y efectivo y Mercado Pago coinciden con una cuenta independiente. Se
  encontró y arregló que la lata se arrastraba con lo esperado en vez de lo
  contado (`TRAMPAS.md`).
- Todo lo de arriba instalado en la PC el 2026-09-28 a las 21:51 (respaldo:
  `Documents/la_plazoleta.sqlite.backup-pre-movimientos-20260928-215140`);
  APK 1.0.0+2098 publicada.
- **Qué sigue**:
  1. Mocks del celular que el dueño todavía no mandó (carrito, historial,
     gestión/configuración, movimiento de caja/arqueo, conteo, login) —
     pedido en `Lenguaje de diseño/PEDIDO-MOCKS-2.md`. Cuando lleguen, van a
     `Lenguaje de diseño/`; aplicar con el mismo criterio (distribución sí,
     reglas/datos inventados no — ver `DECISIONES.md`, "Segunda tanda de
     mocks").
  2. Ventas y los pasos de Cobro* tienen mocks en la carpeta pero el dueño los
     dejó afuera a propósito ("a excepción de la pantalla ventas"): no
     tocarlos sin que lo pida.
  3. Supabase sigue cortado por cuota; la sync celular↔PC va por wifi
     (`DECISIONES.md`, "Sync instantánea por wifi").
- **Leer un mock**: `PYTHONIOENCODING=utf-8 python tool/ver_mock.py "Lenguaje de diseño/X.dc.html" --estilos`.
- **Capturas para revisar a ojo**: `flutter test test/capturas` → PNG en
  `capturas/` (nuevas hoy: `capturas_dialogos_venta_test.dart`,
  `capturas_conteo_stock_test.dart`, `capturas_comparar_precios_test.dart`).
  En esas capturas los diálogos muestran un aro gris grueso: es cómo
  flutter_test dibuja las sombras, en la app es una sombra suave.

---

## Contexto del negocio (por qué el proyecto es como es)

**La Plazoleta** es un almacén de barrio con fiambrería en Km 8 del
corredor Bustillo, San Carlos de Bariloche. Lo atiende **una sola persona**
de lunes a viernes de 10 a 22, con ayuda contratada por hora los fines de
semana. El detalle completo del negocio está en `REGLAS-NEGOCIO.md`.

**El hardware de producción ERA una PC de 2008** (2 núcleos, 4 GB de RAM
DDR2, disco mecánico, Windows 10 LTSC) — el sistema anterior (Next.js +
Tauri) se descartó por lento en esa máquina, no por estar mal hecho. Ese
dato explica casi todas las decisiones técnicas de las fases 1 a 12 (nada
de sombras, nada de animaciones, `ListView.builder` en todo, catálogo
precargado en memoria, etc.), que de otra forma podrían parecer excesivas —
el detalle técnico completo de esas restricciones está en `CLAUDE.md`
("Restricción de hardware") y `DISENO.md`.

**Esa restricción ya no rige**: el local pasó a una máquina nueva, potente,
con monitor de 1920×1080 o más. `CLAUDE.md` y `DISENO.md` **ya están
actualizados** (fase 13, ítem 1 de esta sesión) explicando qué restricción
cae y por qué, y qué se queda por ser criterio de diseño o de negocio, no
por costo de hardware — ver "Hardware" en `CLAUDE.md` y "Restricciones de
hardware" en `DISENO.md`. El código de las fases 1 a 12 sigue en gran parte
escrito para la máquina vieja (código, no documento — se va actualizando a
medida que la fase 13 llega a cada pantalla); lo que cambia de acá en más
son las decisiones de diseño nuevas, detalladas en la fase 13.

## Fases del roadmap

Definición de cada fase en `CLAUDE.md`, sección "Fases".

| Fase | Contenido | Estado |
|---|---|---|
| 1 | Dominio (`lib/domain/`) | **Cerrada** |
| 2 | Base de datos y migraciones | **Cerrada** |
| 3 | Pantalla de venta | **Cerrada** |
| 4 | Cierre de caja | **Cerrada** |
| 5 | Productos | **Cerrada** |
| 6 | Reposición y pedidos | **Cerrada** |
| 7 | Rentabilidad y equilibrio | **Cerrada** |
| 8 | Configuración | **Cerrada** |
| 9 | Historial (+ carga histórica) | **Cerrada** |
| 10 | Impresión y respaldo | **Cerrada** |
| 11 | Sistema de diseño | **En curso** — ver detalle abajo |
| 12 | Cobro por terminal Point (QR/débito) | **Cerrada** |
| 13 | Pulido visual (post-cambio de hardware) | **En curso** — kit de componentes compartidos (`lib/ui/comun/`) construido y aprobado (paso 1), y las cinco pantallas/grupos de gestión del paso 2 ya reescritas con él: Proveedores (absorbe Productos y Stock por proveedor), Cierre, Equilibrio, Historial (+ detalle de día + editor de venta) y Configuración/Carga histórica/Impresión/Respaldo. Detalle abajo. |
| 14 | Remake de estética basado en la companion | **En curso** — Fase 1 del plan (base + navbar superior + 2 pilotos: Dashboard, Proveedores) completa y verificada. Detalle abajo. |

### Fase 11 — detalle de avance

Base del sistema (`lib/ui/tema/tokens.dart`, `tema.dart`, `bloque.dart`,
Inter empaquetada, simulador de resolución de debug) — **lista**. Reglas
completas en `DISENO.md`.

Aplicación a las pantallas:

| Pantalla | Estado |
|---|---|
| Venta (`lib/ui/venta/`) | **Aplicado**, con la corrección post-revisión encima: barra lateral desplegada por default (300px, ver más abajo), búsqueda vuelta a filas de una línea con tres datos (nombre · stock · precio, ya no cards de dos), carrito acotado a `anchoFilaCarrito` (520, no 760), botón "Cobrar" con su color de texto corregido. Incluye el simulador de resolución, actualizado para 1920×1080/1366×768. Es la referencia visual aprobada — no pasó por el kit de `lib/ui/comun/` porque ya cumplía sus mismas reglas, y sigue con su propio manejo de foco/atajos en vez de `PantallaGestion`. **2026-09-16**: dos excepciones puntuales encima, ver "Resuelto: venta 'táctil' y 'con carácter'" más abajo y `DISENO.md` — sensación táctil (radio/ícono/feedback de presión, `tacto_venta.dart`) y color por medio de pago/categoría + filete ámbar del total (`color_categoria.dart`). Las nueve pantallas de gestión NO pasaron por esto todavía — alcance a propósito, solo venta. |
| Proveedores (`lib/ui/proveedores/`) | **Reescrita con el kit** (paso 2) — absorbe Productos y Stock por proveedor (ver "Resuelto: kit de componentes..." abajo). `ListaMaestra` con "Todos"/"Sin proveedor" primero y los proveedores reales después (solo nombre), panel derecho con `FilaMetricas` de cinco cifras + tabla de productos, "Avanzado"/pagar/importar CSV/nuevo producto como `Modal`. Reemplaza a Reposición y a las pantallas viejas de Productos y Stock por proveedor, que ya no existen como tales. |
| Cierre (`lib/ui/cierre/`) | **Reescrita con el kit** — mismos dos patrones que antes (A mientras se cuenta, B con el resumen), ahora con `CampoTexto`/`CampoPlata`/`BotonPrimario`/`FilaDato` (pieza nueva del kit) y el diálogo de reabrir como `Modal`. Sigue sin barra lateral (`AppBar` propio) — decisión a propósito: es un flujo secuencial/bloqueante, no un destino de navegación libre, mismo criterio ahora documentado para cualquier pantalla de "drill-down" (ver Historial). |
| Equilibrio (`lib/ui/equilibrio/`) | **Rehecha con el kit** (ya no la iteración vieja de fase 11) — mismo contenido y reglas de negocio, ahora con `PantallaGestion` (sí lleva barra lateral: es de referencia/lectura, no un flujo bloqueante) y los tres diálogos de fijos como `Modal`. |
| Configuración (`lib/ui/configuracion/`) | **Reescrita con el kit**, las ocho secciones — lista de secciones pasó a `ListaMaestra`, los diálogos de renombrar a `Modal`, los campos de plata a `CampoPlata`. |
| Historial + detalle de día + editor de venta (`lib/ui/historial/`) | **Reescritas con el kit** — la lista de días (`PantallaHistorial`) sí tiene barra lateral (es el destino real del menú); el detalle de un día y el editor de venta, dos niveles de drill-down desde ahí, se quedaron con su `AppBar` propio, mismo criterio que Cierre. |
| Carga histórica, Impresión, Respaldo | **Reescritas con el kit.** Impresión y Respaldo, como antes. Carga histórica **rehecha por completo y reactivada en el menú** (2026-09-07, el dueño: "cargar ventas anteriores... una pantalla igual a la de la venta, pero con la opción de poner la hora y fecha distintas") — ver "Resuelto: carga histórica con carrito real" abajo. |

### Fase 12 — cobro por terminal Point (cerrada)

> 2026-10-02: además del access token local, se puede cobrar por el servidor con el Mercado Pago que el negocio conecta en
> horsepos.com/negocio (PC sin token y celular sin PC). Ver `DECISIONES.md`.

Cobrar una venta por QR o Débito manda la orden a la terminal Point del
sistema (`configuracionTabla.mpTerminalCobroId`) en vez de tocar el monto a
mano — dos posnets físicos separados, uno de cobro manual (ajeno a la app)
y otro "del sistema" que la app maneja vía la Orders API de Mercado Pago.
Las cuatro verificaciones físicas que bloqueaban el código (ver más abajo,
se dejan documentadas) se corrieron y dieron bien; con eso resuelto se
escribió el código completo.

**Construido:**

- Esquema (migración v20→v21): `configuracionTabla.mpTerminalCobroId`,
  `pagos.canal` (`'qr'` | `'debit_card'` | null), tabla
  `OrdenesCobroPendientes` (idempotencia + estado del polling, ver abajo).
- `lib/domain/cobro_posnet.dart` — `clasificarEstadoOrden`, la tabla real de
  estados de MP (`processed` → aprobada, `failed`/`canceled`/`expired` →
  rechazada, todo lo demás → pendiente).
- `lib/data/cobro_posnet.dart` — cliente HTTP (`crearOrdenCobro`,
  `consultarOrden`), mismo patrón que `impresion_posnet.dart`.
- `lib/data/repositorio_cobro.dart` — persiste `externalReference` +
  `idempotencyKey` **antes** del POST (recuperable sin duplicar el cobro si
  la respuesta se pierde), y `ordenesSinResolverDeSesion` (para el aviso en
  Cierre).
- `VentaControlador`: `canalElegido`, `elegirCanalDirecto`,
  `montoParaPosnet`, `iniciarCobroPosnet` / `consultarEstadoPosnet` /
  `confirmarCobroPosnetAprobado` / `resolverCobroPosnetNoAprobado`.
- `lib/ui/venta/dialogo_cobro_posnet.dart` — modal de polling (2s de
  intervalo, 30 intentos = 60s de timeout **contado en intentos, no contra
  un reloj de pared** — `DateTime.now()` no se mueve con el reloj falso de
  los tests de widget, ver el comentario en `_pollear`), cancelable,
  degrada a "Cobrar a mano" en rechazo/timeout/error.
- Botones QR/Débito en `columna_cobro.dart` (`Alt+Q`/`Alt+D`), y en un
  mixto la confirmación del monto en efectivo (`dialogo_mixto.dart`) elige
  también el canal del resto: `Alt+Q` confirma con QR, `Alt+D` con débito,
  `Enter` con QR por default — mismas teclas de siempre, sin campo nuevo.
  Local a ese diálogo vía `CallbackShortcuts`, no pasa por el handler
  global (ver el bug de teclado ya resuelto, abajo).
- Campo `mpTerminalCobroId` en Configuración → Impresión, separado del que
  imprime (pueden ser la misma terminal o no).
- Aviso informativo en Cierre (`_AvisoCobrosSinResolver`) cuando queda
  algún cobro sin confirmar (se agotaron los 60s sin respuesta) — nunca
  bloquea el cierre, la duda se resuelve mirando la cuenta de Mercado Pago.

**Encontrado probando contra el posnet real, ya corregido** (detalle
completo en `TRAMPAS.md`):

- La Orders API exige `config.point.terminal_id` en formato
  `MODELO__SERIAL` (`"NEWLAND_N950__N950NCC503383252"` para la Newland
  N950 de el dueño), no el serial pelado que sí acepta la Terminals API usada
  para imprimir — mismo posnet físico, dos formatos de string distintos
  según el endpoint de MP. `mpTerminalCobroId` ya quedó recargado con el
  valor correcto en la base real.
- **Cancelar por API solo funciona mientras la orden sigue en
  `status=created`** — El dueño: "cuando cancelo el QR no cancela el
  dispositivo". Apenas llega a la terminal (`at_terminal`, casi al
  instante) MP devuelve `409 cannot_cancel_order` y no hay vuelta: cancelar
  pasa a ser una acción física en el posnet. El diálogo igual intenta el
  `POST /v1/orders/{id}/cancel` (la ventana angosta de `created` existe),
  y traduce ese error esperado a "cancelala a mano ahí" en vez de mostrar
  el JSON crudo — la fila queda `'pendiente'` (nunca `'cancelada'`) cuando
  esto pasa, mismo criterio que un timeout.
- De paso, `_mensajeDeError` no entendía la forma real que usa MP para
  estos errores (`{"errors": [{"code", "message"}]}`, no solo
  `{"message": "..."}`) — corregido una vez para las tres funciones de
  `lib/data/cobro_posnet.dart`.

**Alcance decidido (ya construido, se deja como referencia):**

- **Dos botones nuevos en la pantalla de venta: QR y Débito** (`Alt+Q` y
  `Alt+D`), además de Efectivo y Mixto — cuatro botones de medio de pago en
  total, no tres. Cada uno manda su propia orden a la terminal con su
  `config.payment_method.default_type` (`qr` / `debit_card`).
- **En la caja, QR y Débito siguen siendo un solo medio: "Mercado Pago"**
  (el que ya existe). Los dos liquidan al mismo saldo de MP; separarlos
  obligaría a sumar dos líneas para conciliar contra ese único número, y
  rompería el `.getSingle()` de `venta_controlador.dart` y todo lo demás
  que asume un solo medio no efectivo.
- El canal real (`qr` / `debit_card`, tomado de `payment_method.type` en la
  respuesta de la orden) se guarda **por pago**, como dato — el cierre
  puede mostrar "de $X por Mercado Pago: $Y QR, $Z débito" como línea
  informativa, sin que el arqueo dependa de esa separación.
- Cada botón (QR y Débito) tiene que poder degradar a "lo cobré a mano" por
  separado — cuando falla la orden, cuando no hay internet, o por decisión
  de quien cobra — alcanzable por teclado, sin mouse.
- `mpTerminalCobroId` como campo de configuración separado de `mpTerminalId`
  (el que ya existe, para imprimir), aunque hoy señalen la misma terminal
  física.
- Recargo de cigarrillos (Regla 6) aplica a los dos canales — ya está
  resuelto en `REGLAS-NEGOCIO.md`, que nombra "Point" explícitamente.
- Monto al posnet en un mixto: `total − montoEfectivoMixtoCentavos`, sobre
  el total ya compuesto (recargo primero, redondeo después).
- **Canal del resto en un mixto — decidido**: la confirmación del monto en
  efectivo pasa a ser también la elección del canal, sin tecla extra.
  Monto + `Alt+Q` confirma y el resto va por QR; monto + `Alt+D` confirma y
  el resto va por débito; monto + `Enter` confirma por QR (default, para el
  reflejo de hoy). Mismas teclas que ahora, ninguna de más.

**Bug encontrado al diseñar el paso anterior, ya resuelto — nunca fue parte
de la fase 12, era de la app de hoy:** `_manejarTeclaGlobal`
(`pantalla_venta.dart`) seguía activo mientras había un diálogo (o
cualquier pantalla pusheada) encima de la venta, porque
`HardwareKeyboard.instance.addHandler` no sabe nada del `Navigator`. `Alt+Q`
con el diálogo de mixto abierto cambiaba el medio elegido por detrás; una
tecla de accesorio directo con "alta rápida" abierta agregaba un producto
al carrito por detrás del modal. Arreglado con una guardia
(`ModalRoute.of(context)?.isCurrent`) antes de tocar cualquier otra cosa de
esta fase — entra en el build que se prueba en la PC del local. Detalle
completo, con los tres tests que lo prueban, en `TRAMPAS.md`.

**Detalle técnico ya verificado (documentación real de MP, no supuesto):**

- API real: `POST /v1/orders` ("Orders API"). La API que se conocía antes
  (Payment Intent, `POST /point/integration-api/devices/{id}/payment-intents`)
  está en migración/salida según la propia documentación de MP.
- Resultado del pago: **polling** sobre `GET /v1/orders/{id}`, timeout 60s,
  cancelable en cualquier momento. Nunca webhook — necesitaría un servidor
  público que esta app no tiene y `CLAUDE.md` no permite.
- `X-Idempotency-Key` + `external_reference` (aleatorios, no id de venta) se
  persisten a disco **antes** del POST, para poder recuperar una orden cuya
  respuesta se perdió sin duplicar el cobro. No hay reintento automático
  todavía — si el timeout se cumple, la fila queda en `'pendiente'` y
  aparece como aviso en el Cierre de esa sesión (nunca bloquea el cierre).
- La venta se graba recién **después** de que el pago se apruebe. Un
  resultado "no sé si se cobró" (se cortó la conexión a mitad del polling)
  deja un registro visible que aparece en el cierre, no se asume nada.
- El monto va a la API como string en pesos con hasta 2 decimales
  (`"1740.00"`), no en centavos — la conversión es una función propia,
  nunca `formatearARS` (que da `"$1.740"` — sin centavos desde 2026-09-16,
  ver "Plata sin centavos" en `DISENO.md` —, formato distinto y con signo).

**Las cuatro verificaciones físicas que bloquearon el código hasta que se
corrieron (documentación de MP tenía un conflicto sin resolver: una página
decía que el modo API/PDV "solo acepta pagos con tarjeta", la referencia
del propio endpoint de creación de orden ofrecía `qr` como
`payment_method.default_type` válido) — las cuatro dieron bien contra la
Newland N950 del local:**

1. ~~Con la terminal en modo PDV, ¿sigue funcionando el QR cobrado a
   mano?~~ — n/a: El dueño tiene dos posnets físicos separados, uno de cobro
   manual (ajeno a la app) y otro del sistema.
2. Con la terminal en modo PDV, `imprimirEnPosnet` sigue funcionando. Bien.
3. Acepta una orden con `default_type: "debit_card"`. Bien.
4. Acepta una orden con `default_type: "qr"`. Bien — no hizo falta el plan
   B de "QR queda como cobro manual únicamente" que se había previsto acá
   si esta fallaba; la arquitectura de todas formas soporta desde el diseño
   que un canal ande por API y el otro no, sin asumir que los dos funcionan
   igual.

### Fase 13 — pulido visual (post-cambio de hardware, en curso)

**Por qué existe esta fase**: El dueño cambió la PC del local por una máquina
nueva, potente, con monitor de 1920×1080 o más — la restricción de hardware
de 2008 que gobernó toda la fase 11 (`CLAUDE.md`, "Restricción de
hardware") **se levantó**. Esto no vuelve gratuita la app: sigue siendo el
mismo negocio con la misma pantalla de venta de alta densidad, pero libera
presupuesto de repintado para pulir tres cosas que el dueño señaló textuales
como el problema real de la interfaz actual:

> "los formularios no se focalizan al centro"
> "los menús se ven asquerosos"
> "la navegación es PÉSIMA"

Estas tres quejas son el motivo de la fase — no un pedido genérico de "que
se vea mejor". Cualquier trabajo de esta fase tiene que apuntar a resolver
alguna de las tres, no a rehacer lo que ya funciona.

**`DISENO.md` ya está actualizado** con dos principios rectores nuevos que
gobiernan toda esta fase — "evitar fatiga visual" y "tres niveles de
información" — con sus reglas completas. Esta sección de `ESTADO.md` solo
resume el avance; el detalle y el porqué de cada valor vive en `DISENO.md`
y, para las decisiones de negocio, en `DECISIONES.md`.

**Se cayó** (eran restricciones de la PC de 2008, ya no aplican, y `CLAUDE.md`/
`DISENO.md` ya reflejan esto):

- Prohibición de animaciones de transición entre pantallas.
- Prohibición de `BoxShadow` y de `Card`.
- `NoSplash.splashFactory` a nivel de tema (el ripple de Material volvió).
- El simulador de resolución de debug pasó a simular 1920×1080 (objetivo) y
  1366×768 (piso mínimo, ya no objetivo) — `lib/ui/tema/simulador_resolucion.dart`.

**Construido en esta fase, en orden:**

1. **Barra lateral fija** (`lib/ui/navegacion/barra_lateral.dart`), reemplaza
   el `PopupMenuButton` que causaba la queja "la navegación es PÉSIMA".
   Plegable a solo íconos, con toggle explícito (nunca hover) — se recuerda
   entre arranques (`configuracionTabla.barraLateralPlegada`, migración
   v13→v14).
2. **Búsqueda unificada en la pantalla de venta** (`columna_busqueda.dart`):
   los accesos directos y los resultados de búsqueda pasan a ser una sola
   superficie que cambia según haya texto escrito, en vez de dos bloques
   separados (uno vacío casi siempre).
3. **Imprimir sale de acción permanente**: aparece junto al acuse de cobro
   solo mientras hay algo reciente para imprimir (`columna_carrito.dart`),
   no como botón fijo de la barra lateral.
4. **Pasada de "fatiga visual"** (`lib/ui/tema/tokens.dart`, principio nuevo
   en `DISENO.md`): escala tipográfica completa +18-20% (el total de venta
   +33%), altura de botón de grupo 40→48, y los anchos que dependían de eso.
   Aplica a toda pantalla que ya esté en el sistema de diseño.
5. **Pantalla Proveedores reemplaza a Reposición** (`lib/ui/proveedores/`,
   migración v14→v15) — primera aplicación completa del principio "tres
   niveles de información": nivel 1 (lista resumida), nivel 2 (detalle —
   lo que antes era toda la pantalla de Reposición), nivel 3 "Avanzado".
   Feature de dominio nueva: **stock valorizado**
   (`lib/domain/stock_valorizado.dart`), que nunca cuenta un producto sin
   costo/precio cargado como $0. Selector de período
   (`lib/domain/periodo.dart`, `lib/ui/comun/selector_periodo.dart`)
   construido para compartirse con Productos, que todavía no lo usa.
   Fiados y encargues salieron de la pantalla (decisión de el dueño) —
   pendientes de una sección "Pendientes" propia, sin fecha.
6. **Pantalla Cierre recibe el sistema de diseño completo**
   (`lib/ui/cierre/pantalla_cierre.dart`) — Patrón A mientras se cuenta
   (Regla 10, nada más en pantalla), Patrón B una vez revelado el resumen
   (Arqueo a la izquierda, Cigarrillos y Resumen del día a la derecha).
   Primera pantalla en usar los dos patrones de composición en secuencia.
7. **Primera corrección post-revisión** (Venta y Proveedores, después de
   que el dueño y una segunda revisión vieran las primeras capturas y no las
   aprobaran — "se agregó espacio y componentes, pero no jerarquía, y se
   perdieron cosas que ya funcionaban"). Detalle completo y el porqué de
   cada una en `DECISIONES.md`, sección "Corrección post-revisión de fase
   13":
   - Barra lateral: **desplegada por default** (revertido — arrancaba
     plegada), **ancho subido a 300** (a 220 el encabezado desbordaba con
     la escala tipográfica nueva, bug real sin test que lo agarrara porque
     el layout desplegado casi nunca se renderizaba), y **ahora también en
     Proveedores** (`EnvolturaConBarraLateral`, `navegacion_gestion.dart` —
     mecanismo genérico para que cualquier pantalla de gestión la reciba).
     Migración v15→v16 corrige el valor ya grabado en instalaciones
     existentes (cambiar el default de Dart no alcanza para una fila que
     ya existe).
   - Búsqueda de venta: **vuelve a filas de una línea** (nombre · stock ·
     precio — tres datos, no dos), sin marcar stock bajo en rojo (esa señal
     vive solo en el carrito, Regla 8 original). "Varios" se distingue con
     guiones en vez de celdas vacías.
   - Carrito: ancho máximo propio (`Medidas.anchoFilaCarrito`, 520 — ya no
     comparte `anchoMaximoContenido` con los formularios).
   - Botón "Cobrar": bug real de tema corregido (`TRAMPAS.md`) — el texto
     se veía gris apagado sobre ámbar en vez de `acentoTexto`.
   - `ColumnaCobro`: sacado un `Spacer()` que dejaba ~700px muertos entre
     los medios de pago y "Cobrar" (`TRAMPAS.md`).
   - Proveedores: cuatro cifras en el nivel 1 (stock a precio, costo,
     vendido, ganancia), medio de pago mudado a "Avanzado", estado arriba
     de todo, panel de detalle con ancho máximo propio — **todo esto
     quedó superado por el ítem 8** (El dueño no aprobó esta versión
     tampoco, la reencauzó con un dibujo a mano).
8. **Segunda corrección post-revisión** (solo Proveedores — El dueño dibujó a
   mano el layout que quiere: "tres paneles, la misma forma que la
   pantalla de venta"). Detalle completo en `DECISIONES.md`, sección
   "Segunda corrección post-revisión de fase 13":
   - **Nivel 1 vuelve a ser solo nombre** (`Medidas.anchoListaMaestra`
     bajó de 580 a 360) — las cuatro cifras del ítem 7 eran, textual,
     "exactamente lo contrario" de lo que el principio de tres niveles
     pide: son del proveedor ELEGIDO, no de todos a la vez.
   - **Nivel 2 pasa a ser dos bloques apilados, sin campos ni botones**:
     arriba, un resumen de CINCO cifras (Stock, Costo, Venta, Ganancia,
     Separado — "es para mirar"); abajo, una tabla de productos del
     proveedor **nueva** (nombre, costo, venta, margen %) — "el corazón
     de la pantalla" (El dueño). Reusa `gananciaBpDesdeCostoYPrecio`
     (`lib/domain/ganancia.dart`, la misma fórmula de "Margen en vivo" de
     Productos) — `lib/data/repositorio_reposicion.dart`,
     `productosDeProveedor`.
   - **"Avanzado" absorbe todo lo accionable**: colchón, medio de pago,
     código, días de pedido/entrega, activar/desactivar, y las acciones
     de separar y pagar (con "costo real pendiente"/"cuánto separar" como
     contexto). El diálogo es reactivo al controlador
     (`ListenableBuilder`), no una foto fija — separar o pagar sin cerrar
     el diálogo actualiza los números ahí mismo.

9. **Kit de componentes compartidos** (`lib/ui/comun/`, paso 1 — El dueño pausó
   el rediseño pantalla por pantalla acá: "el problema no es la estética, es
   que no hay componentes"). Diez piezas, ninguna recibe color/tamaño/padding
   por parámetro, todas salen de `tokens.dart`: `PantallaGestion`
   (armazón: barra lateral + `EncabezadoPantalla` + contenido),
   `Metrica`/`FilaMetricas`, `FilaLista`, `ListaMaestra`, `Modal` (el único
   diálogo de la app, cierra con Esc vía `CallbackShortcuts`),
   `CampoTexto`/`CampoPlata` (etiqueta FIJA arriba, nunca la flotante de
   Material), `BotonPrimario`/`BotonSecundario`, `EstadoVacio`. Aprobado por
   El dueño tras una captura de muestra y cinco correcciones (campos que no se
   distinguían de un texto de lectura, `CampoPlata` alineada a la derecha,
   `FilaLista` sin truncar en `ListaMaestra`, `BotonSecundario` sin borde
   visible en claro, velo del `Modal` parejo entre temas).
10. **`FilaDato` agregada al kit durante el paso 2** (`lib/ui/comun/fila_dato.dart`)
    — etiqueta izquierda + valor tabular a la derecha, la unidad que
    Proveedores (nivel 2, antes del kit) y Cierre repetían cada uno por su
    cuenta. Sin ancho fijo a propósito (cada fila es su propia `Row` de
    ancho completo) — un ancho fijo partía en dos líneas una cifra grande.
11. **Paso 2 — reescribir cada pantalla con el kit, completo.** Orden fijado
    por el dueño: Proveedores → Cierre → Equilibrio → Historial → Configuración/
    Carga histórica/Impresión/Respaldo. Detalle de qué absorbió qué y qué
    quedó sin `PantallaGestion` (Cierre, y el detalle de día/editor de venta
    de Historial — flujos de drill-down, no destinos de menú) en la tabla de
    fase 11 más arriba. Un solo bug de layout recurrente en todo el paso:
    `CampoTexto`/`CampoPlata`/un `TextFormField` crudo necesitan un `Bloque`
    alrededor para que su fondo (`colores.fondo`) contraste — sin él, quedan
    invisibles contra el canvas. Otro, puntual: un `ListTile`/`Switch`/
    `IconButton` con ink dentro de un `Bloque` necesita su propio
    `Material(type: MaterialType.transparency)` — el `Container` con color
    de `Bloque` tapa el ink y Flutter tira una excepción real al tocar (no
    solo visual, hacía fallar tests).

**"Los formularios no se focalizan al centro" — resuelto en todas las
pantallas de gestión** (Patrón A, `Center` + `ConstrainedBox(maxWidth:
Medidas.anchoMaximoContenido)`, ya universal tras el paso 2).

- **Tema que cambia solo según la hora del día** — sin construir. Falta
  decidir qué rango horario es cada tema, si el switch manual
  (`temaOscuro`) desaparece o queda como override, y qué pasa si la PC
  tiene la hora mal puesta. Única pregunta de fase 13 que sigue abierta.

### Fase 14 — remake de estética basado en la companion (en curso)

El dueño, 2026-09-19: "quiero que en desktop remakeemos toda la estética
basándonos en la estética actual del celular... basémonos al completo en
el apk", más una navbar superior en vez de la barra lateral. Plan
aprobado, ejecución por fases (ver el plan en curso para el detalle
completo de cada una) — **la pantalla de Venta no cambia de layout**
(regla de negocio, 3 columnas sin scroll), solo actualiza tokens/colores.

**Fase 1 — base + 2 pilotos: completa, verificada (`flutter analyze` +
`flutter test`, 1073 tests, todo verde).**

- Paleta nueva (`lib/ui/tema/colores_escritorio.dart`) y familia de
  acentos (`lib/ui/tema/acentos.dart`, `AcentosPlazoleta`), portadas con
  fidelidad completa de `colores_companion.dart`/`AcentosCompanion`.
  `lib/ui/tema/tema.dart` reescrito para usarlas, más radios nuevos
  (`radioSuperficieEscritorio`=22, `radioControlEscritorio`=18) y escala
  tipográfica realineada con la de la companion (`tokens.dart`,
  `TamanioTexto`).
- `Superficie` (`lib/ui/tema/superficie.dart`) — reemplazo de `Bloque`,
  con modos `relleno`/`degrade`/`resplandor` que `Bloque` no tenía.
  `Bloque` sigue vivo mientras dure el rollout (lo sigue usando el código
  no migrado todavía).
- Kit nuevo portado de la companion: `resplandor.dart`, `presionable.dart`
  (con hover, señal de mouse que la companion no tiene), `chip_icono.dart`,
  `chip_seleccionable.dart`, `esqueleto.dart` (skeletons — el escritorio no
  tenía, solo spinners).
- Navbar superior (`lib/ui/navegacion/navbar_superior.dart`,
  `envoltura_con_navbar_superior.dart`) — reemplaza `BarraLateral`/
  `EnvolturaConBarraLateral` (esta última, sin más llamadores, se borró).
  Look de vidrio (blur+borde+sombra), compacta/expandida con el mismo
  campo de siempre (`barraLateralPlegada`, reinterpretado, sin migración).
  `armazon_gestion.dart` (`PantallaGestion`) y `navegacion_gestion.dart`
  actualizados; la lógica de navegación (`popUntil`+push) no cambió.
- Kit `lib/ui/comun/` retematizado: `Modal` (ahora vidrio, diálogo
  centrado — puerto de `mostrarHojaVidrio` adaptado, no hoja inferior),
  `EstadoVacio`/`EstadoError` (ícono en círculo, botón sólido en error),
  `Metrica`/`FilaMetricas`/`ListaMaestra` (`Bloque`→`Superficie`),
  `FilaLista` (pasa a `Presionable`), `SelectorPeriodo` (radio nuevo). Dos
  piezas nuevas opt-in: `FilaDatoAccion` (análogo de `FilaDatoCompanion`)
  y `BotonDestacado` (CTA con degradé).
- **Dashboard**: reskin completo — "Ventas de hoy" pasa a tratamiento
  hero (`Superficie(degrade: acentos.gradienteAcento, resplandor: true)`,
  mismo que la tarjeta homónima de `pantalla_inicio_companion.dart`), el
  resto de las tarjetas a `Superficie`, botón "Ir a Venta" a
  `BotonDestacado`.
- **Proveedores**: reskin completo — lista/detalle/tabla de productos a
  `Superficie`, radios de los diálogos (`dialogo_avanzado_proveedor.dart`,
  `dialogo_edicion_masiva.dart`, `dialogo_editar_producto.dart`,
  `dialogo_nuevo_proveedor.dart`) al radio nuevo. Validó el patrón de tres
  paneles que comparten después Equilibrio/Reportes/Comparar precios/Stock
  por proveedor.
- `DISENO.md` reescrito para el alcance de esta fase (secciones marcadas
  "remake 2026-09-19").
- **Gotcha real encontrado**: el `Container` decorado nuevo de `Modal`
  quedaba entre el `Material` del `Dialog` y cualquier `ListTile` de
  `contenido` (ej. el diálogo de pago de un fijo, Equilibrio) — Flutter
  detecta que el ink del `ListTile` quedaría tapado y tira un assert real
  en tests. Mismo problema ya documentado más arriba para `Bloque` +
  `IconButton`: cualquier `Container` decorado que envuelva contenido con
  `ListTile`/`InkWell` necesita su propio `Material(type:
  MaterialType.transparency)` inmediato — se agregó dentro de `Modal`.

**Fases 2-5 — resto de pantallas + Venta: completas el mismo día, no en
fases separadas.** El dueño, tras ver el primer build de Fase 1: "DIJE QUE LA
PANTALLA DE VENTAS SE ADAPTE TAMBIEN" — pidió no esperar al orden
original del plan. Con la navbar ya heredada automáticamente por
`PantallaGestion`, lo que faltaba en el resto de las pantallas era
mecánico (`Bloque`→`Superficie`, `Radios.control`→`radioControlEscritorio`,
`Bento.*`→`Espaciado.*`): Carga histórica, Cierre, Configuración,
Equilibrio, Historial (+ detalle de día + editor de venta), Impresión,
Reportes (+ `tab_historial_ventas.dart`), Respaldo — Comparar precios y
Stock por proveedor ya no tenían ninguna referencia vieja (compuestos
enteramente del kit ya migrado en Fase 1).

**Venta** (la más delicada, hecha con cuidado aparte):
- Chrome: `BarraLateral` (con su pie de "Cambiar de turno"/"Cerrar caja")
  → `NavbarSuperior` armada a mano, igual que antes — `_AccionesPie` pasa
  de columna vertical a fila de dos íconos con tooltip en el slot `accion`.
- **Bug real encontrado y arreglado**: mover el nav de costado (comía
  ancho) a arriba (come ALTO) hizo que `ColumnaCobro` desbordara de
  verdad en 1366×768 — esa columna ya vivía al límite de espacio vertical
  desde antes (documentado en `tacto_venta.dart`). Arreglado con dos
  medidas: la navbar ahora tiene alto variable (52 compacta/68 expandida,
  antes fijo en 68 siempre) para gastar menos cuando no hace falta el
  texto, y `ColumnaCobro` se envolvió en `SingleChildScrollView` como red
  de seguridad (la regla de "carrito sin scroll" es sobre `ColumnaCarrito`,
  no sobre esta columna — en el caso normal no hace falta scrollear, esto
  cubre el caso límite sin tirar un overflow real).
- Colores reconciliados: `ColorMedioPago` (`color_categoria.dart`) dejó su
  paleta propia — Efectivo usa `colores.acento`, QR/Débito/Mixto usan
  `AcentosPlazoleta.{qr,debito,mixto}` (mismo criterio que la companion:
  "Efectivo comparte el acento principal"). El total pasa de filete ámbar
  a tratamiento "hero" completo (`Superficie(degrade: acentos.gradienteDinero,
  resplandor: true)`).
- `TactoVenta.radio` reanclado entre los radios nuevos (20, antes 12 entre
  los viejos) — `SuperficieTactil`/`EscalaAlPresionar` se quedan como
  mecanismo propio de Venta (ya tenían su propio ajuste fino, no había
  necesidad real de unificar con `Presionable`).
- `columna_busqueda.dart`/`columna_carrito.dart` (los dos bloques que
  faltaban) también pasaron a `Superficie`.

**Limpieza de huérfanos, sobre la marcha** (no se esperó a la Fase 6 para
esto puntual): `lib/ui/navegacion/envoltura_con_barra_lateral.dart` y
`lib/ui/navegacion/barra_lateral.dart` se borraron apenas se confirmó
`grep` que ya no tenían ningún llamador (ni en `lib/`, ni en `test/`) —
dejarlos ahí habría sido código muerto, no "código en rollout".

**Estado real**: toda la app (las 15 pantallas de gestión + Venta) están
en el sistema nuevo. `flutter analyze` limpio, `flutter test` completo en
verde (1073 tests) después de cada tanda. Solo queda una vitrina de test
(`test/capturas/pantalla_muestra_kit.dart`) que sigue usando `Bloque` a
propósito, para mostrar el kit viejo en las capturas de comparación.

**Pendiente real**: chequeo visual de el dueño con la app corriendo
(`flutter run -d windows`, relanzada varias veces durante la sesión con
cada tanda de cambios) — confirmado hasta el momento: la navbar de
Dashboard/Proveedores aprobada tras el primer ajuste (autoajustada,
centrada, ícono-arriba/etiqueta-abajo); Venta con la navbar nueva y los
colores reconciliados, pendiente de un vistazo final. Fase 6 (borrar
`Bloque`/tokens viejos deprecados, y la vitrina del kit) sigue sin
empezar — recién tiene sentido una vez que el dueño dé el visto bueno visual
final, no antes.

## En curso: "Lenguaje de diseño" (2026-09-26/28)

Mocks de el dueño en `Lenguaje de diseño/` aplicados a toda la app (qué se
decidió: `DECISIONES.md`; tokens y piezas: `DISENO.md`, aviso de arriba).

- **Hecho, escritorio**:
  - Base visual: Figtree, paleta nueva, tarjetas planas y botones pastilla.
  - Inicio: tablero del día y vista "Este mes".
  - Separaciones.
  - Proveedores: lista y detalle, stock bajo y stock mínimo editable.
  - Historial: ventas y cierres, con lista y detalle.
  - Venta: botones de cobro con el color de su medio.
  - Modal de producto: precio rápido y ganancia en vivo.
  - Modales opacos, con subtítulo y cruz para cerrar.
  - Segunda tanda: Cierre de caja, Detalle del día, Editor de venta,
    diálogos de Venta (Mixto, Varios, Movimiento rápido, Cambiar cantidad),
    Conteo de stock, Carga histórica, Impresión, Respaldo, Comparar precios,
    diálogos de Proveedores y de Separaciones.
- **Hecho, celular**:
  - Inicio con el tablero del día.
  - Separaciones: pantalla nueva, se abre desde "Falta separar".
  - Productos: arranca por la lista de proveedores y muestra tarjetas de producto.
  - Hoja de editar producto: ganancia en vivo y precio rápido.
- **Sin cambiar a propósito**: la navbar de abajo del celular (el mock usa
  un menú desde el título).
- **Celular**: el mock completo (canvas "Mocks Nodo Sur") ya llegó y se aplicó casi entero
  (2026-10-02, ver `DECISIONES.md`, "Companion: mock completo del celular"). Aplicado
  entero, incluidos Conteo de stock, Configuración y el emparejamiento. Esquema sin cambios, sigue en v39.
- **Pregunta abierta**: Carga histórica por totales del día con costo
  estimado (lo que proponía el mock) o, como ahora, producto por producto.

## Métricas

- **Tests**: 1853, todos verdes (`flutter test`, 2026-10-03). Antes: 1214, todos verdes (`flutter test`, 2026-09-28) — la suite completa a veces
  muestra 1-3 fallos que cambian de nombre entre corridas, todos acotados a
  `test/ui/venta/` (hit-test warnings de Flutter contra widgets fuera de
  pantalla); en aislamiento esos mismos archivos pasan siempre. Flakiness
  preexistente del test runner, no relacionada con ningún cambio de código —
  queda pendiente de investigar si vuelve a aparecer.
- **`flutter analyze`**: limpio en `lib/` y `test/`, salvo restos de Firestore sin el paquete (`lib/data/transporte_firestore.dart`, `lib/firebase_*.dart`, `integration_test/sincronizacion_firestore_test.dart`), que vienen de antes.
- **`schemaVersion`** de la base: **47** al 2026-10-03 (`lib/data/database.dart`; las v40–v47 están comentadas en `onUpgrade`). v39
  saca del menú Reportes, Equilibrio, Respaldo, Impresión y Comparar precios
  (ver "Menú de secciones rehecho..." en `DECISIONES.md`). v38
  guarda la separación del día por proveedor (para destildar en
  Separaciones). v37
  completa el costo de ventas sin costo con el costo ya cargado del
  producto (nunca pisa uno guardado, nunca copia un $0). v36
  agrega la sección de menú `separaciones`. v35
  agrega `proveedores.separado_mp_centavos` (lo separado dividido entre
  cajón y MP, ver `DECISIONES.md`); las dos columnas de v34 quedan sin uso. v34
  agrega `sesiones_de_caja.excedente_mp_cigarrillos_generado_centavos` y
  `movimientos_de_caja.uso_excedente_cigarrillos` (excedente de MP por
  cigarrillos, ver `DECISIONES.md`). Las v25–v33 están documentadas en sus
  secciones de más abajo y en los comentarios de `onUpgrade`. v24
  corrige `recargoSueltoCentavos` de 0 a 5000 ($50), Regla 6 (El dueño,
  2026-09-10: "los puchos sueltos también deben tener recargo por MP, sin
  eso los cálculos dan mal" — ver "Resuelto: recargo de cigarrillos
  sueltos" abajo). v23
  agrega índices (`CREATE INDEX IF NOT EXISTS`, no requiere build_runner)
  sobre las columnas que reciben WHERE/JOIN en la ruta caliente de
  reposición/reportes/cierre (`lineas_de_venta.proveedor_id_foto`/`venta_id`,
  `ventas.sesion_caja_id`/`fecha`, `movimientos_de_caja.sesion_caja_id`/
  `caja_id`, `pagos.venta_id`) — ver "Resuelto: optimización de rendimiento
  en POS/stock/caja" abajo. v22 agrega `configuracionTabla.companionToken`
  (spike companion app Android, ver "Resuelto: companion app Android"
  abajo). v21 agrega
  `configuracionTabla.mpTerminalCobroId`, `pagos.canal` y la tabla
  `OrdenesCobroPendientes` (fase 12, cobro por terminal Point). Desde
  la v13: v14 agrega `barraLateralPlegada`; v15 agrega
  `proveedores.ultimoPagoFecha` y `configuracionTabla.periodoResumen`, y
  renombra la sección de menú `reposicion` a `proveedores` (fase 13,
  pantalla Proveedores); v16 corrige `barraLateralPlegada` a `false` en
  instalaciones existentes (corrección post-revisión — el default de
  esquema cambió, pero una fila ya grabada necesita un paso explícito);
  v17 agrega `proveedores.gananciaRevisadaFecha` (Regla 13, retiro diario
  de ganancias — corte independiente de `corteReposicionFecha`, ver
  "Resuelto: retiro de ganancias diario" más abajo); v18 agrega
  `productos.stockMinimo`/`stockMinimoGramos` (umbral de aviso de stock,
  arranca en 0/"sin alerta" en filas existentes); v19 borra las filas
  `productos`/`stock_proveedor` de `secciones_menu` (paso 2, Proveedores
  las absorbió — ver "Resuelto: kit de componentes..." más abajo); v20
  agrega la sección de menú `reportes` para la pantalla nueva que
  reemplaza a "revisar ganancias" (ver "Resuelto: retiro de ganancias
  diario (Regla 13) → pantalla 'Reportes'" más abajo).
  Versiones anteriores (Mercado Pago arqueado como caja, switch de fijos
  pendientes en el retiro, "Stock por proveedor", catálogo real de 15
  proveedores, separación de fondos, arqueo de la lata, Impresión apagada
  por default) siguen en `DECISIONES.md`.
- **Capturas de referencia** (`capturas/*.png`, regenerables con
  `flutter test test/capturas`): una pareja claro/oscuro (a veces más
  estados) por cada pantalla ya pasada por el kit — `venta`, `proveedores`
  (+ vista "Todos" + modal de editar producto), `cierre` (conteo/revisado/
  cerrado), `equilibrio`, `historial` (+ detalle de día + editor de venta),
  `configuracion` (+ sección Usuarios), `impresion`, `respaldo`,
  `carga-historica`, `reportes`.
  No comparan contra un archivo de referencia (no son golden tests) —
  existen para que el dueño las mire antes de aprobar un cambio visual grande,
  sin tener que levantar la app contra una base real.
- Base real de el dueño: `C:\Users\el dueño\Documents\la_plazoleta.sqlite`
  (fuera del repo, no versionada).
- Credenciales de la terminal Point de Mercado Pago ya cargadas en esa base
  real (`mp_access_token`, `mp_terminal_id`) — no están en el repo ni en
  ningún documento, por diseño.

## Resuelto: venta "táctil" y "con carácter" (2026-09-16)

El dueño: *"quiero que la interfaz de la app desktop sea llamativa al estilo de
que parezca táctil, al menos la parte de ventas"*, y después *"quiero que
esté pensada visualmente para estar 24/7, dejemos el monocromo y démosle
vida, lo mismo para el layout"*. Dos pasadas sobre venta, mismo alcance
acotado que el resto de la fase 13 (una pantalla por vez, `CLAUDE.md`):

1. **Sensación táctil sin cambiar de entrada** (mouse/teclado siguen
   siendo la forma real de operar): `lib/ui/venta/tacto_venta.dart` —
   radio de control más redondeado, íconos más grandes, y
   `SuperficieTactil`/`EscalaAlPresionar` (achique breve al presionar,
   sumado al ripple que ya existía). La altura de los controles NO subió —
   overflow real en la columna de cobro al probarlo (siete controles a esa
   altura en un piso mínimo de 1366×768 sin margen de sobra).
2. **"Bento con carácter"**, elegido por el dueño sobre un mockup de tres
   direcciones (armado aparte, fuera del repo): `lib/ui/venta/color_categoria.dart`
   — los cuatro medios de pago pasan a tener color propio (verde/violeta/
   azul/coral) en vez de compartir el ámbar; cada categoría de producto
   suma un punto de color en el carrito y en la búsqueda (paleta fija de 8
   tonos recorrida por posición del id, cero mantenimiento); el bloque del
   total suma un filete ámbar arriba. `Bloque` (`lib/ui/tema/bloque.dart`)
   ganó un parámetro opcional `colorFilete` (nulo en el resto de la app) para
   esto último.

Las dos son excepciones puntuales, solo en los widgets propios de venta —
`tokens.dart` (`Radios.control`, `Medidas.alturaControl`, la regla de "un
acento, tres usos exactos") no se tocó. Detalle completo y el porqué de
cada valor en `DISENO.md`. Extender cualquiera de las dos al resto de las
pantallas de gestión es un paso aparte, no implícito acá.

## Resuelto: venta "full responsive" + foco selectivo, y edición masiva de productos (2026-09-16)

Misma sesión que "venta táctil/con carácter" arriba, tres pedidos más de el dueño:

1. **Columnas de venta fluidas, no a saltos**: `_anchoColumnaFluido`
   (`pantalla_venta.dart`) interpola el ancho de búsqueda/cobro entre 960px
   ("mitad de pantalla") y `Medidas.anchoUmbralCompacto` (1200) en vez de
   saltar de golpe a los 1200px — de 1200 para arriba (1280 del viewport
   fijo de los tests, 1366 piso mínimo, 1920 diseño) el ancho se mantiene
   igual que antes, sin cambios: una rampa que siguiera hasta 1920 angostaba
   columnas ya aprobadas (overflow real de texto en los medios de pago,
   probado y revertido).
2. **Foco selectivo, no "siempre"**: agregar un producto (tap/Alt+tecla/
   Enter) y cobrar siguen devolviendo el foco al campo único — abrir un
   diálogo secundario (Mixto, Varios, gasto/ingreso rápido, arqueo
   intermedio, editar un acceso directo, imprimir) ya no. Detalle completo
   en `DISENO.md`, "Foco: solo donde hace falta".
3. **Alta rápida sale de la pantalla de venta**: un código/nombre sin
   coincidencias muestra "Sin coincidencias" y nada más — dar de alta un
   producto nuevo es siempre desde Proveedores. `dialogo_alta_rapida.dart`
   se borró (sin más llamadores); `VentaControlador.mostrarAltaRapida` se
   renombró a `sinCoincidencias`.
4. **Edición masiva de productos, en Proveedores** ("maximizá lo que se
   puede hacer con el ajuste masivo"): casilleros en la tabla de productos
   del panel derecho (`FilaLista.leading`, nuevo slot genérico del kit),
   `DialogoEdicionMasiva` (`lib/ui/proveedores/dialogo_edicion_masiva.dart`)
   con seis acciones — precio de venta, costo, categoría, proveedor,
   activar, desactivar — sobre todos los productos marcados a la vez.
   Precio/costo admiten valor nuevo fijo, sumar/restar monto o sumar/restar
   %, redondeado siempre al peso entero (`lib/domain/edicion_masiva_precios.dart`,
   `aplicarAjustePrecio`). Todo pasa producto por producto por
   `actualizarProducto`/`cambiarActivo` (Regla 3, `lib/data/repositorio_productos.dart`:
   `ajustarMontoEnLote`, `asignarCategoriaEnLote`, `asignarProveedorEnLote`,
   `cambiarActivoEnLote`), así que el historial de precios queda idéntico a
   editar uno por uno.

## Resuelto: plata sin centavos en toda la app (2026-09-16)

El dueño: *"dejemos de mostrar centavos"*. `formatearARS` (`lib/domain/dinero.dart`)
redondea al peso más cercano y ya no imprime la parte decimal — cambio en un
solo lugar (Regla 3), automáticamente en toda la app porque es el único
punto de conversión centavos → texto. Solo la capa de texto: `precioCentavos`
sigue siendo centavos reales en la base, `parsearARS` sigue aceptando
centavos al tipear un precio, `formatearParaMercadoPago` (Fase 12) no se
tocó. Detalle completo en `DISENO.md`, "Plata sin centavos". Actualizó
strings esperados en ~18 tests de siete pantallas distintas (`ticket_test.dart`,
carga histórica, cierre, editor de venta, equilibrio, apertura de caja,
reportes, venta) — ningún cambio de comportamiento, solo el texto que
`formatearARS` ya producía distinto.

## Descartado (decisión de el dueño, no pendiente)

- **El descuento de Cliente Frecuente (Regla 17) no se va a hacer.** El dueño decidió que
  no hace falta. Quedan sin usar, a propósito, las dos columnas de esquema que
  ya existían para esto y que nadie llegó a leer ni escribir:
  `clientes.descuentoBp` (`lib/data/tables/catalogo.dart`) y
  `ventas.descuentoCentavos` (`lib/data/tables/ventas.dart`) — no se borran
  porque hacerlo es una migración sobre datos reales para ganar nada.

## Resuelto: retiro de ganancias diario (Regla 13) → pantalla "Reportes"

Cambio de reglas de negocio decidido por el dueño: el retiro semanal
desaparece por completo (`lib/domain/retiro.dart` y la cascada de
`repositorio_equilibrio.dart`, borrados) y se reemplaza por una revisión
por proveedor de vendido/costo real/ganancia, con el colchón dejando de
ser un monto configurable a mano — es ganancia real retenida, que solo se
consume cuando se separa para un pedido (`separarProveedor`). Detalle
completo del razonamiento original, incluidas las tres decisiones de
alcance resueltas sin volver a preguntar, en `DECISIONES.md` ("Regla 13:
el retiro de ganancia es diario...").

**Simplificado el 2026-09-05** (El dueño: "necesito que solo diga cuánto
separar... para ahorrarme trabajo y sobre todo tiempo"): los dos campos de
retiro manual y el dato de fijos pendientes salieron de la pantalla —
queda un número y un botón de un solo toque por corte pendiente.

**El retiro real vuelve el 2026-09-06** (El dueño: "necesito poder retirar
ganancia real de nuevo... pero todo simple: que me calcule las ganancias
de manera automática en base al costo... de qué medio debe calcularse
desde cómo se vendió, o en su defecto editable") — sobre la ganancia sin
revisar, dos acciones en vez de una: "Retener como colchón" (la que ya
había, retiene el 100%, sin movimiento de caja) y "Retirar ganancia"
(`lib/ui/reportes/dialogo_retirar_ganancia.dart`), que abre un diálogo con
dos montos prellenados — no en blanco — según la proporción real en que se
cobraron las ventas que generaron esa ganancia
(`gananciaPorMedioDesde`/`prorratearGananciaPorMedio`, nuevas en
`repositorio_reposicion.dart`/`lib/domain/reposicion.dart`): una venta
100% efectivo manda su parte entera a efectivo, un mixto se reparte a
prorrata de lo cobrado en cada medio. Los dos montos quedan editables
(para el caso sin atribución exacta — mixto de varios productos, ver
"Otros pendientes sueltos" más abajo — o porque el dueño decide otra cosa);
lo que no se retira de los dos campos queda como colchón automáticamente,
sin una acción aparte. Bug real encontrado escribiendo los tests: una
venta sin ningún `Pago` registrado (no debería pasar, pero un día cargado
a mano podría no tenerlos) dividía por cero al calcular la proporción —
`gananciaPorMedioDesde` ahora la salta en vez de crashear.

**Reemplazado por completo el mismo día, 2026-09-06** (El dueño: "en lugar de
revisar ganancias, un apartado de reportes para poder ver detalladamente
todo") — la pantalla dejó de abrirse sola al abrir caja (esa interrupción
forzada era exactamente lo que el dueño pidió sacar: ver también "Apertura y
cierre ya no bloquean el arranque" más arriba) y pasó a ser **"Reportes"**,
sección nueva y permanente de la barra lateral (`lib/ui/reportes/`,
`secciones_menu` v19→v20). A diferencia de la pantalla vieja (que solo
listaba proveedores con algo pendiente, para no interrumpir con ruido en
plena apertura), Reportes muestra los 15 proveedores activos siempre —
"ver detalladamente todo" incluye los que están en cero.

Primer diseño (una tarjeta larga por proveedor, todas apiladas) rechazado
por el dueño en el momento — "no me gusta, recordá que tiene que ser sin
scroll" (mismo principio que la pantalla de venta: nada de la información
principal puede quedar fuera de la pantalla). Diseño final, maestro-detalle
como Proveedores: lista de solo nombres a la izquierda (`ListaMaestra`,
los 15 entran sin scrollear), detalle completo del proveedor elegido a la
derecha (arranca con el primero ya seleccionado, el panel nunca queda
vacío) — reposición (vendido, costo real, pendiente, colchón, sugerido a
separar, separado + fecha, "Separar todo") en un bloque, ganancia (ganancia
sin revisar, "Retener como colchón"/"Retirar ganancia") en el bloque de al
lado. El acceso voluntario que existía desde Proveedores ("Revisar
ganancias") se sacó — quedaba redundante con la sección nueva del menú.
Capturas: `reportes_oscuro.png`/`reportes_claro.png`.

## Resuelto: cambio de turno (Regla 18)

Lo que antes era "no hay selector de usuario independiente de la sesión"
está resuelto, pero no con una tabla de turnos: **un turno ES una sesión de
caja completa** (El dueño, sesión del 31/08/2026 — su planilla de papel tiene
una hoja por persona, no una por día). El que se va cuenta y cierra su hoja
entera (arqueo, separación de cigarrillos, lo que queda en el cajón); el
que entra abre una hoja nueva, precargada con lo que dejó el anterior pero
editable. `sesionCerradaAnterior` encadenando por `id` de inserción ya hacía
exactamente esto — no era un bug, `TRAMPAS.md` lo documenta ahora
correctamente. `pantalla_venta.dart` puede abrir una hoja nueva sin
reiniciar la app, y el Historial distingue turnos del mismo día por hora y
empleado. Ver `DECISIONES.md` para el detalle.

**2026-09-12, botón "Cambiar de turno" + cierre pasado a modal** (El dueño:
"la pantalla de cierre de caja es un bodrio total... una pantalla entera
pierde mucha info"): `PantallaCierre` dejó de ser un `Scaffold` con
`Navigator.push` a pantalla completa — ahora se abre con `mostrarModal`
(`lib/ui/comun/modal.dart`), el mismo diálogo que usa el resto de la app.
El contenido de las tres fases no cambió, solo dónde vive: los botones de
cada fase pasan al pie fijo del `Modal` (ya no se scrollean con el resto), y
la fase "revisado" usa `Medidas.anchoModalCierre` (960, nuevo) porque su
layout de dos columnas no entra en el ancho de formulario de siempre (760).
`Modal` ganó dos parámetros opcionales para esto (`ancho`, `alturaMaxima`)
sin tocar ningún llamador existente — el default sigue siendo el de
siempre.

Además, la barra lateral de Venta ahora tiene dos botones separados:
"Cerrar caja" (fin del día, termina en el bloqueo de siempre) y "Cambiar de
turno" (mismo arqueo obligatorio, pero pensado para cuando viene ayuda a
mitad de sesión — El dueño: "a veces sí me vienen a ayudar"). Este último
encadena directo del cierre a `DialogoAperturaCaja` para el que entra, en
vez de dejar la pantalla en "Caja cerrada" esperando un segundo clic.

**2026-09-12, arqueo obligatorio cada 2hs** (El dueño: "1 es como el cierre, 2
no se puede, 3 no corta la sesión, solo queda registrado"): tabla nueva
`arqueos_intermedios` (schemaVersion 25, `m.createTable`, no toca ninguna
migración vieja). `domain/caja.dart` ganó `necesitaArqueoIntermedio`
(pura, 2hs fijas en el código, con tests) y `repositorio_arqueo_intermedio.dart`
reusa `calcularResumenCierre` tal cual (Regla 3) para calcular cada fila, sin
tocar `sesiones_de_caja` — nada se cierra, nada se separa de verdad, solo
queda la constancia. `VentaControlador.arqueoIntermedioVencido` compara
`DateTime.now()` contra la apertura de la sesión (o el último arqueo
intermedio, lo que sea más reciente) con un `Timer.periodic` de 1 minuto
para que el bloqueo aparezca solo, sin que nadie tenga que tocar nada —
mismo patrón que `_tickHorario` de `main.dart`. La pantalla de venta se
bloquea con el mismo `_EstadoBloqueado` que ya usan "sin sesión" y "sesión
de un día anterior"; el modal (`dialogo_arqueo_intermedio.dart` +
`arqueo_intermedio_controlador.dart`) es una versión de dos fases
(conteo/revisado, sin "cerrado") del mismo flujo de `PantallaCierre`, con
los tres contados siempre obligatorios. Corre en la MISMA sesión que ya
estaba abierta — no crea una hoja nueva, no cambia el `usuarioAbrioId`, no
interactúa con "Cambiar de turno" ni con "Cerrar caja".

**2026-09-12, apertura de caja pide los tres montos** (El dueño: reboot de la
base — "para abrir caja se necesita: caja normal, caja cigarros, monto
mercado pago"). `DialogoAperturaCaja` gana dos campos nuevos ("Caja
cigarrillos" y "Monto Mercado Pago"), con el mismo tratamiento que ya tenía
el fondo normal: precargado con lo último contado, editable. Diferencia
clave entre los tres: el fondo normal solo precarga si hubo un cierre
*hoy* (cambio de turno); lata y MP precargan sin importar el día (no se
"cierran" cada noche como el cajón). `abrirSesion` (`repositorio_ventas.dart`)
gana `mpInicialCentavos` (default 0) y `lataInicialCentavos` (default
`null` = arrastre automático de siempre) — ningún llamador existente
(companion, tests) se rompe por no pasarlos. `domain/caja.dart`
(`mpEsperadoCentavos`) gana `inicialCentavos`, revirtiendo parcialmente
"MP arranca siempre en 0" (`DECISIONES.md`) — el resto de esa fórmula
(esperado = movido en el día) no cambió, el inicial se suma una sola vez
igual que el fondo en efectivo. Columna revivida: `saldoMpInicialCentavos`
(estaba muerta desde schemaVersion 7).

**Mismo día, "el modal de apertura es gigante"**: el primer intento de
arreglar el overflow (tres montos ya no entraban al piso mínimo) fue
envolver el `Dialog` crudo en `ConstrainedBox(maxHeight: 85% de la
pantalla)` + `SingleChildScrollView`, sin fijar `maxWidth` — probado a mano
(ver "sondeo" más abajo), el alto quedaba bien (se ajusta al contenido, no
se infla), pero el ancho sí: sin `maxWidth` explícito, `ConstrainedBox`
hereda el máximo del `Dialog`/`Center` de afuera, que a 1920px es casi la
pantalla entera (1840px) — un `TextField` ahí adentro se estira a esa
medida. `DialogoAperturaCaja` nunca había pasado por el kit de diseño;
la arregla de raíz pasándolo a `Modal` (ancho fijo 760, como cualquier
formulario) con `CampoTexto`/`CampoPlata`/`BotonPrimario` — sin necesidad de
ningún `ConstrainedBox`/`SingleChildScrollView` a mano: verificado que las
tres precargas a la vez + aviso de reposición (el caso más alto posible)
entran sin scroll en el piso mínimo real (1366×768). Ganó también
`mostrarDialogoAperturaCaja` (función, mismo patrón que
`mostrarDialogoArqueoIntermedio`) en vez de construir el widget a mano
desde `pantalla_venta.dart`.

Reboot de la base real de el dueño: **ejecutado** (2026-09-12). Se conservó
productos (con stock actual), historial de precios, proveedores (con sus
contadores de reposición/ganancia reseteados a "desde siempre" — quedarían
huérfanos sin las ventas que los sustentaban; el colchón, que ya estaba en
0 en los 19, no hizo falta tocarlo), categorías, configuración, usuarios,
medios de pago, cajas, accesos directos, secciones del menú y los 4
conceptos de gastos fijos. Se borró ventas, líneas de venta, pagos,
sesiones de caja, movimientos de caja, arqueos intermedios, movimientos de
stock, órdenes de cobro pendientes, historial de pedidos (ya en desuso),
clientes, pendientes y los montos de gastos fijos ya cargados por mes.
Backup previo: `la_plazoleta.backup-2026-09-12-antes-de-reboot.sqlite`
(carpeta Documents, mismo patrón que los backups anteriores de el dueño).
`PRAGMA integrity_check`/`foreign_key_check` limpios después.

## Resuelto: stock por proveedor (Regla 8)

El único lugar que ajustaba stock sin dejar rastro en `movimientos_de_stock`
era el detalle de producto (fase 5) — arreglado con `registrarAjusteDeStock`,
motivo elegido de una lista fija (`motivosAjusteDeStock`). Ese mismo
mecanismo ahora tiene una pantalla propia, **Stock por proveedor**
(`lib/ui/stock_proveedor/`), pensada para el conteo físico recorriendo la
góndola: filtro por proveedor y por categoría, agotados o en negativo
primero (nombre en rojo, mismo criterio que la pantalla de venta), edición
inline del stock (unidades o gramos según el producto) con el mismo motivo
elegido una vez para toda la sesión de conteo. `ajustarStockRapido` hace el
mismo ajuste que `actualizarProducto` pero sin tocar nombre/precio/costo.

**Fase 13, paso 2**: esta pantalla salió del menú lateral (Proveedores
absorbió su rol de "editar/dar de alta un producto" vía `Modal`) pero el
archivo no se borró — se llega con el botón "Conteo de stock" del
encabezado de Proveedores (`Navigator.push` directo). Decisión técnica:
meter su flujo de conteo rápido (fila por fila, sin abrir un diálogo por
producto) dentro de un `Modal` por producto le haría perder la velocidad
que tiene hoy para un conteo físico real — se dejó como pantalla aparte a
propósito, no es un cabo suelto.

## Resuelto: catálogo real de proveedores (Regla 16)

El seed de 7 proveedores placeholder (S/F/C/B/W/G/O) se reemplaza por los 15
reales de el dueño, vía migración v9→v10: Distribuidora y Fiambrería conservan `id` y se
renombran, Coca Cola y Golosinas Oeste no cambian, se agregan los 11 nuevos (incluida
Distribuidora de Cigarrillos con código propio SC, antes compartía el de Distribuidora), y
Bebidas varias/Golosinas/Otros (B/G/O) quedan desactivados sin borrarse.
Ver `DECISIONES.md`. El dueño ya puede cargar productos contra el catálogo
real.

## Resuelto: separación de fondos por proveedor (Regla 5 extendida)

Prioridad número uno de el dueño: saber qué plata es de cada proveedor y qué
guardar, por costo real, no por porcentaje. Cada proveedor tiene medio de
pago (efectivo/transferencia/cuenta corriente/Mercado Pago) y un ciclo de
tres estados — pendiente sin separar (como antes), separado (congela el
costo puro con fecha, lo que se vende después se acumula aparte) y pagado
(si se pagó de menos, la diferencia vuelve a pendiente, nunca se pierde).
El corte pasa a ser la separación/el pago, no la recepción de mercadería:
"Pedido hecho"/"Mercadería recibida" salieron de la pantalla,
`historial_pedidos` queda sin usar. Un proveedor en efectivo o en Mercado
Pago genera un `MovimientoCaja` (`PAGO_PROVEEDOR`) al pagarle — los dos
mueven una caja real de la app, transferencia/cuenta corriente no. Aviso
corto en la apertura de caja con cuánto separar de cada proveedor. Distribuidora
Cigarros no aparece en la pantalla (siempre daría cero, Regla 6). Ver
`DECISIONES.md` para el porqué de cada decisión de diseño.

**Corrección post-revisión de el dueño**: `gastosEnEfectivoDelDia`,
`gastosPorMpDelDia` y `pagosALataDelDia` (`repositorio_cierre.dart`)
filtraban solo `tipo = 'GASTO'` — un pago a proveedor en efectivo no bajaba
la caja esperada y el arqueo marcaba un faltante por ese monto. Las tres
(y `planilla_dia.dart`, mismo agujero) ahora usan `tiposEgresoDeCaja`
(`['GASTO', 'PAGO_PROVEEDOR']`). Un pago por Mercado Pago tampoco grababa
nada — corregido para que grabe con `medioPagoId` = Mercado Pago, igual
que `registrarPagoFijo`.

## Resuelto: la planilla "Control diario de caja" al 100% (ítem 3)

Cubre todo el checklist de el dueño contra el PDF vigente (`Planilla_Diaria_Caja
1.pdf`): las dos grillas con "pago mixto: un renglón en cada grilla" y
"cigarrillos: sin letra" ya testeados; apertura/cierre con las 7 líneas en
orden; salidas/pagos con origen cajón o lata. Nuevo:

- **Los tres totales grandes** (efectivo del día, Mercado Pago del día, a la
  lata) arriba de todo en la pantalla de cierre, antes de la diferencia —
  no en el PDF, que ya los tiene en su lugar natural (ver `DECISIONES.md`).
- **Test end-to-end de cigarrillos + QR + recargo**: a la lata va el precio
  de lista, el recargo cobrado en efectivo queda en el cajón.
- **RETIRO se imprime solo el día configurado**, no todos — bug real
  corregido (`esDiaDeRetiro`).
- **La planilla se genera sola al cerrar caja**, en la carpeta de tickets
  ya configurada — antes solo salía a mano desde Historial.
- **Reposición por proveedor, arqueo propio de la lata, y encabezado con
  empleado + horarios** vuelven al PDF por pedido explícito de el dueño — con
  costo real (nunca el porcentaje del papel viejo), un trío contado/
  esperado/diferencia igual al de efectivo y MP (`SesionesDeCaja` gana
  `lataContadoCentavos`/`lataDiferenciaCentavos`), y sin firmas.
- **Impresión y Carga histórica salieron de la app en su momento** (fuera de
  alcance hasta que esto y la pantalla de venta estuvieran al 100%).
  Impresión: apagada por default vía el flag `visible` que ya tenía
  `secciones_menu` — reactivarla es tildarla de nuevo desde Configuración,
  sin tocar código. Carga histórica volvió (2026-09-07), rehecha por
  completo — ver "Resuelto: carga histórica con carrito real" más abajo.

Ver `DECISIONES.md` para el porqué de cada una de estas decisiones.

## Resuelto: carga histórica con carrito real

El dueño, 2026-09-07: "quiero hacer un apartado para cargar ventas anteriores,
que sería una pantalla igual a la de la venta, pero con la opción de poner
la hora y fecha distintas, para cargar el histórico". Reemplaza por
completo a la carga por planilla de la fase 9 (dos grillas de renglones de
texto libre, apertura/cierre y arqueo real a mano) — decisión explícita de
El dueño, no una convivencia de las dos.

Tres decisiones de negocio resueltas con el dueño antes de escribir código:
**no descuenta stock** (esa mercadería ya se descontó en su momento, aunque
no estuviera en el sistema todavía), **no afecta la caja de hoy** (queda
asociada a una sesión de esa fecha vieja, nunca a la sesión abierta ahora),
y **el costo de la línea es el costo actual del producto**, sin intentar
reconstruir el costo real de esa fecha pasada.

- **Fecha elegida una sola vez** (fecha + hora), antes de poder tocar el
  carrito — todo lo que se carga después de elegirla es para ese mismo día.
  No hay forma de cambiar la fecha línea por línea (decisión de el dueño: "elijo
  la fecha al principio, para cargar los productos vendidos por ese día").
- **Nada se graba hasta "Guardar día"**: la tanda de ventas de ese día vive
  en memoria (`CargaHistoricaControlador._pendientes`) — si se cierra la
  pantalla o la app a mitad de carga, no queda ninguna sesión a medio armar
  en la base. Al guardar, una sola transacción crea la `SesionCaja` del día,
  graba cada venta (`registrarVenta(..., afectaStock: false, fecha: ...)`,
  nuevos parámetros opcionales, sin tocar el comportamiento de la venta en
  vivo) y la cierra sola con **arqueo automático** (contado = esperado,
  diferencia 0 — El dueño: "el arqueo dejalo de lado... es simplemente para
  tener un histórico"), reusando `calcularResumenCierre`/`cerrarSesion`
  tal cual, nunca una fórmula nueva (Regla 3).
- **Medios de pago (Efectivo/Mercado Pago/Mixto) son mocks**: solo etiquetan
  el pago para que el arqueo automático y el desglose salgan bien — a
  diferencia de la pantalla de venta, ningún botón manda una orden a la
  terminal Point (El dueño: "no funcionan para cobrar de verdad en esa
  pantalla").
- **Deliberadamente más simple que la pantalla de venta real** (El dueño: "que
  sea lo más rápido para poder cargar históricos" — prioridad a tenerla
  andando, no a la paridad total): sin atajos de teclado Alt+algo, sin alta
  rápida de producto nuevo (se asume que el producto ya existe en el
  catálogo al reconstruir histórico), sin descuento. No comparte los
  widgets/controlador de la venta en vivo — se reconstruyó a propósito para
  no arriesgar la pantalla de venta real (764+ tests, sostiene la caja todos
  los días) con un refactor de tipos compartidos vía Provider.
- `lib/data/busqueda_productos.dart` gana `exigirStock` (default `true`,
  sin cambios para la venta en vivo): la carga histórica busca con
  `exigirStock: false`, porque un producto vendido en su momento puede
  figurar en 0 hoy por cualquier otro motivo — el filtro de "sin stock no
  aparece" es una regla de la venta en vivo, no de reconstruir el pasado.
- Archivos: `lib/data/repositorio_carga_historica.dart` (reescrito),
  `lib/ui/carga_historica/` (controlador y pantalla, reescritos). El botón
  "Cargar día histórico" de Historial ya no pasa por ningún flag — la
  condición que lo bloqueaba (venta y planilla al 100%) ya se había
  cumplido.
- La vieja carga por planilla (`RenglonPlanilla`/`GastoPlanilla`/
  `cargarDiaHistorico`) se movió a `test/helpers/planilla_fixture.dart`:
  dejó de ser una pantalla real, pero varios tests de OTRAS features
  (planilla PDF, editor de venta, detalle de día) todavía la necesitan como
  fixture flexible (texto libre, sin pasar por un producto real).

## En curso: companion app Android

El dueño, 2026-09-07: llevar la app a Android, empezando como companion
(consulta, edición de precios, alta de productos, conteo de stock, gasto
rápido) — el alcance inicial explícitamente NO incluía POS móvil. **Eso
cambió a lo largo de esta misma sección** (ver más abajo, fecha por fecha):
hoy la companion tiene carrito de venta con cobro por posnet, Arqueo en
vivo, historial de ventas y carga histórica — un POS y una caja reales, no
solo consulta. Si vas a tocar algo de `lib/companion/`/`servidor_companion.dart`,
leé toda esta sección antes de asumir el resumen de este párrafo: quedó
desactualizado varias fases atrás y solo el relato completo de abajo tiene
el alcance real (2026-09-10: El dueño tuvo que corregir esto en el momento
porque una sesión asumió "sin POS" a partir de este párrafo solo). Uso
esperado: en el local, en la misma WiFi que la PC; "afuera sirve poco".
Diseño de la UI Android pensado para pantallas grandes de gama alta (S24
Ultra / S26 Ultra — 6.8"+, QHD+, ~19.5:9), no para un celular chico ni para
tablet.

**Arquitectura elegida**: la PC de escritorio pasa a ser también un
mini-servidor mientras la app está abierta — el celular es un cliente
liviano que le habla por HTTP en la red local. La única base de datos sigue
siendo el SQLite de la PC (Regla 3: una sola fuente de verdad, nada de
sincronizar dos bases con conflictos que resolver). Solo funciona con la
app de escritorio abierta y las dos máquinas en la misma WiFi — sin eso, la
companion no hace nada (coincide con el uso esperado). Sin sincronización
offline: si se corta la conexión a mitad de un conteo, se corta.

**Fase A (spike, hecha)**: confirmar que un servidor HTTP embebido
(`shelf`) convive con la app de escritorio y se puede alcanzar de verdad
desde otro proceso — probado con `curl` contra `127.0.0.1` y contra la IP
real de LAN de la máquina, las dos respondieron.

**Firewall de Windows, probado contra el build real (`flutter build
windows`, no `dart run`) — hallazgo real, sin cerrar del todo**: al abrir
el `.exe`, Windows creó solo dos reglas de entrada (TCP/UDP) para
`la_plazoleta.exe`, **scopeadas nada más al perfil de red activo en ese
momento** ("Pública" en esta máquina de desarrollo) — no a los tres
perfiles. Si la red del local está categorizada distinto (ej. "Privada",
lo más común para una red de confianza), un celular real podría quedar
bloqueado sin ningún aviso visible, y la prueba de "IP de LAN desde la
misma PC" no es 100% concluyente para eso (el tráfico de la propia máquina
hacia su propia IP no pasa necesariamente por el mismo camino de filtrado
que un dispositivo de verdad). Agregar una regla manual (`netsh ...
profile=any`) necesita permisos de administrador que la sesión de desarrollo
no tiene — quedó armado `tool/permitir_firewall_companion.ps1` para que
El dueño lo corra una vez, como administrador, después de instalar la app en
la PC del local. **Falta la prueba real con un segundo dispositivo** (el
celular de el dueño) en la WiFi real del local — es la única que contesta la
pregunta de verdad.

**Fase B (API mínima + esquema, hecha)**: `lib/servidor/servidor_companion.dart`
ahora expone la API real, alcance acotado a lo que el dueño pidió (nada de
ventas/caja/cierre/reportes):

- `GET /ping` (sin token, para que el celular confirme que encontró la PC
  antes de estar emparejado) · `GET /usuarios` · `GET /proveedores` ·
  `GET /productos` (`?busqueda=&proveedorId=`) · `POST /productos` (alta) ·
  `PUT /productos/<id>` (edición) · `POST /productos/<id>/stock` (conteo,
  reusa `ajustarStockRapido`) · `GET /sesion` (si hay caja abierta, para
  saber bajo qué sesión cae un gasto) · `POST /gastos`.
- **Autenticación por token compartido**, no login de usuario — la app
  sigue "sin autenticación" para las personas (El dueño/su empleado eligen
  quién son al hacer una acción, mismo criterio que abrir caja hoy). El
  token vive en `configuracionTabla.companionToken` (v21→v22,
  `regenerarTokenCompanion`) y viaja en el header `X-Companion-Token` — sin
  él, o con uno viejo, 401. Todas las rutas lo exigen salvo `/ping`.
- **Gasto rápido salió del diálogo de venta y pasó a
  `lib/data/repositorio_gastos.dart`** (`registrarGastoRapido`,
  `MedioGasto`): vivía inline en
  `lib/ui/venta/dialogo_gasto_rapido.dart`, y duplicarlo para la API
  companion hubiera violado la Regla 3 — ahora las dos formas de cargarlo
  (el diálogo de la venta, la API) llaman a la misma función.
- El servidor arranca solo con la app (`main.dart`, `initState`/`dispose`),
  en segundo plano, sin bloquear el arranque ni tirar abajo la app si falla
  (puerto ocupado, etc.).

**Fase C (pantalla de emparejamiento, hecha)**: nueva sección "App
companion (Android)" en Configuración (`SeccionConfiguracion.companion`) —
sin IP de LAN detectada, avisa que hace falta conectar la PC a la WiFi
antes; con IP, "Generar código" arma un QR (`qr_flutter`) con
`{ip, puerto, token}` y debajo el dato en texto por si hace falta cargarlo
a mano. "Generar uno nuevo" invalida cualquier celular ya emparejado con el
código anterior — a propósito no es automático, generar uno por las dudas
desconectaría un celular andando sin avisar.

Bug real encontrado escribiendo el test de esta pantalla: `direccionesIpLocales()`
(una llamada real a `NetworkInterface.list()`, no a la base) colgaba el
resto de la carga de Configuración bajo `AutomatedTestWidgetsFlutterBinding`
(el reloj falso de `flutter test`) — nada se renderizaba, ni las secciones
que no tienen nada que ver con la companion. Se sacó de la cadena de
`cargarTodo()` a su propia carga aparte (`_cargarIpCompanion`, con
try/catch), para que una falla o demora ahí nunca pueda tirar abajo el
resto de la pantalla.

**Cambio de rumbo, 2026-09-07 (El dueño: "no quiero que sea un nuevo proyecto
Flutter, simplemente adaptar esta para Android")**: Android se agregó como
plataforma más *de este mismo proyecto* (`flutter create . --platforms=android`,
no un repo aparte) — mismo `pubspec.yaml`, mismo `flutter analyze`/
`flutter test`. `main.dart` elige la raíz según la plataforma
(`Platform.isAndroid`): Windows sigue exactamente igual (`LaPlazoletaApp`,
`AppDatabase`, el servidor); Android monta `CompanionApp`
(`lib/companion/companion_app.dart`), que **no abre ninguna base ni prende
ningún servidor** — es puro cliente HTTP hacia la PC. "Ocultar funciones" es
literal: ese código ni se ejecuta del lado del celular, no es una bandera
visual.

**SDK de Android instalado en la máquina de desarrollo** (no lo traía:
`flutter doctor` daba `[X] Android toolchain`) — JDK 17 (Temurin) y
command-line tools portables en `C:\Android\` (fuera del repo), sin
Android Studio completo. `JAVA_HOME`/`ANDROID_HOME`/`ANDROID_SDK_ROOT` y el
PATH quedaron persistidos para el usuario (`reg add`, no `setx` — `setx`
trunca en 1024 caracteres y se comió el valor en el primer intento, ver
`TRAMPAS.md` si hace falta repetir esto en otra máquina). `flutter build
apk --debug` compila limpio con el proyecto real (bajó NDK/CMake solo, la
primera vez). Advertencia no bloqueante: `mobile_scanner` todavía aplica el
Kotlin Gradle Plugin viejo, Flutter avisa que en el futuro eso puede dejar
de andar — no rompe nada hoy, queda anotado para revisar si Flutter se
actualiza y empieza a fallar.

**`lib/companion/` — companion app Android, primera vuelta (conteo de
stock)**:

- `cliente_companion.dart` — cliente HTTP contra la API de
  `servidor_companion.dart` (`ClienteCompanion`, `DatosConexion`,
  `ErrorCompanion` con el mensaje que ya arma el servidor). `ping()` estático
  sin token, para probar alcance antes de guardar nada.
- `emparejamiento.dart` — persiste conexión (ip/puerto/token) y usuario
  elegido en `shared_preferences`, para no tener que volver a escanear ni
  elegir "quién sos" en cada apertura.
- `pantalla_emparejamiento.dart` — escanea el QR de Configuración
  (`mobile_scanner`) o carga los tres datos a mano; verifica con `/ping`
  antes de guardar y avisa si no encuentra la PC.
- `pantalla_elegir_usuario.dart` — "¿Quién sos?", lista de `/usuarios`
  (mismo criterio que abrir caja: sin login real).
- `pantalla_menu_companion.dart` — tres accesos (Conteo de stock, Precios y
  alta de producto, Gasto rápido); los dos últimos avisan "todavía no está
  lista" — el menú ya tiene su lugar reservado, para cuando se construyan.
- `pantalla_conteo_stock.dart` — buscar producto, ver stock actual, cargar
  el conteo real, guardar (`POST /productos/<id>/stock`, motivo fijo
  "Conteo físico" — es el único motivo real para el que existe esta
  pantalla, no hace falta elegirlo).
- `android/app/src/main/AndroidManifest.xml`: permisos de `INTERNET` y
  `CAMERA` (para escanear), y `usesCleartextTraffic="true"` — el servidor
  de la PC habla HTTP plano, no HTTPS (no tiene sentido un certificado para
  algo que nunca sale de la LAN), y Android bloquea tráfico sin cifrar por
  default desde API 28.

**Falta (próximos pasos, en orden)**:

1. La prueba real de firewall con un segundo dispositivo (arriba) — todavía
   no se probó con un celular de verdad, solo con la PC compilando y
   corriendo.
2. Probar la companion app en un Android real (instalar el `.apk` de
   `build\app\outputs\flutter-apk\app-debug.apk` en el celular) — nunca se
   corrió en un dispositivo físico, solo se compiló.

**Probado en un celular real, con datos reales — funciona.** El dueño instaló
el `.apk` de release en su S24/S26 Ultra, emparejó con la PC real, y contó
el stock de un producto real desde el celular. Primer susto: "no actualiza
el stock de la PC" — no era un bug, era que el producto en su catálogo real
tiene un typo ("Pilip Morris Red S.", sin la "h") y el dueño estaba buscando
"Philip". Confirmado leyendo la base real (solo lectura): el `stock` quedó
en 0 y el `movimientos_de_stock` con `tipo=AJUSTE` quedó grabado
correctamente — el camino completo (celular → servidor → base real) andaba
bien desde el primer intento.

**Precios, alta de producto y consultar precio, hechos** (El dueño,
2026-09-07: "con el escáner de códigos de barras. también un consultador de
precios que funcione por escritura también"):

- `GET /productos/codigo/<codigo>` (servidor) + `productoPorCodigoBarras`
  (`repositorio_productos.dart`) — match exacto de código de barras, nuevo:
  `listarProductos` (que ya existía) solo buscaba por nombre. 404 si no
  hay ningún producto con ese código — la señal para que la pantalla
  ofrezca dar de alta en vez de mostrar un error.
- `lib/companion/escanear_codigo.dart` — cámara a pantalla completa
  (`mobile_scanner`), reusada por las dos pantallas nuevas (Regla 3).
- `lib/companion/pantalla_precios.dart` — buscar por nombre o escanear;
  código sin match abre el alta con ese código ya cargado. El formulario
  (alta y edición comparten el mismo) reusa **el kit de diseño del
  escritorio tal cual** (`CampoTexto`/`CampoPlata`/`Bloque` de
  `lib/ui/comun/` y `lib/ui/tema/`, más `formatearARS`/`parsearARS` de
  `lib/domain/dinero.dart`) — son puro Dart/Flutter sin nada específico de
  Windows, se pudieron reusar directo. No toca stock a propósito (eso
  sigue siendo trabajo exclusivo de Conteo de stock, para no mezclar los
  dos flujos).
- `lib/companion/pantalla_consultar_precio.dart` — solo lectura, a
  propósito en una pantalla separada de la de editar: un vistazo rápido de
  precio nunca puede tocar un precio sin querer. Buscar por nombre o
  escanear, precio grande, stock como dato secundario.

**Sistema de actualización de la companion app, hecho** (El dueño, 2026-09-07:
"ya que de todos modos tenemos un servidor local... para poder probar sin
tener que pasar la apk a cada rato"):

- `GET /companion/version` (compara `PackageInfo` de la PC contra la del
  celular — misma `pubspec.yaml` para las dos plataformas, un solo número
  de versión) y `GET /companion/apk` (sirve el archivo tal cual, como
  stream — no carga los ~25MB enteros en memoria).
- El .apk **no** se empaqueta como asset de Flutter — se probó primero así
  y fue un error real: un asset es compartido por TODAS las plataformas
  del proyecto, así que el build de Android terminaba incluyéndose a sí
  mismo adentro suyo (el `.apk` pasó de 25MB a 38MB de la nada, indicio
  claro apenas se vio el tamaño del build). Ahora vive como archivo suelto
  al lado de la base real (`Documents/la_plazoleta_companion.apk`,
  mismo `path_provider` que ya usa `driftDatabase`) — `servidor_companion.dart`
  lo sirve desde ahí. `tool/publicar_actualizacion_companion.sh` compila y
  lo deja en su lugar en un solo paso.
- Del lado del celular (`lib/companion/actualizacion.dart`): al entrar al
  menú, compara su propia versión contra la de la PC; si difieren (no
  importa si más nueva o más vieja, cualquier diferencia alcanza)
  muestra un `MaterialBanner` con "Actualizar" — descarga el `.apk` a un
  archivo temporal y le pide a Android que lo instale (`open_filex`,
  permiso `REQUEST_INSTALL_PACKAGES` nuevo en el manifest). Android sigue
  pidiendo confirmación humana para instalar — nunca es silencioso.
- Gotcha de test real: los tests de estos dos endpoints necesitaron mockear
  `PackageInfo` y `PathProviderPlatform` (ninguno de los dos tiene canal de
  plataforma real bajo `flutter test`), y sacar el `HttpOverrides` que
  `TestWidgetsFlutterBinding` deja puesto por default (hace fallar
  cualquier HTTP real de un test con 400, para que los widget tests no
  dependan de la red sin querer) — acá los tests SÍ necesitan HTTP real,
  contra el propio servidor.
- **Bug real, encontrado por el dueño probando el sistema el mismo día**: con
  `--split-per-abi`, Flutter le suma a cada arquitectura un multiplicador
  al build number para que Play Store pueda distinguir los `.apk` de cada
  una (arm64 = 2000 + build real — build 3 quedaba reportándose como
  "2003"). Comparar eso contra el build number tal cual de la PC (que no
  tiene ese multiplicador) daba "distinta" siempre, aunque fueran la misma
  versión — el banner de actualización nunca se apagaba. Arreglado
  compilando un solo `.apk` para arm64 sin `--split-per-abi`
  (`tool/publicar_actualizacion_companion.sh`), que no tiene ese problema.
- El chequeo de versión además dejó de fallar en silencio (El dueño: "no
  salió nada" — no había forma de saber si era "misma versión" o "no se
  pudo conectar"): ahora siempre muestra un texto de diagnóstico al pie
  del menú (`Celular: X · PC: Y`, o el error si no pudo consultar).

**Conteo de stock, rediseñado por completo** (El dueño, 2026-09-07, spec
completa): reemplaza al "buscar → editar un producto" de la primera
vuelta, que el dueño calificó de "muy nefasto". Ahora:

- Buscador al principio de todo (`lib/companion/pantalla_conteo_stock.dart`):
  tipear muestra un dropdown con el precio de cada resultado. Tocar un
  resultado **no hace nada todavía, a propósito** — el handler
  (`_alTocarResultadoBusqueda`) queda armado pero vacío, para cuando se
  pueda vender desde acá (El dueño: "no elimines la pantalla, solo
  inhabilitala para después modificarla").
- Sin texto en el buscador, en su lugar aparece la lista de proveedores
  (mismo criterio que Proveedores en el escritorio) — tocar uno abre sus
  productos.
- Productos de un proveedor: stock guardado de **solo lectura** al lado de
  un campo para el conteo real. Vacío = no se toca ese producto (El dueño:
  "si no se pone nada se asume que el stock guardado es correcto") — un
  solo botón "Guardar conteo" aplica todos los campos completos de una
  vez, salta los vacíos.
- `ClienteCompanion.productos()` gana `proveedorId` (ya existía del lado
  del servidor, `GET /productos?proveedorId=`, sin usar todavía del lado
  del celular).
- El dueño va a mandar un layout de referencia para esto y la navegación en
  general — esta es una primera pasada fiel a la especificación en texto,
  puede cambiar cuando llegue esa referencia.

**Gasto rápido desde el celular, hecho** (El dueño, 2026-09-07 — el último de
los tres pedidos originales de la Fase C) — `lib/companion/pantalla_gasto_rapido.dart`,
mismo formulario que `dialogo_gasto_rapido.dart` de escritorio (monto,
motivo opcional, los tres medios: cajón normal/lata/Mercado Pago), llamando
a la misma `registrarGastoRapido` por `POST /gastos` (ya existía del lado
del servidor desde la Fase B, sin usar hasta ahora).

- **Apertura de caja de emergencia desde el celular, agregada de paso**
  (El dueño: "como comparten la misma bd no podemos abrirla desde la app" —
  sí se puede, es la misma base). Si al abrir Gasto rápido `GET /sesion`
  da `abierta: false`, la pantalla ofrece un formulario corto (solo fondo
  inicial, precargado con lo que quedó del turno anterior si se cerró hoy)
  y sigue directo al gasto al confirmar — nuevo `POST /sesion/abrir`
  (`servidor_companion.dart`), misma `abrirSesion` que usa el diálogo de
  escritorio (Regla 3), sin el aviso de reposición que sí tiene la
  apertura de escritorio (no aplica a un desbloqueo puntual) y sin
  quedar como acceso de menú aparte — nace solo dentro de este flujo.
  Decisión de el dueño, explícita: carga directo, sin mostrar a qué
  sesión/turno cae el gasto.
- `fondoInicialSugeridoCentavos` (`repositorio_cierre.dart`) — la cuenta de
  "QUEDA EN EL CAJON" que antes vivía inline en
  `dialogo_apertura_caja.dart`, extraída para que las dos formas de abrir
  caja (el diálogo de escritorio, la apertura de emergencia del celular)
  usen la misma fórmula (Regla 3).

**Vender desde el celular, primera versión** (El dueño, 2026-09-07: "quiero
que la parte de vender use la misma lógica que la app de desktop... el
buscador de precios, si tocamos un producto se agrega al carrito, que
aparezca una barra con el subtotal para elegir el medio de pago") —
Efectivo, QR y Débito; sin Mixto ni descuento (decisión explícita de el dueño,
"después lo mejoramos"), ticket solo "enviar a la terminal Point" (sin
"guardar PDF", eso se sigue haciendo desde la PC):

- **El carrito vive en el celular como una `List<LineaVenta>`** — el mismo
  tipo del dominio, no una copia — armado con lo que ya devuelve
  `buscarVenta` (precio/costo/proveedor/tipo de cigarrillo): el precio
  queda congelado en el momento en que se toca el producto (Regla 2,
  costo-foto), igual que en el mostrador, no al calcular ni al cobrar.
  Serializado por `lib/domain/venta_json.dart` (nuevo, puro Dart) para
  viajar por HTTP.
- **El buscador del menú principal pasa a usar `GET /ventas/buscar`**
  (`buscarProductos`, la misma búsqueda del campo único del escritorio —
  filtra por stock, Regla 8, y entiende "200 queso" para pesables) en vez
  de `GET /productos` (esa sigue siendo la de Precios/Conteo, que necesita
  ver todo el catálogo incluido lo que está en cero). Tocar un resultado
  agrega la línea (`lib/companion/carrito_venta.dart`,
  `lineaDesdeResultadoBusqueda` — mismos avisos que
  `VentaControlador.agregarProducto` para un pesable sin gramos o sin
  precio por kilo) y funde cantidades de un producto repetido
  (`sumarLineasVenta`, extraída de `VentaControlador._sumarLineas` al
  dominio para que las dos puntas usen la misma fusión, Regla 3). Con algo
  en el carrito aparece una barra fija abajo con el subtotal — tocarla abre
  `PantallaCarritoVenta`.
- **Endpoints nuevos en `servidor_companion.dart`, todos sobre las mismas
  funciones que ya usa `VentaControlador`** (Regla 3, cero fórmulas
  nuevas): `GET /ventas/buscar`, `POST /ventas/calcular`
  (`calcularTotalVenta`), `POST /ventas/cobrar` (efectivo directo,
  `registrarVenta`), y el ciclo de tres pasos de Point ya existente
  (`POST /ventas/posnet/iniciar` → `GET /ventas/posnet/estado/<id>` → `POST
  /ventas/posnet/confirmar`, más `/no-aprobado` y `/cancelar`) — mismo
  criterio que `dialogo_cobro_posnet.dart`: la venta se graba recién
  después de la aprobación, nunca antes, y un cancel que Mercado Pago
  rechaza (`cannot_cancel_order`) deja la fila en `'pendiente'`, nunca se
  asume. `POST /ventas/<id>/imprimir` reusa `imprimirEnPosnet` +
  `ticketDeVenta`, mismo camino que "Enviar a posnet" del diálogo de
  Impresión del escritorio.
- El polling del celular usa el mismo ritmo que el diálogo de escritorio
  (`intervaloPollingCobroPosnet`/`timeoutPollingCobroPosnet`, ahora
  compartidas en `domain/cobro_posnet.dart` en vez de constantes privadas
  del diálogo — Regla 3) — `lib/companion/dialogo_cobro_posnet_companion.dart`,
  sin "Cobrar a mano" (a diferencia del escritorio): si no se aprueba,
  vuelve al carrito y el cajero elige Efectivo desde ahí si hace falta.
- **`SesionAbiertaGate`** (`lib/companion/sesion_abierta_gate.dart`) — la
  apertura de emergencia que ya tenía Gasto rápido, extraída para que
  vender también la use sin duplicar el formulario (Regla 3): sin sesión
  abierta, pide el fondo inicial y abre antes de dejar elegir medio de
  pago.
- `iniciarServidorCompanion`/`_armarRouter` ganan `httpClientDePrueba`
  (mismo patrón que `VentaControlador`) para poder testear el ciclo de
  Point sin pegarle a Mercado Pago real — `MockClient` en
  `test/servidor/servidor_companion_test.dart`.
- `tipoCigarrilloDesde` se movió de `repositorio_ventas.dart` a
  `domain/venta.dart` (pura, sin drift): el celular arma una `LineaVenta`
  desde `ProductoCompanion` sin abrir ninguna base, y necesitaba el mismo
  mapeo que ya usa `lineaDesdeProducto` en el escritorio.

**Bug real, encontrado por el dueño probando el alta desde el celular
("funciona medio a pedales, no agrega bien o directamente no agrega")** —
dos causas, las dos arregladas:

- `CampoPlata` pedía `TextInputType.number`: en Android ese teclado no
  ofrece el separador decimal (en el escritorio no se nota, con teclado
  físico). Tipear "15050" pensando en $150,50 se cargaba como
  $15.050,00 — el "agrega mal". Ahora pide
  `numberWithOptions(decimal: true)`, mismo campo para toda la app
  (escritorio y celular).
- `crearProducto`/`actualizarProducto` no validaban un código de barras
  repetido antes de insertar — la restricción `UNIQUE` del esquema tiraba
  una excepción cruda de sqlite sin capturar, que en el celular llegaba
  como un 500 genérico ("directamente no agrega") y en Proveedores
  (escritorio) directamente rompía el diálogo sin aviso, un bug latente
  que nadie había pisado todavía. Ahora las dos funciones
  (`repositorio_productos.dart`) chequean el duplicado antes de insertar y
  tiran un `ArgumentError` con el nombre del producto que ya lo tiene
  (avisando si está dado de baja) — un solo chequeo para las dos puntas
  (Regla 3), el diálogo de Proveedores ahora también lo captura y lo
  muestra en vez de crashear.

**Productos sin stock, revisables desde el celular** (El dueño, 2026-09-07:
"yo debería poder revisar los productos sin stock desde la app Android
para ajustarlos") — nuevo ítem "Sin stock" arriba de la lista de
proveedores en Conteo de stock: junta los agotados/negativos de TODOS los
proveedores (`GET /productos/sin-stock`, mismo criterio que "Stock por
proveedor" del escritorio — `productoAgotado`/`ordenarAgotadosPrimero`,
Regla 3, nada nuevo) en vez de tener que entrar proveedor por proveedor
buscando ceros. La pantalla de conteo en sí se generalizó
(`PantallaConteoProductos`, antes `_PantallaConteoProveedor` privada) para
que "por proveedor" y "sin stock" compartan la misma UI de conteo — la
única diferencia es de dónde sale la lista de productos.

**Carga histórica desde el celular** (El dueño, 2026-09-07: "quiero que
agregues la parte de los históricos... se le pone la fecha, después es
como si fuesen ventas que no descuentan stock, simplemente son para saber
ganancias") — mismo concepto que `lib/ui/carga_historica/` del escritorio,
llevado a la companion:

- Nuevo tile "Cargar día histórico": elegís fecha y hora una sola vez,
  después armás ventas con el mismo buscador de Venta pero sin exigir
  stock (`GET /ventas/buscar?exigirStock=false` — un producto vendido en
  su momento puede estar en 0 hoy por cualquier otro motivo, mismo
  criterio que la carga histórica de escritorio). Medios de pago
  (Efectivo/Mercado Pago/Mixto) son etiquetas nada más, sin posnet — igual
  que en el escritorio.
- **Nada se graba hasta "Guardar día"**: el celular junta las ventas del
  día en memoria (`VentaHistoricaPendienteCompanion`) y las manda todas
  juntas en un solo `POST /historico/dia`, que arma cada una
  (`calcularTotalVenta`/pagos) y se las pasa de una sola vez a
  `cargarDiaHistoricoDesdeVentas` — la misma función del escritorio
  (Regla 3): una sola transacción (sesión + cada venta + cierre automático
  con arqueo en cero), nada queda a medio armar si algo falla a mitad de
  camino.
- Mixto ahora es un medio válido del lado del servidor
  (`_pagosDesdeMedio`/`_medioDesdeTexto` extendidos) — la venta en vivo del
  celular no lo manda (sigue sin Mixto en esta primera versión, decisión
  ya tomada), pero la carga histórica sí lo necesita y comparte el mismo
  código.

**Carga histórica: solo el día (sin hora), carrito con eliminar, y ver/editar
días ya cargados** (El dueño, 2026-09-07: primero "necesito que solo sea el día
que se cargue, y que sea como el carrito normal, que permita eliminar", y
después "dejame verlos y editarlos porque le erré y lo cerré sin
completarlo"):

- El selector de fecha perdió el paso de hora — solo día, con `showDatePicker`.
- El carrito de la venta que se está armando (`_ArmadorDeVenta`) ganó el
  ícono de tacho por línea, igual que el carrito de la venta real.
- **La pantalla pasó a ser un hub**: lista los días ya cargados
  (`GET /historico/dias`, filtra por `nota = 'Carga histórica'`) con
  "+ Nuevo día" para arrancar uno. Entrar a un día (`GET /historico/dias/<id>`)
  muestra sus ventas con tacho por venta (`DELETE .../ventas/<id>`, nunca
  toca stock — nunca lo tocó al cargarla — y recalcula el resumen del día
  después), "Agregar más" (reusa el mismo armador de ventas contra
  `POST .../agregar`, sin crear una sesión nueva) y borrar el día entero
  (`DELETE /historico/dias/<id>`, el escape hatch para "le erré, empiezo de
  cero").
- Nueva `_recalcularResumenDiaHistorico` (`repositorio_carga_historica.dart`)
  — la usan crear un día, agregarle más y borrar una venta: recalcula el
  arqueo automático (contado = esperado) y lo reescribe, para que el
  resumen de Historial nunca quede desactualizado. `cerrarSesion` no exige
  que la sesión esté ABIERTA (es una UPDATE simple), así que no hace falta
  "reabrir" nada para editar un día ya cerrado.

**Actualización de la companion: dos bugs reales, los dos arreglados**
(El dueño, 2026-09-07: "la apk no detecta la actualización si no la cierro y
abro de vuelta, y no hay manera de poder lanzar actualizaciones sin
reiniciar la app desktop"):

- **El celular solo chequeaba la versión una vez, en `initState()`** de la
  pantalla principal — volver de segundo plano sin cerrar la app del todo
  nunca volvía a chequear. Ahora `_PantallaMenuCompanionState` observa
  `AppLifecycleState.resumed` (`WidgetsBindingObserver`) y re-chequea cada
  vez que la app vuelve a primer plano.
- **`/companion/version` comparaba contra `PackageInfo.fromPlatform()` del
  propio proceso de escritorio** — ese número solo cambia reconstruyendo Y
  reiniciando ESE `.exe`, sin ninguna relación con qué `.apk` se estaba
  sirviendo de verdad. Ahora lee un archivo chico al lado del `.apk`
  (`la_plazoleta_companion.version`, texto plano tipo "1.0.0+2016") que
  escribe `tool/publicar_actualizacion_companion.sh` en cada publicación —
  si no existe (primera vez, antes de correr el script una vez con esta
  versión) se cae a `PackageInfo.fromPlatform()` como antes.
- **El script ya sube el build number solo** — antes había que acordarse
  de editar `pubspec.yaml` a mano antes de correrlo (paso que se olvidaba).
  Ahora lee la versión actual, le suma 1 al build number, la escribe de
  vuelta y compila con esa.
- Con esto, publicar una actualización (correr el script) alcanza para que
  el celular la note en cuanto vuelve a primer plano — ya no hace falta
  tocar la app de escritorio para nada.

**Ajuste de cantidad en los carritos del celular** (El dueño, 2026-09-07: "no
puedo agregar más de 1 unidad a la vez de los productos, misma
funcionalidad que carrito [ya] dije") — tocar el mismo producto en el
buscador ya sumaba de a uno (`sumarLineasVenta`), pero eso obligaba a
buscar de nuevo cada vez para subir la cantidad. `FilaLineaCarrito`
(`lib/companion/fila_linea_carrito.dart`, nueva) agrega botones "−"/"+"
para una línea por unidad (restar en 1 saca la línea entera, mismo
criterio que `ajustarCantidad` del escritorio) y doble tap sobre la
cantidad/gramos para tipear el valor exacto de un tirón — sin +/- para un
pesable, igual que el escritorio. Un solo widget para los dos carritos del
celular (vender de verdad y carga histórica), Regla 3 — antes cada uno
tenía su propia fila de solo lectura + tacho.

**QR para instalar en un celular nuevo** (El dueño, 2026-09-07: "¿no podemos
hacer que en la app escaneando el QR lo ponga para descargar?") — el QR de
Configuración → App companion es JSON (`{ip, puerto, token}`), pensado para
el escáner de la propia companion; la cámara común de un celular sin la
app instalada no hace nada útil con eso. Ahora hay un segundo QR debajo,
con una URL lisa a `/companion/apk` — la cámara de cualquier celular la
reconoce como link y abre el navegador, que descarga el `.apk` directo.
`/companion/apk` quedó exento del token (`_autenticacion`,
`servidor_companion.dart`, junto a `/ping`): un navegador abriendo un link
no puede mandar el header, y el `.apk` en sí no es un dato sensible — el
token sigue protegiendo todo lo demás. Después de instalar, el celular
sigue necesitando el QR de arriba (o cargar los datos a mano) para
emparejarse de verdad.

**Recargo de cigarrillos, verificado de punta a punta con el cliente real**
(El dueño, 2026-09-07: "revisa que la apk no agrega los recargos automáticos")
— dos tests nuevos que ya no arman la `LineaVenta` a mano del lado del
servidor (como hacían los existentes) sino que usan `ClienteCompanion` y
`lineaDesdeResultadoBusqueda` tal cual corre en el celular, para vender y
para carga histórica: buscar → armar la línea → calcular/guardar. Los dos
confirman que el recargo aparece con QR/Mercado Pago y da $0 en efectivo
(Regla 6) — no se encontró ningún bug, la lógica ya estaba bien en las dos
puntas.

**Dos bugs reales de la carga histórica, encontrados por el dueño mandando una
captura** (Marlboro Crafted Red, medio Efectivo, botón mostrando siempre el
mismo monto):

- **"Agregar venta" nunca mostraba el recargo** — el botón usaba el
  subtotal crudo (`Venta(lineas: _carrito).subtotalCentavos`), calculado
  en el celular, en vez de pedirle al servidor el total real
  (`calcularVenta`, con recargo de cigarrillos y redondeo). El monto que
  se termina grabando siempre fue correcto (verificado con los tests
  end-to-end de más arriba) — lo que faltaba era mostrarlo ANTES de
  confirmar, así que con un cigarrillo por Mercado Pago parecía que el
  recargo "no se aplicaba". Ahora `_ArmadorDeVenta` llama a
  `calcularVenta` cada vez que cambia el carrito o el medio elegido, y
  `VentaHistoricaPendienteCompanion` guarda ese total ya calculado
  (`totalParaMostrar`) para seguir mostrándolo bien en el resumen de
  ventas ya cargadas de ese día.
- **"Guardar día" (el botón que cierra todo el día) se confundía con
  "Agregar venta"** (El dueño: "invita a apretarlo para guardar las ventas, y
  termino teniendo que volver a abrirlo") — quedaban pegados, uno debajo
  del otro, con el mismo estilo. "Guardar"/"Agregar" (el de terminar) pasó
  a la barra de arriba (`AppBar.actions`), separado del flujo de armar
  cada venta — mismo criterio que "un botón por acción, en el lugar
  correcto" del resto de la app.

**Resumen del día histórico** (El dueño, 2026-09-07: "hay que scrollear
demasiado... sobre todo que ordenemos y resumamos todo, así que al entrar
a un día necesitaría un resumen de lo vendido por medio de pago, por
proveedor, y la separación teórica"):

- **Nada de fórmulas nuevas** — `resumenDiaHistorico`
  (`repositorio_carga_historica.dart`) reusa
  `efectivoDeVentasDelDia`/`pagosNoEfectivoDelDia` (por medio de pago) y
  `reposicionDelDia` (por proveedor: vendido, costo real = separación
  teórica Regla 5, ganancia) — las mismas que ya usan el cierre real y
  "Reportes" para el día en curso, acá apuntadas a un día histórico
  puntual. Nuevo endpoint `GET /historico/dias/<id>/resumen`.
- **El detalle de un día pasó a tener dos pestañas** — "Resumen" (arranca
  ahí, sin scroll: total, efectivo/Mercado Pago, y una tarjeta por
  proveedor con vendido/separar/ganancia) y "Ventas" (la lista de siempre,
  para editar/borrar una puntual, ya no lo primero que se ve). Antes había
  que sumar a ojo revisando venta por venta para saber "cuánto vendí" o
  "cuánto le separo a tal proveedor".
- **Exportar a PDF queda pendiente** — El dueño lo mencionó como "estaría
  interesante" pero no como lo prioritario de este pedido; se puede armar
  después reusando `pdf`/`printing` del escritorio (generar el PDF en el
  servidor, servirlo como archivo descargable al celular, mismo patrón que
  ya existe para el `.apk` de actualización).

**App de escritorio preparada para la mitad de pantalla (960×1080)**
(El dueño, 2026-09-07: "prepara la app desktop para funcionar en la mitad de
la pantalla de 1920×1080, que sea todo bien accesible y nada se vaya por
las ramas") — 960px es más angosto que el piso mínimo ya documentado
(1366): con las columnas anchas de siempre, la pantalla de venta
directamente desbordaba (barra lateral + búsqueda + cobro ya sumaban más
que los 960px disponibles, sin contar el carrito). Detalle completo del
razonamiento y los números en `DISENO.md`, sección "Simulador de
resolución" — acá el resumen de lo construido:

- **`Medidas.anchoUmbralCompacto` (1200px)** — por debajo, la barra
  lateral se pliega sola (`plegadaEfectiva`,
  `lib/ui/navegacion/barra_lateral.dart`) sin pisar la preferencia
  guardada a anchos normales, y la pantalla de venta pasa a columnas
  angostas propias (`anchoColumnaBusquedaVentaCompacta`/
  `anchoColumnaCobroVentaCompacta`). 1920 y 1366 (el piso ya aprobado)
  quedan exactamente como estaban.
- **Bug real encontrado con la primera captura de prueba**: con la
  columna de búsqueda angosta, la fila de resultados (nombre + stock +
  precio, ancho fijo) se quedaba sin lugar para el nombre — se veía en
  blanco. `columna_busqueda.dart` ganó el mismo patrón que ya usa el
  carrito (`LayoutBuilder`, saca la columna de stock antes que dejar el
  nombre sin espacio).
- **`Metrica`/`FilaMetricas` (`lib/ui/comun/metrica.dart`), compartida por
  Proveedores/Reportes/Equilibrio**: la cifra se achica con `FittedBox` en
  vez de partirse en dos líneas — nunca `overflow: ellipsis` en un monto,
  truncarlo podría leerse como un número distinto.
- **Simulador de resolución** (`lib/ui/tema/simulador_resolucion.dart`)
  gana el botón "960×1080 (mitad)" para probar esto en vivo, al lado de
  los dos que ya existían.
- **Verificado con capturas reales** (`test/capturas/*-mitad-pantalla.png`)
  de Venta, Proveedores y Reportes — las tres sin overflow y legibles.
  `flutter_test` falla el test si algo desborda de verdad (RenderFlex
  overflow es un `FlutterError` real), así que estos tests ya prueban "no
  se rompe", más allá de que el dueño las mire.
- **Pendiente**: el resto de las pantallas de gestión (Cierre, Historial,
  Configuración, Equilibrio) no se revisaron una por una a 960 — heredan
  el arreglo de la barra lateral compartida y de `Metrica`, pero ninguna
  se probó con una captura propia todavía. Si el dueño nota algo raro en
  alguna, avisar para revisarla puntual.

**Pulido de fricción en la companion** (El dueño, 2026-09-07: "no me gusta que
se abra el teclado al entrar o volver, en las ventas históricas no me
gusta que aparezca abajo las ventas por agregar, también necesito que
saques la versión de abajo, y que la barra del carrito aparezca arriba
del teclado, no abajo del todo, es fricción innecesaria"):

- **Sin teclado automático al entrar a una pantalla** — se sacó
  `autofocus: true` de los campos de monto/búsqueda que lo tenían en
  `pantalla_precios.dart`, `pantalla_consultar_precio.dart`,
  `pantalla_gasto_rapido.dart` y `sesion_abierta_gate.dart` (el fondo
  inicial de apertura de emergencia). Se dejó a propósito en
  `fila_linea_carrito.dart`: ahí el usuario ya tocó dos veces para pedir
  "editar el valor exacto", así que el teclado es lo que estaba pidiendo.
- **Carga histórica ya no muestra la tira de tarjetas de "ventas por
  agregar" siempre visible** — `_AcumuladorDeVentasState` en
  `pantalla_carga_historica.dart` pasó a una barra compacta de una sola
  línea ("N venta(s) — $total", mismo patrón que la barra del carrito del
  menú principal); tocarla abre un diálogo con la lista y el tacho para
  borrar una puntual. Menos ocupado en pantalla mientras se sigue
  cargando ventas de un día.
- **Diagnóstico de versión sacado de la pantalla principal** —
  `_PantallaMenuCompanionState` mostraba un texto de estado del último
  chequeo de actualización (`_diagnosticoVersion`); el dueño lo consideró
  ruido. Se sacó el campo y toda su UI; `_revisarActualizacion()` sigue
  revisando en segundo plano (silencioso si falla: sin conexión a la PC
  no es un error para mostrar).
- **Barra del carrito, arriba del teclado, no pegada abajo del todo** — en
  `pantalla_menu_companion.dart` la barra pasó de `bottomNavigationBar`
  (que Scaffold pinta debajo de todo, ignorando el teclado) a ser el
  último hijo del `Column` del body: con `resizeToAvoidBottomInset` por
  defecto, el Scaffold ya la sube sola cuando aparece el teclado, sin
  código extra.

**Cobro a mano agregado al diálogo de Point de la companion** (El dueño,
2026-09-07, en medio del pulido anterior: "recordá poner el cobro manual
del qr/posnet, es para cargar las ventas de hoy y seguir cargando
mientras tanto") — mismo criterio que el diálogo de escritorio
(`dialogo_cobro_posnet.dart`): si la terminal Point no está a mano o
falla, hay que poder seguir vendiendo igual. `dialogo_cobro_posnet_companion.dart`
gana la fase `cobrandoAMano` y el botón "Cobrar a mano" en los estados
rechazado/expirado/error (reemplaza a un simple "Volver" — mismo set de
botones `[Cobrar a mano, Reintentar]` que ya usa el escritorio, ninguna
salida sin elegir una de las dos). Nuevo método de cliente
`cobrarVirtualAMano` y parámetro `canal` en `POST /ventas/cobrar` del lado
del servidor, con test end-to-end nuevo.

**"Arqueo" en vivo, sin contar nada a mano** (El dueño, 2026-09-07: "un botón
de arqueo también para saber que tal vamos en cualquier momento sin tener
que contar a mano las ventas del día" — mezclado con el indicador de caja
abierta/cerrada que ya se había pensado):

- El home de la companion ahora muestra siempre "Caja abierta"/"Caja
  cerrada" (`_barraEstadoCaja`, `pantalla_menu_companion.dart`); con la
  caja abierta, tocarlo abre `PantallaArqueo`
  (`lib/companion/pantalla_arqueo.dart`, nueva).
- Nada de fórmulas nuevas (Regla 3): `estadoCajaEnVivo`
  (`repositorio_cierre.dart`) es la primera mitad de
  `calcularResumenCierre` (las mismas `cajaEsperadaCentavos`/
  `mpEsperadoCentavos`), sin pedir el efectivo contado — por eso nunca
  calcula `diferenciaArqueo` ni separa cigarrillos, eso sigue siendo
  exclusivo del cierre real (Regla 10). El resto de la pantalla (total,
  por proveedor) reusa tal cual `resumenDiaHistorico`, que ya no le
  importa si la sesión está abierta o cerrada. Nuevo endpoint
  `GET /caja/estado` (409 si no hay caja abierta), nuevo
  `cantidadVentasDelDia` en `repositorio_cierre.dart`.
- **Pendiente de confirmar con el dueño, no tocado**: al escribir el test de
  este endpoint apareció que `efectivoEsperadoCentavos` (y por lo tanto
  también el del cierre real, `calcularResumenCierre.efectivoEsperadoCentavos`,
  que usa la misma fórmula) suma el redondeo dos veces cuando hay ventas
  en efectivo con redondeo: `efectivoDeVentasDelDia` ya sale de los
  movimientos de caja con el total FINAL (post-redondeo, lo que
  físicamente entra al cajón), y `cajaEsperadaCentavos` le suma
  `redondeoCentavos` otra vez encima. Con la estimación de la Regla 2
  (~$3.000/día de redondeo acumulado), la caja esperada del cierre real
  quedaría sobrestimada en esa misma magnitud todos los días. No se tocó
  nada de esto — es lógica preexistente del cierre de escritorio, ya
  probada y en uso — pero vale la pena que el dueño revise si el arqueo real
  viene mostrando un "sobra" sistemático de ese orden.

**Cobro a mano directo en el carrito de venta, sin pasar por Point**
(El dueño, 2026-09-07: "el carrito de venta no tiene venta manual por QR") —
lo que se había agregado antes era el fallback DENTRO del diálogo de Point
(aparece recién si la orden falla/expira/da error, igual que el
escritorio). Pero el pedido original ("cargar las ventas de hoy y seguir
cargando mientras tanto") es para ventas que ya se sabe que no van a tocar
la terminal — cobradas por otro medio y que solo faltan asentar — así que
esperar a que Point falle primero era la fricción exacta que se quería
evitar. `pantalla_carrito_venta.dart` gana un botón de texto "Cobrar a
mano (sin terminal)" debajo de "Cobrar", visible solo con QR o Débito
elegido (nunca con Efectivo): salta directo a `cobrarVirtualAMano`, el
mismo endpoint que ya usaba el fallback del diálogo (Regla 3) — ninguna
orden Point se crea en este camino.

**El arqueo (y el resumen de un día histórico) ahora muestran toda la
plata, cigarrillos incluidos** (El dueño, 2026-09-07: "el arqueo muestra
solamente una fracción del monto... porque no me marcan los cigarrillos
de Distribuidora de Cigarrillos, y eso que vendí. ni la apk ni la desktop") —
investigado antes de tocar nada: el dato estaba bien guardado (la venta
de cigarrillos tenía el `proveedorIdFoto` de Distribuidora de Cigarrillos correcto), el
hueco era de visibilidad. Los cigarrillos se excluyen a propósito de "por
proveedor" (Regla 6: se separan por la lata, no por reposición estándar)
tanto en Reportes del escritorio como en este resumen — correcto — pero
ninguna de las dos pantallas mostraba en ningún lado esa plata fuera del
cierre real (que pide contar primero). Arreglado sin fórmulas nuevas:
`ResumenDiaHistorico` (`repositorio_carga_historica.dart`) gana
`cigarrillosListaCentavos` (reusa `precioListaCigarrillosDelDia`, Regla
3), mostrado como línea propia en `pantalla_arqueo.dart` y en la pestaña
Resumen de `pantalla_carga_historica.dart`. Pendiente para más adelante,
no tocado: el equivalente en "Reportes" del escritorio necesitaría el
saldo *acumulado* de la lata (no "vendido hoy"), que es una decisión de
diseño distinta — a confirmar con el dueño antes de tocar esa pantalla.

**Detalle de qué falta completar, no solo el total** (El dueño: "de lo
vendido decime que no tiene costo o proveedor, así le asignamos uno y
medio calculamos el costo") — `vendidoSinCostoCentavos` ya daba el
total, pero no A QUÉ ir a completarle el dato. Nueva
`productosSinCostoOProveedorDelDia` (`repositorio_carga_historica.dart`),
agrupada por nombre de producto, mismo criterio de exclusión que
`calcularReposicion` (cigarrillos y "Varios" afuera — ninguno de los dos
necesita completarse, Regla 6/5). Se muestra con `SeccionProductosSinDatos`
(`pantalla_carga_historica.dart`, widget compartido), en Arqueo y en el
resumen de un día histórico: nombre, cuánto le falta (sin proveedor / sin
costo / las dos), y cuánto se vendió. Reemplaza a la vieja línea suelta
"Vendido sin proveedor o costo cargado: $X" (quedaba sin decir qué
producto era). Todavía no es tocable para ir directo a editarlo — hoy hay
que buscarlo a mano en "Precios y alta de producto".

**Historial de ventas, filtrable, "tipo Mercado Pago"** (El dueño, 2026-09-07:
"hagamos la sección de reportes para móvil con el historial de ventas, lo
mismo para desktop, que sea filtrable... para un control manual en caso
de desconfiar de los números... toma inspiración de mercado pago") —
diseño acordado con el dueño antes de escribir código (CLAUDE.md: plan antes
de pantalla grande): celular solo lectura por ahora ("no hace falta
tanto de momento"), escritorio en pestaña nueva de "Reportes" al lado de
la de proveedores (nunca la reemplaza), sesiones desde hoy en adelante.

- **`lib/data/repositorio_historial_ventas.dart`, nuevo** —
  `historialDeVentas(db, {desde, hasta, filtroMedio})`: lista ventas
  individuales en un rango de fechas, clasificadas en
  `MedioVentaHistorial` (`efectivo`/`qr`/`debitCard`/`mixto` — más fino
  que el `medioResumen` de la carga histórica porque acá interesa poder
  filtrar QR y Débito por separado, mismo patrón de agrupar pagos que
  `ventasDeDiaHistorico`, Regla 3) y con el mismo `detalle` de productos
  ("Coca-Cola 500ml x2, Fernet x1"). Con tests propios
  (`repositorio_historial_ventas_test.dart`).
- **`GET /historial/ventas?desde&hasta&medio`** (`servidor_companion.dart`)
  — para el celular; el escritorio llama al repositorio directo, sin
  pasar por HTTP (misma app, mismo proceso).
- **Escritorio**: `pantalla_reportes.dart` ganó una `TabBar` — "Proveedores"
  (lo que ya había) y "Historial de ventas" (`tab_historial_ventas.dart`,
  nuevo): filtros por período (Hoy/Ayer/Últimos 7 días/Este mes,
  `SegmentedButton`) y por medio, total y cantidad de ventas del filtro
  actual arriba a la derecha, una fila por venta.
- **Celular**: acceso nuevo "Historial de ventas" en el menú
  (`pantalla_historial_ventas.dart`) — mismos filtros que el escritorio,
  agrupado por día ("Hoy"/"Ayer"/fecha) como el feed de Mercado Pago que
  El dueño tomó de referencia. Sin las acciones de separar/retener/retirar
  — eso sigue siendo exclusivo de "Reportes" en el escritorio.
- **Pendiente, no construido todavía** (El dueño: "sin confirmaciones" — pero
  esto es solo lectura, no hacía falta ninguna): llevar
  "Separar todo"/"Retener como colchón"/"Retirar ganancia" al celular
  quedó fuera de esta vuelta a pedido explícito de el dueño ("celular solo
  historial, no hace falta tanto de momento") — si lo pide después, reusar
  tal cual la lógica de `ReportesControlador`/`repositorio_reposicion.dart`
  vía nuevos endpoints, sin inventar nada nuevo.

**Falta (próximos pasos, en orden)**:

1. Ajustar el layout de conteo de stock cuando el dueño mande la referencia
   visual que tiene en mente, para eso y para la navegación en general.
2. Tests para `lib/companion/` — todavía no tiene ninguno del lado del
   cliente/UI (ni unitarios del cliente HTTP, ni de widget de las
   pantallas, incluidas venta, sin stock y carga histórica). Los endpoints
   del servidor sí están probados en `test/servidor/`, incluidos los de
   actualización, sesión, gasto rápido, venta (búsqueda, calcular, cobrar
   efectivo, ciclo de Point completo con `MockClient`, imprimir), sin
   stock y carga histórica (incluido el caso "todo o nada" si una venta
   del día falla).
3. **Probar una venta real de punta a punta en el celular** (efectivo, QR
   y Débito contra la terminal Point real) — lo de gasto rápido y conteo
   ya se probó contra hardware real, esto todavía no.
4. Mixto y descuento (Regla 17) quedaron fuera de esta primera versión a
   propósito — sin fecha.
5. **Bot de WhatsApp** (idea de el dueño, 2026-09-07, junto con la de
   actualización) — mucho más grande y con riesgos reales (automatizar
   WhatsApp sin la API oficial de Meta viola los términos de servicio y
   puede terminar en un baneo del número; la API oficial pide aprobación
   de Meta, un número de negocio y tiene costo). Falta que el dueño diga para
   qué lo quiere (¿avisarle a él —stock bajo, cierre del día—, o que
   responda a clientes?) antes de elegir un camino — no se empezó a
   diseñar ni a construir nada todavía.

**Sincronización sin depender del escritorio — fase 1 y 2 del rediseño
(2026-09-17)**: El dueño pidió que la companion tenga su propia base,
sincronizada con la de la PC, para poder seguir operando (vender, gasto/
ingreso rápido, conteo, precios) con la PC cerrada — plan completo en
`C:\Users\el dueño\.claude\plans\recursive-greeting-rose.md`. La migración
v29→v30 (2026-09-15) había dejado las columnas listas (`global_id`/
`origen_dispositivo`/`actualizado_en`) pero sin usar; esta vuelta las puso a
trabajar:

- **Fase 1 (identidad)**: cada repositorio de `lib/data/` que inserta en una
  de las 13 tablas sincronizables ahora estampa `global_id`
  (`lib/data/identidad_sync.dart::generarGlobalId`) y `origen_dispositivo`
  (`idDispositivoActual`, `'desktop'` fijo o el id estable del celular,
  `lib/companion/identidad_dispositivo.dart`) al crear la fila — filas de
  antes de esta fecha siguen con estos campos en `NULL`, a propósito (mismo
  criterio que ya fijó la migración).
- **Fase 2 (motor de sync)**: `lib/data/repositorio_sincronizacion.dart`
  (`cambiosDesde`/`aplicarCambios`, SQL crudo — una sola función para las 13
  tablas, Regla 3) más dos endpoints nuevos en `servidor_companion.dart`
  (`GET`/`POST /sync/cambios`). Del lado del celular,
  `lib/companion/base_local.dart` (primera vez que `lib/companion/` abre su
  propia `AppDatabase` — antes evitado a propósito) y
  `servicio_sincronizacion.dart` (`sincronizarConPc`) mueven filas en el
  orden correcto (categorías/proveedores/productos antes que las ventas que
  los referencian). Conflictos: gana `actualizado_en` más reciente (decisión
  de el dueño); el stock nunca sincroniza como contador — sigue el log de
  `movimientos_de_stock` + `stockRecalculado` (`lib/domain/stock.dart`), ya
  diseñado antes, ahora conectado. Dispara solo al detectar la PC (pairing y
  cada apertura de la companion) más un pull-to-refresh manual en "Inicio"
  (`RefreshIndicator`/`CustomScrollView`, `pantalla_inicio_companion.dart`).
- **Todavía NO permite vender (ni nada) sin la PC abierta** — eso es la fase
  3 (`PuertoLocal` conectado a la UI real, cola de escritura offline,
  herencia de la sesión de caja ya abierta en la PC) y la fase 4 (casos
  borde, prueba real cortando la WiFi), planteadas pero no implementadas
  todavía. Por ahora esto solo deja al celular con una copia local al día,
  sin cambiar ningún comportamiento visible: `ClienteCompanion` (HTTP) sigue
  siendo lo único que se usa para operar de verdad.
- Tests nuevos: `test/data/repositorio_sincronizacion_test.dart` (motor,
  incluido el caso real de dos filas con el mismo `actualizado_en` — con
  segundos como granularidad, dos altas en el mismo segundo comparten
  cursor; el filtro usa `>=`, no `>`, para no perder la segunda para
  siempre), `test/servidor/servidor_companion_test.dart` (grupo
  `/sync/cambios`), `test/companion/servicio_sincronizacion_test.dart`.
- **No desplegado a la PC real todavía** — tocó prácticamente todos los
  caminos de escritura de `lib/data/` (ventas, gastos, ingresos, productos,
  proveedores, pendientes, arqueo intermedio, edición/anulación de venta).
  Toda la suite (998 tests en ese momento) y el analyzer pasan limpio, y los
  dos binarios compilan, pero antes de instalar esto en el local conviene
  una prueba real de un rato — es el cambio de mayor superficie sobre
  `lib/data/` desde la fase 1 del proyecto.

**Fase 3 — vender (y todo lo demás en alcance) sin la PC abierta
(2026-09-17, misma sesión)**: conecta `PuertoLocal` a la UI real por
primera vez.

- `lib/companion/servicio_companion_automatico.dart`
  (`ServicioCompanionAutomatico`) — implementa `ServicioCompanion`
  intentando siempre la PC primero (con 4s de timeout: sin uno, una PC
  apagada deja la llamada colgada para siempre en vez de fallar rápido) y
  cae a `PuertoLocal` solo ante una falla de CONEXIÓN — un error real del
  servidor (`ErrorCompanion`, ej. código de barras repetido) se propaga tal
  cual, nunca dispara un reintento local que podría dar un resultado
  distinto al que la PC ya decidió. La "cola de lo que falta mandarle a la
  PC" no es un mecanismo aparte: son las mismas filas que `PuertoLocal` deja
  con su `global_id`/`actualizado_en` (fase 1), que el próximo
  `sincronizarConPc` (fase 2) ya recoge solo por el cursor de push.
- **Regla de sesión de caja, aplicada de verdad**: `abrirSesion` NUNCA cae a
  la base local — sin PC alcanzable, rechaza con un mensaje claro en vez de
  abrir una caja propia del celular (El dueño: "no permite vender si no había
  una sesión abierta al momento de perder la conexión" — evita el choque de
  dos aperturas del mismo día que ya preveía el comentario de
  `dispositivoAperturaDesignadoId` en `tables/configuracion.dart`). `sesion()`
  sí funciona offline: si ya había una sesión abierta y sincronizada antes
  de cortarse la conexión, `PuertoLocal.sesion()` la encuentra sola en la
  base local (Fase 2 ya la había traído) — no hizo falta ningún mecanismo
  nuevo de "herencia", solo que el pull ya la dejó ahí.
- **Pantallas conectadas** (ahora funcionan sin la PC abierta, si ya
  sincronizaron alguna vez estando online): Gasto rápido, Ingreso rápido,
  Conteo de stock, Precios y alta de producto, y — la pieza central — vender
  en efectivo desde el carrito (`pantalla_carrito_venta.dart` ganó un
  segundo campo `servicio` además de `cliente`: buscar/calcular/cobrar
  efectivo/sesión van por `servicio` con fallback; Point (QR/Débito),
  "cobrar a mano" e imprimir ticket siguen exclusivos de `cliente`, nunca
  andan offline).
- **A propósito sin tocar**: `pantalla_elegir_usuario.dart` — solo se
  alcanza recién emparejado, con la PC ya verificada alcanzable un instante
  antes (`ClienteCompanion.ping`), así que el fallback no serviría de nada
  ahí y sí agregaría un riesgo real (`usuarios` no se sincroniza a
  propósito — "autoridad exclusiva del escritorio" — así que una lista
  offline sería la del seed fijo, no la lista real de la PC si alguna vez
  tiene más de un usuario). `PantallaMenuCompanion._revisarSesion` (el
  indicador de "caja abierta" de la pestaña Inicio) tampoco pasa por el
  fallback — sigue leyendo `estadoCaja()`, que no está en `ServicioCompanion`
  (fuera de alcance) — así que ese indicador puede quedar desactualizado
  estando offline aunque vender siga funcionando bien (el carrito lee la
  sesión por su cuenta, correcto); es un hueco cosmético conocido, no de
  plata.
- Tests nuevos: `test/companion/servicio_companion_automatico_test.dart`
  (PC alcanzable usa la PC; PC caída cae a lo local; un error real de la PC
  nunca dispara un duplicado local; `abrirSesion` sin PC rechaza sin tocar
  la base local; `sesion()` sin PC ve una sesión ya sincronizada).
- Suite completa: 1005 tests, analyzer limpio, los dos binarios compilan.
  **Tampoco desplegado a la PC real todavía**.

**Fase 4 — caso borde real encontrado y arreglado (2026-09-17, misma
sesión)**: "qué pasa si el celular vendió offline un producto que en la PC
se quedó sin stock mientras tanto" resultó ser un bug genuino en la fase 2,
no solo una pregunta teórica.

- **El bug**: `productos` es una tabla que compara `actualizado_en` como
  cualquier otra (gana la edición más reciente) — pero eso incluía sus
  columnas `stock`/`stock_gramos`, que viajan pegadas al resto de la fila.
  Si la PC vendía 3 unidades (sin editar nada más del producto) y el celular
  vendía 2 offline y después sincronizaba, la fila entera del que
  sincronizó último pisaba al otro — una de las dos ventas desaparecía del
  conteo aunque las dos quedaran bien grabadas en `movimientos_de_stock`
  (Regla 6, el rastro nunca se perdía, solo el número derivado). Exactamente
  el problema que `lib/domain/stock.dart` (`DeltaStock`, escrito en la fase
  1 del rediseño, 2026-09-15) ya había diseñado cómo resolver — pero nunca
  se había conectado a nada.
- **El arreglo**, en `lib/data/repositorio_sincronizacion.dart`: `stock`/
  `stock_gramos` de `productos` quedan afuera del `UPDATE` genérico por
  `actualizado_en` (el resto de la fila sigue sincronizando normal). En
  cambio, cada fila de `movimientos_de_stock` que `aplicarCambios` inserta
  por primera vez (nunca una que ya existía — el `global_id` sigue siendo
  la deduplicación) mueve el stock local con su delta
  (`_aplicarDeltaDeMovimientoStock`, `DeltaStock.delta`) — la suma de deltas
  es conmutativa, así que no importa en qué orden cada base vio las ventas
  de la otra.
- **Más de un celular sincronizando a la vez**: no hizo falta código nuevo
  — el mecanismo ya es por dispositivo (`origen_dispositivo`,
  `global_id` random de 128 bits) y la regla de sesión de la fase 3 (nunca
  abrir una caja propia offline) ya evita el único choque real posible
  (dos aperturas del mismo día), sin importar cuántos celulares haya.
- Tests nuevos en `test/data/repositorio_sincronizacion_test.dart`: dos
  bases vendiendo el mismo producto en paralelo sin verse, sincronizar y
  confirmar que las dos ventas se reflejan (era el test que fallaba antes
  del arreglo, con el bug reproducido tal cual); y que sincronizar un
  producto por otro motivo (ej. cambiarle el nombre) nunca pisa el stock
  local con el de la PC.
- Suite completa: 1007 tests, analyzer limpio, los dos binarios compilan.
  **Sigue sin desplegarse a la PC real** — y sigue faltando la prueba que
  ningún test automático puede reemplazar: cortar WiFi de verdad en el
  celular, vender ahí, reconectar, y confirmar a ojo que la PC terminó con
  la venta, el stock y la caja bien. Esa la tiene que hacer el dueño con
  hardware real.

**Ronda de arreglos reales, 2026-09-17 a la noche (no quedó documentada en su
momento)**: El dueño probó la companion en modo local de verdad y encontró un
bug ("no detecta la caja abierta... hacelo de una vez bien" — sin forma de
distinguir "está cargando" de "está en modo local porque no encontró la
PC"). Arreglado con dos piezas nuevas:
- `lib/companion/seleccion_servicio.dart` (`resolverServicioCompanion`):
  reemplaza a `ServicioCompanionAutomatico` — decide una sola vez por
  apertura de pantalla, con un ping corto, si usa `ClienteCompanion` o el
  fallback local (`ServicioCompanionOffline`, antes reintentaba la PC en
  cada acción con su propio timeout, volviendo lenta CADA acción si estaba
  caída).
- `lib/companion/aviso_modo_local.dart` (`AvisoModoLocal`): banner "Modo
  local — sin conexión a la PC", rediseñado como tarjeta redondeada con
  tinte del acento en vez de una franja pegada al borde.

## En curso: companion Android como "POS aparte" — sync vía Firebase (2026-09-18)

El dueño pidió ir más lejos que el rediseño de arriba: que el celular sea un POS
totalmente aparte (ni PC abierta ni misma WiFi), sincronizando por internet
vía Firebase, con login real (Google o registro por email/contraseña) en vez
de auth anónima, y que el cobro por Point y la impresión también anden sin la
PC. Plan completo en `C:\Users\el dueño\.claude\plans\clever-greeting-lagoon.md`.
Hallazgo que cambia el tamaño del problema: `cobro_posnet.dart` e
`impresion_posnet.dart` ya son llamadas HTTP puras a la nube de Mercado Pago
— no dependen de Windows ni de la LAN, solo de tener las credenciales a mano
(hoy solo viven en la PC). El motor de merge ya construido arriba
(`repositorio_sincronizacion.dart`) es 100% transporte-agnóstico y se reusa
tal cual cuando llegue la fase de Firestore.

**Fase 0 y 1 (esta sesión): infraestructura Firebase + login como primer
APK distribuible** — a propósito antes que el motor de sync (El dueño: "es lo
primero que me gustaría distribuir").

- `applicationId`/`namespace` de la companion pasó de `com.example.la_plazoleta`
  (placeholder de siempre) a `com.laplazoleta.companion`, pedido para poder
  registrar la app en Firebase — `android/app/build.gradle.kts` y
  `MainActivity.kt` movido a su nuevo paquete.
- Proyecto Firebase nuevo ("La Plazoleta", `la-plazoleta-3f77b`, plan Spark)
  creado con browser automation guiada por el dueño (login con su propia cuenta
  de Google, `tu-cuenta@ejemplo.com`) — Authentication con Google y
  Correo/contraseña habilitados, Firestore creado (sin usar todavía, es de
  la próxima fase), app Android registrada con la huella SHA-1 de la firma
  debug (`android/app/google-services.json`, no versionado — cada máquina de
  desarrollo necesita el suyo o compartir este archivo aparte).
- `firebase_core`, `firebase_auth`, `google_sign_in` (v7 — API nueva:
  `GoogleSignIn.instance.initialize(serverClientId:)` +
  `.authenticate()`, ya no el `GoogleSignIn().signIn()` de antes) agregados a
  `pubspec.yaml`. Plugin `com.google.gms.google-services` en
  `android/settings.gradle.kts`/`android/app/build.gradle.kts`.
- `lib/companion/autenticacion.dart`: Google o email/contraseña, todo
  detrás de `emailAutorizadoCompanion` — **una sola cuenta autorizada para
  toda la companion** (El dueño: "una sola cuenta para todo"), sin lista
  dinámica ni panel — el selector de usuario/turno de
  `pantalla_elegir_usuario.dart` sigue siendo un concepto totalmente aparte.
- `lib/companion/pantalla_login.dart`: primera pantalla de la companion,
  con el kit de diseño existente (`tema/`) — "Continuar con Google" o
  formulario de registro/login por email. Con el mismo patrón `DePrueba` que
  ya usaba el proyecto (`resolverServicioCompanion`, `ImpresionControlador`)
  para poder testear sin tocar el plugin real de Firebase.
- `lib/companion/companion_app.dart`: nueva `PuertaDeEntradaCompanion`
  (pública a propósito, para poder testearla) delante de todo lo demás —
  escucha `authStateChanges()` y muestra `PantallaLogin` hasta que la cuenta
  autorizada esté firmada; recién ahí sigue el flujo de siempre
  (emparejamiento con la PC, elegir usuario). Todavía no cambia nada de
  cómo habla con la PC — eso es la próxima fase.
- Tests nuevos: `test/companion/pantalla_login_test.dart` (Google
  autorizado/no autorizado/cancelado, registro con contraseña débil, login
  con campos vacíos — todo con `firebase_auth` simulado vía `mocktail`, sin
  tocar el plugin real) y `test/companion/companion_app_test.dart` (la
  puerta de entrada con un stream falso: sin emitir todavía, sin sesión, con
  cuenta no autorizada, con la autorizada).
- Suite completa: 1031 tests, analyzer limpio, `flutter build apk --debug`
  compila. **Prueba real hecha** (El dueño, 2026-09-18): instaló el APK y el
  login con Google anduvo contra su cuenta real — primera vez que el
  proyecto habla con un servicio de Google de verdad. Falta confirmar que el
  resto de la companion (emparejamiento con la PC, elegir usuario, menú)
  sigue andando igual después de loguearse, sin haberse tocado.
- Riesgo anotado, no resuelto: el proyecto firma release con la firma de
  debug (`build.gradle.kts`, TODO ya señalado ahí) — Google Sign-In quedó
  registrado contra ese SHA-1; si el día de mañana se pasa a una firma de
  release de verdad, hay que volver a agregar ese SHA-1 en la consola de
  Firebase o el login con Google deja de andar.

**Migración histórica (El dueño, 2026-09-18: "cómo migramos TODOS los datos
actuales"), hecha** — migración de drift v30→v31
(`lib/data/database.dart`, `schemaVersion` ahora 31): a las filas de antes
de la migración v29→v30 que quedaron con `global_id` NULL a propósito
(nunca se les inventó uno), esta les asigna uno nuevo y les completa
`origen_dispositivo`/`actualizado_en` — con la fecha REAL de cada fila
(`productos.creado_en`, `sesiones_de_caja.fecha_apertura`, `ventas.fecha`,
`pendientes.fecha_creacion`; `lineas_de_venta`/`pagos` toman la fecha de su
venta; categorías/proveedores/clientes, sin fecha propia, quedan en época 0
a propósito), nunca "ahora" — evita que una venta vieja parezca "más nueva"
que una edición de ayer en un conflicto de sync futuro. Los 4 logs de
solo-inserción (`movimientos_de_stock`/`movimientos_de_caja`/
`arqueos_intermedios`/`historial_de_precios`) no tienen `actualizado_en`
(usan `id` como cursor), así que solo necesitan la identidad. Contado
contra la base real de el dueño antes de escribir esto: ~650 de ~1100 filas
totales entre las 13 tablas no tenían `global_id` — todas coordinadas para
entrar cómodas en el límite gratis de Firestore (20.000 escrituras/día).
Test real de upgrade `test/data/migracion_v31_test.dart` (mismo patrón que
`migracion_v30_test.dart` — abre un archivo real, no en memoria, la única
forma de ejercitar `onUpgrade`); tuvo que actualizarse
`migracion_v30_test.dart` también, porque al abrir una base v29 con el
código de hoy corren las dos migraciones seguidas (v29→v30 y v30→v31 en la
misma apertura) — dos aserciones que esperaban `globalId: isNull` pasan a
`isNotNull`, correctamente. Suite completa: 1032 tests, analyzer limpio.
**Corre sola la próxima vez que el dueño abra la app de escritorio** — se hizo
un backup de la base real primero
(`la_plazoleta.sqlite.backup-pre-migracion-v31-20260918-123122`), mismo
criterio que los backups anteriores del proyecto.

**Fase 1b — login del escritorio con la misma cuenta, HECHA**. Límite real
de plataforma: `google_sign_in` no tiene implementación para Windows (tabla
de soporte oficial Android/iOS/macOS/Web nada más) — El dueño eligió la
alternativa con más trabajo en vez de resignarse a un login por contraseña
en el escritorio (2026-09-18: "que abra una ventana en Chrome... y luego
volver a la app").

- `lib/data/autenticacion_escritorio.dart` (`iniciarSesionConGoogleDesdeEscritorio`):
  flujo real de OAuth 2.0 con PKCE — abre el navegador del sistema
  (`url_launcher`) contra un cliente OAuth nuevo tipo "App de escritorio"
  (Google Cloud Console, no el "Web client" que generó Firebase solo, `id`
  `341561955732-3ueijn295cd4i256prsfqo89rc3s31h5...`), levanta un
  `HttpServer` efímero con `shelf` (mismo paquete que ya usaba
  `servidor_companion.dart`, Regla 3) para recibir el código de vuelta en
  `localhost:<puerto libre>`, valida un `state` random contra CSRF, canjea
  el código por tokens (`https://oauth2.googleapis.com/token`, con
  `client_secret` — Google lo exige para este tipo de cliente aunque no lo
  trate como secreto real de una app instalada) y llama al mismo
  `signInWithCredential` que ya usa la companion.
- `lib/firebase_options.dart`/`lib/firebase_init.dart`: Firebase no tiene una
  app nativa de Windows en la consola — el soporte de escritorio reusa la
  configuración de una app "Web" nueva del mismo proyecto
  (`la-plazoleta-3f77b`, alias "La Plazoleta escritorio").
  `inicializarFirebaseEscritorio()` es idempotente (chequea
  `Firebase.apps.isNotEmpty`) porque se llama desde más de un lugar
  (`main.dart` al arrancar, en segundo plano; `ConfiguracionControlador` por
  si Configuración se abre más rápido que ese arranque).
- Sección nueva en Configuración → "Cuenta de Google" (`pantalla_configuracion.dart`,
  `_SeccionCuentaGoogle`): botón "Conectar cuenta de Google", nunca bloquea
  el arranque ni Venta (`CLAUDE.md`, "arranque vs. operación") — es un paso
  de una sola vez, la sesión de Firebase Auth queda guardada sola de ahí en
  más (confirmado: persiste entre reinicios en Windows igual que en
  Android).
- Ambas cuentas (Google en el celular, OAuth propio en el escritorio) inician
  sesión con el mismo proveedor de Google — Firebase las resuelve al MISMO
  usuario (mismo `uid`), así que no hizo falta ningún mecanismo de "vincular
  cuentas": es una sola identidad real para los dos dispositivos.
- Riesgo anotado, no resuelto: si el día de mañana se pasa a firmar el APK
  con una clave de release de verdad (hoy usa la de debug), hay que volver a
  agregar ese SHA-1 en Firebase o el login con Google del celular deja de
  andar — no afecta al del escritorio (usa su propio cliente OAuth, sin
  SHA-1 de por medio).

**Fase 2 — motor de sync sobre Firestore, HECHA** (El dueño, 2026-09-18: "cómo
hacemos con las sync, es el principal problema"). Reemplaza (por ahora, se
suma a) el emparejamiento HTTP viejo — ver Fase 4 más abajo para cuándo se
retira del todo.

- Base de datos Firestore creada (`southamerica-east1`, São Paulo — la región
  más cercana a Bariloche disponible) y reglas de seguridad publicadas
  (`firestore.rules`, copia versionada de las reglas reales): todo bajo
  `negocios/{negocioId}/**` exige `request.auth.token.email ==
  'tu-cuenta@ejemplo.com'` — la única cuenta autorizada, la misma que ya
  usa el login de las dos plataformas.
- `lib/data/transporte_firestore.dart`: capa mínima que sabe de Firestore
  (subir una tanda de filas en un batch, `global_id` como id de documento;
  escuchar una colección entera con `snapshots()`) — `negocioIdFirestore`
  fijo (`'la-plazoleta'`, el dueño no tiene ni va a tener más de un local, no
  hace falta generar/coordinar un id entre dispositivos).
- `lib/data/sincronizacion_firestore.dart` (`SincronizacionFirestore`):
  el orquestador, reusa `repositorio_sincronizacion.dart` (`cambiosDesde`/
  `aplicarCambios`/`cursorMaximo`) sin tocarlo — pull en vivo por listener
  (casi instantáneo en cuanto los dos dispositivos tengan internet), push
  periódico (cada 20s, no atado a cada escritura — enganchar eso a las
  decenas de `repositorio_*.dart` que insertan una fila es un cambio de
  arquitectura más grande, fuera de esta entrega). Detalle real encontrado
  al escribirlo: los listeners de las 13 tablas son colecciones
  independientes que pueden avisar en cualquier orden entre sí — una
  `lineas_de_venta` podía avisar antes que su `ventas` y romper la clave
  foránea. Solución: los cambios entrantes se juntan en una cola por tabla y
  se aplican en el orden de `tablasSincronizables` (categorías/proveedores/
  productos antes que las ventas que los referencian), con reintento
  automático si una tanda falla (`aplicarCambios` es idempotente).
- PC y celular corren la misma clase, simétricos — no hay más "cliente" y
  "servidor" para esto. Desktop la arranca/para sola según
  `authStateChanges()` (`main.dart`); la companion la arranca una sola vez
  al llegar a `_PantallaInicial` (`companion_app.dart`,
  `_asegurarSyncFirestoreCompanion`, vive mientras dure el proceso) contra
  su base LOCAL (`base_local.dart`) — nunca la de la PC en vivo, así que no
  aplica la razón por la que el sync HTTP viejo evita sincronizar solo al
  arrancar.
- **Tests**: `repositorio_sincronizacion_test.dart` no cambió (sigue
  transporte-agnóstico). Nuevo `integration_test/sincronizacion_firestore_test.dart`
  (no un test de widget común — necesita el plugin real de
  `cloud_firestore`/`firebase_auth`, que no existe en `flutter test` normal):
  dos `AppDatabase` en memoria (simulan escritorio y celular), cada una con
  su `SincronizacionFirestore`, sincronizando de verdad contra el Firestore
  Emulator Suite (nunca el proyecto real) — confirma que una fila creada en
  una aparece en la otra. Para correrlo hace falta Java 21+ (el proyecto
  tenía Java 17, `firebase-tools` ya no lo soporta) y
  `firebase emulators:start --only firestore,auth --project demo-la-plazoleta`
  levantado aparte, con `firebase.json`/`firestore.rules` nuevos en la raíz
  del proyecto. `test/companion/companion_app_test.dart` necesitó un ajuste:
  `PuertaDeEntradaCompanion` ganó `iniciarSyncFirestoreDePrueba` (default
  `true`) para que los tests comunes no abran la base local real ni dejen un
  `Timer.periodic` colgado.
- Suite completa: 1032 tests (`flutter test`) + 1 test de integración
  (`flutter test integration_test/... -d windows`), analyzer limpio, los dos
  binarios compilan.
- **Falta probar con hardware real**: todo esto corrió contra el emulador y
  compiló en las dos plataformas, pero todavía no se probó la sincronización
  real PC↔celular con las cuentas reales conectadas — es el próximo paso
  antes de dar la fase por cerrada.

**Prueba con hardware real y bug real encontrado (2026-09-18)** — El dueño pidió
probar de punta a punta: push de todos los datos reales a Firestore, APK
nuevo al celular, desktop nuevo. Apareció un bug real de sync (no solo un
gap de cobertura): `_aplicarPendientes` en `sincronizacion_firestore.dart`
adelantaba el cursor de PUSH de una tabla al cursor de lo que acababa de
RECIBIR de Firestore ("para no reenviar de vuelta lo que ya llegó") — pero
una fila local vieja que nunca se había empujado podía tener un cursor más
bajo que lo recién recibido (`actualizado_en` NULL en cualquier fila
histórica de antes de que esa columna existiera), y adelantar el cursor la
excluía de cualquier empuje futuro para siempre. Dejó 11 de las 13
categorías reales de el dueño sin sincronizar, silenciosamente. Arreglado sacando
ese adelanto (el costo es reenviar alguna vez lo ya recibido — inofensivo,
`subirFilasAFirestore` escribe por `global_id`). Verificado documento por
documento contra la consola de Firebase después del fix: ventas 116/116,
productos 150/150, proveedores 19/19, categorías 13/13.

**Fase 4 — companion sin PC de verdad, no solo "se puede", HECHA
(2026-09-18)** — al probar el APK recién instalado, el dueño encontró que
igual pedía escanear el QR de emparejamiento antes de dejar hacer nada
("no debería tener que escanear ya, es innecesario"). La causa real: sacar
el gate de `companion_app.dart` no alcanzaba, porque CASI TODAS las
pantallas (incluida "Vender", la más importante) resolvían su
`ServicioCompanion` con un patrón que se quedaba en `null` para siempre sin
`conexion` — `PantallaElegirUsuario`, `_iniciarConexion`/`_revisarSesion`
del menú principal, Movimiento de caja, Consultar precio, Conteo de stock,
Productos y Carga histórica lo tenían. Todos arreglados con el mismo patrón
(`conexion == null ? ServicioCompanionOffline(PuertoLocal(...)) :
resolverServicioCompanion(conexion)`).

Con eso resuelto, además, se completó lo que Fase 2 había dejado para
después — `PuertoLocal`/`ServicioCompanion` ahora cubren TODO lo que antes
era exclusivo de `ClienteCompanion` salvo dos cosas que no tiene sentido que
dejen de serlo (actualización del .apk — el archivo se sirve desde la PC —
e imprimir ticket, que sigue necesitando la impresora/PDF de verdad de la
PC, ahora con aviso en vez de tirar si no hay PC):

- **`usuarios` se sumó a la sincronización** (migración v31→v32,
  `schemaVersion` 32) — hasta ahora estaba deliberadamente afuera
  ("autoridad exclusiva del escritorio", migración v29→v30) porque la
  companion siempre dependía de la PC; ya no aplica. Mismo tratamiento que
  categorías/proveedores/clientes: época 0 para filas viejas sin fecha
  propia. `usuarios` va primero en `tablasSincronizables` (otras tablas la
  referencian por `usuario_id`).
- **Arqueo** (`estadoCaja`, `calcularArqueoIntermedio`,
  `confirmarArqueoIntermedio`) — mismas fórmulas que ya usaba el servidor
  (`estadoCajaEnVivo`/`resumenDiaHistorico`/`calcularResumenCierre`/
  `lataEsperadaIntermedia`), corridas directo contra la base local.
- **Historial de ventas** (`historialDeVentas`, `anularVenta`,
  `detalleVenta`) y **Cierres** (`sesionesCerradas`) — mismo `listarDias`/
  `ticketDeVenta` de siempre; Cierres ya tenía una caché en disco para
  "sin conexión", ahora ese caso casi no pasa (solo si ni siquiera terminó
  el primer sync).
- **Carga histórica** completa (`guardarDiaHistorico`, `diasHistoricos`,
  `ventasDeDiaHistorico`, `resumenDiaHistorico`, `agregarVentasADiaHistorico`,
  `eliminarVentaHistorica`, `eliminarDiaHistorico`) — la más grande de las
  cuatro, con un helper nuevo (`_pendienteDesdeCompanion` en
  `puerto_local.dart`) que arma `VentaHistoricaPendiente` de dominio directo
  desde el DTO de la companion, sin la vuelta por JSON que hace el servidor.
- **Cobro por terminal Point directo desde el celular, sin pasar por la PC**
  (El dueño: "revisá cómo hacer para que el celular mande la orden
  directamente al posnet") — hallazgo clave: `cobro_posnet.dart` YA es un
  cliente HTTP puro contra `api.mercadopago.com`, nunca habló con hardware
  local; la terminal recibe la orden de los servidores de Mercado Pago sin
  importar qué dispositivo hizo el POST. Lo único que hacía falta:
  - Confirmado con el dueño (el token puede cobrar/cancelar cobros, no es un
    dato cualquiera): sincronizar `mpAccessToken`/`mpTerminalCobroId` a un
    documento propio de Firestore (`negocios/la-plazoleta/configuracion/cobro`),
    aparte de las 14 tablas — nunca mezclado con el resto de
    `configuracion_tabla`, que sigue sin sincronizarse. Escribe solo el
    escritorio (`SincronizacionFirestore._empujarConfigCobroSiHizoFalta`,
    compara contra lo último empujado para no escribir en cada tick de
    20s); lee solo la companion (`transporte_firestore.dart::leerConfigCobro`,
    lectura puntual, no un listener — esto cambia poquísimo).
  - `PuertoLocal` implementa el ciclo completo (`iniciarCobroPosnet`/
    `consultarEstadoPosnet`/`confirmarCobroPosnet`/
    `resolverCobroPosnetNoAprobado`/`cancelarCobroPosnet`/
    `cobrarVirtualAMano`) llamando directo a `data/cobro_posnet.dart`
    (`crearOrdenCobro`/`consultarOrden`/`cancelarOrdenCobro`) y persistiendo
    en la propia tabla local `ordenes_cobro_pendientes` (no sincronizada —
    es el rastro de un cobro que está pasando en ESTE dispositivo).
  - `dialogo_cobro_posnet_companion.dart` y `PantallaCarritoVenta` pasaron
    de `ClienteCompanion` a `ServicioCompanion` — `cliente` (solo para
    imprimir) pasó a ser nullable, con aviso en vez de tirar si no hay PC.
- Verificado en Firestore: el documento `configuracion/cobro` llegó con las
  credenciales reales después de relanzar el escritorio.
- **Falta probar con la terminal física de verdad** (cobrar por QR/Débito
  desde el celular sin la PC prendida) — todo lo de arriba compila, pasa
  analyzer y los 1033 tests, y el documento de credenciales confirmado en
  Firestore, pero la orden real a la terminal Point todavía no se disparó
  desde el celular en esta sesión (acción con plata real de por medio,
  mejor que la primera vez la haga el dueño mismo, supervisado).
- **Pendiente, no de código**: la instalación de producción de el dueño
  (`C:\LaPlazoleta\app\la_plazoleta.exe`) seguía corriendo el build de ANTES
  de todo esto — hay que copiarle el build nuevo y reiniciarla para que
  también empiece a empujar `usuarios`/`configuracion/cobro` y a beneficiarse
  del fix del cursor de push.

## Resuelto: la pantalla de venta al 100% (ítem 4)

Seis bugs reales de mostrador, todos arreglos chicos, todos con test que
reproduce el caso tal cual pasaría con un cliente esperando:

- **Mixto con el cliente cambiando de opinión cobraba mal** (el caso más
  frecuente que hay): efectivo en $0 igual redondeaba una venta 100%
  virtual, efectivo por el total igual cobraba el recargo de cigarrillos.
  La composición ahora se deriva de los montos (`clasificarComposicion`),
  no del botón apretado.
- **Escribir "varios" y elegirlo del dropdown crasheaba** — ahora abre el
  mismo diálogo de monto que Alt+V, y dejó de pintarse en rojo como stock
  bajo (nunca tuvo stock real).
- **Un pesable sin gramos o sin precio por kilo cargado crasheaba** al
  agregarlo — ahora avisa (`avisoBusqueda`) y no lo agrega, Regla 7.
- **Alta rápida con un código de un producto dado de baja fallaba en
  silencio** (escanear, escribir, tocar "Vender", nada) — ahora ofrece
  "Reactivar y vender" en su lugar.
- **Cobrar con Enter sin medio elegido no daba ninguna señal** — ahora
  avisa (`avisoCobro`) junto al botón, mismo criterio que el acuse de
  cobro.
- Los `Colors.red` de una revisión anterior ya no existían — se habían
  corregido en la pasada de fase 11, antes de este ítem.

Ver `DECISIONES.md` para el detalle de cada uno.

## Resuelto: tres correcciones tras revisar el demo_planilla.pdf

El dueño revisó el PDF de demo contra la planilla de papel real y encontró tres
problemas antes de que la app saliera al local:

- **El RETIRO nunca mostraba un número** cuando no había fijos cargados en el
  mes, aunque la opción de descontar fijos pendientes esté apagada (el
  default). El cálculo exigía los fijos sin condición. Ahora una sola función
  compartida (`retiroSugeridoDelMes`) solo los exige cuando la opción está
  prendida — la usan tanto la pantalla de Equilibrio como la planilla impresa.
- **La venta mixta repartía cada línea proporcionalmente entre efectivo y
  virtual**, dejando centavos en las grillas (ej. $281,25) que la planilla de
  papel nunca tuvo. El arreglo real: un renglón por grilla con el monto exacto
  de cada Pago de la venta, no un reparto por línea. `lib/domain/planilla.dart`
  (la función vieja de reparto) quedó sin uso y se borró.
- **La columna "VENDIDO" de reposición mostraba el costo real, no lo
  vendido** — mentía la etiqueta. Ahora son tres columnas separadas: VENDIDO
  (precio), A SEPARAR (costo real + colchón), SEPARADO. Se agregó también la
  línea de "vendido sin costo cargado" (Regla 5) y se filtran los proveedores
  sin movimiento en el período.

Detalle completo de las tres en `DECISIONES.md`.

## Otros pendientes sueltos

- **Validación real del dominio**: correr los mismos días de venta en
  paralelo contra el sistema HTML anterior y comparar los cierres. Los 486
  tests en verde prueban que el código hace lo que se le pidió, no que el
  modelo de negocio sea correcto — esa prueba todavía no se hizo.
- **Dos caminos para reimprimir un ticket, sin unificar**: uno en la
  pantalla de Impresión (busca por fecha/número), otro que podría vivir en
  el detalle de un día del Historial (ya tiene la lista de ventas del día
  ahí mismo). Ninguno se sacó, no se decidió si conviene fusionarlos.
- **Prueba real de impresión física** contra la terminal Point del local
  (Newland N950): las credenciales ya están cargadas y el código está
  escrito, pero nunca se disparó una impresión de prueba real (consume un
  ticket de papel) — queda pendiente de que el dueño la corra o la autorice
  explícitamente.
- **Carga adelantada sin mover**: el colchón de reposición vive en la
  pantalla de Reposición, la carga de fijos vive en Equilibrio, y la
  configuración de Mercado Pago/carpetas vive en Respaldo/Impresión — se
  decidió a propósito no migrar eso a la pantalla de Configuración cuando
  esta se cerró (fase 8). No es un olvido.
- **Limitación conocida — atribución producto→medio en una venta mixta de
  varios productos** (`lib/data/planilla_dia.dart`): desde el fix del ítem
  3 (arriba), cada renglón de la planilla es el monto exacto de un `Pago`
  de la venta, ya sin decimales ni reparto proporcional. Lo que sigue sin
  poder saberse desde la planilla es, dentro de una venta mixta con **más
  de un producto**, cuál de ellos se pagó con cuál medio — el DETALLE de
  cada renglón lista todos los productos de la venta entera, no solo los
  que corresponden a ese medio puntual, porque el sistema no guarda esa
  atribución por línea. Los montos de cada grilla y el arqueo salen bien
  igual; es solo información que no está. Arreglarlo pide guardar
  atribución de medio de pago por línea, un cambio de modelo más grande —
  confirmado con el dueño que queda así por ahora.

## Resuelto: "sin stock, no aparece en ventas" (reemplaza a Regla 8) — versión inicial

El dueño, 2026-09-06: "si algo no hay stock, el producto no aparece en
ventas. Luego refinamos ese apartado" — pedido explícito, revierte a
propósito la regla vieja de `REGLAS-NEGOCIO.md` §8 ("el stock informa,
nunca bloquea"). Detalle técnico completo, incluidos los casos borde que
quedan sin resolver a propósito (accesos directos, oversell dentro de una
misma venta, productos inactivos), en `TRAMPAS.md` ("Sin stock, no aparece
en ventas").

- `tieneStock` (`lib/data/busqueda_productos.dart`) es el único lugar que
  decide esto — "Varios" siempre cuenta como que tiene, un pesable mira
  `stockGramos`, el resto mira `stock`. `buscarProductos` lo aplica tanto
  al match exacto por código de barras como a la búsqueda por nombre.
- Escanear el código de un producto que existe pero está en 0 **no**
  ofrece "dar de alta" (sería un duplicado de algo real) — muestra "Sin
  stock — no se puede vender" en su lugar
  (`VentaControlador.productoSinStockEncontrado`,
  `columna_busqueda.dart`).
- Se usó de paso para cargar 63 productos nuevos que llegaron sin stock
  todavía (`lista_productos_proveedores.csv`, proveedores Distribuidora/Puelche/
  Varios Eli — nuevo, código `VE` — y ocho sin proveedor conocido): quedan
  en el catálogo pero invisibles en Venta hasta que el dueño haga el conteo
  físico y cargue el stock real.

## Resuelto: aprovechar la pantalla de venta a 1920×1080

El dueño, 2026-09-06: "aprovechemos la pantalla de ventas al máximo" — el
carrito se veía desaprovechado y "todo se ve chico en general", más dos
pedidos concretos que salieron de esa conversación: información pobre en
el carrito + sacar la eliminación de línea por teclado, y un apartado de
descuento en la columna de cobro. Plan completo (contexto, alternativas
consideradas) en el historial de la sesión — acá el resumen de lo que
quedó construido:

- **Carrito** (`columna_carrito.dart`): fila más ancha
  (`anchoFilaCarrito` 520→640, ver tabla de Medidas en `DISENO.md`), con
  una columna nueva de precio unitario (`LineaVentaPorUnidad.precioUnitarioCentavos`,
  ya existía en el dominio) y un ícono de tacho por fila. La columna de
  precio unitario se esconde sola vía `LayoutBuilder` cuando no entra
  (piso mínimo + barra desplegada, ver `TRAMPAS.md`).
- **Eliminar una línea es con mouse, no con teclado**: `Backspace` con el
  campo vacío se sacó por completo (`VentaControlador.borrarUltimaLinea`
  ya no existe) — reemplazado por `eliminarLinea(index)`, cualquier línea,
  no solo la última.
- **Descuento sobre el total** (Regla 17, generalizada — antes solo
  hardcodeada para Cliente Frecuente, 15%): nuevo dominio
  `lib/domain/descuento.dart` (`calcularDescuento`, `TipoDescuento`),
  `calcularTotalVenta` gana el paso recargo→**descuento**→redondeo.
  `Ventas.descuentoCentavos` ya existía en el esquema (reservado para
  esto, nunca poblado) — sin migración nueva. UI en `columna_cobro.dart`:
  el cajero elige $ o %, se ve en vivo en el desglose y en el ticket
  (`DesgloseTicket`, `pdf_ticket.dart`, `contenidoTicketPosnetMp`).
- **Tipografía "un paso arriba", solo en venta**: nombre/subtotal del
  carrito y de la búsqueda, y las etiquetas de todos los botones de venta
  (medios de pago, "Cobrar", accesos directos) pasan de `cuerpo`/16 a
  `subtitulo`/19 — corrige que el precio real de la búsqueda ya estaba en
  ese tamaño y el resto de la fila se había quedado atrás. Detalle en
  `DISENO.md`, "Escala tipográfica". Ninguna otra pantalla cambia.

## Resuelto: ajuste de cantidad en el carrito, posnet directo desde el atajo, y lápiz en accesos directos

El dueño, 2026-09-06, mismo día que lo anterior: "que en el carrito se pueda
ajustar la cantidad tanto con botones de suma o resta como haciendo doble
click, y debería haber una manera de editar los atajos rápidos", más una
interjección a mitad de la conversación: "los atajos en lugar de
seleccionar el medio de pago únicamente, también manden la orden al
posnet en caso de ser por medios virtuales".

- **Ajustar cantidad con mouse** (`columna_carrito.dart`,
  `venta_controlador.dart`): botones "−"/"+" al lado de la cantidad, solo
  para líneas por unidad (un pesable no suma/resta de a uno) — restar en
  1 saca la línea entera (`ajustarCantidad`), mismo criterio que ya usaba
  el ícono de tacho. Doble clic sobre la cantidad o los gramos abre
  `dialogo_editar_cantidad.dart` para tipear el valor exacto de un tirón
  (anda en las dos formas de línea, con o sin los botones al lado). Los
  botones "−"/"+" comparten el mismo umbral `hayLugarParaDetalle` que ya
  escondía el precio unitario en el piso mínimo (ver `TRAMPAS.md`, "la
  fila del carrito necesita `LayoutBuilder`" — segunda vuelta).
- **`Alt+Q`/`Alt+D` mandan la orden al posnet, no solo eligen el canal**
  (`pantalla_venta.dart`, `columna_cobro.dart`): antes eran dos pasos
  (elegir medio, después apretar "Cobrar"); ahora un solo atajo hace las
  dos cosas para QR/Débito, reusando el `cobrarOAbrirPosnet` que ya
  existía desde la fase 12. `Alt+E`/`Alt+X` no cambian — efectivo y mixto
  no pasan por Point. Ver `TRAMPAS.md` por el efecto colateral en tests
  que usaban esos atajos solo para llegar a un estado, no para probarlos.
- **Lápiz en accesos directos ya asignados** (`columna_busqueda.dart`):
  antes solo se podía reeditar un directo con mantener presionado (sin
  pista visual de que existía esa forma); ahora un ícono de lápiz
  flotante en la esquina abre el mismo editor con un clic simple. El
  mantener presionado se deja como está, no se saca.

## Resuelto: cobro manual en el desktop, y un bug real de recargo en la companion

El dueño, 2026-09-08: "necesito cobro manual en el desktop ya que al poner
los atajos rápidos no hay más modal para seleccionarlo" — el paso único
de Alt+Q/Alt+D (arriba, 2026-09-06) le sacó la posibilidad de cobrar por
QR/Débito sin tocar la terminal Point salvo que la orden fallara primero.

- **Alt+Q/Alt+D vuelven a ser de dos pasos** (`pantalla_venta.dart`,
  `columna_cobro.dart`): eligen el canal nada más; "Cobrar" (Enter con el
  campo vacío, o el botón) recién ahí abre el diálogo de Point. Revierte
  el paso único de la entrada anterior — decisión explícita de el dueño,
  eligiendo la opción "aditiva" que se le ofreció (agregar un atajo nuevo
  en vez de tocar el existente) para minimizar el riesgo sobre un flujo
  que ya usa todos los días.
- **`Alt+M`, cobro manual sin pasar por la terminal** — con QR/Débito ya
  elegido, cobra directo (`cobrarActual()`, mismo camino que "Cobrar a
  mano" del diálogo de Point cuando la orden falla, pero elegible desde
  el arranque). Con mouse, un botón "A mano" aparece al lado de "Cobrar"
  (comparte la fila para no sumar altura — a 1366×768 la columna de
  cobro no tenía margen vertical de sobra, lo agarró un test real de
  overflow al escribir esto).
- `CLAUDE.md`, sección Atajos, actualizada para reflejar el cambio.

**Bug real, encontrado revisando "que los recargos se apliquen
correctamente en las dos apps" (mismo pedido de el dueño)**: la carga
histórica de la companion (`pantalla_carga_historica.dart`,
`_ArmadorDeVentaState._confirmarVenta`) mandaba el medio tal cual se
apretó ("mixto" si se eligió Mixto) sin importar el monto en efectivo
tipeado — el mismo error que ya se había encontrado y arreglado en el
escritorio meses atrás (`VentaControlador.confirmarMixto`, ver
`DECISIONES.md`): un "mixto" con el efectivo en $0 es virtual puro y no
debería redondear (Regla 2); un "mixto" con el efectivo igual al total es
efectivo puro y no debería llevar el recargo de cigarrillos (Regla 6).
Mandar "mixto" tal cual en cualquiera de los dos casos cobraba de más en
una carga histórica — plata que termina en los números de ganancia que
esta pantalla existe para calcular. Arreglado reclasificando con la misma
`clasificarComposicion` del dominio antes de mandar nada (Regla 3); si
deja de ser mixto de verdad, vuelve a pedirle el total al servidor con el
medio correcto antes de guardar la venta pendiente. Verificado el resto
de los caminos: la venta en vivo del celular no ofrece Mixto (decisión ya
tomada, sin exposición a este bug), y el servidor (`servidor_companion.dart`)
no necesitaba cambios — la reclasificación es responsabilidad del cliente,
igual que en el escritorio.

## Resuelto: recargo de cigarrillos sueltos (Regla 6)

El dueño, 2026-09-10: "revisá en las configs globales, que los puchos sueltos
también deben tener recargo por MP, sin eso los cálculos dan mal. son $50
por cigarro, solo eso." Investigado antes de tocar nada: el CÓDIGO ya
estaba bien — `recargoCigarrillos` (`lib/domain/recargo_cigarrillos.dart`)
ya multiplicaba `cantidadSueltos × cigarroSueltoCentavos` correctamente, y
los cuatro lugares que arman `ConfigRecargoCigarrillos` desde la
configuración real (venta en vivo, editor de venta, carga histórica,
servidor companion) ya leían `config.recargoSueltoCentavos` sin
excepción. El problema era puramente el VALOR: el default de esquema
estaba en 0 (`REGLAS-NEGOCIO.md` §6 decía explícitamente "Cigarros
sueltos: sin recargo" — cierto hasta hoy, ya no).

- `REGLAS-NEGOCIO.md` actualizado: "Cigarros sueltos: 50 por cigarro".
- `lib/data/tables/configuracion.dart`: default de
  `recargoSueltoCentavos` de `0` a `5000` — alcanza para una base nueva,
  no para una que ya existe.
- Migración v23→v24 (`database.dart`): corrige el valor ya grabado en
  bases existentes (mismo motivo que v15→v16 con `barraLateralPlegada` —
  cambiar el default de Dart no alcanza para una fila que ya existe).
- `test/domain/recargo_cigarrillos_test.dart`: los dos tests que
  documentaban "sueltos sin recargo" como LA regla se actualizaron para
  reflejar la regla nueva (sueltos sí generan recargo en pago virtual,
  $50 c/u); se agregó un test nuevo que deja explícito que en efectivo
  puro siguen sin recargo (eso no cambió — ningún cigarrillo lleva
  recargo en efectivo, Regla 6).

Verificado con `flutter analyze` (limpio) y la suite completa (850 tests,
todos verdes).

## Resuelto: primera tanda de pulido UI/UX de la companion

El dueño, 2026-09-10: "pulí la UI/UX de los distintos apartados para que la
app se sienta cómoda de usar y no un bodrio". Auditoría de código primero
(sin tocar nada) — patrón de fondo encontrado: no es una pantalla mal
hecha en particular, es inconsistencia entre pantallas (la mitad ya sigue
el kit compartido, la otra mitad no). De los ~11 hallazgos, se resolvieron
los de mayor impacto/menor riesgo esta ronda; el resto queda anotado en
"Próximos pasos" para decidir juntos antes de tocarlos (son más rediseño
que arreglo puntual):

- **Bug real: "Cobrar" podía quedar trabado para siempre**
  (`pantalla_carrito_venta.dart`, `_cobrarPosnet`) — a diferencia de
  `_cobrarEfectivo`/`_cobrarAMano`, no tenía `try/finally` alrededor del
  diálogo de posnet. Si `_resultado` todavía era null (el cálculo previo
  había fallado) al tocar "Confirmar", `_resultado!.totalCentavos` tiraba
  una excepción sin capturar antes de siquiera abrir el diálogo — el botón
  quedaba con el spinner girando para siempre, sin ningún error visible,
  única salida cerrar la pantalla. Corregido con el mismo patrón que los
  otros dos caminos, más un mensaje explícito si falta el resultado.
- **Borrar una venta de un día histórico no pedía confirmación**
  (`pantalla_carga_historica.dart`, `_eliminarVenta`) — a diferencia de
  "Borrar día completo", que sí la tenía: la acción más chica y más fácil
  de tocar por error (una fila en una lista larga) tenía MENOS protección
  que la más grande. Mismo diálogo de confirmación ahora en las dos.
- **Errores de red mostraban la excepción cruda** (23 lugares repartidos
  en casi toda la companion) — el escenario más común de esta app (WiFi
  débil, PC apagada o dormida) se veía como `SocketException: Failed host
  lookup...`, técnico y en inglés, en la pantalla que atiende el
  mostrador. `lib/companion/mensaje_error.dart` nuevo (`mensajeDeError`)
  traduce `SocketException`/`HttpException`/`TimeoutException`/
  `FormatException` a frases en español, y deja pasar tal cual el mensaje
  de `ErrorCompanion` (ya legible, lo arma el servidor) — un solo lugar
  (Regla 3), usado en las ~14 pantallas que antes mostraban `'$e'` o
  `'algo: $e'` directo.

Verificado con `flutter analyze` (limpio) y los 849 tests (todos verdes).

**Nota real del proceso**: un `sed` mal escapado (para hacer el reemplazo
mecánico de `'$e'`) corrompió de paso ~9 strings no relacionadas en 7
archivos (comentarios, literales `''`, un `'/kg'`) — se detectó porque
`flutter analyze` dejó de estar limpio, y se reparó cada caso a mano
comparando contra el contenido original antes de seguir. Ningún archivo
quedó con la corrupción sin corregir (confirmado con `flutter analyze`
limpio + suite completa verde al final).

## Resuelto: descuento en el carrito de la companion (Regla 17 generalizada)

El dueño, 2026-09-10: "el carrito del celular no tiene para descuento" — cierto,
era una exclusión explícita de la primera versión (`pantalla_carrito_venta.dart`,
2026-09-07: "Efectivo, QR y Débito... sin Mixto ni descuento"). Agregado con el
mismo mecanismo que el escritorio, cableado por las tres capas:

- **Dominio**: sin cambios — `calcularTotalVenta`/`calcularDescuento`
  (Regla 17) ya estaban generalizados, nunca fueron exclusivos del
  escritorio.
- **Servidor** (`servidor_companion.dart`): `_calcularResultado`/
  `_registrarVentaDesdeBody` ganaron `tipoDescuento`/`valorDescuento`
  opcionales; `_descuentoDesdeBody` los lee del JSON (`null` = sin
  descuento, compatibilidad con una companion vieja que todavía no los
  manda). Los cuatro endpoints de venta (`/ventas/calcular`, `/ventas/cobrar`,
  `/ventas/posnet/iniciar`, `/ventas/posnet/confirmar`) los reciben y
  reenvían — `posnet/confirmar` necesita que el celular se los vuelva a
  mandar (recalcula el total desde cero, no reusa el de la orden ya creada).
- **Cliente** (`cliente_companion.dart`, `dialogo_cobro_posnet_companion.dart`):
  mismos parámetros opcionales en los cinco métodos que calculan/cobran una
  venta, un solo helper `_descuentoAJson` para no repetir el fragmento de
  JSON cinco veces.
- **UI** (`pantalla_carrito_venta.dart`): bloque nuevo con los mismos dos
  botones $/% del escritorio y un `CampoPlata` del kit — `parsearARS` sirve
  igual de bien para plata que para porcentaje (mismo truco de "dos
  decimales" que ya usa `VentaControlador`: $15,00 = 1500 centavos, 15,00%
  = 1500 basis points). El total no se recalcula localmente (a diferencia
  del escritorio, que es dominio puro) — pide `calcularVenta` de nuevo,
  debounced, si ya había un medio elegido; sin medio elegido el descuento
  se aplica recién cuando se elige uno (necesita saber el medio para el
  recargo de cigarrillos/redondeo antes de poder llamar al servidor).
- Tests nuevos en `test/servidor/servidor_companion_test.dart` (monto,
  porcentaje, sin descuento, y que se aplica al registrar la venta no solo
  al calcular) — ver el comentario ahí sobre por qué `lineaCoca` fija su
  propio precio (112000) sin importar el que se le pasó a
  `insertarProducto`.

Sigue excluido, a propósito, Mixto (no pedido esta vez).

Verificado con `flutter analyze` (limpio) y la suite completa (854 tests,
todos verdes).

## Resuelto: organización de elementos en la companion (tercera tanda)

El dueño, 2026-09-10: "quiero que se piense mejor la organización de los
elementos de todas las pantallas para evitar fricciones" — distinto de
las dos tandas anteriores (esas fueron consistencia visual y manejo de
errores; esto es específicamente qué elemento está dónde, en qué orden,
cómo se agrupa). Auditoría primero, cuatro hallazgos:

- **Menú principal**: los 6 accesos pasan de una grilla pareja (mismo
  peso, orden de construcción) a dos grupos — "Uso diario" (Consultar
  precio, Gasto rápido, Conteo de stock) y "Gestión y reportes" (Precios y
  alta, Cargar día histórico, Historial de ventas). El agrupamiento no se
  podía inferir del código — es un dato del negocio de el dueño, confirmado
  antes de tocar nada: esos tres son los que se usan todos los días.
- **Arqueo**: efectivo, redondeo, Mercado Pago, lata y cigarrillos
  estaban apilados en un solo `Bloque` como seis líneas sin agrupar,
  aunque son tres cajas conceptualmente distintas. Separado en tres
  bloques ("Efectivo", "Mercado Pago", "Lata de cigarrillos") — mismo
  criterio que ya usa el cierre real del escritorio (Patrón B, Arqueo
  separado del resto).
- **Conteo de stock**: el mensaje de resultado del guardado aparecía
  arriba de la lista, pero el botón de guardar (que lo dispara) está
  abajo — en una lista de 30-80 productos, casi siempre scrolleada al
  tocar guardar, el resultado quedaba invisible fuera de pantalla. Pasó a
  `SnackBar` (siempre visible). De paso, el botón de guardar ahora muestra
  "Guardar conteo (12 de 47)" — un contador en vivo de cuánto se lleva
  tipeado, útil en una tarea larga sin ningún indicio de progreso hasta
  ahora (cada `TextEditingController` de conteo ganó un listener que
  dispara `setState`, antes tipear no reconstruía nada).
- **Historial de ventas**: los dos filtros (período, medio de pago) se
  mostraban como dos filas de chips idénticas sin ninguna etiqueta que
  las distinga. Cada fila ganó un título chico ("Período"/"Medio de
  pago").

**Ya bien organizadas, sin cambios** (la auditoría no encontró fricción
real, o el orden actual refleja una decisión de el dueño ya documentada en
el propio código): Carga histórica, carrito de venta, formulario de
Precios, Consultar precio, Gasto rápido, apertura de emergencia.

Verificado con `flutter analyze` (limpio) y la suite completa (850 tests,
todos verdes).

## Resuelto: crash en Arqueo por desfasaje companion/escritorio

El dueño, 2026-09-10, probando contra la PC real: "type 'null' is not a
subtype of type 'int' in type cast" al abrir Arqueo. Causa: los dos campos
nuevos de esa misma sesión (`redondeoAcumuladoCentavos`/
`lataInicialCentavos`, ver "Resuelto: visibilidad de la lata y del
redondeo" arriba) se parseaban con cast estricto (`as int`) del lado del
celular — la companion ya se había publicado, pero el escritorio de la PC
del local todavía no se reconstruyó ni se copió (no hay script para eso
todavía, a diferencia de la companion), así que el servidor viejo no manda
esas claves y el cast daba `null`. Detalle completo del mecanismo en
`TRAMPAS.md` ("Agregar un campo nuevo a una respuesta del servidor
companion..."). Arreglado con `as int?` + `?? 0` — degrada a mostrar 0 en
vez de crashear mientras la PC no se actualice; republicado como
`1.0.0+2028`.

**Pendiente real, no resuelto por este fix**: el escritorio de la PC del
local sigue sin el build de hoy — Arqueo ya no crashea, pero "Redondeo
acumulado" y "Lata (arrastrada de antes de hoy)" van a mostrar 0 hasta que
alguien reconstruya (`flutter build windows`) y copie el `.exe` nuevo a la
PC real. Sin script propio para ese paso todavía (`CLAUDE.md` ya lo
menciona como pendiente).

## Resuelto: segunda tanda de pulido UI/UX de la companion

El dueño, 2026-09-10: "quiero que sigas con todo eso" — completa la lista que
había quedado anotada en "Próximos pasos" tras la primera tanda:

- **El menú principal ahora usa el kit compartido**: `TextField` crudo →
  `Bloque` + `CampoTexto` (que ganó `prefixIcon`/`suffixIcon` opcionales,
  `lib/ui/comun/campo_texto.dart` — nadie más los usa todavía, default
  `null` no le cambia nada a las pantallas del escritorio); `Card` → `_Tile`
  reescrito con `Bloque` + `Material(type: MaterialType.transparency)` +
  `InkWell` (mismo gotcha de siempre: el `Container` de `Bloque` tapa el
  ripple si no). De paso, el mismo `TextField` crudo apareció en Precios,
  Consultar precio y Carga histórica (la auditoría solo había marcado el
  menú) — las cuatro pantallas quedaron consistentes, no solo la principal.
- **`EstadoVacio` del kit, en los 6 lugares que reinventaban su propio
  estado vacío**: menú (`Sin resultados`), Carga histórica (tres: sin días
  cargados, sin ventas del día, sin resultados de búsqueda), Historial de
  ventas (sin ventas en el período), carrito de venta (carrito vacío).
- **Aviso al salir con datos sin guardar** (`PopScope`, `confirmarSalirSinGuardar`
  nuevo en `navegacion.dart`) — Precios (formulario de alta/edición) y
  Conteo de stock (hasta 30-80 campos tipeados recorriendo la góndola, el
  caso más grave). `canPop` siempre `false`, la decisión de si hay algo
  sin guardar se evalúa recién dentro de `onPopInvokedWithResult` — un
  `canPop` calculado en el build anterior podía quedar desactualizado
  porque los campos no pasan por `setState` en cada tecla.
- **Doble-tap en los 6 accesos del menú ya no pushea la misma pantalla
  dos veces** — un flag `_navegando` deshabilita los tiles mientras la
  navegación anterior sigue en vuelo.
- **Pull-to-refresh** en Historial de ventas, Precios y la lista de
  proveedores de Conteo de stock (antes solo Arqueo lo tenía). El botón
  de refresh del AppBar de Arqueo NO se sacó pese a que la auditoría lo
  marcó como redundante: es la única forma de reintentar cuando la
  primera carga falla (`_error != null` no es una superficie scrolleable,
  `RefreshIndicator` no alcanza ahí) — sacarlo hubiera sido una regresión
  real, no una limpieza.
- **No se tocó** la jerarquía visual entre los 6 accesos del menú (ítem de
  la auditoría): darle más peso a "Conteo de stock" que a "Cargar día
  histórico" es una decisión de producto (qué se usa más) que no hay
  forma de inferir del código — queda abierto hasta que haya un criterio
  real para decidirlo, no una talla única.

Verificado con `flutter analyze` (limpio) y la suite completa (850 tests,
todos verdes) después de cada cambio.

## Resuelto: teclado fantasma al volver de un apartado (companion)

Bug real reportado por el dueño, 2026-09-10: "si en un apartado ingreso al
teclado, al volver al menú principal usando el botón de atrás vuelve a
salir el teclado". Causa: cada ruta de Flutter tiene su propio
`FocusScopeNode`, que recuerda qué widget tenía el foco antes de que se
pusheara otra ruta encima; al hacer `pop`, el `Navigator` le devuelve el
foco solo a ese mismo widget — si era un campo de texto, el teclado se
abre de nuevo sin que el usuario haya tocado nada. No era un problema solo
del menú principal: pasa en cualquier pantalla de la companion con un
buscador que además navega a otra pantalla (Precios, el escáner de código
de barras que comparten Precios/Consultar precio, Carga histórica,
Conteo de stock).

`lib/companion/navegacion.dart` nuevo (`pushSinTeclado`) — reemplaza cada
`Navigator.of(context).push(MaterialPageRoute(...))` de `lib/companion/`
(diez sitios: menú principal ×8, Precios, escáner de código de barras,
Conteo de stock ×2, Carga histórica ×3). Un solo mecanismo (Regla 3) en
vez de desenfocar a mano después de cada push.

**Primer intento incompleto, corregido el mismo día** (El dueño: "sigue
pasando el mismo bug"): desenfocar recién DESPUÉS de que se resuelve el
`push` (es decir, después del `pop`) no alcanzaba — la memoria de
`focusedChild` que el `Navigator` restaura al volver se graba en el
momento en que se PIERDE el foco (cuando se pushea la ruta nueva), no en
el momento en que se recupera. El desenfoque real tiene que ir ANTES del
`push`, no después — detalle completo del mecanismo en `TRAMPAS.md`.

**Segundo intento, todavía no conforme, resuelto con un cambio
estructural (mismo día)** — El dueño: "sigue pasando el mismo bug de
mierda... por qué no ponemos un ícono de búsqueda en la navbar mejor".
`pushSinTeclado` (el mecanismo de arriba) sigue siendo correcto y se
queda para las demás pantallas, pero en el menú principal específicamente
se optó por sacar la causa de raíz en vez de seguir ajustando el síntoma:
el campo de búsqueda deja de estar siempre montado. Ahora vive dentro del
`AppBar`, oculto por default, revelado con un ícono de lupa
(`_busquedaVisible`, `pantalla_menu_companion.dart`) — sin el `TextField`
en el árbol, no hay ningún `FocusNode` que una ruta pueda recordar ni
restaurar. Se cierra con la flecha de volver del `AppBar` o con el botón
atrás del sistema (`PopScope`, `canPop: !_busquedaVisible` — a diferencia
de otros flags "dirty" de la companion, este sí pasa siempre por
`setState`, así que un `canPop` calculado en el build es seguro de usar
tal cual, sin la salvedad que sí aplica a esos otros casos). Detalle
completo en `TRAMPAS.md`.

## Resuelto: visibilidad de la lata y del redondeo en la companion (Arqueo/apertura)

El dueño, 2026-09-10, después de la ronda de rendimiento: "deberíamos tener
las 2 cajas, la de los cigarros y la normal [al abrir/arquear desde el
celular]... al momento de arqueo, qué parámetros toma, ¿solo ventas en
efectivo?... revisemos el tema de los redondeos, porque eso puede llevar a
confusiones innecesarias". Investigado antes de tocar código — dos
respuestas y dos gaps reales, no un bug de cálculo:

- **El arqueo NO era solo efectivo** — ya tomaba efectivo Y Mercado Pago
  (`estadoCajaEnVivo`, mismas fórmulas del cierre real). Lo que faltaba era
  mostrar la LATA como una tercera cifra al mismo nivel: solo aparecía
  "cigarrillos a separar (lista)", nunca el estado de la lata en sí.
- **La lata no se puede arquear en vivo de verdad** (Regla 10:
  `separarCigarrillos` necesita efectivo CONTADO, algo que un chequeo sin
  contar nada, por diseño, no tiene) — así que no hay "lata esperada" para
  mostrar hoy, solo lo que ya se sabe sin contar: `lataInicialCentavos`
  (lo que se arrastra de antes). Se agregó esa cifra a `EstadoCajaEnVivo`
  (`repositorio_cierre.dart`) y se muestra en el Arqueo de la companion
  (`pantalla_arqueo.dart`) como "Lata (arrastrada de antes de hoy)".
- **El redondeo SÍ se contaba** dentro de "Efectivo esperado" (Regla 2:
  efectivo redondea), pero — a diferencia del cierre real del escritorio,
  que lo separa en su propia línea "para que no se confunda con un
  descuadre" — la companion no lo desglosaba en ningún lado. Mismo campo
  `redondeoAcumuladoCentavos` que ya calculaba `estadoCajaEnVivo`
  internamente, ahora expuesto y mostrado como línea propia en el Arqueo.
- **Apertura desde el celular** (`SesionAbiertaGate`): la lata nunca se
  pregunta ahí ni en el escritorio (se arrastra sola del cierre anterior,
  a propósito — Regla 10), eso no cambió. Lo que sí se agregó: un aviso
  informativo con cuánto se va a arrastrar, para que abrir caja no dé la
  sensación de "¿y la caja de cigarrillos?" — `lataQueSeArrastraCentavos`
  nuevo en `GET /sesion` (`lib/data/repositorio_ventas.dart`, la misma
  consulta que ya usaba `abrirSesion` para esto, extraída a
  `ultimaSesionCerrada` para no duplicarla — Regla 3).

Verificado con `flutter analyze` (limpio) y los 849 tests (todos verdes).

## Resuelto: optimización de rendimiento en la companion Android (POS/stock/caja)

El dueño, 2026-09-10: pedido original de "optimizar el apk" (la companion
Android, no el escritorio — ver la corrección de alcance al principio de
"En curso: companion app Android" más arriba, la confusión inicial de esta
sesión fue exactamente esa). A diferencia del escritorio, cada operación
de la companion es una request HTTP real por WiFi contra el servidor
embebido de la PC — mucho más cara que una consulta SQLite local.

- **Búsqueda sin debounce, en las 4 pantallas con buscador**
  (`pantalla_menu_companion.dart`, `pantalla_precios.dart`,
  `pantalla_consultar_precio.dart`, `pantalla_carga_historica.dart`): cada
  tecla mandaba una request. No era solo lento — sin garantía de orden de
  llegada por WiFi, la respuesta de una búsqueda vieja podía llegar después
  y pisar el resultado de la más nueva, mostrando resultados de otra
  búsqueda (bug real, no solo estética). `lib/companion/debounce.dart`
  (`Debouncer`, ~300ms) nuevo, usado en las cuatro pantallas junto con una
  guardia que descarta cualquier respuesta cuyo texto ya no coincide con
  lo que hay en el campo al momento de llegar.
- **`ClienteCompanion` abría una conexión TCP nueva por request**
  (`lib/companion/cliente_companion.dart`): las ~30 llamadas usaban
  `http.get`/`post`/`delete` de nivel superior (cada una crea y cierra su
  propio `Client`). Pasan a compartir un único `http.Client` estático,
  reusado por todas las instancias — habilita keep-alive real contra la
  misma PC.
- **Guardado de conteo de stock, secuencial** (`pantalla_conteo_stock.dart`,
  `_guardar()`): un conteo físico real de 30-80 productos esperaba un
  `ajustarStock` detrás del otro — ahora todas las requests se lanzan
  juntas (los futures se crean sin esperarse antes del loop que sí los
  espera, para seguir atribuyendo cada error a su producto) en vez de
  esperarse en serie.
- **N+1 en el servidor al cargar un día histórico**
  (`servidor_companion.dart`, `_pendientesHistoricosDesdeBody`): por cada
  venta del día se releían `configuracionTabla` y los dos `mediosDePago` —
  hasta 300 consultas chicas evitables en un día de 50-100 ventas cargado
  de una vez desde el celular. Se resuelven una sola vez antes del loop.
- `/caja/estado` (Arqueo en vivo): sus tres consultas independientes
  (`estadoCajaEnVivo`/`resumenDiaHistorico`/`cantidadVentasDelDia`) se
  lanzan juntas en vez de esperarse en serie — impacto bajo (sin polling
  automático, solo refresh manual) pero gratis de aplicar con el mismo
  patrón.

Verificado con `flutter analyze` (limpio) y la suite completa (849 tests,
todos verdes) después de cada cambio.

## Resuelto: optimización de rendimiento en POS/stock/caja

El dueño, 2026-09-10: "seguir optimizando la app, con énfasis en POS, stock y
contabilidad de caja". Auditoría de código (sin cambiar comportamiento
visible, solo velocidad) en las tres áreas — ningún bug de correctitud de
plata encontrado al pasar, las fórmulas ya cumplían Regla 3.

- **Búsqueda del campo único (POS)**: `normalizarTexto` (22 `replaceAll`)
  se recalculaba para nombre y código de barras de cada producto del
  catálogo en **cada tecla escrita**. `VentaControlador.cargarTodo()` ahora
  precalcula `_nombresNormalizados`/`_codigosNormalizados` (por id) una
  sola vez al cargar el catálogo; `buscarProductos`
  (`lib/data/busqueda_productos.dart`) los usa si se los pasan y sigue
  calculando al vuelo si no (los otros tres llamadores — carga histórica,
  editor de venta, servidor companion — no corren por tecla, no
  necesitaban cambiar).
- **`repositorio_proveedores.dart`/`repositorio_reposicion.dart` (stock/
  Proveedores/Reportes)**: `resumenProveedoresNivel1`, `reposicionActual` y
  `gananciaPendienteDeProveedores` hacían una consulta SQL por proveedor
  (hasta ~15, el doble cuando `proveedoresParaSeparar`/`reporteProveedores`
  llaman a dos de estas juntas) — ahora traen todas las líneas que
  necesitan en una sola consulta (`_lineasPorProveedorDesde`, agrupada por
  `proveedorIdFoto`) y filtran por el corte de cada proveedor en memoria,
  de N round-trips a 1. Aparte, `gananciaPorMedioDesde` (un solo
  proveedor, no un loop) consultaba la tabla de medios de pago (2 filas)
  por cada pago de cada venta sin revisar — cientos de round-trips
  evitables en un proveedor con historial largo; ahora trae los pagos de
  todas esas ventas y los medios de pago una sola vez cada uno, antes de
  resolver la proporción por venta.
- **`repositorio_cierre.dart` (caja)**: `calcularResumenCierre`/
  `estadoCajaEnVivo` consultaban `cajaNormal`/`medioMercadoPago` (tablas de
  2 filas) hasta 3 veces cada una por llamada — se resuelven una sola vez y
  se pasan como parámetro opcional a los helpers (`efectivoDeVentasDelDia`,
  `gastosEnEfectivoDelDia`, etc. — sin el parámetro siguen resolviéndolo
  solos, ningún otro llamador tuvo que cambiar). Las consultas
  independientes entre sí (no se pisan resultados) se lanzan todas de una
  en vez de esperarse en serie.
- **Índices nuevos** (migración v22→v23, `CREATE INDEX IF NOT EXISTS` — no
  necesita build_runner): `lineas_de_venta.proveedor_id_foto`/`venta_id`,
  `ventas.sesion_caja_id`/`fecha`, `movimientos_de_caja.sesion_caja_id`/
  `caja_id`, `pagos.venta_id` — las columnas que reciben WHERE/JOIN en las
  consultas de arriba, ninguna indexada hasta ahora (Drift no indexa
  automáticamente una columna de foreign key).
- Descartado por bajo impacto real a la escala de esta app (un carrito de
  decenas de líneas, no miles): rebuilds de `ColumnaCarrito`
  (`ListenableBuilder`/`ListView.builder` ya está bien pensado) y el scan
  lineal de `productoPorId`.

## Resuelto: rediseño visual del inicio y el layout de la companion

El dueño, 2026-09-10: "rediseña levemente el inicio y el layout, no me
termina de gustar, hacelo sin preguntarme, solo que se vea diferente" —
pedido puramente estético, sin cambio de comportamiento ni de servidor.
Todo en `pantalla_menu_companion.dart`:

- **Barra de estado de caja** (`_barraEstadoCaja`): pasa de un `Row`
  suelto a una tarjeta real (`Bloque` + `Material(transparency)` +
  `InkWell`, mismo patrón que el resto del kit) para que el ripple se vea
  al tocarla. El ícono de candado queda en `colores.textoSecundario`, NO
  en el acento — no es uno de los tres usos canónicos del acento
  (`tokens.dart`: "el total, el medio de pago elegido, la línea recién
  agregada al carrito").
- **Accesos de uso diario (`_Tile`)**: mismo tamaño de grilla, pero
  padding vertical más generoso (`Espaciado.xl` en vez de `lg`) e ícono
  más chico (40 en vez de 48) — menos "botón gigante", más tarjeta.
- **Accesos de gestión y reportes**: dejan de ser tiles cuadrados en fila
  para pasar a `_TileCompacta` (nueva), una fila horizontal ícono+texto+
  chevron, apiladas verticalmente. La diferencia de forma (no de color)
  es la que marca que son de uso ocasional frente a los diarios — "no
  hace falta ningún color nuevo para marcarla".
- **Barra del carrito** (`_barraCarrito`): pasa de ocupar el ancho
  completo pegada al borde a una tarjeta flotante con margen. El
  subtotal sigue en el acento — ese sí es uno de los tres usos
  legítimos ("el total").

Sin cambios de servidor ni de dominio: no hace falta rebuildear el
desktop, solo republicar la companion. `flutter analyze` limpio y las
853 tests existentes (incluye los tests de widget del menú) siguen
verdes — el rediseño no tocó lógica, solo estructura visual.

## Resuelto: migración del motor de sync de Firestore a Supabase

El dueño, 2026-09-18: "nos vamos a supabase" — decisión tomada después de que
un solo día de testing intensivo (varias reinstalaciones completas de la
companion) agotara la cuota gratuita de Firestore (20.000 escrituras/día).

**Causa real encontrada antes de migrar** (no era el límite en sí): el
cursor de "qué ya se empujó" vivía en `SharedPreferences`, local a cada
instalación. Cada reinstalación de la companion lo reseteaba a cero, y la
siguiente sincronización reinterpretaba TODA la base local como cambios
nuevos y la volvía a subir entera. Sumado a un efecto menor de "eco" (una
fila recibida por pull se reenviaba una vez de más porque el cursor de push
de quien la recibía nunca se enteraba de que ya la tenía), el volumen de un
día de reinstalaciones repetidas alcanzó el tope. En uso real (sin
reinstalar la app todo el tiempo) esto nunca hubiera pasado — pero Supabase
tampoco cobra por escritura individual (cobra por almacenamiento/ancho de
banda), así que el mismo patrón de testing no vuelve a bloquear nada.

Beneficio adicional: el SDK de Supabase no tiene el bug que sí tenía
`firebase_auth` en Windows (documentado en el `firebase_rest_escritorio.dart`
ya borrado), así que esta migración también eliminó toda la capa REST manual
que existía solo para esquivarlo — Windows y Android comparten ahora
exactamente el mismo código de sync, sin bifurcación.

**Qué cambió:**

- `lib/data/transporte_firestore.dart` + `lib/data/sincronizacion_firestore.dart`
  + `lib/data/firebase_rest_escritorio.dart` + `lib/firebase_init.dart` +
  `lib/firebase_options.dart` → reemplazados por `lib/data/transporte_supabase.dart`
  + `lib/data/sincronizacion_supabase.dart` + `lib/supabase_init.dart`.
  `lib/data/repositorio_sincronizacion.dart` (el motor de merge) no se tocó
  — es agnóstico de transporte, como ya lo era.
- **Pull con dos caminos que se complementan** (a diferencia de Firestore, el
  Realtime de Postgres no reproduce el historial al conectar un canal nuevo
  ni garantiza reentrega de lo perdido en un corte): Realtime para la parte
  instantánea + un pull con cursor cada 20s como red de seguridad real (cubre
  la sincronización inicial completa y cualquier cosa que Realtime se haya
  perdido). El cursor de ese segundo camino es una columna `rev` nueva
  (`bigint`, solo del lado servidor, nunca viaja a SQLite ni al dominio) que
  un trigger asigna en cada INSERT/UPDATE desde una secuencia compartida
  entre las 14 tablas — ver `supabase/schema.sql`.
- **Fix del bug de "eco"** de paso: al aplicar un pull, si la fila recibida
  es más nueva que el cursor de PUSH local de esa tabla, ese cursor se
  adelanta también — una fila recibida ya no se re-sube de vuelta como si
  fuera un cambio local propio (`sincronizacion_supabase.dart::_aplicarPendientes`).
- **Auth**: se reutilizó el mismo flujo de Google en las dos plataformas
  (loopback+PKCE en desktop, `google_sign_in` nativo en Android) — solo
  cambió el paso final, de `FirebaseAuth.signInWithCredential` a
  `Supabase.instance.client.auth.signInWithIdToken`. El allowlist de un solo
  email autorizado se mantiene igual (antes en `firestore.rules`, ahora como
  policy RLS en cada una de las 15 tablas de Postgres).
- Proyecto real creado en supabase.com (`la-plazoleta`, región São Paulo,
  plan free), `supabase/schema.sql` corrido a mano ahí, proveedor Google de
  Supabase Auth habilitado con los mismos Client IDs de siempre (desktop +
  Android). `lib/supabase_init.dart` tiene la URL y la publishable key reales
  de ese proyecto — la publishable key no es secreta (mismo criterio que
  tenía el `apiKey` de Firebase), la seguridad real la dan las policies RLS.
- `pubspec.yaml`: se sacaron `firebase_core`/`firebase_auth`/`cloud_firestore`,
  se agregó `supabase_flutter`.

**Verificado en vivo de punta a punta** (2026-09-18, con datos reales de
producción, no de prueba): login desktop y companion, push del histórico
completo (150 productos, 19 proveedores, 13 categorías, 135 ventas, 218
líneas, 135 pagos, 6 sesiones, más los logs de movimientos/arqueos/precios),
y pull completo del lado de la companion — coincide exactamente con la base
real de la PC.

**Segundo bug real encontrado en esa verificación, YA ARREGLADO** (no era de
esta migración — ya existía con Firestore, nunca se había topado con este
caso porque `ventas` nunca había llegado a aplicarse del todo en la
companion hasta esta prueba): `_aplicarUnaFila` copiaba crudo el `id` local
de columnas como `ventas.sesion_caja_id`, `lineas_de_venta.venta_id`,
`movimientos_de_stock.usuario_id`, etc. — un entero que solo tiene sentido
en la base que lo generó. La PC, con 25 sesiones de caja acumuladas en
meses de uso, y una companion recién instalada que solo había recibido 6,
nunca iban a coincidir en esa numeración: toda venta fallaba con
`FOREIGN KEY constraint failed`, indefinidamente. Arreglado agregando, en
`repositorio_sincronizacion.dart`, una traducción por `global_id`
(`_referenciasCruzadas`, `_resolverReferencias`): `cambiosDesde` manda,
además del id crudo, el `global_id` de la fila referenciada (vía `LEFT
JOIN`); `_aplicarUnaFila` lo usa para buscar el id LOCAL correcto en la
base que recibe antes de insertar. Esto agregó columnas nuevas
`<col>_gid text` a las tablas de Supabase que tienen claves foráneas
(`supabase/schema.sql` actualizado) — hubo que forzar un re-push completo
del histórico ya subido para completarlas ahí también. Dos tests nuevos en
`test/data/repositorio_sincronizacion_test.dart` cubren el caso (ids que no
coinciden entre dispositivos, y una referencia que todavía no llegó).

De paso, encontrado pero NO arreglado por ser dato, no código: la tabla
`usuarios` real de la PC tiene dos filas distintas llamadas "El dueño" (mismo
nombre, `global_id` distinto) — no es un bug de sync, ya estaba así antes
de cualquier migración. El dueño puede fusionarlas o desactivar una desde la
app cuando quiera, no bloquea nada.

Los archivos viejos de Firebase (`firebase_init.dart`,
`firebase_options.dart`, `firebase_rest_escritorio.dart`,
`transporte_firestore.dart`, `sincronizacion_firestore.dart`,
`android/app/google-services.json`, `firestore.rules`, `firebase.json`)
todavía no se borraron — ya no compilan (se sacaron sus dependencias de
`pubspec.yaml`) pero no los importa nada, así que no bloquean el build
real. Este repo todavía no es un repositorio git, así que no hay manera de
"deshacer" ese borrado más adelante — vale la pena que el dueño corra
`git init` en algún momento antes de esa limpieza final.

**Incidente real en el primer deploy a producción (2026-09-18), YA
RESUELTO**: al actualizar `C:\LaPlazoleta\app` con el build de Supabase, la
app arrancaba con **pantalla en negro**. Causa real, encontrada recién
lanzando la versión debug para ver la consola (la release no muestra
nada): la base de datos real de el dueño tenía `PRAGMA user_version = 30`
pero la tabla `usuarios` YA tenía las columnas de la migración v32 (de
algún momento anterior de esta misma sesión de trabajo, donde una
migración alcanzó a tocar las columnas sin llegar a confirmar la versión)
— al arrancar, `onUpgrade(from: 30, to: 32)` intentaba agregar de nuevo
columnas que ya estaban, `ALTER TABLE ... duplicate column name`, sin
capturar, tiraba abajo el arranque entero antes de dibujar nada. Arreglado
en dos frentes:
1. **Del lado de los datos** (con permiso explícito de el dueño, corrigiendo
   directo la base real): `PRAGMA user_version = 32;` — no tocó ninguna
   fila, solo la marca de versión, ya que los datos estaban completos y
   consistentes.
2. **Del lado del código, para que no vuelva a pasar por cualquier motivo
   parecido**: la migración v32 ahora chequea si la columna ya existe
   (`pragma_table_info`) antes de agregarla — segura de repetir. Además,
   `main()` ahora corre todo adentro de `runZonedGuarded` y el
   `inicializarSupabase()` inicial tiene un timeout de 8s sin bloquear el
   arranque — cualquier excepción o cuelgue de red futuro en el arranque
   deja un rastro en la consola en vez de una pantalla negra muda. Test
   nuevo en `test/data/migracion_v32_test.dart` reproduce el bug exacto.

**Optimización de velocidad, mismo día** (El dueño: "tarda mucho al loguear
la primera vez... tiene que ser completamente instantáneo"): el pull y el
push de las 14 tablas sincronizables eran secuenciales — 14 viajes de red
seguidos, cada uno esperando al anterior. Ahora corren en paralelo
(`Future.wait` en `sincronizacion_supabase.dart::_pullPeriodico`/
`_empujarCambiosLocales`) — no cambia el orden en que se APLICAN los
cambios después (sigue siendo uno por uno, por las claves foráneas), solo
el tiempo de bajarlos/subirlos. Pendiente si sigue sintiéndose lento: medir
cuánto tarda de verdad la primera sincronización completa y decidir si
hace falta paginar las tablas más grandes.

## Próximos pasos

Sin esto, se sabe dónde está el proyecto pero no para dónde va. En orden:

1. **Probar en la PC real del local** — todo lo probado hasta ahora fue en
   la máquina de desarrollo. Con el cambio a la máquina nueva (ver fase 13
   arriba) esta prueba deja de ser sobre todo una prueba de rendimiento
   límite; sigue valiendo como primera instalación real de un día entero.
2. **Correr una semana en paralelo con el sistema HTML anterior**,
   comparando los cierres de caja día a día. Es la prueba de que el
   modelo de negocio (no solo el código) está bien — ver "Validación real
   del dominio" arriba.
3. ~~Aplicar el sistema de diseño (`DISENO.md`) a las pantallas que
   faltan~~ — **hecho** (paso 2 completo: Proveedores, Cierre, Equilibrio,
   Historial, Configuración/Carga histórica/Impresión/Respaldo). Fase 13
   solo le queda el ítem 4 de acá abajo.
4. **Decidir el rango horario del tema automático claro/oscuro** — única
   pregunta de fase 13 que sigue genuinamente abierta, ver detalle arriba.
5. **Aprovechar que el kit ya existe para lo que venga después de fase 13**
   — cualquier pantalla nueva (o la sección "Pendientes" de fiados/encargues
   que quedó afuera de Proveedores, sin fecha todavía) empieza directo con
   `PantallaGestion`/`ListaMaestra`/`Modal`, no con widgets de Material
   sueltos.
6. ~~Pulido UI/UX de la companion (segunda y tercera tanda: kit compartido,
   `EstadoVacio`, guardas de datos sin guardar, doble-tap, pull-to-refresh,
   jerarquía visual del menú, mensajes de error unificados)~~ — **hecho**,
   ver "Resuelto: segunda tanda de pulido UI/UX de la companion",
   "Resuelto: organización de elementos en la companion (tercera tanda)" y
   "Resuelto: rediseño visual del inicio y el layout de la companion"
   arriba.
7. **Separar dividido entre cajón y Mercado Pago** (2026-09-26,
   schemaVersion 35) — reemplaza al "excedente de MP" del día anterior.
   Regla en `REGLAS-NEGOCIO.md` §5, decisiones en `DECISIONES.md`. Código y
   tests listos (1117 en verde). **Falta**: crear
   `proveedores.separado_mp_centavos` en Supabase (final de
   `supabase/schema.sql`) ANTES de instalar, instalar en PC y celular, y
   verlo en vivo al separar/pagar un proveedor con ventas por QR.
   **Actualización**: columna creada en Supabase y v35 instalada en PC;
   después se sumó el apartado **"Separaciones"** (v36, sección nueva del
   menú, ver `DECISIONES.md`) y el arreglo de ventas anuladas — capturas en
   `capturas/separaciones_*.png`.
   **Segunda vuelta** (mismo día): Separaciones pasa a ser solo de hoy, con
   vendido/reposición/ganancia por proveedor (ganancia dividida por caja) y
   ajustada a la plata que hay ahora en el cajón y en MP — ver
   `DECISIONES.md`, "Separaciones es del día...".
8. ~~Bucle de sincronización con Supabase~~ — **arreglado y desplegado
   (2026-09-26)** en PC (build en `C:\LaPlazoleta\app`) y celular (APK
   1.0.0+2084). Verificado: 0 escrituras en reposo, un cambio de precio
   generó 10 y llegó al celular. Falta mirar el uso de Supabase al otro día. Ver `TRAMPAS.md` ("Un cursor `>=` sin
   memoria..."). El build nuevo tiene que llegar a la PC del local y al
   celular: mientras corra un build viejo en cualquiera de los dos, el
   bucle sigue. La red de seguridad del servidor (`sync_asignar_rev` que
   descarta upserts sin cambios, final de `supabase/schema.sql`) YA está
   aplicada en producción (2026-09-26 15:23 UTC): el contador `rev` bajó
   de ~123 escrituras/s a ~4,6/s. Ese resto son filas que PC y celular
   re-suben con distinto contenido (ids locales de claves foráneas que no
   coinciden entre dispositivos), así que para el servidor sí "cambian" —
   eso recién se corta del todo con el build nuevo en los dos.
9. **Menú de 11 apartados a 6, y menú de secciones rehecho** (2026-09-26,
   v39): Inicio · Venta · Proveedores · Separaciones · Historial ·
   Configuración. Detalle de qué fue a dónde en `DECISIONES.md`. Las
   secciones de este archivo que hablan de "Reportes" o "Equilibrio" como
   pantallas describen cómo eran; hoy Reportes no existe y Equilibrio es la
   mitad "del mes" de Inicio.


## Resuelto: revisión de matemática y lógica (2026-09-29)

- Caja esperada sumaba el redondeo dos veces (faltante falso ~redondeo del
  día en cada arqueo): `cajaEsperadaCentavos` ya no lo recibe. Los cierres
  ya guardados conservan el esperado viejo (inflado por el redondeo).
- Editar una venta con descuento lo perdía (total sin descuento, columna
  `descuentoCentavos` vieja) y perdía el canal QR/débito: ahora se conserva
  el descuento como monto fijo y el canal.
- Ganancia/vendido/equilibrio/separaciones salen netos del descuento
  (`lineaParaReposicionDesde(..., venta:)`); `gananciaPorMedioDesde` excluye
  anuladas.
- Pendiente (no tocado): fiado cobrado sin verificar estado ni transacción;
  separar/pagar proveedor sin transacción; búsquedas tipo "7 Up" leídas
  como gramos.

## Hecho: ventas abiertas persistentes y múltiples (2026-09-29)

- Tabla `ventas_abiertas` (migración v40) + `repositorio_ventas_abiertas.dart`.
  `VentaControlador` guarda solo la pestaña activa en cada cambio (fuera del
  camino de la venta) y restaura todas al volver a abrir la pantalla.
- Pestañas sobre el carrito (`columna_carrito.dart`), Alt+N nueva, Alt+S
  siguiente. Cobrar borra el borrador en la misma transacción que la venta
  (`registrarVenta(ventaAbiertaId:)`).
- `cerrarSesion` lanza `VentasAbiertasPendientesException` con ventas
  abiertas; el cierre ofrece descartarlas. La companion recibe 409.
- Pendiente de decidir: fiado como venta abierta con nombre (hoy sigue siendo
  un pendiente aparte); refrescar precios de un borrador viejo.

## Hecho: ventana propia y logo nuevo (2026-09-29)

- Mocks en `ventana-la-plazoleta/` (Main, Barra, Cierre, LEEME). Se saca la
  barra de título nativa (`window_manager`, `TitleBarStyle.hidden`) y se
  dibuja una de 40 px: marca "P", "La Plazoleta", chip "Caja abierta" (o
  "Caja de ayer sin cerrar"), "Respaldo hoy HH:mm" y minimizar/maximizar/
  cerrar propios (hover gris, cerrar rojo, arrastrar, doble clic maximiza,
  apagada sin foco). Código en `lib/ui/ventana/ventana_escritorio.dart`;
  `LaPlazoletaApp(conVentanaPropia: true)` solo desde `main()` (los tests de
  widget no tienen el plugin de ventana).
- Cerrar la ventana con la caja abierta pregunta: Ir a cerrar la caja /
  Seguir trabajando / Cerrar igual (`setPreventClose`).
- Logo nuevo: `assets/icon/logo_la_plazoleta.png` (fuente de
  `flutter_launcher_icons`, regeneró los mipmaps de Android) y
  `windows/runner/resources/app_icon.ico` (el multi-tamaño del paquete;
  ojo: `dart run flutter_launcher_icons` lo pisa con uno propio, volver a
  copiar `ventana-la-plazoleta/logo.ico`). La APK con el ícono nuevo sale
  en la próxima publicación de la companion. El ícono fijado en la barra de
  tareas de Windows queda cacheado hasta reiniciar el explorador.

## Hecho: cuenta corriente con proveedores (2026-09-29)

- Tabla `movimientos_deuda` (migración v41), `repositorio_deuda_proveedores.dart`
  (cargarDeuda, pagarDeuda, anularMovimientoDeuda, saldoDeuda/saldosDeuda),
  diálogo `dialogo_cuenta_corriente.dart` (saldo, libro, cargar, pagar) desde
  Proveedores → botón "Deuda". La lista muestra "le debés $X" y el detalle una
  cifra "Le debés".
- Decisiones de el dueño: libro independiente de lo separado (no consume el
  separado), cualquier proveedor, monto+fecha+nota (sin vencimientos).
- Pendiente: mostrar la deuda total en el Dashboard; la companion Android no
  tiene el apartado.

## Hecho: precio automático por proveedor (2026-09-29)

- `precioConGananciaACentena` (domain/ganancia.dart), `proveedores.markup_bp` y
  `productos.precio_fijo` (migración v42), `aplicarPorcentajeDeProveedor` /
  `cambiosPorPorcentaje` / `guardarPorcentajeProveedor` (repositorio_productos)
  y recálculo automático al cambiar el costo dentro de `actualizarProducto`.
- UI: selector de % en el detalle del proveedor (`selector_porcentaje.dart`),
  "Aplicar a los precios" con vista previa; en el producto, chip "Automático /
  Precio fijo" que reemplaza a los botones +30/40/50%.
- Cigarrillos y "Varios" excluidos. La companion Android sigue con sus botones
  de precio rápido y sin el selector; el % y la marca de fijo no se sincronizan.
- Sin tocar: markup de referencia por categoría (Configuración), ya redundante.

## Hecho: creador de promos (2026-09-29)

- `productos.es_promo` + tabla `promo_componentes` (migración v43),
  `precioDePromo`/`repartirEnProporcion`/`stockDePromo` (domain), 
  `repositorio_promos.dart`, `registrarPromoEnVenta` (abre la promo en sus
  artículos al cobrar), stock derivado de la promo en `VentaControlador`.
- UI: Proveedores → ⋮ → Promos (`dialogo_promos.dart`): lista, alta y edición
  con precio en vivo y tope.
- Pendiente: la promo no se vende desde el celular; la venta ya cobrada se
  edita como líneas sueltas.

## Hecho: ganancia real en vez de markup (2026-10-01)

- `domain/markup.dart` → `domain/ganancia.dart`: `precioDesdeCostoYGanancia`, `costoDesdePrecioYGanancia`,
  `gananciaBpDesdeCostoYPrecio`, `precioConGananciaACentena`, `precioDePromo(gananciaBp:)`. Ganancia sobre el
  precio; ver `DECISIONES.md`.
- Migración v46 convierte los porcentajes guardados (proveedores y categorías) sin mover precios
  (`test/data/migracion_v46_test.dart`).
- UI: el selector del proveedor, las promos, el diálogo de producto, la companion, Configuración y los tableros
  dicen "ganancia"; los chips de la companion pasan a 20/30/40% de ganancia.
- **Sin verificar en esta sesión**: no había Flutter/Dart instalado, así que los tests no se corrieron. Correr
  `flutter test` antes de dar esto por cerrado.

## Hecho: asistente contable, primera parte (2026-10-01)

- `domain/rentabilidad.dart`, `data/repositorio_rentabilidad.dart`; tarjeta "Estado de resultados del mes" en
  Equilibrio y aviso "Retirar igual" en el retiro de ganancia. Ver `DECISIONES.md`.
- Tarjeta "Margen necesario" en Equilibrio: venta objetivo y ganancia a retener (se guardan en el dispositivo), margen necesario vs. el de hoy, venta necesaria y productos por debajo con precio sugerido (solo sugerencia, Regla 14).
- **Sin verificar**: sin Flutter en la sesión, nada de esto se compiló ni se corrió. `flutter analyze` y `flutter test`
  primero.


## Encargues por apartado (2026-10-02)

Hecho en PC y celular, con tests: apartar (baja el stock), cancelar (lo devuelve), entregar (abre una venta con lo apartado y la cobra liberándolo). Ver `DECISIONES.md` ("Encargues por apartado"). Pantalla `lib/ui/encargues/` en la PC, `lib/companion/pantalla_encargues_companion.dart` en el celular; reglas en `lib/data/repositorio_encargues.dart`.
Pendiente de decidir con el dueño: nada de lo pedido. Fuera de alcance a propósito: seña, fecha prometida, aviso al cliente, "pedir al proveedor".

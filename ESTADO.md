# Estado actual — La Plazoleta / Nodo Sur POS

**Fuente de verdad de cómo está el proyecto HOY.** Corto a propósito: lo que ya se resolvió vive en `DECISIONES.md`
(por qué se hizo así) y `TRAMPAS.md` (bugs que no hay que repetir); el detalle cronológico anterior al 2026-10-03 está en
[`docs/archivo/ESTADO-ARCHIVO.md`](./docs/archivo/ESTADO-ARCHIVO.md). Si algo de acá contradice al código o a `git log`, gana el código y
se corrige este archivo. Para retomar desde cero: `CONTEXTO.md`.

Se actualiza al cerrar cada sesión de trabajo. **No agregar acá historias de "Resuelto"**: una línea en "Últimos cambios"
y el detalle en `DECISIONES.md`.

---

## Publicado (2026-10-03)

- **Windows**: estable 1.0.0.2129 (03/10, al 100 %).
- **Android**: estable 1.0.0+2130 (03/10, al 100 %). **La 1.0.0+2129 de Android quedó rota**: una segunda
  publicación con el mismo número pisó su archivo en R2 y el sitio conserva la firma del anterior. La 2130 la reemplaza
  (los celulares toman la más nueva). La 2129 quedó **bloqueada** en el sitio (03/10).
- **Sitio** (`NodoSurPage`): en producción al mezclar a `main`.

## Rediseño de la PC v3 — mock hecho, sin aplicar al código (05/10/2026)

El dueño rechazó el aspecto de la app de escritorio y pidió **rehacerla desde cero** (disposición incluida) con el lenguaje de
horsepos.com y antigravity.google. Se hicieron **dos versiones**:

- **Expresiva** (primera): títulos que se tipean, partículas, mega-menú, tablero 3D, cinta de avisos, cursor-pastilla. El dueño dijo
  que para la caja **se exageró un poco** (hay que poder leer claro y, en lo posible, **sin scroll**), **pero le gustó para la web**:
  queda **guardada para el sitio** en [`docs/archivo/ESTILO-EXPRESIVO-WEB.md`](./docs/archivo/ESTILO-EXPRESIVO-WEB.md) y
  `docs/mock-pc/NodoSurPC-v3-expresivo.html` (vivo: https://claude.ai/artifact/DnUi6qvYDxZpgpD3uh14js). **Pendiente: llevarla al sitio**
  (repo `NodoSurPage`, fuera de este repo).
- **Sobria** (la de la PC): cada pantalla entra en 1920×1080 sin scroll de página, títulos chicos, sin partículas/3D/cinta/títulos tipeados.
  Especificación para aplicarla: [`docs/archivo/ESPECIFICACION-PC-V3.md`](./docs/archivo/ESPECIFICACION-PC-V3.md) y `docs/mock-pc/NodoSurPC-v3.html` (vivo: https://claude.ai/artifact/Kq4qCixuDtGpRKS1sjKxxj).

**Ronda 3 (05/10, la última):** el dueño pidió rapidez inmediata y cero fricción, IA siempre a mano (no escondida en Configuración),
**Pagar proveedor** como acción principal de caja (gasto/ingreso secundario), navbar sin logo/nombre/lupa, tuerca para Configuración y
mucha información legible. Está en la especificación (secciones 4.2, 4.5, 7.x, 8 y **15**) y en el mock sobrio; funciones nuevas a confirmar
en 14.3 (asistente con pregunta libre, IA contextual, medio inicial Efectivo, "Venta cobrada" que se cierra sola).

**Ronda 4 (05/10, la última):** el dueño pidió **eliminar redundancias** (dejar lo más práctico a mano), sacar las tarjetas de IA del medio de Inicio,
**todo simétrico** y **avisos (toast) arriba**; y pidió un mock **aparte** porque la v3 le gusta de base. Quedó en
[`docs/ESPECIFICACION-PC-V4.md`](./docs/ESPECIFICACION-PC-V4.md) (delta sobre la v3: gana la v4) y `docs/mock-pc/NodoSurPC-v4.html`
(vivo: https://claude.ai/artifact/XumwdGBG2BR9FcbLShoSqh). La v3 queda intacta. Funciones movidas a confirmar: menú **Caja ▾**, ✕ en las pestañas de venta,
"Venta cobrada" sin botón de siguiente, diálogos sin "Cancelar".

**Aplicación al código (06/10, etapa 1 en curso):** se empezó a llevar el diseño v4 a Flutter, con el plan en [`docs/PLAN-APLICAR-V4.md`](./docs/PLAN-APLICAR-V4.md).
Hecho y probado con `flutter analyze` + tests: **avisos arriba** (`mostrarAviso`, reemplaza a todos los `SnackBar` de la PC), botón **"Caja ▾"** (menú de caja en Venta y en el
resto de las pantallas), **navbar y barra de la ventana en tres costados simétricos**. **Sin probar en Windows real** (aspecto, rendimiento, terminal). Falta de la etapa 1: campanita en
todas las pantallas. **Etapa 2 (Venta) empezada**: sin título "Vender", buscador grande con **Pagar proveedor (Alt+P)** al lado (diálogo rápido nuevo, usa `pagarDeuda`), pastilla **Varios**.
Todavía NO se tocó "Venta cobrada" ni los diálogos de cobro (hay una decisión pendiente, ver el plan). **Etapa 3 (Inicio) hecha**: sin "Nueva venta" y tres columnas iguales arriba (vendido, indicadores, más vendidos) y abajo (cómo te pagaron, stock bajo, encargues y deudas); el gráfico de ventas por hora se adapta a una tarjeta angosta. **Pantallas sin subtítulo** (decidido en el rediseño v4). **Configuración (etapa 7) hecha**: una sola lista con las 16 secciones y el nombre del grupo arriba de las suyas, título y descripción a la derecha, sin pastillas. Al comparar las capturas reales con el mock se vio que **Proveedores, Separaciones e Historial ya coinciden en lo funcional** (cifras por período, selección, filtros por medio); queda por ver Cierre y los diálogos (sin "Cancelar" ni total repetido), y todo lo marcado como decisión pendiente en el plan.

**Ronda 5 (06/10):** el dueño pidió implementar en el mock **todo lo que existe en la app real y faltaba** y **dejar lo que solo está en el mock** (son funciones útiles que quiere conservar).
Hecho: ~35 funciones agregadas al mock v4 (imprimir ticket, quién abre, caja de ayer, cerrar el sistema, reabrir, cifras y selección en Proveedores, cuenta corriente, edición masiva completa, promos, comparar con los súper,
períodos y filtros, devolución por Mercado Pago, editor y carga histórica completos, cierre completo, Configuración). Detalle en la sección 8 de [`docs/ESPECIFICACION-PC-V4.md`](./docs/ESPECIFICACION-PC-V4.md). **Sigue sin tocarse el código de Flutter.**

**Auditoría del mock v4 (05/10):** se comparó contra la app real y **no tiene todas las funciones**: faltan ~35 (unas 15 de prioridad alta) y hay 7 cosas
inventadas que no existen en la real. Detalle y orden para cerrar en [`docs/archivo/AUDITORIA-MOCK-V4.md`](./docs/archivo/AUDITORIA-MOCK-V4.md). **Antes de aplicar el diseño al código hay que cerrar esa lista.**

**No se tocó código de Flutter.** Reemplaza al mock y a la comparación de la sección siguiente.

## PC rehecha según el mock del celular + horsepos (05/10/2026) — etapa 2 aplicada a medias

Pedido del dueño: revisar el mock del celular, la web (horsepos.com) y antigravity.google, comparar con la app de PC y rehacerla.
Comparación en [`docs/archivo/COMPARACION-MOCK-PC.md`](./docs/archivo/COMPARACION-MOCK-PC.md); mock de escritorio interactivo en
`docs/mock-pc/NodoSurPC.html` (todas las pantallas y modales, claro/oscuro). Decisiones del dueño (05/10): modales al centro, "Cobrar"
azul, colores de medios como el mock, títulos en peso 500, ninguna función nueva.

**Hecho en el código** (`flutter analyze` limpio; suite completa verde): paleta y acentos del mock (azul de marca en oscuro, medios
verde/azul/gris/ámbar, sin degradés), navbar con íconos de trazo y Venta azul, "Cobrar" y "Nueva venta" azules, medios grises hasta
elegirse, aro azul en la última línea del carrito, toast oscuro, **íconos de trazo en toda la app** (`IconoPlz`), saludo "Hola, nombre"
en Inicio. **Distinto del mock a propósito:** no hay franja "Este mes" en Inicio (ya existe la vista "Este mes", y no se repite una cuenta
de plata); Historial, cierre y Configuración ya tenían la disposición del mock, solo cambiaron colores e íconos. Los íconos que no
tienen trazo equivalente siguen en Material. No probado en una PC real; solo capturas de test (`test/ui/capturas_escritorio_test.dart`).

## Celular calcado del mock (04–05/10/2026) — publicado, APK 2135

Mezclado en `main` (PR #67, #68 y #69) y publicado en estable, al 100 % (APK 2133, 2134 y 2135). El celular se rehizo para que sea el mock "Nodo Sur · App del celular" (paquete
`nodo-sur-mock-celular`, segunda vuelta con 175 capturas): barra inferior de 5 pestañas, paleta/tipografía/iconos/animaciones
del mock y todas sus pantallas: bienvenida/modo de uso/emparejar/entrar con Google/asistente de 3 pasos, Inicio (con tablero,
estados de conexión y tarjeta "Te faltan N pasos"), Vender → Cobrar (crédito, descuento libre, cantidad exacta, deshacer,
entregar encargue, hoja de la terminal con todos sus estados), Caja (Resumen · Separar · Ventas), Contar la caja, Cerrar caja
en dos etapas, Gasto o ingreso (con lata), Productos (filtros, ganancia, proveedor), Controlar stock, Editar en lote por
contexto, Nuevo/Editar producto, Días históricos, Cierres anteriores, Encargues, Pagar proveedor, Cuenta y sincronización,
Actualización en 3 pasos, Más y Configuración. Comparación y decisiones en
[`docs/COMPARACION-MOCK-CELULAR.md`](./docs/COMPARACION-MOCK-CELULAR.md); el kit está en `lib/companion/kit/` y las pantallas
nuevas en `lib/companion/pantallas/`. **Probado por el dueño en su celular (05/10/2026): anda todo.**

Lo que pasó después del primer lanzamiento (2133):
- **2134 — arreglo.** En el celular real, Productos y Caja › Ventas quedaban cargando para siempre y Notificaciones, el Buscador de funciones, Consultar precio, Cierre y Gasto se rompían al abrirse. Causas: (1) el menú resuelve el servicio *después* de abrirse y no avisaba a las pestañas; (2) las pantallas abiertas con `Navigator.push` no encontraban `AppNs`. Ahora `setState` del menú suma versión y `AppNs` se publica arriba del navegador (`puenteAppNs` / `PuenteAppNs`, en `app_ns.dart` y `companion_app.dart`). Los tests no lo vieron porque usaban un controlador falso: hay un test nuevo con el **menú real** (`test/companion/menu_real_test.dart`).
- **2135 — animaciones.** Fundido cruzado de Material Motion (`FadeThroughTransition`) al abrir pantallas (`tema_companion.dart`) y al cambiar de pestaña (`CambioDePestanaNs`, en `kit/movimiento_ns.dart`), y `PantallaEntradaNs` ya no anima (se sumaba una segunda entrada). Decisión del dueño del 05/10, **distinta del mock**, que usa fade + subida de 14 px (`.scr`, 0,55 s). Se mantienen las entradas de tarjetas/filas, hojas, avisos y el efecto de apretar; todo respeta "reducir movimiento".

Distinto del mock a propósito:
- **Pago mixto** no se cobra desde el celular (falta el endpoint); queda el crédito en 1 pago.
- **¿Quién sos?**: el perfil sale de la cuenta con que se entró (decisión del 2026-10-02), no de una lista.
- **Bienvenida**: se conserva la animada de la app (el mock tiene 6 escenas estáticas).
- **Terminal**: en los fallos se suma un botón "Cancelar" que el mock no tiene.
- **Encargues**: las líneas no muestran precio (el servidor del celular no los manda).
- **Pagar proveedor**: sin alias/CVU (en el mock es solo una propuesta de diseño).
- **Animación de pantallas**: fundido cruzado en vez del fade + subida del mock (decisión del dueño, APK 2135).
- **Más**: sin "Historial de ventas" ni "Tablero del día" como filas (el historial está en Caja › Ventas y el tablero en Inicio),
  y "Probar estados" es solo del mock.

Pendiente / ideas (sin hacer):
- **Funciones de la PC en el celular** (El dueño, 2026-10-07: "que las funciones del sistema desktop estén disponibles para el apk, reutilizando la lógica"): hechas la lectura de facturas, pagar proveedor sin la PC, promos (con sugerencias), la cuenta corriente y separaciones completas. Sigue: comparar precios. Criterio: sacar la lógica de la pantalla de la PC a `servicios/`/`data/` y que el celular trabaje sobre su base propia.
- **Rediseño v4, etapa 8 (2026-10-06)**: hechos el **Asistente Ctrl+K**, el **WhatsApp del proveedor** (migración v53; botón "Pedir por WhatsApp" con lo de stock bajo) y el **logo del ticket** en el PDF (migración v54, `schemaVersion` **54**). La **seña de encargues** está hecha en la PC (migración v55, `schemaVersion` **55**; ver `docs/PLAN-SENA.md`; falta probarla en una Windows real). **Sucursal y Miembros**: la PC ya los muestra (Configuración › Cuenta de Nodo Sur) pero depende de un endpoint nuevo del sitio (`GET /api/device/team`) ya aplicado en `NodoSurPage` (PR #51, 2026-10-06). Detalle en `docs/PLAN-APLICAR-V4.md`.
- **IA de Google (Gemini) y promos sugeridas, 2026-10-05**: cliente en `lib/servicios/gemini.dart`; la clave se carga en Configuración › Asistente IA de la PC y del celular (cada equipo la suya, local; `probarYGuardarClave` no guarda una clave rota y elige el modelo que le anda a la clave: la 2133 de Windows salió con `gemini-2.5-flash` fijo y daba 404 con claves nuevas, corregido después). **Sugerir promos** (solo PC, Proveedores › Promos › "Sugerir promos"): `domain/sugerencia_promos.dart` busca los pares que se llevan juntos (≥2 ventas, lift ≥ 1,2, últimos 90 días, sin anuladas), `data/repositorio_sugerencia_promos.dart` les calcula el precio con `calcularPromo`, y Gemini (`servicios/asistente_promos.dart`, que no ve precios ni costos) solo les pone nombre y motivo; cada sugerencia deja elegir el porcentaje como el creador; sin clave o sin cupo se ven igual con "A + B". "Crear" abre el creador precargado. Probado con `flutter analyze` y tests; **no probado con una clave real de Google ni en un celular**. El celular no tiene promos, así que no tiene las sugerencias. **Facturas de compra con IA**: plan en `docs/PLAN-FACTURAS.md` (decidido el 2026-10-05); hechas las cuentas (`domain/factura_compra.dart`) y la lectura con Gemini (`servicios/lector_facturas.dart`, `domain/lectura_factura.dart`, achicar la foto) con la pantalla en Proveedores › "Leer factura"; **no probada con la clave ni las facturas reales**; hechos también los vínculos con tus productos (por CUIT del proveedor, aprendido, parecido de nombre y ayuda de la IA; migración v52, `schemaVersion` **52**); **bultos vs. unidades** propuestos por la descripción y el costo que ya tenés cargado (`domain/unidades_bulto.dart`, confirmás vos y se aprende por producto); **aplicar** hecho el 2026-10-07 (stock, costo, deuda, "No va", aviso de precio perdedor, sin repetir, "Deshacer"; migraciones v56–v57). Falta: notas de crédito, adjuntar la imagen y el celular con cámara.
- **Promos**: "Promo Fernet Coca" está cargada sin componentes (`promo_componentes` vacía): no descuenta el Fernet ni la Coca.
- **Reporte "ventas desde el último ingreso de stock"**: ofrecido, sin hacer.

## Últimos cambios (07/10/2026)

- **Cargar factura en el celular** (Más › Cargar factura): foto con la cámara o fotos/PDF, la IA la lee y se vincula, se revisa y se
  aplica (stock, costo, deuda) con "Deshacer", igual que en la PC. Funciona **sin la PC**: trabaja sobre la base del celular y la sync
  lo lleva. Para eso la **cuenta corriente y las facturas se sincronizan** (migración v61, `schemaVersion` **61**). La lógica del lector
  salió del diálogo de la PC a `servicios/flujo_factura.dart` (la usan las dos). **Publicar la PC y el APK juntos**: un equipo sin
  actualizar ignora las filas de esas tablas que le llegan por la nube y no las vuelve a pedir. Probado con tests; **no probado en un
  celular real (cámara incluida) ni con facturas reales desde el celular**.
- **Pagar proveedor sin la PC**: el celular paga sobre su propia base (cuenta corriente sincronizada desde la v61); el pago y su
  movimiento de caja llegan a la PC por la sync. Si la caja ya se cerró en otro equipo, avisa y no graba.
- **Promos en el celular** (Más › Promos): lista, crear, editar, activar/desactivar y "Sugerir promos" con IA, con las mismas cuentas
  de la PC. **Se venden en el celular**: la búsqueda muestra cada promo con el stock que alcanza con sus artículos y al cobrarla
  descuenta cada artículo (antes figuraba en 0 y no aparecía). **Arreglo**: una promo creada en la PC no llegaba nunca al celular (se
  creaba sin identidad de sincronización y sus artículos eran locales); ahora viaja con sus artículos (migración v62, `schemaVersion`
  **62**). Probado con tests; **no probado en un celular real**.
- **Cuenta corriente en el celular** (Más › Cuenta corriente): cuánto le debés en total y a cada proveedor, el libro de cargos y pagos,
  cargar deuda (con fecha y nota), pagar (abre Pagar proveedor con el proveedor elegido), anular y deshacer una factura cargada. Sobre la
  base del celular; solo pantallas, las reglas son las de la PC. Probado con tests; **no probado en un celular real**.
- **Separaciones en el celular** (Caja › Separar), lo que faltaba de la PC: reserva diaria de fijos, "Pagar" en cada proveedor,
  "Retirar plata" (ganancia sin revisar por proveedor: retener como colchón o retirar por medio, con el aviso de "te pasás de lo
  retirable") y "vendido sin costo · ver cuáles" con carga del costo ahí mismo. Mismo controlador de la PC; las reglas del retiro pasaron
  a `motivoParaNoRetirar` (`domain/rentabilidad.dart`), que usan las dos. Probado con tests; **no probado en un celular real**.
- **Plata que no aparece** (el dueño: "vendo mucho pero no tengo un peso"): en su base real salieron ~$1.590.000 sin anotar,
  casi todo de Mercado Pago. Ahora (1) **el cierre pregunta a dónde fue cada faltante** (gasto mío / proveedor / fijo / otro
  gasto) desde un mínimo configurable; (2) **los fijos repiten el último monto** hasta que se cambia; (3) **día de vencimiento
  de cada fijo**, avisado en Equilibrio. Migraciones v59 y v60 (`schemaVersion` **60**). Detalle en `DECISIONES.md`. Probado con
  tests; **no probado en una Windows real**.
- **Celular**: editar un producto desde el celular ya no le borra la marca de cigarrillo (y con ella el recargo por pago virtual). Los
  productos que ya la perdieron la recuperan solos al actualizar (migración v58, con la última venta marcada de cada uno;
  `schemaVersion` **58**).
- **Facturas de compra**: un CUIT para varios proveedores ("X" y "X cigarrillos", elegido por lo que trae la factura), crear el producto
  que falta desde la línea (nombre armado con tus productos, "Mejorar nombre con IA") y **aplicar la factura** con "Deshacer". Detalle
  en `DECISIONES.md`. Probado con tests; **no probado con facturas reales ni en una Windows real**.

## Últimos cambios (02–03/10/2026)

- **Auditoría de la caja**: `test/data/conciliacion_caja_test.dart` arma 120 días al azar y coincide siempre con un libro
  independiente; las diferencias negativas que veía el dueño eran plata que salió sin anotarse. Arreglos: abrir caja desde
  el celular arrastra el último MP contado, la sync no reabre una caja `CERRADA` con una fila vieja, y cerrar desde el aviso
  de "cerrar la app" termina en "Cerrar el sistema".
- **Mercado Pago por negocio**: cobro por el servidor, interruptor "Cobrar e imprimir por Nodo Sur", imprimir en la
  terminal por el servidor, conciliación en el cierre.
- **Posnet (2026-10-04)**: etapa A (la orden vence a los 2 minutos, avisos en vivo, "confirmá en la terminal"), B (devolver por
  MP al anular), C (botón Tarjeta: débito o crédito en 1 pago, ticket en la Point, modo autónomo) y D (avisos de cobros sin
  venta, contracargos y reclamos en la campanita; **falta activar los temas Pagos, Contracargos y Reclamos en el panel de MP**,
  ver el README del sitio) hechas. E (saldo real de MP en el cierre de la PC, con el botón "Traer saldo de Mercado Pago") hecha; falta que el celular lo tenga.
- **Navbar y Configuración rehechas** (engranaje, 5 grupos) en PC y celular; navbar centrada con lupa y Venta como pantalla
  principal.
- **Celular**: PDF del día completo, bienvenida, "Entrar con Google", "Configurá tu negocio", accesos de Inicio (Pagar
  proveedor, Hacer arqueo), encargues.
- **Rendimiento**: índices en la base, "Más vendidos" memorizado; en el sitio, caché de 2 min del estado de pago y caché
  larga de estáticos.

- **Arreglos de la revisión (03/10)**: una PC instalada de cero sincroniza su usuario inicial, "Varios" y las categorías
  de la plantilla (antes nacían sin `global_id` y el celular rechazaba sus cajas; migración v49 para las ya instaladas);
  un mixto cuyo total baja después de cargar el efectivo ya no graba Mercado Pago negativo (y `registrarVenta` rechaza
  pagos negativos); "con cuánto paga" del celular ya no repite $100.000. La configuración del negocio (recargos, redondeo,
  módulos) es una sola fila por equipo también para la sync: nace con un id fijo, una que llega con otro id se toma como
  la misma y gana la más reciente (antes una PC nueva no la mandaba nunca, y un equipo podía quedar con dos filas y sin
  poder leerla); migración v50 deja una sola.

## Sin probar en real

- Conciliación de Mercado Pago contra la cuenta real en un cierre.
- Bienvenida, "Entrar con Google" y "Configurá tu negocio" en un celular real y contra la nube real.
- Pagar proveedor del celular contra la PC real; sync por la nube con dos dispositivos reales (WebSocket/Durable Object).
- Una actualización real de una PC instalada contra el feed real, y que WinSparkle rechace una firma inválida.
- Impresión física de prueba en la Point (consume un ticket; la corre o autoriza el dueño).
- Ganancia real en vez de markup (migración v46) y asistente contable (primera parte): se escribieron sin Flutter en la
  sesión; correr `flutter analyze` y `flutter test` antes de darlos por cerrados.
- **Validación real del dominio**: correr una semana en paralelo con el sistema anterior y comparar cierres. Los tests
  prueban que el código hace lo pedido, no que el modelo de negocio sea correcto.

## Pendiente

**Pedido por el dueño / a confirmar antes de arrancar** (lista completa y orden de interés en `CONTEXTO.md` §7):
integración con Mercado Pago: **solo queda el QR en pantalla sin terminal** (el dueño, 2026-10-04: "de momento no"; Orders API
`type: "qr"`, `config.qr.mode: "dynamic"`, hace falta crear una sucursal y una caja en MP) y el saldo real en el cierre del
celular; pagar a un proveedor con MP desde el celular; "etapa 3" de MP (esconder token/terminal locales como avanzado); motivo
obligatorio en cada gasto.

**Pendientes técnicos conocidos:**

- (Resuelto el 2026-10-04: cobrar un fiado ahora es atómico e idempotente, y separar/pagar proveedor van en transacción; ver
  `TRAMPAS.md`.) Las búsquedas tipo "7 up" ya se arreglaron (`docs/PLAN.md`, 0.8).
- Ventas abiertas: decidir si el fiado pasa a ser una venta abierta con nombre; refrescar precios de un borrador viejo.
- Cuenta corriente: falta la deuda total en el Dashboard de la PC (el celular la muestra arriba de Más › Cuenta corriente).
- Promos: una venta ya cobrada se edita como líneas sueltas. Precio automático por proveedor:
  el celular no tiene el selector ni sincroniza el % y la marca de fijo.
- Dos caminos para reimprimir un ticket (pantalla Impresión y detalle del día en Historial), sin unificar.
- Limitación conocida: en una venta mixta con varios productos no se sabe cuál se pagó con qué medio (no se guarda medio de
  pago por línea). Los montos y el arqueo salen bien; arreglarlo es un cambio de modelo, y el dueño dejó que quede así
  (`lib/data/planilla_dia.dart`).
- Carga histórica: sigue producto por producto (el mock proponía totales del día con costo estimado; el dueño decidió no).

- Clave privada DSA (`Documents\la_plazoleta_claves\dsa_priv.pem`): respaldarla (USB + otro lugar). Si se pierde, ninguna PC
  instalada recibe más actualizaciones. Firma de código real: sin certificado todavía (SmartScreen avisa).

## Descartado (decisión del dueño, no pendiente)

- Descuento de Cliente Frecuente (Regla 17): no se hace. Las columnas `clientes.descuentoBp` y `ventas.descuentoCentavos`
  quedan sin usar a propósito (borrarlas es una migración sobre datos reales para no ganar nada).
- Reportes y Equilibrio como pantallas aparte (hoy Equilibrio es la mitad "del mes" de Inicio), retiro semanal de ganancias.

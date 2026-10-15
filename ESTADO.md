# Estado actual — La Plazoleta / Nodo Sur POS

**Fuente de verdad de cómo está el proyecto HOY.** Corto a propósito: lo que ya se resolvió vive en `DECISIONES.md`
(por qué se hizo así) y `TRAMPAS.md` (bugs que no hay que repetir); el detalle cronológico anterior al 2026-10-03 está en
[`docs/archivo/ESTADO-ARCHIVO.md`](./docs/archivo/ESTADO-ARCHIVO.md). Si algo de acá contradice al código o a `git log`, gana el código y
se corrige este archivo. Para retomar desde cero: `CONTEXTO.md`.

Se actualiza al cerrar cada sesión de trabajo. **No agregar acá historias de "Resuelto"**: una línea en "Últimos cambios"
y el detalle en `DECISIONES.md`.

---

## Publicado (al 2026-10-12)

- **Windows**: estable 1.0.0.2160 (10/10); betas hasta la 1.0.0+2163 (11/10). Los APK (almacén y Nodo Sur Servicios)
  salen con el mismo merge `release:`/`beta:`. El número exacto de cada plataforma, en `/admin/` → Versiones.

Lo de abajo es del 03/10 y queda como historia del incidente de la 2129:

- **Windows**: estable 1.0.0.2129 (03/10, al 100 %).
- **Android**: estable 1.0.0+2130 (03/10, al 100 %). **La 1.0.0+2129 de Android quedó rota**: una segunda
  publicación con el mismo número pisó su archivo en R2 y el sitio conserva la firma del anterior. La 2130 la reemplaza
  (los celulares toman la más nueva). La 2129 quedó **bloqueada** en el sitio (03/10).
- **Sitio** (`NodoSurPage`): en producción al mezclar a `main`.

## Rediseño de la PC v3/v4 — mocks (05–06/10/2026) y aplicación al código (desde el 06/10)

El dueño rechazó el aspecto de la app de escritorio y pidió **rehacerla desde cero** (disposición incluida) con el lenguaje de
horsepos.com y antigravity.google. Se hicieron **dos versiones**:

- **Expresiva** (primera): títulos que se tipean, partículas, mega-menú, tablero 3D, cinta de avisos, cursor-pastilla. El dueño dijo
  que para la caja **se exageró un poco** (hay que poder leer claro y, en lo posible, **sin scroll**), **pero le gustó para la web**:
  queda **guardada para el sitio** en [`docs/archivo/ESTILO-EXPRESIVO-WEB.md`](./docs/archivo/ESTILO-EXPRESIVO-WEB.md) y
  `docs/mock-pc/NodoSurPC-v3-expresivo.html` (vivo: https://claude.ai/artifact/DnUi6qvYDxZpgpD3uh14js). **Pendiente: llevarla al sitio**
  (repo `NodoSurPage`, fuera de este repo).
- **Sobria** (la de la PC): cada pantalla entra en 1920×1080 sin scroll de página, títulos chicos, sin partículas/3D/cinta/títulos tipeados.
  Especificación para aplicarla: [`docs/archivo/ESPECIFICACION-PC-V3.md`](./docs/archivo/ESPECIFICACION-PC-V3.md) y `docs/mock-pc/NodoSurPC-v3.html` (vivo: https://claude.ai/artifact/Kq4qCixuDtGpRKS1sjKxxj).

**Ronda 3 (05/10):** el dueño pidió rapidez inmediata y cero fricción, IA siempre a mano (no escondida en Configuración),
**Pagar proveedor** como acción principal de caja (gasto/ingreso secundario), navbar sin logo/nombre/lupa, tuerca para Configuración y
mucha información legible. Está en la especificación (secciones 4.2, 4.5, 7.x, 8 y **15**) y en el mock sobrio; funciones nuevas a confirmar
en 14.3 (asistente con pregunta libre, IA contextual, medio inicial Efectivo, "Venta cobrada" que se cierra sola).

**Ronda 4 (05/10):** el dueño pidió **eliminar redundancias** (dejar lo más práctico a mano), sacar las tarjetas de IA del medio de Inicio,
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

(Al momento de esa auditoría todavía no se había tocado código de Flutter; la aplicación empezó el 06/10, ver arriba.) Reemplaza
al mock y a la comparación de la sección siguiente.

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
- **¿Quién sos?**: el perfil sale de la cuenta con que se entró (decisión del 2026-10-02), no de una lista.
- **Bienvenida**: se conserva la animada de la app (el mock tiene 6 escenas estáticas).
- **Terminal**: en los fallos se suma un botón "Cancelar" que el mock no tiene.
- **Encargues**: las líneas no muestran precio (el servidor del celular no los manda).
- **Pagar proveedor**: sin alias/CVU (en el mock es solo una propuesta de diseño).
- **Animación de pantallas**: fundido cruzado en vez del fade + subida del mock (decisión del dueño, APK 2135).
- **Más**: sin "Historial de ventas" ni "Tablero del día" como filas (el historial está en Caja › Ventas y el tablero en Inicio),
  y "Probar estados" es solo del mock.

Pendiente / ideas (sin hacer):
- **Nodo Sur para servicios: barbería, uñas y belleza** (El dueño, 2026-10-09): una sola app; el rubro elegido en el
  onboarding decide qué pantallas se ven, y todo es un módulo opcional. Agenda con turnos por WhatsApp, servicios con receta
  de insumos y calculador de costo, descuento de insumos al cobrar, seña configurable. **Etapas 1 a 5 hechas y mezcladas**
  (rubros, servicios con insumos, cobrar servicios, Agenda, turnos del bot; ver "Últimos cambios" del 09 y el 10/10); plan en
  [`docs/PLAN-SERVICIOS.md`](./docs/PLAN-SERVICIOS.md). Solo en el celular: la PC no tiene lo de servicios.
- **Bot de WhatsApp configurable desde Nodo Sur, todo desde el celular** (El dueño, 2026-10-09): primero la cuenta del
  almacén. Plan en [`docs/PLAN-BOT.md`](./docs/PLAN-BOT.md). Etapas 1 a 4 hechas y mezcladas (esta app en
  el release #94; `NodoSurPage` #55; `botdemo`): rubro guardado (v63), `/api/bot/*` en el sitio, el
  bot en Termux y, en el celular, **pedidos por confirmar en Encargues** (Aceptar los aparta, sin stock dice qué falta y no
  acepta; Rechazar no toca nada) y la pantalla **Más › Bot de WhatsApp** (estado, configuración para dueño/encargado,
  instalar). La PC también publica el catálogo: **hace falta un release nuevo de Windows** además del APK. Probado con
  tests; **nada probado en un celular real ni con WhatsApp real**. La etapa 5 (notificaciones con la app
  cerrada) también está hecha (10/10).
- **Abrir la caja desde el celular sin la PC** (El dueño, 2026-10-07/09, independencia del celular, etapa 1, opción A):
  con el modo **"Solo celular"** el celular abre la caja sobre su propia base (antes daba "No se puede abrir una nueva
  desde acá" y el modo solo celular no podía arrancar el día). En "PC y celular" sigue bloqueado, para no tener dos cajas
  abiertas. `ServicioCompanionOffline.abrirSesion` + `esSoloCelularGuardado` (`emparejamiento.dart`). Probado con tests;
  **no probado en un celular real**. Siguen: ticket sin la PC, avisos de MP en el celular, saldo de MP en el cierre,
  seña y precio de encargues.
- **Pago mixto en el celular** (El dueño, 2026-10-09, etapa 2): quinto medio "Mixto: efectivo + Mercado Pago"; se escribe
  el efectivo, se ve el resto y se elige QR, débito o crédito para el resto. La terminal cobra solo el resto; "Cobrar a mano"
  también sirve. Con la PC va por rutas nuevas (`/ventas/mixto/...`): una PC sin actualizar contesta 404 y el celular pide
  actualizarla, en vez de cobrar el total entero en la terminal. Sin la PC, sobre la base propia. El efectivo tiene que
  ser más de $0 y menos que el total (`validarEfectivoMixto`). Crédito pasa al color de débito y el mixto recupera el suyo.
  Probado con tests; **no probado en un celular real ni con la terminal real**.
- **Funciones de la PC en el celular** (El dueño, 2026-10-07: "que las funciones del sistema desktop estén disponibles para el apk, reutilizando la lógica"): hechas la lectura de facturas, pagar proveedor sin la PC, promos (con sugerencias), la cuenta corriente y separaciones completas. **Comparar precios queda de lado** (El dueño, 2026-10-07: "eso dejémoslo de lado"): La Anónima y Carrefour salen de un archivo de ~330 MB por día que el celular no puede bajar; no se decidió de dónde los sacaría. Criterio: sacar la lógica de la pantalla de la PC a `servicios/`/`data/` y que el celular trabaje sobre su base propia.
- **Rediseño v4, etapa 8 (2026-10-06)**: hechos el **Asistente Ctrl+K**, el **WhatsApp del proveedor** (migración v53; botón "Pedir por WhatsApp" con lo de stock bajo) y el **logo del ticket** en el PDF (migración v54, `schemaVersion` **54**). La **seña de encargues** está hecha en la PC (migración v55, `schemaVersion` **55**; ver `docs/PLAN-SENA.md`; falta probarla en una Windows real). **Sucursal y Miembros**: la PC ya los muestra (Configuración › Cuenta de Nodo Sur) pero depende de un endpoint nuevo del sitio (`GET /api/device/team`) ya aplicado en `NodoSurPage` (PR #51, 2026-10-06). Detalle en `docs/PLAN-APLICAR-V4.md`.
- **IA de Google (Gemini) y promos sugeridas, 2026-10-05**: cliente en `lib/servicios/gemini.dart`; la clave se carga en Configuración › Asistente IA de la PC y del celular (desde el 2026-10-07 es la del negocio, guardada en la cuenta: ver "Clave de la IA por cuenta" en `DECISIONES.md`; `probarYGuardarClave` no guarda una clave rota y elige el modelo que le anda a la clave: la 2133 de Windows salió con `gemini-2.5-flash` fijo y daba 404 con claves nuevas, corregido después). **Sugerir promos** (solo PC, Proveedores › Promos › "Sugerir promos"): `domain/sugerencia_promos.dart` busca los pares que se llevan juntos (≥2 ventas, lift ≥ 1,2, últimos 90 días, sin anuladas), `data/repositorio_sugerencia_promos.dart` les calcula el precio con `calcularPromo`, y Gemini (`servicios/asistente_promos.dart`, que no ve precios ni costos) solo les pone nombre y motivo; cada sugerencia deja elegir el porcentaje como el creador; sin clave o sin cupo se ven igual con "A + B". "Crear" abre el creador precargado. Probado con `flutter analyze` y tests; **no probado con una clave real de Google ni en un celular**. Desde el 2026-10-07 el celular tiene promos con sugerencias. **Facturas de compra con IA**: plan en `docs/PLAN-FACTURAS.md` (decidido el 2026-10-05); hechas las cuentas (`domain/factura_compra.dart`) y la lectura con Gemini (`servicios/lector_facturas.dart`, `domain/lectura_factura.dart`, achicar la foto) con la pantalla en Proveedores › "Leer factura"; **no probada con la clave ni las facturas reales**; hechos también los vínculos con tus productos (por CUIT del proveedor, aprendido, parecido de nombre y ayuda de la IA; migración v52, `schemaVersion` **52**); **bultos vs. unidades** propuestos por la descripción y el costo que ya tenés cargado (`domain/unidades_bulto.dart`, confirmás vos y se aprende por producto); **aplicar** hecho el 2026-10-07 (stock, costo, deuda, "No va", aviso de precio perdedor, sin repetir, "Deshacer"; migraciones v56–v57). Falta: notas de crédito, adjuntar la imagen y el celular con cámara.
- **Promos**: "Promo Fernet Coca" está cargada sin componentes (`promo_componentes` vacía): no descuenta el Fernet ni la Coca.
- **Reporte "ventas desde el último ingreso de stock"**: ofrecido, sin hacer.

## Últimos cambios (15/10/2026)

- **Nodo Sur Servicios en la compu** (El dueño, 15/10; mock aprobado): con la ventana ancha (web y Windows) la app de servicios
  tiene menú lateral (Alt+1…5), la Agenda con el turno al costado y Cobrar con el cobro a la derecha. Y una **edición de
  Windows aparte** (otro `.exe`, ícono ciruela, su carpeta de datos y su base fuera de Documentos, instalador y feed
  `windows-servicios`). Publicada en beta (1.0.0+2176). **Sin probar en una PC real**. Todo en
  [`docs/PLAN-ESCRITORIO-SERVICIOS.md`](./docs/PLAN-ESCRITORIO-SERVICIOS.md).

- **Servicios en la compu sin partes de celular** (El dueño, 15/10: "se ven partes de móvil, la vinculación sigue siendo por
  navegador y tarda mucho"): lo que se abre desde una pestaña queda al lado del menú, las hojas son ventanas al centro, entrar
  tiene panel de marca y **QR para entrar con el celular** (Más › Cuenta › "Entrar en una compu"; sitio: `/api/device/qr`).
  Al volver de entrar, una sola vuelta de sincronización. Sin probar con equipos reales.

- **El bot de WhatsApp también corre en la compu** (Nodo Sur Servicios de Windows): el mismo bot del Android con el Node de
  Windows, un supervisor que lo mantiene vivo y arranque oculto al iniciar sesión. Sin probar en Windows real.

## Últimos cambios (14/10/2026)

- **Nodo Sur Servicios vende productos** (El dueño, 14/10): solapa Productos en Servicios (alta, compra, conteo, editar) y
  "+ Producto" al cobrar, junto al servicio o suelto. Sin stock se vende con aviso. Detalle en `DECISIONES.md`. Falta: que el
  sitio lo diga (`/servicios/` y las páginas por rubro) cuando salga.

- **Ícono propio de Nodo Sur Servicios** (El dueño, 14/10): misma familia que "pos" (Figtree, punto abajo) pero dice
  "turnos", fondo ciruela `#5B1F45` y letras `#F6E7EF`. Distingue las dos apps en el mismo celular. Detalle en `DECISIONES.md`.

- **"Configurá tu negocio" en Servicios pregunta el horario de atención** (paso 3 de 4: días y franja, la misma para todos;
  un día distinto se ajusta en Configuración › Agenda y seña). Antes el bot ofrecía turnos en el horario de fábrica. En
  almacén siguen siendo tres pasos. "Conectar" e "Invitar" del último paso ahora se ven como botones.

- **Revisión de Nodo Sur Servicios** (El dueño: "la configuración no guarda"): la causa era guardar sobre una fila de
  configuración que en ese celular no existía (ver `TRAMPAS.md`). Además: doble toque que anotaba turnos, señas y compras dos
  veces; errores que no se mostraban; la Agenda o su configuración colgadas si fallaba la lectura; WhatsApp sin código de país;
  la misma clienta duplicada por el teléfono escrito distinto; títulos en "Nuevo turno". Capturas en
  `test/companion/capturas_servicios_test.dart`. **Falta probarlo en el celular.**
- **Registro y negocio nuevo** (misma revisión): el nombre que el dueño pone en "Configurá tu negocio" o en Configuración ahora
  llega al sitio (`/api/device/negocio`): antes el negocio quedaba "Negocio de (nombre de Google)" para siempre en la lista de
  negocios del celular y en horsepos.com. El asistente propone el nombre ya conocido (antes lo pedía en blanco), no se traba si
  guardar falla, y en Servicios la Agenda muestra la tarjeta de pasos pendientes (antes solo estaba en el Inicio de almacén).

- **Beta o Estable en el celular** (las dos apps), solo para cuentas de prueba: Más › Actualización. Hasta ahora el celular nunca
  veía las betas. Necesita el sitio desplegado (`solo=1`). Probado con tests; falta verlo en un celular.
- **Point Tap descartado**: Mercado Pago no deja pedir el cobro desde otra app (probado en un celular). Se sacó la prueba.

- **Cambiar de negocio en el celular ya no cierra la app** (El dueño: "necesito que funcione íntegramente sin cerrarse"):
  se frena y se olvida todo lo de la cuenta y la app se arma de cero. Probado con `flutter analyze` y tests; **falta probarlo en
  un celular**. Detalle en `DECISIONES.md`.
- **Entrar con Google sin navegador anda en el celular** (14/10): los dos clientes Android quedaron en el proyecto del Web.

## Últimos cambios (13/10/2026)

- **El stock se duplicaba en un equipo que bajaba todo de cero** (El dueño: "el stock subió y yo no lo subí"): arreglado con la
  base de stock (v67). Los equipos ya desfasados se corrigen solos cuando el equipo donde nació cada producto sube su base.
- **Perfiles repetidos** ("aparezco tres veces"): mismo nombre = misma persona; se muestran una vez y lo cargado pasa al que queda.

- **El celular entra con Google sin abrir el navegador** (El dueño: "la vinculación por el sitio es un paso medio innecesario"):
  selector de cuentas de Android + `POST /api/device/google` del sitio; si no anda, "Entrar con el navegador". Los dos clientes
  OAuth tipo Android quedaron en el proyecto del cliente Web (`433741777622`) y el dueño lo dio por andando el 14/10. Detalle en
  `DECISIONES.md`.
- **Varios negocios en un mismo celular, sin mezclar ni cerrar sesión**, y una cuenta de Google con varios negocios, cada uno
  con su plan (un mail con N planes cubre sus N negocios más viejos). "Agregar otro negocio" en Cuenta y sincronización.
  Sin probar en un teléfono real. Detalle en `DECISIONES.md`.
- **Publicar los APK tardaba ~22 min** (El dueño: "me molesta la lentitud"): el APK de almacén compilaba Android de cero (~19 min,
  casi todo Gradle) y el de Servicios, con eso ya hecho, ~2 min. `publicar-apk` ahora guarda Gradle entre corridas
  (`gradle/actions/setup-gradle` + build cache). La primera corrida después del cambio llena el caché; se mide en la segunda.
  Separar Servicios en otro repo no lo arreglaba (seguiría compilando de cero) y duplicaba base, sync y cobro.
- **Turnos y señas del bot tardaban en aparecer** (El dueño: "tardó en aparecer, pero apareció", con la beta que ya redibujaba la
  Agenda): un aviso en vivo que llegaba mientras la app ya estaba bajando turnos se sumaba a esa bajada, que había pedido la lista
  antes; el turno o la seña entraban recién en la próxima vuelta de la sync. Ahora, si llega un aviso en el medio, al terminar se
  hace otra vuelta (`SincronizadorTurnosBot.vuelta`). Test que lo reproduce (falla sin el arreglo).

- **Un turno del bot ya no se pierde** (El dueño, probando de punta a punta: "se confirma el turno, se confirma la seña, pero en
  la aplicación no aparece"): si un turno del bot no se podía cargar (el servicio no estaba en la app con ese nombre, un error al
  crearlo, sin usuario), se salteaba callado y el cursor seguía: no se reintentaba nunca. Ahora queda guardado, se reintenta en
  cada vuelta y la Agenda muestra por qué no entró ("el servicio «X» no está en Servicios…"). El servicio se busca sin importar
  mayúsculas, acentos ni espacios. `servicios/turnos_bot_nube.dart`. Probado con tests; **falta confirmar en el celular** que
  esa era la causa (si no aparece ni el turno ni el aviso, es otra).

- (Point Tap: la prueba se sacó el 2026-10-14. En el celular la app de Mercado Pago no atiende el pedido de cobro de otra app;
  ver `DECISIONES.md`, "QR de Mercado Pago en la pantalla".)

- **QR de Mercado Pago en la pantalla, en cualquier negocio** (El dueño: "que la app cree un QR y lo muestre en la pantalla…
  que se pueda configurar"): en el celular de almacén y en la web, además de Nodo Sur Servicios. Se elige en cada equipo
  (Configuración › Cobro: automático, en la pantalla, en la terminal Point o preguntar cada vez); arranca en automático: a la
  terminal si la sucursal tiene una, a la pantalla si no. Sin terminal no se ofrecen débito ni crédito. La PC no muestra el QR
  (sigue con la terminal) y el celular conectado a la PC cobra como la PC. `domain/cobro_qr.dart`. Probado con tests; **falta
  probarlo con la cuenta real** (la orden QR la crea el sitio, como en Servicios). Cobrar con tarjeta por NFC (Point Tap) desde la
  app: no se puede (probado el 14/10), se descartó.

- **Tablero arriba de la Agenda** (servicios; El dueño eligió las tres tarjetas y "Compartir huecos"): **Ahora** (el turno en
  curso o el que sigue, cuántos turnos y huecos quedan), **Plata de hoy** (cobrado en efectivo y Mercado Pago, y lo que falta
  cobrar con la seña descontada) y **Para atender** (señas que no llegaron, quien viene y ya faltó, insumos por acabarse).
  **Compartir huecos** arma el texto con los horarios libres de los próximos 3 días con lugar, para mandar por WhatsApp o copiar
  a una historia. Cuentas en `domain/tablero_agenda.dart`, datos en `data/repositorio_tablero_agenda.dart`. Probado con tests y
  una captura; falta verlo en un celular real.

- **El bot no ofrecía turnos para hoy** (Nodo Sur Servicios): el Node que corre adentro de la app arrancaba sin zona horaria, en
  UTC; con la anticipación mínima de 2 horas, hoy quedaba siempre "en el pasado". La app le pasa la zona del celular
  (`ServicioBot.kt`, `TZ`) y el bot, sin zona, usa la de Argentina (`botdemo/src/zona.js`). **Publicar el APK y `botdemo` juntos.**
- **Un turno del bot aparece en la Agenda al toque** (y la seña pagada también): el sincronizador de turnos del bot avisa a las
  pantallas cuando baja algo (`alBajar`); antes la Agenda se enteraba recién al cambiar de pantalla.

- **Barbería de ejemplo en una cuenta de verdad** (para grabar los reels con la app real): 7 toques en el título de Más ofrecen
  cargar la misma barbería de la demo (`companion/demo/sembrar_ejemplo.dart`), solo con la base sin turnos, ventas ni cajas.
  Viaja por la sync como cualquier dato. Probado con tests; **falta verlo en un celular real** (necesita un APK nuevo).

- **Plan para muchos rubros** (`docs/PLAN-RUBROS.md`, sin código): tercera forma de trabajar, "pedidos", empezando por quien
  emprende con comidas por encargo (reutiliza recetas e insumos de servicios, Encargues y el bot); antes, ordenar la base para
  que un rubro nuevo sea solo datos. Preguntas de negocio abiertas al final del plan.

- **Menos contexto por sesión de Claude**: `CLAUDE.md` pasó de ~24 KB a ~4 KB (se carga en cada turno); lo largo (pantalla de
  venta, hardware, fases) se movió tal cual a `docs/CLAUDE-DETALLE.md`. `CONTEXTO.md` pide leer solo la sección que toca, y
  `.claude/settings.json` no deja leer código generado, builds ni `docs/archivo/`.
- **Tests solo de lo afectado** (`tool/tests_afectados.dart`): sigue los imports desde lo cambiado; un cambio en la Agenda corre
  189 tests en 1,5 min en vez de la suite entera. CI: en un PR corre solo los afectados y saltea la compilación web si no se
  tocó código; en `main`, la suite entera. Flutter se instala solo en las sesiones en la nube (`.claude/hooks/session-start.sh`).
  `botdemo` tiene CI por primera vez.

## Últimos cambios (12/10/2026)

- **Demo de Nodo Sur Servicios** (`horsepos.com/demo/`; `docs/PLAN-DEMO-SERVICIOS.md`): la app web sin entrar con Google, con un
  negocio de ejemplo a elegir (barbería, peluquería, uñas, estética) con turnos, cobros y caja; todo en memoria, se borra al
  cerrar. Mercado Pago simulado. Franja con "Probar gratis". Sale con la app web. Probada en Chromium; falta un iPhone real.
- **Nodo Sur Servicios en el navegador** (`horsepos.com/app/`; `docs/PLAN-WEB-SERVICIOS.md`, motivos en `DECISIONES.md`): la misma
  app del celular, compilada para web, con todo (agenda, turnos, cobrar, servicios, caja, configuración); el bot sigue en un
  Android. Entrar con Google, sync por la nube con avisos en vivo, base guardada en el navegador. Se publica con `release:`
  (`publicar-web.yml`); CI la compila en cada PR. Probado en Chromium contra el sitio local; **falta un iPhone real y el sitio
  real**. Arreglo de paso: entrar desde un equipo nuevo ya no duplica a la persona.
- **Revisión de los tres repos** (código, documentos y tests). Arreglado:
  - Sitio: **devolver la seña** por Mercado Pago pide el permiso `devolver` (dueño o encargado), como devolver una venta; antes
    lo podía hacer un empleado. El **token del bot de WhatsApp** solo sirve para `/api/bot/*`, escuchar avisos y `device/me`/`ping`
    (antes podía cobrar, devolver o bajar la sync de la sucursal). **Turnos y pedidos del bot**: una página ya no corta un grupo
    de cambios con la misma hora (con más de 200 turnos de la app publicados juntos, el bot dejaba de ver los que pasaban de
    200). **Vincular un equipo** con el id de otro que sigue en uso da `device_ajeno` en vez de pisarlo.
  - App: aplicar un movimiento de stock de la sync (grabarlo y moverle el stock al producto) va en una transacción por fila.
    El test `escucha_pc_test.dart` esperaba un tiempo fijo y fallaba a veces en máquinas lentas.
  - Documentos: `CLAUDE.md` (la nube, lo configurable, avisos de MP en el celular), `CONTEXTO.md` y este archivo.
- **Sitio: página de Nodo Sur Servicios** (`horsepos.com/servicios/`, repo `NodoSurPage`): agenda, bot, señas, cobro con QR,
  costo por servicio, precio del plan Emprendedor y preguntas frecuentes, con capturas reales de la app; "Servicios" en el
  menú de todo el sitio. **La PC no tiene lo de servicios** (es solo del celular).
- Vistos y **sin tocar** (ver "Pendientes técnicos"): el stock contado dos veces en un equipo nuevo, y la publicación.

## Últimos cambios (10/10/2026)

- **Nodo Sur Servicios** (mezclado y publicado en beta, PR #104 a #107; plan en `docs/PLAN-APP-SERVICIOS.md`): segunda edición
  del celular (flavor `servicios`, `com.laplazoleta.servicios`) que se instala al lado de la de almacén. Solo lo de servicios y caja
  simple; **el bot de WhatsApp corre adentro** (Node de Termux empaquetado, `ServicioBot.kt`), sin Termux, vinculado sin navegador
  (`POST /api/bot/token`). Seña con **link de Mercado Pago** (media hora, se confirma sola, recibo por WhatsApp, devolución con un
  toque) y cobro con **QR en la pantalla** (orden QR dinámica). El workflow arma y publica las dos (`android` y `android-servicios`).
  Probado: Node, SQLite, internet, Baileys y la conexión cifrada con WhatsApp en el celular del dueño (10/10). **Falta**: la prueba
  larga con la pantalla apagada, un turno real con la seña por link, el id de app de Firebase de la edición nueva y el plan Emprendedor.
- **Agenda** (etapa 4 de `docs/PLAN-SERVICIOS.md`, reglas en `REGLAS-NEGOCIO.md` §21; migración v66, `schemaVersion` **66**): en
  un negocio de servicios la pestaña Inicio pasa a ser la **Agenda** y la app abre ahí. Turnos del día por hora; "+ Turno" con
  los horarios libres cada 15 minutos (u otra hora a mano: sobreturno o fuera de horario, avisa y deja); cada turno se cobra
  con la seña descontada (efectivo o Mercado Pago a mano), se anota la seña, se mueve, "no vino" (el cliente lleva la cuenta),
  se cancela (la seña se pierde o se devuelve según lo configurado), WhatsApp y Google Calendar. Más › Configuración › **Agenda
  y seña** (horario de atención, cada cuánto arrancan los turnos, seña nunca / algunos / todos, % o monto fijo, alias) y
  **"Pide seña"** en cada servicio. Una seña sin caja abierta entra al abrir la próxima. Probado con tests; **falta verlo en
  un celular real**. Lo que no se hizo: profesionales con agenda propia en pantalla (la base ya los separa), cobrar un turno
  con la terminal Point (se cobra a mano o desde Vender).
- **Turnos del bot en la Agenda** (etapa 5, versión simple, `DECISIONES.md`): el bot reserva cada turno en el sitio (que no
  deja dar dos veces el mismo horario), el equipo que sube la sync lo baja a la Agenda, le avisa al bot lo que hace la dueña
  (mover, cancelar, cobrar, anotar la seña) y publica lo que ocupa la Agenda sin datos de clientes. Los servicios, el horario y
  la seña del negocio le llegan solos al bot (sin configuración aparte). **Hace falta publicar los tres repos juntos.**
- **Notificaciones con la app cerrada** (etapa 5 de `docs/PLAN-BOT.md`): el celular registra su token de Firebase y el sitio
  le manda los pedidos y turnos nuevos del bot. El proyecto de Firebase ya está cargado en
  `lib/servicios/push.dart` (`opcionesFirebase`, release #102); del lado del sitio hace falta el secreto `FCM_SERVICE_ACCOUNT`
  en Cloudflare (no se puede ver desde una sesión: confirmarlo con el dueño).

- **Cobrar servicios** (etapa 3 de `docs/PLAN-SERVICIOS.md`, reglas en `REGLAS-NEGOCIO.md` §20): en un negocio de
  servicios, Vender es una grilla de servicios; cobrar descuenta los insumos, la línea guarda lo que costaron ese día (sin
  mano de obra), anular o editar los devuelven, "+ Propina" después de cobrar y "Para reponer insumos" en Caja. Solo
  "Solo celular". Probado con tests; falta verlo en un celular real.
- **Cerrar sesión y borrar este celular** (Más › Cuenta; El dueño: "no se puede cerrar sesión y eliminar los datos sin
  borrarlos desde configuraciones"): con cuenta, primero sube lo que falte; borra la base, la cuenta, la sync y las
  preferencias, y cierra la app. Al abrirla arranca de cero.
- **Un negocio de servicios ya no ve lo de almacén** en el celular (El dueño: "muchas cosas siguen siendo genéricas de
  almacén"): el alta pide el primer **servicio** (nombre, duración y precio) en vez de escanear un código; Configuración sin
  cigarrillos, vuelto ni ganancia por categoría; Caja en Resumen y Ventas (sin Separar); Inicio sin "Separar para
  proveedores", sin stock bajo y con atajos de servicios; Más sin Promos ni Carga histórica; la campanita sin avisos de
  stock ni de separar; el buscador de funciones sin lo de almacén y con servicios e insumos; Vender avisa que cobrar
  servicios llega en la próxima actualización. Nada se borra: un almacén ve todo como siempre.

## Últimos cambios (09/10/2026)

- **Servicios, etapas 1 y 2** (`docs/PLAN-SERVICIOS.md`; mezclado, release #96): rubros **Barbería**, **Uñas
  y belleza**, **Peluquería**, **Estética** y **Otro servicio** en el alta y en Configuración › Tu negocio del celular (en dos
  grupos); la forma de trabajar sale del rubro y esconde a un negocio de servicios lo que es de un comercio con stock. En "Solo
  celular", la pestaña Productos pasa a **Servicios**: servicios con costo, ganancia y para cuántos alcanza; insumos con compra
  por envases, conteo y poco stock; creador con el costo en vivo y el precio sugerido; valor de la hora en Configuración.
  Migración v65. Cobrar servicios (descontar insumos) es la etapa 3. La Plazoleta no cambia. Probado con tests; **falta verlo en
  un celular real**. Motivos en `DECISIONES.md`. El bot suma `peluqueria`, `estetica` y `servicio`, y un salón con turnos ya no
  se vuelve comercio si la app le manda un rubro de comercio (`botdemo`, misma rama).
- **Independizar el celular de la PC** (El dueño: "¿qué falta para independizar?"; sobre el modo "PC y celular": "dejalo como
  respaldo"). La nube pasa a ser el camino principal; el wifi con la PC queda de respaldo. Hecho:
  - **Abrir la caja con la PC apagada** en "PC y celular": se sincroniza por internet y, si con lo último de todos no hay una caja
    abierta, el celular la abre y la sube al instante. Sin internet sigue bloqueado. Queda una ventana de un par de segundos si
    dos equipos abren a la vez (cerrarla del todo pide un candado en el servidor, repo `NodoSurPage`).
  - **Imprimir el ticket sin la PC**: en la terminal Point por el servidor de Nodo Sur (`PuertoLocal.imprimirTicket`). Las ventas
    grabadas en la PC se siguen imprimiendo por la PC.
  - **"Traer saldo de Mercado Pago"** en el cierre del celular, como en la PC.
  - **Categorías nuevas** desde Configuración del celular (viajan por la sync).
  - **Avisos de Mercado Pago** en la campanita del celular (el mismo `ServicioAvisosMp` de la PC), solo en "Solo celular": con
    PC los muestra la PC y "Visto" no viaja entre equipos.
  - **Seña de encargues desde el celular**: al apartar (entra a la caja abierta, efectivo o Mercado Pago) y al cancelar (se devuelve),
    sin la PC y con la PC (rutas `/encargues` y `/encargues/<id>/cancelar` aceptan la seña). Cobrar o anotar deuda de un encargue
    con seña conectado a la PC sigue yendo por la PC (409).
  - **Gastos fijos sincronizados** (migración v64, `schemaVersion` **64**; iba a ser la v63, que quedó para el rubro del bot): `gastos_fijos` y `gastos_fijos_montos` con identidad
    de sincronización; el mismo nombre en dos equipos es un solo fijo, y `movimientos_de_caja.gasto_fijo_id` se traduce por
    `global_id`. En el celular: Configuración › Gastos fijos (alta, monto del mes, vencimiento). Arreglo del motor de sync: dos
    filas "iguales" por clave natural creadas en el mismo segundo se quedan con el `global_id` menor (antes no convergían).
    **Publicar la PC y el APK juntos** (un equipo sin v64 ignora esas filas). Esta rama ya trae la del bot (`ccr-e5e5b532-aj3e0g`): se publica después de ella o junto.
  - **"¿A dónde fue esta plata?" en el cierre del celular**: con un faltante desde el mínimo, se anota como gasto mío, proveedor,
    fijo u otro gasto (en partes), con el mismo `anotarFaltante` de la PC; cerrar sin explicar avisa antes. Con la PC, rutas
    nuevas `GET/POST /cierre/faltantes` (una PC vieja contesta 404 y el celular no pregunta). El fondo fijo ya no entra en
    ninguna cuenta: no hace falta en el celular.
  - **"+ Nuevo proveedor" y "+ Nueva categoría" en el formulario de producto**, solo sobre la base del celular (con la PC
    conectada el producto se guarda en la PC con sus ids y lo nuevo del celular no existe ahí hasta la sync).
  - **Encargues con precio**: "Hoy sale $X" (y lo que falta cobrar si hay seña), a precios de hoy (`totalHoyDeEncargue`).
  Falta: dejar de preguntar el modo al configurar. **Reserva diaria de fijos y día del retiro semanal ya no se usan** (columnas vestigiales), no hace falta pasarlos.
  Probado con tests; **no probado en un celular real ni con la Point/cuenta real**.
- **El rubro del comercio queda guardado** (bot de WhatsApp, etapa 1 de [`docs/PLAN-BOT.md`](./docs/PLAN-BOT.md)): columna
  `rubro` en la configuración del negocio (migración v63, `schemaVersion` **63**), que viaja por la sync. Se elige en el celular,
  Configuración › **Tu negocio** (Kiosco, Almacén, Fiambrería, Otro), con o sin PC; el asistente de negocio nuevo y las plantillas
  de la PC lo guardan solos. Un negocio armado antes nace **sin elegir** (el rubro no se guardaba y no se adivina). Con una PC sin
  actualizar, el celular avisa que hay que actualizarla. Probado con tests; **no probado en un celular real**.
- **Vender en el celular sin la pantalla "Venta cobrada"** (El dueño: "siento que hay una pantalla extra"): al cobrar se vuelve
  directo a una venta nueva con el buscador listo, y arriba queda una tarjeta con el total, el vuelto bien grande e "Imprimir
  ticket", que se va sola al agregar el primer producto de la siguiente (o con la ✕). Un toque menos por venta. Probado con tests;
  **no probado en un celular real**.
- **Vender en el celular, con el teclado** (El dueño: "arriba del teclado hay una franja muy grande que tapa la lista"; "tiene
  que escribir y seleccionar"): con el teclado abierto se esconden la barra de pestañas, su espacio y el título, y los resultados
  ocupan todo el lugar hasta el teclado (antes 4 filas flotando sobre el total). El primero va marcado y **Enter lo agrega** sin
  cerrar el teclado. La búsqueda espera 120 ms (antes 300) y los resultados aparecen sin animación. Probado con tests; **no probado
  en un celular real** (el alto real del teclado y el comportamiento de la tecla Enter dependen del teclado del celular).
- **Proveedores en el celular** (El dueño: "que no queden datos importantes sin poder llenar, por ej. un proveedor"): Más › Proveedores
  junta lo que estaba en tres filas (Cuenta corriente, Pagar proveedor, Cargar factura) y suma **alta y edición** (nombre, WhatsApp, días
  de pedido y entrega, cómo se le paga, dar de baja) y **"Pedir por WhatsApp"**. El código se arma solo. Detalle en `DECISIONES.md`.
  Probado con tests; **no probado en un celular real**.
- **Abrir caja desde el celular pide el saldo de Mercado Pago** (El dueño: "al abrir caja no me da el monto de Mercado
  Pago"): igual que la PC, viene precargado con lo último contado en el cierre anterior y se puede corregir (hoja "Abrir
  caja" y la apertura dentro de "Gasto o ingreso"). Antes se arrastraba en silencio, sin verlo. Con la PC va por
  `/sesion` (`mpQueSeArrastraCentavos`) y `/sesion/abrir` (`mpInicialCentavos`, opcional): una PC sin actualizar ignora
  el monto y arrastra como antes, así que **conviene publicar la PC y el APK juntos**. Probado con tests; **no probado en
  un celular real**.

## Últimos cambios (07/10/2026)

- **Clave de la IA por cuenta** (El dueño: "la clave es por cuenta"): el dueño la carga una vez en Configuración › Asistente IA (PC o
  celular) y queda cifrada en el servidor (`/api/ia/*` del sitio, como el token de Mercado Pago). Todos los equipos del negocio,
  empleados incluidos, usan la IA por el sitio sin verla. Un equipo sin cuenta vinculada sigue con su clave propia, y una clave propia
  vieja sigue andando hasta que el dueño guarde la del negocio. Necesita el sitio con `/api/ia` publicado. Probado con tests (app y sitio);
  **no probado con una clave real ni en un celular real**.
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
- Ganancia real en vez de markup (migración v46) y asistente contable (primera parte): pasan `flutter analyze` y los tests
  (verificado el 2026-10-12); falta verlos con datos reales.
- **Validación real del dominio**: correr una semana en paralelo con el sistema anterior y comparar cierres. Los tests
  prueban que el código hace lo pedido, no que el modelo de negocio sea correcto.

## Pendiente

**Pedido por el dueño / a confirmar antes de arrancar** (lista completa y orden de interés en `CONTEXTO.md` §7):
integración con Mercado Pago: el QR en pantalla sin terminal ya está en el celular y la web (13/10; en la PC no) (antes: ya estaba en Nodo Sur Servicios,
10/10; en almacén el dueño dijo "de momento no", 2026-10-04) — el saldo real en el cierre del celular ya está (09/10); pagar a un proveedor con MP desde el celular; "etapa 3" de MP (esconder token/terminal locales como avanzado); motivo
obligatorio en cada gasto.

**Pendientes técnicos conocidos:**

- (Resuelto el 2026-10-14: Google Cloud no dejaba crear el cliente Android del almacén porque Firebase ya tenía la pareja
  paquete + SHA-1. Ver `TRAMPAS.md` y `docs/PENDIENTE-GOOGLE-ANDROID.md`.)

- (Resuelto el 2026-10-13: el stock contado dos veces en un equipo que bajaba todo de cero. Ver `DECISIONES.md`, "Base de stock".)

- **Publicación** (revisión 2026-10-12, sin tocar, a decidir): (1) un merge `release:`/`beta:` publica aunque los tests de
  ese mismo merge fallen (`publicar-beta.yml` y `publicar-apk.yml` no esperan a `tests.yml`); (2) el APK de Nodo Sur Servicios
  lleva el bot de `botdemo` tal como esté en su `main` en ese momento, y `botdemo` no tiene CI; (3) los APK se firman con el
  `debug.keystore` de una PC: si se pierde, no hay forma de actualizar los celulares sin desinstalar; (4) el commit que deja
  el número de una estable dice "Publicada la beta".
- La copia local a la carpeta de respaldo (Drive/OneDrive) lleva el token de Mercado Pago y la llave del celular tal cual; la
  copia en la nube los saca (`copias_nube.dart`).

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

- Cobrar con tarjeta por NFC en el celular (Point Tap) desde la app: Mercado Pago no lo deja pedir desde otra app (probado el
  14/10). Se cobra con QR o con la terminal Point.
- Descuento de Cliente Frecuente (Regla 17): no se hace. Las columnas `clientes.descuentoBp` y `ventas.descuentoCentavos`
  quedan sin usar a propósito (borrarlas es una migración sobre datos reales para no ganar nada).
- Reportes y Equilibrio como pantallas aparte (hoy Equilibrio es la mitad "del mes" de Inicio), retiro semanal de ganancias.

# App del celular vs. mock "Nodo Sur · App del celular" (2026-10-04)

> **Ojo:** las secciones 1 a 4 describen la app **antes** del rediseño (04/10) y se dejan como historia de la comparación. Lo que se hizo y lo que quedó distinto está en las secciones 6, 6b y 6c.

Fuente del mock: paquete `nodo-sur-mock-celular` (docs 00–08, 46 capturas, 46 tablas de medidas, `Movil.dc.html`).
Objetivo del dueño: que la app sea **tal cual el mock**, adaptando solo lo que el mock no tiene.

Método: se corrió `test/companion/capturas_companion_test.dart` (390×844 @2x) y se puso cada captura de la app al lado
de la del mock. Los cuadrados que se ven en lugar de iconos en esas capturas son del test (no carga la fuente de
iconos); no son un error de la app.

## 1. Diferencias de fondo (afectan a todas las pantallas)

| Tema | Mock | App hoy |
|---|---|---|
| Barra inferior | Píldora **blanca** flotante, 5 pestañas con icono + rótulo: Inicio · Productos · **Vender** (centro, azul `#2f5be8`, 52 px) · **Caja** · Más. Punto naranja en Más si hay actualización | Píldora **negra**, 4 pestañas de solo texto: Inicio · Productos · Historial · Gestión. Vender es una tarjeta dentro de Inicio |
| Color de marca | Un solo azul `#2f5be8`; tinta/papel/grises + 4 tonos de estado (verde, rojo, ámbar, azul claro). **Sin degradés, sin violeta** | Tinta como acento, degradés oscuros con partículas, violeta y verde-agua en los atajos |
| Tokens | `--ink --paper --s --s2 --mute --line --prim --hero --toast` + 4 pares fondo/texto; tema claro, oscuro (el primario pasa a azul) y automático | `ColoresPlazoleta` con otros valores (`borde`, `fondoBloque`…); oscuro con acento blanco |
| Iconos | Trazo único 24×24, grosor 2, sin relleno, propios (31 paths) | Material Icons |
| Tipografía | Figtree, títulos y cifras grandes en peso 450 con tracking negativo, números tabulares | Figtree 400–700 estática (sin 450: se usa 500, desviación permitida por el doc 07) |
| Animación | `.scr` 0,55 s, `.rv` 0,6 s, hoja 0,5 s, toast 0,45 s, tilde que se dibuja; se apagan con "reducir movimiento" | (Antes) transición propia distinta; partículas. **Hoy:** igual al mock salvo la entrada de pantalla, que es un fundido cruzado por decisión del dueño (ver 6c) |
| Cartel sin conexión | Tira de 34 px arriba en todas las pantallas (menos Emparejar y ¿Quién sos?) que corre todo 34 px | Franja "modo local" dentro de Inicio |
| Hojas | Hoja inferior radio 40, asa, título 28, botones apilados; el velo cierra (decisión del doc 07) salvo terminal y "salir sin guardar" | `hoja_vidrio` y diálogos de Material |
| Avisos | Toast oscuro flotante abajo (2,6 s) | `SnackBar` |

## 2. Estructura de navegación

| Mock | App hoy | Qué se hace |
|---|---|---|
| Inicio | Inicio | Se rehace: conexión + campana, "Hola, X", **Nueva venta** azul, carrusel "Tu día" (3 tarjetas), 3 atajos, buscador de funciones |
| Productos | Productos (`pantalla_precios`) | Se rehace: "Controlar stock", buscador, filtros combinables, lista agrupada, "Elegir varios", barra de lote |
| **Vender** (pestaña) | Carrito (se abre desde Inicio) | Pasa a pestaña central. Carrito → Cobrar → Venta cobrada, con los servicios reales |
| **Caja** (Resumen · Separar · Ventas) | Gestión + Historial + Separaciones + Arqueo + Cierres | Pestaña nueva. Resumen = esperado + cierre + arqueo; Separar = separaciones; Ventas = historial del día |
| Más | Gestión (parte) + Cuenta | Usuario, apariencia, Configuración, Cargar días anteriores, Conexión, Actualización, Desconectar |

## 3. Lo que la app tiene y el mock no (se conserva, con el estilo del mock)

Se ubican dentro del mock sin inventar pantallas nuevas de otro estilo:

- **Encargues (apartados)**, **Pagar a un proveedor**, **Cuenta de Nodo Sur** (Google, negocio, vínculo), **Modo de uso** (PC / nube /
  solo celular), **Bienvenida** y **Configurá tu negocio** → filas dentro de *Más*, en la sección NEGOCIO o ESTA APLICACIÓN.
- **Historial con período** (hoy / ayer / 7 días / mes) → la solapa *Ventas* de Caja muestra el día; "Ver cierres anteriores" y
  *Días anteriores* cubren el resto. Los filtros extra siguen disponibles dentro de la misma pantalla.
- **Devolución por Mercado Pago al anular**, **cobro por Point de verdad**, **impresión de ticket**: se mantienen detrás de los
  mismos botones del mock (Eliminar esta venta, Terminal, Imprimir ticket).
- **Carga histórica producto por producto**: el mock también la pide así (decisión del dueño ya tomada en `ESTADO.md`).

## 4. Lo que el mock tiene y la app no (hay que construirlo)

- Cartel global "Sin conexión con la PC · usás los datos del celular".
- Pestaña Caja con Resumen/Separar/Ventas, "Contar la caja" como hoja y Cerrar caja en 3 pasos + resultado.
- Notificaciones con pendientes calculados (separar, sin stock, versión nueva) y sección "Antes".
- Buscador de funciones (30 funciones, algoritmo del doc 06).
- "Controlar stock" desde Productos con códigos de proveedor y tilde "está igual".
- Hoja "Editar en lote" con paso de revisión y advertencia de >50 %.
- Descuento fijo del 10 % en el carrito y atajos de pago mixto (Mitad / $ 10.000 / $ 20.000).
- Pantalla Emparejar con visor y línea de escaneo, y ¿Quién sos?.

## 5. Decisiones de negocio que el mock deja abiertas (doc 07, §4)

1. El velo de las hojas cierra al tocar fuera (equivale a Cancelar), salvo en "Cobrando en la terminal" y "¿Salir sin guardar?".
2. Redondeo, recargo de cigarrillos, producto de vuelto y formas de cobro **sí** se aplican al cobro (la app ya lo hace).
3. Todas las cifras salen de datos reales; las del mock son de ejemplo.
4. Versión: se muestra la real (`package_info`), no 1.0.0/1.0.1.

## 6. Estado (2026-10-04)

Hecho: todo lo de las fases 1 a 5 de abajo, salvo lo listado como pendiente en `ESTADO.md` ("En curso — celular calcado del
mock"). Se compararon capturas de la app contra las del mock con `test/companion/capturas_mock_test.dart` (PNG en
`capturas/companion-mock/`); la diferencia de píxeles va del 2 % al 14 % (tipografía y 1–3 px de interlineado). No se
probó en un celular real.

## 6b. Segunda vuelta del mock (2026-10-05)

El dueño mandó un mock actualizado (175 capturas) que cubre casi todo lo que faltaba. Se hizo en 4 lotes:

1. **Vender y Cobrar**: medios en lista (con Crédito), efectivo con "Justo" y billetes, "Cobrar a mano", descuento libre
   (monto o porcentaje), cantidad exacta con un toque, deshacer al quitar, entregar un encargue, y la hoja de la terminal
   con todos sus estados.
2. **Caja**: cierre en dos etapas (contar a ciegas → revisar), contar la caja con aviso de 2 horas, gasto/ingreso con lata,
   estados con la caja cerrada, cierres anteriores con detalle.
3. **Productos y datos**: filtros y ganancia en Productos, edición en lote por contexto, formulario con ganancia, escáner,
   Caja › Ventas por período con anular, Separar con lo vendido, tablero en Inicio, días históricos con detalle.
4. **Arranque y gestión**: modo de uso, emparejar con código, entrar con Google, asistente de 3 pasos, Inicio con
   estados de conexión y tarjeta de pasos pendientes, Encargues, Pagar proveedor, Cuenta y sincronización, Actualización
   en 3 pasos (descargar → verificar → instalar) y Más.

Desvíos a propósito: ver la lista en `ESTADO.md` ("Celular calcado del mock"). La pantalla "Probar estados" del mock no se
implementa (es del simulador).

## 6c. Después del lanzamiento (2026-10-05)

| APK | Qué cambió |
|---|---|
| 2133 | El rediseño completo (4 lotes). |
| 2134 | Arreglo: Productos y Caja › Ventas se quedaban cargando; Notificaciones, Buscador, Consultar precio, Cierre y Gasto se rompían al abrir. |
| 2135 | Animaciones: fundido cruzado al abrir pantallas y al cambiar de pestaña. |

- **Qué falló en el 2133:** el menú resuelve el servicio después de abrirse y no avisaba a las pestañas, y las pantallas abiertas con `Navigator.push` no encontraban `AppNs` (cuelga del menú, no del navegador). Los tests no lo mostraron porque usaban un controlador falso con el servicio ya armado y montaban cada pantalla suelta.
- **Arreglo:** `setState` del menú suma versión; `AppNs` se publica arriba del navegador (`puenteAppNs` + `PuenteAppNs`); Productos y Ventas cargan apenas aparece el servicio. Test con el menú real: `test/companion/menu_real_test.dart`.
- **Animación (decisión del dueño, 05/10):** de las opciones que se le dieron (fade + subida del mock, fundido cruzado, deslizamiento en eje, tarjeta que se agranda, sin animación) eligió el **fundido cruzado**. Se aplica a la ruta (`tema_companion.dart`, `FadeThroughTransition`) y al cambio de pestaña (`CambioDePestanaNs`). `PantallaEntradaNs` quedó sin animación: antes se sumaba una segunda entrada encima de la de la ruta. Respeta "reducir movimiento".
- **Probado en un celular real por el dueño:** anda todo.

## 7. Plan por fases

1. Tokens + iconos + componentes base + barra de 5 pestañas + cartel offline + toast + hoja.
2. Emparejar, ¿Quién sos?, Inicio, Notificaciones, Buscador de funciones.
3. Vender, Cobrar, Venta cobrada, Consultar precio.
4. Caja (Resumen, Separar, Ventas), Cerrar caja, Contar la caja, Gasto o ingreso.
5. Productos, Controlar stock, Editar en lote, formulario de producto, Más, Configuración, Días anteriores.

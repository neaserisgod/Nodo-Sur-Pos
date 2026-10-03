# Plan: cómo va a quedar el proyecto (2026-10-03)

Resultado de la revisión de `docs/REVISION-FRICCIONES.md` y de las respuestas del dueño. **Nada de esto está hecho todavía.**
Cada fase es uno o más PR chicos, con `flutter analyze` y `flutter test` en verde, y no se publica nada hasta que el dueño
diga "lanzá". Lo que cambia una regla de negocio se pregunta antes (`CLAUDE.md`).

## Decisiones del dueño que ordenan el plan

1. **Fiado y encargue son lo mismo → se unifica en "Encargues".** Una sola tarjeta en el Inicio, una sola pantalla en la PC y
   una en el celular, un solo nombre. El fiado deja de existir como módulo aparte.
2. Botones de gasto/ingreso/Varios/vuelto en Venta: **no por ahora** (se deja como está, por teclado).
3. **Roles: sí hacen falta**, pero piden rehacer el sistema de usuarios (hoy un usuario es solo un nombre, Regla 18).
4. **Paridad PC/celular: sí** (deuda con proveedores en los dos, Consultar precio en la PC).

## Cómo queda cada pieza

**PC — menú:** Inicio · Venta · Proveedores · Separaciones · Historial · Encargues (+ engranaje de Configuración y lupa).
Sin cambios de estructura; lo que cambia es lo de adentro:
- *Inicio:* tarjeta "Encargues" (apartados y lo que te deben) con filas tocables que abren Encargues; "Stock bajo" con filas
  tocables que abren el producto; nueva tarjeta "Deuda con proveedores".
- *Venta:* igual que hoy. Texto en "Cambiar de turno" y "Cerrar caja" cuando hay ancho. Atajos de cobro mixto (Mitad, $10.000,
  $20.000).
- *Proveedores:* "Conteo de stock" como botón visible; Comparar precios, Importar CSV y Promos siguen en el menú ⋮.
- *Historial:* "Cargar día histórico" baja a un menú (uso raro).
- *Encargues:* absorbe lo que hoy sería fiado (ver abajo).

**Celular — pestañas:** Inicio · Productos · Historial · Gestión.
- *Inicio:* Vender, Consultar precio, Movimiento de caja, Pagar proveedor. **"Hacer arqueo" sale de acá** (queda en Gestión).
- *Historial:* dos pestañas, **Ventas y Cierres** (hoy Cierres está escondido en Gestión).
- *Gestión*, en este orden: Cerrar caja · Arqueo · Separaciones · Conteo de stock · Encargues · Carga histórica · Cuenta ·
  Configuración. Deuda con proveedores se suma a Pagar proveedor.
- *Carrito:* quitar línea más fácil de tocar.

**Sitio y servidor:** sin cambios hasta la fase de roles (ahí se suma el rol por usuario y su sincronización) y la de Mercado Pago.

## Fases

**Fase A — Fricciones sin decisión de negocio** (1–2 PR, sin migración)
Conteo de stock visible, filas tocables en Inicio, texto en Cambiar de turno / Cerrar caja, Historial: "Cargar día histórico" a
un menú, celular: un solo arqueo y Gestión reordenada, Historial con Ventas + Cierres, atajos del cobro mixto.

**Fase B — Unificar fiado y encargue**
- Qué hay hoy: `crearFiado`/`cobrarFiado` existen pero ninguna pantalla los usa; Encargues ya tiene apartar, cancelar y entregar.
- Qué se hace: la tarjeta del Inicio pasa a "Encargues"; se saca el módulo "Fiado" de Configuración → Módulos y su texto; el
  Cierre y el PDF dejan de hablar de fiado donde hoy lo nombran. **No se borran columnas ni filas** (si el local tuviera algún
  fiado viejo cargado, sigue ahí y se muestra como encargue).
- ❓ Antes de empezar: ¿hay algún fiado cargado en la base real? Se mira con una consulta, sin tocar nada.
- ❓ ¿"Encargue" cubre también "se lo llevó y paga después" (sin apartar stock)? Hoy un encargue baja el stock al apartar y
  entregar abre la venta. Para "me lo llevo y pago después" haría falta entregar sin cobrar. Proponer: un botón "Entregar y
  anotar deuda" que deja el encargue como deuda del cliente. Decisión tuya.

**Fase C — Avisos en un solo lugar**
La campanita de Venta junta: arqueo vencido, falta separar, stock bajo, caja de ayer sin cerrar, encargues por entregar; cada
aviso lleva a su pantalla. En el celular, lo mismo en Inicio.

**Fase D — Paridad PC/celular**
Deuda con proveedores en el Inicio de los dos y apartado "Deuda" en el celular (hoy solo PC); "Consultar precio" en la PC
(extender la lupa Ctrl+F para mostrar precio/stock sin navegar). Promos y precio automático por proveedor quedan solo en PC
salvo que lo pidas.

**Fase E — Roles y usuarios (rework, con diseño antes)**
Es el cambio más grande y toca modelo, UI y sitio. Por eso arranca con un documento corto de diseño para aprobar:
- *Hoy:* `usuarios` = nombre + activo; sin PIN; los roles (dueño/encargado/empleado) viven en el sitio y viajan con la cuenta
  (`GET /api/device/me`), pero el POS no los usa.
- *Propuesta:* `domain/permisos.dart` con una lista de capacidades (ver costos y ganancia, anular/editar ventas, ver y cerrar
  cierres, retirar ganancia, configuración, pagar proveedores, importar/editar precios) y qué rol tiene cada una; una sola
  función `puede(rol, capacidad)` que usan las pantallas (Regla 3: un solo lugar). Dos fuentes del rol: la cuenta de Nodo Sur
  cuando el equipo está vinculado, y un PIN por usuario cuando se usa solo local (migración v48: `rol`, `pin_hash`).
- ❓ Hay que definir con vos qué puede y qué no puede un empleado y un encargado. Es la parte de negocio.
- Se hace en orden: diseño aprobado → dominio y tests → modelo/migración → ocultar o bloquear en cada pantalla → sitio.

**Fase F — Mercado Pago real** (el dueño la quiere mucho)
Primero probar la conciliación contra la cuenta real en un cierre (hoy sin probar); después webhooks (venta confirmada y cobros
sin venta), devoluciones al anular, saldo real en el cierre y QR en pantalla. Detalle en `CONTEXTO.md` §7.

**Fase G — Pedido a proveedores por WhatsApp** (si lo confirmás)
Desde "Stock bajo" armar el pedido y mandarlo; usa el contacto y día de visita del proveedor.

**Limpieza (en cualquier momento, sin riesgo):** `.gitignore` de `android/build`, restos de Firestore, `Bloque` y tokens
deprecados, aprovechar el flujo de la suite para ver los fallos intermitentes de `test/ui/venta/`.

## Orden recomendado

A → B → C → D → E → F (G cuando lo decidas). A y B no tienen riesgo y dan el cambio visible rápido; E y F son los grandes y
conviene hacerlos con la app ya ordenada. Antes de F, el dueño prueba en el local un día de cierre con la conciliación.

## Qué sigue sin verificarse

Todo esto se plantea leyendo código y capturas: falta usar cada flujo en la PC y en un celular reales (Windows con escala 125 %
y 150 %, escáner, cajón, terminal Point).

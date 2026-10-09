# Pendientes y preguntas abiertas (sesión del 2026-10-09)

Para retomar en una sesión nueva. Lo hecho y publicado ese día está en `ESTADO.md` ("Últimos cambios (09/10/2026)") y en
`DECISIONES.md`. Acá queda **lo que falta decidir o hacer**.

## Publicado el 2026-10-09

- Hotfix (#92): abrir caja desde el celular pide el saldo de Mercado Pago. Windows 1.0.0.2151 y APK 2153, estable.
- Release (#93): Proveedores en un solo lugar en el celular (alta, edición, WhatsApp), vender con el teclado sin la
  franja que tapaba (Enter agrega el primero), sin pantalla de "Venta cobrada". Windows 1.0.0.2153 estable (salió dos
  veces, como 2152 y 2153, por dos eventos de push del mismo merge: mismo código, no se pisó nada). APK **2154**
  relanzado a las 15:40 UTC: **verificar en `/admin/` → Versiones que haya quedado publicado**. El primer intento se
  canceló solo por la fila de publicación (`concurrency: publicar` cancela el pendiente cuando entra otro).

## 1. Cierre de caja: separar los cigarrillos ANTES de contar (esperando al dueño)

**Pedido del dueño:** *"tengo que hacer las cuentas 2 veces, porque tengo que contar el efectivo, y recién ahí separar,
en lugar de que separe lo de los cigarrillos antes de contar"*.

**Hoy** (PC y celular): (1) se cuenta el cajón con los cigarrillos adentro, Mercado Pago y la lata; (2) recién
después la app dice "separá $X a la lata"; (3) se mueve $X y la lata se vuelve a contar.

**Problema extra en la PC:** la lata se pide en el paso 1 (antes de separar), pero se compara contra la lata con lo de
hoy ya separado (`lataNuevaCentavos` incluye `separadoHoy`, `repositorio_cierre.dart` ~línea 637). Si se cuenta en
ese momento da un **faltante falso igual a lo que hay que separar**. En el celular la lata se pide en la etapa 2,
así que no pasa, pero el ida y vuelta es el mismo.

**Por qué estaba así:** Regla 10 (`REGLAS-NEGOCIO.md` §10): "la diferencia y la separación de cigarrillos permanecen
ocultas hasta confirmar el conteo", y `DECISIONES.md` ("La separación de cigarrillos es posterior al arqueo"). Pero el
monto a separar (precio de lista de lo vendido hoy + pendiente de cierres anteriores) **no revela lo esperado del
cajón**: mostrarlo antes no rompe el contar a ciegas.

**Flujo propuesto (recomendado):**
1. **Separar primero:** "Separá $X a la lata" → se separa → "Listo". Si en el cajón no alcanza (mucho QR), se escribe
   cuánto se separó y el resto queda pendiente para el próximo cierre (como hoy hace `separarCigarrillos`).
2. **Contar a ciegas:** cajón ya sin cigarrillos, lata ya con lo separado, Mercado Pago.
3. **Comparar:** cajón esperado = esperado de siempre − separado; lata esperada = inicial + separado − pagos +
   ingresos (igual que hoy). Separar de más o de menos aparece como diferencia igual y opuesta en cajón y lata, así se
   distingue de un faltante real.

Las cuentas de fondo no cambian, solo el orden. Hay que cambiar la Regla 10 y la entrada de `DECISIONES.md`, y hacerlo
en la PC (`lib/ui/cierre/`) y en el celular (`lib/companion/pantallas/pantalla_cierre_ns.dart`), con tests en
`domain/caja.dart` y `repositorio_cierre.dart`. Revisar también el arqueo intermedio (`arqueos_del_turno`).

**Preguntas para el dueño (sin responder):**
1. ¿Le sirve ver el monto a separar **antes** de contar?
2. Si en el cajón no alcanza para separar todo, ¿escribe a mano cuánto separó y el resto queda pendiente para el
   próximo cierre?

## 2. Celular: lo que sigue del plan "simple pero sin datos faltantes"

Orden acordado: Proveedores (hecho) → Inicio → Más y Configuración. Falta:

- **Inicio** muy cargado: "Nueva venta" repite la pestaña Vender; "Tu día" es un carrusel lateral y abajo el tablero
  repite la ganancia; 3 atajos + buscador de funciones + 4 tarjetas más. Proponer una versión corta.
- **Más** y **Configuración**: ordenar; sumar lo que hoy solo está en la PC:
  - **Categorías nuevas** (el celular no puede crearlas).
  - **Gastos fijos** (monto y día de vencimiento).
  - Fondo fijo de caja, reserva diaria de fijos, día del retiro semanal, desde cuánto faltante pregunta el cierre.
- **Formulario de producto:** "+ Nuevo" al lado de Proveedor y de Categoría. Con la PC conectada la lista de
  proveedores viene de la PC (otros ids que la base del celular): un proveedor recién creado en el celular aparece ahí
  cuando la sync lo lleva. Resolverlo antes de agregar el botón.
- **Cobrar, opción B** (no elegida todavía): poner Efectivo/QR/Tarjeta en el carrito en vez de "Cobrar" y saltear la
  pantalla Cobrar. El dueño eligió solo la A (sin "Venta cobrada").
- **Búsqueda con la PC conectada:** sigue yendo por wifi a la PC en cada búsqueda (120 ms de espera + la red). Buscar
  en la base local sería instantáneo, pero los ids de producto del celular no son los de la PC: haría falta mapear por
  `global_id` antes de cobrar. No hecho.

## 3. Detalles técnicos encontrados

- Las capturas 14 (`test/companion/capturas_mock_test.dart`, `_PuertoPosnet.cobrarEfectivo`) muestran el total sin
  redondeo porque el servicio de mentira devuelve el subtotal. La app real redondea bien. Corregir el falso si molesta.
- Un fallo de CI en el PR #93 (2688 pasaron, 1 falló) no se pudo ver: el registro llegó cortado y en el commit
  siguiente pasó todo. Si vuelve a aparecer, buscar el test inestable.
- Nada de esto se probó en un celular real: teclado (alto y tecla Enter), proveedores, tarjeta de la última venta.

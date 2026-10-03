# Revisión pantalla por pantalla — fricciones y qué falta (2026-10-03)

Hecha mirando capturas reales de cada pantalla (`test/ui/capturas_escritorio_test.dart` y
`test/companion/capturas_companion_test.dart`, 24 + 50 tests verdes con Flutter 3.47.5), el código de la navegación y los
mocks (`Lenguaje de diseño/`, `docs/anotaciones-mocks.md`). **No se usó la app corriendo en Windows ni en un celular**: lo
que dice "se siente" es lectura del código y de las capturas, no uso real. En las capturas los íconos salen como cuadrados
vacíos: es la fuente del entorno de test, no un bug de la app.

Todavía **no se cambió nada de código**. Esto es el plan; lo que necesita decisión del dueño está marcado con ❓.

## 1. Lo más grave: funciones que existen pero no se pueden usar

| # | Qué pasa | Dónde se ve | Propuesta |
|---|---|---|---|
| 1 | **Fiado no tiene pantalla.** `crearFiado`/`cobrarFiado` (`lib/data/repositorio_pendientes.dart`) solo se llaman desde tests. El Inicio tiene la tarjeta "Fiados y encargues" y hay un módulo "Fiado" para prenderlo, pero no hay forma de anotar un fiado ni de cobrarlo. La tarjeta nunca va a mostrar fiados. | PC (Inicio, Configuración → Módulos) | ❓ ¿El dueño usa fiado? Si sí: pantalla/diálogo para anotar (desde Venta: "Fiar") y cobrar (desde Inicio). Si no: sacar la tarjeta y el módulo. |
| 2 | **Gasto, ingreso, Varios, vuelto y arqueo en Venta no tienen botón.** Solo existen por tecla (`-`, Alt+I, Alt+V, Alt+C) o por el aviso de las 2 hs. El mock `Ventas.dc.html` tenía "Movimiento / Arqueo / Varios" arriba. Quien no sabe la tecla no los encuentra. | PC (Venta) | Un menú "Más" chico junto a la búsqueda con esos cuatro, con la tecla impresa al lado. No toca el cobro ni el carrito. |
| 3 | **Las tarjetas del Inicio son de lectura.** "Stock bajo" y "Fiados y encargues" listan filas que no se pueden tocar; solo "Falta separar" y "Ir a Venta" llevan a algún lado. | PC (Inicio) | Tocar una fila de Stock bajo abre ese producto (editar/pedir); "Encargues" abre Encargues. |
| 4 | **"Conteo de stock", "Comparar precios", "Importar CSV" y "Promos" están escondidos** en el menú de tres puntitos de Proveedores. Conteo de stock es una tarea diaria en el celular y en la PC está tres niveles adentro. | PC (Proveedores) | Sacar "Conteo de stock" a un botón visible junto a "+ Nuevo proveedor". |

## 2. Fricciones de uso (ordenadas por cuánto cuestan en el mostrador)

**PC**
1. Venta: el foco vuelve al buscador al agregar y cobrar (bien), pero cobrar con QR/Débito son dos pasos (elegir canal, después
   "Cobrar") por decisión del dueño (2026-09-08). Dejarlo. Con teclado ya es Alt+Q → Enter.
2. Venta: "Cambiar de turno" y "Cerrar caja" son solo íconos con tooltip. Un cajero nuevo no sabe cuál es cuál. Ponerles texto
   corto cuando haya ancho (la navbar de Venta es la única con lugar de sobra).
3. Navbar de gestión: Encargues está como sección propia en la PC, pero en el celular vive dentro de Gestión; el Inicio de
   la PC lo nombra en "Fiados y encargues". Mismo concepto en tres lugares con tres nombres → unificar nombre y lugar.
4. Historial: "Cargar día histórico" está a la par de las pestañas como si fuera una vista más. Es una herramienta de uso
   raro; bajarla a un menú.
5. Configuración: cuatro de las diez secciones útiles (impresión, copias, celular, cuenta) están en "Equipos y cuenta". Está
   bien agrupado; falta un acceso directo desde donde se necesita (ej. "Imprimir" en Venta cuando no hay impresora → ir a
   Configuración). ❓ no pedido, solo anotado.
6. Cierre: sin botón "volver" visible en el paso 1 salvo la cruz. Es a propósito (flujo bloqueante, Regla 10); dejarlo.

**Celular**
1. "Hacer arqueo" aparece dos veces (Inicio y Gestión → "Arqueo") y al lado hay "Cerrar caja" con otro texto según el estado
   de la caja. Dejar un solo lugar para arqueo y que Cerrar caja sea el botón grande de Gestión (ya lo es).
2. Gestión tiene 9 tarjetas en 2 columnas y hay que scrollear para llegar a "Cuenta" y "Configuración". Ordenar por uso:
   Cerrar caja → Arqueo → Separaciones → Conteo de stock → Encargues → Cierres → Carga histórica → Cuenta → Configuración, y
   mover lo de uso raro (Carga histórica) al final.
3. "Cierres anteriores" vive en Gestión y "Historial" es otra pestaña: el dueño pregunta dos veces "dónde veo los días".
   Los mocks (`HistorialCierres.dc.html`) los ponen juntos. Unificar: Historial con dos pestañas, Ventas y Cierres (como ya
   hace la PC).
4. Carrito: "Quitar" en texto gris chico, lejos del pulgar. Probar un deslizar para quitar o un ícono de tacho más grande.
5. Productos: ya tiene filtros útiles (Sin costo, Sin proveedor, Sin código). Falta mostrar el contador de cada uno para
   saber cuál vale la pena abrir.

## 3. Cosas que no son de una pantalla sino de integración

1. **Mismas cosas, distinto alcance PC/celular.** La PC tiene Equilibrio (mitad "Este mes" del Inicio), deuda con proveedores,
   promos y precio automático por proveedor; el celular no (ver "Pendientes técnicos" en `ESTADO.md`). El celular, en cambio,
   tiene Consultar precio y Conteo por escáner que la PC no tiene como pantalla. ❓ ¿Qué de esto tiene que estar en los dos?
   Mi propuesta mínima: deuda total con proveedores en el Inicio de los dos, y "Consultar precio" también en PC (Ctrl+F ya
   casi lo hace).
2. **Un solo lugar para "qué tengo que hacer hoy".** Hoy el aviso de arqueo es una campanita en Venta, "Falta separar" es una
   tarjeta del Inicio, el stock bajo es otra y los pendientes otra. Propuesta: que la campanita (ya existe) junte los avisos
   de todo — arqueo vencido, falta separar, stock bajo, caja de ayer sin cerrar — y que su panel lleve directo a cada pantalla.
3. **Mercado Pago real en el cierre** está hecho pero sin probar contra la cuenta real (ver `ESTADO.md`). Es la fricción más
   cara si falla: conviene probarlo un día antes de agregar más cosas encima.

## 4. Mocks: qué falta, qué conviene y qué no

Fuente: `docs/anotaciones-mocks.md` + `PEDIDO-MOCKS-2.md` + los `.dc.html`.

| Mock | Estado en la app | Recomendación |
|---|---|---|
| Dashboard: "Pedir a proveedores" · Proveedores: "Hacer pedido" | No existe | **Sí, vale la pena** (el dueño pidió reposición desde la fase 6): armar el pedido con lo de "Stock bajo" y mandarlo por WhatsApp al proveedor (el mock ya trae contacto y día de visita). ❓ confirmar |
| Dashboard: "Efectivo en caja" con "Retirar o ingresar dinero" | Existe el movimiento rápido, no la tarjeta | **Sí**, es el punto 2 de arriba (acceso visible) |
| Cobro mixto: atajos "Mitad / $10.000 / $20.000" | No existe | **Sí**, bajo costo y reduce tipeo en el mostrador |
| Ventas: cobro en dos pasos (ticket y después medio) | La app tiene los 4 medios siempre visibles | **No.** La app es más rápida; se mantuvo a propósito |
| Cierre de caja en un solo paso | La app cuenta a ciegas y después muestra lo esperado | **No.** Es la Regla 10 del negocio |
| Config: código de 6 dígitos para vincular el celular | Vincula con QR, con IP/puerto/token o ahora con un toque en el wifi | **No hace falta**; el QR ya resolvió eso |
| Config: copia en la nube cifrada | Ya existe (cuenta de Nodo Sur) | Hecho, mejor que el mock |
| Config: roles Administrador/Cajero | Solo hay usuarios; los miembros del sitio heredan permisos | ❓ ¿Hace falta que el cajero no vea costos ni cierres? Es decisión de negocio |
| Celular: tarjeta "Actualización" manual | La app avisa sola | **No** |
| Celular: "Cobro mixto" con atajos | No | Igual que arriba |
| Mocks de celular de carrito, historial, gestión, arqueo, conteo, login | Aplicados a mano según `DECISIONES.md` | Revisar contra el mock cuando el dueño pruebe en un celular real |

## 5. Orden propuesto para hacerlo

Pensado para que cada tanda sea un PR chico, con la suite verde, y sin tocar reglas de negocio:

1. **Tanda 1 (sin decisiones):** menú "Más" en Venta (gasto, ingreso, Varios, vuelto, arqueo), "Conteo de stock" visible en
   Proveedores, filas tocables en Stock bajo, un solo "Hacer arqueo" en el celular, orden nuevo de Gestión, texto en
   "Cambiar de turno" / "Cerrar caja".
2. **Tanda 2 (necesita ❓):** fiado (hacerlo o sacarlo), campanita única de avisos, unificar Historial y Cierres en el
   celular, atajos del cobro mixto.
3. **Tanda 3 (negocio):** pedido a proveedores por WhatsApp, deuda de proveedores en el celular y el Inicio, roles.

## 6. Qué no pude verificar

- Cómo se siente cada flujo con el mouse, el escáner y el cajón en la PC real.
- Si algún texto se corta con la letra a 125 % o 150 % de Windows.
- El celular real: ni la bienvenida ni "Entrar con Google" ni pagar proveedor contra la PC.
- Que el fiado no tenga otra entrada que no encontré: busqué `crearFiado`/`cobrarFiado` en `lib/` y `test/` y solo aparecen
  en el repositorio y en sus tests.

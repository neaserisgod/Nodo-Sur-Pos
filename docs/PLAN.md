# Plan: cómo va a quedar el proyecto (2026-10-03, v2)

Segunda versión, después de **leer el código** (ver "Qué leí" al final) y de pedir el dueño la estética de horsepos.com /
antigravity.google y el estándar de diseño y funcionamiento de Google (`docs/ESTANDARES-GOOGLE.md`). Reemplaza al plan anterior.
**Nada de esto está hecho todavía.** Cada fase son PR chicos con `flutter analyze` y `flutter test` en verde; no se publica nada
hasta que el dueño diga "lanzá"; lo que cambia una regla de negocio se pregunta antes (`CLAUDE.md`).

## Decisiones del dueño que ordenan el plan

1. Fiado y encargue son lo mismo → **una sola cosa: "Encargues"**.
2. Gasto/ingreso/Varios/vuelto en Venta: no por ahora.
3. **Roles: sí**, y exigen rehacer el sistema de usuarios.
4. **Paridad PC/celular: sí** (deuda con proveedores en ambos, Consultar precio en la PC). Sin cobro mixto en el celular (decisión
   2026-09-07, no se toca).
5. Mercado Pago: lo útil ya anda; solo falta lo nuevo (webhooks, devoluciones desde el POS, saldo real, QR en pantalla).
6. **Estética horsepos/antigravity y estándar Google en toda la app.**

## Fase 0 — Correcciones antes de tocar nada (riesgo real, sin decisión de negocio)

Se hacen primero porque pueden dañar plata o datos. Cada una con su test que falla antes.

| # | Qué | Dónde | Por qué importa |
|---|---|---|---|
| 0.1 | **Cobrar contra una caja ya cerrada** no se verifica | `servidor_companion` (`/ventas/cobrar`, `/ventas/posnet/confirmar`), `VentaControlador.cobrar` | una venta entra en un cierre ya hecho y lo desarma. Verificar en `registrarVenta`, un solo lugar |
| 0.2 | `/ventas/cobrar` sin clave de idempotencia | servidor + cliente celular | reintento por mala señal duplica la venta |
| 0.3 | **Tokens de terceros hardcodeados** en el repo | `servicios/comparador_precios_todoatucasa.dart` | secreto filtrado: sacarlo, rotarlo y moverlo a configuración |
| 0.4 | SQL armado con nombres de columna que vienen del JSON remoto | `repositorio_sincronizacion.aplicarCambios` | lista blanca de columnas por tabla |
| 0.5 | El cursor de sincronización avanza aunque `aplicarCambios` haya dejado filas sin aplicar (p. ej. configuración antes que productos → se pierde el producto de vuelto) | `companion/servicio_sincronizacion.dart` | ordenar por dependencias y no avanzar el cursor con pendientes |
| 0.6 | Cambios que **no se sincronizan** porque no actualizan `actualizadoEn`: activar/desactivar productos y en lote, promos, medios de pago, y en proveedores pagar/separar/retener/revisar ganancia/nivel 2 y avanzado | repositorios de productos, promos, reposición | el celular muestra datos viejos |
| 0.7 | Importar CSV: fila corta → `RangeError`; nombre duplicado → `StateError`; sin transacción deja la importación a medias | `data/importacion_csv.dart` | todo o nada + error por fila |
| 0.8 | Búsqueda "7 up", "2 cocas" se toma como gramos y no encuentra nada | `data/busqueda_productos.dart` | solo tratar como gramos si el producto es pesable |
| 0.9 | Registrar pago de un fijo sin caja abierta cierra el diálogo como si hubiera guardado | `equilibrio_controlador.registrarPago` | avisar y no cerrar |
| 0.10 | Ajustes de conteo de stock se aplican de a uno (corte parcial) | `stock_proveedor_controlador.aplicarAjustes` | una transacción |
| 0.11 | El número de venta es el id local (distinto en PC y celular) y el ticket no tiene número | varios | número de venta global y visible en ticket (decisión en Fase 3) |
| 0.12 | `vueltoEsCaramelo` con $100 fijo; valores heredados del local original (fondo $150.000, reserva $70.000, "Distribuidora de Cigarrillos", "Bariloche") | dominio, configuración, PDF, mails | pasar a configuración / vacío |
| 0.13 | Token del celular = administrador sobre HTTP sin cifrar en el wifi | `servidor_companion` | se resuelve en Fase 5 (roles); mientras, documentar el riesgo |
| 0.14 | Escalabilidad: reposición/proveedores/ganancia leen todas las líneas de todas las ventas; `listarDias` e `historialDeVentas` hacen una consulta por fila | `data/` | consultas acotadas por fecha + índices; Separaciones deja de recargar todo cada 15 s |
| 0.15 | Errores mudos: 37 `catch (_) {}` en la PC (16 en el celular) y sin log a archivo | todo | log a archivo + aviso al usuario donde el fallo cambie el resultado |

## Fase 1 — Un solo sistema de diseño (base de todo lo visual)

- Unificar `companion/tema/*` dentro de `ui/tema/` (ver `docs/ESTANDARES-GOOGLE.md` §1).
- Tokens: acento único, colores solo de estado, oscuro `#0E0F12`, borrar legados, cero `Color(0xFF…)` sueltos.
- Kit completo y usado en todos lados: `Modal`, `HojaInferior` (celular), `BotonPrimario/Secundario`, `Campo*`, `EstadoVacio/Error`,
  `Esqueleto*`, `Snackbar con deshacer`, `FilaDato`, píldoras. Se eliminan los `AlertDialog`/`ElevatedButton` crudos.
- `es_AR` y `flutter_localizations`; `Semantics`/`tooltip` en todo ícono; anillo de foco; objetivos de 48 dp.
- Test automático de contraste y de tamaño táctil sobre el kit.

## Fase 2 — Fricciones por pantalla (sobre el kit nuevo)

**PC — Venta:** `−`/`+`, tacho y cerrar pestaña a 48 dp; **deshacer** al quitar línea, cerrar pestaña y Esc (Esc ya no cancela la
venta de golpe: pide deshacer); cantidad editable con un toque en la cantidad (hoy es doble clic oculto); "Cambiar de turno" y
"Cerrar caja" con texto; pantalla de caja cerrada con el kit; atajos del mixto (Mitad, $10.000, $20.000); sin stock: mostrar el
producto atenuado en la búsqueda con "sin stock" en vez de "Sin coincidencias" (❓ regla `REGLAS-NEGOCIO.md` §8, se pregunta).
**PC — Inicio:** filas de "Stock bajo" y "Encargues" tocables; tarjeta "Deuda con proveedores"; esqueleto al cargar.
**PC — Cierre:** el paso de conteo gana "Cancelar"; MP y lata contados pasan a "0 si no usás"; protección de doble clic.
**PC — Proveedores:** "Conteo de stock" visible; "Avanzado" se parte en "Pedidos y pagos" y "Datos del proveedor";
Importar CSV con plantilla descargable y errores completos.
**PC — Configuración:** guardado uniforme con aviso; sin jerga ("fase 12"); "Desconectar celulares" con confirmación.
**PC — Historial/Impresión:** "Cargar día histórico" a un menú; imprimir ticket con el kit; número de venta global.
**Celular:** carrito persistente (como los borradores de la PC) y con deshacer; un solo "Hacer arqueo" (queda en Gestión);
Gestión reordenada (Cerrar caja · Arqueo · Separaciones · Conteo · Encargues · Carga histórica · Cuenta · Configuración);
Historial con **Ventas y Cierres**; "Anular" en vez de "Eliminar"; pestaña "Productos" (hoy "Precios"); un toque menos en el cobro
(confirmar desde la misma vista del medio de pago).

## Fase 3 — Unificar fiado y encargue (Encargues)

Una tarjeta en Inicio, una pantalla en PC y celular, un solo nombre. Se saca el módulo "Fiado" y sus textos (cierre, PDF,
`modulos.dart`). **No se borra ninguna columna ni fila.**
❓ ¿Hay fiados cargados en la base real? (consulta de solo lectura, antes de empezar).
❓ ¿"Entregar y anotar deuda" (se lo lleva y paga después) entra en Encargues? Hoy un encargue aparta stock y entregar abre la venta.

## Fase 4 — Avisos y paridad PC/celular

Campanita única (PC) y Inicio (celular) con: arqueo vencido, falta separar, stock bajo, caja de ayer sin cerrar, encargues por
entregar. Deuda con proveedores en ambos; Consultar precio en la PC (extender Ctrl+F).

## Fase 5 — Roles y usuarios (con documento de diseño primero)

- Hoy: `usuarios` = nombre + activo, sin PIN; los roles existen en el sitio (`permisos.js`, `/api/device/me`) pero el POS no los
  usa, y el token del celular es administrador total.
- Propuesta: `domain/permisos.dart` con `puede(rol, capacidad)` (un solo lugar); capacidades: ver costos y ganancia, anular y
  editar ventas, ver/cerrar cierres, retirar ganancia, configuración, pagar proveedores, editar precios/importar, gestionar
  usuarios. **El servidor de la PC aplica los permisos** (no solo se oculta el botón); el celular manda el usuario con PIN.
  Rol por cuenta cuando el equipo está vinculado y PIN por usuario cuando se usa solo local (migración: `rol`, `pin_hash`).
  El sitio suma el rol por usuario del POS y su sincronización.
- ❓ Hay que definir con el dueño qué puede y qué no puede un empleado y un encargado.

## Fase 6 — Mercado Pago: lo que falta
Webhooks, devolución desde el POS al anular, saldo real en el cierre, QR en pantalla. Se lee primero el código de MP a fondo
(solo leí lo que toca el cobro y la conciliación). Detalle en `CONTEXTO.md` §7.

## Fase 7 — Pedido a proveedores por WhatsApp (si se confirma)

Limpieza (cuando se pueda): `.gitignore` de `android/build`, restos de Firestore, `Bloque` y tokens deprecados, ver fallos
intermitentes de `test/ui/venta/`.

## Orden

**0 → 1 → 2 → 3 → 4 → 5 → 6** (7 cuando se decida). La 0 va primero porque es plata y datos; la 1 antes que la 2 para no
arreglar dos veces la misma pantalla; la 5 y la 6 son las grandes y conviene hacerlas con la app ordenada.

## Preguntas abiertas al dueño

1. ¿Hay fiados reales en la base? 2. ¿"Entregar y anotar deuda" entra en Encargues? 3. Qué puede hacer cada rol.
4. ¿Los productos sin stock se muestran atenuados en la búsqueda o siguen ocultos? 5. ¿Tema oscuro "seguir al sistema" en vez
de por horario? 6. ¿Número de venta global (con prefijo del equipo) en el ticket?

## Qué leí y qué no

Leído línea por línea: `domain/`, `data/`, `servidor/` y `servicios/`, el sitio (`functions/`, `worker.js`) y **toda la UI de la
PC** (venta, cierre, inicio, proveedores, separaciones, historial, impresión, configuración, respaldo, navegación, tema).
Celular: leí gestión, inicio, menú, carrito y cobro, historial, encargues, precios, separaciones, cierre, formulario de
producto, entrar con cuenta y el cliente local. **No leí completos**: bienvenida/animaciones, asistente de negocio nuevo, carga
histórica, configuración, conteo y arqueo del celular, las páginas estáticas del sitio, ni ejecuté la app en dispositivos
reales (falta probar con Windows al 125 %/150 %, escáner, cajón y terminal Point).

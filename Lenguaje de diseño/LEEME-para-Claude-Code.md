# POS La Plazoleta — guía de diseño para implementar

Este paquete tiene los mockups del POS (desktop y móvil) y lo necesario para implementarlos.

## Importante sobre los archivos `.dc.html`

Están en un formato de maqueta (Design Component). **No son HTML plano listo para usar**: dependen de un runtime propio (`support.js`, etiquetas `<x-dc>`, `<sc-for>`, `<sc-if>`, `{{variables}}` y una clase `Component extends DCLogic`).
Usalos como **referencia visual y de comportamiento**. Cada archivo tiene:
- el markup con todos los estilos inline (colores, tamaños, espaciados exactos);
- al final, un `<script>` con los datos de ejemplo y la lógica (cálculos, filtros, estados).

Traducciones rápidas del formato:
- `{{x}}` → valor que se calcula en `renderVals()`.
- `<sc-for list="{{items}}" as="it">` → un `.map()` / bucle.
- `<sc-if value="{{cond}}">` → render condicional.
- `onClick="{{fn}}"` → handler de click.
- `<dc-import name="MovilNav">` → incluir el componente de `MovilNav.dc.html`.

## Pantallas

| Archivo | Pantalla |
|---|---|
| `Main.dc.html` | Separaciones (desktop) — cuánto apartar por proveedor y medio de pago, con tildes por sobre |
| `Dashboard.dc.html` | Dashboard del día |
| `Proveedores.dc.html` | Proveedores → productos, con modal de edición de producto |
| `HistorialVentas.dc.html` | Historial de ventas con detalle de ticket |
| `HistorialCierres.dc.html` | Historial de cierres de caja con conciliación de efectivo |
| `MovilDashboard.dc.html` | Dashboard (móvil) |
| `MovilSeparaciones.dc.html` | Separaciones (móvil) |
| `MovilProveedores.dc.html` | Lista de proveedores (móvil) |
| `MovilProveedor.dc.html` | Detalle de proveedor con productos (móvil) |
| `MovilEditar.dc.html` | Editar producto como hoja inferior (móvil) |
| `MovilNav.dc.html` | Menú desplegable (móvil) |
| `Ventas.dc.html` | Vender (desktop): buscador, 12 productos rápidos, ticket tipo recibo, Cobrar. Incluye todos los modales del cobro (confirmar, mixto, esperando MP, rechazado, cobrada, descartar) según la prop `paso` |
| `VentasBuscando.dc.html` | Vender con la búsqueda abierta |
| `CobroConfirmar` / `CobroMixto` / `CobroEsperando` / `CobroRechazado` / `CobroListo` / `CobroDescartar` `.dc.html` | Cada paso del flujo de cobro (son `Ventas` con `paso="..."`) |
| `DetalleDia.dc.html` | Historial → ventas de un día, con Imprimir/Editar por ticket |
| `EditorVenta.dc.html` | Editar una venta ya cobrada (ajusta stock, caja y separaciones) |
| `CierreCaja.dc.html` | Modal de cierre de caja: debería haber vs contado, con diferencia en vivo |
| `ConteoStock.dc.html` | Conteo de stock con diferencias y "Aplicar ajustes" |
| `CargaHistorica.dc.html` | Cargar ventas viejas día por día, con costo estimado |
| `ConfigImpresion.dc.html` | Configuración: impresión (con vista previa del ticket) y respaldo |
| `CompararPrecios.dc.html` | Comparar costo de un producto entre proveedores |
| `DialogosVenta.dc.html` | Pago mixto, Varios, Movimiento rápido (gasto/ingreso), Cambiar cantidad |
| `DialogosProveedores.dc.html` | Registrar pago, Nuevo proveedor, Edición masiva, Importar CSV |
| `DialogosSeparaciones.dc.html` | Ganancia, Retirar plata, Productos sin costo, Ajustes de separación |
| `canvas.json` | Índice del canvas (posición de cada pantalla). No hace falta para implementar |

Pendiente de diseñar: móvil de Carrito de venta, Historial, Gestión/Configuración, Movimiento de caja/Arqueo, Conteo/Consulta de precios, hojas desplegables y pantallas de Login.

Navegación: un menú desplegable desde el título de cada pantalla (no hay barra lateral).

## Tokens de diseño

- Tipografía: **Figtree** (Google Fonts), 400/500/600/700, números con `font-variant-numeric: tabular-nums`.
- Fondo de página `#f0f4f9` · cards `#ffffff`, radio 16–24 px · texto `#1f1f1f`, secundario `#444746`, apagado `#5e5e5e`.
- Acento / selección: azul `#0b57d0`, fondo seleccionado `#d3e3fd`, texto sobre él `#041e49`.
- Card destacada (acción principal / totales): `#1f1f1f` con texto blanco.
- **Efectivo**: `#b45309` (fondo suave `#fdf3e7`, texto `#7a3a04`).
- **Mercado Pago**: `#0b57d0` (fondo suave `#e8f0fe`, texto `#0842a0`).
- Ganancia / OK: `#146c2e` (fondo `#e6f4ea`).
- Alerta stock bajo / sobrante: `#7a3a04` sobre `#fef1e0`.
- Faltante / eliminar: `#8c1d18` / `#b3261e` sobre `#fce8e6`.
- Botones y zonas táctiles ≥ 44 px de alto.

## Datos que necesita cada pantalla

**Venta (ticket)**: id, número, fecha/hora, medio (`efectivo` | `mercadopago`), anulada, líneas.
**Línea de venta**: producto_id, cantidad, precio_unitario y **costo_unitario guardados al momento de vender** (así el historial no cambia si después actualizás precios).
**Producto**: id, nombre, proveedor_id, código de barras, costo, precio, stock, stock_minimo.
**Proveedor**: id, nombre, rubro, contacto WhatsApp, día de visita.
**Cierre de caja**: fecha, apertura, cierre, cambio_inicial, pagos_proveedores, retiros, contado, nota.
**Separación**: fecha, proveedor_id, separado (bool) — para los tildes.

Cálculos clave:
- A separar por proveedor y medio = suma de `cantidad × costo_unitario` de las líneas no anuladas, agrupada por proveedor y medio.
- Ganancia = total − costo.
- Efectivo esperado en caja = cambio_inicial + ventas en efectivo − pagos a proveedores − retiros; diferencia = contado − esperado.
- Stock bajo = stock < stock_minimo.

Consulta de ejemplo (SQLite) para Separaciones de hoy:

```sql
SELECT p.proveedor_id,
       v.medio,
       SUM(l.cantidad * l.costo_unitario)  AS a_separar,
       SUM(l.cantidad * l.precio_unitario) AS vendido
FROM ventas v
JOIN venta_lineas l ON l.venta_id = v.id
JOIN productos p    ON p.id = l.producto_id
WHERE date(v.fecha) = date('now', 'localtime')
  AND v.anulada = 0
GROUP BY p.proveedor_id, v.medio;
```

Los montos y nombres de los mockups son datos de ejemplo.

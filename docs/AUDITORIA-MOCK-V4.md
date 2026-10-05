# Auditoría: ¿el mock v4 tiene todas las funciones de la app de PC real?

**Fecha:** 05/10/2026 · **Respuesta corta: no, todavía no.** La estética está, la gran mayoría de las pantallas están, pero faltan funciones
chicas y medianas, y hay un puñado de cosas del mock que **no existen** en la app real. Esta tabla es la lista para cerrar eso **antes** de
aplicar el diseño al código.

## Cómo se hizo (y qué NO cubre)

1. Se sacaron **todos los textos visibles** del código real (`lib/ui/**`, ~130 archivos: botones, diálogos, avisos, filtros, secciones).
2. Se volcó **todo el texto** del mock v4 (61 estados: 11 pantallas, 16 secciones de Configuración, 38 diálogos, pasos del cierre, pestañas).
3. Se compararon a mano función por función.

**No cubre:** la lógica interna (reglas de dinero, redondeo, recargo: esas las prueban los ~2016 tests de la app, no el mock); la app del
celular; ni se corrió la app real. Una función puede estar en el mock y verse distinta a como anda de verdad. **Lo "✅" significa "tiene
dónde vivir en el mock", no "está probada".**

Leyenda: ✅ está · ⚠️ parcial · ❌ falta en el mock · ➕ está en el mock pero **no existe** en la app real. Prioridad: **A** diaria o toca plata ·
**B** semanal · **C** rara.

## 1. Lo que sacamos en la v4 y no corresponde (error mío)

| Qué | Real | Mock v4 | Prio |
|---|---|---|---|
| Historial: períodos | Hoy · Ayer · **Este mes** | Solo Hoy · Ayer (saqué "Este mes" al sacar "Últimos 7 días", que nunca existió) | **A** |

## 2. Faltan en el mock (existen en la app real)

### Venta y caja
| Función real | Estado | Prio |
|---|---|---|
| Diálogo **Imprimir ticket**: Enviar a posnet / Guardar PDF / elegir carpeta (hoy el botón solo muestra un aviso) | ❌ | A |
| **Abrir caja**: elegir **quién abre** (y agregar otra persona en el momento) | ❌ (solo 3 montos) | A |
| **Caja de ayer sin cerrar** (aviso en la barra y en Venta al abrir el sistema) | ❌ | A |
| **Cerrar el sistema** con la caja abierta: "¿Cerrar La Plazoleta? … no se hace el arqueo" → Ir a cerrar / Seguir / Cerrar igual (la X de la ventana no hace nada) | ❌ | A |
| Cierre ya hecho → **Reabrir caja** (visible en el paso "Caja cerrada") | ⚠️ existe la acción, **no hay botón visible** | A |
| Gasto rápido: motivos rápidos (Flete, Limpieza, Bolsas, Impuestos, Otro) | ⚠️ hay "Proveedor / Limpieza / Fletes / Retiro / Otro" (distintos) | B |
| Diálogo **Datos de tu comercio** (primer arranque / "Más tarde") | ❌ | C |

### Proveedores y productos
| Función real | Estado | Prio |
|---|---|---|
| Lista: entradas **Todos los productos** y **Sin proveedor** | ❌ | A |
| Detalle: cifras **Vendido · Ganancia · Stock a costo · Stock a precio · Separado · Le debés** con período **Hoy / Semana / Mes / Desde el último pago** | ❌ (hay solo la deuda) | A |
| Tabla de productos: **casillas de selección** (para la edición masiva) y filtro **Todos (n) / Stock bajo (n)** | ❌ (la edición masiva abre sin selección) | A |
| **Cuenta corriente**: **Cargar deuda** (monto, nota, fecha), **Pagar**, y **Anular** un pago o una deuda | ⚠️ solo lista de movimientos | A |
| **Editar producto**: Proveedor, Categoría (con "Nueva categoría"), **Cigarrillo: atado / suelto**, Activo, Precio fijo vs. automático, **motivo del ajuste de stock** | ⚠️ faltan esos campos | A |
| **Ver lata** (saldo de la lata de cigarrillos: vendido hoy, pendiente de cierres anteriores) | ❌ | B |
| **Selector de ganancia %** por proveedor ("Aplicar a los precios", vista previa de cambios, "no se tocan fijos/cigarrillos/sin costo") | ⚠️ está en Avanzado solo como texto; no hay vista previa | B |
| Edición masiva: precio **y costo**, sumar/restar **monto o %**, categoría, proveedor, **activar/desactivar**, aviso si el cambio es raro (más del doble, deja en $0) | ⚠️ solo "subir %" y cambiar proveedor/categoría | B |
| **Promos**: formulario Nueva/Editar (nombre, artículos, % con tope y aviso "no cubre su costo"), activar/desactivar | ⚠️ solo la lista y las sugeridas | B |
| **Comparar precios**: en la app real es **tu precio contra los súper** (SEPA, Todo a tu Casa, "Actualizar ahora") | ➕ el mock compara costos entre proveedores: **es otra función** | B |
| Conteo de stock: **Bajar planilla** | ❌ | C |

### Separaciones, Historial, Cierre
| Función real | Estado | Prio |
|---|---|---|
| Separaciones: período **Hoy / Semana / Mes** | ❌ (solo hoy) | A |
| Retirar ganancia: aviso **"estás retirando más de lo que el negocio ganó… Retirar igual"** | ❌ | A |
| Historial · Ventas: filtro por medio **Todos / Efectivo / Débito / Crédito / Mixto** | ❌ | B |
| Historial · Movimientos: filtro **Todos / Gasto / Ingreso / Pago a proveedor / Retiro** | ❌ | B |
| **Devolución por Mercado Pago** al anular una venta cobrada con la terminal ("Sí, devolver $…") | ❌ (solo un texto) | A |
| Detalle del día: **Ocultar/Ver** el vendido por proveedor, etiqueta **Editada**, anular desde ahí | ⚠️ | C |
| Editor de venta: **renglón libre**, **motivo obligatorio al confirmar**, anular desde el editor, resumen "qué se va a ajustar" (stock / a separar / ganancia) | ⚠️ solo una nota | B |
| Carga histórica: **calendario del mes** con días "ya tiene caja / falta cargar", **hora**, **varias ventas en una tanda** ("Agregar venta" → "Guardar día (n)") | ⚠️ una sola venta, fechas fijas | B |
| Cierre: **arqueos del turno** (lista), **Nota (opcional)**, **A separar por proveedor**, **Vendido sin costo**, **Cargar la diferencia de MP como gasto/ingreso** | ❌ | A |
| Cierre: Mercado Pago **por canal** (QR / débito / crédito / prepaga / transferencia), devoluciones, comisiones, "volver a consultar" | ⚠️ resumido en 4 líneas | B |

### Inicio / Este mes
| Función real | Estado | Prio |
|---|---|---|
| **Cargar / corregir monto** de un fijo del mes (diálogo propio) y **Pagos de fijos** (presupuestado / pagado / pendiente) | ⚠️ "Cargar" abre el diálogo de pago | B |

### Configuración
| Función real | Estado | Prio |
|---|---|---|
| Usuarios: **Activar / Desactivar** (mock: solo Renombrar y Agregar) | ⚠️ | B |
| Respaldo: **Copias a conservar (n)**, **Importar una base** (.sqlite/.gz) | ❌ | B |
| Cuenta de Nodo Sur: **Guardar una copia ahora**, **Copias en tu cuenta + Restaurar**, **Volver a bajar todo**, estado de suscripción | ⚠️ solo "Sincronizar" y "Desconectar" | B |
| Impresión: **Access Token**, **Terminal ID** (imprime y cobra), **Reimprimir una venta por N°** | ⚠️ ("Token local" sin campos; no hay reimpresión por número) | B |
| Celular: **Desconectar los celulares**, **QR para instalar la app**, IP de la PC en el wifi | ⚠️ | C |
| Asistente IA: **Quitar clave**, modelo, aviso de privacidad del plan gratis | ⚠️ | C |
| **Estado de Mercado Pago** (conectado / falta elegir terminal / reconectar → horsepos.com/negocio) | ❌ | B |

## 3. Está en el mock pero NO existe en la app real (➕ a confirmar o sacar)

| Cosa del mock | Nota |
|---|---|
| Config › Comercio: **Rubro**, **Logo del ticket** | La app real solo tiene nombre y encabezado. |
| Config › Cuenta: **Sucursal**, **Miembros** | No existen en la PC. |
| Nuevo/Editar proveedor: **WhatsApp**; Avanzado: **"Excluir de la reposición"** | La real tiene Código, Activo, "Caja aparte (cobra solo en efectivo)". |
| Encargues: **Seña (opcional)** | No existe. |
| Venta cobrada que **se cierra sola** y diálogos **sin Cancelar** | Decididos en la v4, a confirmar (ya anotado). |
| Asistente **Ctrl+K** con pregunta libre a la IA, **Pagar proveedor Alt+P**, menú **Caja ▾** | Nuevos de la v3/v4 (la función de fondo existe; la forma de llegar es nueva). |
| Comparar precios **entre proveedores** | Ver arriba: la real compara contra súper. |

## 4. Lo que SÍ está (resumen)

Venta completa (búsqueda, pesables "200 queso", categorías, más vendidos, medios, mixto, tarjeta débito/crédito, cobro a mano, descuento,
varios, vuelto/caramelo, cantidad exacta, quitar y cancelar con Deshacer, ventas en pestañas, notificaciones de arqueo y de Mercado Pago, arqueo
intermedio, cambio de turno, gasto/ingreso rápido); Inicio hoy y mes (estado de resultados, margen necesario, fijos); Proveedores (lista, ficha,
cuenta corriente en lectura, pagar proveedor, avanzado, CSV, factura con IA, conteo de stock); Separaciones (por proveedor, ganancia, sin costo,
retirar); Historial (ventas, movimientos, cierres, detalle del día, editar y anular venta, carga histórica); Encargues (apartar, entregar,
cancelar, cobrar deuda); Cierre en dos pasos con conteo a ciegas; Configuración con las 16 secciones; actualización y restaurar copia.

## 5. Orden propuesto para cerrar

1. **Prioridad A** (sección 1 + todo lo marcado A): son ~15 puntos; los más importantes son los que tocan plata o el arranque/cierre del día.
2. Decidir con el dueño la sección 3 (sacar o dejar lo inventado).
3. **Prioridad B**, y recién después empezar a aplicar al código pantalla por pantalla (con la lista ya cerrada).
4. **C** se puede dejar tal cual está hoy en la app real, sin rediseñar.

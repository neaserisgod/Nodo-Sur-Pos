# Plan · Nodo Sur para servicios (barbería, uñas y belleza)

**Estado al 2026-10-09: mock hecho, sin código.** Mock: `docs/mock-servicios/NodoSurServicios.html`
(vivo: https://claude.ai/artifact/2RdUiVVqZkPvn9qezwW2gJ). Este plan sigue la regla de `CLAUDE.md`: plan antes de código,
una etapa por vez y tests primero en `domain/`.

## Lo que decidió el dueño (2026-10-09)

1. **Una sola app.** No se arma otra app: en el onboarding, al elegir el rubro, se decide qué pantallas ve el negocio.
   Un almacén sigue viendo la app de hoy; una barbería o un local de uñas arrancan en la Agenda.
2. **Todo es opcional** (SaaS multi-negocio). Cada función nueva es un módulo que el negocio prende o apaga; apagado no se
   muestra ni entra en los cálculos. El rubro solo elige con qué módulos arranca.
3. **Si falta un insumo, el servicio no se cobra** (bloquea). Es un módulo: apagado, solo avisa.
4. **Varios profesionales**: opcional; sirve para la agenda por persona.
5. **Mano de obra en el costo** y **ajustar lo que se usó al cobrar**: opcionales, los decide cada profesional.
6. **Turnos sí**, y se toman con un **bot de WhatsApp**.
7. **Seña configurable por negocio**: si la pide (nunca, en algunos servicios o en todos), cuánto (% o monto fijo) y si se
   pierde o se devuelve cuando el cliente no viene. Por defecto: algunos servicios, 30 %, se pierde.

## Qué se reutiliza, qué se adapta, qué es nuevo

| | Qué |
|---|---|
| Igual | Cobro (efectivo, QR, tarjeta por Point, mixto, redondeo), caja, cierre, ticket, sincronización, usuarios, cargar factura, proveedores y cuenta corriente. |
| Se adapta | **Productos → Insumos**: el producto gana una unidad de uso (ml, g, u) y un contenido por envase. **Separar** aparta el costo real de lo usado (misma regla de reposición). **Seña de encargues** (`domain/sena.dart`) se reutiliza para la seña del turno. |
| Nuevo | Servicios con receta y calculador de costo; descuento automático de insumos al cobrar; agenda de turnos; profesionales; bot de WhatsApp. |
| Oculto para servicios | Recargo de cigarrillos, vuelto, pesables, encargues, promos, carga histórica, editar en lote, comparador. Ya son módulos o se vuelven módulos. |

## Etapas (una por vez, cada una probada antes de la siguiente)

### Etapa 1 · Rubro guardado y forma de trabajar
- `PlantillaRubro` suma `forma` (`productos` | `servicios`) y `modulosApagados`. Rubros nuevos: **Barbería**,
  **Uñas y belleza** y **Otro servicio**.
- Se **guarda el rubro** en `configuracion_negocio` (hoy solo se usa para cargar categorías y se pierde). Migración v63.
- El onboarding (`asistente_negocio.dart`) agrupa los rubros en "Vendés productos" / "Das servicios" y, al guardar,
  apaga los módulos que el rubro no usa (`ModulosNegocio`).
- Los negocios que ya existen quedan con `forma = productos`: no cambia nada para La Plazoleta.
- Tests: plantillas nuevas y módulos por rubro (`test/domain/`), migración v63 y onboarding (`test/companion/`).

### Etapa 2 · Servicios, insumos y calculador (módulo `insumos`)
- Dominio puro (`domain/servicios.dart`), tests primero: costo por unidad de uso, costo del servicio (redondeo hacia arriba
  al peso, convención 5), ganancia sobre el precio, precio sugerido para la ganancia de referencia, "alcanza para N",
  qué insumo falta y mano de obra (`valor hora × minutos`).
- Tablas: `servicios` y `receta_servicio` (servicio, insumo, cantidad), con `global_id` y `actualizado_en` para la sync.
  El insumo es un **producto** con unidad de uso y contenido por envase: así cargar factura, proveedores, cuenta corriente,
  historial de precios y controlar stock funcionan sin reescribirse.
- Pantallas del celular: Servicios (lista + insumos) y el creador de servicios.

### Etapa 3 · Cobrar servicios
- La línea de venta gana `servicio_id`, y la **foto del costo** (convención 2) es el costo de insumos de ese momento.
- Al cobrar, cada servicio descuenta su receta (o la ajustada, si el módulo está prendido) como **movimiento de stock con
  rastro** (convención 6). Eliminar la venta lo devuelve.
- Módulo `bloquear_insumos`: con insumos que no alcanzan no se agrega ni se cobra; apagado, avisa.
- Tests de caja: lo que entra a la caja es igual que vender productos; "Para reponer" suma el costo real de lo usado.

### Etapa 4 · Agenda y profesionales (módulos `agenda` y `profesionales`)
- Tablas `turnos` (cliente, teléfono, servicio, profesional, inicio, duración, estado, origen, seña) y `profesionales`
  (o los usuarios que ya existen; ver pregunta 2).
- Pantalla Agenda: días, horarios libres, estados, cobrar un turno con un toque. Con `forma = servicios`, es la primera
  pestaña.
- Seña del turno: reutiliza `domain/sena.dart` y la regla de "no vino" según la configuración.

### Etapa 5 · Bot de WhatsApp (módulo `turnos_whatsapp`)
- Vive en el sitio (`NodoSurPage`, Cloudflare Worker), no en la app: tiene que contestar aunque el celular esté apagado.
- Usa la API oficial de WhatsApp Business (Meta). Cada negocio conecta su número desde `/negocio`.
- La seña se cobra con el link de Mercado Pago del negocio (el OAuth que ya existe).
- Es la etapa más grande y depende de las respuestas 3 y 4 de abajo.

## Preguntas antes de programar

1. **Nombre del módulo de agenda.** Ya existe el módulo `turnos` (`lib/domain/modulos.dart`), que significa *varios usuarios y
   cambio de turno de caja*. Propuesta: el nuevo se llama `agenda` en el código y "Turnos y agenda" en pantalla. Las claves
   no se renombran nunca, así que conviene decidirlo antes.
2. **Profesionales: ¿son los mismos usuarios de la app o una lista aparte?** Recomiendo **los mismos usuarios**: ya existen,
   ya se sincronizan y ya tienen nombre. Lo malo: un profesional que no usa el celular igual tiene que existir como usuario.
3. **Bot: ¿quién es la fuente de verdad de la agenda?** Hoy cada equipo tiene su base y se sincroniza "gana el último". El
   bot necesita ver los horarios libres al instante y no puede dar dos veces el mismo horario. Recomiendo que **la agenda
   viva en el servidor** cuando el módulo del bot está prendido, y que la app la lea desde ahí. Es un cambio de arquitectura,
   por eso se pregunta.
4. **Costo de WhatsApp.** Meta cobra por conversación iniciada por el negocio (recordatorios). ¿Lo paga Nodo Sur dentro del
   plan, o se cobra aparte?
5. **Comisión por profesional.** ¿Entra con la agenda (etapa 4) o más adelante? Hoy el plan solo anota quién atendió.
6. **¿La PC también muestra la versión para servicios**, o los negocios de servicios usan solo el celular? El mock es del
   celular. Recomiendo empezar solo con el celular.

## Qué no se probó
Solo existe el mock (probado en Chromium de escritorio y a ancho de celular). No hay código.

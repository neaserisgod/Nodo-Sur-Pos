# Plan: turnos y pedidos para otra persona, y gift cards

El dueño, 2026-10-13: *"si alguien quiere sacar un turno para otra persona como regalo, como sorpresa… lo pido, lo pago y
pasa a buscarlo X persona"*. Toca los tres repos: el bot (`botdemo`), el sitio (`NodoSurPage`, solo lo que viaja cifrado) y
la app (`lib/`). **No hay código todavía.**

## 1. Cómo está hoy

- El bot ata todo a **quien escribe**: guarda su nombre una sola vez por número (`pidiendo_nombre`, `src/core/maquina.js`);
  los recordatorios, la seña y el "no vino" van a ese número.
- La seña es un porcentaje del servicio: **no se puede pagar el turno entero** por link.
- Un pedido del bot de comercio no dice **quién lo retira**.
- El sitio guarda los datos del cliente del turno **cifrados en `bot_turnos.datos_enc`** (JSON libre): sumar campos ahí no
  cambia la base del sitio.

## 2. Decisiones del dueño (2026-10-13)

| Tema | Decisión |
|---|---|
| Pago de un regalo | El bot ofrece **pagar la seña o el turno entero** por link de Mercado Pago. Al cobrar en el local ya figura pagado. |
| Recordatorios | Van a **quien regaló**. Si dejó el teléfono de quien va y dice que sí, el recordatorio le llega también a esa persona (respeta la sorpresa). |
| "No vino" | Se le cuenta a **quien va**, no a quien regaló. |
| Gift card | **Sí, en este mismo trabajo** (regalo sin fecha: quien lo recibe elige el turno después). |

## 3. Turno o pedido para otra persona

**En el bot:**
- En la confirmación del turno se suma **"3 — Es para otra persona"** (al que pide para sí no le agrega ningún paso).
  También entiende frases como "es para mi novia" o "es un regalo".
- Pregunta el **nombre de quien va** y, opcional, **su teléfono**; si lo deja: "¿Le aviso del turno a ella o es sorpresa?".
- Con seña configurada: ofrece **"1 — Pagar la seña ($ X)"** / **"2 — Pagar todo ($ Y)"**. El link es el mismo mecanismo
  de la seña, con el monto completo.
- En comercio, al confirmar el pedido: "¿Lo retirás vos o otra persona?" → **"lo retira: Ana"**.

**En la app:**
- El turno guarda a **quien va** en los campos de siempre (`nombreCliente`, `telefono`) y suma **quién lo pidió**
  (nombre y teléfono), **si es regalo** y **si el aviso va también a quien va**. Migración nueva.
- En la Agenda: **"Ana · lo pidió Juan 🎁"**. Al cobrar, si se pagó todo, queda **$ 0 a cobrar** (como una seña del 100 %).
- El "no vino" suma a la ficha de **quien va** (Regla 21).
- En Encargues: **"Lo retira: Ana"**.

## 4. Gift card

Un **código** que se vende y después se **canjea** por un turno o una compra.

**Contabilidad (propuesta, a confirmar; va a `REGLAS-NEGOCIO.md` cuando se decida):**
- **Vender** una gift card entra a la caja con el medio con que se pagó, como **ingreso de caja, no como venta** (igual que
  la seña, Regla 15): todavía no se dio ningún servicio.
- **Canjearla** es una **venta** del día del canje, pagada con el medio "gift card", que **no mueve la caja** (la plata ya
  entró al venderla).
- Lo que queda sin usar al vencer: ver las preguntas.

**Cómo se usa:**
- Se vende **desde la app** (Caja › "Vender gift card") y **por el bot** ("quiero regalar una gift card" → monto → link de
  Mercado Pago → el código llega por WhatsApp, para reenviarlo).
- Quien la recibe escribe al bot "tengo una gift card ABC123" → saca el turno → al cobrar se descuenta.
- En la app: lista de gift cards (vendidas, usadas, con saldo, vencidas) y canje al cobrar.

## 5. Etapas

| Etapa | Qué | Repos |
|---|---|---|
| 1 | Turno para otra persona + pagar todo por link + "lo retira X" en pedidos | bot, app |
| 2 | Gift card: vender, código, canjear al cobrar, lista | app, bot, sitio (validar el código desde el bot) |

Cada etapa con sus tests y publicada junta en los tres repos (como los turnos del bot).

## 6. Decisiones de la gift card (El dueño, 2026-10-13)

- **De las dos clases**:
  - **Por monto** ($ 20.000): sirve para cualquier cosa y **se usa en partes**; lo que sobra queda de saldo.
  - **Por servicio** ("un semipermanente"): cubre ese servicio **aunque haya subido el precio**. Se usa una vez; si se
    elige otro servicio, vale lo que costaba el original cuando se vendió.
- **Vence a los 6 meses** por defecto, configurable por negocio.
- **Si vence sin usarse**, **cada negocio elige** en Configuración: queda para el negocio (entra como ingreso ese día) o
  se devuelve (queda en una lista "para devolver").

Cuando se implemente, todo esto pasa a `REGLAS-NEGOCIO.md` como regla nueva (§22), junto con la contabilidad de la sección 4.

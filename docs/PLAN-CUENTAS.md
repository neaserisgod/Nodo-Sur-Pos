# Plan · Cuentas, negocios y las tres apps

El dueño, 2026-10-19: *"que no se me haga un lío con aplicación A, B, C, y probablemente alguna complementaria de
gastronomía para los mozos… quiero organizar sobre todo el tema de las cuentas y el multitenant"*. Toca el sitio
(`NodoSurPage`, `functions/_lib/`) y este repo (`lib/servicios/cuenta_nube.dart`, `lib/edicion.dart`). **No hay código
todavía.**

**Estado al 2026-10-19:** las cinco etapas hechas. Las del sitio (1, 2 y 5) y sacar «Solo el bot» están en NodoSurPage#97,
sin mezclar (en el sitio mezclar publica: espera el "mergeá" del dueño). La 3 está mezclada (#145) y la 4 en #146; salen con
la próxima beta.

## Decisiones del dueño (2026-10-19)

1. **Cada negocio es de un solo producto**: Nodo Gestión (almacén, kiosco), Nodo Estudio (turnos) o Nodo Gastro
   (rotisería). Un almacén con rotisería son dos negocios en la misma cuenta de Google.
2. **El plan de Gestión ($ 35.000) trae incluido un negocio de Estudio o de Gastro** (uno u otro, no los dos). Los
   planes de Estudio y Gastro ($ 18.000) cubren solo su producto.
3. **Los nombres del sitio quedan en todos lados**: Nodo Gestión, Nodo Estudio y Nodo Gastro. Las apps hoy se llaman
   "Nodo Sur POS" y "Nodo Sur Servicios"; se cambia **solo el nombre visible** (ventana, ícono, tienda). El id del
   paquete de Android, el AppId del instalador y las rutas de actualización (`android-servicios`...) **no se tocan**:
   cambiarlos deja a los equipos instalados sin actualizaciones.
4. **Mozos: un rol dentro de Nodo Gastro, más adelante** (con las mesas, `PLAN-GASTRONOMIA.md` punto 6). No es una
   cuarta app. Este plan solo deja el lugar: los roles viven en `permisos.js` y sumar `mozo` es una línea más ahí.

## Cómo está hoy (el lío)

- **El servidor no sabe de qué producto es cada negocio.** `orgs` no tiene esa columna: la edición vive solo en la app
  (`lib/edicion.dart`).
- **Cualquier plan cubre cualquier negocio.** `plan_por_negocio.js` cuenta suscripciones del mail y cubre a los N
  negocios más viejos, sin mirar el producto. Pagando Estudio ($ 18.000) se usa la caja de Gestión ($ 35.000), y
  `downloadAccess` deja bajar cualquier instalador con cualquier suscripción. Hoy no hay clientes pagos: **es el
  momento barato de arreglarlo**.
- **Tres nombres por producto**: almacén = "Nodo Sur POS" (app) = "Nodo Gestión" (sitio) = plan `pos`; turnos =
  "Nodo Sur Servicios" = "Nodo Estudio" = plan `emprendedor`; rotisería = "Nodo Gastro" = plan `gastro` (todavía sin
  plan en Mercado Pago).

## Cómo queda

```
cuenta de Google (persona)
 └─ negocio (org) ── producto: gestion | estudio | gastro      ← NUEVO, uno solo y fijo
     ├─ mail de cobro (billing_email) → suscripciones de Mercado Pago
     ├─ sucursales
     └─ miembros: owner · manager · employee  (· mozo, más adelante, solo en gastro)

app instalada (edición) ── solo entra a negocios de su mismo producto
```

**Qué cubre cada plan** (una función, `plan_por_negocio.js`; nadie más lo calcula):

| Plan | Cubre |
|---|---|
| `pos` (Gestión, $ 35.000) | 1 negocio de Gestión **+ 1 de Estudio o Gastro** |
| `pos-bot` (Gestión + bot) | igual que `pos`, con el bot en el de Gestión |
| `emprendedor` (Estudio) | 1 negocio de Estudio, con bot |
| `gastro` (Gastro) | 1 negocio de Gastro, con bot |
| `bot` (solo el bot) | ver pregunta abierta 1 |

El reparto sigue siendo "del más viejo al más nuevo", pero **por producto**: cada suscripción busca el negocio más viejo
de su producto todavía sin cubrir; la de Gestión, después, el más viejo de Estudio o Gastro sin cubrir.

## Etapas

1. **Sitio: el producto del negocio.** Columna `orgs.producto` (se crea sola, como las demás). La app manda su edición
   al vincularse (`/api/device/authorize`, `/api/device/google`) y en `/api/device/negocio`; un negocio sin producto
   toma el de la primera app que se conecta. Un negocio de otro producto responde `otro_producto` con el nombre de la
   app correcta. Tests en `tests/`.
2. **Sitio: qué cubre cada plan.** Reescribir `planDelNegocio` con la tabla de arriba, y que `downloadAccess` mire el
   producto del instalador. **Mientras un negocio no tenga producto, se cubre como hoy** (así nada que ande deja de
   andar). Los negocios eximidos y de admin (La Plazoleta) no cambian.
3. **App: mandar la edición y filtrar.** `cuenta_nube.dart` manda `edicion`; el selector de negocios muestra solo los
   del producto de la app, y ante `otro_producto` dice "Este negocio es de Nodo X: bajala de horsepos.com".
4. **App: nombres.** `nombreDeEdicion`, `manifestPlaceholders` y el nombre visible de los instaladores pasan a Nodo
   Gestión / Nodo Estudio / Nodo Gastro. Sale con la próxima beta. **El `ProductName` de `windows/runner/Runner.rc` no se
   toca**: de él sale la carpeta de datos de Windows (`migracion_carpeta_datos.dart`), y cambiarlo deja a la PC sin su base.
5. **Sitio: pantallas.** `/negocio/` y `/cuenta/` muestran el producto de cada negocio y qué plan lo cubre (o que
   está incluido en el de Gestión). `/admin/` suma la columna.

Orden: 1 → 3 → 2 → 4 → 5. La 2 va después de la 3 para que, cuando el cobro empiece a mirar el producto, las apps ya
lo estén mandando.

## Preguntas abiertas

Contestadas el mismo día: 1, sí (se saca del sitio); 2, sí (el incluido trae el bot).

1. **El plan "Solo el bot" ($ 35.000 + alta $ 70.000)**: Estudio y Gastro ya traen el bot por $ 18.000, así que nadie
   lo va a elegir. Propuesta: sacarlo del sitio (las suscripciones que existan siguen andando).
2. **El negocio incluido con Gestión, ¿trae el bot?** Estudio y Gastro siempre lo traen, así que la propuesta es que sí.
3. **Pendiente (2026-10-19): el precio del bot en el almacén.** Con Gestión ($ 35.000) la rotisería o el estudio incluido
   traen el bot sin costo, pero el bot para el propio almacén cuesta $ 25.000 más por mes y $ 70.000 de alta (Sistema + Bot).
   Para un cliente puede sonar incoherente. Opciones: (a) dejarlo así (el bot de un almacén da más trabajo de configurar);
   (b) bajar el alta o el adicional; (c) que Gestión traiga el bot en el propio almacén. Decide el dueño; no hay código
   hasta que lo haga.

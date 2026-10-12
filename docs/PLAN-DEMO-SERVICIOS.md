# La demo de Nodo Sur Servicios (horsepos.com/demo/)

Pedido del dueño (2026-10-12): *"cómo podemos usar eso para hacer una demo? que la gente entre, vea el sistema y todo eso. Debería
bypassear el login y tener datos sembrados"*. Decisiones del dueño, ese mismo día:

- **Solo Servicios** (no la app de almacén ni el sistema de PC).
- **Siempre de cero**: cada visita arranca con los datos de ejemplo limpios; lo que se tocó se pierde al cerrar.
- **Varios rubros para elegir**: barbería, peluquería, uñas y belleza, estética.

## Cómo está armada

Es **la app de `horsepos.com/app/`, la misma compilación**. El sitio sirve en `/demo/` la página de `/app/` (que carga lo demás
desde `/app/` por su `<base href>`), y `lib/main_web.dart` ve que la dirección es `/demo/` y arranca en modo demo
(`lib/companion/demo/`):

| Pieza | Qué hace |
|---|---|
| `demo.dart` | `modoDemo`, y `prepararDemo()`: preferencias en memoria y base en memoria, antes de que nada lea o escriba. Nada queda en el navegador: no pisa la cuenta ni la base de `/app/`, que están en el mismo sitio. |
| `base_demo_web.dart` | SQLite en WebAssembly, en memoria (sin worker ni OPFS). El `.wasm` se pide contra la base de la página (`/app/`), no contra `/demo/`. |
| `semilla_demo.dart` | Los cuatro negocios de ejemplo: servicios con precio, duración, seña y receta de insumos; dos personas que atienden; clientes; la semana de turnos (los de hoy que ya pasaron, cobrados; uno que no vino; señas pagadas; turnos del bot esperando la seña) y la caja del día abierta. Todo por los repositorios de la app (`crearServicio`, `crearTurno`, `abrirSesion`, el cobro de un turno): las cuentas que se ven son las de verdad. Siempre deja ratos libres para los dos a la vez, para poder dar un turno con "Cualquiera". |
| `pantalla_elegir_demo.dart` | "¿Qué negocio querés ver?". Se entra como el dueño. |
| `franja_demo.dart` | La franja de arriba en todas las pantallas: "Es una demo", **Reiniciar** (recarga: vuelve a elegir) y **Probar gratis** (`/pagar/?plan=emprendedor`, en otra pestaña). |
| `pasarela_demo.dart` | Mercado Pago simulado: QR, débito y crédito "aprueban" solos a los 3 segundos, por el mismo camino que la terminal de verdad. |

Lo que necesita una cuenta no aparece: en Más, "Cuenta" pasa a ser "Crear tu cuenta" y no está "Cambiar" (de persona). No hay
sync (no hay cuenta), ni bot, ni avisos de Mercado Pago.

Publicar: nada aparte. Sale con la app web (`publicar-web.yml`, con `release:` o a mano).

## Probado (2026-10-12)

`test/companion/semilla_demo_test.dart`: los cuatro negocios, abiertos a las 8, a las 15 y a las 23 (ningún turno cobrado antes
de terminar, ninguno abierto que ya pasó, nadie con dos turnos encima, lugar libre todos los días). En Chromium con el worker del
sitio: elegir cada rubro, Agenda, Servicios, Cobrar (efectivo y QR simulado), Caja, Más, dar un turno nuevo; celular y compu.

## Pendiente

- Ver la pantalla en un iPhone real.
- Si se quiere medir cuánta gente entra a la demo: el sitio no la cuenta (la política de contenido de `/app/` no deja cargar el
  script de Cloudflare). Se podría contar en el worker.

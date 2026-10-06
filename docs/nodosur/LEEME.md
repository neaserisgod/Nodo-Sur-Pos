# Endpoint nuevo para NodoSurPage: el equipo del negocio visto desde la PC

La PC (Configuración › Cuenta de Nodo Sur) muestra la sucursal y, al dueño, el equipo del negocio. Para eso el sitio necesita
`GET /api/device/team`, que **todavía no está publicado**: este repo no puede subir cambios a `NodoSurPage`. Hasta que se aplique, la PC
simplemente no muestra esa tarjeta (el sitio responde 404 y la PC lo ignora).

## Qué hace
- Con el token de dispositivo (el mismo de `/api/device/me`), solo lectura.
- Devuelve `{ org: {id,name}, branch: {id,name}, role, members }`.
- `members` (nombre, mail, rol, si trabaja en todas las sucursales y cuáles) solo si quien vinculó la PC es el **dueño**. Un encargado o
  un empleado recibe `members: null`. No devuelve invitaciones.
- Con la sesión web o sin token: 401. Si la persona ya no es miembro activa: 401 (lo hace `deviceFromRequest`).

## Cómo aplicarlo
```
git clone https://github.com/neaserisgod/NodoSurPage && cd NodoSurPage
git checkout -b equipo-para-dispositivos
git am /ruta/a/P41---POS-/docs/nodosur/equipo-dispositivos.patch
node tests/equipo_dispositivo.test.mjs      # 5 pruebas
node tests/worker.test.mjs && node tests/acceso.test.mjs
```
El patch agrega `functions/api/device/team.js`, la ruta en `worker.js`, una línea en el README y `tests/equipo_dispositivo.test.mjs`.
Probado localmente con Node 22; **no se publicó ni se probó contra el sitio real**.

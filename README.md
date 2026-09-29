# La Plazoleta

Sistema de caja y gestión para un almacén de barrio en Bariloche. App de
escritorio en Flutter para Windows — sin red, sin backend, todo local.

Este repo está pensado para que alguien que nunca estuvo en las sesiones de
desarrollo (otra persona, otra sesión de Claude Code, Cowork) pueda seguir
trabajando sin tener que preguntar nada. Para eso, la documentación está
repartida en documentos con un dueño claro cada uno — **no hay dos
documentos diciendo cosas distintas sobre lo mismo**; cuando un tema se
toca en más de un lado, uno es la fuente de verdad y el resto apunta ahí.

## Mapa de documentación

| Documento | Es la fuente de verdad de... |
|---|---|
| [`CLAUDE.md`](./CLAUDE.md) | Cómo está armado el código: stack, arquitectura de carpetas, convenciones que no se rompen, qué es cada fase del roadmap, el flujo de trabajo (plan antes de código, ambigüedades marcadas, tests primero), la restricción de hardware, y la especificación completa de la pantalla de venta. |
| [`REGLAS-NEGOCIO.md`](./REGLAS-NEGOCIO.md) | El dominio del negocio: qué hace la app y por qué, regla por regla (dinero, cigarrillos, reposición, fiado, retiro, etc.). Si el código contradice esto, el código está mal. |
| [`ESTADO.md`](./ESTADO.md) | El estado ACTUAL: qué fases están cerradas, qué falta, tests/`schemaVersion` de hoy, contexto del negocio en una línea, y los próximos pasos concretos. Es el documento que más cambia — se actualiza al cerrar cada fase. |
| [`DECISIONES.md`](./DECISIONES.md) | El PORQUÉ de decisiones de dominio y de arquitectura que sin el motivo parecen arbitrarias (por qué los cigarrillos quedan fuera de la reposición, por qué el costo es nullable, por qué el redondeo va después del recargo, etc.). |
| [`TRAMPAS.md`](./TRAMPAS.md) | Bugs y comportamientos inesperados ya encontrados y resueltos — para no volver a pisar el mismo palo (orden de `sesionCerradaAnterior`, el hang de `dart:io` en `testWidgets`, etc.). |
| [`DISENO.md`](./DISENO.md) | El sistema de diseño completo: escalas de espaciado y tipografía, colores, el acento único y sus tres usos, reglas de alineación y simetría, y las restricciones visuales por hardware. |

Regla general: si vas a agregar algo que ya tiene dueño en esta lista,
agregalo en ese documento — no lo dupliques en otro.

## Cómo correrlo

Requiere el SDK de Flutter con soporte para Windows desktop habilitado
(`flutter config --enable-windows-desktop`).

```powershell
# Instalar dependencias
flutter pub get

# Regenerar código de drift después de tocar un esquema (lib/data/tables/*, database.dart)
dart run build_runner build

# Análisis estático — tiene que dar "No issues found!"
flutter analyze

# Toda la suite de tests (440 al día de este documento, ver ESTADO.md)
flutter test

# Build de desarrollo — se abre con hot reload
flutter run -d windows

# Build de debug sin correr (para probar el binario tal cual)
flutter build windows --debug
# Ejecutable en: build\windows\x64\runner\Debug\la_plazoleta.exe

# Build de producción — el que se instala en la PC del local
flutter build windows --release
# Ejecutable en: build\windows\x64\runner\Release\la_plazoleta.exe
```

### Publicar en la máquina que corre la app (2026-09-14)

`tool\publicar_actualizacion_desktop.ps1` compila en release y copia la
carpeta completa (`.exe` + `.dll` + `data\`, todo lo que hace falta para
que arranque en destino) a `C:\LaPlazoleta\app\` — nunca correr el `.exe`
directo desde `build\windows\x64\runner\Release\` del repo: esa carpeta la
pisa `flutter build`/`flutter clean` en cualquier momento, mala base para
un acceso directo que tiene que seguir andando entre una compilación y la
siguiente.

El mismo script actualiza el acceso directo del escritorio (si ya existe,
apuntándolo a la copia estable) y crea uno en el inicio de Windows —
Bruno, 2026-09-14: "si yo no abro el acceso directo la companion no
funciona" (el servidor embebido que usa el celular solo corre mientras
esta app está abierta, Regla del proyecto, no un bug — pero depender de
acordarse de abrirla a mano sí lo era). Correr:

```powershell
.\tool\publicar_actualizacion_desktop.ps1
```

`-SinAccesoDirecto` salta la parte de accesos directos/inicio de Windows,
por si alguna vez hace falta solo recompilar y copiar.

**Ojo con accesos directos viejos**: en el escritorio y el menú inicio de
esta máquina quedan accesos al sistema anterior (Tauri/Next.js,
`AppData\Local\La Plazoleta Soft\`) — no son esta app, no los toca el
script, y no deberían usarse.

**Revisar los cierres de una base real** (sin tocarla): copiar la base y
correr `$env:BASE_A_REVISAR="ruta\copia.sqlite"; flutter test tool/revisar_cierres_test.dart`
— compara cada cierre guardado contra el mismo cálculo corrido de nuevo,
una cuenta independiente por SQL, la cadena de la lata y los pagos de cada
venta.

La base de datos real vive fuera del repo, en
`C:\Users\Bruno\Documents\la_plazoleta.sqlite` en la máquina de Bruno — no
se versiona ni se copia como parte de un build.

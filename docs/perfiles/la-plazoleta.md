# Perfil de origen — La Plazoleta

El producto nació para este comercio. Sigue siendo una instalación más: todos los módulos activos, con los nombres de
archivo de siempre (base `la_plazoleta`, respaldos `la_plazoleta_*.sqlite`, APK `la_plazoleta_companion.apk`,
`applicationId` del celular), que **no se cambian** para no cortar las actualizaciones ni el emparejamiento de las
instalaciones existentes.

## El comercio

Almacén de barrio con fiambrería. Atiende una persona sola de lunes a viernes, de 10 a 22, y el fin de semana con
ayuda por hora. Cobra en efectivo y con Mercado Pago (QR y terminal Point).

## Cómo está configurado

| Qué | Valor |
|---|---|
| Módulos | todos activos |
| Caja aparte | el proveedor de cigarrillos (código `SC`), solo efectivo, con recargo por atado/suelto |
| Pesables | fiambres (stock en gramos, precio por kilo) |
| Plantilla de rubro | ninguna: el catálogo se cargó a mano; la app hoy ofrece plantillas (Kiosco, Almacén, Fiambrería, Otro) para comercios nuevos |
| Proveedores | los 15 de la Regla 16 de [`REGLAS-NEGOCIO.md`](../../REGLAS-NEGOCIO.md) |
| Cliente recurrente | descuento por porcentaje (Regla 17) |
| Comparador de precios | activo: supermercados de la ciudad (SEPA) y una tienda online de la zona |

## Datos personales

Los nombres de personas, proveedores y clientes reales que aparecen en comentarios, tests y documentos se reemplazan
por nombres genéricos con `tool/limpiar_datos_personales.py` antes de hacer público el repositorio.

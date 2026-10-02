# Comparación de precios con el mercado (investigación, sin implementar)

Fecha de las pruebas: 2026-10-02. Se probó desde un entorno de nube, sin login
y con una sola consulta por tienda. **No se construyó nada**: esto documenta
qué se puede hacer para decidir más adelante.

Zona de referencia: Villa Carlos Paz, Córdoba (CP 5152). Tiendas que sirven en
la zona según el dueño: Cordiez, Disco y Supermercados Buenos Días.

## Fuentes que sirven

### 1. Tiendas VTEX (precio regular, todos los días)

Buscador JSON público, sin autenticación:

```
GET https://<tienda>/api/catalog_system/pub/products/search?ft=<texto>&_from=0&_to=9
GET https://<tienda>/api/catalog_system/pub/products/search?fq=alternateIds_Ean:<EAN>
```

Por producto: `productName`, `items[0].ean`, `items[0].sellers[0].commertialOffer`
(`Price` = precio de venta, `AvailableQuantity` = stock).

| Tienda | Dominio | Resultado |
|---|---|---|
| Cordiez | `www.cordiez.com.ar` | Responde. Es la más barata en los 4 productos de prueba. |
| Disco | `www.disco.com.ar` | Responde. |
| Jumbo | `www.jumbo.com.ar` | Responde (sin filtro de región). |
| Vea | `www.vea.com.ar` | Responde (sin filtro de región). |
| Carrefour | `www.carrefour.com.ar` | Responde. |
| Día | `diaonline.supermercadosdia.com.ar` | Responde. |
| Más Online | `www.masonline.com.ar` | Responde. |

Trampas:
- **Descartar lo que tenga stock 0**: salen publicaciones viejas con precios
  absurdos ($3, $16, $26).
- **No usar `ListPrice` en Disco, Jumbo y Vea**: viene mal cargado (miles de
  veces el precio real). Usar `Price`.
- El EAN puede variar entre tiendas para el mismo producto (ej. Más Online
  `7622201752170` en vez de `7622201735906`), y a veces con ceros a la
  izquierda (`0000077915481`).

### 2. Supermercados Buenos Días (solo ofertas de la semana)

No es VTEX: es un sitio PHP propio. Pero carga las ofertas desde un JSON
público:

```
GET https://superbuenosdias.com.ar/api/ofertas.php   (Accept: application/json)
```

Devuelve `vigencia` ("Del 1 al 7 de octubre del 2026"), `categorias` y
`ofertas` (128 en la prueba). Por oferta: `codigo`, `nombre`, `categoria`,
`precio`, `precioSinImp`, `stock`, `vigencia`, `foto`, `descuentoPorcentaje`.

Trampas:
- Es una API interna, sin documentar: puede cambiar sin aviso.
- **Son ofertas, no el precio de siempre.** Un producto que no aparece no
  significa que no lo vendan: mostrar "sin oferta esta semana".
- Guardar y mostrar la `vigencia` de cada precio; la lista cambia cada lunes.
- `codigo` a veces trae varios EAN unidos por guiones
  (`7790742363008-7790742363107`): separar para cruzar con los productos.

## Resultados de la prueba (4 productos Pepitos, 2026-10-02)

| Producto | EAN | Cordiez | Disco | Buenos Días (oferta) | Otras (mín.) |
|---|---|---|---|---|---|
| Alfajor triple 57 g | `77915481` | 1.919 | 2.350 | — | 2.120 (Día) |
| Galletitas chips 119 g | `7622201735906` | 2.219 | 2.320 | — | 2.290 (Vea) |
| Mini 50 g | `7622201740399` | 1.049 | 1.250 | — | 1.149 (Más Online) |
| Pack x3 357 g | `7622201735883` | 5.979 | 6.280 | 4.299 | 6.190 (Vea) |

## Filtro por región / sucursal: no sirve por ahora

VTEX permite pedir la región por código postal y filtrar con `regionId`:

```
GET https://<tienda>/api/checkout/pub/regions?country=ARG&postalCode=5152
GET .../products/search?fq=alternateIds_Ean:<EAN>&regionId=<id>
```

Con CP 5152 (y también 1425 y 5000):
- Carrefour, Día y Más Online devolvieron región pero **los precios fueron
  idénticos** con y sin `regionId`. No se pudo distinguir si no hay precio por
  región o si el filtro no se aplica.
- Día y Cordiez devuelven la región con `sellers: []` (sin sucursales).
- Jumbo, Disco y Vea dan error `ORD021.6` en el endpoint de regiones.
- Pendiente (no hecho): mirar en el navegador qué envía cada web al elegir
  sucursal.

Conclusión: usar el **precio online general** y rotularlo "precio online,
puede variar en tu sucursal". Un campo de código postal en Configuración
quedaría para cuando alguna tienda lo aproveche.

## No sirven por esta vía

Hiper Libertad, Maxiconsumo y Diarco (sin API VTEX), Super Mami (403), La
Anónima y Farmacity (sin resultados). Sitios con scraping de HTML: no probados.

## Si se implementa más adelante (idea, no decidido)

- Proceso aparte (job programado o servicio en la PC), no dentro del POS.
- Tabla nueva con producto, fuente, URL, precio, fecha y vigencia; el POS solo
  la lee.
- Cruce por `codigoBarras`. Columna "Mercado" en Comparar precios con la fecha
  de cada dato.
- Lista de "productos a seguir" (por EAN) para no consultar todo el catálogo.
- Si una tienda falla, mostrar "dato de hace X días" en vez de un error.
- Términos de uso: muchas webs prohíben el scraping automatizado; para uso
  interno y pocos productos el riesgo suele ser bajo, pero es decisión del
  dueño. Estas APIs no requieren login.

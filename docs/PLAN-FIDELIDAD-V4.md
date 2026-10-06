# Fidelidad 1:1 con el mock v4 — estado (2026-10-06)

El dueño pidió que la PC se vea **igual al mock** (`docs/mock-pc/NodoSurPC-v4.html`), pantallas y animaciones. La versión publicada
(1.0.0+2143) tiene la lógica pero **no** la composición visual del mock.

Esta rama trae un avance de **Venta + barra de navegación** (compila, `flutter analyze` limpio) y el generador de capturas
`test/ui/capturas_v4_test.dart` (renderiza a 1920×1040 con el catálogo del mock y guarda `capturas/v4/*.png`).

**Pendiente** (no verificado en Windows real; los tests de pantalla de Venta/barra todavía no se actualizaron a los textos y medidas nuevos):
- Diferencias que quedan en Venta: cápsulas del total estiradas, etiqueta "Quedan N" sin wrap, formato `$ 16.300`, mega-menús/chevrons
  en la barra, barra de ventana propia, nombre en "Caja · Ana", tema oscuro.
- Inicio y todas las demás pantallas y diálogos, tema oscuro, animaciones fuera de Venta (catálogo en el paquete de entrega:
  `01-ANIMACIONES.md`, `02-TOKENS-Y-MEDIDAS.md`, `03-PANTALLAS.md`, `04-ESTADO-DEL-TRABAJO.md`).

No publicar hasta que el dueño lo pida.

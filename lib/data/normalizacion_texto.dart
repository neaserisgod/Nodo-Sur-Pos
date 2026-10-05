// La normalización de texto (sin mayúsculas ni acentos) vive en `domain/` desde el 2026-10-05, porque el vínculo de facturas con productos
// (`domain/vinculo_factura.dart`) la necesita y `domain/` no puede importar `data/`. Se re-exporta acá para que nada de lo que ya la
// importaba cambie: sigue siendo UNA sola definición (Regla 3).
export '../domain/normalizacion_texto.dart';

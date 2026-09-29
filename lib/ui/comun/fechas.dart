// Fechas en castellano para los encabezados de pantalla ("sábado 26 de
// septiembre"). Un solo lugar: antes cada pantalla tenía su lista de días
// y meses.

const diasSemana = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const meses = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// "sábado 26 de septiembre".
String fechaLarga(DateTime f) => '${diasSemana[f.weekday - 1]} ${f.day} de ${meses[f.month - 1]}';

/// "septiembre 2026".
String mesLargo(DateTime f) => '${meses[f.month - 1]} ${f.year}';

/// "16:05".
String horaCorta(DateTime f) => '${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';

// Normalización de texto para búsquedas que ignoran mayúsculas y acentos
// (regla del campo único de la pantalla de venta, reusada también en la
// búsqueda de la pantalla de productos): un solo lugar para la tabla de
// reemplazo, para que las dos búsquedas de la app nunca puedan ignorar
// acentos de formas distintas.

const _acentuadas = 'áéíóúàèìòùäëïöüâêîôûñ';
const _simples = 'aeiouaeiouaeiouaeioun';

String normalizarTexto(String texto) {
  var resultado = texto.toLowerCase();
  for (var i = 0; i < _acentuadas.length; i++) {
    resultado = resultado.replaceAll(_acentuadas[i], _simples[i]);
  }
  return resultado;
}

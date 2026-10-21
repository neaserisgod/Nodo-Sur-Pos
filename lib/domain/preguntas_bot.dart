// Las preguntas frecuentes del bot (El dueño, 2026-10-21: "que cubra todas las posibles preguntas acerca de las hamburguesas").
// El bot ya las contesta (`botdemo/src/core/nlu.js`, `tema`: `config.preguntas` = [{claves, respuesta}], antes que pagos, envíos,
// horarios y ubicación); la app no tenía dónde cargarlas. Acá viven las reglas: leerlas de la configuración del bot, devolverla
// con los cambios sin tocar lo demás, y el bloque de texto que se pega para cargar muchas de una vez.
//
// El bot compara las claves por frase exacta o por palabra (con tolerancia a errores de tipeo): por eso una clave suelta y corta
// ("carne") calza en mensajes que no son esa pregunta. El editor avisa (`avisosDeClave`), no lo impide.

/// Una pregunta del local: las frases que la disparan y lo que contesta el bot. [titulo] es solo para mostrarla en la lista.
class PreguntaBot {
  const PreguntaBot({required this.claves, required this.respuesta, this.titulo = ''});

  final List<String> claves;
  final String respuesta;
  final String titulo;

  /// Lo que se muestra en la lista: el título, o la primera clave si no tiene.
  String get nombre => titulo.trim().isNotEmpty ? titulo.trim() : (claves.isEmpty ? '' : claves.first);

  Map<String, dynamic> toJson() => {
        if (titulo.trim().isNotEmpty) 'titulo': titulo.trim(),
        'claves': claves,
        'respuesta': respuesta,
      };
}

/// Hasta dónde se aceptan: el sitio guarda la configuración entera del bot con un tope de tamaño.
const maxPreguntasBot = 80;
const maxClavesPorPregunta = 30;
const maxLargoClave = 60;
const maxLargoRespuesta = 1000;

/// Lo que cargó el local, como lo tiene la configuración del bot.
class PreguntasDelBot {
  const PreguntasDelBot({this.preguntas = const [], this.pagos = '', this.envios = '', this.emoji = ''});

  final List<PreguntaBot> preguntas;

  /// Lo que contesta a "¿cómo se paga?" y "¿hacen envíos?". Vacío: lo arma el bot (o lo contesta una persona).
  final String pagos;
  final String envios;

  /// El emoji del local en el menú y la carta (`textos.emoji`). Vacío: el del rubro.
  final String emoji;
}

/// Saca de la configuración del bot lo que se edita acá. Lo que no tiene la forma esperada se ignora.
PreguntasDelBot preguntasDeConfig(Map<String, dynamic>? config) {
  final c = config ?? const {};
  final lista = <PreguntaBot>[];
  final crudas = c['preguntas'];
  if (crudas is List) {
    for (final x in crudas) {
      if (x is! Map) continue;
      final claves = x['claves'];
      final respuesta = x['respuesta'];
      if (claves is! List || respuesta is! String) continue;
      lista.add(PreguntaBot(
        claves: [for (final k in claves) if (k is String && k.trim().isNotEmpty) k.trim()],
        respuesta: respuesta,
        titulo: x['titulo'] is String ? x['titulo'] as String : '',
      ));
    }
  }
  final respuestas = c['respuestas'] is Map ? c['respuestas'] as Map : const {};
  final textos = c['textos'] is Map ? c['textos'] as Map : const {};
  return PreguntasDelBot(
    preguntas: lista,
    pagos: respuestas['pagos'] is String ? respuestas['pagos'] as String : '',
    envios: respuestas['envios'] is String ? respuestas['envios'] as String : '',
    emoji: textos['emoji'] is String ? textos['emoji'] as String : '',
  );
}

/// La configuración del bot con [p] puesto encima de [anterior]: todo lo demás (números, horarios, pedidos, el resto de los
/// textos y respuestas) queda como estaba. Una respuesta vacía va como `null` (el bot la arma o la contesta una persona) y un
/// emoji vacío se saca, así vuelve el del rubro.
Map<String, dynamic> configConPreguntas(Map<String, dynamic> anterior, PreguntasDelBot p) {
  final respuestas = Map<String, dynamic>.from((anterior['respuestas'] as Map?) ?? const {});
  respuestas['pagos'] = p.pagos.trim().isEmpty ? null : p.pagos.trim();
  respuestas['envios'] = p.envios.trim().isEmpty ? null : p.envios.trim();
  final textos = Map<String, dynamic>.from((anterior['textos'] as Map?) ?? const {});
  if (p.emoji.trim().isEmpty) {
    textos.remove('emoji');
  } else {
    textos['emoji'] = p.emoji.trim();
  }
  return {
    ...anterior,
    'preguntas': [for (final q in p.preguntas) q.toJson()],
    'respuestas': respuestas,
    'textos': textos,
  };
}

/// Lo que está mal en una pregunta para guardarla (vacío: está bien).
List<String> problemasDePregunta(PreguntaBot p) {
  final malos = <String>[];
  if (p.claves.isEmpty) malos.add('Falta al menos una frase que la dispare.');
  if (p.claves.length > maxClavesPorPregunta) malos.add('Son muchas frases: hasta $maxClavesPorPregunta.');
  if (p.claves.any((k) => k.length > maxLargoClave)) malos.add('Cada frase va hasta $maxLargoClave letras.');
  if (p.respuesta.trim().isEmpty) malos.add('Falta la respuesta.');
  if (p.respuesta.length > maxLargoRespuesta) malos.add('La respuesta va hasta $maxLargoRespuesta letras.');
  return malos;
}

/// Las claves que probablemente disparen la pregunta donde no corresponde: una palabra suelta de menos de 5 letras, o una que
/// es parte del nombre de algo de la carta ([nombresCarta]), así "¿tienen cerveza?" no se confunde con pedir la cerveza.
List<String> avisosDeClave(List<String> claves, {List<String> nombresCarta = const []}) {
  final palabrasCarta = {for (final n in nombresCarta) ...normalizarClave(n).split(' ').where((w) => w.length >= 3)};
  final avisos = <String>[];
  for (final k in claves) {
    final n = normalizarClave(k);
    if (n.isEmpty || n.contains(' ')) continue;
    if (palabrasCarta.contains(n)) {
      avisos.add('"$k" está en la carta: mejor una frase como "tienen $n".');
    } else if (n.length < 5) {
      avisos.add('"$k" es muy corta: puede saltar en otros mensajes.');
    }
  }
  return avisos;
}

/// Como compara el bot (`nlu.normalizar`): minúsculas, sin tildes ni signos.
String normalizarClave(String s) {
  const conTilde = 'áéíóúüÁÉÍÓÚÜ';
  const sinTilde = 'aeiouuaeiouu';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = conTilde.indexOf(ch);
    b.write(i >= 0 ? sinTilde[i] : ch);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9ñ\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Lo que se leyó de un bloque pegado.
class BloquePreguntas {
  const BloquePreguntas({required this.preguntas, this.pagos, this.envios, this.emoji, this.errores = const []});
  final List<PreguntaBot> preguntas;

  /// Null: el bloque no lo trae (se deja lo que había).
  final String? pagos;
  final String? envios;
  final String? emoji;

  /// Lo que no se pudo leer, para mostrarlo ("Pregunta 3: falta la respuesta").
  final List<String> errores;
}

/// Lee un bloque de preguntas pegado (lo que se arma una vez y se pasa por WhatsApp). Las preguntas se separan con una línea
/// `---`; cada una lleva `claves:` (frases separadas por coma) y `respuesta:` (sigue en los renglones de abajo hasta el
/// separador), y opcional `pregunta:` (el título). Antes de la primera, o en cualquier parte, `emoji:`, `pagos:` y `envios:`.
///
/// ```
/// emoji: 🍔
/// pagos: Efectivo al recibir o transferencia.
/// ---
/// pregunta: ¿De qué es la carne?
/// claves: que carne, de que es la carne
/// respuesta: Aguja picada, 100 g cada medallón.
/// ```
BloquePreguntas leerBloquePreguntas(String texto) {
  final preguntas = <PreguntaBot>[];
  final errores = <String>[];
  String? pagos;
  String? envios;
  String? emoji;
  final bloques = texto.replaceAll('\r\n', '\n').split(RegExp(r'^\s*-{3,}\s*$', multiLine: true));
  var n = 0;
  for (final bloque in bloques) {
    String? titulo;
    String? claves;
    final respuesta = <String>[];
    var enRespuesta = false;
    for (final linea in bloque.split('\n')) {
      final m = RegExp(r'^\s*(pregunta|claves|respuesta|emoji|pagos|envios|envíos)\s*:\s*(.*)$', caseSensitive: false).firstMatch(linea);
      final clave = m?.group(1)!.toLowerCase();
      if (m != null && !(enRespuesta && clave != 'claves' && clave != 'pregunta' && clave != 'respuesta')) {
        final valor = m.group(2)!.trim();
        enRespuesta = false;
        switch (clave) {
          case 'pregunta':
            titulo = valor;
          case 'claves':
            claves = valor;
          case 'respuesta':
            enRespuesta = true;
            if (valor.isNotEmpty) respuesta.add(valor);
          case 'emoji':
            emoji = valor;
          case 'pagos':
            pagos = valor;
          default:
            envios = valor;
        }
        continue;
      }
      if (enRespuesta) respuesta.add(linea.trimRight());
    }
    if (titulo == null && claves == null && respuesta.isEmpty) continue;
    n++;
    final p = PreguntaBot(
      titulo: titulo ?? '',
      claves: [for (final k in (claves ?? '').split(',')) if (k.trim().isNotEmpty) k.trim()],
      respuesta: respuesta.join('\n').trim(),
    );
    final malos = problemasDePregunta(p);
    if (malos.isEmpty) {
      preguntas.add(p);
    } else {
      errores.add('Pregunta $n${p.nombre.isEmpty ? '' : ' (${p.nombre})'}: ${malos.join(' ')}');
    }
  }
  return BloquePreguntas(preguntas: preguntas, pagos: pagos, envios: envios, emoji: emoji, errores: errores);
}

/// Suma lo pegado a lo que ya había: una pregunta con el mismo título (o, sin título, la misma primera clave) se reemplaza; las
/// nuevas van al final. Pagos, envíos y emoji solo cambian si el bloque los trae.
PreguntasDelBot sumarBloque(PreguntasDelBot actual, BloquePreguntas b) {
  String llave(PreguntaBot p) => normalizarClave(p.nombre);
  final lista = [...actual.preguntas];
  for (final nueva in b.preguntas) {
    final i = lista.indexWhere((x) => llave(x) == llave(nueva));
    if (i >= 0) {
      lista[i] = nueva;
    } else {
      lista.add(nueva);
    }
  }
  return PreguntasDelBot(
    preguntas: lista.length > maxPreguntasBot ? lista.sublist(0, maxPreguntasBot) : lista,
    pagos: b.pagos ?? actual.pagos,
    envios: b.envios ?? actual.envios,
    emoji: b.emoji ?? actual.emoji,
  );
}

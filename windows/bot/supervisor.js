// El bot de WhatsApp de Nodo Sur Servicios y Nodo Gastro en Windows (El dueño, 2026-10-15, `docs/PLAN-ESCRITORIO-SERVICIOS.md`):
// hace lo que en Android hace `ServicioBot.kt`. Lo arranca la app (o Windows al iniciar sesión, por la clave Run que deja la app) con
//   node.exe supervisor.js <carpeta de datos del bot>
// y corre oculto, aunque la app esté cerrada:
//  * lee `arranque.json` de la carpeta de datos (lo escribe la app: encendido, carpeta del bot, número);
//  * levanta el bot (`<codigo>/src/index.js`) con el mismo entorno que en Android y lo vuelve a levantar si se cae, cada vez más
//    espaciado si se cae enseguida (hasta 5 minutos);
//  * si la app lo apaga, o pasa a otra versión del bot (otra carpeta), corta y termina: a la versión nueva la arranca la app.
// Uno solo por carpeta de datos (`supervisor.pid`). Sin dependencias: corre con el Node que trae la app.
'use strict';

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

const datos = process.argv[2];
if (!datos) {
  console.error('Uso: node supervisor.js <carpeta de datos del bot>');
  process.exit(2);
}
fs.mkdirSync(datos, { recursive: true });
const archivoArranque = path.join(datos, 'arranque.json');
const archivoPid = path.join(datos, 'supervisor.pid');
const archivoLog = path.join(datos, 'bot.log');
// La carpeta de esta versión del bot: el supervisor corre desde adentro (lo copia la app junto al bot).
const miCodigo = path.resolve(__dirname);

function anotar(texto) {
  try {
    fs.appendFileSync(archivoLog, `[supervisor ${new Date().toISOString()}] ${texto}\n`);
  } catch (_) {}
}

function leerArranque() {
  try {
    return JSON.parse(fs.readFileSync(archivoArranque, 'utf8'));
  } catch (_) {
    return { encendido: false };
  }
}

function vive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (e) {
    return e.code === 'EPERM';
  }
}

// Uno solo: si hay otro vivo, se espera un rato (puede ser la versión vieja terminando para dejarle el lugar a esta) y si
// sigue, esta se va.
async function tomarElLugar() {
  for (let i = 0; i < 30; i++) {
    let otro = 0;
    try {
      otro = parseInt(fs.readFileSync(archivoPid, 'utf8'), 10) || 0;
    } catch (_) {}
    if (!otro || otro === process.pid || !vive(otro)) {
      fs.writeFileSync(archivoPid, String(process.pid));
      return true;
    }
    await new Promise((r) => setTimeout(r, 1000));
  }
  return false;
}

function soltarElLugar() {
  try {
    if (parseInt(fs.readFileSync(archivoPid, 'utf8'), 10) === process.pid) fs.unlinkSync(archivoPid);
  } catch (_) {}
}

let hijo = null;
let arrancoEn = 0;
let intentos = 0;
let reintento = null;
let terminando = false;

function arrancar(arranque) {
  reintento = null;
  const script = path.join(miCodigo, 'src', 'index.js');
  if (!fs.existsSync(script)) {
    anotar(`Falta el bot en ${script}. Abrí la app y encendelo de nuevo.`);
    return terminar(1);
  }
  // El registro no crece para siempre: arranca de cero si pasó de 1 MB (como en Android).
  try {
    if (fs.statSync(archivoLog).size > 1000000) fs.unlinkSync(archivoLog);
  } catch (_) {}
  const salida = fs.openSync(archivoLog, 'a');
  hijo = spawn(process.execPath, [script], {
    cwd: miCodigo,
    windowsHide: true,
    stdio: ['ignore', salida, salida],
    env: {
      ...process.env,
      DIR_DATOS: datos,
      ADAPTADOR: 'baileys',
      // Todo sale de la app: sin servicios cargados, el bot no ofrece los de ejemplo (`botdemo/src/config.js`).
      BOT_EN_APP: '1',
      // Con número, vincula con el código (como en el celular). Sin número (lo que manda la app desde el 2026-10-20) no se pide
      // código: la app dibuja el QR que deja el bot en estado.json y se escanea con el celular del local. Sin PAREO el bot no
      // pide código aunque tenga el número en su configuración: dos vinculaciones a la vez no.
      ...(arranque.numero ? { PAREO: '1', NUMERO_BOT: String(arranque.numero) } : {}),
    },
  });
  fs.closeSync(salida);
  arrancoEn = Date.now();
  anotar(`Bot arrancado (pid ${hijo.pid}).`);
  hijo.on('exit', (codigo) => alTerminarElBot(codigo));
  hijo.on('error', (e) => anotar(`El bot no pudo arrancar: ${e.message}`));
}

function alTerminarElBot(codigo) {
  hijo = null;
  if (terminando) return;
  const arranque = leerArranque();
  if (!arranque.encendido) return terminar(0);
  if (Date.now() - arrancoEn > 10 * 60000) intentos = 0;
  intentos++;
  const espera = Math.min(5000 * 2 ** Math.min(intentos - 1, 6), 5 * 60000);
  anotar(`El bot se detuvo (código ${codigo}). Vuelve a arrancar en ${espera / 1000} s.`);
  reintento = setTimeout(() => {
    const a = leerArranque();
    if (a.encendido && mismaVersion(a)) arrancar(a);
    else terminar(0);
  }, espera);
}

function mismaVersion(arranque) {
  return !arranque.codigo || path.resolve(arranque.codigo) === miCodigo;
}

function terminar(codigo) {
  if (terminando) return;
  terminando = true;
  if (reintento) clearTimeout(reintento);
  clearInterval(vigilancia);
  const fin = () => {
    soltarElLugar();
    process.exit(codigo);
  };
  if (hijo) {
    hijo.once('exit', fin);
    hijo.kill();
    // Si no termina por las buenas en 10 s, igual se va: Windows lo corta con el árbol al cerrar la sesión.
    setTimeout(fin, 10000).unref();
  } else {
    fin();
  }
}

// La app apaga el bot o lo pasa a otra versión escribiendo `arranque.json`: se mira cada 3 segundos.
let vigilancia = null;

(async () => {
  if (!(await tomarElLugar())) process.exit(0);
  const arranque = leerArranque();
  if (!arranque.encendido || !mismaVersion(arranque)) {
    soltarElLugar();
    process.exit(0);
  }
  anotar('Supervisor arrancado.');
  vigilancia = setInterval(() => {
    const a = leerArranque();
    if (!a.encendido) {
      anotar('Apagado desde la app.');
      terminar(0);
    } else if (!mismaVersion(a)) {
      anotar('Pasa a otra versión del bot: esta termina.');
      terminar(0);
    }
  }, 3000);
  process.on('SIGTERM', () => terminar(0));
  process.on('SIGINT', () => terminar(0));
  arrancar(arranque);
})();

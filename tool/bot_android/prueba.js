// Prueba del bot dentro del APK (sin Termux). Cada paso escribe una línea "OK …" o "ERROR …" que la app muestra.
// Uso: node prueba.js <carpeta de datos> [número para pedir código de vinculación]
//
// Escribe en <datos>/bot.log además de la consola: la app lo lanza suelto (sigue andando aunque se cierre la pantalla, mientras
// el servicio de Android mantenga viva la app) y lee el archivo. Queda conectado y anota la memoria cada 30 segundos: si Android
// lo frena con la pantalla apagada, se ve el hueco en la hora.
const fs = require('fs');
const path = require('path');
const [datos, numero] = process.argv.slice(2);
fs.mkdirSync(datos, { recursive: true });
const archivo = path.join(datos, 'bot.log');
const log = (...a) => {
  const linea = [new Date().toISOString().slice(11, 19), ...a].join(' ');
  console.log(linea);
  try { fs.appendFileSync(archivo, linea + '\n'); } catch {}
};
process.on('uncaughtException', (e) => log('ERROR', e.stack));
process.on('unhandledRejection', (e) => log('ERROR', e && e.stack));

(async () => {
  log('OK node', process.version, process.platform, process.arch, 'icu', process.versions.icu, 'openssl', process.versions.openssl, 'pid', process.pid);
  try {
    const { DatabaseSync } = require('node:sqlite');
    const db = new DatabaseSync(path.join(datos, 'prueba.db'));
    db.exec('CREATE TABLE IF NOT EXISTS t (x INTEGER)'); db.prepare('INSERT INTO t VALUES (?)').run(1);
    log('OK sqlite', db.prepare('SELECT COUNT(*) AS n FROM t').get().n, 'filas');
  } catch (e) { log('ERROR sqlite', e.message); }
  try {
    const r = await fetch('https://horsepos.com/');
    log('OK internet (https)', r.status);
  } catch (e) { log('ERROR internet', e.message); }
  let b;
  try {
    b = await import('@whiskeysockets/baileys');
    log('OK baileys cargado');
  } catch (e) { log('ERROR baileys', e.stack); return; }
  const { state, saveCreds } = await b.useMultiFileAuthState(path.join(datos, 'auth'));
  if (state.creds.registered) log('Ya hay un WhatsApp vinculado: me conecto con esa sesión');
  let pedido = false;
  let espera = 2000;

  // Baileys no se reconecta solo: cada corte (y el reinicio que pide WhatsApp justo después de vincular) es un socket nuevo.
  const conectar = () => {
    const sock = b.default({ auth: state, logger: require('pino')({ level: 'silent' }), browser: b.Browsers.ubuntu('Chrome') });
    sock.ev.on('creds.update', saveCreds);
    sock.ev.on('connection.update', async (u) => {
      if (u.connection && u.connection !== 'close') log('conexión:', u.connection);
      if (u.qr && !pedido) {
        pedido = true;
        log('OK WhatsApp respondió (se pudo abrir la conexión cifrada)');
        if (numero) {
          try { log('OK CÓDIGO DE VINCULACIÓN:', await sock.requestPairingCode(numero.replace(/\D/g, ''))); }
          catch (e) { log('ERROR código', e.message); }
        } else {
          log('Sin número: no pido código. Listo, la prueba anduvo.');
          process.exit(0);
        }
      }
      if (u.connection === 'open') { espera = 2000; log('OK VINCULADO: el bot quedó conectado a WhatsApp'); }
      if (u.connection === 'close') {
        const codigo = u.lastDisconnect?.error?.output?.statusCode;
        if (codigo === b.DisconnectReason.loggedOut) {
          log('ERROR WhatsApp cerró la sesión (desvinculado). Borro la sesión: hay que vincular de nuevo.');
          fs.rmSync(path.join(datos, 'auth'), { recursive: true, force: true });
          process.exit(1);
        }
        log('conexión: cortada', codigo || '', u.lastDisconnect?.error?.message || '', `— reconecto en ${espera / 1000} s`);
        setTimeout(conectar, espera);
        espera = Math.min(espera * 2, 60000);
      }
    });
  };
  conectar();
  setInterval(() => log('memoria', Math.round(process.memoryUsage().rss / 1048576), 'MB'), 30000);
})().catch((e) => log('ERROR', e.stack));

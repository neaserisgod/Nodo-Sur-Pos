// Prueba del bot dentro del APK (sin Termux). Cada paso escribe una línea "OK …" o "ERROR …" que la app muestra.
// Uso: node prueba.js <carpeta de datos> [número para pedir código de vinculación]
const fs = require('fs');
const path = require('path');
const [datos, numero] = process.argv.slice(2);
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

(async () => {
  log('OK node', process.version, process.platform, process.arch, 'icu', process.versions.icu, 'openssl', process.versions.openssl);
  fs.mkdirSync(datos, { recursive: true });
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
  const sock = b.default({ auth: state, logger: require('pino')({ level: 'silent' }), browser: b.Browsers.ubuntu('Chrome') });
  sock.ev.on('creds.update', saveCreds);
  let pedido = false;
  sock.ev.on('connection.update', async (u) => {
    if (u.connection) log('conexión:', u.connection, u.lastDisconnect?.error?.message || '');
    if (u.qr && !pedido) {
      pedido = true;
      log('OK WhatsApp respondió (se pudo abrir la conexión cifrada)');
      if (numero) {
        try { log('OK CÓDIGO DE VINCULACIÓN:', await sock.requestPairingCode(numero.replace(/\D/g, ''))); }
        catch (e) { log('ERROR código', e.message); }
      } else log('Sin número: no pido código. Listo, la prueba anduvo.');
    }
    if (u.connection === 'open') log('OK VINCULADO: el bot quedó conectado a WhatsApp');
  });
  setInterval(() => log('memoria', Math.round(process.memoryUsage().rss / 1048576), 'MB'), 30000);
})().catch((e) => log('ERROR', e.stack));

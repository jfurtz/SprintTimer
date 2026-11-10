// Sprint Time Tracker - local server for Windows, macOS and Linux. Needs Node.js 18 or newer, no packages.
'use strict';
const http = require('http'), fs = require('fs'), path = require('path'), os = require('os'), crypto = require('crypto');
const { execFile, spawn } = require('child_process');

if (parseInt(process.versions.node, 10) < 18) { console.log('Node.js 18 or newer is required. Download it from https://nodejs.org'); process.exit(1); }

const PORT = parseInt(process.env.PORT || '8787', 10);
const TARGET = 'SprintTimeTracker:AzureDevOpsPAT';
const AZ_BASE = (process.env.AZ_BASE || 'https://dev.azure.com/').replace(/\/?$/, '/');
const TOKEN = crypto.randomUUID().replace(/-/g, '');
const DIR = __dirname;

// ---------- data folder (the Windows location is the same as the PowerShell version) ----------
const DATA_DIR = process.platform === 'win32' ? path.join(process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming'), 'SprintTimeTracker')
  : process.platform === 'darwin' ? path.join(os.homedir(), 'Library', 'Application Support', 'SprintTimeTracker')
  : path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'), 'SprintTimeTracker');
fs.mkdirSync(DATA_DIR, { recursive: true });
const DATA_FILE = path.join(DATA_DIR, 'data.json');

// ---------- PAT storage: Windows Credential Manager, macOS Keychain, Linux Secret Service (file fallback) ----------
const run = (cmd, args, input) => new Promise((resolve) => {
  const p = execFile(cmd, args, { encoding: 'utf8', windowsHide: true, timeout: 30000 }, (err, stdout) => resolve({ err, out: (stdout || '').replace(/\r?\n$/, '') }));
  if (input != null) { p.stdin.on('error', () => {}); p.stdin.end(input); }
});
const FALLBACK = path.join(DATA_DIR, 'pat.secret');
const stores = {
  win32: {
    get: async () => { const r = await run('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(DIR, 'cred.ps1'), 'get']); return r.err ? null : r.out || null; },
    set: async (v) => { const r = await run('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(DIR, 'cred.ps1'), 'set'], v); if (r.err) throw new Error('Could not store the PAT in Windows Credential Manager'); },
    del: async () => { await run('powershell', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', path.join(DIR, 'cred.ps1'), 'del']); }
  },
  darwin: {
    get: async () => { const r = await run('security', ['find-generic-password', '-a', 'pat', '-s', TARGET, '-w']); return r.err ? null : r.out || null; },
    set: async (v) => { const r = await run('security', ['add-generic-password', '-U', '-a', 'pat', '-s', TARGET, '-w', v]); if (r.err) throw new Error('Could not store the PAT in the macOS Keychain'); },
    del: async () => { await run('security', ['delete-generic-password', '-a', 'pat', '-s', TARGET]); }
  },
  linux: {
    get: async () => { const r = await run('secret-tool', ['lookup', 'service', TARGET, 'account', 'pat']); if (!r.err) return r.out || null; return fileGet(); },
    set: async (v) => { const r = await run('secret-tool', ['store', '--label=' + TARGET, 'service', TARGET, 'account', 'pat'], v); if (r.err) fileSet(v); },
    del: async () => { await run('secret-tool', ['clear', 'service', TARGET, 'account', 'pat']); try { fs.unlinkSync(FALLBACK); } catch (e) {} }
  }
};
const fileGet = () => { try { return fs.readFileSync(FALLBACK, 'utf8').trim() || null; } catch (e) { return null; } };
const fileSet = (v) => fs.writeFileSync(FALLBACK, v, { mode: 0o600 });
const store = stores[process.platform] || { get: async () => fileGet(), set: async (v) => fileSet(v), del: async () => { try { fs.unlinkSync(FALLBACK); } catch (e) {} } };
let patCache, patLoaded = false;
const getPat = async () => { if (!patLoaded) { patCache = await store.get(); patLoaded = true; } return patCache; };
const setPat = async (v) => { await store.set(v); patCache = v; patLoaded = true; };
const delPat = async () => { await store.del(); patCache = null; patLoaded = true; };

// ---------- HTTP server ----------
const send = (res, code, body, type) => { const b = Buffer.isBuffer(body) ? body : Buffer.from(body); res.writeHead(code, { 'Content-Type': type, 'Content-Length': b.length, 'Cache-Control': 'no-store' }); res.end(b); };
const json = (res, code, obj) => send(res, code, JSON.stringify(obj), 'application/json');
const readBody = (req) => new Promise((resolve, reject) => {
  const chunks = []; let n = 0;
  req.on('data', (c) => { n += c.length; if (n > 50e6) { reject(new Error('Request too large')); req.destroy(); } else chunks.push(c); });
  req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
  req.on('error', reject);
});

const server = http.createServer(async (req, res) => {
  try {
    // only answer requests addressed to this machine (blocks DNS-rebinding attempts)
    const host = (req.headers.host || '').replace(/:\d+$/, '').toLowerCase();
    if (host !== 'localhost' && host !== '127.0.0.1' && host !== '[::1]') return send(res, 403, 'Forbidden', 'text/plain');
    const p = new URL(req.url, 'http://localhost').pathname;
    if (p === '/') {
      const html = fs.readFileSync(path.join(DIR, 'index.html'), 'utf8').split('__TOKEN__').join(TOKEN);
      return send(res, 200, html, 'text/html; charset=utf-8');
    }
    if (!p.startsWith('/api/')) return send(res, 404, 'Not found', 'text/plain');
    if (req.headers['x-token'] !== TOKEN) return json(res, 403, { message: 'forbidden' });
    const body = req.method === 'GET' || req.method === 'DELETE' ? '' : await readBody(req);

    if (p === '/api/state') {
      if (req.method === 'PUT') { const tmp = DATA_FILE + '.tmp'; fs.writeFileSync(tmp, body, 'utf8'); fs.renameSync(tmp, DATA_FILE); return json(res, 200, { ok: true }); }
      let t = '{}'; try { t = fs.readFileSync(DATA_FILE, 'utf8') || '{}'; } catch (e) {}
      return send(res, 200, t, 'application/json; charset=utf-8');
    }
    if (p === '/api/pat') {
      if (req.method === 'POST') { const v = (JSON.parse(body || '{}').pat || '').trim(); if (v) await setPat(v); }
      else if (req.method === 'DELETE') await delPat();
      return json(res, 200, { has: !!(await getPat()) });
    }
    if (p.startsWith('/api/az/')) {
      if (!['GET', 'POST', 'PATCH'].includes(req.method)) return json(res, 405, { message: 'method not allowed' });
      const pat = await getPat();
      if (!pat) return json(res, 401, { message: 'No PAT stored' });
      const headers = { Authorization: 'Basic ' + Buffer.from(':' + pat).toString('base64') };
      if (body) headers['Content-Type'] = (req.headers['content-type'] || 'application/json').split(';')[0];
      const r = await fetch(AZ_BASE + req.url.substring(8), { method: req.method, headers, body: body || undefined, signal: AbortSignal.timeout(60000), redirect: 'manual' });
      return send(res, r.status, Buffer.from(await r.arrayBuffer()), 'application/json; charset=utf-8');
    }
    return json(res, 404, { message: 'not found' });
  } catch (e) {
    try { json(res, 500, { message: String(e && e.message || e).replace(/[\r\n]+/g, ' ') }); } catch (x) {}
  }
});

server.on('error', (e) => {
  console.log(e.code === 'EADDRINUSE' ? `Could not start on port ${PORT}. Is it already running?` : 'Could not start: ' + e.message);
  process.exit(1);
});
server.listen(PORT, '127.0.0.1', () => {
  const url = `http://localhost:${PORT}/`;
  console.log(`Sprint Time Tracker is running at ${url}  (close this window or press Ctrl+C to stop)`);
  if (process.env.NO_OPEN === '1' || process.argv.includes('--no-open')) return;
  const [cmd, args] = process.platform === 'win32' ? ['cmd', ['/c', 'start', '', url]] : process.platform === 'darwin' ? ['open', [url]] : ['xdg-open', [url]];
  try { spawn(cmd, args, { stdio: 'ignore', detached: true }).on('error', () => {}).unref(); } catch (e) {}
});

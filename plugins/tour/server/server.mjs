// tour server: read-only tour UI backend. Node >= 18 stdlib, no dependencies.
// Usage: node server.mjs <data-dir> [--port N] [--worktree <dir>] [--open]
// <data-dir> holds tour.json, atoms.json, state.json (created on first PUT) and worktree/ (detached checkout at the head SHA).
// Binds 127.0.0.1 only (random free port unless --port); every request needs the per-run token (URL ?token=, then a cookie).
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const uiDir = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'ui');
const STATIC = { '/': 'index.html', '/index.html': 'index.html', '/app.js': 'app.js', '/app.css': 'app.css' };
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8' };
const MAX_BODY = 1 << 20, MAX_FILE = 2 << 20;

const args = process.argv.slice(2);
const opt = (name) => { const i = args.indexOf(name); return i < 0 ? null : args.splice(i, 2)[1]; };
const port = Number(opt('--port') ?? 0);
const wtOpt = opt('--worktree');
const openIdx = args.indexOf('--open');
const openBrowser = openIdx >= 0 && args.splice(openIdx, 1).length === 1;
const dataDir = args[0] && path.resolve(args[0]);
if (!dataDir || !fs.existsSync(path.join(dataDir, 'tour.json'))) {
  console.error('usage: server.mjs <data-dir containing tour.json> [--port N] [--worktree <dir>] [--open]');
  process.exit(2);
}
const worktree = path.resolve(wtOpt ?? path.join(dataDir, 'worktree'));
const token = crypto.randomBytes(16).toString('hex');
const statePath = path.join(dataDir, 'state.json');

function tokenOk(t) {
  const a = Buffer.from(String(t ?? '')), b = Buffer.from(token);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}
const cookieToken = (req) => /(?:^|;\s*)tour=([0-9a-f]+)/.exec(req.headers.cookie ?? '')?.[1];

function send(res, code, body, type = 'application/json; charset=utf-8', extra = {}) {
  res.writeHead(code, { 'content-type': type, 'cache-control': 'no-store', 'x-content-type-options': 'nosniff', ...extra });
  res.end(body);
}
const fail = (res, code, msg) => send(res, code, JSON.stringify({ error: msg }));
const sendFile = (res, file, type) => send(res, 200, fs.readFileSync(file), type);

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = []; let n = 0;
    req.on('data', (c) => { n += c.length; if (n > MAX_BODY) { reject(new Error('too large')); req.destroy(); } else chunks.push(c); });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

// A repo-relative file path inside the worktree, or null (absolute, '..', NUL, or a symlink leading outside).
function worktreeFile(rel) {
  if (!rel || rel.includes('\0') || path.isAbsolute(rel) || rel.split(/[\\/]/).includes('..')) return null;
  try {
    const root = fs.realpathSync(worktree), real = fs.realpathSync(path.join(root, rel));
    return real.startsWith(root + path.sep) && fs.statSync(real).isFile() ? real : null;
  } catch { return null; }
}

async function api(req, res, url) {
  const route = `${req.method} ${url.pathname}`;
  if (route === 'GET /api/tour') return sendFile(res, path.join(dataDir, 'tour.json'), 'application/json');
  if (route === 'GET /api/atoms') {
    const f = path.join(dataDir, 'atoms.json');
    return fs.existsSync(f) ? sendFile(res, f, 'application/json') : send(res, 200, '{"atoms":[]}');
  }
  if (route === 'GET /api/state') return fs.existsSync(statePath) ? sendFile(res, statePath, 'application/json') : send(res, 200, '{}');
  if (route === 'PUT /api/state') {
    let state;
    try { state = JSON.parse(await readBody(req)); } catch { return fail(res, 400, 'body must be JSON (max 1 MB)'); }
    if (!state || typeof state !== 'object' || Array.isArray(state)) return fail(res, 400, 'state must be a JSON object');
    fs.writeFileSync(statePath + '.tmp', JSON.stringify(state));
    fs.renameSync(statePath + '.tmp', statePath);
    return send(res, 200, '{"ok":true}');
  }
  if (route === 'GET /api/file') {
    const file = worktreeFile(url.searchParams.get('path'));
    if (!file) return fail(res, 404, 'no such file in the worktree');
    if (fs.statSync(file).size > MAX_FILE) return fail(res, 413, 'file too large');
    return sendFile(res, file, 'text/plain; charset=utf-8');
  }
  return fail(res, 404, 'not found');
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://x');
    const host = req.headers.host ?? '';
    const p = server.address().port;
    if (host !== `127.0.0.1:${p}` && host !== `localhost:${p}`) return fail(res, 403, 'bad host');
    if (req.method === 'GET' && url.pathname === '/' && tokenOk(url.searchParams.get('token'))) {
      return send(res, 302, '', 'text/plain', { location: '/', 'set-cookie': `tour=${token}; HttpOnly; SameSite=Strict; Path=/` });
    }
    if (!tokenOk(req.headers['x-tour-token'] ?? cookieToken(req))) return fail(res, 403, 'missing or wrong token');
    if (url.pathname.startsWith('/api/')) return await api(req, res, url);
    const name = STATIC[url.pathname];
    if (req.method === 'GET' && name) return sendFile(res, path.join(uiDir, name), TYPES[path.extname(name)]);
    return fail(res, 404, 'not found');
  } catch {
    return fail(res, 500, 'server error');
  }
});

server.listen(port, '127.0.0.1', () => {
  const url = `http://127.0.0.1:${server.address().port}/?token=${token}`;
  console.log(url);
  if (openBrowser) {
    const cmd = process.platform === 'darwin' ? 'open' : 'xdg-open';
    spawn(cmd, [url], { stdio: 'ignore', detached: true }).on('error', () => {}).unref();
  }
});

// tour server: tour UI backend. Reads the tour, keeps state.json, and is the only thing that posts comments (bin/tour-post), per click. Node >= 18 stdlib, no dependencies.
// Usage: node server.mjs <data-dir> [--port N] [--worktree <dir>] [--open]
// <data-dir> holds tour.json, atoms.json, state.json (created on first PUT) and worktree/ (detached checkout at the head SHA).
// Binds 127.0.0.1 only (random free port unless --port); every request needs the per-run token (URL ?token=, then a cookie).
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawn, execFile } from 'node:child_process';
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
const postBin = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'bin', 'tour-post');
const postedMem = new Map(); // draft id -> posted, kept in memory too: a failed state.json write must not allow a second post
const claudeBin = process.env.TOUR_CLAUDE_BIN || 'claude'; // the CLI login is used: no API key; the override exists for tests
const chatDir = path.join(dataDir, 'chat');
const READ_ONLY_TOOLS = 'Read,Grep,Glob'; // the chat can look at the code, never change it or run commands
const chatting = new Set(); // chapter ids with a chat turn in flight
const posting = new Set(); // draft ids with a post in flight: a double click never posts twice

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

// {} when there is no state.json yet; a state.json that cannot be parsed throws (a PUT must not overwrite it and drop note ids)
const readState = () => (fs.existsSync(statePath) ? JSON.parse(fs.readFileSync(statePath, 'utf8')) : {});
const writeState = (state) => { fs.writeFileSync(statePath + '.tmp', JSON.stringify(state)); fs.renameSync(statePath + '.tmp', statePath); };
const readAtoms = () => { try { const a = JSON.parse(fs.readFileSync(path.join(dataDir, 'atoms.json'), 'utf8')); return Array.isArray(a) ? a : a.atoms ?? []; } catch { return []; } };
const isLine = (n) => Number.isInteger(n) && n > 0;

// A draft -> tour-post arguments, derived from atoms.json (paths) and checked against the atom's ranges (lines).
// kind add: new_line inside the atom's new range. del: old_line inside its old range. ctx: both lines (unchanged line near the atom).
function postArgs(d, atom) {
  if (!atom || !atom.old || !atom.new) return 'this atom has no lines to comment on';
  const within = (r, n) => isLine(n) && r.count > 0 && n >= r.start && n <= r.start + r.count - 1;
  if (d.kind === 'add') { if (!within(atom.new, d.new_line)) return 'new_line is outside the atom'; return ['--new-line', d.new_line]; }
  if (d.kind === 'del') { if (!within(atom.old, d.old_line)) return 'old_line is outside the atom'; return ['--old-line', d.old_line]; }
  if (d.kind === 'ctx') { // the UI shows 3 unchanged lines either side: same window, and the old/new offset before or after the hunk
    if (!isLine(d.old_line) || !isLine(d.new_line)) return 'a context line needs old_line and new_line';
    const first = (r) => (r.count ? r.start : r.start + 1), last = (r) => (r.count ? r.start + r.count - 1 : r.start);
    const near = (r, n) => n >= first(r) - 3 && n <= last(r) + 3;
    const offsets = [first(atom.old) - first(atom.new), last(atom.old) - last(atom.new)];
    if (!near(atom.new, d.new_line) || !near(atom.old, d.old_line) || !offsets.includes(d.old_line - d.new_line)) return 'the context line does not belong to the atom';
    return ['--old-line', d.old_line, '--new-line', d.new_line];
  }
  return 'kind must be add, del or ctx';
}

// Existing posted drafts always survive a state PUT: a stale browser copy must not drop a note id (and so allow a second post).
function keepPosted(old, next) {
  for (const [id, d] of Object.entries(old.drafts ?? {})) if (d?.posted) { next.drafts = { ...(next.drafts ?? {}), [id]: d }; }
  return next;
}

async function postComment(res, body) {
  let id;
  try { id = JSON.parse(body).id; } catch { return fail(res, 400, 'body must be JSON {"id": "<draft id>"}'); }
  let state; try { state = readState(); } catch { return fail(res, 500, 'state.json is unreadable: fix or remove it'); }
  const d = state.drafts?.[id];
  if (!d) return fail(res, 404, 'no such draft: save it first');
  const done = d.posted ?? postedMem.get(id);
  if (done) return fail(res, 409, `already posted (note ${done.id})`);
  if (posting.has(id)) return fail(res, 409, 'a post for this draft is already in flight');
  const atom = readAtoms().find((a) => a.id === d.atom);
  const extra = postArgs(d, atom);
  if (typeof extra === 'string') return fail(res, 400, extra);
  if (typeof atom.file !== 'string' || !atom.file) return fail(res, 400, 'the atom has no file');
  if (typeof d.body !== 'string' || !d.body.trim()) return fail(res, 400, 'the comment is empty');
  posting.add(id);
  const child = execFile(postBin, [dataDir, '--path', atom.file, '--old-path', atom.old_file ?? atom.file, ...extra.map(String), '--body-file', '-'],
    { maxBuffer: 1 << 20 }, (err, stdout, stderr) => {
      posting.delete(id);
      if (err) return send(res, 502, JSON.stringify({ error: (stderr || stdout || String(err.message)).trim() }));
      let note; try { note = JSON.parse(stdout); } catch { return fail(res, 502, 'unexpected tour-post output: ' + stdout.trim()); }
      postedMem.set(id, { id: note.id });
      try {
        const cur = readState(); // re-read: the browser may have saved meanwhile
        cur.drafts = { ...(cur.drafts ?? {}), [id]: { ...(cur.drafts?.[id] ?? d), posted: { id: note.id, url: note.url, inline: note.inline !== false } } };
        writeState(cur);
        send(res, 200, JSON.stringify({ ok: true, draft: cur.drafts[id] }));
      } catch (e) { fail(res, 500, `posted as note ${note.id} (${note.url}) but state.json could not be saved: ${e.message}`); }
    });
  child.stdin.on('error', () => {}); // tour-post may exit before reading the body; its exit code reports the failure
  child.stdin.end(d.body);
}

// --- chat: one `claude -p --resume` session per chapter, read-only tools, cwd = the MR worktree
const chapterById = (id) => {
  try {
    const t = JSON.parse(fs.readFileSync(path.join(dataDir, 'tour.json'), 'utf8'));
    return [...(t.chapters ?? []), ...(t.mechanical?.atoms?.length ? [{ id: 'mechanical', title: 'Mechanical changes', blocks: [{ what: t.mechanical.note ?? '', atoms: t.mechanical.atoms }] }] : [])].find((c) => c.id === id);
  } catch { return null; }
};
const chatFile = (id) => path.join(chatDir, id.replace(/[^A-Za-z0-9_-]/g, '_') + '.json');
const readChat = (id) => { try { return JSON.parse(fs.readFileSync(chatFile(id), 'utf8')); } catch { return { session: null, messages: [] }; } };
const writeChat = (id, chat) => { fs.mkdirSync(chatDir, { recursive: true }); fs.writeFileSync(chatFile(id) + '.tmp', JSON.stringify(chat)); fs.renameSync(chatFile(id) + '.tmp', chatFile(id)); };

// The first message of a chapter carries the chapter and its atoms; later turns resume the session and send the question alone.
function chapterContext(ch) {
  const byId = new Map(readAtoms().map((a) => [a.id, a]));
  const parts = [`You are helping a reviewer understand one chapter of a merge request tour. Answer questions about this chapter; the checkout in your working directory is the MR head and is read-only to you.`, `Chapter: ${ch.title}${ch.order_reason ? ` (${ch.order_reason})` : ''}`];
  for (const b of ch.blocks) {
    parts.push(`- ${b.what}${b.why ? ` Why: ${b.why}` : ''}`);
    for (const id of b.atoms ?? []) { const a = byId.get(id); if (a) parts.push(`  ${a.file} @@ -${a.old?.start ?? ''} +${a.new?.start ?? ''}\n${(a.lines ?? []).join('\n')}`.slice(0, 4000)); }
  }
  return parts.join('\n');
}

// Streams SSE: {type:'text',text} | {type:'error',error} | {type:'done'}. An error is the CLI's own output, verbatim; nothing is retried.
async function chat(req, res, body) {
  let msg;
  try { msg = JSON.parse(body); } catch { return fail(res, 400, 'body must be JSON {"chapter": "<id>", "message": "<text>"}'); }
  const ch = typeof msg.chapter === 'string' && chapterById(msg.chapter);
  if (!ch) return fail(res, 404, 'no such chapter');
  if (typeof msg.message !== 'string' || !msg.message.trim()) return fail(res, 400, 'the message is empty');
  if (chatting.has(ch.id)) return fail(res, 409, 'a reply for this chapter is already streaming');
  const chatState = readChat(ch.id);
  const session = /^[0-9A-Za-z-]{8,64}$/.test(chatState.session ?? '') ? chatState.session : null;
  const cargs = ['-p', '--output-format', 'stream-json', '--verbose', '--include-partial-messages', '--tools', READ_ONLY_TOOLS, '--allowedTools', READ_ONLY_TOOLS, ...(session ? ['--resume', session] : [])];
  const prior = chatState.session; // a failed turn may not have seen the chapter context: keep only a session an earlier success stored
  chatting.add(ch.id);
  res.writeHead(200, { 'content-type': 'text/event-stream; charset=utf-8', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff' });
  const emit = (o) => { if (!res.writableEnded) res.write(`data: ${JSON.stringify(o)}\n\n`); };
  let reply = '', gotDelta = false, errText = '', stderr = '', buf = '', finished = false;
  const child = spawn(claudeBin, cargs, { cwd: fs.existsSync(worktree) ? worktree : dataDir, stdio: ['pipe', 'pipe', 'pipe'] });
  const text = (t) => { reply += t; emit({ type: 'text', text: t }); };
  const line = (l) => {
    let e; try { e = JSON.parse(l); } catch { return; }
    if (typeof e.session_id === 'string' && /^[0-9A-Za-z-]{8,64}$/.test(e.session_id)) chatState.session = e.session_id;
    if (e.type === 'stream_event' && e.event?.delta?.type === 'text_delta') { gotDelta = true; text(e.event.delta.text); }
    else if (e.type === 'result') {
      if (e.is_error) errText = String(e.result ?? 'the claude CLI reported an error');
      else if (!gotDelta && typeof e.result === 'string') text(e.result);
    }
  };
  child.stdout.on('data', (c) => { buf += c; let i; while ((i = buf.indexOf('\n')) >= 0) { line(buf.slice(0, i)); buf = buf.slice(i + 1); } });
  child.stderr.on('data', (c) => { if (stderr.length < 8192) stderr += c; });
  const finish = (code, spawnErr) => {
    if (finished) return; finished = true;
    chatting.delete(ch.id);
    if (buf.trim()) line(buf);
    const err = spawnErr ? `could not run ${claudeBin}: ${spawnErr.message}` : errText || (code ? (stderr.trim() || `${claudeBin} exited with code ${code}`) : '');
    const messages = [...chatState.messages, { role: 'user', text: msg.message }, ...(reply ? [{ role: 'assistant', text: reply }] : []), ...(err ? [{ role: 'error', text: err }] : [])];
    try { writeChat(ch.id, { session: (err ? prior : chatState.session) ?? null, messages }); } catch {}
    emit(err ? { type: 'error', error: err } : { type: 'done' });
    res.end();
  };
  child.on('error', (e) => finish(null, e));
  child.on('close', (code) => finish(code));
  res.on('close', () => { if (!finished) child.kill(); });
  child.stdin.on('error', () => {});
  child.stdin.end(session ? msg.message : `${chapterContext(ch)}\n\nQuestion: ${msg.message}`);
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
    let old; try { old = readState(); } catch { return fail(res, 500, 'state.json is unreadable: fix or remove it'); }
    writeState(keepPosted(old, state));
    return send(res, 200, '{"ok":true}');
  }
  if (route === 'POST /api/comment') return postComment(res, await readBody(req).catch(() => ''));
  if (route === 'GET /api/chat') {
    const id = url.searchParams.get('chapter');
    if (!id || !chapterById(id)) return fail(res, 404, 'no such chapter');
    return send(res, 200, JSON.stringify({ messages: readChat(id).messages }));
  }
  if (route === 'POST /api/chat') return chat(req, res, await readBody(req).catch(() => ''));
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

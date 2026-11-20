// tour UI: vanilla JS, no build step, read-only. Contract: references/tour-schema.md. Tour data is only ever set via
// textContent (never innerHTML); the one innerHTML is highlight.js output, which escapes its input.
const CTX = 3; // real file lines shown around each atom
const CDN = {
  hljs: 'https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js',
  mermaid: 'https://cdnjs.cloudflare.com/ajax/libs/mermaid/10.9.1/mermaid.min.js',
};
const LANG = { js: 'javascript', mjs: 'javascript', ts: 'typescript', php: 'php', py: 'python', rb: 'ruby', go: 'go', rs: 'rust',
  java: 'java', kt: 'kotlin', sh: 'bash', json: 'json', yml: 'yaml', yaml: 'yaml', css: 'css', html: 'xml', xml: 'xml', md: 'markdown', sql: 'sql' };

const h = (tag, props, ...kids) => {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(props ?? {})) {
    if (k === 'class') el.className = v; else if (k.startsWith('on')) el.addEventListener(k.slice(2), v); else el.setAttribute(k, v);
  }
  el.append(...kids.flat().filter((c) => c != null && c !== false));
  return el;
};
const $main = document.getElementById('main'), $bar = document.getElementById('bar');
const show = (el, ...kids) => el.replaceChildren(...kids.flat().filter((c) => c != null && c !== false));

const getJSON = async (url) => { const r = await fetch(url); if (!r.ok) throw new Error(`${url}: ${r.status}`); return r.json(); };
const loadScript = (src) => new Promise((ok, no) => { const s = h('script', { src }); s.onload = ok; s.onerror = no; document.head.append(s); });

let tour, atoms = {}, S, saveTimer;
const files = new Map();
const save = () => { clearTimeout(saveTimer); saveTimer = setTimeout(flush, 300); };
const flush = () => fetch('/api/state', { method: 'PUT', body: JSON.stringify(S), keepalive: true }).catch(() => {});
addEventListener('pagehide', flush);

const chapters = () => [...tour.chapters, ...(tour.mechanical?.atoms?.length
  ? [{ id: 'mechanical', title: 'Mechanical', order_reason: tour.mechanical.note, blocks: [{ atoms: tour.mechanical.atoms, what: tour.mechanical.note, why: '', why_source: 'code', impact: [], watch: [] }] }] : [])];
const key = (ch, i) => `${ch.id}/${i}`;
const doneCount = (ch) => ch.blocks.filter((_, i) => S.understood[key(ch, i)]).length;

async function fileLines(path) {
  if (!files.has(path)) {
    files.set(path, fetch('/api/file?path=' + encodeURIComponent(path)).then((r) => (r.ok ? r.text() : null)).then((t) => (t == null ? null : t.split('\n'))));
  }
  return files.get(path);
}

// --- syntax highlighting (optional: plain text without highlight.js)
function code(text, file) {
  const span = h('span', { class: 'cell-text' });
  const lang = LANG[file.split('.').pop()];
  if (window.hljs && lang) { try { span.innerHTML = window.hljs.highlight(text, { language: lang, ignoreIllegals: true }).value; return span; } catch { /* fall through */ } }
  span.textContent = text;
  return span;
}

// --- atom + real surrounding context -> rows {k: ctx|add|del, o, n, t}
function atomRows(a, lines) {
  const oldFirst = a.old.count ? a.old.start : a.old.start + 1;
  const newFirst = a.new.count ? a.new.start : a.new.start + 1;
  const ctx = (from, to, delta) => { const r = []; for (let n = from; n <= to; n++) if (lines && lines[n - 1] !== undefined) r.push({ k: 'ctx', o: n + delta, n, t: lines[n - 1] }); return r; };
  const dels = [], adds = [];
  let o = oldFirst, n = newFirst;
  for (const l of a.lines ?? []) {
    if (l.startsWith('-')) dels.push({ k: 'del', o: o++, t: l.slice(1) });
    else if (l.startsWith('+')) adds.push({ k: 'add', n: n++, t: l.slice(1) });
  }
  const end = a.new.count ? a.new.start + a.new.count - 1 : a.new.start;
  const before = ctx(Math.max(1, newFirst - CTX), newFirst - 1, oldFirst - newFirst);
  const after = ctx(end + 1, Math.min(lines ? lines.length : 0, end + CTX), (a.old.count ? a.old.start + a.old.count - 1 : a.old.start) - end);
  return { before, dels, adds, after };
}

function atomView(a) {
  const box = h('div', { class: 'code', id: 'atom-' + a.id }, h('div', { class: 'file' }, h('a', { href: '#/f/' + encodeURIComponent(a.file) }, a.file),
    h('span', { class: 'muted' }, ` ${a.id} · -${a.old.start},${a.old.count} +${a.new.start},${a.new.count}${a.kind ? ' · ' + a.kind : ''}`)));
  fileLines(a.file).then((lines) => {
    const { before, dels, adds, after } = atomRows(a, lines);
    const num = (v) => h('span', { class: 'n' }, v ?? '');
    if (S.mode === 'split') {
      const pairs = []; for (let i = 0; i < Math.max(dels.length, adds.length); i++) pairs.push([dels[i], adds[i]]);
      const cell = (r) => h('span', { class: 'cell ' + (r?.k ?? '') }, r ? code(r.t, a.file) : '');
      for (const r of before) box.append(h('div', { class: 'row split ctx' }, num(r.o), cell(r), num(r.n), cell(r)));
      for (const [d, p] of pairs) box.append(h('div', { class: 'row split' }, num(d?.o), cell(d), num(p?.n), cell(p)));
      for (const r of after) box.append(h('div', { class: 'row split ctx' }, num(r.o), cell(r), num(r.n), cell(r)));
    } else {
      for (const r of [...before, ...dels, ...adds, ...after]) box.append(h('div', { class: 'row ' + r.k }, num(r.k === 'add' ? r.n : r.o), h('span', { class: 'cell' }, (r.k === 'add' ? '+' : r.k === 'del' ? '-' : ' '), code(r.t, a.file))));
    }
    if (!dels.length && !adds.length) box.append(h('div', { class: 'row ctx' }, num(), h('span', {}, `(${a.kind ?? 'no line changes'})`)));
  });
  return box;
}

// --- views
function bar() {
  show($bar, 
    h('a', { href: '#/', class: 'grow' }, 'Tour · ', tour.mr.title),
    h('button', { 'aria-pressed': S.mode === 'split', title: 'unified / side by side', onclick: () => { S.mode = S.mode === 'split' ? 'unified' : 'split'; save(); route(true); } }, 'side by side'),
    h('button', { title: 'toggle theme', onclick: () => { S.theme = document.documentElement.dataset.theme === 'dark' || (!document.documentElement.dataset.theme && matchMedia('(prefers-color-scheme: dark)').matches) ? 'light' : 'dark'; theme(); save(); } }, 'theme'));
}
const theme = () => { if (S.theme) document.documentElement.dataset.theme = S.theme; };

function landing() {
  const { mr, summary } = tour, all = chapters();
  const total = all.reduce((n, c) => n + c.blocks.length, 0), done = all.reduce((n, c) => n + doneCount(c), 0);
  const graph = tour.graph?.mermaid && h('pre', { class: 'mermaid' }, tour.graph.mermaid);
  show($main, 
    h('h1', {}, mr.title),
    h('p', { class: 'muted' }, h('a', { href: mr.url, target: '_blank', rel: 'noopener noreferrer' }, `${mr.project} #${mr.iid}`), ` · head ${mr.head_sha.slice(0, 8)}`,
      mr.ticket && ` · ${mr.ticket.id}: ${mr.ticket.summary}`),
    h('div', { class: 'card' }, h('p', {}, h('b', {}, 'Intent. '), summary.intent), h('p', {}, h('b', {}, 'Approach. '), summary.approach),
      h('p', {}, h('b', {}, 'Risk: '), h('span', { class: 'risk-' + summary.risk }, summary.risk)), h('ul', { class: 'plain' }, summary.risk_reasons.map((r) => h('li', {}, '• ' + r)))),
    tour.drift?.length && h('div', { class: 'card' }, h('b', {}, 'Drift flags'), h('ul', { class: 'plain' }, tour.drift.map((d) => h('li', {}, h('span', { class: 'badge warn' }, d.kind), ' ' + d.detail)))),
    graph && h('div', { class: 'card' }, h('b', {}, 'Architecture'), graph),
    h('h2', {}, `Chapters (${done}/${total} understood)`),
    all.map((c, i) => h('div', { class: 'chapter-row' }, h('span', { class: 'muted' }, i + 1),
      h('a', { href: '#/c/' + c.id }, c.title), h('div', { class: 'bar', title: `${doneCount(c)}/${c.blocks.length}` }, h('i', { style: `width:${(100 * doneCount(c)) / c.blocks.length}%` })))),
    S.pos && all.some((c) => c.id === S.pos.chapter) && h('p', {}, h('a', { href: '#/c/' + S.pos.chapter }, 'Continue where you left off')));
  if (graph) loadScript(CDN.mermaid).then(() => { window.mermaid.initialize({ startOnLoad: false, theme: matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default' }); return window.mermaid.run({ nodes: [graph] }); }).catch(() => {});
}

let cur = 0, curCh = null;
function chapterView(id) {
  const all = chapters(), idx = all.findIndex((c) => c.id === id);
  if (idx < 0) return (location.hash = '#/');
  const ch = curCh = all[idx];
  cur = S.pos?.chapter === id ? Math.min(S.pos.block ?? 0, ch.blocks.length - 1) : 0;
  const blocks = ch.blocks.map((b, i) => {
    const el = h('section', { class: 'block', 'data-i': i },
      h('div', { class: 'narr' },
        h('p', { class: 'what' }, h('b', {}, b.what)),
        b.why && h('p', {}, b.why, ' ', h('span', { class: 'badge ' + (b.why_source === 'unclear' ? 'warn' : '') }, b.why_source === 'unclear' ? 'unclear why: ask the author' : 'source: ' + b.why_source)),
        b.impact.length > 0 && h('ul', { class: 'plain' }, b.impact.map((m) => h('li', {}, h('a', { href: '#/f/' + encodeURIComponent(m.file) }, m.symbol), ' ' + m.note))),
        b.watch.length > 0 && h('ul', { class: 'plain' }, b.watch.map((w) => h('li', { class: 'warn' }, '⚠ ' + w))),
        h('button', { onclick: () => { cur = i; mark(); } }, 'understood (u)')),
      h('div', { class: 'ctx' }, b.atoms.map((aid) => (atoms[aid] ? atomView(atoms[aid]) : h('p', { class: 'bad' }, 'atom ' + aid + ' missing from atoms.json')))));
    return el;
  });
  const nav = (c, label) => (c ? h('a', { href: '#/c/' + c.id }, label) : h('span', { class: 'muted' }, label));
  const body = ch.id === 'mechanical' ? h('details', {}, h('summary', {}, 'Show mechanical changes'), blocks) : blocks;
  show($main, h('p', {}, h('a', { href: '#/' }, 'Overview'), ' · ', nav(all[idx - 1], '← previous (p)'), ' · ', nav(all[idx + 1], 'next (n) →')),
    h('h1', {}, `${idx + 1}. ${ch.title}`), h('p', { class: 'muted' }, ch.order_reason), body);
  paint();
}
function paint(scroll = false) {
  document.querySelectorAll('.block').forEach((el) => {
    const i = Number(el.dataset.i);
    el.classList.toggle('cur', i === cur); el.classList.toggle('done', !!S.understood[key(curCh, i)]);
    if (scroll && i === cur) el.scrollIntoView({ block: 'nearest' });
  });
  S.pos = { chapter: curCh.id, block: cur }; save();
}
function mark() { const k = key(curCh, cur); if (S.understood[k]) delete S.understood[k]; else S.understood[k] = true; paint(); }

async function fileView(path) {
  const lines = await fileLines(path);
  show($main, h('p', {}, h('a', { onclick: () => history.back() }, '← back'), ` · ${path} @ ${tour.mr.head_sha.slice(0, 8)}`),
    lines ? h('div', { class: 'code' }, lines.map((t, i) => h('div', { class: 'row' }, h('span', { class: 'n' }, i + 1), h('span', { class: 'cell' }, code(t, path))))) : h('p', { class: 'bad' }, 'File not available in the worktree.'));
}

function route(keepScroll) {
  bar(); curCh = null;
  const [, kind, ...rest] = location.hash.split('/'), arg = decodeURIComponent(rest.join('/'));
  if (kind === 'c') chapterView(arg); else if (kind === 'f') fileView(arg); else landing();
  if (keepScroll !== true) scrollTo(0, 0);
}

addEventListener('keydown', (e) => {
  if (e.ctrlKey || e.metaKey || e.altKey || /^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName) || !curCh) return;
  const all = chapters(), idx = all.indexOf(curCh);
  if (e.key === 'j') { cur = Math.min(cur + 1, curCh.blocks.length - 1); paint(true); }
  else if (e.key === 'k') { cur = Math.max(cur - 1, 0); paint(true); }
  else if (e.key === 'u') mark();
  else if (e.key === 'n' && all[idx + 1]) location.hash = '#/c/' + all[idx + 1].id;
  else if (e.key === 'p' && all[idx - 1]) location.hash = '#/c/' + all[idx - 1].id;
});
addEventListener('hashchange', () => route());

try {
  let raw;
  [tour, raw, S] = await Promise.all([getJSON('/api/tour'), getJSON('/api/atoms'), getJSON('/api/state')]);
  atoms = Object.fromEntries((Array.isArray(raw) ? raw : raw.atoms ?? []).map((a) => [a.id, a]));
  S = { understood: {}, mode: 'unified', ...S }; theme(); route();
  loadScript(CDN.hljs).then(() => route(true)).catch(() => {}); // highlight when it arrives; the tour reads fine without it
} catch (e) {
  show($main, h('p', { class: 'bad' }, 'Could not load the tour: ' + e.message));
}

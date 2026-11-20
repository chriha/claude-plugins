// tour UI ("cockpit"): vanilla JS, no build step. Top bar, sidebar (chapters, files, signals), main pane (overview, chapter or file),
// inspector (context, checks, ask) and status bar. Optional layers (deep, active, arch, rules, drift) render only when listed in tour.layers.
// Nothing is posted without a click on "Post". Contract: references/tour-schema.md. Tour data is only ever set via textContent (never
// innerHTML); the one innerHTML is highlight.js output, which escapes its input.
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
    if (v == null || v === false) continue;
    if (k === 'class') el.className = v; else if (k.startsWith('on')) el.addEventListener(k.slice(2), v); else el.setAttribute(k, v === true ? '' : v);
  }
  el.append(...kids.flat(Infinity).filter((c) => c != null && c !== false));
  return el;
};
const show = (el, ...kids) => el && el.replaceChildren(...kids.flat(Infinity).filter((c) => c != null && c !== false));
const $ = (id) => document.getElementById(id);
const $bar = $('bar'), $side = $('side'), $main = $('main'), $insp = $('insp'), $status = $('status');
const getJSON = async (url) => { const r = await fetch(url); if (!r.ok) throw new Error(`${url}: ${r.status}`); return r.json(); };
const loadScript = (src) => new Promise((ok, no) => { const s = h('script', { src }); s.onload = ok; s.onerror = no; document.head.append(s); });
const cap = (s) => (s ? s[0].toUpperCase() + s.slice(1) : '');
const base = (f) => f.split('/').pop();
const dirOf = (f) => f.slice(0, f.lastIndexOf('/') + 1);
const plural = (n, w) => `${n} ${w}${n === 1 ? '' : 's'}`;
const fileHref = (f) => '#/f/' + encodeURIComponent(f);

// --- data and state. S is state.json: understood, checks, predictions, drafts, pos, mode, theme, tab. ui is this page only.
let tour, atoms = {}, S, saveTimer, CH = [], READ = [];
const ui = { view: 'overview', arg: null, palette: null, palSel: 0, drawer: false, editing: null, focusDraft: null };
let cur = 0, curCh = null;
const fileByPath = new Map(); // path -> [{id, ch, i}] in reading order: a file can be split across chapters
const save = () => { clearTimeout(saveTimer); saveTimer = setTimeout(flush, 300); };
const flush = () => fetch('/api/state', { method: 'PUT', body: JSON.stringify(S), keepalive: true }).catch(() => {});
addEventListener('pagehide', flush);

const has = (layer) => !!tour.layers?.includes(layer);
const key = (ch, i) => `${ch.id}/${i}`;
const doneCount = (ch) => ch.blocks.filter((_, i) => S.understood[key(ch, i)]).length;
const totals = () => { let t = 0, d = 0; for (const c of READ) { t += c.blocks.length; d += doneCount(c); } return { t, d, pct: t ? (100 * d) / t : 0 }; };
const label = (ch, i) => (ch.mechanical ? 'M' : `${ch.n}.${i + 1}`);
const isActive = (ch) => !ch.mechanical && has('active') && typeof ch.intent === 'string';
const gated = (ch) => isActive(ch) && !S.predictions[ch.id]?.revealed;
const lineStat = (ids) => { let add = 0, del = 0; for (const id of ids) for (const l of atoms[id]?.lines ?? []) { if (l[0] === '+') add++; else if (l[0] === '-') del++; } return { add, del }; };
const ref = (p) => (tour.mr.platform === 'github' ? '#' : '!') + p;

function buildIndex() {
  CH = [...tour.chapters.map((c, i) => ({ ...c, n: i + 1 })), ...(tour.mechanical?.atoms?.length
    ? [{ id: 'mechanical', mechanical: true, title: 'Mechanical', order_reason: tour.mechanical.note, blocks: [{ atoms: tour.mechanical.atoms, what: tour.mechanical.note, why: '', why_source: 'code', impact: [], watch: [] }] }] : [])];
  READ = CH.filter((c) => !c.mechanical);
  for (const ch of CH) ch.blocks.forEach((b, i) => b.atoms.forEach((id) => { const f = atoms[id]?.file; if (f) { if (!fileByPath.has(f)) fileByPath.set(f, []); fileByPath.get(f).push({ id, ch, i }); } }));
}

// Active review: an atom counts as anticipated when the reviewer's prediction names its file path, file name or file stem.
const anticipated = (a, text) => { const t = text.toLowerCase(), f = a.file.toLowerCase(), name = f.split('/').pop(), stem = name.replace(/\.[^.]*$/, ''); return t.includes(f) || t.includes(name) || (stem.length > 2 && t.includes(stem)); };
const surprise = (ch, a) => { const p = S.predictions[ch.id]; return !!(p?.revealed && p.text.trim() && !anticipated(a, p.text)); };

// --- files: fetched once per path; `lines` holds the resolved ones so a render can stay synchronous
const files = new Map(), lines = new Map();
function fileLines(path) {
  if (!files.has(path)) {
    files.set(path, fetch('/api/file?path=' + encodeURIComponent(path)).then((r) => (r.ok ? r.text() : null)).then((t) => (t == null ? null : t.split('\n')))
      .catch(() => null).then((l) => { lines.set(path, l); return l; }));
  }
  return files.get(path);
}
const preload = (paths) => Promise.all([...new Set(paths)].map(fileLines));

// --- syntax highlighting (optional: plain text without highlight.js)
function code(text, file, lang) {
  const span = h('span', { class: 'tx' });
  lang ??= LANG[file.split('.').pop()];
  if (window.hljs && lang) { try { span.innerHTML = window.hljs.highlight(text, { language: lang, ignoreIllegals: true }).value; return span; } catch { /* fall through */ } }
  span.textContent = text;
  return span;
}

// --- atom + real surrounding context -> rows {k: ctx|add|del, o, n, t}
function atomRows(a, lns) {
  const oldFirst = a.old.count ? a.old.start : a.old.start + 1;
  const newFirst = a.new.count ? a.new.start : a.new.start + 1;
  const ctx = (from, to, delta) => { const r = []; for (let n = from; n <= to; n++) if (lns && lns[n - 1] !== undefined) r.push({ k: 'ctx', o: n + delta, n, t: lns[n - 1] }); return r; };
  const dels = [], adds = [];
  let o = oldFirst, n = newFirst;
  for (const l of a.lines ?? []) {
    if (l.startsWith('-')) dels.push({ k: 'del', o: o++, t: l.slice(1) });
    else if (l.startsWith('+')) adds.push({ k: 'add', n: n++, t: l.slice(1) });
  }
  const end = a.new.count ? a.new.start + a.new.count - 1 : a.new.start;
  const before = ctx(Math.max(1, newFirst - CTX), newFirst - 1, oldFirst - newFirst);
  const after = ctx(end + 1, Math.min(lns ? lns.length : 0, end + CTX), (a.old.count ? a.old.start + a.old.count - 1 : a.old.start) - end);
  return { before, dels, adds, after };
}

// --- comment drafts (state.json: drafts{id: {id, atom, file, kind add|del|ctx, old_line, new_line, body, posted?}}); posting is a server call per click
const draftId = (a, r) => `${a.id}:${r.k}:${r.k === 'add' ? '' : r.o}:${r.k === 'del' ? '' : r.n}`;
const draftOf = (a, r) => S.drafts[draftId(a, r)];
const draftList = () => Object.values(S.drafts);
const unposted = () => draftList().filter((d) => !d.posted && d.body.trim());
function startDraft(a, r) {
  const id = draftId(a, r);
  for (const d of draftList()) if (d.id !== id && !d.posted && !d.body.trim()) delete S.drafts[d.id]; // one open empty draft at a time
  S.drafts[id] ??= { id, atom: a.id, file: a.file, kind: r.k, old_line: r.k === 'add' ? null : r.o, new_line: r.k === 'del' ? null : r.n, body: '' };
  ui.editing = id; ui.focusDraft = id; save(); render();
}
function discard(d) { delete S.drafts[d.id]; if (ui.editing === d.id) ui.editing = null; save(); render(); }
async function postDraft(d) {
  if (d.posting) return;
  d.error = null; d.posting = true; render();
  const saved = await fetch('/api/state', { method: 'PUT', body: JSON.stringify(S) }).catch(() => null); // the server posts what it has saved
  if (!saved?.ok) { d.error = 'could not save the draft before posting: ' + (saved ? (await saved.text()) : 'no connection'); d.posting = false; render(); return; }
  try {
    const r = await fetch('/api/comment', { method: 'POST', body: JSON.stringify({ id: d.id }) });
    const j = await r.json();
    if (r.ok) { S.drafts[d.id] = j.draft; if (ui.editing === d.id) ui.editing = null; } else d.error = j.error ?? `HTTP ${r.status}`;
  } catch (e) { d.error = String(e.message ?? e); }
  d.posting = false; render();
}
const where = (d) => `${d.kind === 'del' ? 'removed line ' + d.old_line : 'line ' + d.new_line}`;
const noteLink = (d) => ['note ', /^https?:\/\//.test(d.posted.url ?? '') ? h('a', { href: d.posted.url, target: '_blank', rel: 'noopener noreferrer' }, String(d.posted.id)) : String(d.posted.id),
  d.posted.inline === false && h('span', { class: 'warn' }, ' (the forge dropped the position: it is a general note)')];
function draftBox(d, inDrawer) {
  if (d.posted) return h('div', { class: 'dbox' }, h('div', { class: 'dmeta' }, h('span', {}, h('span', { class: 'pill ok' }, 'posted'), ' ', noteLink(d)), inDrawer && h('span', {}, `${d.file} · ${where(d)}`)), h('p', {}, d.body));
  const editing = !inDrawer && (ui.editing === d.id || !d.body.trim());
  const post = h('button', { class: 'btn solid', onclick: () => postDraft(d) }, d.posting ? 'Posting…' : 'Post'); if (d.posting || !d.body.trim()) post.disabled = true;
  let body;
  if (editing) {
    const ta = h('textarea', { rows: '3', id: 'draft-' + d.id, placeholder: 'Comment for the author', 'aria-label': 'Comment' }); ta.value = d.body;
    ta.addEventListener('input', () => { d.body = ta.value; save(); post.disabled = !ta.value.trim(); });
    ta.addEventListener('keydown', (e) => { if ((e.key === 'Enter' && (e.metaKey || e.ctrlKey)) || e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); if (!d.body.trim()) return discard(d); ui.editing = null; render(); } });
    if (ui.focusDraft === d.id) { ui.focusDraft = null; setTimeout(() => ta.focus?.({ preventScroll: true })); }
    body = ta;
  } else body = h('p', {}, d.body);
  return h('div', { class: 'dbox' },
    h('div', { class: 'dmeta' }, h('span', {}, h('span', { class: 'pill' }, 'draft'), ' ', inDrawer ? `${d.file} · ${where(d)}` : where(d)), h('span', {}, 'not posted until you press Post')),
    body,
    h('div', { class: 'dact' }, h('button', { class: 'btn', onclick: () => discard(d) }, 'Discard'),
      inDrawer ? h('button', { class: 'btn', onclick: () => { ui.drawer = false; goAtom(d.atom); } }, 'Show') : editing ? h('button', { class: 'btn', onclick: () => { if (!d.body.trim()) return discard(d); ui.editing = null; render(); } }, 'Save draft') : h('button', { class: 'btn', onclick: () => { ui.editing = d.id; ui.focusDraft = d.id; render(); } }, 'Edit'),
      post),
    d.error && h('pre', { class: 'err' }, d.error));
}

// --- one diff box per atom
function atomView(a, ch) {
  const sur = ch && !ch.mechanical && surprise(ch, a), st = lineStat([a.id]);
  const head = h('div', { class: 'dh' },
    h('a', { class: 'fp', href: fileHref(a.file), title: a.file }, dirOf(a.file), h('b', {}, base(a.file))),
    sur && h('span', { class: 'tag warn', title: 'Your prediction did not name this file' }, 'not predicted'),
    h('span', { class: 'meta' }, `${a.id}${a.old && a.new ? ` · -${a.old.start},${a.old.count} +${a.new.start},${a.new.count}` : ''}${a.kind ? ' · ' + a.kind : ''}${a.old_file && a.old_file !== a.file ? ' · from ' + a.old_file : ''}`),
    h('span', { class: 'dstat' }, h('span', { class: 'p' }, '+' + st.add), h('span', { class: 'm' }, '−' + st.del)));
  if (!a.old || !a.new) return h('div', { class: 'diff' + (sur ? ' np' : '') }, head, h('div', { class: 'dempty' }, `(${a.kind ?? 'no line changes'})`)); // rename, binary, mode and empty atoms have no hunk
  const { before, dels, adds, after } = atomRows(a, lines.get(a.file) ?? null);
  const rows = h('div', { class: 'rows' });
  const num = (v, r, extra = '') => (v == null || !r ? h('span', { class: 'ln ' + extra }, '')
    : h('button', { class: 'ln ' + extra + (draftOf(a, r) ? ' drafted' : ''), title: 'Comment on this line', 'aria-label': `Comment on ${r.k === 'del' ? 'removed ' : ''}line ${v}`, onclick: () => startDraft(a, r) }, v));
  const sign = (r) => (r?.k === 'add' ? '+' : r?.k === 'del' ? '−' : ' ');
  const drafts = (...rs) => rs.filter(Boolean).map((r) => draftOf(a, r)).filter(Boolean).map((d) => h('div', { class: 'dr' }, draftBox(d)));
  if (S.mode === 'split') {
    const cell = (r) => h('span', { class: 'cell ' + (r?.k ?? '') }, r ? code(r.t, a.file) : '');
    const side = (r, v) => [num(v, r, r?.k ?? ''), h('span', { class: 'sg ' + (r?.k ?? '') }, r ? sign(r) : ''), cell(r)];
    for (const r of before) rows.append(h('div', { class: 'dl split ctx' }, side(r, r.o), side(r, r.n)), ...drafts(r));
    for (let i = 0; i < Math.max(dels.length, adds.length); i++) rows.append(h('div', { class: 'dl split' }, side(dels[i], dels[i]?.o), side(adds[i], adds[i]?.n)), ...drafts(dels[i], adds[i]));
    for (const r of after) rows.append(h('div', { class: 'dl split ctx' }, side(r, r.o), side(r, r.n)), ...drafts(r));
  } else {
    for (const r of [...before, ...dels, ...adds, ...after]) {
      rows.append(h('div', { class: 'dl ' + r.k }, num(r.k === 'add' ? null : r.o, r), num(r.k === 'del' ? null : r.n, r), h('span', { class: 'sg' }, sign(r)), h('span', { class: 'cell' }, code(r.t, a.file))), ...drafts(r));
    }
  }
  if (!dels.length && !adds.length) rows.append(h('div', { class: 'dempty' }, `(${a.kind ?? 'no line changes'})`));
  return h('div', { class: 'diff' + (sur ? ' np' : ''), id: 'atom-' + a.id }, head, h('div', { class: 'dbody' }, rows));
}
const atomOrMissing = (id, ch) => (atoms[id] ? atomView(atoms[id], ch) : h('p', { class: 'bad' }, 'atom ' + id + ' missing from atoms.json'));

// --- shared pieces
const SRC = { ticket: () => `from ${tour.mr.ticket?.id ?? 'the ticket'}`, mr: () => 'from the MR text', code: () => 'from the code', unclear: () => 'unclear why: ask the author' };
const srcChip = (b) => h('span', { class: 'src' + (b.why_source === 'unclear' ? ' unclear' : '') }, (SRC[b.why_source] ?? (() => 'source: ' + b.why_source))());
function riskCard() {
  const lv = ['low', 'medium', 'high'], at = lv.indexOf(tour.summary.risk);
  return h('div', { class: 'card' },
    h('div', { class: 'rhead' }, h('p', { class: 'lbl' }, 'Risk'), h('b', { class: 'risk-' + tour.summary.risk, style: 'background:none' }, cap(tour.summary.risk))),
    h('div', { class: 'scale', 'data-level': tour.summary.risk }, lv.map((l, i) => h('i', { class: i <= at ? 'on' : '' }))),
    h('div', { class: 'legend' }, h('span', {}, 'low'), h('span', {}, 'medium'), h('span', {}, 'high')),
    tour.summary.risk_reasons.length > 0 && h('ul', { class: 'plain reasons' }, tour.summary.risk_reasons.map((r) => h('li', {}, r))));
}
const chapterOfAtom = (id) => { for (const ch of CH) { const i = ch.blocks.findIndex((b) => b.atoms.includes(id)); if (i >= 0) return { ch, i }; } return null; };
function driftCard() {
  if (!has('drift') || !tour.drift?.length) return null;
  return h('div', { class: 'card drift' }, h('p', { class: 'lbl' }, 'Signals from the diff'),
    h('ul', { class: 'plain' }, tour.drift.map((d) => { const at = chapterOfAtom(d.atoms?.[0]);
      return h('li', {}, h('span', { class: 'k' }, d.kind.replace(/_/g, ' ')), h('code', {}, d.detail), at && h('a', { href: '#/c/' + at.ch.id, onclick: () => setPos(at.ch, at.i) }, at.ch.mechanical ? 'mechanical' : 'step ' + label(at.ch, at.i))); })));
}
function setPos(ch, i) { S.pos = { chapter: ch.id, block: i }; save(); }
function goAtom(id) { const at = chapterOfAtom(id); if (!at) return; setPos(at.ch, at.i); if (location.hash === '#/c/' + at.ch.id) route(); else location.hash = '#/c/' + at.ch.id; }
function setCur(i, scroll = true) {
  cur = i; setPos(curCh, i); render();
  if (scroll) $('blk-' + i)?.scrollIntoView?.({ block: 'nearest', behavior: 'smooth' });
}
function mark() { const k = key(curCh, cur); if (S.understood[k]) delete S.understood[k]; else S.understood[k] = true; save(); render(); }
const theme = () => { if (S.theme) document.documentElement.dataset.theme = S.theme; };
const dark = () => (document.documentElement.dataset.theme ? document.documentElement.dataset.theme === 'dark' : !!globalThis.matchMedia?.('(prefers-color-scheme: dark)').matches);

// --- top bar, sidebar, status bar
function bar() {
  const { mr, summary } = tour, { t, d, pct } = totals(), n = unposted().length;
  show($bar,
    h('a', { class: 'logo', href: '#/' }, h('i'), 'tour'),
    h('a', { class: 'proj', href: mr.url, target: '_blank', rel: 'noopener noreferrer', title: 'Open on ' + mr.platform }, `${mr.project} ${ref(mr.iid)}`),
    h('span', { class: 'title', title: mr.title }, mr.title),
    h('a', { class: 'risk risk-' + summary.risk, href: '#/' }, cap(summary.risk) + ' risk'),
    h('button', { class: 'search', onclick: () => openPalette() }, h('span', {}, 'Jump to a step or file'), h('kbd', {}, '⌘K')),
    h('span', { class: 'prog', title: `${d} of ${t} steps understood` }, `${d}/${t}`, h('span', { class: 'meter' }, h('i', { style: `width:${pct}%` }))),
    h('button', { class: 'tb', 'aria-pressed': String(S.mode === 'split'), title: 'Unified or side by side', onclick: () => { S.mode = S.mode === 'split' ? 'unified' : 'split'; save(); render(); } }, 'Split'),
    h('button', { class: 'tb', title: 'Toggle theme', onclick: () => { S.theme = dark() ? 'light' : 'dark'; theme(); save(); render(); } }, 'Theme'),
    h('button', { class: 'tb', 'aria-pressed': String(ui.drawer), onclick: () => { ui.drawer = !ui.drawer; render(); } }, 'Comments', n > 0 && h('span', { class: 'n' }, n)));
}
function side() {
  const { t, d } = totals();
  show($side,
    h('a', { class: 'nav' + (ui.view === 'overview' ? ' cur' : ''), href: '#/' }, h('span', { class: 'no' }, '◆'), h('span', { class: 't' }, 'Overview'), h('span', { class: 'cnt' }, tour.summary.risk)),
    h('div', { class: 'sh' }, h('span', {}, 'Chapters'), h('span', {}, `${d}/${t}`)),
    CH.map((c) => {
      const open = ui.view === 'chapter' && curCh === c, dn = doneCount(c);
      return [h('a', { class: 'nav' + (open ? ' cur' : ''), href: '#/c/' + c.id, title: c.title }, h('span', { class: 'no' }, c.mechanical ? 'M' : c.n), h('span', { class: 't' }, c.title),
        h('span', { class: 'cnt' + (!c.mechanical && dn === c.blocks.length ? ' all' : '') }, c.mechanical ? plural(c.blocks[0].atoms.length, 'hunk') : `${dn}/${c.blocks.length}`)),
      open && !c.mechanical && h('div', { class: 'blocks' }, c.blocks.map((b, i) => { const u = S.understood[key(c, i)];
        return h('button', { class: 'brow' + (i === cur ? ' cur' : '') + (u ? ' done' : ''), onclick: () => setCur(i) }, h('span', { class: 'g' }, u ? '✓' : i === cur ? '●' : '○'), h('span', { class: 't' }, b.what)); }))];
    }),
    h('div', { class: 'sh' }, h('span', {}, `Files · ${fileByPath.size}`), h('span', {}, '+ / −')),
    [...fileByPath].map(([f, refs]) => {
      const st = lineStat(refs.map((r) => r.id)), steps = [...new Set(refs.map((r) => label(r.ch, r.i)))];
      return h('a', { class: 'frow' + (ui.view === 'file' && ui.arg === f ? ' cur' : ''), href: fileHref(f), title: f + (steps.length > 1 ? `: explained in ${steps.length} places` : '') },
        h('span', { class: 'fn' }, h('span', {}, dirOf(f)), base(f)), h('span', { class: 'dstat' }, h('span', { class: 'p' }, '+' + st.add), h('span', { class: 'm' }, '−' + st.del)),
        h('span', { class: 'steps' }, steps.map((s) => h('span', { class: 'step' + (steps.length > 1 ? ' many' : '') }, s))));
    }),
    has('drift') && tour.drift?.length > 0 && [h('div', { class: 'sh' }, 'Signals'), tour.drift.map((d) => { const at = chapterOfAtom(d.atoms?.[0]);
      return h('button', { class: 'sig', onclick: () => d.atoms?.[0] && goAtom(d.atoms[0]) }, h('span', { class: 'k' }, d.kind.replace(/_/g, ' ')), h('code', {}, d.detail), at && h('span', { class: 'cnt' }, at.ch.mechanical ? 'mechanical' : 'step ' + label(at.ch, at.i))); })]);
}
function status() {
  show($status, [['j', 'k', 'step'], ['n', 'p', 'chapter'], ['u', null, 'understood'], ['c', null, 'comment'], ['⌘K', null, 'jump']].map(([a, b, l]) => h('span', { class: 'k' }, h('kbd', {}, a), b && h('kbd', {}, b), l)),
    h('span', { class: 'grow' }), h('span', {}, `base ${tour.mr.base_sha.slice(0, 8)} → head ${tour.mr.head_sha.slice(0, 8)}`), h('span', {}, plural(unposted().length, 'draft')));
}

// --- main pane
function overview() {
  const { mr, summary } = tour, all = CH;
  const graph = has('arch') && tour.graph?.mermaid && h('pre', { class: 'mermaid' }, tour.graph.mermaid);
  const resume = S.pos && all.find((c) => c.id === S.pos.chapter);
  show($main, h('div', { class: 'ov' },
    h('div', {}, h('span', { class: 'eyebrow' }, `${mr.project} ${ref(mr.iid)} · head ${mr.head_sha.slice(0, 8)}`), h('h1', {}, mr.title)),
    h('p', { class: 'lede' }, summary.intent), h('p', { class: 'approach' }, summary.approach),
    mr.ticket && h('p', { class: 'ticket' }, h('b', {}, mr.ticket.id), mr.ticket.summary),
    h('div', { class: 'grid2' }, riskCard(), driftCard()),
    h('a', { class: 'btn solid continue', href: '#/c/' + (resume ?? all[0]).id }, resume ? `Continue at step ${label(resume, Math.min(S.pos.block ?? 0, resume.blocks.length - 1))}` : 'Start with chapter 1', ' →'),
    h('div', {}, h('p', { class: 'lbl' }, `Reading order · ${plural(READ.length, 'chapter')}`), h('div', { class: 'chtable' }, all.map((c) =>
      h('a', { href: '#/c/' + c.id }, h('span', { class: 'cnt' }, c.mechanical ? 'M' : c.n), h('span', {}, h('span', { class: 't' }, c.title), h('span', { class: 'r' }, c.order_reason)),
        h('span', { class: 'cnt' + (!c.mechanical && doneCount(c) === c.blocks.length ? ' all' : '') }, c.mechanical ? '' : `${doneCount(c)}/${c.blocks.length}`))))),
    graph && h('div', {}, h('p', { class: 'lbl' }, 'Architecture'), h('div', { class: 'card arch' }, graph))));
  if (graph) loadScript(CDN.mermaid).then(() => { window.mermaid.initialize({ startOnLoad: false, theme: dark() ? 'dark' : 'neutral' }); return window.mermaid.run({ nodes: [graph] }); }).catch(() => {});
}
function chapterMain(ch) {
  const idx = CH.indexOf(ch), prev = CH[idx - 1], next = CH[idx + 1];
  const blocks = ch.blocks.map((b, i) => {
    const u = !!S.understood[key(ch, i)];
    const nWatch = b.watch.length, nRules = has('rules') ? b.rules_flags?.length ?? 0 : 0;
    return h('section', { class: 'blk' + (i === cur ? ' cur' : '') + (u ? ' done' : ''), id: 'blk-' + i, 'data-i': i },
      h('header', { class: 'bh', onclick: () => { if (i !== cur) setCur(i, false); } },
        h('span', { class: 'bn' }, ch.mechanical ? 'M' : label(ch, i)),
        h('div', {}, h('p', { class: 'what' }, b.what), b.why && h('p', { class: 'why' }, srcChip(b), b.why),
          (nWatch > 0 || nRules > 0) && h('div', { class: 'tags' },
            nWatch > 0 && h('button', { class: 'tag warn', onclick: (e) => { e.stopPropagation(); S.tab = 'checks'; setCur(i, false); } }, `${nWatch} to check by hand`),
            nRules > 0 && h('button', { class: 'tag bad', onclick: (e) => { e.stopPropagation(); S.tab = 'checks'; setCur(i, false); } }, plural(nRules, 'rule flag')))),
        !ch.mechanical && h('button', { class: 'ubtn' + (u ? ' on' : ''), title: 'Mark as understood (u)', onclick: (e) => { e.stopPropagation(); cur = i; mark(); } }, u ? '✓ Understood' : 'Mark understood')),
      h('div', { class: 'bd' }, b.atoms.map((id) => atomOrMissing(id, ch))));
  });
  const body = gated(ch) ? gate(ch) : ch.mechanical ? h('details', { class: 'mech' }, h('summary', {}, `Show ${plural(ch.blocks[0].atoms.length, 'mechanical hunk')}`), blocks) : [predRecap(ch), blocks];
  show($main,
    h('div', { class: 'chead' }, h('span', { class: 'eyebrow' }, ch.mechanical ? 'Mechanical · no explanation needed' : `Chapter ${ch.n} of ${READ.length} · ${plural(ch.blocks.length, 'step')}`), h('h1', {}, ch.title), h('p', {}, ch.order_reason)),
    body,
    h('div', { class: 'cnav' }, prev && h('a', { href: '#/c/' + prev.id }, h('small', {}, '← previous (p)'), prev.title), next && h('a', { href: '#/c/' + next.id }, h('small', {}, 'next (n) →'), next.title)));
}
// Active review: teaser and prediction box, then reveal. The prediction only goes to state.json via the local server.
function gate(ch) {
  const box = h('textarea', { rows: '4', id: 'pred-' + ch.id, placeholder: 'Name files or classes, e.g. "the service gets a limit check"', 'aria-label': 'Your prediction' });
  box.value = S.predictions[ch.id]?.text ?? '';
  box.addEventListener('input', () => { S.predictions[ch.id] = { text: box.value, revealed: false }; save(); });
  const reveal = (text) => { S.predictions[ch.id] = { text, revealed: true }; save(); render(); };
  return h('div', { class: 'card gate' }, h('p', { class: 'lbl' }, 'Before you look'), h('p', { class: 'teaser' }, ch.intent),
    h('label', { for: 'pred-' + ch.id }, 'What do you expect to change, and where?'), box,
    h('p', { class: 'note' }, 'After the reveal, changes in files you did not name are marked "not predicted". Predictions stay on this machine (state.json).'),
    h('div', { class: 'act' }, h('button', { class: 'btn solid', onclick: () => reveal(box.value) }, 'Reveal the change'), h('button', { class: 'btn', onclick: () => reveal('') }, 'Skip and reveal')));
}
function predRecap(ch) {
  if (!isActive(ch)) return null;
  const p = S.predictions[ch.id], ids = ch.blocks.flatMap((b) => b.atoms).filter((id) => atoms[id]);
  const missed = ids.filter((id) => surprise(ch, atoms[id])).length;
  return h('div', { class: 'pred' }, h('p', { class: 'lbl' }, 'Your prediction'),
    p?.text.trim() ? [h('p', {}, p.text), h('p', { class: 'muted' }, missed ? `${ids.length - missed} of ${plural(ids.length, 'change')} are in files you named; the others are marked "not predicted".` : 'You named every file this chapter changes.')]
      : h('p', { class: 'muted' }, 'You skipped the prediction.'));
}
function fileMain(path) {
  const refs = fileByPath.get(path) ?? [], lns = lines.get(path);
  const full = h('details', { class: 'full', open: refs.length === 0 }, h('summary', {}, `Whole file at ${tour.mr.head_sha.slice(0, 8)}`));
  const fill = () => { if (full.dataset.filled) return; full.dataset.filled = '1';
    full.append(lns ? h('div', { class: 'diff' }, h('div', { class: 'dbody' }, h('div', { class: 'rows' }, lns.map((t, i) => h('div', { class: 'dl ctx' }, h('span', { class: 'ln' }, ''), h('span', { class: 'ln' }, i + 1), h('span', { class: 'sg' }, ' '), h('span', { class: 'cell' }, code(t, path)))))))
      : h('p', { class: 'bad' }, 'File not available in the worktree.')); };
  if (refs.length === 0) fill(); else full.addEventListener('toggle', fill);
  const steps = [...new Set(refs.map((r) => label(r.ch, r.i)))];
  show($main,
    h('div', { class: 'chead' }, h('span', { class: 'eyebrow' }, dirOf(path) || 'file'), h('h1', {}, base(path)),
      h('p', {}, refs.length ? `${plural(refs.length, 'hunk')}, explained in ${steps.length === 1 ? 'step ' + steps[0] : plural(steps.length, 'step') + ': ' + steps.join(', ')}.` : 'Not changed in this MR.')),
    refs.map((r) => h('section', { class: 'fblk' },
      h('a', { href: '#/c/' + r.ch.id, onclick: () => setPos(r.ch, r.i) }, h('span', { class: 'bn' }, label(r.ch, r.i)), h('span', { class: 't' }, r.ch.mechanical ? 'Mechanical' : r.ch.blocks[r.i].what)),
      atomOrMissing(r.id, r.ch))),
    full);
}

// --- inspector: context, checks and ask for the current step
function insp() {
  if (ui.view !== 'chapter') {
    const t = tour.mr.ticket;
    show($insp, h('div', { class: 'ip' },
      t && h('div', { class: 'head' }, h('span', {}, 'Linked ticket'), h('b', {}, t.id), h('p', { class: 'empty' }, t.summary)),
      h('p', { class: 'empty' }, 'Open a chapter. What the current step reaches, what to check by hand and a chat about the chapter show up here.'),
      h('div', { class: 'keys' }, [['j', 'k', 'next / previous step'], ['n', 'p', 'next / previous chapter'], ['u', null, 'mark understood'], ['c', null, 'comment on the step'], ['⌘K', null, 'jump to a step or file']]
        .map(([a, b, l]) => h('div', {}, h('kbd', {}, a), b && h('kbd', {}, b), l)))));
    return;
  }
  const ch = curCh, b = ch.blocks[cur] ?? ch.blocks[0];
  const probes = has('active') && !ch.mechanical ? ch.probes ?? [] : [];
  const rules = has('rules') ? b.rules_flags ?? [] : [];
  const nChecks = b.watch.length + rules.length + probes.length;
  const tab = ['context', 'checks', 'ask'].includes(S.tab) ? S.tab : 'context';
  const tabs = [['context', 'Context', b.impact.length], ['checks', 'Checks', nChecks], ['ask', 'Ask', 0]];
  let body;
  if (gated(ch) && tab !== 'ask') body = h('p', { class: 'empty' }, 'Make your prediction first. Context and checks appear after the reveal.');
  else if (tab === 'context') body = [h('div', { class: 'head' }, h('span', {}, ch.mechanical ? 'Mechanical' : 'Step ' + label(ch, cur)), h('b', {}, [...new Set(b.atoms.map((id) => atoms[id]?.file).filter(Boolean).map(base))].join(', '))),
    b.impact.length ? h('div', {}, h('p', { class: 'lbl' }, 'What it reaches'), h('ul', { class: 'plain imp' }, b.impact.map((m) => h('li', {},
      h('a', { class: 'sym mono', href: fileHref(m.file), title: m.file }, m.symbol), h('span', {}, m.note),
      has('deep') && m.callers?.length > 0 && h('ul', { class: 'callers' }, m.callers.map((c) => h('li', {}, h('span', { class: 'arr' }, 'called from'), h('code', {}, c.symbol), h('a', { class: 'f', href: fileHref(c.file) }, c.file))))))))
      : h('p', { class: 'empty' }, 'Nothing outside this step depends on it.')];
  else if (tab === 'checks') body = [
    b.watch.length > 0 && h('div', { class: 'watch' }, h('p', { class: 'lbl' }, 'Check by hand'), h('ul', { class: 'plain' }, b.watch.map((w, j) => {
      const k = `${key(ch, cur)}/${j}`, id = 'w-' + k.replace(/[^A-Za-z0-9]/g, '-');
      const box = h('input', { type: 'checkbox', id, onchange: (e) => { if (e.target.checked) S.checks[k] = true; else delete S.checks[k]; save(); } }); box.checked = !!S.checks[k];
      return h('li', {}, box, h('label', { for: id }, w)); }))),
    rules.length > 0 && h('div', {}, h('p', { class: 'lbl' }, 'Rules'), h('ul', { class: 'plain' }, rules.map((r) => h('li', { class: 'rule' }, h('b', {}, r.rule), h('span', { class: 'src-file' }, r.source), h('p', {}, r.note))))),
    probes.length > 0 && h('div', {}, h('p', { class: 'lbl' }, `Break it · chapter ${ch.n}`), h('ul', { class: 'plain' }, probes.map((q) => h('li', { class: 'probe' }, h('p', {}, q.question), h('pre', { class: 'snippet' }, code(q.snippet, '', LANG[base(atoms[b.atoms[0]]?.file ?? '').split('.').pop()])))))),
    nChecks === 0 && h('p', { class: 'empty' }, 'Nothing to check by hand for this step.')];
  else body = ch.mechanical ? h('p', { class: 'empty' }, 'Chat is available on explained chapters.') : chatPanel(ch);
  show($insp,
    h('div', { class: 'tabs', role: 'tablist' }, tabs.map(([id, l, n]) => h('button', { role: 'tab', 'aria-selected': String(tab === id), onclick: () => { S.tab = id; save(); render(); } }, l, n > 0 && h('span', { class: 'c' }, n)))),
    h('div', { class: 'ip' }, body));
}
// Chat: scoped to this chapter, streamed from POST /api/chat (server-sent events). Errors from the claude CLI are shown as they are.
const chats = {};
function chatOf(id) {
  const st = chats[id] ??= { messages: [], busy: false, input: '', loaded: false };
  if (!st.loaded) { st.loaded = true; getJSON('/api/chat?chapter=' + encodeURIComponent(id)).then((c) => { st.messages = [...(c.messages ?? []), ...st.messages]; render(); }).catch(() => {}); }
  return st;
}
function chatPanel(ch) {
  const st = chatOf(ch.id);
  const input = h('textarea', { rows: '3', id: 'chat-' + ch.id, placeholder: 'Ask what a symbol does, who calls it, or why it changed', 'aria-label': 'Chat message' }); input.value = st.input;
  input.addEventListener('input', () => { st.input = input.value; });
  input.addEventListener('keydown', (e) => { if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) { e.preventDefault(); ask(ch); } });
  const send = h('button', { class: 'btn solid', type: 'submit' }, st.busy ? 'Answering…' : 'Ask'); if (st.busy) send.disabled = true;
  return h('div', { class: 'chat' },
    h('p', { class: 'note' }, 'Answers come from claude with read-only tools on the MR checkout, using your CLI login. It counts against your subscription limits.'),
    h('div', { class: 'chatlog', 'aria-live': 'polite' }, st.messages.length ? st.messages.map((m) => h('div', { class: 'msg ' + m.role }, m.text)) : h('p', { class: 'empty' }, 'Nothing asked yet. A question costs tokens only when you send it.')),
    h('form', { class: 'chatf', onsubmit: (e) => { e.preventDefault(); ask(ch); } }, input, send));
}
async function ask(ch) {
  const st = chatOf(ch.id), message = st.input.trim();
  if (!message || st.busy) return;
  st.input = ''; st.busy = true; st.messages.push({ role: 'user', text: message });
  const out = { role: 'assistant', text: '' }; st.messages.push(out); render();
  const live = () => { const els = $insp.querySelectorAll('.msg.assistant'); const el = els[els.length - 1]; if (el) el.textContent = out.text; };
  try {
    const r = await fetch('/api/chat', { method: 'POST', body: JSON.stringify({ chapter: ch.id, message }) });
    if (!r.ok) throw new Error((await r.json().catch(() => ({}))).error ?? `chat: ${r.status}`);
    const rd = r.body.getReader(), dec = new TextDecoder(); let buf = '';
    for (;;) {
      const { done, value } = await rd.read();
      if (done) break;
      buf += dec.decode(value, { stream: true });
      for (let i; (i = buf.indexOf('\n\n')) >= 0; buf = buf.slice(i + 2)) {
        const e = JSON.parse(buf.slice(0, i).replace(/^data: /, ''));
        if (e.type === 'text') { out.text += e.text; live(); } else if (e.type === 'error') st.messages.push({ role: 'error', text: e.error });
      }
    }
  } catch (e) { st.messages.push({ role: 'error', text: e.message }); }
  if (!out.text) st.messages.splice(st.messages.indexOf(out), 1);
  st.busy = false; render();
}

// --- overlays: comment drawer and the jump palette
function drawer() {
  document.getElementById('drawer')?.remove();
  if (!ui.drawer) return;
  const items = draftList().filter((d) => d.body.trim() || d.posted), open = unposted();
  const close = () => { ui.drawer = false; render(); };
  const postAll = h('button', { class: 'btn solid', onclick: async () => { for (const d of unposted()) await postDraft(d); } }, `Post all (${open.length})`); if (!open.length) postAll.disabled = true;
  document.body.append(h('div', { id: 'drawer' }, h('div', { class: 'scrim', onclick: close }),
    h('aside', { class: 'drawer', role: 'dialog', 'aria-label': 'Comment drafts' },
      h('header', {}, h('h2', {}, `Comment drafts (${items.length})`), postAll, h('button', { class: 'btn', onclick: close }, 'Close')),
      h('div', { class: 'list' }, h('p', { class: 'muted' }, 'Nothing reaches the MR until you press Post. The tour never approves.'),
        items.length === 0 && h('p', { class: 'muted' }, 'Click a line number (or press c) to draft a comment on that line.'),
        items.map((d) => draftBox(d, true))))));
}
function openPalette() { ui.palette = ''; ui.palSel = 0; render(); }
function paletteItems() {
  const items = [...CH.flatMap((c) => c.blocks.map((b, i) => ({ k: label(c, i), t: c.mechanical ? 'Mechanical: ' + b.what : b.what, href: '#/c/' + c.id, go: () => setPos(c, i) }))),
    ...[...fileByPath.keys()].map((f) => ({ k: 'file', t: f, href: fileHref(f) }))];
  const q = ui.palette.toLowerCase().trim();
  return items.filter((x) => !q || x.t.toLowerCase().includes(q) || x.k.startsWith(q)).slice(0, 14);
}
function palette() {
  const open = document.getElementById('palette');
  if (ui.palette == null) { open?.remove(); return; }
  if (open) return; // already open: its own handlers update the list
  const close = () => { ui.palette = null; render(); };
  const pick = (x) => { ui.palette = null; x.go?.(); if (location.hash === x.href) route(); else location.hash = x.href; };
  const ul = h('ul', {});
  let list = [];
  const fill = () => {
    list = paletteItems(); ui.palSel = Math.min(ui.palSel, Math.max(0, list.length - 1));
    show(ul, list.length ? list.map((x, i) => h('li', { class: i === ui.palSel ? 'sel' : '' }, h('a', { href: x.href, onclick: (e) => { e.preventDefault(); pick(x); } }, h('span', { class: 'kd' }, x.k), h('span', { class: 'tt' }, x.t))))
      : h('li', { class: 'none' }, 'No step or file matches.'));
  };
  const input = h('input', { id: 'palette-q', 'aria-label': 'Jump to', placeholder: 'Type a step, a sentence or a file name', autocomplete: 'off' }); input.value = ui.palette;
  input.addEventListener('input', () => { ui.palette = input.value; ui.palSel = 0; fill(); });
  input.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { e.preventDefault(); ui.palSel = (ui.palSel + (e.key === 'ArrowDown' ? 1 : -1) + list.length) % Math.max(1, list.length); fill(); }
    else if (e.key === 'Enter' && list[ui.palSel]) pick(list[ui.palSel]);
    else if (e.key === 'Escape') close();
  });
  fill();
  document.body.append(h('div', { id: 'palette', class: 'pal-wrap', onclick: (e) => { if (e.target === e.currentTarget) close(); } },
    h('div', { class: 'pal', role: 'dialog', 'aria-label': 'Jump to' }, input, ul)));
  input.focus?.();
}

// --- render (synchronous; keeps the scroll position of each pane) and routing (loads the files it needs, then renders)
function render() {
  const keep = [$side, $main, $insp].map((e) => e?.scrollTop ?? 0);
  bar(); side(); status(); insp();
  if (ui.view === 'chapter') chapterMain(curCh); else if (ui.view === 'file') fileMain(ui.arg); else overview();
  drawer(); palette();
  [$side, $main, $insp].forEach((e, i) => { if (e) e.scrollTop = keep[i]; });
}
let routing = 0;
async function route() {
  const n = ++routing;
  const [, kind, ...rest] = location.hash.split('/'), arg = decodeURIComponent(rest.join('/'));
  const ch = kind === 'c' && CH.find((c) => c.id === arg);
  if (kind === 'c' && !ch) { location.hash = '#/'; return; }
  if (ch) await preload(ch.blocks.flatMap((b) => b.atoms).map((id) => atoms[id]?.file).filter(Boolean));
  else if (kind === 'f') await preload([arg, ...(fileByPath.get(arg) ?? []).map((r) => atoms[r.id].file)]);
  if (n !== routing) return; // a newer navigation won
  ui.view = ch ? 'chapter' : kind === 'f' ? 'file' : 'overview'; ui.arg = arg; ui.editing = null;
  if (ch) { curCh = ch; cur = S.pos?.chapter === ch.id ? Math.min(S.pos.block ?? 0, ch.blocks.length - 1) : 0; setPos(ch, cur); } else curCh = null;
  render();
  if ($main) $main.scrollTop = 0;
  globalThis.scrollTo?.(0, 0);
  if (ch && cur > 0) $('blk-' + cur)?.scrollIntoView?.({ block: 'start' });
}

// key c: draft on the first changed line of the current block (click a line number for any other line)
function draftOnBlock() {
  const a = atoms[curCh.blocks[cur]?.atoms[0]];
  if (!a?.old || !a?.new) return;
  const { dels, adds } = atomRows(a, lines.get(a.file) ?? null);
  const r = adds[0] ?? dels[0];
  if (r) startDraft(a, r);
}
addEventListener('keydown', (e) => {
  if (!tour) return;
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); if (ui.palette == null) openPalette(); else { ui.palette = null; render(); } return; }
  if (e.key === 'Escape' && (ui.drawer || ui.palette != null)) { ui.drawer = false; ui.palette = null; render(); return; }
  if (e.ctrlKey || e.metaKey || e.altKey || /^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName)) return;
  if (e.key === '/') { e.preventDefault(); openPalette(); return; }
  if (ui.view !== 'chapter') return;
  const idx = CH.indexOf(curCh);
  if (e.key === 'j') setCur(Math.min(cur + 1, curCh.blocks.length - 1));
  else if (e.key === 'k') setCur(Math.max(cur - 1, 0));
  else if (e.key === 'u' && !curCh.mechanical && !gated(curCh)) mark();
  else if (e.key === 'c' && !gated(curCh)) draftOnBlock();
  else if (e.key === 'n' && CH[idx + 1]) location.hash = '#/c/' + CH[idx + 1].id;
  else if (e.key === 'p' && CH[idx - 1]) location.hash = '#/c/' + CH[idx - 1].id;
});
addEventListener('hashchange', () => route());

try {
  let raw;
  [tour, raw, S] = await Promise.all([getJSON('/api/tour'), getJSON('/api/atoms'), getJSON('/api/state')]);
  atoms = Object.fromEntries((Array.isArray(raw) ? raw : raw.atoms ?? []).map((a) => [a.id, a]));
  S = { understood: {}, predictions: {}, checks: {}, mode: 'unified', tab: 'context', ...S, drafts: S.drafts ?? {} };
  S.checks ??= {};
  buildIndex(); theme();
  globalThis.matchMedia?.('(prefers-color-scheme: dark)').addEventListener?.('change', () => { if (!S.theme) render(); });
  await route();
  loadScript(CDN.hljs).then(() => render()).catch(() => {}); // highlight when it arrives; the tour reads fine without it
} catch (e) {
  show($main, h('p', { class: 'bad' }, 'Could not load the tour: ' + e.message));
}

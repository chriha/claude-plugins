// #56: render a chapter whose atoms have no hunks (rename, binary, mode, add) with app.js and a minimal fake DOM.
// usage: node ui-atoms.mjs <app.js>; prints the rendered text of the chapter, or exits 1 on a throw / unhandled rejection.
import { pathToFileURL } from 'node:url';
const node = (tag) => ({ tag, children: [], attrs: {}, className: '', classList: { toggle() {} }, dataset: {},
  append(...k) { this.children.push(...k); }, replaceChildren(...k) { this.children = k; }, setAttribute(k, v) { this.attrs[k] = v; },
  addEventListener() {}, remove() {}, set textContent(t) { this.children = [String(t)]; }, set innerHTML(t) { this.children = [t]; } });
const text = (n) => (typeof n === 'string' ? n : (n.children ?? []).map(text).join(' '));
const els = { main: node('main'), bar: node('header'), side: node('nav'), insp: node('aside'), status: node('footer') }, main = els.main;
globalThis.document = { createElement: node, getElementById: (id) => els[id] ?? null, querySelectorAll: () => [], documentElement: { dataset: {} }, head: node('head'), body: node('body') };
globalThis.addEventListener = () => {}; globalThis.scrollTo = () => {}; globalThis.matchMedia = () => ({ matches: false });
globalThis.location = { hash: '#/c/c1' };
const atoms = [
  { id: 'a1', file: 'new/name.txt', old_file: 'old/name.txt', status: 'renamed', kind: 'rename', old: null, new: null, lines: [], mode: null },
  { id: 'a2', file: 'img.png', old_file: null, status: null, kind: 'binary', old: null, new: null, lines: [], mode: null },
  { id: 'a3', file: 'run.sh', old_file: null, status: null, kind: 'mode', old: null, new: null, lines: [], mode: { old: '100644', new: '100755' } },
  { id: 'a4', file: 'empty.txt', old_file: null, status: 'added', kind: 'add', old: null, new: null, lines: [], mode: null },
];
const block = { atoms: atoms.map((a) => a.id), what: 'no-hunk atoms', why: '', why_source: 'code', impact: [], watch: [] };
const api = { '/api/tour': { mr: { platform: 'github', project: 'o/r', iid: 1, title: 't', url: 'https://github.com/o/r/pull/1', base_sha: '0123456789ab', head_sha: 'abcdef012345' },
  summary: { intent: 'i', approach: 'a', risk: 'low', risk_reasons: [] }, chapters: [{ id: 'c1', title: 'C', order_reason: 'r', blocks: [block] }], mechanical: { atoms: [], note: 'n' }, layers: ['base'] }, '/api/atoms': { atoms }, '/api/state': {} };
globalThis.fetch = async (url) => (api[url] ? { ok: true, json: async () => api[url] } : { ok: false, status: 404, text: async () => '' });
const bad = []; process.on('unhandledRejection', (e) => bad.push(e));
import(pathToFileURL(process.argv[2]).href).catch((e) => bad.push(e));
await new Promise((r) => setTimeout(r, 200)); // app.js has top-level await: let it settle
const out = text(main);
if (bad.length) { console.error('unhandled: ' + bad[0]); process.exit(1); }
console.log(out);

// Static checks that run without the Flutter SDK:
//   1. every .dart file parses (tree-sitter-dart)
//   2. every relative import points at a real file
//   3. every translation key used in lib/ exists in Arabic and English,
//      and neither language map has a duplicate key (a compile error in Dart)
// Usage: node tool/check_dart.mjs [node_modules with web-tree-sitter]  (run via tool/tests: npm test)
import fs from 'fs';
import path from 'path';
import { createRequire } from 'module';

const modules = path.resolve(process.argv[2] || 'tool/tests/node_modules');
const require = createRequire(path.join(modules, 'x.js'));
const TS = require('web-tree-sitter');
const Parser = TS.Parser || TS;
const Language = TS.Language || Parser.Language;
const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');

await Parser.init();
const parser = new Parser();
parser.setLanguage(await Language.load(path.join(modules, 'tree-sitter-wasms/out/tree-sitter-dart.wasm')));

const files = [];
(function walk(d) {
  for (const f of fs.readdirSync(d)) {
    const p = path.join(d, f);
    if (fs.statSync(p).isDirectory()) walk(p);
    else if (p.endsWith('.dart')) files.push(p);
  }
})(path.join(root, 'lib'));
for (const t of fs.readdirSync(path.join(root, 'test'))) if (t.endsWith('.dart')) files.push(path.join(root, 'test', t));

let problems = 0;
const report = (m) => { problems++; console.log('  ' + m); };

// 1 + 2
for (const f of files) {
  const src = fs.readFileSync(f, 'utf8');
  const tree = parser.parse(src);
  const rel = path.relative(root, f);
  const errs = [];
  (function visit(n) {
    if (n.type === 'ERROR' || (typeof n.isMissing === 'function' ? n.isMissing() : n.isMissing)) errs.push(n);
    for (let i = 0; i < n.childCount; i++) visit(n.child(i));
  })(tree.rootNode);
  for (const e of errs.slice(0, 5)) {
    const line = src.split('\n')[e.startPosition.row];
    report(`${rel}:${e.startPosition.row + 1}:${e.startPosition.column + 1} ${e.type !== 'ERROR' ? 'missing ' + e.type : 'syntax error'} → ${line.trim().slice(0, 90)}`);
  }
  for (const m of src.matchAll(/^import\s+'([^']+)'/gm)) {
    const target = m[1];
    if (target.startsWith('package:jalabiya_app/')) {
      if (!fs.existsSync(path.join(root, 'lib', target.slice('package:jalabiya_app/'.length)))) report(`${rel}: import not found ${target}`);
    } else if (!target.startsWith('package:') && !target.startsWith('dart:')) {
      if (!fs.existsSync(path.resolve(path.dirname(f), target))) report(`${rel}: import not found ${target}`);
    }
  }
}

// 3. translation keys
const stringsSrc = fs.readFileSync(path.join(root, 'lib/l10n/strings.dart'), 'utf8');
const enStart = stringsSrc.indexOf("'en': {");
const tables = { ar: stringsSrc.slice(0, enStart), en: stringsSrc.slice(enStart) };
const keys = {};
for (const [lang, body] of Object.entries(tables)) {
  keys[lang] = new Set();
  for (const m of body.matchAll(/^\s*"([a-zA-Z_.]+)":/gm)) {
    if (keys[lang].has(m[1])) report(`strings.dart: duplicate key in ${lang}: ${m[1]}`);
    keys[lang].add(m[1]);
  }
}
for (const k of keys.ar) if (!keys.en.has(k)) report(`strings.dart: "${k}" has Arabic but no English`);
for (const k of keys.en) if (!keys.ar.has(k)) report(`strings.dart: "${k}" has English but no Arabic`);

const used = new Set();
const prefixes = ['action', 'auth', 'welcome', 'role', 'form', 'profile', 'shop', 'tab', 'orders', 'family', 'relation',
  'measure', 'm', 'tip', 'd', 'cloth', 'thread', 'cut', 'collar', 'emb', 'unit', 'money', 'room', 'compose', 'order',
  'status', 'step', 'progress', 'event', 'tailor', 'settings', 'err', 'city'];
const keyLike = new RegExp(`'((?:${prefixes.join('|')})\\.[A-Za-z_.]+)'`, 'g');
for (const f of files) {
  if (f.endsWith('strings.dart')) continue;
  const src = fs.readFileSync(f, 'utf8');
  for (const m of src.matchAll(keyLike)) if (!m[1].endsWith('.dart')) used.add(m[1]);
}
// keys built at runtime from known value lists
const families = {
  status: ['submitted', 'changes_requested', 'confirmed', 'cutting', 'sewing', 'ready', 'delivered', 'declined', 'cancelled'],
  event: ['submitted', 'changes_requested', 'confirmed', 'cutting', 'sewing', 'ready', 'delivered', 'declined', 'cancelled'],
  step: ['submitted', 'confirmed', 'cutting', 'sewing', 'ready', 'delivered'],
  progress: ['declined', 'cancelled'],
  'tailor.next': ['cutting', 'sewing', 'ready', 'delivered'],
  m: ['height', 'chest', 'waist', 'hip', 'shoulder', 'arm', 'neck'],
  tip: ['height', 'chest', 'waist', 'hip', 'shoulder', 'arm', 'neck', 'hem', 'cuff'],
  cloth: ['damuriya', 'cream', 'nile', 'sand', 'ash', 'charcoal'],
  thread: ['gold', 'white', 'indigo', 'henna'],
  cut: ['slim', 'regular', 'full'],
  collar: ['round', 'band', 'shirt'],
  emb: ['none', 'neck', 'full'],
  relation: ['self', 'son', 'father', 'brother', 'other'],
  'room.view': ['cloth', 'both', 'body'],
  'compose.step': ['person', 'body', 'design', 'tailor', 'review'],
  'settings.unit': ['cm', 'in'],
  err: ['NOT_SIGNED_IN', 'NOT_A_CUSTOMER', 'PROFILE_INCOMPLETE', 'TAILOR_UNAVAILABLE', 'INVALID_MEASUREMENT_SET',
    'INVALID_MEASUREMENTS', 'INVALID_DESIGN', 'INVALID_QUANTITY', 'INVALID_WEARER', 'ORDER_NOT_FOUND', 'ORDER_LOCKED',
    'TRANSITION_NOT_ALLOWED', 'PRICE_AND_DATE_REQUIRED', 'NOTE_REQUIRED'],
};
const placesSrc = fs.readFileSync(path.join(root, 'lib/models/places.dart'), 'utf8');
families.city = [...placesSrc.matchAll(/^\s*'([a-z_]+)',/gm)].map((m) => m[1]);
for (const [fam, vals] of Object.entries(families)) for (const v of vals) used.add(`${fam}.${v}`);

for (const k of [...used].sort()) {
  if (!keys.ar.has(k)) report(`missing translation: ${k}`);
}
const unused = [...keys.en].filter((k) => !used.has(k));

console.log(`checked ${files.length} Dart files, ${used.size} translation keys`);
if (unused.length) console.log(`(${unused.length} defined but unused: ${unused.slice(0, 12).join(', ')}${unused.length > 12 ? '…' : ''})`);
console.log(problems ? `\n${problems} problem(s)` : 'no problems');
process.exit(problems ? 1 : 0);

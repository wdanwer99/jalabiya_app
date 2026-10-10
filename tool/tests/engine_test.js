// Loads assets/engine/fitting_room.html the way the Android WebView will, with a
// fake JalabiyaBridge channel, and drives it only through window.engine.
const fs = require('fs');
const { JSDOM } = require('jsdom');
const THREE = require('three');

const html = fs.readFileSync(require('path').join(__dirname, '../../assets/engine/fitting_room.html'), 'utf8');
const [lib, page] = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]);

function boot({ webgl = true } = {}) {
  const dom = new JSDOM(html, { runScripts: 'outside-only', pretendToBeVisual: true });
  const w = dom.window;
  const st = { msgs: [], renders: 0, scene: null };
  w.JalabiyaBridge = { postMessage: (s) => st.msgs.push(JSON.parse(s)) };
  w.eval(lib);
  w.THREE.WebGLRenderer = class {
    constructor() { this.shadowMap = {}; }
    getContext() { return webgl ? {} : null; }
    setPixelRatio() {} setSize() {}
    render(sc) { st.scene = sc; st.renders++; }
  };
  const cv = w.document.getElementById('glass');
  Object.defineProperty(cv, 'clientWidth', { value: 390 });
  Object.defineProperty(cv, 'clientHeight', { value: 340 });
  cv.setPointerCapture = () => {};
  st.errors = [];
  w.addEventListener('error', (e) => st.errors.push(e.message));
  w.eval(page);
  return { w, st };
}
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const out = [];
const check = (ok, m) => out.push((ok ? 'PASS  ' : 'FAIL  ') + m);

function shown(o) { for (let n = o; n; n = n.parent) if (!n.visible) return false; return true; }
function girthAt(scene, y) {
  // tallest visible centred mesh spanning y; measure the ring that sits on y
  let best = null, span = 0;
  scene.traverse((o) => {
    if (!o.isMesh || !o.geometry.index || o.userData.helper || !shown(o)) return;
    o.updateMatrixWorld(true); o.geometry.computeBoundingBox();
    const bb = o.geometry.boundingBox.clone().applyMatrix4(o.matrixWorld);
    if (!(bb.min.y < y - 0.5 && bb.max.y > y + 0.5) || Math.abs((bb.max.x + bb.min.x) / 2) > 3) return;
    if (bb.max.y - bb.min.y > span) { span = bb.max.y - bb.min.y; best = o; }
  });
  if (!best) return null;
  const p = best.geometry.attributes.position, pts = [];
  for (let i = 0; i < p.count; i++) {
    const v = new THREE.Vector3().fromBufferAttribute(p, i).applyMatrix4(best.matrixWorld);
    if (Math.abs(v.y - y) < 0.02) pts.push([v.x, v.z]);
  }
  const cx = pts.reduce((s, q) => s + q[0], 0) / pts.length, cz = pts.reduce((s, q) => s + q[1], 0) / pts.length;
  pts.sort((a, b) => Math.atan2(a[1] - cz, a[0] - cx) - Math.atan2(b[1] - cz, b[0] - cx));
  let per = 0;
  for (let i = 0; i < pts.length; i++) {
    const a = pts[i], b = pts[(i + 1) % pts.length];
    per += Math.hypot(b[0] - a[0], b[1] - a[1]);
  }
  return per;
}

(async () => {
  const { w, st } = boot();
  await wait(150);
  check(st.msgs.some((m) => m.type === 'ready'), 'engine tells Flutter it is ready');
  check(st.renders > 0 && st.errors.length === 0, `renders with no errors (${st.renders} frames)`);

  // sizes arrive exactly as the Dart code sends them
  w.engine.setView('body');
  w.engine.apply({ height: 196, chest: 132, waist: 128, hip: 130, shoulder: 52, arm: 66, neck: 44,
                   cut: 'full', hem: 3, cuff: 40, collar: 'shirt', emb: 'full',
                   clothColor: 0xB9CDD9, threadColor: 0x9C4A2F });
  await wait(120);
  for (const [k, f, want] of [['chest', 0.725, 132], ['waist', 0.625, 128], ['hip', 0.525, 130]]) {
    const g = girthAt(st.scene, f * 196);
    check(g && Math.abs(g - want) < 0.05, `${k} sent ${want} → mesh measures ${g && g.toFixed(2)} cm`);
  }
  // colours reach the materials
  let cloth = null, trim = null;
  st.scene.traverse((o) => {
    if (o.isMesh && o.material && o.material.normalMap === undefined) return;
    if (o.isMesh && o.material.side === THREE.DoubleSide && !cloth) cloth = o.material;
    if (o.isMesh && o.material.metalness === 0.35 && !trim) trim = o.material;
  });
  check(cloth && cloth.color.getHex() === 0xB9CDD9, 'cloth colour applied');
  check(trim && trim.color.getHex() === 0x9C4A2F, 'thread colour applied');

  // garbage in never becomes broken geometry
  w.engine.apply({ chest: 'abc', waist: NaN, hip: 9999, height: -5, cut: 'tent', collar: null });
  w.engine.apply('{"neck": 31, "arm": "70"}');
  await wait(120);
  let nan = 0, meshes = 0;
  st.scene.traverse((o) => {
    if (!o.geometry || !o.geometry.attributes.position) return; meshes++;
    for (const v of o.geometry.attributes.position.array) if (!Number.isFinite(v)) nan++;
  });
  check(nan === 0 && st.errors.length === 0, `bad input is clamped, not crashed (${meshes} meshes, ${nan} NaN)`);
  const g150 = girthAt(st.scene, 0.525 * 145); // height clamped to 145, hip clamped to 150
  check(g150 && Math.abs(g150 - 150) < 0.05, `out-of-range hip clamps to the 150 cm limit (${g150 && g150.toFixed(2)})`);

  // tape labels: localized, unit aware, and safe
  w.engine.setLabels({ chest: 'الصدر', height: '<img src=x onerror=alert(1)>' });
  w.engine.setUnit('in');
  const tapeTxt = w.document.getElementById('tape').textContent;
  check(tapeTxt.includes('الصدر') && tapeTxt.includes('″'), 'Arabic labels and inches show on the tape');
  check(w.document.querySelectorAll('#tape img').length === 0, 'labels are escaped, never run as HTML');

  // focus ring on the measurement being edited
  w.engine.focus('waist');
  await wait(80);
  let ring = 0; st.scene.traverse((o) => { if (o.isLine) ring++; });
  check(ring === 1 && w.document.querySelector('#tape .mark.live'), 'focus draws a chalk ring and lights its tape mark');
  w.engine.focus(null);

  // pausing stops the GPU work when the stage is hidden
  w.engine.setPaused(true);
  await wait(60); const n0 = st.renders; await wait(150);
  check(st.renders === n0, 'paused engine stops rendering');
  w.engine.setPaused(false); await wait(100);
  check(st.renders > n0, 'and resumes');

  // a phone without WebGL reports it instead of hanging
  const bad = boot({ webgl: false });
  await wait(100);
  check(bad.st.msgs.some((m) => m.type === 'error' && m.code === 'webgl') && !bad.st.msgs.some((m) => m.type === 'ready'),
    'no WebGL → posts an error so Flutter can show a fallback');
  let threw = null; try { bad.w.engine.apply({ chest: 100 }); bad.w.engine.setView('body'); } catch (e) { threw = e.message; }
  check(threw === null, 'calls into a failed engine are harmless no-ops');

  console.log(out.join('\n'));
  const f = out.filter((l) => l.startsWith('FAIL')).length;
  console.log(`\n${out.length - f}/${out.length} passed`);
  process.exit(f ? 1 : 0);
})();

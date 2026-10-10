#!/usr/bin/env python3
"""Builds assets/engine/fitting_room.html from the web prototype.

The prototype page carries its own sliders and panels. In the app, Flutter
draws those natively, so this keeps only the 3D stage and the tailor's tape,
and adds a small bridge:

    Flutter -> page   window.engine.apply({...})  setView  focus  setUnit
                      setLabels  setPaused
    page -> Flutter   JalabiyaBridge.postMessage('{"type":"ready"}')
                      ... '{"type":"error","code":"webgl"}'

Usage:  python3 tool/build_engine.py <prototype.html> <three.min.js r128>
"""
import re
import sys
from pathlib import Path

proto_path, three_path = sys.argv[1], sys.argv[2]
proto = Path(proto_path).read_text(encoding="utf-8")
three = Path(three_path).read_text(encoding="utf-8")
assert "</script" not in three
assert "REVISION" in three[:4000] or '"128"' in three, "expected three.js r128"

scripts = re.findall(r"<script>([\s\S]*?)</script>", proto)
page = scripts[-1].split("\n")


def lines(a, b):
    """1-based inclusive slice of the prototype's page script."""
    return "\n".join(page[a - 1:b])


def find(marker):
    for i, l in enumerate(page, 1):
        if marker in l:
            return i
    raise SystemExit("marker not found: " + marker)


geo_start = find("/* ============================ math")
geo_end = find("/* ============================ numbers out") - 1
fmt_start = find("function fmt(cm)")
turn_start = find("/* ============================ turning")
turn_end = find("/* ============================ resize + loop") - 1

geometry = lines(geo_start, geo_end)
fmt = lines(fmt_start, fmt_start + 4)
turning = lines(turn_start, turn_end)


def swap(src, old, new, label):
    assert old in src, "missing: " + label
    return src.replace(old, new, 1)


# errors go to Flutter, which shows its own localized message
geometry = swap(geometry, """function stageError(head, body){
  var box = document.createElement("div");
  box.className = "stagemsg";
  box.innerHTML = "<strong>" + head + "</strong><span>" + body + "</span>";
  canvas.parentNode.appendChild(box);
  canvas.style.display = "none";
}""", """function stageError(head, body){
  canvas.style.display = "none";
  post({type:"error", code: window.THREE ? "webgl" : "three", detail: head});
}""", "stageError")

geometry = swap(geometry, "color:CLOTHS[0].c,", "color:CLOTH_COLOR,", "cloth colour")
geometry = swap(geometry, "{color:THREADS[0].c,", "{color:THREAD_COLOR,", "thread colour")
# phones: a 1024 shadow map looks the same at this size and costs a quarter
geometry = swap(geometry, "key.shadow.mapSize.width = 2048; key.shadow.mapSize.height = 2048;",
                "key.shadow.mapSize.width = 1024; key.shadow.mapSize.height = 1024;", "shadow map")
for k, word in [("height", "Height"), ("shoulder", "Shoulder"), ("chest", "Chest"),
                ("waist", "Waist"), ("hip", "Hip"), ("hem", "Hem")]:
    geometry = swap(geometry, 'lab:"%s"' % word, "lab:LABELS.%s" % k, "label " + k)
# labels arrive from Flutter, so escape them before they touch innerHTML
geometry = swap(geometry, "'+r.lab+' <b>'", "'+esc(r.lab)+' <b>'", "escape label")

header = r"""(function(){
"use strict";

/* ============================ bridge ============================ */
function post(msg){
  try{
    if(window.JalabiyaBridge && window.JalabiyaBridge.postMessage){
      window.JalabiyaBridge.postMessage(JSON.stringify(msg));
    }
  }catch(e){}
}
function esc(s){
  return String(s).replace(/[&<>"']/g, function(c){
    return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c];
  });
}
/* calls that arrive before the scene exists are a no-op, so Flutter can never
   crash the page; Flutter re-sends everything when it hears "ready". */
window.engine = { apply:function(){}, setView:function(){}, focus:function(){},
                  setUnit:function(){}, setLabels:function(){}, setPaused:function(){} };

/* ============================ state ============================ */
var DEFAULTS = {
  height:175, chest:100, waist:90, hip:100, shoulder:46, arm:60, neck:39,
  cut:"regular", hem:4, cuff:34, collar:"band", emb:"neck"
};
var RANGES = {
  height:[145,205], chest:[76,150], waist:[64,150], hip:[76,150], shoulder:[36,58],
  arm:[48,74], neck:[32,50], hem:[0,30], cuff:[22,60]
};
var CHOICES = { cut:["slim","regular","full"], collar:["round","band","shirt"], emb:["none","neck","full"] };
var S = Object.assign({}, DEFAULTS);
var CLOTH_COLOR = 0xF5F1E6, THREAD_COLOR = 0xC8A24A;
var LABELS = { height:"Height", shoulder:"Shoulder", chest:"Chest", waist:"Waist", hip:"Hip", hem:"Hem" };
var unit = "cm";
var view = "cloth";
var live = null;
var dirty = true;
var paused = false;

var SWEEP = { slim:1.30, regular:1.62, full:2.05 };
var L = {
  ankle:0.045, calf:0.155, knee:0.285, thigh:0.40, crotch:0.475,
  hip:0.525, waist:0.625, chest:0.725, shoulder:0.818, neck:0.862, crown:1.0
};

"""

footer = r"""
/* ============================ resize + loop ============================ */
function resize(){
  var w = canvas.clientWidth, h = canvas.clientHeight;
  if(!w || !h) return;
  renderer.setSize(w, h, false);
  var aspect = w/h;
  camera.left = -FRUSTUM*aspect/2;
  camera.right = FRUSTUM*aspect/2;
  camera.top = FRUSTUM/2; camera.bottom = -FRUSTUM/2;
  camera.updateProjectionMatrix();
}
window.addEventListener("resize", function(){ resize(); buildTape(); drawMarks(); dirty = true; });

function frame(){
  requestAnimationFrame(frame);
  if(paused) return;
  if(dirty){ buildBody(); buildCloth(); buildMark(); applyView(); dirty=false; }
  if(!drag){
    if(!slowMo) spin += 0.0016;
    vel *= 0.9;
    spin += vel;
  }
  turn.rotation.y = spin;
  renderer.render(scene, camera);
}

/* ============================ the API Flutter calls ============================ */
function toNum(v, k){
  var n = Number(v);
  if(!isFinite(n)) return S[k];
  var r = RANGES[k];
  return r ? clamp(n, r[0], r[1]) : n;
}
window.engine = {
  apply: function(state){
    var o = (typeof state === "string") ? JSON.parse(state) : (state || {});
    Object.keys(RANGES).forEach(function(k){ if(o[k] != null) S[k] = toNum(o[k], k); });
    Object.keys(CHOICES).forEach(function(k){
      if(o[k] != null && CHOICES[k].indexOf(o[k]) >= 0) S[k] = o[k];
    });
    if(o.clothColor != null){ CLOTH_COLOR = Number(o.clothColor) >>> 0; matCloth.color.setHex(CLOTH_COLOR); }
    if(o.threadColor != null){ THREAD_COLOR = Number(o.threadColor) >>> 0; matTrim.color.setHex(THREAD_COLOR); }
    dirty = true; drawMarks();
  },
  setView: function(v){
    if(v === "cloth" || v === "both" || v === "body"){ view = v; applyView(); }
  },
  focus: function(k){ live = k || null; dirty = true; drawMarks(); },
  setUnit: function(u){ unit = (u === "in") ? "in" : "cm"; drawMarks(); },
  setLabels: function(m){
    var o = (typeof m === "string") ? JSON.parse(m) : (m || {});
    Object.keys(LABELS).forEach(function(k){ if(typeof o[k] === "string") LABELS[k] = o[k]; });
    drawMarks();
  },
  setPaused: function(p){ paused = !!p; }
};

resize(); buildTape(); drawMarks(); frame();
post({type:"ready", version:1});
})();
"""

script = header + geometry + "\n\n" + fmt + "\n\n" + turning + "\n" + footer

html = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<title>Fitting room engine</title>
<style>
:root{ --ink:#101A2B; --ink-3:#22344F; --damur:#F2EDE1; --gold:#C8A24A; --chalk:#8B93A5; }
html,body{margin:0;padding:0;height:100%;overflow:hidden;background:var(--ink);
  -webkit-user-select:none;user-select:none;-webkit-tap-highlight-color:transparent}
.stage{position:fixed;inset:0;overflow:hidden;
  background:radial-gradient(120% 80% at 50% 8%, var(--ink-3) 0%, var(--ink) 62%)}
#glass{position:absolute;inset:0;display:block;width:100%;height:100%;touch-action:none}
.tape{position:absolute;inset:0 auto 0 0;width:92px;pointer-events:none;
  font-family:ui-monospace,"Roboto Mono",monospace}
.tape-rail{position:absolute;inset:0;border-right:1px solid rgba(242,237,225,.18)}
.tick{position:absolute;right:0;height:1px;background:rgba(242,237,225,.22);width:7px}
.tick.major{width:15px;background:rgba(242,237,225,.45)}
.tick-num{position:absolute;right:20px;transform:translateY(-50%);font-size:9px;color:var(--chalk)}
.mark{position:absolute;left:0;right:0;transform:translateY(-50%);transition:opacity .2s}
.mark-line{position:absolute;left:12px;right:-14px;top:50%;height:1px;
  background:linear-gradient(90deg,var(--gold),rgba(200,162,74,.15))}
.mark-txt{position:relative;padding:0 0 4px 12px;font-size:9px;letter-spacing:.06em;color:var(--gold);
  white-space:nowrap;font-family:system-ui,sans-serif}
.mark-txt b{font-weight:500;color:var(--damur);font-family:ui-monospace,"Roboto Mono",monospace}
.mark[data-dim]{opacity:.3}
.mark.live{opacity:1}
</style>
</head>
<body>
<div class="stage">
  <canvas id="glass" aria-label="3D model, drag to turn"></canvas>
  <div class="tape" id="tape"><div class="tape-rail"></div></div>
</div>
<!-- three.js r128 (MIT, Three.js Authors), bundled so the app works offline -->
<script>
""" + three + """
</script>
<script>
""" + script + """
</script>
</body>
</html>
"""

out = Path(__file__).resolve().parent.parent / "assets" / "engine" / "fitting_room.html"
out.write_text(html, encoding="utf-8")
print("wrote", out, round(len(html) / 1024), "KB")

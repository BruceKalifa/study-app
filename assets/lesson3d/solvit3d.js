/*!
 * Solvit 3D 수업 런타임 v1 — three.js(r147) 위에서 단계별 3D 모션 그래픽 수업을 재생한다.
 * 좌표는 수학식 그대로 z 가 위쪽(오른손 좌표계). 문서: docs/lesson3d.md
 *
 *   Solvit3D.lesson({
 *     title: '이중적분과 부피',
 *     camera: { position: [7, -9, 6], target: [0, 0, 1] },
 *     setup(s) { s.axes({ size: 4 }); },                     // 모든 단계에 남는 물체
 *     steps: [
 *       { title: '1. 곡면', caption: 'z = f(x, y) 는 …',
 *         build(s) { s.surface((x, y) => 4 - x * x - y * y, { x: [-2, 2], y: [-2, 2] }); },
 *         animate(s, p) { … },  duration: 5 },                // 선택: p = 0~1 진행도
 *     ],
 *   });
 */
(function (global) {
  'use strict';
  var T = global.THREE;
  if (!T) { throw new Error('three.js 가 먼저 불러와져야 해요'); }

  var TAU = Math.PI * 2;
  var css = [
    'html,body{margin:0;height:100%;overflow:hidden;background:#F7F5EF;font-family:Pretendard,"Noto Sans KR","Apple SD Gothic Neo","Malgun Gothic",sans-serif;-webkit-user-select:none;user-select:none;-webkit-tap-highlight-color:transparent}',
    '#s3{position:fixed;inset:0;touch-action:none}',
    '#s3 canvas{display:block;width:100%;height:100%}',
    '.s3-title{position:fixed;left:14px;top:12px;padding:8px 14px;border-radius:12px;background:rgba(255,255,255,.86);font-weight:800;font-size:18px;color:#1D2433;box-shadow:0 1px 6px rgba(0,0,0,.12);max-width:60vw}',
    '.s3-tools{position:fixed;right:14px;top:12px;display:flex;gap:8px}',
    '.s3-btn{min-width:46px;height:46px;padding:0 14px;border:0;border-radius:23px;background:rgba(255,255,255,.92);color:#1D2433;font:700 16px/1 inherit;box-shadow:0 1px 6px rgba(0,0,0,.18);cursor:pointer}',
    '.s3-btn.on{background:#2F6BFF;color:#fff}',
    '.s3-btn:disabled{opacity:.35}',
    '.s3-cap{position:fixed;left:50%;bottom:78px;transform:translateX(-50%);width:min(920px,calc(100vw - 28px));padding:12px 18px;border-radius:16px;background:rgba(255,255,255,.93);box-shadow:0 2px 12px rgba(0,0,0,.16);color:#1D2433}',
    '.s3-cap b.h{display:block;font-size:20px;margin-bottom:4px}',
    '.s3-cap div{font-size:18px;line-height:1.55;white-space:pre-wrap}',
    '.s3-bar{position:fixed;left:50%;bottom:14px;transform:translateX(-50%);width:min(920px,calc(100vw - 28px));display:flex;align-items:center;gap:10px}',
    '.s3-bar input[type=range]{flex:1;height:34px;accent-color:#2F6BFF}',
    '.s3-n{min-width:54px;text-align:center;font-weight:800;color:#1D2433;background:rgba(255,255,255,.9);border-radius:16px;padding:8px 10px;font-size:15px}',
    '.s3-err{position:fixed;left:14px;right:14px;top:64px;padding:10px 14px;border-radius:12px;background:#FDE7E7;color:#B42318;font:600 14px/1.5 monospace;white-space:pre-wrap;display:none}',
  ].join('\n');

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]; }); }
  function clamp(x, a, b) { return Math.min(b, Math.max(a, x)); }
  function ease(p) { p = clamp(p, 0, 1); return p * p * (3 - 2 * p); }
  function V(x, y, z) { return x && x.isVector3 ? x.clone() : Array.isArray(x) ? new T.Vector3(x[0], x[1], x[2] || 0) : new T.Vector3(x, y, z); }
  function C(c, d) { return new T.Color(c == null ? d : c); }

  function lesson(def) {
    if (!document.body) { document.addEventListener('DOMContentLoaded', function () { lesson(def); }); return; }
    return new Player(def || {});
  }

  function Player(def) {
    var self = this;
    this.def = def;
    this.steps = (def.steps || []).slice();
    if (!this.steps.length) this.steps = [{ title: def.title || '', caption: '' }];
    this.index = -1;
    this.p = 0;
    this.playing = false;
    this.time = 0;
    this.stepGroup = null;
    this.tween = null;

    var style = el('style'); style.textContent = css; document.head.appendChild(style);
    var root = el('div'); root.id = 's3'; document.body.appendChild(root);
    this.errBox = el('div', 's3-err'); document.body.appendChild(this.errBox);

    var renderer;
    try {
      renderer = new T.WebGLRenderer({ antialias: true, alpha: false, preserveDrawingBuffer: !!def.preserveDrawingBuffer });
    } catch (e) {
      root.appendChild(el('div', 's3-cap', '이 기기에서는 3D 그림을 그릴 수 없어요 (WebGL 없음)'));
      return;
    }
    renderer.setPixelRatio(Math.min(global.devicePixelRatio || 1, 2));
    renderer.setClearColor(C(def.background, '#F7F5EF'));
    root.appendChild(renderer.domElement);
    this.renderer = renderer;

    var scene = this.scene = new T.Scene();
    var camera = this.camera = new T.PerspectiveCamera(45, 1, 0.05, 500);
    camera.up.set(0, 0, 1);
    var cam = def.camera || {};
    this.home = { position: V(cam.position || [7, -9, 6]), target: V(cam.target || [0, 0, 0]) };
    camera.position.copy(this.home.position);
    var controls = this.controls = new T.OrbitControls(camera, renderer.domElement);
    controls.enableDamping = true;
    controls.dampingFactor = 0.12;
    controls.target.copy(this.home.target);
    controls.autoRotateSpeed = 1.6;
    controls.update();

    scene.add(new T.AmbientLight(0xffffff, 0.72));
    var d1 = new T.DirectionalLight(0xffffff, 0.75); d1.position.set(4, -6, 10); scene.add(d1);
    var d2 = new T.DirectionalLight(0xffffff, 0.35); d2.position.set(-6, 5, -3); scene.add(d2);

    // ── 화면 요소
    root.appendChild(el('div', 's3-title', def.title || ''));
    var tools = el('div', 's3-tools');
    this.btnRotate = el('button', 's3-btn', '⟳ 자동회전');
    this.btnHome = el('button', 's3-btn', '시점 처음으로');
    tools.appendChild(this.btnRotate); tools.appendChild(this.btnHome);
    document.body.appendChild(tools);
    this.cap = el('div', 's3-cap'); document.body.appendChild(this.cap);
    var bar = el('div', 's3-bar'); document.body.appendChild(bar);
    this.btnPrev = el('button', 's3-btn', '◀ 이전');
    this.btnPlay = el('button', 's3-btn', '▶ 재생');
    this.slider = el('input'); this.slider.type = 'range'; this.slider.min = 0; this.slider.max = 1000; this.slider.value = 0;
    this.btnNext = el('button', 's3-btn', '다음 ▶');
    this.count = el('div', 's3-n', '');
    bar.appendChild(this.btnPrev); bar.appendChild(this.btnPlay); bar.appendChild(this.slider); bar.appendChild(this.btnNext); bar.appendChild(this.count);

    this.btnPrev.onclick = function () { self.go(self.index - 1); };
    this.btnNext.onclick = function () { self.go(self.index + 1); };
    this.btnPlay.onclick = function () { self.toggle(); };
    this.btnHome.onclick = function () { self.camTo(self.stepCamera() || self.home, 0.8); };
    this.btnRotate.onclick = function () { controls.autoRotate = !controls.autoRotate; self.btnRotate.classList.toggle('on', controls.autoRotate); };
    this.slider.oninput = function () { self.playing = false; self.setP(self.slider.value / 1000); self.syncUi(); };
    document.addEventListener('keydown', function (e) {
      if (e.key === 'ArrowRight') self.go(self.index + 1);
      else if (e.key === 'ArrowLeft') self.go(self.index - 1);
      else if (e.key === ' ') { e.preventDefault(); self.toggle(); }
    });
    global.addEventListener('error', function (e) { self.fail(e.error || e.message); });
    global.addEventListener('resize', function () { self.resize(); });

    // ── 도우미 (s)
    this.s = this.makeApi();
    this.rootGroup = new T.Group(); scene.add(this.rootGroup);
    this.target = this.rootGroup;
    this.guard(function () { if (def.setup) def.setup(self.s); });
    this.resize();
    this.go(0);
    var last = performance.now();
    (function loop(now) {
      var dt = Math.min(0.1, (now - last) / 1000); last = now;
      self.tick(dt);
      requestAnimationFrame(loop);
    })(last);
    Solvit3D._player = this;
  }

  var P = Player.prototype;

  P.fail = function (err) {
    var msg = err && err.stack ? String(err.stack).split('\n').slice(0, 4).join('\n') : String(err);
    this.errBox.textContent = '⚠ ' + msg;
    this.errBox.style.display = 'block';
    if (global.console) console.error(err);
  };
  P.guard = function (fn) { try { return fn(); } catch (e) { this.fail(e); } };

  P.resize = function () {
    var w = global.innerWidth, h = global.innerHeight;
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / Math.max(1, h);
    this.camera.updateProjectionMatrix();
  };

  P.stepCamera = function () {
    var c = this.steps[this.index] && this.steps[this.index].camera;
    return c ? { position: V(c.position || this.home.position), target: V(c.target || this.home.target) } : null;
  };

  P.camTo = function (to, sec) {
    this.tween = { t: 0, d: Math.max(0.01, sec || 0.8), p0: this.camera.position.clone(), t0: this.controls.target.clone(), p1: V(to.position), t1: V(to.target) };
  };

  P.clearStep = function () {
    var g = this.stepGroup;
    if (!g) return;
    g.traverse(function (o) {
      if (o.geometry) o.geometry.dispose();
      if (o.material) { if (o.material.map) o.material.map.dispose(); o.material.dispose(); }
    });
    this.scene.remove(g);
    this.stepGroup = null;
  };

  P.go = function (i) {
    i = clamp(i, 0, this.steps.length - 1);
    if (i === this.index) return;
    var self = this, step = this.steps[i];
    this.clearStep();
    this.index = i;
    this.stepGroup = new T.Group();
    this.scene.add(this.stepGroup);
    this.target = this.stepGroup;
    this.p = 0; this.time = 0; this.playing = false;
    this.s.v = {}; // 단계마다 새로 비는 보관함 (build 에서 담고 animate 에서 꺼내 쓴다)
    this.guard(function () { if (step.build) step.build.call(step, self.s); });
    this.target = this.rootGroup;
    var sc = this.stepCamera();
    if (sc) this.camTo(sc, 0.9);
    this.setCaption(step.title, step.caption);
    this.setP(step.startAt != null ? step.startAt : (step.animate ? 0 : 1));
    if (step.animate && step.autoplay !== false && step.startAt == null) this.playing = true;
    this.syncUi();
  };

  P.setCaption = function (title, text) {
    this.cap.innerHTML = (title ? '<b class="h">' + esc(title) + '</b>' : '') +
      '<div>' + esc(text).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>') + '</div>';
    this.cap.style.display = (title || text) ? 'block' : 'none';
  };

  P.setP = function (p) {
    var self = this, step = this.steps[this.index];
    this.p = clamp(p, 0, 1);
    this.slider.value = Math.round(this.p * 1000);
    if (step && step.animate) this.guard(function () { self.target = self.stepGroup; step.animate.call(step, self.s, self.p, self.p * (step.duration || 5)); self.target = self.rootGroup; });
  };

  P.toggle = function () {
    var step = this.steps[this.index];
    if (!step || !step.animate) return;
    if (!this.playing && this.p >= 1) this.setP(0);
    this.playing = !this.playing;
    this.syncUi();
  };

  P.syncUi = function () {
    var step = this.steps[this.index] || {};
    var anim = !!step.animate;
    this.btnPlay.textContent = this.playing ? '❚❚ 멈춤' : '▶ 재생';
    this.btnPlay.disabled = !anim;
    this.slider.disabled = !anim;
    this.slider.style.visibility = anim ? 'visible' : 'hidden';
    this.btnPrev.disabled = this.index <= 0;
    this.btnNext.disabled = this.index >= this.steps.length - 1;
    this.count.textContent = (this.index + 1) + ' / ' + this.steps.length;
  };

  P.tick = function (dt) {
    var step = this.steps[this.index];
    if (this.tween) {
      var tw = this.tween; tw.t += dt;
      var k = ease(tw.t / tw.d);
      this.camera.position.lerpVectors(tw.p0, tw.p1, k);
      this.controls.target.lerpVectors(tw.t0, tw.t1, k);
      if (tw.t >= tw.d) this.tween = null;
    }
    if (this.playing && step && step.animate) {
      var dur = step.duration || 5;
      var np = this.p + dt / dur;
      if (np >= 1) {
        if (step.loop) np = 0; else { np = 1; this.playing = false; this.syncUi(); }
      }
      this.setP(np);
    }
    this.controls.update();
    this.renderer.render(this.scene, this.camera);
  };

  // ───────────── 도우미 모음 ─────────────
  P.makeApi = function () {
    var self = this;
    function add(o) { (self.target || self.rootGroup).add(o); return o; }
    var s = {
      THREE: T, scene: this.scene, camera: this.camera, controls: this.controls, renderer: this.renderer,
      V: V, color: C, clamp: clamp, ease: ease, TAU: TAU,
      lerp: function (a, b, t) { return a + (b - a) * t; },
      add: add,
      setCaption: function (title, text) { self.setCaption(title, text); },
      camTo: function (c, sec) { self.camTo({ position: V(c.position), target: V(c.target) }, sec); },
      goto: function (i) { self.go(i); },
    };

    s.light = function (pos, intensity, color) { var l = new T.PointLight(color || 0xffffff, intensity == null ? 0.6 : intensity); l.position.copy(V(pos)); return add(l); };

    s.point = function (pos, o) {
      o = o || {};
      var m = new T.Mesh(new T.SphereGeometry(o.r || 0.08, 20, 14), new T.MeshPhongMaterial({ color: C(o.color, '#E0703B') }));
      m.position.copy(V(pos)); add(m);
      if (o.label) m.userData.label = s.label(o.label, V(pos).add(new T.Vector3(0, 0, (o.r || 0.08) + 0.25)), { color: o.labelColor || o.color });
      return m;
    };

    s.sphere = function (pos, r, o) {
      o = o || {};
      var mat = new T.MeshPhongMaterial({ color: C(o.color, '#4f7cff'), transparent: o.opacity != null && o.opacity < 1, opacity: o.opacity == null ? 1 : o.opacity, wireframe: !!o.wire });
      var m = new T.Mesh(new T.SphereGeometry(r || 1, 32, 20), mat); m.position.copy(V(pos || [0, 0, 0])); return add(m);
    };

    s.box = function (center, size, o) {
      o = o || {};
      var sz = V(size || [1, 1, 1]);
      var mat = new T.MeshPhongMaterial({ color: C(o.color, '#4f7cff'), transparent: o.opacity != null && o.opacity < 1, opacity: o.opacity == null ? 1 : o.opacity });
      var m = new T.Mesh(new T.BoxGeometry(sz.x, sz.y, sz.z), mat); m.position.copy(V(center || [0, 0, 0]));
      add(m);
      if (o.edges !== false) { var e = new T.LineSegments(new T.EdgesGeometry(m.geometry), new T.LineBasicMaterial({ color: C(o.edgeColor, '#1D2433') })); m.add(e); }
      return m;
    };

    function between(a, b, geom, mat) {
      var A = V(a), B = V(b), d = B.clone().sub(A), len = d.length() || 1e-6;
      var m = new T.Mesh(geom(len), mat);
      m.position.copy(A.clone().add(B).multiplyScalar(0.5));
      m.quaternion.setFromUnitVectors(new T.Vector3(0, 1, 0), d.normalize());
      return m;
    }

    s.cylinder = function (a, b, r, o) {
      o = o || {};
      var mat = new T.MeshPhongMaterial({ color: C(o.color, '#4f7cff'), transparent: o.opacity != null && o.opacity < 1, opacity: o.opacity == null ? 1 : o.opacity });
      return add(between(a, b, function (len) { return new T.CylinderGeometry(r || 0.5, r || 0.5, len, 40, 1, !!o.open); }, mat));
    };

    s.cone = function (apex, base, r, o) {
      o = o || {};
      var mat = new T.MeshPhongMaterial({ color: C(o.color, '#4f7cff'), transparent: o.opacity != null && o.opacity < 1, opacity: o.opacity == null ? 1 : o.opacity });
      return add(between(base, apex, function (len) { return new T.ConeGeometry(r || 0.5, len, 40, 1, !!o.open); }, mat));
    };

    // 화살표: from → to. 반환값 .set(from, to) 로 움직일 수 있다.
    s.arrow = function (from, to, o) {
      o = o || {};
      var g = new T.Group(), col = C(o.color, '#1D2433');
      var mat = new T.MeshPhongMaterial({ color: col });
      var rad = o.width || 0.035;
      var shaft = new T.Mesh(new T.CylinderGeometry(rad, rad, 1, 12), mat);
      var head = new T.Mesh(new T.ConeGeometry(rad * 3.2, 1, 16), mat);
      g.add(shaft); g.add(head);
      var lab = null;
      g.set = function (f, t) {
        var A = V(f), B = V(t), d = B.clone().sub(A), len = d.length();
        var hl = Math.min(o.headLength || rad * 8, len * 0.6);
        var dir = len > 1e-9 ? d.clone().normalize() : new T.Vector3(0, 0, 1);
        var q = new T.Quaternion().setFromUnitVectors(new T.Vector3(0, 1, 0), dir);
        shaft.scale.set(1, Math.max(1e-4, len - hl), 1);
        shaft.position.copy(A.clone().add(dir.clone().multiplyScalar((len - hl) / 2))); shaft.quaternion.copy(q);
        head.scale.set(1, hl, 1);
        head.position.copy(B.clone().sub(dir.clone().multiplyScalar(hl / 2))); head.quaternion.copy(q);
        head.visible = len > 1e-6; shaft.visible = len > 1e-6;
        if (lab) lab.position.copy(B.clone().add(new T.Vector3(0, 0, 0.22)));
      };
      add(g);
      if (o.label) lab = s.label(o.label, V(to), { color: o.labelColor || o.color });
      g.set(from, to);
      return g;
    };

    s.line = function (pts, o) {
      o = o || {};
      var geo = new T.BufferGeometry().setFromPoints(pts.map(function (p) { return V(p); }));
      return add(new T.Line(geo, new T.LineBasicMaterial({ color: C(o.color, '#1D2433'), transparent: o.opacity != null, opacity: o.opacity == null ? 1 : o.opacity })));
    };

    // 매개변수 곡선 r(t) = [x, y, z]. 반환값 .progress(p) 로 처음 p(0~1) 만큼만 그린다.
    s.curve = function (fn, o) {
      o = o || {};
      var t0 = o.t ? o.t[0] : 0, t1 = o.t ? o.t[1] : 1, n = o.n || 200, pts = [];
      for (var i = 0; i <= n; i++) pts.push(V(fn(t0 + (t1 - t0) * i / n)));
      var curve = new T.CatmullRomCurve3(pts);
      var geo = new T.TubeGeometry(curve, n, o.radius || 0.03, 8, false);
      var m = new T.Mesh(geo, new T.MeshPhongMaterial({ color: C(o.color, '#E0703B') }));
      var total = geo.index.count;
      m.progress = function (p) { geo.setDrawRange(0, Math.max(0, Math.floor(total * clamp(p, 0, 1) / 3) * 3)); };
      m.at = function (p) { return curve.getPointAt(clamp(p, 0, 1)); };
      m.tangentAt = function (p) { return curve.getTangentAt(clamp(p, 0, 1)); };
      return add(m);
    };

    function surfaceMesh(pos, nu, nv, o) {
      var geo = new T.BufferGeometry();
      geo.setAttribute('position', new T.BufferAttribute(new Float32Array(pos), 3));
      var idx = [];
      for (var i = 0; i < nu; i++) for (var j = 0; j < nv; j++) {
        var a = i * (nv + 1) + j, b = a + 1, c = a + nv + 1, d = c + 1;
        idx.push(a, c, b, b, c, d);
      }
      geo.setIndex(idx);
      geo.computeVertexNormals();
      if (o.heightColor) {
        var lo = C(o.heightColor[0]), hi = C(o.heightColor[1]), zs = [], mn = 1e9, mx = -1e9, k, col = [];
        for (k = 2; k < pos.length; k += 3) { zs.push(pos[k]); mn = Math.min(mn, pos[k]); mx = Math.max(mx, pos[k]); }
        for (k = 0; k < zs.length; k++) { var c2 = lo.clone().lerp(hi, (zs[k] - mn) / ((mx - mn) || 1)); col.push(c2.r, c2.g, c2.b); }
        geo.setAttribute('color', new T.BufferAttribute(new Float32Array(col), 3));
      }
      var mat = new T.MeshPhongMaterial({ color: o.heightColor ? 0xffffff : C(o.color, '#4f7cff'), vertexColors: !!o.heightColor, side: T.DoubleSide,
        transparent: (o.opacity == null ? 0.88 : o.opacity) < 1, opacity: o.opacity == null ? 0.88 : o.opacity, shininess: 40 });
      var mesh = new T.Mesh(geo, mat);
      if (o.wire !== false) {
        mesh.add(new T.LineSegments(new T.WireframeGeometry(geo), new T.LineBasicMaterial({ color: C(o.wireColor, '#1D2433'), transparent: true, opacity: o.wireOpacity == null ? 0.18 : o.wireOpacity })));
      }
      return add(mesh);
    }

    // 곡면 z = f(x, y)
    s.surface = function (f, o) {
      o = o || {};
      var xr = o.x || [-2, 2], yr = o.y || [-2, 2], n = o.n || 40, pos = [];
      for (var i = 0; i <= n; i++) for (var j = 0; j <= n; j++) {
        var x = xr[0] + (xr[1] - xr[0]) * i / n, y = yr[0] + (yr[1] - yr[0]) * j / n, z = f(x, y);
        pos.push(x, y, isFinite(z) ? z : 0);
      }
      return surfaceMesh(pos, n, n, o);
    };

    // 매개변수 곡면 r(u, v) = [x, y, z]
    s.paramSurface = function (f, o) {
      o = o || {};
      var ur = o.u || [0, 1], vr = o.v || [0, 1], nu = o.nu || o.n || 40, nv = o.nv || o.n || 40, pos = [];
      for (var i = 0; i <= nu; i++) for (var j = 0; j <= nv; j++) {
        var p = f(ur[0] + (ur[1] - ur[0]) * i / nu, vr[0] + (vr[1] - vr[0]) * j / nv);
        pos.push(p[0], p[1], p[2]);
      }
      return surfaceMesh(pos, nu, nv, o);
    };

    // 평면: 한 점과 법선벡터
    s.plane = function (point, normal, o) {
      o = o || {};
      var size = o.size || 4;
      var m = new T.Mesh(new T.PlaneGeometry(size, size), new T.MeshPhongMaterial({ color: C(o.color, '#2F9E6E'), side: T.DoubleSide, transparent: true, opacity: o.opacity == null ? 0.45 : o.opacity }));
      m.position.copy(V(point));
      m.quaternion.setFromUnitVectors(new T.Vector3(0, 0, 1), V(normal).normalize());
      if (o.edges !== false) m.add(new T.LineSegments(new T.EdgesGeometry(m.geometry), new T.LineBasicMaterial({ color: C(o.color, '#2F9E6E') })));
      return add(m);
    };

    s.axes = function (o) {
      o = o || {};
      var size = o.size || 4, g = new T.Group(), prev = self.target;
      self.target = g;
      var names = o.names || ['x', 'y', 'z'], cols = o.colors || ['#D9534F', '#2F9E6E', '#2F6BFF'];
      [[size, 0, 0], [0, size, 0], [0, 0, size]].forEach(function (e, i) {
        s.arrow([0, 0, 0], e, { color: cols[i], width: o.width || 0.022, headLength: 0.28 });
        if (o.negative) s.line([[0, 0, 0], [-e[0], -e[1], -e[2]]], { color: cols[i], opacity: 0.35 });
        s.label(names[i], [e[0] * 1.06 + (i === 0 ? 0.2 : 0), e[1] * 1.06 + (i === 1 ? 0.2 : 0), e[2] * 1.06 + (i === 2 ? 0.2 : 0)], { color: cols[i], size: 0.34 });
      });
      if (o.ticks !== false) {
        for (var k = 1; k < size; k++) {
          [[k, 0, 0], [0, k, 0], [0, 0, k]].forEach(function (p, i) { s.point(p, { r: 0.03, color: cols[i] }); });
        }
      }
      self.target = prev; add(g);
      return g;
    };

    // xy 평면 위의 격자 (z 높이)
    s.grid = function (o) {
      o = o || {};
      var size = o.size || 6, div = o.divisions || size;
      var g = new T.GridHelper(size, div, C(o.color, '#B8B3A7'), C(o.color, '#D9D5CA'));
      g.rotation.x = Math.PI / 2; g.position.z = o.z || 0;
      return add(g);
    };

    s.vectorField = function (f, o) {
      o = o || {};
      var xr = o.x || [-2, 2], yr = o.y || [-2, 2], zr = o.z || [0, 0], n = o.n || 5, sc = o.scale == null ? 0.5 : o.scale, g = new T.Group();
      var prev = self.target; self.target = g;
      var nz = zr[0] === zr[1] ? 1 : n;
      for (var i = 0; i < n; i++) for (var j = 0; j < n; j++) for (var k = 0; k < nz; k++) {
        var x = xr[0] + (xr[1] - xr[0]) * (n === 1 ? 0.5 : i / (n - 1)), y = yr[0] + (yr[1] - yr[0]) * (n === 1 ? 0.5 : j / (n - 1));
        var z = nz === 1 ? zr[0] : zr[0] + (zr[1] - zr[0]) * k / (nz - 1);
        var v = f(x, y, z), len = Math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
        if (len < 1e-9) continue;
        s.arrow([x, y, z], [x + v[0] * sc, y + v[1] * sc, z + v[2] * sc], { color: o.color || '#4f7cff', width: 0.018, headLength: 0.16 });
      }
      self.target = prev; add(g);
      return g;
    };

    // 글자 표지판 (항상 화면을 향함). 유니코드 수식 문자 OK: x² ∂f/∂x ∫ √ π
    s.label = function (text, pos, o) {
      o = o || {};
      var size = o.size || 0.3, lines = String(text).split('\n'), px = 64;
      var cv = document.createElement('canvas'), ctx = cv.getContext('2d');
      var font = '800 ' + px + 'px Pretendard,"Noto Sans KR","Apple SD Gothic Neo","Malgun Gothic",sans-serif';
      ctx.font = font;
      var w = 0; lines.forEach(function (l) { w = Math.max(w, ctx.measureText(l).width); });
      cv.width = Math.ceil(w + 24); cv.height = Math.ceil(px * 1.25 * lines.length + 12);
      ctx = cv.getContext('2d'); ctx.font = font; ctx.textBaseline = 'middle'; ctx.textAlign = 'center';
      if (o.bg) { ctx.fillStyle = o.bg; ctx.fillRect(0, 0, cv.width, cv.height); }
      ctx.lineWidth = 8; ctx.strokeStyle = 'rgba(255,255,255,.92)'; ctx.fillStyle = C(o.color, '#1D2433').getStyle();
      lines.forEach(function (l, i) { var y = 6 + px * 1.25 * (i + 0.5); ctx.strokeText(l, cv.width / 2, y); ctx.fillText(l, cv.width / 2, y); });
      var tex = new T.CanvasTexture(cv);
      var sp = new T.Sprite(new T.SpriteMaterial({ map: tex, depthTest: false, transparent: true }));
      sp.scale.set(size * cv.width / px, size * cv.height / px, 1);
      sp.position.copy(V(pos)); sp.renderOrder = 10;
      return add(sp);
    };

    return s;
  };

  var Solvit3D = {
    version: 1,
    lesson: lesson,
    _player: null,
    goto: function (i) { if (Solvit3D._player) Solvit3D._player.go(i); },
    play: function () { var p = Solvit3D._player; if (p && !p.playing) p.toggle(); },
    state: function () { var p = Solvit3D._player; return p ? { index: p.index, steps: p.steps.length, p: p.p, playing: p.playing, error: p.errBox.style.display === 'block' ? p.errBox.textContent : '' } : null; },
  };
  global.Solvit3D = Solvit3D;
})(window);

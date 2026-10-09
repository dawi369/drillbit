/* Drillbit prototype — docs/design/prototype.js
   Each phone is a tiny state machine. `go(phone, state, data)` re-renders it. */
(() => {
  const $ = (s, r = document) => r.querySelector(s);
  const h = (html) => { const t = document.createElement('template'); t.innerHTML = html.trim(); return t.content.firstElementChild; };
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const reduce = () => document.documentElement.dataset.motion === 'reduce' || matchMedia('(prefers-reduced-motion: reduce)').matches && document.documentElement.dataset.motion !== 'full';
  const wait = (ms) => new Promise((r) => setTimeout(r, reduce() ? 1 : ms));

  const I = {
    x: '<svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M5 5l10 10M15 5L5 15"/></svg>',
    more: '<svg width="20" height="20" viewBox="0 0 20 20" fill="currentColor"><circle cx="4" cy="10" r="1.7"/><circle cx="10" cy="10" r="1.7"/><circle cx="16" cy="10" r="1.7"/></svg>',
    up: '<svg width="18" height="18" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10 16V4M4 10l6-6 6 6"/></svg>',
    chev: '<svg width="14" height="14" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M7 4l6 6-6 6"/></svg>',
    back: '<svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4l-6 6 6 6"/></svg>',
    check: '<svg width="16" height="16" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 10.5l4 4 8-9"/></svg>',
    mic: '<svg width="18" height="18" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"><rect x="7" y="2.5" width="6" height="10" rx="3"/><path d="M4 9.5a6 6 0 0 0 12 0M10 15.5V18"/></svg>',
    apple: '<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M16.4 12.7c0-2.4 2-3.6 2.1-3.7-1.1-1.7-2.9-1.9-3.5-1.9-1.5-.2-2.9.9-3.7.9-.8 0-1.9-.9-3.2-.8-1.6 0-3.1 1-4 2.4-1.7 3-.4 7.3 1.2 9.7.8 1.2 1.8 2.5 3 2.4 1.2 0 1.7-.8 3.2-.8 1.5 0 1.9.8 3.2.8 1.3 0 2.2-1.2 3-2.4.9-1.4 1.3-2.7 1.3-2.8 0 0-2.6-1-2.6-3.8zM14 5.6c.7-.8 1.1-1.9 1-3-1 0-2.1.7-2.8 1.5-.6.7-1.2 1.8-1 2.9 1 .1 2.1-.6 2.8-1.4z"/></svg>',
    logo: '<svg viewBox="0 -146 574 148" height="22" aria-label="Drillbit"><g fill="none" stroke="currentColor" stroke-width="24"><circle cx="51.5" cy="-50" r="39.5"/><circle cx="392" cy="-50" r="39.5"/><path d="M91 -146V0M139 -100V0M139 -50A39.5 39.5 0 0 1 178.5 -89.5M208.5 -100V0M256.5 -146V0M304.5 -146V0M352.5 -146V0M475.5 -100V0M531.5 -128V0M505.5 -88H561.5"/></g><g fill="var(--accent)"><circle cx="208.5" cy="-128" r="14"/><circle cx="475.5" cy="-128" r="14"/></g></svg>',
  };

  const status = `<div class="status"><span>9:41</span><div class="island"></div><span>●●●</span></div><div class="homebar"></div>`;
  const nav = (left, title, right) => `<div class="nav">${left ? `<button class="ic" data-act="${left}">${left === 'close' ? I.x : I.back}</button>` : '<span class="ic"></span>'}<div class="title">${title}</div>${right ? `<button class="ic" data-act="${right}">${I.more}</button>` : '<span class="ic"></span>'}</div>`;

  const STEPS = ['Requirements', 'Entities', 'API', 'Design', 'Deep dive'];
  const stepsBar = (now, done = now) => `<div class="steps" role="group" aria-label="Step ${now + 1} of 5: ${STEPS[now] || ''}"><div class="segs">${STEPS.map((s, i) => `<i class="${i < done ? 'done' : ''} ${i === now ? 'now' : ''}"></i>`).join('')}</div><div class="names">${STEPS.map((s, i) => i === now ? `<b>${s}</b>` : `<span class="${i < done ? 'done' : ''}">${s}</span>`).join(' · ')}</div></div>`;

  /* ---------------- lane canvas ---------------- */
  const LANES = ['Clients', 'Services', 'Data'];
  const KIND = { client: { lane: 0, k: 'client' }, api: { lane: 1, k: 'service' }, worker: { lane: 1, k: 'worker' }, queue: { lane: 2, k: 'queue' }, cache: { lane: 2, k: 'cache' }, db: { lane: 2, k: 'db' }, blob: { lane: 2, k: 'blob' }, ext: { lane: 1, k: 'external' } };
  const PALETTE = [
    ['client', 'Client', '<rect x="5" y="3" width="12" height="18" rx="2.5"/><path d="M9.5 18h3"/>'],
    ['api', 'Service', '<rect x="3" y="5" width="16" height="12" rx="2.5"/><path d="M7 11h8"/>'],
    ['worker', 'Worker', '<circle cx="11" cy="11" r="7"/><path d="M11 7v4l2.5 2"/>'],
    ['queue', 'Queue', '<path d="M3 7h16M3 11h16M3 15h16"/>'],
    ['cache', 'Cache', '<path d="M4 6h14v4H4zM4 12h14v4H4z"/>'],
    ['db', 'Database', '<ellipse cx="11" cy="6" rx="7" ry="2.5"/><path d="M4 6v10c0 1.4 3.1 2.5 7 2.5s7-1.1 7-2.5V6"/>'],
    ['blob', 'Blob store', '<path d="M6 17a4 4 0 0 1-.5-8A6 6 0 0 1 17 9a3.5 3.5 0 0 1 0 8z"/>'],
    ['ext', 'External', '<path d="M11 3v16M3 11h16"/><circle cx="11" cy="11" r="8"/>'],
  ];
  // Lanes are horizontal bands (Clients on top, Data at the bottom); requests read top-down.
  const W = 342, NW = 100, NH = 42, GAPX = 16, PERROW = 3, LANE_PAD = 18, LANE_GAP = 40;
  function layout(g) {
    const byLane = [[], [], []];
    g.nodes.forEach((n) => byLane[KIND[n.kind].lane].push(n));
    const pos = {}, bands = [];
    let y = 6;
    byLane.forEach((list, lane) => {
      const lines = Math.max(1, Math.ceil(list.length / PERROW));
      const top = y; y += LANE_PAD;
      list.forEach((n, i) => { const row = Math.floor(i / PERROW), col = i % PERROW, count = Math.min(PERROW, list.length - row * PERROW); const x0 = (W - (count * NW + (count - 1) * GAPX)) / 2; pos[n.id] = { x: x0 + col * (NW + GAPX), y: y + row * (NH + 14), lane }; });
      y += lines * NH + (lines - 1) * 14;
      bands.push({ lane, top, bottom: y });
      y += LANE_GAP;
    });
    return { pos, bands, height: y - LANE_GAP + 6 };
  }
  function edgePath(a, b, px = NW / 2, qx = NW / 2) {
    if (a.lane === b.lane) {
      const fwd = a.x < b.x;
      const sx = fwd ? a.x + NW : a.x, ex = fwd ? b.x : b.x + NW, yy = a.y + NH / 2;
      return { d: `M${sx} ${yy} L${ex} ${yy}`, mx: (sx + ex) / 2, my: yy };
    }
    const down = a.lane < b.lane;
    const sx = a.x + px, sy = down ? a.y + NH : a.y;
    const ex = b.x + qx, ey = down ? b.y : b.y + NH;
    const c = Math.abs(ey - sy) * .5 * (down ? 1 : -1);
    return { d: `M${sx} ${sy} C${sx} ${sy + c} ${ex} ${ey - c} ${ex} ${ey}`, mx: (sx + ex) / 2, my: (sy + ey) / 2 };
  }
  // Spread the edges touching each node's top/bottom side so they don't share one point.
  function ports(g, pos) {
    const side = {}; // id -> { top: [edgeIdx…], bottom: […] }
    g.edges.forEach((e, i) => { const a = pos[e.from], b = pos[e.to]; if (!a || !b || a.lane === b.lane) return; const down = a.lane < b.lane; (side[e.from] ??= { top: [], bottom: [] })[down ? 'bottom' : 'top'].push({ i, x: b.x }); (side[e.to] ??= { top: [], bottom: [] })[down ? 'top' : 'bottom'].push({ i, x: a.x }); });
    const out = {}; // edgeIdx -> { px, qx }
    Object.entries(side).forEach(([id, s]) => ['top', 'bottom'].forEach((k) => { const list = s[k].sort((u, v) => u.x - v.x); list.forEach((p, n) => { const x = NW * (n + 1) / (list.length + 1); const e = g.edges[p.i]; (out[p.i] ??= {})[e.from === id ? 'px' : 'qx'] = x; }); }));
    return out;
  }
  function canvasSVG(g, opt = {}) {
    const { pos, bands, height } = layout(g);
    const lanes = bands.map((b, i) => `<text class="lane-h" x="6" y="${b.top + 9}">${LANES[i]}</text>${i ? `<line class="lane-l" x1="0" y1="${b.top - LANE_GAP / 2}" x2="${W}" y2="${b.top - LANE_GAP / 2}"/>` : ''}`).join('');
    const pt = ports(g, pos);
    const edges = g.edges.map((e, i) => { const a = pos[e.from], b = pos[e.to]; if (!a || !b) return ''; const { d, mx, my } = edgePath(a, b, pt[i]?.px, pt[i]?.qx); const down = opt.down && (opt.down === e.from || opt.down === e.to); const lw = e.label ? e.label.length * 6.2 + 10 : 0; return `<path class="edge ${e.fresh ? 'new' : ''} ${down ? 'ghost' : ''}" d="${d}"></path>${e.label ? `<rect class="edge-lbg" x="${mx - lw / 2}" y="${my - 8}" width="${lw}" height="16" rx="8"/><text class="edge-l" x="${mx}" y="${my + 3.5}" text-anchor="middle">${esc(e.label)}</text>` : ''}`; }).join('');
    const nodes = g.nodes.map((n) => { const p = pos[n.id]; const sel = opt.sel === n.id ? 'sel' : ''; const down = opt.down === n.id ? 'down' : ''; return `<g class="node ${sel} ${down} ${n.fresh ? 'new' : ''}" data-node="${n.id}" transform="translate(${p.x} ${p.y})" tabindex="0" role="button" aria-label="${esc(n.label)}, ${KIND[n.kind].k}"><rect width="${NW}" height="${NH}"/><text x="10" y="18">${esc(n.label)}</text><text class="k" x="10" y="33">${KIND[n.kind].k}</text></g>`; }).join('');
    const pulse = opt.pulse ? (() => { const i = g.edges.findIndex((e) => e.from === opt.pulse[0] && e.to === opt.pulse[1]); if (i < 0) return ''; const e = g.edges[i]; const { d } = edgePath(pos[e.from], pos[e.to], pt[i]?.px, pt[i]?.qx); return `<circle class="pulse" r="4"><animateMotion dur="1.6s" repeatCount="indefinite" path="${d}"/></circle>`; })() : '';
    return `<svg viewBox="0 0 ${W} ${height}" width="${W}" height="${height}"><defs><marker id="arr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5 0 10z" fill="var(--ink-2)"/></marker></defs>${lanes}${edges}${nodes}${pulse}</svg>`;
  }
  const paletteHTML = () => `<div class="palette" role="toolbar" aria-label="Components">${PALETTE.map(([k, l, svg]) => `<button class="p" data-add="${k}" aria-label="Add ${l}"><svg viewBox="0 0 22 22" stroke-linecap="round" stroke-linejoin="round">${svg}</svg>${l}</button>`).join('')}</div>`;

  /* ---------------- shared data ---------------- */
  const Q = {
    title: 'Design a reliable job queue',
    prompt: 'A web app needs to run work later: emails, PDF exports, webhooks. Thousands of jobs an hour, some retried, none lost.',
    constraints: ['At-least-once is fine, duplicates are not', 'A worker can die at any moment', 'Keep it to things you could build this quarter'],
    opener: 'Let’s start with what the queue promises. Two things it must do, one thing it doesn’t have to.',
  };
  const graphSeed = () => ({ nodes: [{ id: 'web', kind: 'client', label: 'Web app' }, { id: 'api', kind: 'api', label: 'Enqueue API' }, { id: 'q', kind: 'queue', label: 'Jobs' }, { id: 'w', kind: 'worker', label: 'Worker' }, { id: 'db', kind: 'db', label: 'Job state' }], edges: [{ from: 'web', to: 'api' }, { from: 'api', to: 'q', label: 'push' }, { from: 'q', to: 'w', label: 'lease' }, { from: 'w', to: 'db', label: 'done' }] });

  /* ---------------- phones ---------------- */
  const phones = {};
  function define(id, states, initial) { phones[id] = { states, state: initial, data: {}, el: null }; }
  function go(id, state, data) { const p = phones[id]; p.state = state; if (data) Object.assign(p.data, data); render(id); }
  function render(id) {
    const p = phones[id]; const el = p.el;
    el.innerHTML = status + p.states[p.state](p.data, (s, d) => go(id, s, d), id);
    el.querySelectorAll('[data-go]').forEach((b) => b.addEventListener('click', () => go(id, b.dataset.go)));
    el.querySelectorAll('[data-hop]').forEach((b) => b.addEventListener('click', () => { const [pid, st] = b.dataset.hop.split(':'); go(pid, st); document.getElementById('f-' + pid)?.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'center' }); }));
    p.states[p.state].after?.(el, p.data, (s, d) => go(id, s, d));
    const doc = el.querySelector('.doc.scroll'); if (doc) doc.scrollTop = doc.scrollHeight;
  }

  /* ===== 1. Welcome ===== */
  const wdiag = (mode) => {
    // mode: idle | retry | check | fix
    const req = mode === 'idle' ? '<circle class="req die" cx="118" cy="52" r="5"/>'
      : mode === 'retry' ? '<circle class="req a" cx="118" cy="52" r="5"/><circle class="req b" cx="118" cy="52" r="5"/>'
      : mode === 'check' ? '<circle class="req die" cx="118" cy="52" r="5"/>'
      : '<circle class="req a" cx="118" cy="52" r="5"/><circle class="req skip" cx="118" cy="52" r="5"/>';
    return `<div class="wdiag" aria-hidden="true"><svg viewBox="0 0 342 104" style="padding-right:14px">
      <rect class="box" x="6" y="30" width="104" height="44"/><text x="18" y="49">Your server</text><text class="sub" x="18" y="64">push ${mode === 'fix' ? 'id 7f3a' : ''}</text>
      <path class="wire" d="M110 52H230"/>
      <rect class="box" x="232" y="30" width="104" height="44" rx="14"/><text x="246" y="49">Their phone</text><text class="sub" x="246" y="64">${mode === 'retry' ? 'buzz · buzz' : mode === 'fix' ? 'buzz once' : 'waiting'}</text>
      ${req}
      <path class="x ${mode === 'idle' || mode === 'check' ? 'on' : ''}" d="M212 44l12 16M224 44l-12 16"/>
      <text class="idem ${mode === 'fix' ? 'on' : ''}" x="171" y="22" text-anchor="middle">same id → skipped</text>
      <g class="buzz ${mode === 'retry' || mode === 'fix' ? 'on' : ''}"><path class="wire" d="M341 40q6 12 0 24" stroke="var(--accent)"/></g>
      <g class="buzz ${mode === 'retry' ? 'on2' : ''}"><path class="wire" d="M348 36q8 16 0 32" stroke="var(--accent)"/></g>
    </svg></div>`;
  };
  const WLINE = { idle: 'Your push to their phone timed out. Now what?', retry: 'It had gone out the first time. Their phone buzzed twice.', check: 'Smart. But the server never answered, so you can’t tell if it went out.', fix: 'Same request, same result. That’s an idempotency key.' };
  const WACTS = { idle: '<button class="chip" data-go="retry">Retry it</button><button class="chip" data-go="check">Check first</button>', retry: '<button class="chip on" data-go="fix">Retry with the same request ID</button>', check: '<button class="chip on" data-go="fix">Retry with the same request ID</button>', fix: '<button class="chip" data-go="idle">Again</button>' };
  const welcome = (mode) => () => `<div class="screen center">
      <div style="margin-bottom:28px;color:var(--ink)">${I.logo}</div>
      <p class="t-display" style="margin-bottom:10px;font-size:28px">Other apps teach system design. We put you in the interview.</p>
      <p class="t-small" style="margin:0 0 26px">Knowing it isn’t the test. Saying it out loud to someone who pushes back is.</p>
      <div class="t-micro" style="margin-bottom:8px">Try one · 20 seconds</div>
      ${wdiag(mode)}
      <p class="t-read" style="margin:14px 0 14px; min-height:54px">${WLINE[mode]}</p>
      <div class="chips" style="min-height:40px">${WACTS[mode]}</div>
      ${mode === 'fix' ? `<div class="row" style="margin-top:22px;gap:14px"><img class="bit hop" src="assets/bit.png" alt="" width="40" height="44"><p class="t-small" style="margin:0">That’s the kind of hole the interviewer pokes at. Then it tells you how to patch it.</p></div>` : ''}
      <div class="grow"></div>
      <button class="btn primary full" data-hop="signin:main">Get started</button>
    </div>`;
  define('welcome', { idle: welcome('idle'), retry: welcome('retry'), check: welcome('check'), fix: welcome('fix') }, 'idle');

  /* ===== 2. Sign in ===== */
  define('signin', { main: () => `<div class="screen center" style="text-align:center">
      <div class="grow"></div>
      <div style="color:var(--ink);display:flex;justify-content:center">${I.logo}</div>
      <p class="t-title" style="margin:22px 0 6px">Ready when you are.</p>
      <p class="t-small" style="margin:0">Sign in to keep your reps and feedback.</p>
      <div class="grow"></div>
      <div class="stack">
        <button class="btn primary full" data-hop="setup:main">${I.apple} Sign in with Apple</button>
        <button class="btn ghost full" data-hop="setup:main">Continue with Google</button>
        <button class="btn ghost full" data-hop="setup:main">Continue with GitHub</button>
      </div>
    </div>` }, 'main');

  /* ===== 3. Setup (one screen, two questions) ===== */
  const WHEN = [['week', 'This week'], ['month', 'This month'], ['later', 'Later this year'], ['none', 'No date, just sharpening']];
  const LEVEL = [['junior', 'Junior', 'We start with the building blocks and work through them together.'], ['mid', 'Mid-level', 'We skip the definitions and push on your decisions.'], ['senior', 'Senior', 'Expect tradeoffs and failure modes, not definitions.'], ['staff', 'Staff+', 'Straight to the hard tradeoffs. Expect pushback.']];
  define('setup', { main: (d) => `<div class="screen">
      ${nav(null, '', null)}
      <p class="t-title" style="margin-bottom:18px">When’s the interview?</p>
      <div class="chips" style="margin-bottom:34px">${WHEN.map(([k, l]) => `<button class="chip" data-when="${k}" aria-pressed="${d.when === k}">${l}</button>`).join('')}</div>
      <p class="t-title" style="margin-bottom:18px">What level?</p>
      <div class="chips">${LEVEL.map(([k, l]) => `<button class="chip" data-level="${k}" aria-pressed="${d.level === k}">${l}</button>`).join('')}</div>
      <p class="t-body muted" style="margin:16px 0 0;min-height:48px">${(LEVEL.find((x) => x[0] === d.level) || [])[2] || ''}</p>
      ${d.when === 'week' ? `<p class="t-small" style="margin:8px 0 0">Tight. We’ll keep each rep to one decision.</p>` : ''}
      <div class="grow"></div>
      <p class="t-small" style="margin:0 0 12px">Everything else has a default. Change it later in Settings.</p>
      <button class="btn primary full" ${d.when && d.level ? '' : 'disabled'} data-hop="first:writing">Pick my first question</button>
    </div>` }, 'main');
  phones.setup.states.main.after = (el, d, go) => {
    el.querySelectorAll('[data-when]').forEach((b) => b.addEventListener('click', () => go('main', { when: b.dataset.when })));
    el.querySelectorAll('[data-level]').forEach((b) => b.addEventListener('click', () => go('main', { level: b.dataset.level })));
  };
  phones.setup.data = { when: null, level: 'mid' };

  /* ===== 4. First question ===== */
  const qPreview = (d, writing) => `<div class="screen">
      ${nav(null, '', null)}
      <div class="grow scroll">
        <div class="t-micro" style="margin-bottom:10px">Your first question</div>
        <p class="t-display ${writing ? 'caret' : ''}" style="margin-bottom:14px">${writing ? esc(Q.title.slice(0, d.n || 0)) : esc(Q.title)}</p>
        ${writing ? '' : `<p class="t-read" style="margin-bottom:16px">${esc(Q.prompt)}</p>
        <div class="lines">${Q.constraints.map((c, i) => `<div class="ln"><span class="n">${i + 1}</span><span>${esc(c)}</span></div>`).join('')}</div>
        <div class="hr"></div>
        <p class="t-small" style="margin:0 0 10px">About 15 minutes. The interviewer walks you through five steps:</p>
        ${stepsBar(-1, 0)}`}
      </div>
      <div class="stack" style="padding-top:12px">
        ${writing ? '<p class="t-small" style="text-align:center;margin:0 0 8px">Writing your question…</p>' : '<button class="btn text full" data-go="writing">Another question</button>'}
        <button class="btn primary full" ${writing ? 'disabled' : ''} data-hop="room:s0">Start</button>
      </div>
    </div>`;
  define('first', { writing: (d) => qPreview(d, true), ready: (d) => qPreview(d, false) }, 'writing');
  phones.first.states.writing.after = async (el, d, go) => {
    const target = Q.title.length; let n = 0; const token = (d.token = Symbol());
    while (n < target) { await wait(45); if (d.token !== token) return; n++; const t = el.querySelector('.t-display'); if (t) t.textContent = Q.title.slice(0, n); }
    await wait(350); if (d.token !== token) return; go('ready');
  };

  /* ===== 5. Interview room ===== */
  const roomNav = (step) => nav('close', `<span class="serif">Job queue</span>`, 'menu');
  const turn = (who, text, cls = '') => `<div class="turn"><div class="who ${who === 'You' ? 'me' : ''}">${who}</div><p class="say ${cls}">${text}</p></div>`;
  const typing = () => `<div class="turn"><div class="who">Interviewer</div><div class="typing" aria-label="Interviewer is replying"><i></i><i></i><i></i></div></div>`;

  // Step 0: requirements, with a numbered composer and a tiny step (move)
  const REQ_MOVE = { q: 'One of these isn’t a functional requirement. Which?', opts: [['Retry a failed job', false], ['No job runs twice', true], ['Run jobs in priority order', false]], why: { 'No job runs twice': 'Right. That’s a guarantee about <b>how</b> the queue behaves, not <b>what</b> it does. It’ll drive the design later.', other: 'That one’s a feature the queue does. The odd one out is <b>No job runs twice</b>: a property of the system, not a feature of it.' } };
  define('room', {
    s0: (d) => `<div class="screen">${roomNav(0)}${stepsBar(0)}
      <div class="grow scroll doc">
        ${turn('Interviewer', esc(Q.opener))}
      </div>
      <div class="composer"><div class="label">Requirements · one per line</div>
        <div class="lines">${[d.r1, d.r2, d.r3].map((r, i) => `<div class="ln"><span class="n">${i + 1}</span><span class="field" contenteditable="true" data-ph="${['Must…', 'Must…', 'Doesn’t have to…'][i]}" data-r="${i}">${esc(r || '')}</span></div>`).join('')}</div>
        <div class="bar"><button class="btn text" data-go="nudge0">Need a nudge?</button><button class="send" aria-label="Send" data-go="s0sent" ${d.r1 ? '' : 'disabled'}>${I.up}</button></div>
      </div>
    </div>`,
    nudge0: (d) => phones.room.states.s0(d) + `<div class="scrim" data-go="s0"></div><div class="sheet"><div class="t-micro" style="margin-bottom:8px">Nudge</div><p class="t-read" style="margin-bottom:16px">Think about what the caller is promised when enqueue returns 200. Then what the worker is promised when it picks a job up.</p><button class="btn primary full" data-go="s0">Got it</button></div>`,
    s0sent: (d) => `<div class="screen">${roomNav(0)}${stepsBar(d.pick ? 1 : 0)}
      <div class="grow scroll doc">
        ${turn('Interviewer', esc(Q.opener))}
        <div class="turn"><div class="who me">You</div><div class="lines sent">${[d.r1, d.r2, d.r3].filter(Boolean).map((r, i) => `<div class="ln"><span class="n">${i + 1}</span><span>${esc(r)}</span></div>`).join('')}</div></div>
        ${d.replied ? turn('Interviewer', 'Good. “Not lost” is the big one. ' + esc(REQ_MOVE.q)) : typing()}
        ${d.replied ? `<div class="chips" style="margin-top:-6px">${REQ_MOVE.opts.map(([o, ok]) => `<button class="chip soft ${d.pick ? (ok ? 'right' : d.pick === o ? 'wrong' : '') : ''}" data-move="${esc(o)}" aria-pressed="${d.pick === o}" ${d.pick ? 'disabled' : ''}>${esc(o)}</button>`).join('')}</div>` : ''}
        ${d.pick ? `<div class="why">${REQ_MOVE.why[d.pick] || REQ_MOVE.why.other}</div>` : ''}
        ${d.pick ? turn('Interviewer', 'Keep that one in your pocket. Now name the things this system has to remember.') : ''}
      </div>
      <div class="composer"><div class="label">${d.pick ? 'Entities' : 'Your reply'}</div>
        <div class="field" contenteditable="true" data-ph="${d.pick ? 'Job, Attempt, …' : 'Answer or ask a question…'}"></div>
        <div class="bar"><button class="btn text" data-go="nudge0">Need a nudge?</button><button class="send" aria-label="Send" ${d.pick ? 'data-hop="room:s3"' : 'disabled'}>${I.up}</button></div>
      </div>
    </div>`,
    // Step 3: Design on the lane canvas
    s3: (d) => `<div class="screen">${roomNav(3)}${stepsBar(3)}
      <div class="grow scroll doc" style="gap:12px">
        ${turn('Interviewer', 'Sketch the high-level design. Start with what accepts a job and work towards what runs it.')}
        <div class="canvas" aria-label="Design canvas">${canvasSVG(d.g, { sel: d.sel })}${d.g.nodes.length === 0 ? '<div class="hint">Tap a part below to place it</div>' : d.sel ? '' : d.g.edges.length === 0 && d.g.nodes.length > 1 ? '<div class="hint">Tap a part, then another, to connect them</div>' : ''}</div>
        <div class="seltools">${d.sel ? `<span>${esc(d.g.nodes.find((n) => n.id === d.sel)?.label)}</span><button data-ren>Rename</button><button class="danger" data-del>Delete</button><button data-unsel>Done</button>` : `<span class="quiet">${d.g.nodes.length} parts · ${d.g.edges.length} connections</span>`}</div>
      </div>
      <div class="composer" style="border-top:0;padding-top:0">
        ${paletteHTML()}
        <div class="field" contenteditable="true" data-ph="Say what happens on enqueue, in a sentence…" style="margin-top:6px"></div>
        <div class="bar"><button class="btn text" data-go="s3">Need a nudge?</button><button class="send" aria-label="Send" data-go="s3sent" ${d.g.edges.length ? '' : 'disabled'}>${I.up}</button></div>
      </div>
    </div>`,
    s3sent: (d) => `<div class="screen">${roomNav(3)}${stepsBar(3)}
      <div class="grow scroll doc" style="gap:12px">
        ${turn('You', 'Enqueue writes the job and pushes it. Workers lease a job, do it, write done.', 'sent')}
        <div class="canvas">${canvasSVG(d.g, { down: d.replied ? 'w' : null, pulse: d.replied ? null : ['q', 'w'] })}</div>
        ${d.replied ? turn('Interviewer', 'Your <b>Worker</b> writes <i>done</i> to <b>Job state</b>, then acks <b>Jobs</b>. Say it dies in between. What does the next worker see?') : typing()}
      </div>
      <div class="composer"><div class="label">Your reply</div>
        <div class="field" contenteditable="true" data-ph="Answer or ask a question…"></div>
        <div class="bar"><button class="btn text">Need a nudge?</button><button class="send" aria-label="Send" data-hop="room:menu">${I.up}</button></div>
      </div>
    </div>`,
    menu: (d) => phones.room.states.s3sent({ ...d, replied: true }) + `<div class="scrim" data-go="s3sent"></div><div class="menu" role="menu"><button data-go="s3sent">Show an example</button><button data-go="s3sent">Session style <span class="quiet">Guided</span></button><button data-go="s3sent">Full question</button><button data-go="finish">Finish interview</button><button class="danger" data-go="s3sent">Skip question</button></div>`,
    finish: (d) => phones.room.states.s3sent({ ...d, replied: true }) + `<div class="scrim"></div><div class="alert" role="alertdialog"><div class="body"><b>Finish interview?</b><p>Your answers and the diagram are saved for review.</p></div><div class="acts"><button data-go="s3sent">Keep going</button><button data-hop="feedback:pending">Finish</button></div></div>`,
  }, 's0');
  phones.room.data = { r1: '', r2: '', r3: '', g: { nodes: [], edges: [] }, sel: null };
  phones.room.states.s0.after = (el, d, go) => {
    el.querySelectorAll('[data-r]').forEach((f) => f.addEventListener('input', () => { d['r' + (Number(f.dataset.r) + 1)] = f.textContent.trim(); el.querySelector('.send').disabled = !d.r1; }));
    const f = el.querySelector('[data-r="0"]'); if (f && !d.r1) { f.textContent = ''; }
  };
  phones.room.states.s0sent.after = async (el, d, go) => {
    if (!d.replied) { await wait(1400); d.replied = true; go('s0sent'); return; }
    el.querySelectorAll('[data-move]').forEach((b) => b.addEventListener('click', () => go('s0sent', { pick: b.dataset.move })));
  };
  phones.room.states.s3.after = (el, d, go) => {
    el.querySelectorAll('[data-add]').forEach((b) => b.addEventListener('click', () => {
      const kind = b.dataset.add; const n = d.g.nodes.filter((x) => x.kind === kind).length;
      const label = PALETTE.find((p) => p[0] === kind)[1] + (n ? ' ' + (n + 1) : '');
      d.g.nodes.forEach((x) => delete x.fresh); d.g.edges.forEach((x) => delete x.fresh);
      const id = kind + Date.now().toString(36); d.g.nodes.push({ id, kind, label, fresh: true }); go('s3', { sel: null });
    }));
    el.querySelectorAll('[data-node]').forEach((n) => n.addEventListener('click', () => {
      const id = n.dataset.node;
      d.g.nodes.forEach((x) => delete x.fresh); d.g.edges.forEach((x) => delete x.fresh);
      if (d.sel && d.sel !== id) { if (!d.g.edges.some((e) => e.from === d.sel && e.to === id)) d.g.edges.push({ from: d.sel, to: id, fresh: true }); go('s3', { sel: null }); }
      else go('s3', { sel: d.sel === id ? null : id });
    }));
    el.querySelector('[data-unsel]')?.addEventListener('click', () => go('s3', { sel: null }));
    el.querySelector('[data-del]')?.addEventListener('click', () => { d.g.nodes = d.g.nodes.filter((x) => x.id !== d.sel); d.g.edges = d.g.edges.filter((e) => e.from !== d.sel && e.to !== d.sel); go('s3', { sel: null }); });
    el.querySelector('[data-ren]')?.addEventListener('click', () => { const nd = d.g.nodes.find((x) => x.id === d.sel); const v = prompt('Name', nd.label); if (v) { nd.label = v.slice(0, 14); go('s3'); } });
  };
  phones.room.states.s3sent.after = async (el, d, go) => { if (!d.replied3) { await wait(1600); d.replied3 = true; d.replied = true; go('s3sent'); } };
  // Preload the design step with the seed graph when jumping there directly.
  const origS3 = phones.room.states.s3; phones.room.states.s3 = (d) => { if (!d.g.nodes.length && !d.touched) { d.g = graphSeed(); } d.touched = true; return origS3(d); }; phones.room.states.s3.after = origS3.after;
  const origS3s = phones.room.states.s3sent; phones.room.states.s3sent = (d) => { if (!d.g.nodes.length) d.g = graphSeed(); if (!d.g.nodes.find((n) => n.id === 'w')) d.g = graphSeed(); return origS3s(d); }; phones.room.states.s3sent.after = origS3s.after;

  /* ===== 6. Feedback ===== */
  const PATHREV = [['Requirements', 'covered', 'No job runs twice'], ['Entities', 'covered', 'Job, Attempt, Lease'], ['API', 'thin', 'enqueue(job) → id'], ['Design', 'covered', 'Workers lease a job, do it, write done.'], ['Deep dive', 'missed', '']];
  const G = { covered: ['●', 'var(--ok)'], thin: ['◐', 'var(--accent)'], missed: ['○', 'var(--ink-3)'] };
  define('feedback', {
    pending: () => `<div class="screen center" style="text-align:center"><div class="grow"></div><p class="t-read muted">Saved. The interviewer is writing up notes…</p><div class="typing" style="justify-content:center;margin-top:8px"><i></i><i></i><i></i></div><div class="grow"></div></div>`,
    main: (d) => `<div class="screen">
      ${nav(null, '', null)}
      <div class="grow scroll">
        <div class="row" style="gap:12px;margin-bottom:14px"><img class="bit hop" src="assets/bit.png" alt="" width="36" height="40"><p class="t-display" style="margin:0">Here’s how it went.</p></div>
        <div class="stack" style="gap:18px;margin-bottom:22px">
          <div class="fb-lead"><div class="k good">What worked</div><p class="quote">Workers lease a job, do it, write done.</p><p class="obs">Leases are the right call: a dead worker’s job comes back on its own.</p></div>
          <div class="fb-lead"><div class="k fix">What to fix</div><p class="quote">…write done, then ack.</p><p class="obs">Between those two writes a crash runs the job twice. Give each job a stable id and check it before you run.</p></div>
        </div>
        <div class="t-micro" style="margin-bottom:4px">The five steps</div>
        <div class="path-rev">${PATHREV.map(([n, s, q]) => `<div class="pr"><span class="g" style="color:${G[s][1]}">${G[s][0]}</span><div class="nm">${n}<span>${s}</span></div>${q ? `<p class="q">${esc(q)}</p>` : '<p class="q" style="font-style:italic">Ran out of time before this one.</p>'}</div>`).join('')}</div>
        <div class="inline-ask" style="margin-top:18px">
          <p class="t-body" style="margin:0">Want a nudge tomorrow at 9?</p>
          <div class="chips"><button class="chip" data-go="main">Sure</button><button class="chip" data-go="main">No thanks</button></div>
        </div>
      </div>
      <div class="stack" style="padding-top:12px">
        <button class="btn primary full" data-hop="home:gate">Done</button>
      </div>
    </div>`,
  }, 'pending');
  phones.feedback.states.pending.after = async (el, d, go) => { await wait(1800); go('main'); };

  /* ===== 7. Home after first rep (gate) ===== */
  define('home', {
    gate: () => `<div class="screen">
      <div class="nav"><span class="ic"></span><span></span><button class="ic" aria-label="Settings"><svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="10" cy="10" r="2.6"/><path d="M10 2.5v2M10 15.5v2M2.5 10h2M15.5 10h2M4.7 4.7l1.4 1.4M13.9 13.9l1.4 1.4M4.7 15.3l1.4-1.4M13.9 6.1l1.4-1.4"/></svg></button></div>
      <p class="t-display" style="margin-bottom:8px">One rep in.</p>
      <p class="t-read muted" style="margin-bottom:26px">Your fix to carry: check the job id before you run it.</p>
      <div class="t-micro" style="margin-bottom:8px">Next rep</div>
      <p class="t-title" style="margin-bottom:6px">Design a rate limiter</p>
      <p class="t-small" style="margin:0 0 14px">Picked from today’s gap: the same “did this already happen?” question, under load.</p>
      <p class="t-body" style="margin:0 0 16px">Your free rep comes back <b>Thursday</b>.</p>
      <div class="row"><button class="btn primary">See plans</button><button class="btn text">Remind me Thursday</button></div>
      <div class="grow"></div>
      <div class="hr"></div>
      <div class="row between"><div><div class="t-micro">Keep this</div><p class="t-body" style="margin:2px 0 0">1 card from today</p></div><button class="chip">Review ${I.chev}</button></div>
    </div>`,
  }, 'gate');

  /* ---------------- mount ---------------- */
  document.querySelectorAll('.phone[data-phone]').forEach((el) => { const id = el.dataset.phone; const p = phones[id]; if (!p) return; p.el = el; if (el.dataset.state) p.state = el.dataset.state; render(id); });
  // separate instances of the room at a given step
  document.querySelectorAll('.phone[data-clone]').forEach((el) => {
    const [src, state] = el.dataset.clone.split(':'); const id = src + '_' + state; const base = phones[src];
    phones[id] = { states: base.states, state, data: JSON.parse(JSON.stringify({ ...base.data, g: graphSeed(), r1: 'Jobs are never lost once enqueue returns 200', r2: 'A job runs even if the worker that took it dies', r3: 'Exactly-once' })), el };
    phones[id].data.touched = true; render(id);
  });

  /* theme & motion */
  $('#theme')?.addEventListener('click', (e) => { const b = e.target.closest('button'); if (!b) return; document.documentElement.dataset.theme = b.dataset.v; $('#theme').querySelectorAll('button').forEach((x) => x.setAttribute('aria-pressed', x === b)); });
  $('#motion')?.addEventListener('click', (e) => { const b = e.target.closest('button'); if (!b) return; document.documentElement.dataset.motion = b.dataset.v; $('#motion').querySelectorAll('button').forEach((x) => x.setAttribute('aria-pressed', x === b)); });
  window.proto = { go, phones };
})();

/* Drillbit prototype — recreation of the shipped app. Each phone is a tiny state machine; go(phone, state, data) re-renders. */
(() => {
  const $ = (s, r = document) => r.querySelector(s);
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const reduce = () => document.documentElement.dataset.motion === 'reduce';
  const wait = (ms) => new Promise((r) => setTimeout(r, reduce() ? 1 : ms));

  const I = {
    x: '<svg width="22" height="22" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M5 5l10 10M15 5L5 15"/></svg>',
    more: '<svg width="22" height="22" viewBox="0 0 20 20" fill="currentColor"><circle cx="4" cy="10" r="1.8"/><circle cx="10" cy="10" r="1.8"/><circle cx="16" cy="10" r="1.8"/></svg>',
    up: '<svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M10 16V4M4 10l6-6 6 6"/></svg>',
    chev: '<svg width="16" height="16" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M7 4l6 6-6 6"/></svg>',
    down: '<svg width="16" height="16" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7l6 6 6-6"/></svg>',
    back: '<svg width="22" height="22" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4l-6 6 6 6"/></svg>',
    check: '<svg width="16" height="16" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M4 10.5l4 4 8-9"/></svg>',
    gear: '<svg width="22" height="22" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="10" cy="10" r="2.6"/><path d="M10 2.5v2M10 15.5v2M2.5 10h2M15.5 10h2M4.7 4.7l1.4 1.4M13.9 13.9l1.4 1.4M4.7 15.3l1.4-1.4M13.9 6.1l1.4-1.4"/></svg>',
    wave: '<svg width="18" height="18" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M3 8v4M6.5 5v10M10 3v14M13.5 6v8M17 8v4"/></svg>',
    bell: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M5 14V9a5 5 0 0 1 10 0v5l1.5 2h-13zM8 17.5a2 2 0 0 0 4 0"/></svg>',
    bulb: '<svg width="22" height="22" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M7 15h6M8 17.5h4M10 2.5a5 5 0 0 0-3 9c.6.5 1 1.2 1 2h4c0-.8.4-1.5 1-2a5 5 0 0 0-3-9z"/></svg>',
    apple: '<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M16.4 12.7c0-2.4 2-3.6 2.1-3.7-1.1-1.7-2.9-1.9-3.5-1.9-1.5-.2-2.9.9-3.7.9-.8 0-1.9-.9-3.2-.8-1.6 0-3.1 1-4 2.4-1.7 3-.4 7.3 1.2 9.7.8 1.2 1.8 2.5 3 2.4 1.2 0 1.7-.8 3.2-.8 1.5 0 1.9.8 3.2.8 1.3 0 2.2-1.2 3-2.4.9-1.4 1.3-2.7 1.3-2.8 0 0-2.6-1-2.6-3.8zM14 5.6c.7-.8 1.1-1.9 1-3-1 0-2.1.7-2.8 1.5-.6.7-1.2 1.8-1 2.9 1 .1 2.1-.6 2.8-1.4z"/></svg>',
    logo: '<svg viewBox="0 -146 574 148" aria-label="Drillbit"><g fill="none" stroke="currentColor" stroke-width="24"><circle cx="51.5" cy="-50" r="39.5"/><circle cx="392" cy="-50" r="39.5"/><path d="M91 -146V0M139 -100V0M139 -50A39.5 39.5 0 0 1 178.5 -89.5M208.5 -100V0M256.5 -146V0M304.5 -146V0M352.5 -146V0M475.5 -100V0M531.5 -128V0M505.5 -88H561.5"/></g><g fill="var(--logo-dot)"><circle cx="208.5" cy="-128" r="14"/><circle cx="475.5" cy="-128" r="14"/></g></svg>',
    mic: '<svg viewBox="0 0 24 24"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/></svg>',
    micoff: '<svg viewBox="0 0 24 24"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3M4 4l16 16"/></svg>',
    list: '<svg viewBox="0 0 24 24"><path d="M5 7h14M5 12h14M5 17h9"/></svg>',
    xs: '<svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18"/></svg>',
    tabHome: '<svg viewBox="0 0 24 24"><path d="M4 11l8-7 8 7v9H4z"/><path d="M10 20v-6h4v6"/></svg>',
    tabRecall: '<svg viewBox="0 0 24 24"><rect x="4" y="6" width="16" height="12" rx="2"/><path d="M8 3v4M16 3v4"/></svg>',
    tabLib: '<svg viewBox="0 0 24 24"><path d="M5 4h4v16H5zM10 4h4v16h-4zM15.5 5l3.5 1-3 14-3.5-1z"/></svg>',
  };
  const status = `<div class="status"><span>9:41</span><div class="island"></div><span>●●●</span></div><div class="homebar"></div>`;
  const nav = (lead, title, trail) => `<div class="nav"><div class="lead">${lead || ''}</div><div class="ttl">${title || ''}</div><div class="trail">${trail || ''}</div></div>`;
  const tabbar = (on) => `<div class="tabbar">${[['home', 'Home', I.tabHome], ['recall', 'Recall', I.tabRecall], ['library', 'Library', I.tabLib]].map(([k, l, s]) => `<button class="tab ${on === k ? 'on' : ''}" data-hop="${k}:default">${s}${l}</button>`).join('')}</div>`;
  const bit = (w, cls = '') => `<img class="bit ${cls}" src="assets/bit.png" alt="" width="${w}" height="${Math.round(w * 1.1)}">`;
  const bitAsks = (text, read) => `<div class="bitasks">${bit(64)}<div class="bubble ${read ? 'read' : ''}">${text}</div></div>`;

  const Q = {
    title: 'Design a reliable job queue',
    prompt: 'Design a durable job queue that survives worker failures. Explain how workers claim jobs, how retries avoid duplicate side effects and how accepted work is recovered after a crash.',
    opener: 'You’ve designed a few systems, so let’s skip the basics. A worker can crash at any point. What should a client be able to rely on?',
    followUp: 'What happens if a worker stops after completing the operation but before acknowledging it?',
    path: ['Pin down what the queue promises', 'Sketch the job lifecycle', 'Handle worker failures', 'Make retries safe'],
    choices: ['Store a done marker per job', 'Make the work itself idempotent', 'Not sure, show me'],
    nudge: 'Consider what a retry can know about an operation that already happened.',
    example: 'For example, give each logical operation a stable key and store its result in the same transaction as the state change.',
  };

  /* --------------- engine --------------- */
  const phones = {};
  const define = (id, states, initial, data = {}) => { phones[id] = { states, state: initial, data, el: null }; };
  const defaults = {};
  function go(id, state, data) { const p = phones[id]; if (!p) return; if (state === 'default') state = defaults[id] || Object.keys(p.states)[0]; p.state = state; if (data) Object.assign(p.data, data); render(id); }
  function render(id) {
    const p = phones[id]; if (!p.el) return;
    const g = (s, d) => go(id, s, d);
    p.el.innerHTML = status + p.states[p.state](p.data, g);
    p.el.querySelectorAll('[data-go]').forEach((b) => b.addEventListener('click', (e) => { e.stopPropagation(); go(id, b.dataset.go); }));
    p.el.querySelectorAll('[data-set]').forEach((b) => b.addEventListener('click', (e) => { e.stopPropagation(); const [k, v] = b.dataset.set.split('='); go(id, p.state, { [k]: v === 'true' ? true : v === 'false' ? false : v }); }));
    p.el.querySelectorAll('[data-hop]').forEach((b) => b.addEventListener('click', (e) => { e.stopPropagation(); const [pid, st] = b.dataset.hop.split(':'); go(pid, st); document.getElementById('f-' + pid)?.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'center' }); }));
    p.states[p.state].after?.(p.el, p.data, g);
    const doc = p.el.querySelector('.doc.scroll'); if (doc) doc.scrollTop = doc.scrollHeight;
  }

  /* ===== Welcome (WelcomeView + RetryExample) ===== */
  const RC = (t, id, st, cls) => `<div class="rcpt"><span class="ico">${I.bell}</span><span class="t">${t}<small>request ${id}</small></span><span class="st ${cls || ''}">${st}</span></div>`;
  const W = {
    idle: { line: 'Your push to their phone timed out. Now what?', rc: RC('Push notification', '7f3a', 'Timed out', 'bad'), acts: '<button class="chip" data-go="retry">Retry it</button><button class="chip ghost" data-go="check">Check first</button>' },
    check: { line: 'Smart. But the server never answered, so you can’t tell if it went out.', rc: RC('Push notification', '7f3a', 'No answer'), acts: '<button class="chip" data-go="fix">Retry with the same request ID</button>' },
    retry: { line: 'Oops. It went out the first time. Their phone buzzed twice.', rc: RC('Push notification', '7f3a', 'Delivered', 'ok') + RC('Push notification', 'b21c', 'Delivered again', 'bad'), acts: '<button class="chip" data-go="fix">Retry with the same request ID</button>' },
    fix: { line: 'Same request, same result. That’s an idempotency key.', rc: RC('Push notification', '7f3a', 'Delivered', 'ok') + RC('Push notification', '7f3a', 'Duplicate skipped', 'ok'), acts: '<p class="sub" style="margin-bottom:10px">That’s the kind of hole Drillbit pokes. Then it tells you how to patch it.</p><button class="chip ghost" data-go="idle">Again</button>' },
  };
  const welcome = (m) => () => `<div class="screen">
      <div class="grow scroll">
        <div class="logo" style="margin-bottom:22px">${I.logo}</div>
        <p class="eyebrow">System design mock rounds</p>
        <p class="display" style="margin-bottom:10px">Grills you like<br>the real one.<br>Wants you to pass.</p>
        <p class="sub" style="margin-bottom:28px">Talk it through or type it out. Get honest notes on what to fix.</p>
        <p class="eyebrow">Try one · 20 seconds</p>
        <div class="bitasks">${bit(76, m === 'fix' ? 'hop' : '')}<div class="bubble read">${W[m].line}</div></div>
        <div class="receipts">${W[m].rc}</div>
        <div class="chips">${W[m].acts}</div>
      </div>
      <div style="padding-top:12px;border-top:1px solid var(--hair)"><button class="btn action full" data-hop="signin:main">Get started</button></div>
    </div>`;
  define('welcome', { idle: welcome('idle'), check: welcome('check'), retry: welcome('retry'), fix: welcome('fix') }, 'idle');

  /* ===== Sign in ===== */
  define('signin', {
    main: () => `<div class="screen center"><div class="grow"></div><div class="logo" style="height:30px">${I.logo}</div><p class="title2" style="margin:22px 0 6px">Ready when you are.</p><p class="sub">Sign in to keep your reps and feedback.</p><div class="grow"></div>
      <div class="stack" style="width:100%"><button class="btn black full" data-hop="setup:p1">${I.apple} Sign in with Apple</button><button class="btn outline full" data-hop="setup:p1">Continue with Google</button><button class="btn outline full" data-hop="setup:p1">Continue with GitHub</button><p class="foot" style="text-align:center;opacity:0">Signing in…</p></div></div>`,
    invite: () => `<div class="screen center"><div class="grow"></div><div class="logo" style="height:30px">${I.logo}</div><p class="title2" style="margin:22px 0 6px">One last step.</p><p class="sub">Enter your invite code to begin.</p><div class="grow"></div>
      <div class="stack" style="width:100%"><div class="cells"><div class="cell ph" style="min-height:48px;align-items:center">Invite code</div></div><button class="btn action full" data-hop="setup:p1">Start practising</button></div></div>`,
  }, 'main');

  /* ===== Setup (SetupView, two pages) ===== */
  const GOALS = [['interview', 'An interview’s coming up'], ['learn', 'I want to get sharper'], ['fresh', 'Just keeping fresh']];
  const LEVELS = [['junior', 'New to system design', 'We’ll start with the building blocks and work through them together.'], ['mid', 'I’ve designed a few systems', 'We’ll skip the definitions and push on your decisions.'], ['senior', 'I design systems regularly', 'Expect tradeoffs and failure modes, not definitions.'], ['staff', 'I lead architecture across teams', 'We’ll go straight to the hard tradeoffs. Expect pushback.']];
  const stepline = (n) => `<div class="stepline"><span class="n">0${n} / 02</span><div class="track"><i style="width:${n * 50}%"></i></div></div>`;
  define('setup', {
    p1: (d) => `<div class="screen">${stepline(1)}
      <div class="grow scroll">${bitAsks('What are we drilling for?')}
        <div class="choices">${GOALS.map(([k, l]) => `<button class="choice" data-set="goal=${k}" aria-pressed="${d.goal === k}">${l}<span class="chk">${I.check}</span></button>`).join('')}</div>
        ${d.goal === 'interview' ? `<div style="margin-top:22px" class="stack"><div class="toggle"><span class="body">I know the date</span><button class="sw ${d.date ? 'on' : ''}" data-set="date=${!d.date}" aria-label="I know the date"></button></div>
          ${d.date ? `<div class="datefield"><span class="body">Interview date</span><span class="val">16 Oct 2026</span></div><div class="countdown"><span class="num">12</span><span class="sub">days until your interview. Let’s find one thing to sharpen today.</span></div>` : ''}</div>` : ''}
      </div>
      <div style="padding-top:12px;border-top:1px solid var(--hair)"><button class="btn action full" data-go="p2">Continue</button></div></div>`,
    p2: (d) => `<div class="screen">${stepline(2)}
      <div class="grow scroll">${bitAsks('How much system design have you done?')}
        <p class="sub" style="margin-bottom:14px">This sets how deep your questions go. You can change it any time.</p>
        <div class="choices">${LEVELS.map(([k, l]) => `<button class="choice" data-set="level=${k}" aria-pressed="${d.level === k}">${l}<span class="chk">${I.check}</span></button>`).join('')}</div>
        <div class="promise">${LEVELS.find((x) => x[0] === d.level)[2]}</div>
      </div>
      <div class="row" style="padding-top:12px;border-top:1px solid var(--hair)"><button class="btn secondary" data-go="p1">Back</button><button class="btn action" style="flex:1" data-hop="preview:writing">Show me a question</button></div></div>`,
  }, 'p1', { goal: 'learn', date: false, level: 'mid' });

  /* ===== Question preview (QuestionFlow) ===== */
  const preview = (d, writing) => `<div class="screen">
      ${nav(d.firstRep ? '' : `<button class="icbtn" data-hop="home:ready">Close</button>`, '', '')}
      <div class="grow scroll">
        <p class="eyebrow">The scenario</p>
        <p class="title1 ${writing ? 'caret' : ''}" style="margin-bottom:14px">${esc(writing ? Q.title.slice(0, d.n || 0) : Q.title)}</p>
        ${writing ? '' : `<p class="body">${esc(Q.prompt)}</p>`}
      </div>
      <div class="stack" style="padding-top:12px">
        ${writing ? `<div style="display:flex;justify-content:center">${bit(52)}</div>` : `
          ${d.firstRep ? '<p class="sub">Guided practice helps you structure the approach.</p>' : ''}
          <p class="cap2">How you’ll answer</p>
          <div class="segmented"><button data-set="mode=write" aria-pressed="${d.mode !== 'talk'}">Write it</button><button data-set="mode=talk" aria-pressed="${d.mode === 'talk'}">Talk it through</button></div>
          <p class="foot" style="text-align:center">${d.mode === 'talk' ? 'Up to 10 min · 5 of 6 left today · resets 00:00' : 'Type it out. You can switch to talking any time.'}</p>
          <button class="btn action full" data-hop="${d.mode === 'talk' ? 'voice:live' : d.firstRep ? 'room:opener' : 'room:empty'}">${d.mode === 'talk' ? 'Start talking' : 'Start writing'}</button>
          ${d.firstRep && !d.swapped ? '<button class="btn secondary full" data-set="swapped=true" data-go="writing">Choose another question</button>' : ''}`}
      </div></div>`;
  define('preview', { writing: (d) => preview(d, true), ready: (d) => preview(d, false) }, 'ready', { firstRep: true, mode: 'write', swapped: false });
  phones.preview.states.writing.after = async (el, d, go) => { const tok = (d.tok = Symbol()); for (let n = 1; n <= Q.title.length; n++) { await wait(45); if (d.tok !== tok) return; const t = el.querySelector('.title1'); if (t) t.textContent = Q.title.slice(0, n); } await wait(500); if (d.tok === tok) go('ready'); };

  /* ===== Interview room (InterviewView) ===== */
  const roomNav = (d) => d.mode === 'mock'
    ? nav(`<button class="icbtn" data-hop="home:ready">Close</button>`, `<span>Job queue</span><small>⏱ 19:58</small>`, `<button class="icbtn" data-go="menu" aria-label="Interview options">${I.more}</button>`)
    : nav(`<button class="icbtn" data-hop="home:ready">Close</button>`, 'System design', `<button class="icbtn" data-go="menu" aria-label="Interview options">${I.more}</button>`);
  const pathBar = (step) => `<button class="pathbar" data-go="path" aria-label="Step ${step + 1} of 4: ${Q.path[step]}"><div class="segs">${Q.path.map((_, i) => `<i class="${i <= step ? 'on' : ''}"></i>`).join('')}</div><div class="cur"><span><b>Step ${step + 1} of 4</b>${Q.path[step]}</span>${I.down}</div></button>`;
  const original = (open) => `<div class="disc ${open ? 'open' : ''}"><div class="hd"><div><div class="lbl">Original question</div><div class="tt">${Q.title}</div></div><span class="chv">${I.down}</span></div><p class="txt">${esc(Q.prompt)}</p></div>`;
  const turnRow = (who, text, cls = '') => `<div class="turn"><div class="who">${who}</div><p class="say ${cls}">${text}</p></div>`;
  const answered = (text) => `<div class="turn answered"><div><div class="who">You</div><p class="say sent">${esc(text)}</p></div><span class="chv" style="color:var(--ink-2)">${I.down}</span></div>`;
  const typing = () => `<div class="turn"><div class="who">Interviewer</div><div class="typing"><i></i><i></i><i></i></div></div>`;
  const composer = (d, label, ph, sendTo, enabled) => `<div class="composer"><div class="lbl ${label === 'Asking the interviewer' ? 'ask' : ''}">${label}</div><div class="field" contenteditable="true" data-ph="${ph}" data-field>${esc(d.draft || '')}</div>
    <div class="footer"><div class="row"><button class="talk" data-hop="voice:idle">${I.wave} Talk</button>${d.mode === 'mock' ? '' : '<button class="link" data-go="nudge" id="inlineNudge">Need a nudge?</button>'}</div><button class="send" data-go="${sendTo}" ${enabled ? '' : 'disabled'} aria-label="Send">${I.up}</button></div></div>`;
  const ANSWER = 'Use a durable queue, retry failed work with backoff, and record each attempt so duplicates stay safe.';
  const room = {
    opener: (d) => `<div class="screen">${roomNav(d)}${d.mode === 'guided' ? pathBar(0) : ''}
      <div class="grow scroll doc">${original(true)}<div class="divider"></div>${turnRow('Interviewer', `<span class="caret">${esc(Q.opener.slice(0, d.n || 0))}</span>`)}<div class="divider"></div></div>
      ${composer(d, 'Your reply', 'A sentence is fine. Send when you’ve got a first take.', 'sent', !!d.draft)}</div>`,
    empty: (d) => `<div class="screen">${roomNav(d)}${d.mode === 'guided' ? pathBar(0) : ''}
      <div class="grow scroll doc">${original(true)}<div class="divider"></div>${turnRow('Interviewer', esc(Q.opener))}<div class="divider"></div></div>
      ${composer(d, 'Your reply', 'A sentence is fine. Send when you’ve got a first take.', 'sent', !!d.draft)}</div>`,
    sent: (d) => `<div class="screen">${roomNav(d)}${d.mode === 'guided' ? pathBar(d.replied ? 0 : 0) : ''}
      <div class="grow scroll doc">${original(false)}<div class="divider"></div>${answered(d.draft || ANSWER)}${d.replied ? turnRow('Interviewer', esc(Q.followUp)) : typing()}<div class="divider"></div>
        ${d.replied && d.mode === 'guided' ? `<div class="gchoices">${Q.choices.map((c) => `<button class="gc" data-go="step2">${c}</button>`).join('')}</div>` : ''}</div>
      ${composer({ ...d, draft: '' }, 'Your reply', 'Answer or ask a question…', 'sent', false)}</div>`,
    step2: (d) => `<div class="screen">${roomNav(d)}${d.mode === 'guided' ? pathBar(1) : ''}
      <div class="grow scroll doc">${original(false)}<div class="divider"></div>${answered(d.draft || ANSWER)}${turnRow('Interviewer', esc(Q.followUp))}${answered(Q.choices[0])}${turnRow('Interviewer', 'Good. Now sketch the lifecycle: what states does a job move through from enqueue to done?')}<div class="divider"></div>
        <div class="gchoices"><button class="gc">queued → leased → done</button><button class="gc">queued → running → done / failed</button><button class="gc">Not sure, show me</button></div></div>
      ${composer({ ...d, draft: '' }, 'Your reply', 'Answer or ask a question…', 'sent', false)}</div>`,
    asking: (d) => `<div class="screen">${roomNav(d)}${d.mode === 'guided' ? pathBar(0) : ''}
      <div class="grow scroll doc">${original(false)}<div class="divider"></div>${answered(ANSWER)}${turnRow('Interviewer', esc(Q.followUp))}<div class="divider"></div></div>
      ${composer({ ...d, draft: 'What throughput should I plan for?' }, 'Asking the interviewer', '', 'sent', true)}</div>`,
    path: (d) => room.sent({ ...d, replied: true }) + `<div class="scrim" data-go="sent"></div><div class="popover"><p>How a strong answer usually goes. You move on as you cover each step.</p>${Q.path.map((s, i) => `<div class="st ${i === 0 ? 'cur' : 'future'}"><span class="ic">${i === 0 ? '' : i + 1}</span><span>${i === 0 ? '<small>You’re here</small>' : ''}${s}</span></div>`).join('')}</div>`,
    menu: (d) => room.sent({ ...d, replied: true }) + `<div class="scrim" data-go="sent"></div><div class="menu" role="menu">${d.mode === 'mock' ? '' : `<button data-go="nudge">Need a nudge? ${I.bulb}</button><button data-go="example">Show an example <svg viewBox="0 0 20 20"><path d="M4 5h12M4 10h12M4 15h8"/></svg></button>`}<button data-go="style">Session style ${I.chev}</button><button data-go="finish">Finish interview ${I.check}</button><button class="danger" data-hop="home:ready">Skip question ${I.x}</button></div>`,
    nudge: (d) => room.sent({ ...d, replied: true }) + `<div class="scrim" data-go="sent"></div><div class="sheet"><div class="row" style="gap:8px;margin-bottom:10px;color:var(--accent)">${I.bulb}<span class="headline">Nudge</span></div>${d.slow ? `<div class="loading" style="justify-content:flex-start;min-height:48px"><span class="spin"></span>Preparing nudge</div><button class="btn secondary full" data-go="sent">Cancel</button>` : `<p class="body" style="margin-bottom:18px">${Q.nudge}</p><button class="btn action full" data-go="sent">Got it</button>`}</div>`,
    example: (d) => room.sent({ ...d, replied: true }) + `<div class="scrim" data-go="sent"></div><div class="sheet"><div class="row" style="gap:8px;margin-bottom:10px;color:var(--accent)"><svg width="22" height="22" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M4 5h12M4 10h12M4 15h8"/></svg><span class="headline">Example</span></div><p class="body" style="margin-bottom:18px">${Q.example}</p><button class="btn action full" data-go="sent">Got it</button></div>`,
    style: (d) => room.sent({ ...d, replied: true }) + `<div class="scrim" data-go="sent"></div><div class="sheet tall">${nav(`<button class="icbtn" data-go="sent">${I.back}</button>`, 'Session style', '')}<div class="list" style="margin-top:8px"><div class="cells">${STYLES.map(([k, t, s]) => `<button class="cell" data-set="mode=${k}" data-go="sent" style="width:100%"><span>${t}<span class="sub">${s}</span></span><span class="v acc">${d.mode === k ? I.check : ''}</span></button>`).join('')}</div></div></div>`,
    finish: (d) => room.sent({ ...d, replied: true }) + `<div class="scrim"></div><div class="alert" role="alertdialog"><div class="body"><b>Finish interview?</b><p>Your shared answers and current draft will be saved for review.</p></div><div class="acts"><button data-go="sent">Keep writing</button><button data-hop="reflection:${d.mode}">Finish interview</button></div></div>`,
    coach1: (d) => room.empty(d) + `<div class="coach" style="left:24px;bottom:150px"><b>Your turn.</b><p>A rough first take is fine. End a line with “?” to ask the interviewer instead.</p><button class="btn action small" data-go="empty">Got it</button></div>`,
    coach2: (d) => room.sent({ ...d, replied: true }) + `<div class="coach below" style="right:16px;top:96px"><b>Stuck?</b><p>Nudges, an example and Finish live up here.</p><button class="btn action small" data-go="sent">Got it</button></div>`,
  };
  const STYLES = [['guided', 'Guided', 'Work through an approach together, with examples along the way.'], ['practice', 'Practice', 'Take the lead. Get useful pointers when you’re stuck or missing something.'], ['mock', 'Mock interview', 'Put your approach to the test. Save the coaching for the debrief.']];
  define('room', room, 'opener', { mode: 'guided', draft: '', replied: false });
  const fieldWatch = (el, d) => { const f = el.querySelector('[data-field]'); if (!f) return; f.addEventListener('input', () => { d.draft = f.textContent; const s = el.querySelector('.send'); if (s) s.disabled = !d.draft.trim(); }); };
  room.opener.after = async (el, d, go) => { fieldWatch(el, d); const tok = (d.tok = Symbol()); await wait(800); for (let n = 1; n <= Q.opener.length; n++) { await wait(18); if (d.tok !== tok) return; const t = el.querySelector('.caret'); if (t) t.textContent = Q.opener.slice(0, n); } if (d.tok === tok) go('empty'); };
  room.empty.after = (el, d) => fieldWatch(el, d);
  room.sent.after = async (el, d, go) => { if (!d.replied) { await wait(1400); d.replied = true; go('sent'); } };
  room.nudge.after = async (el, d, go) => { if (d.slow) { await wait(1500); d.slow = false; go('nudge'); } };

  /* ===== Reflection ===== */
  const heading = (eyebrow, title) => `<div class="row" style="gap:12px;margin-bottom:18px">${bit(56, 'hop')}<div><p class="eyebrow" style="margin-bottom:4px">${eyebrow}</p><p class="title1">${title}</p></div></div>`;
  const leadFB = () => `<p class="foot" style="margin-bottom:14px">No explicit help recorded</p><div class="lead"><div class="pt"><p class="eyebrow" style="margin:0">What worked</p><p class="q">“You gave workers durable ownership of queued jobs.”</p><p class="o">Used leases and durable records</p></div><div class="rule"></div><div class="pt"><p class="eyebrow" style="margin:0">What to fix</p><p class="q">“Explain what happens when work finishes but its acknowledgement is lost.”</p><p class="o">Make retries safe before making them automatic.</p></div></div>`;
  const reminder = () => `<div class="card" style="margin-top:22px"><p class="headline" style="margin-bottom:4px">Want a nudge tomorrow?</p><p class="sub" style="margin-bottom:12px">Every day at 09:00. Change it in Settings.</p><div class="row"><button class="btn action small" data-go="guidedNoRem">Remind me</button><button class="btn secondary small" data-go="guidedNoRem">No thanks</button></div></div>`;
  const tail = () => `<div class="stack" style="margin-top:22px"><button class="btn action full" data-hop="home:done">Done for today</button><p class="eyebrow" style="margin:8px 0 0">Other moments</p><button class="rowbtn">Start a clean branch here<small>“Use a durable queue, retry failed work…”</small></button><button class="btn secondary full">Review in Recall</button><button class="btn secondary full">Practise this next</button></div>`;
  const refl = (eyebrow, title, mid, rem) => () => `<div class="screen"><div class="grow scroll">${heading(eyebrow, title)}${leadFB()}${mid}<div class="disclosure-row" style="margin-top:18px">Full feedback ${I.chev}</div>${rem ? reminder() : ''}${tail()}</div></div>`;
  const lesson = `<p class="eyebrow" style="margin:22px 0 10px">What you worked out</p><ul class="lesson"><li>A lease lets another worker take over a stalled job</li><li>Retries need a stable operation ID to stay safe</li></ul><p class="eyebrow" style="margin:18px 0 6px">Try it solo</p><p class="body">Design retries for a payment webhook without any hints.</p>`;
  const debrief = `<p class="eyebrow" style="margin:22px 0 10px">Interview debrief</p><div class="verdict"><span class="ico"></span><span>Borderline. Could go either way.</span></div><p class="sub" style="margin:8px 0 14px">Durable ownership is solid, but a lost acknowledgement would still run the job twice.</p><div class="card"><div class="signals">${[['Requirements', 'Strong', 'Pinned down retries and ordering early.'], ['Design', 'Mixed', 'Leases are right; completion isn’t idempotent yet.'], ['Trade-offs', 'Weak', 'Didn’t weigh at-least-once against exactly-once.'], ['Communication', 'Strong', 'Clear, in a sensible order.']].map(([k, r, n]) => `<div class="sg"><span>${k}<small>${n}</small></span><span class="r ${r.toLowerCase()}">${r}</span></div>`).join('')}</div></div><p class="eyebrow" style="margin:18px 0 6px">To pass</p><p class="body">Show how a retry recognises work that already finished before running it again.</p>`;
  define('reflection', {
    pending: () => `<div class="screen center"><div class="grow"></div><div class="loading"><span class="spin"></span>Your answer is saved. Feedback is being prepared.</div><div class="grow"></div></div>`,
    guided: refl('Lesson recap', 'Here’s what you worked out.', lesson, true),
    guidedNoRem: refl('Lesson recap', 'Here’s what you worked out.', lesson, false),
    practice: refl('Practice complete', 'One idea to carry forward.', '', false),
    mock: refl('Interview debrief', 'Here’s how the round went.', debrief, false),
  }, 'guided');
  phones.reflection.states.pending.after = async (el, d, go) => { await wait(1800); go('guided'); };

  /* ===== Home ===== */
  const homeHead = (sub, mood) => `<div class="home-head"><div><p class="date">Sun, Oct 4</p><h2>Sunday</h2><p class="sub">${sub}</p></div>${bit(64)}</div><button class="icbtn" style="position:absolute;top:58px;right:14px" aria-label="Settings" data-hop="settings:main">${I.gear}</button>`;
  const ticketReady = (style = 'Practice', note = 'Nudges if you ask') => `<button class="ticket" data-hop="preview:ready"><div class="top"><div class="meta"><span><b>No. 001</b></span><span>Oct 4 · Mid-level</span></div><h3>${Q.title}</h3><p>${Q.prompt}</p></div><div class="perf"></div><div class="stub"><div class="l"><b>${style}</b><span>${note}</span></div><span class="pill">Open</span></div></button>`;
  const recallRow = (n) => `<div class="recall-row"><div><b>Recall</b><span>A few things from past sessions, ready to test.</span></div><span class="due">${n} due ${I.chev}</span></div>`;
  define('home', {
    ready: () => `<div class="screen tabbed">${homeHead('One question, about 10 minutes.')}${ticketReady()}${tabbar('home')}</div>`,
    rich: () => `<div class="screen tabbed">${homeHead('One question, about 10 minutes.')}${ticketReady('Guided', 'Step by step, with examples')}${recallRow(3)}${tabbar('home')}</div>`,
    menu: () => `<div class="screen tabbed">${homeHead('One question, about 10 minutes.')}${ticketReady()}${tabbar('home')}</div><div class="scrim" data-go="ready"></div><div class="ctxmenu"><button data-go="ready">Regenerate</button><button data-hop="prepare:main">Choose focus or level</button><button data-go="ready">Choose another question</button><button class="danger" data-go="skip">Skip question</button></div>`,
    skip: () => `<div class="screen tabbed">${homeHead('One question, about 10 minutes.')}${ticketReady()}${tabbar('home')}</div><div class="scrim"></div><div class="alert"><div class="body"><b>Skip this question?</b><p>It goes to Skipped questions in Library. Your draft stays saved.</p></div><div class="acts"><button data-go="ready">Keep practising</button><button class="danger" data-go="empty">Skip question</button></div></div>`,
    inprogress: () => `<div class="screen tabbed">${homeHead('One question, about 10 minutes.')}<button class="ticket" data-hop="room:sent"><div class="top"><div class="meta"><span><b>No. 001</b></span><span>Oct 4 · Mid-level</span></div><h3>${Q.title}</h3><p>${Q.prompt}</p></div><div class="perf"></div><div class="stub"><div class="l"><b>Where you left off</b><span class="q">“${Q.followUp}”</span></div><span class="pill">Resume</span></div></button>${tabbar('home')}</div>`,
    done: () => `<div class="screen tabbed">${homeHead('Today’s rep is in the bag.')}<button class="ticket" data-hop="library:detail"><div class="top"><div class="meta"><span><b>No. 001</b></span><span>Done 13:55</span></div><h3>${Q.title}</h3></div><div class="perf"></div><div class="stub"><div class="l"><b>Worked out together</b><span class="q">“Make retries safe before making them automatic.”</span></div></div></button><div class="after"><p class="sub">Next one’s picked when you open the app tomorrow.</p><button class="link" data-go="ready">One more?</button></div>${recallRow(1)}${tabbar('home')}</div>`,
    gate: () => `<div class="screen tabbed">${homeHead('One question, about 10 minutes.')}<div class="ticket"><div class="top"><div class="meta"><span><b>Today</b></span><span>Oct 4</span></div><h3>Your free rep comes back Thursday.</h3><p>Recall and Library are still open in the meantime.</p></div><div class="perf"></div><div class="stub"><div class="l"><b>Free reps</b><span>One a week, on the house</span></div></div></div>${tabbar('home')}</div>`,
    empty: () => `<div class="screen tabbed">${homeHead('One question, about 10 minutes.')}<button class="ticket" data-hop="prepare:main"><div class="top"><div class="meta"><span><b>Today</b></span><span>Oct 4</span></div><h3>Nothing picked yet.</h3><p>Choose an area and level, or let Drillbit pick.</p></div><div class="perf"></div><div class="stub"><div class="l"><b>Prepare a question</b><span>Takes a few seconds</span></div><span class="pill">Prepare</span></div></button>${tabbar('home')}</div>`,
    preparing: () => `<div class="screen tabbed">${homeHead('One question, about 10 minutes.')}<div class="ticket"><div class="top"><div class="meta"><span><b>Today</b></span><span>Oct 4</span></div><h3 class="caret">Design a reliable</h3></div><div class="perf"></div><div class="stub"><div class="l"><b>Drilling one out</b><span>Takes a few seconds</span></div></div></div>${tabbar('home')}</div>`,
    failed: () => `<div class="screen tabbed">${homeHead('One question, about 10 minutes.')}<button class="ticket" data-hop="prepare:main"><div class="top"><div class="meta"><span><b>Today</b></span><span>Oct 4</span></div><h3>Couldn’t write today’s question.</h3><p>The question service is unavailable right now.</p></div><div class="perf"></div><div class="stub"><div class="l"><b>Your settings are safe</b><span>Check them and try again</span></div><span class="pill">Review</span></div></button>${tabbar('home')}</div>`,
    coach: () => `<div class="screen tabbed">${homeHead('Today’s rep is in the bag.')}<button class="ticket"><div class="top"><div class="meta"><span><b>No. 001</b></span><span>Done 13:55</span></div><h3>${Q.title}</h3></div><div class="perf"></div><div class="stub"><div class="l"><b>Worked out together</b><span class="q">“Make retries safe before making them automatic.”</span></div></div></button><div class="after"><p class="sub">Next one’s picked when you open the app tomorrow.</p></div><div class="recall-row"><div><b>Recall</b><span>1 card from your first rep. A quick check now makes it stick.</span></div><span class="due">1 due ${I.chev}</span></div>${tabbar('home')}</div><div class="coach" style="left:24px;bottom:200px"><b>Keep this one.</b><p>Cards from your own answers. A quick check now makes them stick.</p><button class="btn action small" data-go="done">Got it</button></div>`,
  }, 'ready');
  defaults.home = 'ready';

  /* ===== Preparation sheet ===== */
  define('prepare', {
    main: (d) => `<div class="screen">${nav('', 'New question', `<button class="link" data-hop="home:ready">Cancel</button>`)}<div class="grow scroll list" style="padding-top:6px">
      <div class="group"><div class="cells"><div class="cell">Practice area<span class="v">Automatic ${I.chev}</span></div><div class="cell">Target level<span class="v">Mid-level ⌃⌄</span></div></div></div>
      <div class="group"><div class="hd">Session style</div><div class="cells"><button class="cell" style="width:100%" data-go="style">Session style<span class="v">${STYLES.find((s) => s[0] === d.mode)[1]} ${I.chev}</span></button></div></div>
      <div class="group"><div class="cells"><div class="cell ph">Any custom instructions? (e.g. talk like a pirate)</div></div></div>
      <div class="group"><button class="btn action full" data-hop="preview:writing">Prepare question</button><div class="ft">Your current question stays until the new one is ready.</div></div></div></div>`,
    style: (d) => `<div class="screen">${nav(`<button class="icbtn" data-go="main">${I.back}</button>`, 'Session style', '')}<div class="list" style="padding-top:6px"><div class="cells">${STYLES.map(([k, t, s]) => `<button class="cell" data-set="mode=${k}" data-go="main" style="width:100%"><span>${t}<span class="sub">${s}</span></span><span class="v acc">${d.mode === k ? I.check : ''}</span></button>`).join('')}</div></div></div>`,
  }, 'main', { mode: 'practice' });
  phones.prepare.states.main.after = (el, d) => { phones.preview.data.firstRep = false; phones.room.data.mode = d.mode; };

  /* ===== Voice room ===== */
  const vq = () => `<div class="disc"><div class="hd"><div><div class="lbl">Original question</div><div class="tt">${Q.title}</div></div><span class="chv">${I.down}</span></div><p class="txt">${esc(Q.prompt)}</p></div>`;
  const rc = (cls, icon, label, go) => `<button class="rc ${cls}" ${go ? `data-go="${go}"` : ''}><span class="c">${icon}</span>${label}</button>`;
  const vscreen = (d, { clock, orb, state, cap, dock, body }) => `<div class="screen">${nav('', `<span>Talk it through</span>${clock ? `<small style="color:var(--ink-2)">${clock}</small>` : ''}`, '')}
    <div class="grow scroll">${vq()}${body || `<div class="orb ${orb}"></div><p class="vstate">${state}</p><p class="vcap">${cap || ''}</p>`}</div>
    <div class="stack" style="padding-top:8px">${dock}</div></div>`;
  define('voice', {
    idle: (d) => vscreen(d, { orb: '', state: 'Ready when you are', cap: 'Say it out loud, like the real one. The interviewer talks back.', dock: `<p class="foot" style="text-align:center">Up to 10 min a session · 5 of 6 left today · resets 00:00</p><button class="btn action full" data-go="connecting">${I.wave} Start talking</button><button class="btn secondary full" data-hop="room:empty">Back to writing</button>` }),
    connecting: (d) => vscreen(d, { orb: 'still', state: 'Connecting', cap: ' ', dock: `<div class="loading"><span class="spin"></span>Connecting…</div><button class="btn secondary full" data-hop="room:empty">Cancel</button>` }),
    live: (d) => vscreen(d, { clock: '0:02', orb: 'live', state: 'You’re talking', cap: ' ', dock: `<div class="dock">${rc('', I.list, 'Transcript', 'transcript')}${rc('big', I.mic, 'Mute', 'muted')}${rc('end', I.xs, 'End', 'ended')}</div>` }),
    muted: (d) => vscreen(d, { clock: '0:07', orb: 'still', state: 'Mic off. They can’t hear you.', cap: ' ', dock: `<div class="dock">${rc('', I.list, 'Transcript', 'transcript')}${rc('big muted', I.micoff, 'Unmute', 'live')}${rc('end', I.xs, 'End', 'ended')}</div>` }),
    caption: (d) => vscreen(d, { clock: '0:41', orb: 'live', state: 'Interviewer’s talking', cap: 'Makes sense. What happens when a worker retries?', dock: `<div class="dock">${rc('', I.list, 'Transcript', 'transcript')}${rc('big', I.mic, 'Mute', 'muted')}${rc('end', I.xs, 'End', 'ended')}</div>` }),
    thinking: (d) => vscreen(d, { clock: '1:12', orb: 'live', state: 'Working through your answer', cap: 'Makes sense. What happens when a worker retries?', dock: `<div class="dock">${rc('', I.list, 'Transcript', 'transcript')}${rc('big', I.mic, 'Mute', 'muted')}${rc('end', I.xs, 'End', 'ended')}</div>` }),
    closing: (d) => vscreen(d, { clock: '1:58 left', orb: 'live', state: 'Listening', cap: 'Makes sense. What happens when a worker retries?', dock: `<div class="dock">${rc('', I.list, 'Transcript', 'transcript')}${rc('big', I.mic, 'Mute', 'muted')}${rc('end', I.xs, 'End', 'ended')}</div>` }),
    transcript: (d) => vscreen(d, { clock: '0:48', body: `<div style="margin-top:6px"><div class="vrow"><div class="who">Interviewer</div><p>${Q.opener}</p></div><div class="vrow"><div class="who">You</div><p>I'd use a durable queue.</p></div><div class="vrow"><div class="who">Interviewer</div><p>Makes sense. What happens when a worker retries?</p></div></div>`, dock: `<div class="dock">${rc('', I.wave, 'Live', 'caption')}${rc('big', I.mic, 'Mute', 'muted')}${rc('end', I.xs, 'End', 'ended')}</div>` }),
    ending: (d) => vscreen(d, { orb: 'still', state: 'Saving the conversation', cap: 'Makes sense. What happens when a worker retries?', dock: `<div class="loading"><span class="spin"></span>Saving the conversation…</div>` }),
    unavailable: (d) => vscreen(d, { orb: 'still', state: 'Voice is off', cap: ' ', dock: `<p class="foot" style="text-align:center">Voice disconnected. Your transcript is preserved.</p><button class="btn action full" data-go="connecting">Try again</button><button class="btn secondary full" data-hop="room:empty">Back to writing</button>` }),
    ended: (d) => `<div class="screen">${roomNav({ mode: 'practice' })}<div class="grow scroll doc">${original(false)}<div class="divider"></div>${turnRow('Interviewer', esc(Q.opener))}<div class="divider"></div>${turnRow('You', 'I\'d use a durable queue.')}${turnRow('Interviewer', 'Makes sense. What happens when a worker retries?')}<div class="divider"></div></div>${composer({ mode: 'practice', draft: 'Keep my written draft.' }, 'Your reply', '', 'ended', true)}</div>`,
    alert: (d) => `<div class="screen">${roomNav({ mode: 'practice' })}<div class="grow scroll doc">${original(true)}<div class="divider"></div>${turnRow('Interviewer', esc(Q.opener))}<div class="divider"></div></div>${composer({ mode: 'practice', draft: 'Keep this reply' }, 'Your reply', '', 'alert', true)}</div><div class="scrim"></div><div class="alert"><div class="body"><b>Voice</b><p>Live voice is currently unavailable. You can continue in text.</p></div><div class="acts"><button data-go="ended">Done</button></div></div>`,
  }, 'live');
  phones.voice.states.connecting.after = async (el, d, go) => { await wait(1800); go('live'); };
  phones.voice.states.ending.after = async (el, d, go) => { await wait(1500); go('ended'); };

  /* ===== Recall ===== */
  const recallSeg = (on) => `<div class="segmented" style="margin-bottom:22px">${['Review', 'Map', 'Paths'].map((s) => `<button data-go="${s.toLowerCase()}" aria-pressed="${on === s}">${s}</button>`).join('')}</div>`;
  const recallCard = (revealed) => `<div class="recall-card"><div class="row between"><p class="eyebrow" style="margin:0">Path</p><button class="link" data-go="paths">Leave path</button></div><p class="sub">3 cards left in this set</p><p class="foot">System design · Foundations</p><p class="q">What problem does a load balancer solve?</p>
    ${revealed ? `<p class="eyebrow" style="margin:10px 0 4px">Answer</p><p class="a">It spreads requests across healthy service instances, preventing one instance from taking all traffic. It also creates one stable entry point for health checks, failover and routing policy.</p><div class="row" style="margin-top:18px"><button class="btn outline" style="flex:1" data-go="card">Again</button><button class="btn action" style="flex:1" data-go="card">Got it</button></div>` : `<button class="btn action full" style="margin-top:18px" data-go="revealed">Reveal answer</button>`}</div>`;
  define('recall', {
    review: () => `<div class="screen tabbed">${nav('', '<span style="font-size:17px;font-weight:600">Recall</span>', '')}${recallSeg('Review')}<div class="grow"></div><div class="center" style="display:grid;gap:6px;justify-items:center"><p class="eyebrow">Nothing due</p><p class="title2">You’re caught up.</p><p class="sub">New ideas will appear here when they are ready to revisit.</p></div><div class="grow"></div>${tabbar('recall')}</div>`,
    map: () => `<div class="screen tabbed">${nav('', '<span style="font-size:17px;font-weight:600">Recall</span>', '')}${recallSeg('Map')}<div class="grow scroll"><p class="title2" style="margin-bottom:2px">Your system design map</p><p class="sub" style="margin-bottom:10px">Evidence, not scores</p><p class="eyebrow quiet" style="margin-top:12px">Async work</p>${[['●', 'Queues & streams', 'Practised in 1 completed session'], ['◐', 'Retry safety & idempotency', 'Worth revisiting'], ['○', 'Backpressure', 'A core system design decision.']].map(([i, b, s]) => `<div class="map-item"><span class="ic">${i}</span><div><b>${b}</b><span>${s}</span></div></div>`).join('')}<p class="eyebrow quiet" style="margin-top:18px">Data & storage</p>${[['○', 'Caching', 'Caching and capacity'], ['○', 'Sharding', 'A core system design decision.']].map(([i, b, s]) => `<div class="map-item"><span class="ic">${i}</span><div><b>${b}</b><span>${s}</span></div></div>`).join('')}</div>${tabbar('recall')}</div>`,
    paths: () => `<div class="screen tabbed">${nav('', '<span style="font-size:17px;font-weight:600">Recall</span>', '')}${recallSeg('Paths')}<div class="grow scroll"><p class="title2" style="margin-bottom:2px">Choose a path</p><p class="eyebrow quiet" style="margin:8px 0 4px">Focused sets</p><p class="sub" style="margin-bottom:12px">Short general-knowledge sets. They don’t change your personal Recall.</p><div class="stack" style="gap:8px">${[['System design essentials', 'Load balancing, cache-aside and backpressure.'], ['Swift', 'Value semantics, actors and Sendable.'], ['TypeScript', 'Narrowing, discriminated unions and variance.'], ['SQL', 'Indexes, composite keys and isolation.'], ['Networking', 'TCP, TLS and HTTP/3.']].map(([t, s]) => `<button class="rowbtn" data-go="card"><span>${t}<small>${s}</small></span><span class="sub">3 cards</span></button>`).join('')}</div></div>${tabbar('recall')}</div>`,
    card: () => `<div class="screen tabbed">${nav('', '<span style="font-size:17px;font-weight:600">Recall</span>', '')}${recallSeg('Review')}<div class="grow scroll">${recallCard(false)}</div>${tabbar('recall')}</div>`,
    revealed: () => `<div class="screen tabbed">${nav('', '<span style="font-size:17px;font-weight:600">Recall</span>', '')}${recallSeg('Review')}<div class="grow scroll">${recallCard(true)}</div>${tabbar('recall')}</div>`,
  }, 'review');
  defaults.recall = 'review';

  /* ===== Library ===== */
  const libNav = (title, back) => nav(back ? `<button class="icbtn" data-go="${back}">${I.back}</button>` : '', `<span style="font-size:17px;font-weight:600">${title}</span>`, title === 'Library' ? `<span class="row" style="gap:0;justify-content:flex-end"><button class="icbtn" aria-label="Filters"><svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M3 5h14M6 10h8M8 15h4"/></svg></button><button class="icbtn" data-go="menu" aria-label="Library menu">${I.more}</button></span>` : '');
  define('library', {
    list: () => `<div class="screen tabbed">${libNav('Library')}<div class="cells" style="margin-bottom:12px"><div class="cell ph" style="min-height:40px;align-items:center;font-size:16px">🔍 Search</div></div><p class="eyebrow quiet">Questions / evidence</p><div class="cells"><button class="cell" style="width:100%" data-go="evidence">Practice evidence<span class="v">${I.chev}</span></button></div><div class="cells" style="margin-top:12px"><button class="qrow" style="width:100%;text-align:left" data-go="detail"><b>${Q.title}</b><span>Notification service · Senior</span><span>10 Sep 2026 · 1 attempt</span><div class="tags"><i>Queues & streams</i><i>Retry safety & idempotency</i></div></button></div>${tabbar('library')}</div>`,
    menu: () => phones.library.states.list() + `<div class="scrim" data-go="list"></div><div class="menu" style="top:88px"><button data-go="skipped">Skipped questions</button></div>`,
    skipped: () => `<div class="screen tabbed">${libNav('Skipped questions', 'list')}<div class="cells" style="margin-top:12px"><button class="qrow" style="width:100%;text-align:left"><b>Design a scheduler for recurring reports</b><span>Scheduler · Senior</span><span>Skipped 9 Sep 2026</span></button></div>${tabbar('library')}</div>`,
    detail: () => `<div class="screen tabbed">${libNav('Question', 'list')}<div class="grow scroll list" style="padding-top:4px"><div class="group"><div class="cells"><div class="cell" style="font-weight:600;font-size:19px">${Q.title}</div><div class="cell">Original question<span class="v">${I.chev}</span></div></div></div>
      <div class="group"><div class="hd">Concepts</div><div class="cells"><div class="cell">Queues & streams<span class="v">${I.chev}</span></div><div class="cell">Retry safety & idempotency<span class="v">${I.chev}</span></div></div><div class="ft">Explore related questions in your library.</div></div>
      <div class="group"><button class="btn action full" data-hop="preview:ready">Try again</button><button class="btn secondary full">Practise this concept</button><div class="ft" style="text-align:center">Available in your question pool</div></div>
      <div class="group"><div class="hd">Attempts</div><div class="cells"><button class="cell" style="width:100%" data-go="session"><span>10 Sep 2026<span class="sub">Completed</span></span><span class="v">${I.chev}</span></button></div></div></div>${tabbar('library')}</div>`,
    session: () => `<div class="screen tabbed">${libNav('Session', 'detail')}<div class="grow scroll"><p class="eyebrow">Completed session</p><p class="title2" style="margin-bottom:4px">${Q.title}</p><p class="sub" style="margin-bottom:16px">Senior · 10 Sep 2026, 12:00</p><div class="cells"><div class="cell">Original question<span class="v">${I.chev}</span></div><div class="cell">Interview conversation<span class="v">${I.chev}</span></div></div><p class="eyebrow" style="margin-top:18px">Your answer</p><p class="body" style="margin-bottom:14px">${ANSWER}</p><p class="foot">No explicit help recorded</p><div class="hr"></div>${leadFB()}<div class="stack" style="margin-top:18px"><button class="btn action full">Practise this next</button><div class="disclosure-row">Help history ${I.chev}</div><div class="disclosure-row">Assistance used ${I.chev}</div></div></div>${tabbar('library')}</div>`,
    evidence: () => `<div class="screen tabbed">${libNav('Practice evidence', 'list')}<div class="grow scroll"><p class="sub" style="margin:4px 0 14px">Feedback from your latest 100 sessions, linked to your answers. Counts track practice, not mastery.</p><p class="headline">Retry safety & idempotency</p><p class="foot" style="margin-bottom:6px">Completed attempts · 1</p><div class="evidence"><span class="k">Demonstrated in practice</span><q>Defined a bounded retry policy.</q><span class="o">Used leases and durable records</span><span class="foot">Independence not established</span><button class="link" style="justify-self:start">View session</button></div><p class="headline" style="margin-top:18px">Queues & streams</p><p class="foot">Completed attempts · 1</p><p class="sub">No recorded evidence yet</p></div>${tabbar('library')}</div>`,
  }, 'list');
  defaults.library = 'list';

  /* ===== Settings ===== */
  define('settings', {
    main: () => `<div class="screen">${nav('', '<span style="font-size:17px;font-weight:600">Settings</span>', `<button class="link" data-hop="home:ready" style="font-weight:600">Done</button>`)}<div class="grow scroll list" style="padding-top:4px">
      <div class="group"><div class="cells"><div class="cell">Learning plan<span class="v">${I.chev}</span></div><div class="cell">About your practice<span class="v">${I.chev}</span></div></div></div>
      <div class="group"><div class="hd">Practice</div><div class="cells"><div class="cell">Engineering level<span class="v">Mid-level ⌃⌄</span></div><div class="cell">Daily reminder<span class="sw"></span></div><div class="cell">Time zone<span class="v">Prague (UTC+02:00) ${I.chev}</span></div><div class="cell"><span>Formatted questions<span class="sub">Bold, italics and code blocks where they help</span></span><span class="sw on"></span></div><div class="cell">LLM provider<span class="v">${I.chev}</span></div></div></div>
      <div class="group"><div class="hd">Appearance</div><div class="cells"><div class="cell">Appearance<span class="v">Dark ⌃⌄</span></div></div></div>
      <div class="group"><div class="hd">Account</div><div class="cells"><div class="cell">Export practice data<span class="v">${I.chev}</span></div><div class="cell acc">Sign out</div><div class="cell danger">Delete account</div></div></div>
      <div class="group"><div class="hd">Developer</div><div class="cells"><div class="cell danger">Reset Drillbit</div></div><div class="ft">Clears all Drillbit data and preferences, then returns to onboarding. Your sign-in stays active.</div></div></div></div>`,
  }, 'main');

  /* --------------- mount --------------- */
  document.querySelectorAll('.phone[data-phone]').forEach((el) => {
    const [src, state] = el.dataset.phone.split(':'); const base = phones[src]; if (!base) return;
    if (el.dataset.clone !== undefined || base.el) { // extra instance sharing state tables
      const id = src + '_' + (state || 'x') + '_' + Math.random().toString(36).slice(2, 6);
      phones[id] = { states: base.states, state: state || base.state, data: JSON.parse(JSON.stringify(base.data)), el };
      if (el.dataset.data) Object.assign(phones[id].data, JSON.parse(el.dataset.data));
      render(id); return;
    }
    base.el = el; if (state) base.state = state; if (el.dataset.data) Object.assign(base.data, JSON.parse(el.dataset.data)); render(src);
  });
  $('#theme')?.addEventListener('click', (e) => { const b = e.target.closest('button'); if (!b) return; document.documentElement.dataset.theme = b.dataset.v; $('#theme').querySelectorAll('button').forEach((x) => x.setAttribute('aria-pressed', x === b)); });
  $('#motion')?.addEventListener('click', (e) => { const b = e.target.closest('button'); if (!b) return; document.documentElement.dataset.motion = b.dataset.v; $('#motion').querySelectorAll('button').forEach((x) => x.setAttribute('aria-pressed', x === b)); });
  window.proto = { go, phones };
})();

// app.jsx — Wakey: location alarm for commuters who doze on transit.
// Three-screen flow: Home (map) → Confirm destination → Armed / Sleeping.

const { useState, useEffect, useRef } = React;

// ── data ─────────────────────────────────────────────────────
const DESTS = [
  { id:'home', name:'Home',       emoji:'🏠', area:'Maadi · Cairo',      eta:'18 min', arrive:'9:59',  station:'Maadi Metro',     cam:{ scale:1.32, x:-70, y:60  } },
  { id:'uni',  name:'University',  emoji:'🎓', area:'New Cairo',          eta:'34 min', arrive:'10:15', station:'El Rehab Station', cam:{ scale:1.36, x:90,  y:-70 } },
  { id:'work', name:'Work',        emoji:'💼', area:'Downtown',           eta:'25 min', arrive:'10:06', station:'Sadat Station',    cam:{ scale:1.30, x:40,  y:120 } },
];
const RECENTS = [
  { id:'r1', name:'El Rehab Station', area:'New Cairo',        eta:'31 min', arrive:'10:12', station:'El Rehab Station', cam:{ scale:1.4,  x:120, y:-40 } },
  { id:'r2', name:'Heliopolis',       area:'Sheraton',         eta:'22 min', arrive:'10:03', station:'Heliopolis',       cam:{ scale:1.34, x:-30, y:-110 } },
  { id:'r3', name:'Nasr City',        area:'Abbas El Akkad',   eta:'19 min', arrive:'10:00', station:'Nasr City',        cam:{ scale:1.3,  x:60,  y:30 } },
];

// places that can be searched + selected
const SEARCH_POOL = [
  ...DESTS,
  { id:'s1', name:'El Rehab Station', area:'Metro · New Cairo',    eta:'31 min', arrive:'10:12', station:'El Rehab Station', cam:{ scale:1.4,  x:120, y:-40 } },
  { id:'s2', name:'Sadat Station',    area:'Metro · Tahrir Square', eta:'25 min', arrive:'10:06', station:'Sadat Station',    cam:{ scale:1.3,  x:40,  y:120 } },
  { id:'s3', name:'Ramses Station',   area:'Metro · Downtown',     eta:'27 min', arrive:'10:08', station:'Ramses Station',   cam:{ scale:1.32, x:-40, y:-60 } },
  { id:'s4', name:'Heliopolis',       area:'Sheraton',             eta:'22 min', arrive:'10:03', station:'Heliopolis',       cam:{ scale:1.34, x:-30, y:-110 } },
  { id:'s5', name:'Nasr City',        area:'Abbas El Akkad',       eta:'19 min', arrive:'10:00', station:'Nasr City',        cam:{ scale:1.3,  x:60,  y:30 } },
  { id:'s6', name:'Maadi Metro',      area:'Road 9 · Maadi',       eta:'18 min', arrive:'9:59',  station:'Maadi Metro',      cam:{ scale:1.32, x:-70, y:60 } },
  { id:'s7', name:'Zamalek',          area:'26th of July',         eta:'24 min', arrive:'10:05', station:'Kit Kat Station',  cam:{ scale:1.36, x:10,  y:-40 } },
  { id:'s8', name:'Giza Station',     area:'Metro · Giza',         eta:'38 min', arrive:'10:19', station:'Giza Station',     cam:{ scale:1.3,  x:-100,y:90 } },
];

const radiusToPx = (m) => Math.round(44 + (m / 1500) * 116);

// ── small shared pieces ──────────────────────────────────────
function Handle() {
  return <div style={{ width:44, height:5, borderRadius:99, background:'var(--surface-3)', margin:'0 auto' }}/>;
}

function FloatPill({ children, onClick, style }) {
  return (
    <button className="press" onClick={onClick} style={{
      height:48, minWidth:48, padding:'0 6px', borderRadius:99,
      background:'rgba(255,255,255,0.82)', backdropFilter:'blur(14px)',
      WebkitBackdropFilter:'blur(14px)', boxShadow:'var(--shadow-float)',
      display:'flex', alignItems:'center', justifyContent:'center',
      color:'var(--ink)', ...style,
    }}>{children}</button>
  );
}

// ── HOME ─────────────────────────────────────────────────────
function HomeScreen({ onPick, onSearch }) {
  return (
    <React.Fragment>
      {/* floating search */}
      <div className="anim-fade" style={{ position:'absolute', top:52, left:16, right:16, zIndex:6 }}>
        <button className="press" onClick={onSearch} style={{
          width:'100%', height:58, borderRadius:20, padding:'0 18px',
          background:'rgba(255,255,255,0.9)', backdropFilter:'blur(16px)',
          WebkitBackdropFilter:'blur(16px)', boxShadow:'var(--shadow-float)',
          display:'flex', alignItems:'center', gap:13, color:'var(--ink-2)',
        }}>
          <SearchIcon size={22} style={{ color:'var(--brand)' }}/>
          <span style={{ fontSize:18, fontWeight:600, color:'var(--ink-3)' }}>Where are you headed?</span>
        </button>
      </div>

      {/* you-are-here dot */}
      <div style={{ position:'absolute', left:'50%', top:'40%', transform:'translate(-50%,-50%)', zIndex:4 }}>
        <div style={{ position:'relative' }}>
          <div style={{ position:'absolute', left:-26, top:-26, width:52, height:52, borderRadius:'50%',
            border:'2px solid rgba(96,140,210,0.4)', animation:'haloPulse 3s ease-out infinite' }}/>
          <div style={{ position:'absolute', left:-9, top:-9, width:18, height:18, borderRadius:'50%',
            background:'#5b8fd6', boxShadow:'0 0 0 4px #fff, 0 4px 10px rgba(60,100,180,0.5)' }}/>
        </div>
      </div>

      {/* bottom sheet */}
      <div className="anim-sheet" style={sheet()}>
        <div style={{ padding:'12px 0 6px' }}><Handle/></div>
        <div style={{ padding:'6px 22px 22px', overflowY:'auto', maxHeight:'52vh' }} className="no-scrollbar stagger">
          <SheetLabel>Saved places</SheetLabel>
          <div style={{ display:'flex', flexDirection:'column', gap:12, marginBottom:22 }}>
            {DESTS.map(d => <DestCard key={d.id} d={d} onClick={() => onPick(d)} />)}
          </div>
          <SheetLabel>Recent</SheetLabel>
          <div style={{ display:'flex', flexDirection:'column', gap:2 }}>
            {RECENTS.map(r => <RecentRow key={r.id} r={r} onClick={() => onPick(r)} />)}
          </div>
        </div>
      </div>
    </React.Fragment>
  );
}

function SheetLabel({ children }) {
  return <div style={{ fontSize:13, fontWeight:800, letterSpacing:1, textTransform:'uppercase',
    color:'var(--ink-3)', margin:'2px 4px 12px' }}>{children}</div>;
}

function DestCard({ d, onClick }) {
  return (
    <button className="press" onClick={onClick} style={{
      width:'100%', display:'flex', alignItems:'center', gap:16, textAlign:'left',
      background:'var(--surface)', border:'1px solid var(--surface-2)',
      borderRadius:'var(--radius-card)', padding:'15px 16px', boxShadow:'var(--shadow-card)',
    }}>
      <div style={{ width:56, height:56, borderRadius:18, flexShrink:0,
        background:'linear-gradient(135deg, var(--brand-tint), var(--brand-soft))',
        display:'flex', alignItems:'center', justifyContent:'center', fontSize:28 }}>{d.emoji}</div>
      <div style={{ flex:1, minWidth:0 }}>
        <div style={{ fontSize:20, fontWeight:800, color:'var(--ink)' }}>{d.name}</div>
        <div style={{ fontSize:15, fontWeight:600, color:'var(--ink-2)', overflow:'hidden', textOverflow:'ellipsis', whiteSpace:'nowrap' }}>{d.area}</div>
      </div>
      <div style={{ display:'flex', flexDirection:'column', alignItems:'flex-end', gap:2 }}>
        <span style={{ fontSize:15, fontWeight:800, color:'var(--brand-deep)', whiteSpace:'nowrap' }}>{d.eta}</span>
        <ChevronR size={20} style={{ color:'var(--ink-3)' }}/>
      </div>
    </button>
  );
}

function RecentRow({ r, onClick }) {
  return (
    <button className="press" onClick={onClick} style={{
      width:'100%', display:'flex', alignItems:'center', gap:14, textAlign:'left',
      background:'transparent', padding:'13px 8px', borderRadius:16,
    }}>
      <div style={{ width:42, height:42, borderRadius:13, flexShrink:0, background:'var(--surface-2)',
        display:'flex', alignItems:'center', justifyContent:'center', color:'var(--ink-3)' }}>
        <RecentIcon size={21}/>
      </div>
      <div style={{ flex:1, minWidth:0 }}>
        <div style={{ fontSize:17, fontWeight:700, color:'var(--ink)' }}>{r.name}</div>
        <div style={{ fontSize:14, fontWeight:600, color:'var(--ink-3)' }}>{r.area}</div>
      </div>
      <span style={{ fontSize:14, fontWeight:700, color:'var(--ink-3)', whiteSpace:'nowrap' }}>{r.eta}</span>
    </button>
  );
}

// ── CONFIRM ──────────────────────────────────────────────────
function ConfirmScreen({ d, radius, setRadius, onSleep, onBack }) {
  const [open, setOpen] = useState(false);
  return (
    <React.Fragment>
      <div className="anim-fade" style={{ position:'absolute', top:52, left:16, zIndex:7 }}>
        <FloatPill onClick={onBack}><BackIcon size={22}/></FloatPill>
      </div>

      <div className="anim-sheet" style={sheet()}>
        <div style={{ padding:'12px 0 6px' }}><Handle/></div>
        <div style={{ padding:'8px 24px 24px' }}>
          <div style={{ display:'flex', alignItems:'flex-start', gap:14, marginBottom:18 }}>
            <div style={{ width:50, height:50, borderRadius:16, flexShrink:0, marginTop:2,
              background:'linear-gradient(135deg, var(--brand-tint), var(--brand-soft))',
              display:'flex', alignItems:'center', justifyContent:'center', fontSize:25 }}>
              {d.emoji || '📍'}
            </div>
            <div style={{ flex:1 }}>
              <div style={{ fontSize:25, fontWeight:800, color:'var(--ink)', lineHeight:1.1 }}>{d.name}</div>
              <div style={{ fontSize:16, fontWeight:600, color:'var(--ink-2)', marginTop:3 }}>{d.station}</div>
            </div>
          </div>

          {/* arrival */}
          <div style={{ display:'flex', gap:10, background:'var(--surface-2)', borderRadius:18,
            padding:'14px 18px', marginBottom:14, alignItems:'center' }}>
            <ClockIcon size={22} style={{ color:'var(--brand)' }}/>
            <div style={{ flex:1 }}>
              <div style={{ fontSize:17, fontWeight:800, color:'var(--ink)' }}>Arriving ~{d.arrive}</div>
              <div style={{ fontSize:14, fontWeight:600, color:'var(--ink-2)' }}>about {d.eta} away</div>
            </div>
          </div>

          {/* radius — collapsed by default */}
          <button className="press" onClick={() => setOpen(o => !o)} style={{
            width:'100%', display:'flex', alignItems:'center', gap:10, background:'transparent',
            padding:'8px 4px', marginBottom: open ? 4 : 6,
          }}>
            <PinDot size={19} style={{ color:'var(--brand)' }}/>
            <span style={{ fontSize:15, fontWeight:700, color:'var(--ink-2)', whiteSpace:'nowrap' }}>
              Wake zone · <b style={{ color:'var(--ink)' }}>{radius} m</b>
            </span>
            <span style={{ marginLeft:'auto', color:'var(--ink-3)', display:'flex' }}>
              {open ? <ChevronUp size={18}/> : <ChevronDown size={18}/>}
            </span>
          </button>
          {open && (
            <div className="anim-up" style={{ padding:'4px 4px 14px' }}>
              <input type="range" min="200" max="1500" step="50" value={radius}
                onChange={e => setRadius(+e.target.value)} className="radius-range"
                style={{ width:'100%' }}/>
              <div style={{ display:'flex', justifyContent:'space-between', fontSize:12.5,
                fontWeight:700, color:'var(--ink-3)', marginTop:4 }}>
                <span>nearer</span><span>earlier heads-up</span>
              </div>
            </div>
          )}

          {/* big sleep button */}
          <button className="press" onClick={onSleep} style={{
            width:'100%', height:66, borderRadius:22, marginTop:6,
            background:'linear-gradient(135deg, var(--brand) 0%, var(--brand-deep) 100%)',
            color:'#fff', fontSize:21, fontWeight:800, letterSpacing:0.2,
            boxShadow:'0 10px 26px var(--brand-glow)',
            display:'flex', alignItems:'center', justifyContent:'center', gap:10,
          }}>
            Sleep <span style={{ fontSize:24 }}>😴</span>
          </button>
          <div style={{ display:'flex', alignItems:'center', justifyContent:'center', gap:7,
            marginTop:13, color:'var(--ink-3)' }}>
            <ShieldIcon size={16}/>
            <span style={{ fontSize:13.5, fontWeight:700 }}>We'll wake you in time. Rest easy.</span>
          </div>
        </div>
      </div>
    </React.Fragment>
  );
}

// ── SLEEPING ─────────────────────────────────────────────────
function SleepingScreen({ d, radius, ambient = true, onCancel }) {
  const [elapsed, setElapsed] = useState(0);
  useEffect(() => {
    const t = setInterval(() => setElapsed(e => e + 1), 1000);
    return () => clearInterval(t);
  }, []);

  return (
    <div className="anim-fade" style={{
      position:'absolute', inset:0, zIndex:30,
      background:'linear-gradient(180deg, #f3effb 0%, #ece6f7 48%, #e6e0f4 100%)',
      display:'flex', flexDirection:'column', alignItems:'center',
      paddingTop:96, paddingBottom:34,
    }}>
      {/* drifting ambient dots */}
      {ambient && [
        { l:'22%', s:5, dl:0 }, { l:'70%', s:4, dl:2.5 }, { l:'40%', s:6, dl:4.2 },
        { l:'82%', s:3, dl:1.4 }, { l:'12%', s:4, dl:5.5 },
      ].map((p, i) => (
        <div key={i} style={{ position:'absolute', bottom:'30%', left:p.l, width:p.s, height:p.s,
          borderRadius:'50%', background:'var(--brand)', opacity:0.4,
          animation:`drift ${7 + i}s ease-in-out ${p.dl}s infinite` }}/>
      ))}

      {/* status line */}
      <div className="anim-up" style={{ textAlign:'center', marginBottom:54 }}>
        <div style={{ display:'inline-flex', alignItems:'center', gap:8, padding:'8px 16px',
          borderRadius:99, background:'rgba(255,255,255,0.6)', color:'var(--brand-deep)' }}>
          <BellIcon size={17}/>
          <span style={{ fontSize:13.5, fontWeight:800, letterSpacing:0.6, textTransform:'uppercase', whiteSpace:'nowrap' }}>Alarm armed</span>
        </div>
      </div>

      {/* breathing pin */}
      <div style={{ position:'relative', width:150, height:150, marginBottom:46,
        display:'flex', alignItems:'center', justifyContent:'center' }}>
        {[0,1,2].map(i => (
          <div key={i} style={{ position:'absolute', width:150, height:150, borderRadius:'50%',
            border:'2px solid var(--brand)', opacity:0.35,
            animation:`haloPulse 4.2s ease-out ${i * 1.4}s infinite` }}/>
        ))}
        <div style={{ animation:'breathe 4.2s ease-in-out infinite' }}>
          <div style={{ width:96, height:96, borderRadius:'50%',
            background:'radial-gradient(circle at 38% 32%, #a796de, var(--brand) 56%, var(--brand-deep))',
            boxShadow:'0 16px 40px var(--brand-glow), 0 0 0 10px rgba(255,255,255,0.45)',
            display:'flex', alignItems:'center', justifyContent:'center', color:'#fff' }}>
            <PinDot size={42}/>
          </div>
        </div>
      </div>

      {/* destination text */}
      <div className="anim-up" style={{ textAlign:'center', padding:'0 36px', marginBottom:8 }}>
        <div style={{ fontSize:14, fontWeight:800, letterSpacing:1.2, textTransform:'uppercase',
          color:'var(--ink-3)', marginBottom:10 }}>Waking you near</div>
        <div style={{ fontSize:30, fontWeight:800, color:'var(--ink)', lineHeight:1.15 }}>{d.station}</div>
        <div style={{ fontSize:16, fontWeight:600, color:'var(--ink-2)', marginTop:10 }}>
          within {radius} m · you can lock your phone
        </div>
      </div>

      <div style={{ flex:1 }}/>

      {/* sleeping for + cancel */}
      <div style={{ width:'100%', padding:'0 24px', display:'flex', flexDirection:'column', alignItems:'center' }}>
        <div style={{ display:'flex', alignItems:'center', gap:7, marginBottom:18, color:'var(--ink-3)' }}>
          <MoonIcon size={16} style={{ animation:'softGlow 4s ease-in-out infinite' }}/>
          <span style={{ fontSize:14, fontWeight:700 }}>Resting for {fmt(elapsed)}</span>
        </div>
        <button className="press" onClick={onCancel} style={{
          width:'100%', height:64, borderRadius:22, background:'rgba(255,255,255,0.85)',
          color:'var(--ink)', fontSize:19, fontWeight:800, boxShadow:'var(--shadow-card)',
          border:'1px solid var(--surface-2)',
        }}>Cancel alarm</button>
      </div>
    </div>
  );
}

const fmt = (s) => {
  const m = Math.floor(s / 60), ss = s % 60;
  return `${m}:${String(ss).padStart(2,'0')}`;
};

// shared sheet style
function sheet() {
  return {
    position:'absolute', left:0, right:0, bottom:0, zIndex:6,
    background:'var(--surface)', borderRadius:'var(--radius-sheet) var(--radius-sheet) 0 0',
    boxShadow:'var(--shadow-sheet)', paddingBottom:30,
  };
}

// ── SEARCH ───────────────────────────────────────────────────
function SearchScreen({ onPick, onBack }) {
  const [q, setQ] = useState('');
  const ql = q.trim().toLowerCase();
  const filtered = ql
    ? SEARCH_POOL.filter(p => (p.name + ' ' + p.area).toLowerCase().includes(ql))
    : [];

  return (
    <div className="anim-fade" style={{
      position:'absolute', inset:0, zIndex:25, background:'var(--bg)',
      display:'flex', flexDirection:'column',
    }}>
      {/* search field */}
      <div style={{ padding:'48px 14px 10px', display:'flex', alignItems:'center', gap:8 }}>
        <button className="press" onClick={onBack} style={{
          width:46, height:46, borderRadius:99, flexShrink:0, color:'var(--ink)',
          display:'flex', alignItems:'center', justifyContent:'center', background:'transparent',
        }}><BackIcon size={24}/></button>
        <div style={{
          flex:1, height:52, borderRadius:16, background:'var(--surface)',
          boxShadow:'var(--shadow-card)', display:'flex', alignItems:'center',
          gap:10, padding:'0 16px',
        }}>
          <SearchIcon size={21} style={{ color:'var(--brand)', flexShrink:0 }}/>
          <div style={{ flex:1, minWidth:0, display:'flex', alignItems:'center', fontSize:18, fontWeight:700, whiteSpace:'nowrap', overflow:'hidden' }}>
            {q
              ? <span style={{ color:'var(--ink)', whiteSpace:'nowrap', overflow:'hidden' }}>{q}</span>
              : <span style={{ color:'var(--ink-3)' }}>Search station or place</span>}
            <span style={{ width:2, height:22, background:'var(--brand)', marginLeft:1,
              animation:'softGlow 1.1s steps(1) infinite' }}/>
          </div>
          {q && (
            <button className="press" onClick={() => setQ('')} style={{
              width:26, height:26, borderRadius:99, flexShrink:0, color:'var(--ink-3)',
              display:'flex', alignItems:'center', justifyContent:'center', background:'var(--surface-2)',
            }}><CloseIcon size={16}/></button>
          )}
        </div>
      </div>

      {/* results */}
      <div className="no-scrollbar" style={{ flex:1, overflowY:'auto', padding:'4px 12px 8px' }}>
        {!q && (
          <React.Fragment>
            <SheetLabel>Recent</SheetLabel>
            <div style={{ marginBottom:18 }}>
              {RECENTS.map(r => <SearchRow key={r.id} p={r} onClick={() => onPick(r)} recent />)}
            </div>
            <SheetLabel>Suggestions</SheetLabel>
            <div>
              {[SEARCH_POOL[0], SEARCH_POOL[3], SEARCH_POOL[5], SEARCH_POOL[7]].map(p =>
                <SearchRow key={p.id} p={p} onClick={() => onPick(p)} />)}
            </div>
          </React.Fragment>
        )}
        {q && filtered.length > 0 &&
          filtered.map(p => <SearchRow key={p.id} p={p} q={ql} onClick={() => onPick(p)} />)}
        {q && filtered.length === 0 && (
          <div style={{ textAlign:'center', padding:'48px 24px', color:'var(--ink-3)' }}>
            <div style={{ fontSize:17, fontWeight:700 }}>No places found</div>
            <div style={{ fontSize:14, fontWeight:600, marginTop:6 }}>Try another station or area</div>
          </div>
        )}
      </div>

      {/* keyboard */}
      <SearchKeyboard
        onKey={(c) => setQ(v => v + c)}
        onDel={() => setQ(v => v.slice(0, -1))}
        onSpace={() => setQ(v => v + ' ')}
        onEnter={() => { const top = ql ? filtered[0] : RECENTS[0]; top && onPick(top); }}
      />
    </div>
  );
}

function SearchRow({ p, onClick, recent = false }) {
  return (
    <button className="press" onClick={onClick} style={{
      width:'100%', display:'flex', alignItems:'center', gap:14, textAlign:'left',
      background:'transparent', padding:'13px 8px', borderRadius:16,
    }}>
      <div style={{ width:44, height:44, borderRadius:14, flexShrink:0,
        background:'var(--surface)', boxShadow:'var(--shadow-card)',
        display:'flex', alignItems:'center', justifyContent:'center',
        color: recent ? 'var(--ink-3)' : 'var(--brand)' }}>
        {recent ? <RecentIcon size={21}/> : <PinDot size={21}/>}
      </div>
      <div style={{ flex:1, minWidth:0 }}>
        <div style={{ fontSize:17, fontWeight:700, color:'var(--ink)', overflow:'hidden', textOverflow:'ellipsis', whiteSpace:'nowrap' }}>{p.name}</div>
        <div style={{ fontSize:14, fontWeight:600, color:'var(--ink-3)' }}>{p.area}</div>
      </div>
      <span style={{ fontSize:14, fontWeight:700, color:'var(--ink-3)', whiteSpace:'nowrap' }}>{p.eta}</span>
    </button>
  );
}

function SearchKeyboard({ onKey, onDel, onSpace, onEnter }) {
  const rows = [['q','w','e','r','t','y','u','i','o','p'], ['a','s','d','f','g','h','j','k','l'], ['z','x','c','v','b','n','m']];
  const Key = ({ ch, flex = 1, children, action, accent }) => (
    <button className="press" onClick={() => action ? action() : onKey(ch)} style={{
      flex, height:46, minWidth:0, borderRadius:9,
      background: accent ? 'var(--brand)' : 'var(--surface)',
      color: accent ? '#fff' : 'var(--ink)',
      boxShadow:'0 1px 2px rgba(80,65,140,0.12)',
      fontSize:19, fontWeight:700, fontFamily:'inherit',
      display:'flex', alignItems:'center', justifyContent:'center',
    }}>{children || ch}</button>
  );
  return (
    <div style={{ background:'var(--surface-3)', padding:'10px 6px 30px',
      display:'flex', flexDirection:'column', gap:8 }}>
      <div style={{ display:'flex', gap:6 }}>{rows[0].map(c => <Key key={c} ch={c}/>)}</div>
      <div style={{ display:'flex', gap:6, padding:'0 20px' }}>{rows[1].map(c => <Key key={c} ch={c}/>)}</div>
      <div style={{ display:'flex', gap:6 }}>
        <Key flex={1.5} accent action={onEnter}><SearchIcon size={20}/></Key>
        {rows[2].map(c => <Key key={c} ch={c}/>)}
        <Key flex={1.5} action={onDel}><CloseIcon size={20}/></Key>
      </div>
      <div style={{ display:'flex', gap:6 }}>
        <Key flex={1.6} action={onSpace}><span style={{ fontSize:13, fontWeight:800, color:'var(--ink-3)' }}>?123</span></Key>
        <Key flex={5} action={onSpace}><span style={{ fontSize:13, fontWeight:700, color:'var(--ink-3)' }}>space</span></Key>
        <Key flex={1.6} accent action={onEnter}><span style={{ fontSize:14, fontWeight:800 }}>Go</span></Key>
      </div>
    </div>
  );
}

// ── tweaks ───────────────────────────────────────────────────
const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "accent": "#8a7dc8",
  "radius": 500,
  "ambient": true
}/*EDITMODE-END*/;

const PALETTES = {
  '#8a7dc8': { brand:'#8a7dc8', deep:'#7164b8', soft:'#e7e1f8', tint:'#f1ecfb', rgb:'138,125,200' }, // lavender
  '#7faa8e': { brand:'#7faa8e', deep:'#5f8f72', soft:'#dceae0', tint:'#eef6f0', rgb:'127,170,142' }, // sage
  '#6f93cf': { brand:'#6f93cf', deep:'#5577ba', soft:'#dfe8f6', tint:'#eef3fb', rgb:'111,147,207' }, // blue
};

// ── SHELL ────────────────────────────────────────────────────
function Wakey({ defaultRadius, ambient }) {
  const [screen, setScreen] = useState('home');
  const [sel, setSel] = useState(null);
  const [radius, setRadius] = useState(defaultRadius);
  useEffect(() => { setRadius(defaultRadius); }, [defaultRadius]);

  const camera = (screen === 'home' || screen === 'search' || !sel) ? { scale:1, x:0, y:0 } : sel.cam;
  const showPin = screen === 'confirm';

  return (
    <AndroidDevice immersive>
      <div style={{ position:'absolute', inset:0, overflow:'hidden', background:'var(--map-land)' }}>
        <MapCanvas camera={camera} dim={screen !== 'home'} />

        {/* destination pin (confirm) */}
        {showPin && (
          <div className="anim-pop" style={{ position:'absolute', left:'50%', top:'39%', zIndex:5 }}>
            <WakePin radius={radiusToPx(radius)} pulsing />
          </div>
        )}

        {screen === 'home' &&
          <HomeScreen
            onPick={(d) => { setSel(d); setScreen('confirm'); }}
            onSearch={() => setScreen('search')} />}

        {screen === 'search' &&
          <SearchScreen
            onPick={(d) => { setSel(d); setScreen('confirm'); }}
            onBack={() => setScreen('home')} />}

        {screen === 'confirm' && sel &&
          <ConfirmScreen d={sel} radius={radius} setRadius={setRadius}
            onSleep={() => setScreen('sleeping')} onBack={() => setScreen('home')} />}

        {screen === 'sleeping' && sel &&
          <SleepingScreen d={sel} radius={radius} ambient={ambient} onCancel={() => setScreen('home')} />}
      </div>
    </AndroidDevice>
  );
}

function Stage() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const [scale, setScale] = useState(1);

  // apply accent palette to CSS variables
  useEffect(() => {
    const p = PALETTES[t.accent] || PALETTES['#8a7dc8'];
    const r = document.documentElement.style;
    r.setProperty('--brand', p.brand);
    r.setProperty('--brand-deep', p.deep);
    r.setProperty('--brand-soft', p.soft);
    r.setProperty('--brand-tint', p.tint);
    r.setProperty('--brand-rgb', p.rgb);
    r.setProperty('--brand-glow', `rgba(${p.rgb},0.35)`);
  }, [t.accent]);

  useEffect(() => {
    const fit = () => {
      const pad = 40;
      const s = Math.min((window.innerWidth - pad) / 412, (window.innerHeight - pad) / 892, 1);
      setScale(s);
    };
    fit();
    window.addEventListener('resize', fit);
    return () => window.removeEventListener('resize', fit);
  }, []);

  return (
    <React.Fragment>
      <div style={{ transform:`scale(${scale})`, transformOrigin:'center center' }}>
        <Wakey defaultRadius={t.radius} ambient={t.ambient} />
      </div>

      <TweaksPanel>
        <TweakSection label="Look" />
        <TweakColor label="Accent" value={t.accent}
          options={['#8a7dc8', '#7faa8e', '#6f93cf']}
          onChange={(v) => setTweak('accent', v)} />
        <TweakSection label="Wake alarm" />
        <TweakSlider label="Default wake zone" value={t.radius} min={200} max={1500} step={50} unit=" m"
          onChange={(v) => setTweak('radius', v)} />
        <TweakToggle label="Ambient motion (sleep)" value={t.ambient}
          onChange={(v) => setTweak('ambient', v)} />
      </TweaksPanel>
    </React.Fragment>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<Stage/>);

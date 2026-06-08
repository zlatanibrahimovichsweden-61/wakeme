// map.jsx — abstract, low-detail "almost a texture" map backdrop.
// MapCanvas takes a `camera` { scale, x, y } and eases between states.

function MapCanvas({ camera = { scale: 1, x: 0, y: 0 }, dim = false }) {
  return (
    <div style={{ position: 'absolute', inset: 0, overflow: 'hidden', background: 'var(--map-land)' }}>
      <div style={{
        position: 'absolute',
        width: 560, height: 1120, left: '50%', top: '50%',
        transform: `translate(-50%,-50%) translate(${camera.x}px, ${camera.y}px) scale(${camera.scale})`,
        transformOrigin: 'center center',
        transition: 'transform 1.1s cubic-bezier(.6,.01,.2,1)',
        filter: dim ? 'saturate(0.7) brightness(1.03)' : 'none',
      }}>
        <svg width="560" height="1120" viewBox="0 0 560 1120" style={{ display: 'block' }}>
          <defs>
            <linearGradient id="landGrad" x1="0" y1="0" x2="0.6" y2="1">
              <stop offset="0" stopColor="#f1ecf9"/>
              <stop offset="1" stopColor="#e7e0f4"/>
            </linearGradient>
            <filter id="soft"><feGaussianBlur stdDeviation="4"/></filter>
          </defs>

          <rect width="560" height="1120" fill="url(#landGrad)"/>

          {/* ── water: a calm river sweeping through ── */}
          <path d="M-40,250 C120,300 150,470 300,520 C440,565 470,720 430,900 C410,990 470,1080 560,1120 L640,1120 L640,-40 L-40,-40 Z"
                fill="var(--map-water)" opacity="0.85"/>
          <ellipse cx="120" cy="880" rx="140" ry="92" fill="var(--map-water)" opacity="0.8"/>

          {/* ── parks: soft sage blobs ── */}
          <ellipse cx="430" cy="200" rx="120" ry="96" fill="var(--map-park)" opacity="0.9"/>
          <rect x="40" y="470" width="170" height="150" rx="46" fill="var(--map-park)" opacity="0.85"/>
          <ellipse cx="470" cy="640" rx="86" ry="120" fill="var(--map-park)" opacity="0.8"/>

          {/* ── faint district blocks (very low detail) ── */}
          <g fill="var(--map-land-2)" opacity="0.7">
            <rect x="250" y="640" width="120" height="90" rx="22"/>
            <rect x="60"  y="690" width="120" height="110" rx="24"/>
            <rect x="300" y="780" width="110" height="100" rx="22"/>
            <rect x="120" y="180" width="130" height="120" rx="26"/>
          </g>

          {/* ── road network: smooth, sparse ── */}
          <g fill="none" stroke="var(--map-road-2)" strokeWidth="9" opacity="0.85" strokeLinecap="round">
            <path d="M-20,420 C140,400 260,470 360,640 C440,775 470,930 540,1040"/>
            <path d="M70,-20 C90,200 40,420 120,620 C190,800 160,980 230,1140"/>
            <path d="M560,300 C420,330 320,300 200,360 C90,415 20,470 -20,640"/>
          </g>
          <g fill="none" stroke="var(--map-road)" strokeWidth="6" opacity="0.95" strokeLinecap="round">
            <path d="M-20,560 C160,520 340,560 560,520"/>
            <path d="M300,-20 C330,260 300,520 360,760 C400,920 360,1040 320,1140"/>
            <path d="M-20,860 C170,820 380,880 560,820"/>
          </g>
          {/* hair-thin lanes for faint texture */}
          <g fill="none" stroke="#ffffff" strokeWidth="2.4" opacity="0.6" strokeLinecap="round">
            <path d="M120,40 C140,260 120,520 180,760"/>
            <path d="M-20,360 C180,340 360,380 560,340"/>
            <path d="M-20,700 C160,680 360,720 560,690"/>
            <path d="M420,40 C440,260 420,520 470,760"/>
          </g>
        </svg>
      </div>

      {/* gentle vignette so the sheet floats over a softer edge */}
      <div style={{
        position: 'absolute', inset: 0, pointerEvents: 'none',
        background: 'radial-gradient(130% 80% at 50% 36%, transparent 56%, rgba(110,95,170,0.07) 100%)',
      }}/>
    </div>
  );
}

// A destination pin with an animated radius "wake zone" ring.
function WakePin({ radius = 92, pulsing = false, color = 'var(--brand)' }) {
  return (
    <div style={{ position: 'relative', width: 0, height: 0 }}>
      {/* radius ring */}
      <div style={{
        position: 'absolute', left: -radius, top: -radius,
        width: radius * 2, height: radius * 2, borderRadius: '50%',
        background: 'radial-gradient(circle, rgba(var(--brand-rgb),0.16) 0%, rgba(var(--brand-rgb),0.10) 60%, rgba(var(--brand-rgb),0.04) 100%)',
        border: '2px solid rgba(var(--brand-rgb),0.5)',
        boxShadow: '0 0 0 1px rgba(255,255,255,0.4) inset',
      }}/>
      {pulsing && [0, 1].map(i => (
        <div key={i} style={{
          position: 'absolute', left: -radius, top: -radius,
          width: radius * 2, height: radius * 2, borderRadius: '50%',
          border: '2px solid rgba(var(--brand-rgb),0.45)',
          animation: `haloPulse 3.4s ease-out ${i * 1.7}s infinite`,
        }}/>
      ))}
      {/* the pin head */}
      <div style={{
        position: 'absolute', left: -19, top: -50,
        width: 38, height: 38, borderRadius: '50% 50% 50% 6px',
        transform: 'rotate(45deg)',
        background: `linear-gradient(135deg, var(--brand) 0%, var(--brand-deep) 100%)`,
        boxShadow: '0 8px 18px rgba(113,100,184,0.45)',
      }}/>
      <div style={{
        position: 'absolute', left: -9, top: -41, width: 18, height: 18,
        borderRadius: '50%', background: '#fff',
      }}/>
    </div>
  );
}

Object.assign(window, { MapCanvas, WakePin });

// icons.jsx — simple, friendly rounded line icons (currentColor, 2px strokes)

function Icon({ d, size = 24, sw = 2, fill = 'none', children, vb = 24, style }) {
  return (
    <svg width={size} height={size} viewBox={`0 0 ${vb} ${vb}`} fill={fill}
         stroke="currentColor" strokeWidth={sw} strokeLinecap="round"
         strokeLinejoin="round" style={style}>
      {d ? <path d={d} /> : children}
    </svg>
  );
}

const SearchIcon  = (p) => <Icon {...p}><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/></Icon>;
const CloseIcon   = (p) => <Icon {...p}><path d="M6 6l12 12M18 6L6 18"/></Icon>;
const ChevronR    = (p) => <Icon {...p} sw={2.4}><path d="M9 5l7 7-7 7"/></Icon>;
const ChevronDown = (p) => <Icon {...p} sw={2.4}><path d="M5 9l7 7 7-7"/></Icon>;
const ChevronUp   = (p) => <Icon {...p} sw={2.4}><path d="M5 15l7-7 7 7"/></Icon>;
const ClockIcon   = (p) => <Icon {...p}><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3.5 2"/></Icon>;
const LocateIcon  = (p) => <Icon {...p}><circle cx="12" cy="12" r="3.4"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/></Icon>;
const BackIcon    = (p) => <Icon {...p} sw={2.4}><path d="M15 5l-7 7 7 7"/></Icon>;
const BellIcon    = (p) => <Icon {...p}><path d="M18 8a6 6 0 10-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 01-3.4 0"/></Icon>;
const RecentIcon  = (p) => <Icon {...p}><path d="M3 12a9 9 0 109-9 9 9 0 00-6.4 2.6L3 8"/><path d="M3 4v4h4"/><path d="M12 8v4l3 2"/></Icon>;
const PinDot      = (p) => <Icon {...p}><path d="M12 21s-7-6.5-7-11a7 7 0 0114 0c0 4.5-7 11-7 11z"/><circle cx="12" cy="10" r="2.6"/></Icon>;
const MoonIcon    = (p) => <Icon {...p} fill="currentColor" sw={0}><path d="M20 14.5A8 8 0 019.5 4 7 7 0 1020 14.5z"/></Icon>;
const ShieldIcon  = (p) => <Icon {...p}><path d="M12 3l7 3v5c0 4.4-3 7.8-7 9-4-1.2-7-4.6-7-9V6z"/><path d="M9 12l2 2 4-4"/></Icon>;
const VolumeIcon  = (p) => <Icon {...p}><path d="M5 9v6h4l5 4V5L9 9z"/><path d="M17 8.5a4 4 0 010 7"/></Icon>;

Object.assign(window, {
  WIcon: Icon,
  SearchIcon, CloseIcon, ChevronR, ChevronDown, ChevronUp, ClockIcon,
  LocateIcon, BackIcon, BellIcon, RecentIcon, PinDot, MoonIcon, ShieldIcon, VolumeIcon,
});

// ── Device position calculator ─────────────────────────────────────────────────
// Distributes N devices evenly around the radar circle.
// Skips the upper-left quadrant where the admin node sits.
function getDevicePosition(index, total) {
  const cx = 210, cy = 210, r = 150
  // Start at top-right and go clockwise, leaving upper-left for admin
  const startAngle = -Math.PI / 6         // -30 degrees (slightly right of top)
  const totalAngle =  Math.PI * 1.7       // 306 degrees — leaves gap for admin
  const angle = startAngle + (totalAngle * index / Math.max(total, 1))
  return {
    x: Math.round(cx + r * Math.cos(angle)),
    y: Math.round(cy + r * Math.sin(angle))
  }
}
 
// ── Device node component ──────────────────────────────────────────────────────
function DeviceNode({ x, y, label, sublabel, color = "#2a5a50", delay = "0s" }) {
  return (
    <g>
      <circle
        cx={x} cy={y} r="12"
        fill="none" stroke={color} strokeWidth="1"
        opacity="0.6"
        style={{ animation: `node-pulse 2.5s ease infinite`, animationDelay: delay }}
      />
      <circle cx={x} cy={y} r="7" fill={color} opacity="0.75"/>
      <line
        x1="210" y1="210" x2={x} y2={y}
        stroke={color} strokeWidth="0.5" opacity="0.2" strokeDasharray="4 4"
      />
      <text
        x={x} y={y + 20}
        textAnchor="middle"
        fontFamily="'Share Tech Mono'"
        fontSize="8" fill={color} opacity="0.8" letterSpacing="1"
      >
        {label}
      </text>
      {sublabel && (
        <text
          x={x} y={y + 30}
          textAnchor="middle"
          fontFamily="'Share Tech Mono'"
          fontSize="7" fill={color} opacity="0.5"
        >
          {sublabel}
        </text>
      )}
    </g>
  )
}
 
// ── Main RadarMap ──────────────────────────────────────────────────────────────
export default function RadarMap({ threat, neutralised, deviceData }) {
  const hasAttacker = !!threat
  const ip = threat?.attacker_ip || ""
 
  // Separate out own device (admin), gateway, and guests
  const { devices = [], own_ip = "", gateway_ip = "" } = deviceData
 
  const adminDevice = devices.find(d => d.ip === own_ip)
  const guestDevices = devices.filter(
    d => d.ip !== own_ip && d.ip !== gateway_ip
  )
 
  return (
    <div className="radar-wrap">
      <svg className="radar-svg" viewBox="0 0 420 420">
        <defs>
          <radialGradient id="sweepGrad" cx="210" cy="210" r="200" gradientUnits="userSpaceOnUse">
            <stop offset="0%"   stopColor="#00ddb4" stopOpacity="0.3"/>
            <stop offset="100%" stopColor="#00ddb4" stopOpacity="0"/>
          </radialGradient>
          <radialGradient id="bgGrad" cx="50%" cy="50%" r="50%">
            <stop offset="0%"   stopColor="#001f18" stopOpacity="0.9"/>
            <stop offset="100%" stopColor="#030810" stopOpacity="0.4"/>
          </radialGradient>
          <filter id="glow">
            <feGaussianBlur stdDeviation="3" result="blur"/>
            <feMerge>
              <feMergeNode in="blur"/>
              <feMergeNode in="SourceGraphic"/>
            </feMerge>
          </filter>
        </defs>
 
        {/* Background */}
        <circle cx="210" cy="210" r="200" fill="url(#bgGrad)"/>
 
        {/* Rings */}
        <circle cx="210" cy="210" r="50"  fill="none" stroke="#00ddb4" strokeWidth="0.5" opacity="0.15"/>
        <circle cx="210" cy="210" r="100" fill="none" stroke="#00ddb4" strokeWidth="0.5" opacity="0.12"/>
        <circle cx="210" cy="210" r="150" fill="none" stroke="#00ddb4" strokeWidth="0.5" opacity="0.10"/>
        <circle cx="210" cy="210" r="200" fill="none" stroke="#00ddb4" strokeWidth="1"   opacity="0.08"/>
 
        {/* Crosshairs */}
        <line x1="210" y1="10"  x2="210" y2="410" stroke="#00ddb4" strokeWidth="0.5" opacity="0.10"/>
        <line x1="10"  y1="210" x2="410" y2="210" stroke="#00ddb4" strokeWidth="0.5" opacity="0.10"/>
        <line x1="68"  y1="68"  x2="352" y2="352" stroke="#00ddb4" strokeWidth="0.5" opacity="0.06"/>
        <line x1="352" y1="68"  x2="68"  y2="352" stroke="#00ddb4" strokeWidth="0.5" opacity="0.06"/>
 
        {/* Radar sweep */}
        <g className="radar-sweep-group">
          <path d="M210,210 L210,10 A200,200 0 0,1 375,310 Z" fill="url(#sweepGrad)"/>
          <line
            x1="210" y1="210" x2="210" y2="10"
            stroke="#00ddb4" strokeWidth="2" opacity="0.9" filter="url(#glow)"
          />
        </g>
 
        {/* Router — always center */}
        <g filter="url(#glow)">
          <circle cx="210" cy="210" r="20"
            fill="none" stroke="#00ddb4" strokeWidth="2" opacity="0.8"/>
          <circle cx="210" cy="210" r="20"
            fill="none" stroke="#00ddb4" strokeWidth="10" opacity="0.05"
            className="node-ring-pulse"/>
          <circle cx="210" cy="210" r="10" fill="#00ddb4" opacity="0.95"/>
          <circle cx="210" cy="210" r="4"  fill="#030810"/>
          <text x="210" y="238"
            textAnchor="middle"
            fontFamily="'Share Tech Mono'"
            fontSize="9" fill="#00ddb4" opacity="0.9" letterSpacing="2">
            ROUTER
          </text>
          {gateway_ip && (
            <text x="210" y="249"
              textAnchor="middle"
              fontFamily="'Share Tech Mono'"
              fontSize="7" fill="#4a7a70">
              {gateway_ip}
            </text>
          )}
        </g>
 
        {/* Admin device — fixed upper-left */}
        <g filter="url(#glow)">
          <circle cx="100" cy="110" r="14"
            fill="none" stroke="#00ddb4" strokeWidth="1.5" opacity="0.75"/>
          <circle cx="100" cy="110" r="14"
            fill="none" stroke="#00ddb4" strokeWidth="8" opacity="0.05"
            className="node-ring-pulse" style={{animationDelay:'0.7s'}}/>
          <circle cx="100" cy="110" r="8"  fill="#00ddb4" opacity="0.85"/>
          <circle cx="100" cy="110" r="3"  fill="#030810"/>
          <line
            x1="210" y1="210" x2="100" y2="110"
            stroke="#00ddb4" strokeWidth="0.5" opacity="0.2" strokeDasharray="4 4"
          />
          <text x="100" y="132"
            textAnchor="middle"
            fontFamily="'Share Tech Mono'"
            fontSize="8" fill="#00ddb4" opacity="0.8" letterSpacing="1">
            ADMIN
          </text>
          <text x="100" y="143"
            textAnchor="middle"
            fontFamily="'Share Tech Mono'"
            fontSize="7" fill="#4a7a70">
            {own_ip || "this device"}
          </text>
        </g>
 
        {/* Real guest devices — dynamically positioned */}
        {guestDevices.length > 0
          ? guestDevices.map((device, i) => {
              const pos = getDevicePosition(i, guestDevices.length)
              return (
                <DeviceNode
                  key={device.mac || device.ip}
                  x={pos.x}
                  y={pos.y}
                  label={`DEVICE·${i + 1}`}
                  sublabel={device.ip}
                  delay={`${i * 0.4}s`}
                />
              )
            })
          : (
            // No devices yet — show scanning indicator
            <text
              x="210" y="320"
              textAnchor="middle"
              fontFamily="'Share Tech Mono'"
              fontSize="9" fill="#4a7a70" letterSpacing="2"
            >
              SCANNING NETWORK...
            </text>
          )
        }
 
        {/* Attacker node — shown during threat */}
        {hasAttacker && (
          <g style={{animation: "entry-slide 0.4s ease"}}>
            <circle cx="335" cy="65" r="22"
              fill="none" stroke="#ff2d55" strokeWidth="2"
              opacity="0.2" className="attacker-ring-pulse"/>
            <circle cx="335" cy="65" r="14"
              fill="#ff2d55" opacity="0.9" filter="url(#glow)"/>
            <circle cx="335" cy="65" r="6" fill="#030810"/>
            <text x="335" y="42"
              textAnchor="middle"
              fontFamily="'Orbitron'"
              fontSize="9" fill="#ff2d55" fontWeight="700" letterSpacing="1">
              ⚠ HOSTILE
            </text>
            <text x="335" y="90"
              textAnchor="middle"
              fontFamily="'Share Tech Mono'"
              fontSize="8" fill="#ff2d55" letterSpacing="1">
              ATTACKER
            </text>
            <text x="335" y="101"
              textAnchor="middle"
              fontFamily="'Share Tech Mono'"
              fontSize="7" fill="#ff2d55" opacity="0.7">
              {ip}
            </text>
          </g>
        )}
 
        {/* Attack lines */}
        <line x1="335" y1="65" x2="210" y2="210"
          className={`attack-line ${hasAttacker ? "visible" : ""}`}/>
        <line x1="335" y1="65" x2="100" y2="110"
          className={`attack-line ${hasAttacker ? "visible" : ""}`}/>
 
        {/* Sentinel label */}
        <text
          x="210" y="408"
          textAnchor="middle"
          fontFamily="'Share Tech Mono'"
          fontSize="8" fill="#00ddb4" opacity="0.3" letterSpacing="3">
          VIGILO SENTINEL — MONITORING ACTIVE
        </text>
      </svg>
 
      {/* Neutralised overlay */}
      <div className={`neutralised-overlay ${neutralised ? "show" : ""}`}>
        <div className="neutralised-text">THREAT NEUTRALISED</div>
        <div className="neutralised-sub">ATTACKER REMOVED FROM NETWORK</div>
      </div>
    </div>
  )
}
 
import { useState, useEffect } from "react"
 
function AnimatedNumber({ value }) {
  const [display, setDisplay] = useState(value)
 
  useEffect(() => {
    if (value === display) return
    const step = value > display ? 1 : -1
    const timer = setInterval(() => {
      setDisplay((prev) => {
        if (prev === value) { clearInterval(timer); return prev }
        return prev + step
      })
    }, 80)
    return () => clearInterval(timer)
  }, [value])
 
  return <>{display}</>
}
 
export default function NetworkStats({ threats, uptime }) {
  const neutralised    = threats.filter((t) => t.status === "neutralised").length
  const uniqueAttackers = new Set(threats.map((t) => t.attacker_mac)).size
 
  return (
    <div className="stats-grid">
      <div className="stat">
        <div className="stat-val cyan"><AnimatedNumber value={threats.length}/></div>
        <div className="stat-label">Detected</div>
      </div>
      <div className="stat">
        <div className="stat-val cyan"><AnimatedNumber value={neutralised}/></div>
        <div className="stat-label">Neutralised</div>
      </div>
      <div className="stat">
        <div className="stat-val red"><AnimatedNumber value={uniqueAttackers}/></div>
        <div className="stat-label">Active Threats</div>
      </div>
      <div className="stat">
        <div className="stat-val amber">{uptime}</div>
        <div className="stat-label">Uptime</div>
      </div>
    </div>
  )
}
 
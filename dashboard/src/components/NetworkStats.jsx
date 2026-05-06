export default function NetworkStats({ threats }) {
  const neutralised = threats.filter((t) => t.status === "neutralised").length
  const uniqueAttackers = new Set(threats.map((t) => t.attacker_mac)).size
  const lastSeen = threats.length > 0
    ? new Date(threats[0].timestamp).toLocaleTimeString()
    : "None"
 
  const stats = [
    { label: "Threats detected", value: threats.length, accent: "accent-red" },
    { label: "Neutralised", value: neutralised, accent: "accent-green" },
    { label: "Unique attackers", value: uniqueAttackers, accent: "accent-amber" },
    { label: "Last threat", value: lastSeen, accent: "accent-blue" },
  ]
 
  return (
    <div className="stats-grid">
      {stats.map((s) => (
        <div key={s.label} className={`stat-card ${s.accent}`}>
          <span className="stat-value">{s.value}</span>
          <span className="stat-label">{s.label}</span>
        </div>
      ))}
    </div>
  )
}
 
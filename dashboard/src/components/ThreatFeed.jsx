export default function ThreatFeed({ threats, onClear }) {
  const formatTime = (iso) => {
    try { return new Date(iso).toLocaleString() } catch { return iso }
  }
 
  return (
    <section className="threat-feed">
      <div className="feed-header">
        <h3 className="feed-title">Threat log</h3>
        {threats.length > 0 && (
          <button className="btn-clear" onClick={onClear}>Clear log</button>
        )}
      </div>
 
      {threats.length === 0 ? (
        <div className="feed-empty">
          <p>No threats detected this session.</p>
          <p className="feed-empty-sub">Vigilo is watching your network.</p>
        </div>
      ) : (
        <ul className="feed-list">
          {threats.map((t) => (
            <li key={t.id} className="feed-item">
              <div className="feed-item-header">
                <span className="threat-badge">ARP spoof</span>
                <span className={`status-tag status-${t.status}`}>
                  {t.status === "neutralised" ? "Neutralised" : t.status}
                </span>
                <span className="feed-time">{formatTime(t.timestamp)}</span>
              </div>
              <div className="feed-item-body">
                <div className="feed-detail">
                  <span className="detail-label">Attacker device</span>
                  <span className="detail-value mono">{t.attacker_mac}</span>
                </div>
                <div className="feed-detail">
                  <span className="detail-label">Attacker IP</span>
                  <span className="detail-value mono">{t.attacker_ip}</span>
                </div>
                <div className="feed-detail">
                  <span className="detail-label">Targeted IP</span>
                  <span className="detail-value mono">{t.spoofed_ip}</span>
                </div>
                <div className="feed-detail">
                  <span className="detail-label">Action taken</span>
                  <span className="detail-value">Corrective ARP broadcast — attacker mapping overwritten</span>
                </div>
              </div>
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}
 
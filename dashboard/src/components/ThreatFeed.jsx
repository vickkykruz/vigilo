export default function ThreatFeed({ threats, blinking }) {
  const formatTime = (iso) => {
    try { return new Date(iso).toUTCString().slice(17, 25) + " UTC" }
    catch { return iso }
  }
 
  return (
    <>
      <div className="log-header">
        <span>◈ Threat Log</span>
        {blinking && <span className="log-blink"/>}
      </div>
 
      <div className="log-feed">
        {threats.length === 0 ? (
          <div className="log-empty">
            NO THREATS DETECTED<br/>
            <span style={{opacity:0.5, fontSize:'9px'}}>
              SENTINEL MONITORING ALL NETWORK TRAFFIC
            </span>
          </div>
        ) : (
          threats.map((t) => (
            <div key={t.id} className="log-entry">
              <div className="log-time">{formatTime(t.timestamp)}</div>
              <div className="log-type">▶ ARP SPOOFING DETECTED</div>
              <div className="log-row"><span>MAC</span><span className="val">{t.attacker_mac}</span></div>
              <div className="log-row"><span>IP &nbsp;</span><span className="val">{t.attacker_ip}</span></div>
              <div className="log-row"><span>VIA</span><span className="val">{t.interface || 'eth0'}</span></div>
              <div className="log-result">✓ CORRECTIVE ARP BROADCAST — NEUTRALISED</div>
            </div>
          ))
        )}
      </div>
    </>
  )
}
 
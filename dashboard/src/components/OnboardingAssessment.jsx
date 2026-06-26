import { useEffect, useState } from "react"
 
// Animated count-up for the health score
function ScoreCounter({ target }) {
  const [val, setVal] = useState(0)
  useEffect(() => {
    let current = 0
    const step = Math.max(1, Math.ceil(target / 40))
    const timer = setInterval(() => {
      current += step
      if (current >= target) { current = target; clearInterval(timer) }
      setVal(current)
    }, 25)
    return () => clearInterval(timer)
  }, [target])
  return <>{val}</>
}
 
function scoreColor(score) {
  if (score >= 85) return "var(--cyan)"
  if (score >= 60) return "var(--amber)"
  return "var(--red)"
}
 
export default function OnboardingAssessment({ assessment, onContinue }) {
  const { score = 0, status, summary, findings = [], actions = [], device_count } = assessment
  const color = scoreColor(score)
 
  // Score ring geometry
  const radius = 84
  const circumference = 2 * Math.PI * radius
  const offset = circumference - (score / 100) * circumference
 
  return (
    <div className="assessment-overlay">
      <div className="assessment-card">
 
        {/* Header */}
        <div className="assessment-header">
          <div className="assessment-eyebrow">VIGILO — FIRST-RUN NETWORK ASSESSMENT</div>
          <h1 className="assessment-title">Your Network Report</h1>
          <p className="assessment-sub">
            Vigilo has scanned your network. Here is what it found.
          </p>
        </div>
 
        {/* Score + summary */}
        <div className="assessment-score-row">
          <div className="score-ring-wrap">
            <svg className="score-ring" viewBox="0 0 200 200">
              <circle cx="100" cy="100" r={radius} fill="none"
                stroke="rgba(0,221,180,0.08)" strokeWidth="12"/>
              <circle cx="100" cy="100" r={radius} fill="none"
                stroke={color} strokeWidth="12" strokeLinecap="round"
                strokeDasharray={circumference}
                strokeDashoffset={offset}
                transform="rotate(-90 100 100)"
                style={{ transition: "stroke-dashoffset 1.4s ease" }}/>
              <text x="100" y="96" textAnchor="middle"
                fontFamily="'Orbitron'" fontSize="46" fontWeight="900"
                fill={color}>
                <ScoreCounter target={score}/>
              </text>
              <text x="100" y="124" textAnchor="middle"
                fontFamily="'Share Tech Mono'" fontSize="12"
                fill="var(--text-dim)" letterSpacing="2">
                / 100
              </text>
            </svg>
            <div className="score-label" style={{ color }}>
              {status === "good" ? "PROTECTED"
                : status === "fair" ? "FAIR" : "NEEDS ATTENTION"}
            </div>
          </div>
 
          <div className="assessment-summary">
            <p className="summary-text">{summary}</p>
            <div className="summary-meta">
              <span className="meta-dot" style={{ background: color }}/>
              {device_count} device(s) detected on your network
            </div>
          </div>
        </div>
 
        {/* Findings */}
        <div className="assessment-section-title">What we found</div>
        <div className="findings-list">
          {findings.map((f, i) => (
            <div key={i} className={`finding finding-${f.level}`}>
              <div className="finding-icon">
                {f.level === "good" ? "✓" : "!"}
              </div>
              <div className="finding-body">
                <div className="finding-title">{f.title}</div>
                <div className="finding-detail">{f.detail}</div>
              </div>
            </div>
          ))}
        </div>
 
        {/* Actions */}
        {actions.length > 0 && (
          <>
            <div className="assessment-section-title">What you should do</div>
            <div className="actions-list">
              {actions.map((a, i) => (
                <div key={i} className="action-item">
                  <div className="action-number">{i + 1}</div>
                  <div className="action-text">{a.text}</div>
                </div>
              ))}
            </div>
          </>
        )}
 
        {/* Continue */}
        <button className="assessment-continue" onClick={onContinue}>
          CONTINUE TO DASHBOARD
        </button>
        <p className="assessment-footnote">
          Vigilo is now protecting your network. You can return to this report anytime.
        </p>
      </div>
    </div>
  )
}
 
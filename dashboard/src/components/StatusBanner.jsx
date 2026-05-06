export default function StatusBanner({ status, threatCount }) {
  const isSafe = status === "safe"
  return (
    <div className={`status-banner ${isSafe ? "status-safe" : "status-threat"}`}>
      <div className="status-icon-wrap">
        <span className={`status-icon ${isSafe ? "icon-safe" : "icon-threat"}`} />
      </div>
      <div className="status-text">
        <h2 className="status-title">
          {isSafe ? "Your network is safe" : "Threat detected and neutralised"}
        </h2>
        <p className="status-sub">
          {isSafe
            ? "Vigilo is actively monitoring your Wi-Fi. No suspicious activity detected."
            : `${threatCount} suspicious device${threatCount !== 1 ? "s were" : " was"} automatically removed from your network.`}
        </p>
      </div>
    </div>
  )
}
 
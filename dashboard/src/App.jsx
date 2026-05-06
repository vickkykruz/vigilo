import { useState, useEffect, useRef } from "react"
import { io } from "socket.io-client"
import ThreatFeed from "./components/ThreatFeed"
import StatusBanner from "./components/StatusBanner"
import NetworkStats from "./components/NetworkStats"
import "./App.css"
 
const API_URL = import.meta.env.VITE_API_URL || "http://localhost:5000"
 
export default function App() {
  const [threats, setThreats] = useState([])
  const [connected, setConnected] = useState(false)
  const [networkStatus, setNetworkStatus] = useState("safe")
  const socketRef = useRef(null)
 
  useEffect(() => {
    fetch(`${API_URL}/api/threats`)
      .then((r) => r.json())
      .then((data) => {
        if (data.threats.length > 0) {
          setThreats(data.threats)
          setNetworkStatus("threat")
        }
      })
      .catch(() => {})
 
    socketRef.current = io(API_URL, { transports: ["websocket"] })
 
    socketRef.current.on("connect", () => setConnected(true))
    socketRef.current.on("disconnect", () => setConnected(false))
    socketRef.current.on("threat_detected", (threat) => {
      setThreats((prev) => [threat, ...prev])
      setNetworkStatus("threat")
    })
    socketRef.current.on("threats_cleared", () => {
      setThreats([])
      setNetworkStatus("safe")
    })
 
    return () => socketRef.current.disconnect()
  }, [])
 
  const handleClear = async () => {
    await fetch(`${API_URL}/api/threats/clear`, { method: "POST" })
  }
 
  return (
    <div className="app">
      <header className="app-header">
        <div className="header-left">
          <div className="logo">
            <span className="logo-icon" />
            <span className="logo-text">Vigilo</span>
          </div>
          <span className="logo-tagline">Autonomous Network Protection</span>
        </div>
        <div className="header-right">
          <div className={`connection-pill ${connected ? "online" : "offline"}`}>
            <span className="pulse-dot" />
            {connected ? "Live monitoring" : "Connecting..."}
          </div>
        </div>
      </header>
 
      <main className="app-main">
        <StatusBanner status={networkStatus} threatCount={threats.length} />
        <NetworkStats threats={threats} />
        <ThreatFeed threats={threats} onClear={handleClear} />
      </main>
 
      <footer className="app-footer">
        <p>Vigilo v1.0 &mdash; All threats neutralised automatically</p>
      </footer>
    </div>
  )
}
 
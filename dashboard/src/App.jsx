import { useState, useEffect, useRef } from "react"
import { io } from "socket.io-client"
import RadarMap from "./components/RadarMap"
import NetworkStats from "./components/NetworkStats"
import ThreatFeed from "./components/ThreatFeed"
import "./App.css"
 
const API_URL = import.meta.env.VITE_API_URL || "http://localhost:5000"
 
export default function App() {
  const [threats, setThreats]           = useState([])
  const [connected, setConnected]       = useState(false)
  const [activeThreat, setActiveThreat] = useState(null)
  const [neutralised, setNeutralised]   = useState(false)
  const [flashClass, setFlashClass]     = useState("")
  const [uptime, setUptime]             = useState("00:00")
  const [clock, setClock]               = useState("")
  const [deviceData, setDeviceData]     = useState({
    devices: [], own_ip: "", gateway_ip: ""
  })
  const socketRef  = useRef(null)
  const uptimeRef  = useRef(0)
  const neutralRef = useRef(null)
 
  // ── Clock ──
  useEffect(() => {
    const tick = () => setClock(new Date().toUTCString().slice(17, 25) + " UTC")
    tick()
    const id = setInterval(tick, 1000)
    return () => clearInterval(id)
  }, [])
 
  // ── Uptime ──
  useEffect(() => {
    const id = setInterval(() => {
      uptimeRef.current++
      const m = String(Math.floor(uptimeRef.current / 60)).padStart(2, "0")
      const s = String(uptimeRef.current % 60).padStart(2, "0")
      setUptime(`${m}:${s}`)
    }, 1000)
    return () => clearInterval(id)
  }, [])
 
  // ── Socket.IO + initial data fetch ──
  useEffect(() => {
    // Load existing threats
    fetch(`${API_URL}/api/threats`)
      .then((r) => r.json())
      .then((data) => { if (data.threats?.length) setThreats(data.threats) })
      .catch(() => {})
 
    // Load existing device list
    fetch(`${API_URL}/api/devices`)
      .then((r) => r.json())
      .then((data) => { if (data.devices?.length) setDeviceData(data) })
      .catch(() => {})
 
    socketRef.current = io(API_URL, { transports: ["websocket"] })
 
    socketRef.current.on("connect",    () => setConnected(true))
    socketRef.current.on("disconnect", () => setConnected(false))
 
    // Real device list from network scanner
    socketRef.current.on("devices_updated", (data) => {
      setDeviceData(data)
    })
 
    // Threat detected
    socketRef.current.on("threat_detected", (threat) => {
      setThreats((prev) => [threat, ...prev])
      setActiveThreat(threat)
      triggerFlash("rgba(255,45,85,0.12)")
 
      if (neutralRef.current) clearTimeout(neutralRef.current)
      neutralRef.current = setTimeout(() => {
        setNeutralised(true)
        triggerFlash("rgba(0,221,180,0.08)")
        setTimeout(() => {
          setActiveThreat(null)
          setNeutralised(false)
        }, 2800)
      }, 3500)
    })
 
    socketRef.current.on("threats_cleared", () => {
      setThreats([])
      setActiveThreat(null)
      setNeutralised(false)
    })
 
    return () => {
      socketRef.current.disconnect()
      if (neutralRef.current) clearTimeout(neutralRef.current)
    }
  }, [])
 
  function triggerFlash(color) {
    setFlashClass("show")
    document.documentElement.style.setProperty("--flash-color", color)
    setTimeout(() => setFlashClass(""), 350)
  }
 
  const isThreat = !!activeThreat && !neutralised
 
  return (
    <>
      <div
        className={`threat-flash ${flashClass}`}
        style={{ background: "var(--flash-color, rgba(255,45,85,0.1))" }}
      />
 
      <div className="app">
        <header className="app-header">
          <div className="logo-wrap">
            <div className="logo-mark"/>
            <div>
              <div className="logo-name">VIGILO</div>
              <div className="logo-sub">Autonomous Network Protection System</div>
            </div>
          </div>
          <div className="header-right">
            <div className={`status-pill ${isThreat ? "threat" : "secure"}`}>
              <span className="pill-dot"/>
              <span>{isThreat ? "THREAT DETECTED" : "NETWORK SECURED"}</span>
            </div>
            <div className="app-clock">{clock}</div>
          </div>
        </header>
 
        <div className="app-main">
          <div className="radar-panel">
            <div className="radar-title">
              ◈ Live Network Topology — Sentinel Mode Active
            </div>
            <RadarMap
              threat={activeThreat}
              neutralised={neutralised}
              deviceData={deviceData}
            />
            <div style={{
              fontSize: "9px", letterSpacing: "2px", color: "var(--text-dim)",
              display: "flex", alignItems: "center", gap: "8px"
            }}>
              <span style={{
                width: "6px", height: "6px", borderRadius: "50%",
                background: connected ? "var(--cyan)" : "var(--red)",
                display: "inline-block"
              }}/>
              {connected
                ? `SENTINEL CONNECTED — ${deviceData.devices.length} DEVICE(S) ON NETWORK`
                : "CONNECTING TO SENTINEL..."}
            </div>
          </div>
 
          <div className="side-panel">
            <NetworkStats threats={threats} uptime={uptime}/>
            <ThreatFeed threats={threats} blinking={isThreat}/>
          </div>
        </div>
 
        <footer className="app-footer">
          <span>VIGILO v1.0 &nbsp;|&nbsp; UNIVERSITY OF LANCASHIRE HACKATHON MAY 2026</span>
          <div className="bar-right">
            <div className="bar-dot" style={{ background: isThreat ? "var(--red)" : "var(--cyan)" }}/>
            <span style={{ color: isThreat ? "var(--red)" : "" }}>
              {isThreat
                ? "⚠ HOSTILE DEVICE DETECTED — VIGILO RESPONDING"
                : "ALL SYSTEMS NOMINAL"}
            </span>
          </div>
        </footer>
      </div>
    </>
  )
}
 
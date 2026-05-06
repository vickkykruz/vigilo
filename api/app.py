"""
Vigilo — Flask API + Socket.IO
Receives threat events from the Python monitor,
pushes them to the React dashboard in real time via Socket.IO,
and fires an automatic plain-English email alert to the owner.
 
Run:
    python3 app.py
"""
 
import os
import logging
from datetime import datetime
from flask import Flask, request, jsonify
from flask_socketio import SocketIO
from flask_cors import CORS
from mailer import send_threat_email
 
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
log = logging.getLogger("vigilo.api")
 
app = Flask(__name__)
app.config["SECRET_KEY"] = os.environ.get("SECRET_KEY", "vigilo-dev-secret")
 
CORS(app, resources={r"/*": {"origins": "*"}})
socketio = SocketIO(app, cors_allowed_origins="*", async_mode="threading")
 
# In-memory threat log for the session
threat_log: list[dict] = []
 
 
# ── Routes ─────────────────────────────────────────────────────────────────────
 
@app.route("/api/health", methods=["GET"])
def health():
    """Simple health check — confirms the API is running."""
    return jsonify({"status": "ok", "service": "vigilo-api"})
 
 
@app.route("/api/threat", methods=["POST"])
def receive_threat():
    """
    Receives a threat event from the Python monitor.
    Stores it, pushes it to all connected dashboard clients
    via Socket.IO, and fires the email alert.
    """
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "No JSON payload"}), 400
 
    required = {"attacker_mac", "attacker_ip", "spoofed_ip", "timestamp"}
    if not required.issubset(data.keys()):
        return jsonify({"error": "Missing required fields"}), 400
 
    # Build the threat record
    threat = {
        "id": len(threat_log) + 1,
        "attacker_mac": data["attacker_mac"],
        "attacker_ip": data["attacker_ip"],
        "spoofed_ip": data["spoofed_ip"],
        "interface": data.get("interface", "unknown"),
        "action": data.get("action", "corrective_arp_broadcast"),
        "status": data.get("status", "neutralised"),
        "timestamp": data.get("timestamp", datetime.utcnow().isoformat()),
        "received_at": datetime.utcnow().isoformat()
    }
 
    threat_log.append(threat)
    log.info(f"Threat received — attacker: {threat['attacker_mac']}")
 
    # Push to all connected dashboard clients immediately
    socketio.emit("threat_detected", threat)
    log.info("Threat pushed to dashboard via Socket.IO")
 
    # Fire the email alert
    owner_email = os.environ.get("OWNER_EMAIL", "owner@yourhostel.com")
    try:
        send_threat_email(owner_email, threat)
        log.info(f"Email alert sent to {owner_email}")
    except Exception as e:
        log.warning(f"Email failed: {e}")
 
    return jsonify({"status": "received", "threat_id": threat["id"]}), 200
 
 
@app.route("/api/threats", methods=["GET"])
def get_threats():
    """Returns all threats logged in this session — used by dashboard on load."""
    return jsonify({"threats": threat_log, "count": len(threat_log)})
 
 
@app.route("/api/threats/clear", methods=["POST"])
def clear_threats():
    """Clears the threat log — useful for demo resets."""
    threat_log.clear()
    socketio.emit("threats_cleared", {})
    log.info("Threat log cleared")
    return jsonify({"status": "cleared"})
 
 
# ── Socket.IO events ───────────────────────────────────────────────────────────
 
@socketio.on("connect")
def on_connect():
    log.info(f"Dashboard client connected: {request.sid}")
 
 
@socketio.on("disconnect")
def on_disconnect():
    log.info(f"Dashboard client disconnected: {request.sid}")
 
 
# ── Entry point ────────────────────────────────────────────────────────────────
 
if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    log.info(f"Vigilo API starting on port {port}")
    socketio.run(app, host="0.0.0.0", port=port, debug=False)
 
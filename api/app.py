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
from flask import Flask, request, jsonify, send_from_directory
from flask_socketio import SocketIO
from flask_cors import CORS
from mailer import send_threat_email
 
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
log = logging.getLogger("vigilo.api")
 
# ── Dashboard path ─────────────────────────────────────────────────────────────
_API_DIR       = os.path.dirname(os.path.abspath(__file__))
_PROJECT_ROOT  = os.path.dirname(_API_DIR)
DASHBOARD_DIST = os.path.join(_PROJECT_ROOT, "dashboard", "dist")
 
log.info(f"Dashboard dist path   : {DASHBOARD_DIST}")
log.info(f"Dashboard dist exists : {os.path.exists(DASHBOARD_DIST)}")
 
# ── Flask app ──────────────────────────────────────────────────────────────────
app = Flask(__name__)
app.config["SECRET_KEY"] = os.environ.get("SECRET_KEY", "vigilo-dev-secret")
 
CORS(app, resources={r"/api/*": {"origins": "*"}})
socketio = SocketIO(app, cors_allowed_origins="*", async_mode="threading")
 
# In-memory threat log for the session
threat_log: list[dict] = []
 
 
# ── API routes ─────────────────────────────────────────────────────────────────
 
@app.route("/api/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "service": "vigilo-api"})
 
 
@app.route("/api/threat", methods=["POST"])
def receive_threat():
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "No JSON payload"}), 400
 
    required = {"attacker_mac", "attacker_ip", "spoofed_ip", "timestamp"}
    if not required.issubset(data.keys()):
        return jsonify({"error": "Missing required fields"}), 400
 
    threat = {
        "id": len(threat_log) + 1,
        "attacker_mac": data["attacker_mac"],
        "attacker_ip":  data["attacker_ip"],
        "spoofed_ip":   data["spoofed_ip"],
        "interface":    data.get("interface", "unknown"),
        "action":       data.get("action", "corrective_arp_broadcast"),
        "status":       data.get("status", "neutralised"),
        "timestamp":    data.get("timestamp", datetime.utcnow().isoformat()),
        "received_at":  datetime.utcnow().isoformat()
    }
 
    threat_log.append(threat)
    log.info(f"Threat received — attacker: {threat['attacker_mac']}")
 
    socketio.emit("threat_detected", threat)
    log.info("Threat pushed to dashboard via Socket.IO")
 
    owner_email = os.environ.get("OWNER_EMAIL", "")
    try:
        send_threat_email(owner_email, threat)
        log.info(f"Email alert sent to {owner_email}")
    except Exception as e:
        log.warning(f"Email failed: {e}")
 
    return jsonify({"status": "received", "threat_id": threat["id"]}), 200
 
 
@app.route("/api/threats", methods=["GET"])
def get_threats():
    return jsonify({"threats": threat_log, "count": len(threat_log)})
 
 
@app.route("/api/threats/clear", methods=["POST"])
def clear_threats():
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
 
 
# ── React dashboard catch-all ──────────────────────────────────────────────────
# IMPORTANT: Must be defined BEFORE the entry point block.
# socketio.run() blocks execution — anything after it never runs.
 
@app.route("/", defaults={"path": ""})
@app.route("/<path:path>")
def serve_dashboard(path):
    # API and Socket.IO routes are handled above — return 404 if somehow reached
    if path.startswith("api/") or path.startswith("socket.io"):
        return jsonify({"error": "Not found"}), 404
 
    # Dashboard dist folder missing — build has not been run
    if not os.path.exists(DASHBOARD_DIST):
        log.error(f"Dashboard dist not found at: {DASHBOARD_DIST}")
        return jsonify({
            "error": "Dashboard not built",
            "fix": "Run: npm run build inside the dashboard folder"
        }), 503
 
    # Serve static asset if the file exists (JS, CSS, images, fonts)
    if path:
        target = os.path.join(DASHBOARD_DIST, path)
        if os.path.isfile(target):
            return send_from_directory(DASHBOARD_DIST, path)
 
    # Everything else serves index.html — React Router handles client routing
    return send_from_directory(DASHBOARD_DIST, "index.html")
 
 
# ── Entry point ────────────────────────────────────────────────────────────────
 
if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    log.info(f"Vigilo API starting on port {port}")
    socketio.run(
        app,
        host="0.0.0.0",
        port=port,
        debug=False,
        allow_unsafe_werkzeug=True
    )
 
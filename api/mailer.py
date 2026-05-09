"""
Vigilo — Email Alert Module
Sends a plain-English threat notification to the business owner.
 
The sending credentials are managed by Vigilo internally.
The owner only needs to provide their email address to receive alerts.
"""
 
import smtplib
import logging
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from datetime import datetime
 
log = logging.getLogger("vigilo.mailer")
 
# ── Vigilo sending account ────────────────────────────────────
# These are Vigilo's own SMTP credentials for dispatching alerts.
# The owner never needs to configure these.
_SMTP_HOST   = "mail.privateemail.com"
_SMTP_PORT   = 587
_SMTP_USER   = "alerts@yourvigilo.com"
_SMTP_PASS   = "YOUR_PASSWORD_HERE"
_SENDER_NAME = "Vigilo Security"
 
 
def format_timestamp(iso_str: str) -> str:
    """Convert ISO timestamp to human-readable format."""
    try:
        dt = datetime.fromisoformat(iso_str)
        return dt.strftime("%d %B %Y at %H:%M:%S UTC")
    except Exception:
        return iso_str
 
 
def build_email_body(threat: dict) -> str:
    """
    Builds a plain-English HTML email the business owner
    can understand without any technical background.
    """
    timestamp    = format_timestamp(threat.get("timestamp", ""))
    attacker_mac = threat.get("attacker_mac", "Unknown")
    attacker_ip  = threat.get("attacker_ip",  "Unknown")
    spoofed_ip   = threat.get("spoofed_ip",   "Unknown")
 
    return f"""
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body {{ font-family: Arial, sans-serif; background: #f4f4f4; margin: 0; padding: 0; }}
    .container {{ max-width: 600px; margin: 30px auto; background: #ffffff; border-radius: 8px; overflow: hidden; }}
    .header {{ background: #0d0f1a; padding: 28px 32px; }}
    .header h1 {{ color: #00ddb4; margin: 0; font-size: 22px; letter-spacing: 3px; font-family: monospace; }}
    .header p {{ color: #4a7a70; margin: 6px 0 0; font-size: 13px; }}
    .alert-banner {{ background: #fff3cd; border-left: 4px solid #e8a000; padding: 16px 32px; }}
    .alert-banner p {{ margin: 0; color: #5a4000; font-size: 15px; }}
    .content {{ padding: 28px 32px; }}
    .content p {{ color: #333333; font-size: 15px; line-height: 1.7; margin-bottom: 14px; }}
    .detail-box {{ background: #f8f9fa; border-radius: 6px; padding: 16px 20px; margin: 20px 0; border: 1px solid #e9ecef; }}
    .detail-box table {{ width: 100%; border-collapse: collapse; }}
    .detail-box td {{ padding: 7px 0; font-size: 14px; color: #444444; vertical-align: top; }}
    .detail-box td:first-child {{ font-weight: bold; color: #111111; width: 160px; }}
    .status-ok {{ background: #d4edda; border-left: 4px solid #28a745; padding: 16px 32px; }}
    .status-ok p {{ margin: 0; color: #155724; font-size: 15px; font-weight: bold; }}
    .footer {{ padding: 20px 32px; background: #f8f9fa; text-align: center; border-top: 1px solid #e9ecef; }}
    .footer p {{ margin: 0; font-size: 12px; color: #999999; }}
  </style>
</head>
<body>
  <div class="container">
 
    <div class="header">
      <h1>VIGILO</h1>
      <p>Autonomous Network Protection — Security Alert</p>
    </div>
 
    <div class="alert-banner">
      <p><strong>⚠ A suspicious device was detected on your Wi-Fi network.</strong></p>
    </div>
 
    <div class="content">
      <p>Hello,</p>
      <p>
        Vigilo detected an unauthorised device on your network attempting to
        intercept your internet traffic. This type of attack is used by
        intruders to steal login credentials for your business platforms
        such as booking.com, your email, or your admin systems.
      </p>
      <p>
        <strong>Vigilo automatically removed this device from your network.</strong>
        You did not need to do anything. Your systems remain protected.
      </p>
 
      <div class="detail-box">
        <table>
          <tr><td>Time detected</td><td>{timestamp}</td></tr>
          <tr><td>Attacker IP</td><td>{attacker_ip}</td></tr>
          <tr><td>Attacker device ID</td><td>{attacker_mac}</td></tr>
          <tr><td>Targeted IP</td><td>{spoofed_ip}</td></tr>
          <tr><td>Action taken</td><td>Device automatically removed from network</td></tr>
        </table>
      </div>
 
      <p>
        As a precaution, we recommend reviewing any active sessions on your
        booking platforms and changing your passwords if you notice anything
        unusual. If alerts continue, consider separating your admin Wi-Fi
        from your guest Wi-Fi.
      </p>
    </div>
 
    <div class="status-ok">
      <p>✓ Your network is currently safe. Vigilo continues to monitor.</p>
    </div>
 
    <div class="footer">
      <p>Vigilo — Autonomous Network Protection &nbsp;|&nbsp; This is an automated security alert</p>
      <p style="margin-top:6px">You are receiving this because your email was registered with Vigilo.</p>
    </div>
 
  </div>
</body>
</html>
"""
 
 
def send_threat_email(to_address: str, threat: dict) -> None:
    """
    Sends the threat alert email to the business owner.
    Uses Vigilo's own sending account — no owner configuration needed.
    """
    if not to_address:
        log.warning("No owner email configured — skipping alert")
        return
 
    msg = MIMEMultipart("alternative")
    msg["Subject"] = "⚠ Vigilo Alert — Suspicious device detected on your network"
    msg["From"]    = f"{_SENDER_NAME} <{_SMTP_USER}>"
    msg["To"]      = to_address
 
    html_body = build_email_body(threat)
    msg.attach(MIMEText(html_body, "html"))
 
    try:
        with smtplib.SMTP(_SMTP_HOST, _SMTP_PORT) as server:
            server.ehlo()
            server.starttls()
            server.login(_SMTP_USER, _SMTP_PASS)
            server.sendmail(_SMTP_USER, to_address, msg.as_string())
        log.info(f"Threat alert delivered to {to_address}")
    except smtplib.SMTPAuthenticationError:
        log.error("SMTP authentication failed — check Vigilo sending credentials")
    except smtplib.SMTPException as e:
        log.error(f"SMTP error: {e}")
    except Exception as e:
        log.error(f"Email delivery failed: {e}")
 
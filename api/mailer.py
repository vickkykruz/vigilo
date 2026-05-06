"""
Vigilo — Email Alert Module
Sends a plain-English threat notification to the hostel owner.
No technical jargon. John needs to understand it immediately.
 
Configure via environment variables:
    SMTP_HOST     — SMTP server (default: smtp.gmail.com)
    SMTP_PORT     — SMTP port (default: 587)
    SMTP_USER     — sender email address
    SMTP_PASSWORD — sender email password or app password
"""
 
import os
import smtplib
import logging
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from datetime import datetime
 
log = logging.getLogger("vigilo.mailer")
 
 
def format_timestamp(iso_str: str) -> str:
    """Convert ISO timestamp to human-readable format."""
    try:
        dt = datetime.fromisoformat(iso_str)
        return dt.strftime("%d %B %Y at %H:%M:%S UTC")
    except Exception:
        return iso_str
 
 
def build_email_body(threat: dict) -> str:
    """
    Builds a plain-English HTML email the hostel owner
    can understand without any technical background.
    """
    timestamp = format_timestamp(threat.get("timestamp", ""))
    attacker_mac = threat.get("attacker_mac", "Unknown")
    attacker_ip = threat.get("attacker_ip", "Unknown")
    spoofed_ip = threat.get("spoofed_ip", "Unknown")
 
    return f"""
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body {{ font-family: Arial, sans-serif; background: #f4f4f4; margin: 0; padding: 0; }}
    .container {{ max-width: 600px; margin: 30px auto; background: #ffffff; border-radius: 8px; overflow: hidden; }}
    .header {{ background: #1a1a2e; padding: 28px 32px; }}
    .header h1 {{ color: #ffffff; margin: 0; font-size: 22px; }}
    .header p {{ color: #aaaacc; margin: 6px 0 0; font-size: 14px; }}
    .alert-banner {{ background: #fff3cd; border-left: 4px solid #e8a000; padding: 16px 32px; }}
    .alert-banner p {{ margin: 0; color: #5a4000; font-size: 15px; }}
    .content {{ padding: 28px 32px; }}
    .content p {{ color: #333333; font-size: 15px; line-height: 1.7; }}
    .detail-box {{ background: #f8f9fa; border-radius: 6px; padding: 16px 20px; margin: 20px 0; }}
    .detail-box table {{ width: 100%; border-collapse: collapse; }}
    .detail-box td {{ padding: 6px 0; font-size: 14px; color: #444444; }}
    .detail-box td:first-child {{ font-weight: bold; color: #111111; width: 160px; }}
    .status-ok {{ background: #d4edda; border-left: 4px solid #28a745; padding: 16px 32px; }}
    .status-ok p {{ margin: 0; color: #155724; font-size: 15px; }}
    .footer {{ padding: 20px 32px; background: #f8f9fa; text-align: center; }}
    .footer p {{ margin: 0; font-size: 12px; color: #999999; }}
  </style>
</head>
<body>
  <div class="container">
 
    <div class="header">
      <h1>Vigilo Security Alert</h1>
      <p>Automated network protection for your business</p>
    </div>
 
    <div class="alert-banner">
      <p><strong>A suspicious device was detected on your Wi-Fi network.</strong></p>
    </div>
 
    <div class="content">
      <p>Hello,</p>
      <p>
        Vigilo detected an unauthorised device on your network attempting to
        intercept your internet traffic. This type of attack — known as ARP
        spoofing — is used by attackers to steal login credentials and
        monitor activity on your platforms such as booking.com.
      </p>
      <p>
        <strong>Vigilo automatically removed this device from your network.</strong>
        You did not need to do anything. Your systems remain safe.
      </p>
 
      <div class="detail-box">
        <table>
          <tr><td>Time detected</td><td>{timestamp}</td></tr>
          <tr><td>Attacker device IP</td><td>{attacker_ip}</td></tr>
          <tr><td>Attacker device ID</td><td>{attacker_mac}</td></tr>
          <tr><td>Target IP address</td><td>{spoofed_ip}</td></tr>
          <tr><td>Action taken</td><td>Device automatically removed</td></tr>
        </table>
      </div>
 
      <p>
        We recommend reviewing any active sessions on your booking platforms
        and changing your passwords as a precaution. If you continue to see
        alerts, consider contacting your IT provider to review your network setup.
      </p>
    </div>
 
    <div class="status-ok">
      <p>Your network is currently safe. Vigilo continues to monitor.</p>
    </div>
 
    <div class="footer">
      <p>Vigilo — Autonomous Network Protection &nbsp;|&nbsp; This is an automated alert</p>
    </div>
 
  </div>
</body>
</html>
"""
 
 
def send_threat_email(to_address: str, threat: dict) -> None:
    """
    Sends the threat alert email to the hostel owner.
    Reads SMTP credentials from environment variables.
    """
    smtp_host = os.environ.get("SMTP_HOST", "smtp.gmail.com")
    smtp_port = int(os.environ.get("SMTP_PORT", 587))
    smtp_user = os.environ.get("SMTP_USER", "")
    smtp_password = os.environ.get("SMTP_PASSWORD", "")
 
    if not smtp_user or not smtp_password:
        log.warning("SMTP credentials not configured — skipping email")
        return
 
    msg = MIMEMultipart("alternative")
    msg["Subject"] = "Vigilo Alert — Suspicious device detected on your network"
    msg["From"] = f"Vigilo Security <{smtp_user}>"
    msg["To"] = to_address
 
    html_body = build_email_body(threat)
    msg.attach(MIMEText(html_body, "html"))
 
    with smtplib.SMTP(smtp_host, smtp_port) as server:
        server.ehlo()
        server.starttls()
        server.login(smtp_user, smtp_password)
        server.sendmail(smtp_user, to_address, msg.as_string())
 
    log.info(f"Threat email delivered to {to_address}")
 
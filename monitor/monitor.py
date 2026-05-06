"""
Vigilo — Network Threat Monitor
Detects ARP spoofing on the local network, automatically sends
corrective ARP to restore legitimate mappings, and reports the
threat to the Flask API in real time.
 
Run as root on Ubuntu:
    sudo python3 monitor.py --interface eth0 --gateway 192.168.1.1 --api http://localhost:5000
"""
 
import time
import requests
import argparse
import logging
from datetime import datetime
from scapy.all import (
    ARP, Ether, srp, sendp, sniff, get_if_hwaddr, conf
)
 
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
log = logging.getLogger("vigilo")
 
# ── ARP table ─────────────────────────────────────────────────────────────────
# Tracks the legitimate IP → MAC mapping we have verified ourselves.
arp_table: dict[str, str] = {}
 
# Track which attackers we have already reported to avoid spam
reported: set[str] = set()
 
 
# ── Helpers ───────────────────────────────────────────────────────────────────
 
def get_mac(ip: str, interface: str) -> str | None:
    """Send an ARP request to resolve an IP to its real MAC address."""
    ans, _ = srp(
        Ether(dst="ff:ff:ff:ff:ff:ff") / ARP(pdst=ip),
        timeout=2,
        iface=interface,
        verbose=False
    )
    if ans:
        return ans[0][1].hwsrc
    return None
 
 
def send_corrective_arp(target_ip: str, real_mac: str, interface: str) -> None:
    """
    Broadcast a corrective gratuitous ARP reply to restore the
    legitimate IP → MAC mapping across all devices on the network.
    This undoes what the attacker's ARP poison put in place.
    """
    packet = (
        Ether(dst="ff:ff:ff:ff:ff:ff") /
        ARP(
            op=2,
            pdst="255.255.255.255",
            hwdst="ff:ff:ff:ff:ff:ff",
            psrc=target_ip,
            hwsrc=real_mac
        )
    )
    # Send 5 times to ensure it propagates
    sendp(packet, iface=interface, count=5, inter=0.2, verbose=False)
    log.info(f"Corrective ARP broadcast: {target_ip} is at {real_mac}")
 
 
def report_threat(api_url: str, attacker_mac: str, attacker_ip: str,
                  spoofed_ip: str, interface: str) -> None:
    """POST the threat event to the Vigilo Flask API."""
    payload = {
        "attacker_mac": attacker_mac,
        "attacker_ip": attacker_ip,
        "spoofed_ip": spoofed_ip,
        "interface": interface,
        "timestamp": datetime.utcnow().isoformat(),
        "action": "corrective_arp_broadcast",
        "status": "neutralised"
    }
    try:
        response = requests.post(
            f"{api_url}/api/threat",
            json=payload,
            timeout=5
        )
        if response.status_code == 200:
            log.info(f"Threat reported to API — attacker: {attacker_mac}")
        else:
            log.warning(f"API returned {response.status_code}")
    except requests.exceptions.ConnectionError:
        log.warning("Flask API unreachable — threat logged locally only")
 
 
# ── Core detection ─────────────────────────────────────────────────────────────
 
def handle_packet(packet, interface: str, gateway_ip: str, api_url: str) -> None:
    """
    Called for every ARP packet sniffed on the network.
    Checks whether the packet contradicts the known ARP table.
    """
    if not packet.haslayer(ARP):
        return
 
    arp = packet[ARP]
 
    # We only care about ARP replies (op=2) — these are the ones
    # an attacker uses to poison the ARP cache of other devices.
    if arp.op != 2:
        return
 
    sender_ip = arp.psrc
    sender_mac = arp.hwsrc
 
    # Skip our own interface MAC to avoid false positives
    try:
        own_mac = get_if_hwaddr(interface)
        if sender_mac == own_mac:
            return
    except Exception:
        pass
 
    # First time we see this IP — record it as legitimate
    if sender_ip not in arp_table:
        arp_table[sender_ip] = sender_mac
        log.debug(f"ARP table updated: {sender_ip} → {sender_mac}")
        return
 
    # We have seen this IP before — check if MAC matches
    known_mac = arp_table[sender_ip]
    if sender_mac == known_mac:
        return  # Legitimate, nothing to do
 
    # MAC mismatch — this is ARP spoofing
    log.warning(
        f"ARP SPOOF DETECTED — {sender_ip} "
        f"claimed by {sender_mac} (known: {known_mac})"
    )
 
    # Avoid duplicate reports for the same attacker MAC
    if sender_mac in reported:
        return
    reported.add(sender_mac)
 
    # Resolve the real MAC for the spoofed IP
    real_mac = get_mac(sender_ip, interface) or known_mac
 
    # Neutralise: broadcast the correct ARP mapping
    send_corrective_arp(sender_ip, real_mac, interface)
 
    # Report to Flask API
    report_threat(
        api_url=api_url,
        attacker_mac=sender_mac,
        attacker_ip=arp.psrc,
        spoofed_ip=sender_ip,
        interface=interface
    )
 
 
# ── Entry point ────────────────────────────────────────────────────────────────
 
def main():
    parser = argparse.ArgumentParser(description="Vigilo ARP spoof monitor")
    parser.add_argument("--interface", default="eth0", help="Network interface to monitor")
    parser.add_argument("--gateway", required=True, help="Gateway IP address (e.g. 192.168.1.1)")
    parser.add_argument("--api", default="http://localhost:5000", help="Vigilo Flask API URL")
    args = parser.parse_args()
 
    conf.verb = 0  # Suppress Scapy output
 
    log.info(f"Vigilo monitor starting on {args.interface}")
    log.info(f"Gateway: {args.gateway}")
    log.info(f"API: {args.api}")
 
    # Seed the ARP table with the real gateway MAC before monitoring begins
    log.info("Resolving gateway MAC address...")
    gateway_mac = get_mac(args.gateway, args.interface)
    if gateway_mac:
        arp_table[args.gateway] = gateway_mac
        log.info(f"Gateway verified: {args.gateway} → {gateway_mac}")
    else:
        log.warning("Could not resolve gateway MAC — proceeding without seed")
 
    log.info("Monitoring for ARP spoofing... (Ctrl+C to stop)")
 
    sniff(
        iface=args.interface,
        filter="arp",
        prn=lambda pkt: handle_packet(pkt, args.interface, args.gateway, args.api),
        store=False
    )
 
 
if __name__ == "__main__":
    main()
 
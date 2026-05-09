"""
Vigilo — Network Threat Monitor
Detects ARP spoofing on the local network, automatically sends
corrective ARP to restore legitimate mappings, and reports the
threat to the Flask API in real time.
 
Also performs periodic network scans to discover real devices
and reports them to the dashboard for live radar display.
 
Run as root:
    sudo python3 monitor.py --interface eth0 --gateway 192.168.1.1 --api http://localhost:5000
"""
 
import time
import ipaddress
import threading
import requests
import argparse
import logging
from datetime import datetime
from scapy.all import (
    ARP, Ether, srp, sendp, sniff,
    get_if_hwaddr, get_if_addr, conf
)
 
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
log = logging.getLogger("vigilo")
 
# ── ARP table ──────────────────────────────────────────────────────────────────
arp_table: dict[str, str] = {}
reported: set[str] = set()
 
 
# ── Network helpers ────────────────────────────────────────────────────────────
 
def get_mac(ip: str, interface: str) -> str | None:
    """ARP request to resolve an IP to its real MAC address."""
    ans, _ = srp(
        Ether(dst="ff:ff:ff:ff:ff:ff") / ARP(pdst=ip),
        timeout=2, iface=interface, verbose=False
    )
    return ans[0][1].hwsrc if ans else None
 
 
def get_subnet(interface: str) -> str:
    """
    Derive the subnet CIDR from the interface.
    Uses socket/fcntl (always available) instead of Scapy's
    get_if_netmask which was removed in recent Scapy versions.
    Falls back to /24 if detection fails.
    """
    import socket
    import struct
 
    try:
        import fcntl
        # SIOCGIFNETMASK — ioctl call to get interface netmask
        SIOCGIFNETMASK = 0x891b
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        netmask = socket.inet_ntoa(
            fcntl.ioctl(
                s.fileno(),
                SIOCGIFNETMASK,
                struct.pack("256s", interface[:15].encode())
            )[20:24]
        )
        s.close()
    except Exception:
        # Fallback to /24 — works for most home/office networks
        log.warning("Could not detect netmask — defaulting to /24")
        netmask = "255.255.255.0"
 
    ip      = get_if_addr(interface)
    network = ipaddress.IPv4Network(f"{ip}/{netmask}", strict=False)
    return str(network)
 
 
def get_own_ip(interface: str) -> str:
    """Return this machine's IP on the given interface."""
    return get_if_addr(interface)
 
 
def scan_network(subnet: str, interface: str) -> list[dict]:
    """
    ARP scan the entire subnet and return a list of
    discovered devices with their IP and MAC addresses.
    """
    log.info(f"Scanning subnet {subnet}...")
    ans, _ = srp(
        Ether(dst="ff:ff:ff:ff:ff:ff") / ARP(pdst=subnet),
        timeout=5, iface=interface, verbose=False
    )
    devices = [
        {"ip": received.psrc, "mac": received.hwsrc}
        for _, received in ans
    ]
    log.info(f"Scan complete — {len(devices)} device(s) found")
    return devices
 
 
# ── API reporting ──────────────────────────────────────────────────────────────
 
def report_devices(api_url: str, devices: list[dict],
                   own_ip: str, gateway_ip: str) -> None:
    """POST discovered device list to the Flask API."""
    payload = {
        "devices":    devices,
        "own_ip":     own_ip,
        "gateway_ip": gateway_ip,
        "timestamp":  datetime.utcnow().isoformat()
    }
    try:
        requests.post(
            f"{api_url}/api/devices",
            json=payload, timeout=5
        )
        log.info(f"Device list reported — {len(devices)} device(s)")
    except requests.exceptions.ConnectionError:
        log.warning("API unreachable — device list not reported")
    except Exception as e:
        log.warning(f"Device report error: {e}")
 
 
def report_threat(api_url: str, attacker_mac: str, attacker_ip: str,
                  spoofed_ip: str, interface: str) -> None:
    """POST a threat event to the Flask API."""
    payload = {
        "attacker_mac": attacker_mac,
        "attacker_ip":  attacker_ip,
        "spoofed_ip":   spoofed_ip,
        "interface":    interface,
        "timestamp":    datetime.utcnow().isoformat(),
        "action":       "corrective_arp_broadcast",
        "status":       "neutralised"
    }
    try:
        response = requests.post(
            f"{api_url}/api/threat",
            json=payload, timeout=5
        )
        if response.status_code == 200:
            log.info(f"Threat reported — attacker: {attacker_mac}")
        else:
            log.warning(f"API returned {response.status_code}")
    except requests.exceptions.ConnectionError:
        log.warning("API unreachable — threat logged locally only")
 
 
def send_corrective_arp(target_ip: str, real_mac: str,
                        interface: str) -> None:
    """Broadcast a corrective ARP to restore legitimate mappings."""
    packet = (
        Ether(dst="ff:ff:ff:ff:ff:ff") /
        ARP(
            op=2, pdst="255.255.255.255",
            hwdst="ff:ff:ff:ff:ff:ff",
            psrc=target_ip, hwsrc=real_mac
        )
    )
    sendp(packet, iface=interface, count=5, inter=0.2, verbose=False)
    log.info(f"Corrective ARP sent: {target_ip} is at {real_mac}")
 
 
# ── Periodic device scanner ────────────────────────────────────────────────────
 
def device_scan_loop(interface: str, gateway_ip: str,
                     api_url: str, interval: int = 30) -> None:
    """
    Background thread — scans the network every `interval` seconds
    and reports real devices to the dashboard.
    """
    own_ip = get_own_ip(interface)
    log.info(f"Device scanner started — scanning every {interval}s")
 
    while True:
        try:
            subnet  = get_subnet(interface)
            devices = scan_network(subnet, interface)
            report_devices(api_url, devices, own_ip, gateway_ip)
 
            # Also seed ARP table with discovered devices
            for device in devices:
                if device["ip"] not in arp_table:
                    arp_table[device["ip"]] = device["mac"]
 
        except Exception as e:
            log.warning(f"Device scan error: {e}")
 
        time.sleep(interval)
 
 
# ── ARP packet handler ─────────────────────────────────────────────────────────
 
def handle_packet(packet, interface: str, gateway_ip: str,
                  api_url: str) -> None:
    """Inspect each ARP packet for spoofing."""
    if not packet.haslayer(ARP):
        return
 
    arp = packet[ARP]
    if arp.op != 2:  # Only ARP replies
        return
 
    sender_ip  = arp.psrc
    sender_mac = arp.hwsrc
 
    # Skip own interface
    try:
        if sender_mac == get_if_hwaddr(interface):
            return
    except Exception:
        pass
 
    # First time seeing this IP — record as legitimate
    if sender_ip not in arp_table:
        arp_table[sender_ip] = sender_mac
        log.debug(f"ARP table: {sender_ip} → {sender_mac}")
        return
 
    # Check for MAC mismatch
    known_mac = arp_table[sender_ip]
    if sender_mac == known_mac:
        return
 
    # ARP spoof detected
    log.warning(
        f"ARP SPOOF DETECTED — {sender_ip} "
        f"claimed by {sender_mac} (known: {known_mac})"
    )
 
    if sender_mac in reported:
        return
    reported.add(sender_mac)
 
    real_mac = get_mac(sender_ip, interface) or known_mac
    send_corrective_arp(sender_ip, real_mac, interface)
    report_threat(
        api_url=api_url,
        attacker_mac=sender_mac,
        attacker_ip=arp.psrc,
        spoofed_ip=sender_ip,
        interface=interface
    )
 
 
# ── Entry point ────────────────────────────────────────────────────────────────
 
def main():
    parser = argparse.ArgumentParser(description="Vigilo Network Monitor")
    parser.add_argument("--interface", default="eth0")
    parser.add_argument("--gateway",   required=True)
    parser.add_argument("--api",       default="http://localhost:5000")
    parser.add_argument("--scan-interval", type=int, default=30,
                        help="Seconds between network scans (default: 30)")
    args = parser.parse_args()
 
    conf.verb = 0
 
    log.info(f"Vigilo monitor starting on {args.interface}")
    log.info(f"Gateway : {args.gateway}")
    log.info(f"API     : {args.api}")
 
    # Resolve and seed gateway MAC
    log.info("Resolving gateway MAC address...")
    gateway_mac = get_mac(args.gateway, args.interface)
    if gateway_mac:
        arp_table[args.gateway] = gateway_mac
        log.info(f"Gateway verified: {args.gateway} → {gateway_mac}")
    else:
        log.warning("Could not resolve gateway MAC — proceeding without seed")
 
    # Start background device scanner thread
    scanner = threading.Thread(
        target=device_scan_loop,
        args=(args.interface, args.gateway, args.api, args.scan_interval),
        daemon=True
    )
    scanner.start()
 
    log.info("Monitoring for ARP spoofing... (Ctrl+C to stop)")
 
    sniff(
        iface=args.interface,
        filter="arp",
        prn=lambda pkt: handle_packet(
            pkt, args.interface, args.gateway, args.api
        ),
        store=False
    )
 
 
if __name__ == "__main__":
    main()
 